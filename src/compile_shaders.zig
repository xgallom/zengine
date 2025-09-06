const std = @import("std");
const fatal = std.process.fatal;

const zengine = @import("zengine");
const allocators = zengine.allocators;
const c = zengine.ext.c;

const log = std.log.scoped(.compile_shaders);

pub const std_options: std.Options = .{
    .log_level = .info,
};

const usage =
    \\Usage: ./shader_compile [options]
    \\
    \\Options:
    \\  --input-dir INPUT_DIRECTORY
    \\  --output-dir OUTPUT_DIRECTORY
    \\  --install-dir INSTALL_DIRECTORY
    \\  --include-dir INCLUDE_DIRECTORY
    \\
;

const Arguments = struct {
    input_directory: []const u8,
    output_directory: []const u8,
    install_directory: ?[]const u8,
    include_directory: ?[:0]const u8,
};

const FileFormat = enum {
    spirv,
    dxil,
    metal,
    hlsl,
    json,

    fn extension(comptime format: FileFormat) []const u8 {
        return switch (format) {
            .spirv => ".spv",
            .dxil => ".dxil",
            .metal => ".msl",
            .hlsl => ".hlsl",
            .json => ".json",
        };
    }
};

const ShaderStage = enum(c.SDL_ShaderCross_ShaderStage) {
    vertex = c.SDL_SHADERCROSS_SHADERSTAGE_VERTEX,
    fragment = c.SDL_SHADERCROSS_SHADERSTAGE_FRAGMENT,
    compute = c.SDL_SHADERCROSS_SHADERSTAGE_COMPUTE,

    fn extension(comptime stage: ShaderStage) []const u8 {
        return switch (stage) {
            .vertex => ".vert",
            .fragment => ".frag",
            .compute => ".comp",
        };
    }

    fn fromFileName(filename: []const u8) ShaderStage {
        const shader_stage_ext = std.fs.path.extension(filename);
        if (std.mem.eql(u8, ".vert", shader_stage_ext)) {
            return .vertex;
        } else if (std.mem.eql(u8, ".frag", shader_stage_ext)) {
            return .fragment;
        } else if (std.mem.eql(u8, ".comp", shader_stage_ext)) {
            return .compute;
        } else {
            fatal("shader {s} missing stage extension", .{filename});
        }
    }
};

const ComputeMetadata = c.SDL_ShaderCross_ComputePipelineMetadata;
const ComputeMetadataJSON = struct {
    num_samplers: u32,
    num_readonly_storage_textures: u32,
    num_readonly_storage_buffers: u32,
    num_readwrite_storage_textures: u32,
    num_readwrite_storage_buffers: u32,
    num_uniform_buffers: u32,
    threadcount_x: u32,
    threadcount_y: u32,
    threadcount_z: u32,

    fn fromMetadata(info: *const ComputeMetadata) ComputeMetadataJSON {
        return .{
            .num_samplers = info.num_samplers,
            .num_readonly_storage_textures = info.num_readonly_storage_textures,
            .num_readonly_storage_buffers = info.num_readonly_storage_buffers,
            .num_readwrite_storage_textures = info.num_readwrite_storage_textures,
            .num_readwrite_storage_buffers = info.num_readwrite_storage_buffers,
            .num_uniform_buffers = info.num_uniform_buffers,
            .threadcount_x = info.threadcount_x,
            .threadcount_y = info.threadcount_y,
            .threadcount_z = info.threadcount_z,
        };
    }
};

const GraphicsMetadata = c.SDL_ShaderCross_GraphicsShaderMetadata;
const GraphicsMetadataJSON = struct {
    num_samplers: u32,
    num_storage_textures: u32,
    num_storage_buffers: u32,
    num_uniform_buffers: u32,

    // TODO: inputs and outputs?
    fn fromMetadata(info: *const GraphicsMetadata) GraphicsMetadataJSON {
        return .{
            .num_samplers = info.num_samplers,
            .num_storage_textures = info.num_storage_textures,
            .num_storage_buffers = info.num_storage_buffers,
            .num_uniform_buffers = info.num_uniform_buffers,
        };
    }
};

pub fn main() !void {
    try allocators.init(1_000_000);
    defer allocators.deinit();

    const arguments = try parseArguments(allocators.global()) orelse return;

    if (!c.SDL_ShaderCross_Init()) fatal(
        "failed initializing shadercross: {s}",
        .{c.SDL_GetError()},
    );
    defer c.SDL_ShaderCross_Quit();

    log.info(
        \\running with:
        \\  input-dir: {s}
        \\  output-dir: {s}
        \\  install-dir: {?s}
        \\  include-dir: {?s}
    , .{
        arguments.input_directory,
        arguments.output_directory,
        arguments.install_directory,
        arguments.include_directory,
    });

    std.fs.makeDirAbsolute(arguments.output_directory) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {},
            else => fatal("failed creating output directory: {s}", .{@errorName(err)}),
        }
    };

    var input_dir = try std.fs.cwd().openDir(
        arguments.input_directory,
        .{ .access_sub_paths = true, .iterate = true },
    );

    var output_dir = try std.fs.cwd().openDir(
        arguments.output_directory,
        .{ .access_sub_paths = true },
    );

    log.info("starting shader compilation", .{});
    var timer = try std.time.Timer.start();
    defer log.info("shader compilation took {D}", .{timer.lap()});

    var iter = input_dir.iterate();
    while (try iter.next()) |file| {
        defer allocators.scratchRelease();

        const input_filename = file.name;
        const input_extension = std.fs.path.extension(input_filename);
        const input_basename = input_filename[0 .. input_filename.len - input_extension.len];

        if (!std.mem.eql(u8, FileFormat.extension(.hlsl), input_extension)) {
            log.info("skipping {s}", .{input_filename});
            continue;
        }

        const shader_stage = ShaderStage.fromFileName(input_basename);

        log.info("processing input file {s}", .{input_filename});

        const output_filenames = std.EnumArray(FileFormat, []const u8).init(.{
            .spirv = try std.fmt.allocPrint(
                allocators.scratch(),
                "{s}" ++ FileFormat.extension(.spirv),
                .{input_basename},
            ),
            .dxil = try std.fmt.allocPrint(
                allocators.scratch(),
                "{s}" ++ FileFormat.extension(.dxil),
                .{input_basename},
            ),
            .metal = try std.fmt.allocPrint(
                allocators.global(),
                "{s}" ++ FileFormat.extension(.metal),
                .{input_basename},
            ),
            .hlsl = try std.fmt.allocPrint(
                allocators.global(),
                "{s}" ++ FileFormat.extension(.hlsl),
                .{input_basename},
            ),
            .json = try std.fmt.allocPrint(
                allocators.global(),
                "{s}" ++ FileFormat.extension(.json),
                .{input_basename},
            ),
        });

        const hlsl_code = readInputFileZ(
            allocators.gpa(),
            input_filename,
            &input_dir,
        ) catch |err| {
            fatal("failed reading input file: {t}", .{err});
        };
        defer allocators.gpa().free(hlsl_code);

        const hlsl_info: c.SDL_ShaderCross_HLSL_Info = .{
            .source = hlsl_code.ptr,
            .entrypoint = "main",
            .include_dir = if (arguments.include_directory) |dir| dir.ptr else null,
            .shader_stage = @intFromEnum(shader_stage),
            .enable_debug = std.debug.runtime_safety,
            .name = (try std.mem.concatWithSentinel(allocators.scratch(), u8, &.{input_filename}, 0)).ptr,
        };

        {
            var dxil_code: []u8 = undefined;
            const ptr = c.SDL_ShaderCross_CompileDXILFromHLSL(&hlsl_info, &dxil_code.len);
            if (ptr == null) fatal("failed compiling dxil from hlsl: {s}", .{c.SDL_GetError()});
            dxil_code.ptr = @ptrCast(@alignCast(ptr));
            defer allocators.sdl().free(dxil_code.ptr);

            const output_filename = output_filenames.get(.dxil);
            try writeOutputFile(dxil_code, output_filename, &output_dir);
            try installFile(&arguments, output_filename);
        }

        var spirv_code: []u8 = undefined;
        {
            const ptr = c.SDL_ShaderCross_CompileSPIRVFromHLSL(&hlsl_info, &spirv_code.len);
            if (ptr == null) fatal("failed compiling spirv from hlsl: {s}", .{c.SDL_GetError()});
            spirv_code.ptr = @ptrCast(@alignCast(ptr));
        }
        defer allocators.sdl().free(spirv_code.ptr);

        {
            const output_filename = output_filenames.get(.spirv);
            try writeOutputFile(spirv_code, output_filename, &output_dir);
            try installFile(&arguments, output_filename);
        }

        const spirv_info: c.SDL_ShaderCross_SPIRV_Info = .{
            .bytecode = spirv_code.ptr,
            .bytecode_size = spirv_code.len,
            .entrypoint = "main",
            .shader_stage = @intFromEnum(shader_stage),
            .enable_debug = std.debug.runtime_safety,
            .name = (try std.mem.concatWithSentinel(
                allocators.scratch(),
                u8,
                &.{output_filenames.get(.spirv)},
                0,
            )).ptr,
        };

        {
            var metal_code: [:0]u8 = undefined;
            const ptr = c.SDL_ShaderCross_TranspileMSLFromSPIRV(&spirv_info);
            if (ptr == null) fatal("failed transpiling metal from spirv: {s}", .{c.SDL_GetError()});
            metal_code.ptr = @ptrCast(@alignCast(ptr));
            metal_code.len = std.mem.indexOfSentinel(u8, 0, metal_code.ptr);
            defer allocators.sdl().free(metal_code.ptr);

            const output_filename = output_filenames.get(.metal);
            try writeOutputFile(metal_code, output_filename, &output_dir);
            try installFile(&arguments, output_filename);
        }

        if (shader_stage == .compute) {
            const info = c.SDL_ShaderCross_ReflectComputeSPIRV(spirv_code.ptr, spirv_code.len, 0);
            if (info == null) fatal("failed to reflect spirv: {s}", .{c.SDL_GetError()});
            const output_filename = output_filenames.get(.json);
            try writeComputeJsonFile(info, output_filename, &output_dir);
        } else {
            const info = c.SDL_ShaderCross_ReflectGraphicsSPIRV(spirv_code.ptr, spirv_code.len, 0);
            if (info == null) fatal("failed to reflect spirv: {s}", .{c.SDL_GetError()});
            const output_filename = output_filenames.get(.json);
            try writeGraphicsJsonFile(info, output_filename, &output_dir);
        }
    }
}

fn parseArguments(allocator: std.mem.Allocator) !?Arguments {
    const args = try std.process.argsAlloc(allocator);

    var input_directory: ?[]const u8 = null;
    var output_directory: ?[]const u8 = null;
    var install_directory: ?[]const u8 = null;
    var include_directory: ?[:0]const u8 = null;

    {
        var n: usize = 1;
        while (n < args.len) : (n += 1) {
            const arg = args[n];
            if (std.mem.eql(u8, "-h", arg) or std.mem.eql(u8, "--help", arg)) {
                const stdout_buf = try allocators.scratch().alloc(u8, 256);
                defer allocators.scratchRelease();
                var stdout_writer = std.fs.File.stdout().writer(stdout_buf);
                const stdout = &stdout_writer.interface;
                try stdout.writeAll(usage);
                try stdout.flush();
                return null;
            } else if (std.mem.eql(u8, "--input-dir", arg)) {
                n += 1;
                if (n >= args.len) fatal("expected argument after '{s}'", .{arg});
                if (input_directory != null) fatal("duplicated argument {s}", .{arg});
                input_directory = args[n];
            } else if (std.mem.eql(u8, "--output-dir", arg)) {
                n += 1;
                if (n >= args.len) fatal("expected argument after '{s}'", .{arg});
                if (output_directory != null) fatal("duplicated argument {s}", .{arg});
                output_directory = args[n];
            } else if (std.mem.eql(u8, "--install-dir", arg)) {
                n += 1;
                if (n >= args.len) fatal("expected argument after '{s}'", .{arg});
                if (install_directory != null) fatal("duplicated argument {s}", .{arg});
                install_directory = args[n];
            } else if (std.mem.eql(u8, "--include-dir", arg)) {
                n += 1;
                if (n >= args.len) fatal("expected argument after '{s}'", .{arg});
                if (include_directory != null) fatal("duplicated argument {s}", .{arg});
                include_directory = try std.mem.concatWithSentinel(allocator, u8, &.{args[n]}, 0);
            } else {
                fatal("unrecognized argument: {s}", .{arg});
            }
        }
    }

    return .{
        .input_directory = input_directory orelse fatal("missing argument --input-dir", .{}),
        .output_directory = output_directory orelse fatal("missing argument --output-dir", .{}),
        .install_directory = install_directory,
        .include_directory = include_directory,
    };
}

fn readInputFileZ(allocator: std.mem.Allocator, filename: []const u8, dir: *std.fs.Dir) ![:0]const u8 {
    const file = try dir.openFile(filename, .{ .lock = .shared });
    defer file.close();

    const reader_buf = try allocators.scratch().alloc(u8, 256);
    defer allocators.scratch().free(reader_buf);

    var reader = file.reader(reader_buf);
    const buf = try reader.interface.readAlloc(allocator, try reader.getSize());
    errdefer allocator.free(buf);

    const result = try allocator.realloc(buf, buf.len + 1);
    result[buf.len] = 0;
    return result[0..buf.len :0];
}

fn writeOutputFile(data: []const u8, filename: []const u8, dir: *std.fs.Dir) !void {
    const file = try dir.createFile(filename, .{ .lock = .exclusive });
    defer file.close();

    const writer_buf = try allocators.scratch().alloc(u8, 256);
    defer allocators.scratch().free(writer_buf);

    var writer = file.writer(writer_buf);
    try writer.interface.writeAll(data);
    try writer.end();
    log.info("processed output file {s}", .{filename});
}

fn writeComputeJsonFile(info: *const ComputeMetadata, filename: []const u8, dir: *std.fs.Dir) !void {
    const file = try dir.createFile(filename, .{ .lock = .exclusive });
    defer file.close();

    const writer_buf = try allocators.scratch().alloc(u8, 256);
    defer allocators.scratch().free(writer_buf);

    var writer = file.writer(writer_buf);
    try std.json.fmt(ComputeMetadataJSON.fromMetadata(info), .{}).format(&writer.interface);
    try writer.end();
    log.info("processed output file {s}", .{filename});
}

fn writeGraphicsJsonFile(info: *const GraphicsMetadata, filename: []const u8, dir: *std.fs.Dir) !void {
    const file = try dir.createFile(filename, .{ .lock = .exclusive });
    defer file.close();

    const writer_buf = try allocators.scratch().alloc(u8, 256);
    defer allocators.scratch().free(writer_buf);

    var writer = file.writer(writer_buf);
    try std.json.fmt(GraphicsMetadataJSON.fromMetadata(info), .{}).format(&writer.interface);
    try writer.end();
    log.info("processed output file {s}", .{filename});
}

fn installFile(arguments: *const Arguments, output_filename: []const u8) !void {
    if (arguments.install_directory) |install_directory| {
        const output_path = try std.fs.path.join(
            allocators.scratch(),
            &.{ arguments.output_directory, output_filename },
        );
        const install_path = try std.fs.path.join(
            allocators.scratch(),
            &.{ install_directory, output_filename },
        );

        const update_stat = std.fs.updateFileAbsolute(output_path, install_path, .{}) catch |err| {
            fatal("failed installing for {s}: {t}\n- copy\n  from: {s}\n  to: {s}", .{
                output_filename,
                err,
                output_path,
                install_path,
            });
        };

        switch (update_stat) {
            .stale => log.info("updated install file {s}", .{output_filename}),
            .fresh => log.info("file {s} is already installed", .{output_filename}),
        }
    }
}
