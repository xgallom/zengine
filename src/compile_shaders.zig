const std = @import("std");
const fatal = std.process.fatal;

const zengine = @import("zengine");
const allocators = zengine.allocators;
const c = zengine.ext.c;
const str = zengine.str;
const ComputeMetadata = c.SDL_ShaderCross_ComputePipelineMetadata;
const GraphicsMetadata = c.SDL_ShaderCross_GraphicsShaderMetadata;
const GraphicsMetadataIOVar = c.SDL_ShaderCross_IOVarMetadata;

const log = std.log.scoped(.compile_shaders);
const sections = zengine.perf.sections(@This(), &.{ .init, .read, .compile, .write, .install });

pub const std_options: std.Options = .{
    .log_level = .info,
};

const usage =
    \\Usage: ./compile-shaders [options]
    \\
    \\Options:
    \\  --input-dir INPUT_DIRECTORY
    \\  --output-dir OUTPUT_DIRECTORY
    \\  --install-dir INSTALL_DIRECTORY
    \\  --include-dir INCLUDE_DIRECTORY
    \\
;

const Arguments = struct {
    input_directory: [:0]const u8,
    output_directory: [:0]const u8,
    install_directory: ?[:0]const u8,
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

const FileEntry = struct {
    hlsl_code: [:0]const u8,
    basename: [:0]const u8,
    path: [:0]const u8,
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
        if (str.eql(extension(.vertex), shader_stage_ext)) {
            return .vertex;
        } else if (str.eql(extension(.fragment), shader_stage_ext)) {
            return .fragment;
        } else if (str.eql(extension(.compute), shader_stage_ext)) {
            return .compute;
        } else {
            fatal("shader {s} missing stage extension", .{filename});
        }
    }
};

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

const GraphicsMetadataJSON = struct {
    num_samplers: u32,
    num_storage_textures: u32,
    num_storage_buffers: u32,
    num_uniform_buffers: u32,
    inputs: []IOVar,
    outputs: []IOVar,

    const IOVar = struct {
        name: [:0]const u8,
        location: u32,
        vector_type: Type,
        vector_size: u32,

        const Type = enum(c.SDL_ShaderCross_IOVarType) {
            unknown = c.SDL_SHADERCROSS_IOVAR_TYPE_UNKNOWN,
            i8 = c.SDL_SHADERCROSS_IOVAR_TYPE_INT8,
            u8 = c.SDL_SHADERCROSS_IOVAR_TYPE_UINT8,
            i16 = c.SDL_SHADERCROSS_IOVAR_TYPE_INT16,
            u16 = c.SDL_SHADERCROSS_IOVAR_TYPE_UINT16,
            i32 = c.SDL_SHADERCROSS_IOVAR_TYPE_INT32,
            u32 = c.SDL_SHADERCROSS_IOVAR_TYPE_UINT32,
            i64 = c.SDL_SHADERCROSS_IOVAR_TYPE_INT64,
            u64 = c.SDL_SHADERCROSS_IOVAR_TYPE_UINT64,
            f16 = c.SDL_SHADERCROSS_IOVAR_TYPE_FLOAT16,
            f32 = c.SDL_SHADERCROSS_IOVAR_TYPE_FLOAT32,
            f64 = c.SDL_SHADERCROSS_IOVAR_TYPE_FLOAT64,
        };

        fn fromMetadata(items: [*]const GraphicsMetadataIOVar, len: usize) ![]IOVar {
            const buf = try allocators.global().alloc(IOVar, len);
            for (items[0..len], 0..) |item, n| {
                buf[n] = .{
                    .name = std.mem.span(item.name),
                    .location = item.location,
                    .vector_type = @enumFromInt(item.vector_type),
                    .vector_size = item.vector_size,
                };
            }
            return buf;
        }
    };

    fn fromMetadata(info: *const GraphicsMetadata) !GraphicsMetadataJSON {
        return .{
            .num_samplers = info.num_samplers,
            .num_storage_textures = info.num_storage_textures,
            .num_storage_buffers = info.num_storage_buffers,
            .num_uniform_buffers = info.num_uniform_buffers,
            .inputs = try IOVar.fromMetadata(info.inputs, info.num_inputs),
            .outputs = try IOVar.fromMetadata(info.outputs, info.num_outputs),
        };
    }
};

pub fn main() !void {
    allocators.init(1_000_000);
    defer allocators.deinit();

    try zengine.perf.init();
    defer zengine.perf.deinit();
    try sections.register();

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
    defer input_dir.close();

    var output_dir = try std.fs.cwd().openDir(
        arguments.output_directory,
        .{ .access_sub_paths = true },
    );
    defer output_dir.close();

    log.info("starting shader compilation", .{});
    var timer = try std.time.Timer.start();
    defer log.info("shader compilation took {D}", .{timer.lap()});

    var m: std.Thread.Mutex = .{};
    var queue: std.ArrayList(FileEntry) = .empty;
    var is_running: std.atomic.Value(bool) = .init(true);

    const thread_cnt = @max(try std.Thread.getCpuCount() -| 1, 1);
    const threads = try allocators.global().alloc(std.Thread, thread_cnt);

    for (threads) |*thread| {
        thread.* = try .spawn(.{}, spawnThread, .{ &arguments, output_dir, &queue, &m, &is_running });
    }

    var iter = try input_dir.walk(allocators.gpa());
    defer iter.deinit();
    while (try iter.next()) |entry| {
        switch (entry.kind) {
            .file => {
                m.lock();
                defer m.unlock();
                const hlsl_code = readInputFileZ(
                    allocators.gpa(),
                    entry.basename,
                    entry.dir,
                ) catch |err| {
                    fatal("failed reading input file: {t}", .{err});
                };
                errdefer allocators.gpa().free(hlsl_code);
                try queue.append(allocators.global(), .{
                    .hlsl_code = hlsl_code,
                    .basename = try str.dupeZ(entry.basename),
                    .path = try str.dupeZ(entry.path),
                });
            },
            .directory => {
                log.info("creating output directory {s}", .{entry.path});
                m.lock();
                defer m.unlock();
                try output_dir.makePath(entry.path);
            },
            else => log.info("skipping {t} {s}", .{ entry.kind, entry.path }),
        }
    }

    is_running.store(false, .monotonic);
    for (threads) |*thread| thread.join();
}

fn spawnThread(
    arguments: *const Arguments,
    output_dir: std.fs.Dir,
    queue: *std.ArrayList(FileEntry),
    m: *std.Thread.Mutex,
    is_running: *std.atomic.Value(bool),
) !void {
    while (true) {
        const item = blk: {
            m.lock();
            defer m.unlock();
            break :blk queue.pop();
        };
        if (item) |i| {
            try processFile(arguments, output_dir, i, m);
        } else if (!is_running.load(.monotonic)) {
            m.lock();
            defer m.unlock();
            if (queue.items.len == 0) break;
        }
    }
}

const ProcessState = struct {
    arguments: *const Arguments,
    output_dir: std.fs.Dir,
};

fn processFile(
    arguments: *const Arguments,
    output_dir: std.fs.Dir,
    item: FileEntry,
    m: *std.Thread.Mutex,
) !void {
    const hlsl_code = item.hlsl_code;
    defer {
        m.lock();
        defer m.unlock();
        allocators.gpa().free(hlsl_code);
    }

    const input_extension = std.fs.path.extension(item.basename);
    const input_basename = item.path[0 .. item.path.len - input_extension.len];

    if (!str.eql(FileFormat.extension(.hlsl), input_extension)) {
        log.info("skipping {s}", .{item.path});
        return;
    }

    var output_filenames: std.EnumArray(FileFormat, [:0]const u8) = undefined;
    {
        m.lock();
        defer m.unlock();
        output_filenames = .init(.{
            .spirv = try str.allocPrintZ(
                "{s}" ++ FileFormat.extension(.spirv),
                .{input_basename},
            ),
            .dxil = try str.allocPrintZ(
                "{s}" ++ FileFormat.extension(.dxil),
                .{input_basename},
            ),
            .metal = try str.allocPrintZ(
                "{s}" ++ FileFormat.extension(.metal),
                .{input_basename},
            ),
            .hlsl = try str.allocPrintZ(
                "{s}" ++ FileFormat.extension(.hlsl),
                .{input_basename},
            ),
            .json = try str.allocPrintZ(
                "{s}" ++ FileFormat.extension(.json),
                .{input_basename},
            ),
        });
    }

    const shader_stage = ShaderStage.fromFileName(input_basename);
    log.info("processing input file {s}", .{item.path});

    const hlsl_info: c.SDL_ShaderCross_HLSL_Info = .{
        .source = hlsl_code.ptr,
        .entrypoint = "main",
        .include_dir = if (arguments.include_directory) |dir| dir.ptr else null,
        .shader_stage = @intFromEnum(shader_stage),
        .enable_debug = std.debug.runtime_safety,
        .name = item.path.ptr,
    };

    {
        var dxil_code: []u8 = undefined;
        const ptr = c.SDL_ShaderCross_CompileDXILFromHLSL(&hlsl_info, &dxil_code.len);
        if (ptr == null) fatal("failed compiling dxil from hlsl: {s}", .{c.SDL_GetError()});
        dxil_code.ptr = @ptrCast(@alignCast(ptr));
        defer allocators.sdl().free(dxil_code.ptr);

        const output_filename = output_filenames.get(.dxil);
        {
            m.lock();
            defer m.unlock();
            try writeOutputFile(dxil_code, output_filename, output_dir);
            try installFile(arguments, output_filename);
        }
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
        {
            m.lock();
            defer m.unlock();
            try writeOutputFile(spirv_code, output_filename, output_dir);
            try installFile(arguments, output_filename);
        }
    }

    const spirv_info: c.SDL_ShaderCross_SPIRV_Info = .{
        .bytecode = spirv_code.ptr,
        .bytecode_size = spirv_code.len,
        .entrypoint = "main",
        .shader_stage = @intFromEnum(shader_stage),
        .enable_debug = std.debug.runtime_safety,
        .name = output_filenames.get(.spirv).ptr,
    };

    {
        var metal_code: [:0]u8 = undefined;
        const ptr = c.SDL_ShaderCross_TranspileMSLFromSPIRV(&spirv_info);
        if (ptr == null) fatal("failed transpiling metal from spirv: {s}", .{c.SDL_GetError()});
        metal_code.ptr = @ptrCast(@alignCast(ptr));
        metal_code.len = std.mem.len(metal_code.ptr);
        defer allocators.sdl().free(metal_code.ptr);

        const output_filename = output_filenames.get(.metal);
        {
            m.lock();
            defer m.unlock();
            try writeOutputFile(metal_code, output_filename, output_dir);
            try installFile(arguments, output_filename);
        }
    }

    if (shader_stage == .compute) {
        const info = c.SDL_ShaderCross_ReflectComputeSPIRV(spirv_code.ptr, spirv_code.len, 0);
        if (info == null) fatal("failed to reflect spirv: {s}", .{c.SDL_GetError()});
        const output_filename = output_filenames.get(.json);
        {
            m.lock();
            defer m.unlock();
            try writeComputeJsonFile(info, output_filename, output_dir);
            try installFile(arguments, output_filename);
        }
    } else {
        const info = c.SDL_ShaderCross_ReflectGraphicsSPIRV(spirv_code.ptr, spirv_code.len, 0);
        if (info == null) fatal("failed to reflect spirv: {s}", .{c.SDL_GetError()});
        const output_filename = output_filenames.get(.json);
        {
            m.lock();
            defer m.unlock();
            try writeGraphicsJsonFile(info, output_filename, output_dir);
            try installFile(arguments, output_filename);
        }
    }
}

fn parseArguments(allocator: std.mem.Allocator) !?Arguments {
    const args = try std.process.argsAlloc(allocator);

    var input_directory: ?[:0]const u8 = null;
    var output_directory: ?[:0]const u8 = null;
    var install_directory: ?[:0]const u8 = null;
    var include_directory: ?[:0]const u8 = null;

    {
        var n: usize = 1;
        while (n < args.len) : (n += 1) {
            const arg = args[n];
            if (str.eql("-h", arg) or str.eql("--help", arg)) {
                const stdout_buf = try allocators.scratch().alloc(u8, 256);
                defer allocators.scratchRelease();
                var stdout_writer = std.fs.File.stdout().writer(stdout_buf);
                const stdout = &stdout_writer.interface;
                try stdout.writeAll(usage);
                try stdout.flush();
                return null;
            } else if (str.eql("--input-dir", arg)) {
                n += 1;
                if (n >= args.len) fatal("expected argument after '{s}'", .{arg});
                if (input_directory != null) fatal("duplicated argument {s}", .{arg});
                input_directory = try allocator.dupeZ(u8, args[n]);
            } else if (str.eql("--output-dir", arg)) {
                n += 1;
                if (n >= args.len) fatal("expected argument after '{s}'", .{arg});
                if (output_directory != null) fatal("duplicated argument {s}", .{arg});
                output_directory = try allocator.dupeZ(u8, args[n]);
            } else if (str.eql("--install-dir", arg)) {
                n += 1;
                if (n >= args.len) fatal("expected argument after '{s}'", .{arg});
                if (install_directory != null) fatal("duplicated argument {s}", .{arg});
                install_directory = try allocator.dupeZ(u8, args[n]);
            } else if (str.eql("--include-dir", arg)) {
                n += 1;
                if (n >= args.len) fatal("expected argument after '{s}'", .{arg});
                if (include_directory != null) fatal("duplicated argument {s}", .{arg});
                include_directory = try allocator.dupeZ(u8, args[n]);
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

fn readInputFileZ(allocator: std.mem.Allocator, filename: []const u8, dir: std.fs.Dir) ![:0]const u8 {
    const file = try dir.openFile(filename, .{ .lock = .shared });
    defer file.close();

    const reader_buf = try allocators.scratch().alloc(u8, 256);
    defer allocators.scratch().free(reader_buf);

    var reader = file.reader(reader_buf);
    const size = try reader.getSize();
    const buf = try allocator.allocSentinel(u8, size, 0);
    errdefer allocator.free(buf);

    try reader.interface.readSliceAll(buf);
    return buf;
}

fn writeOutputFile(data: []const u8, filename: []const u8, dir: std.fs.Dir) !void {
    const file = try dir.createFile(filename, .{ .lock = .exclusive });
    defer file.close();

    const writer_buf = try allocators.scratch().alloc(u8, 256);
    defer allocators.scratch().free(writer_buf);

    var writer = file.writer(writer_buf);
    try writer.interface.writeAll(data);
    try writer.end();
    log.info("processed output file {s}", .{filename});
}

fn writeComputeJsonFile(info: *const ComputeMetadata, filename: []const u8, dir: std.fs.Dir) !void {
    const file = try dir.createFile(filename, .{ .lock = .exclusive });
    defer file.close();

    const writer_buf = try allocators.scratch().alloc(u8, 256);
    defer allocators.scratch().free(writer_buf);

    var writer = file.writer(writer_buf);
    try std.json.fmt(ComputeMetadataJSON.fromMetadata(info), .{}).format(&writer.interface);
    try writer.end();
    log.info("processed output file {s}", .{filename});
}

fn writeGraphicsJsonFile(info: *const GraphicsMetadata, filename: []const u8, dir: std.fs.Dir) !void {
    const file = try dir.createFile(filename, .{ .lock = .exclusive });
    defer file.close();

    const writer_buf = try allocators.scratch().alloc(u8, 256);
    defer allocators.scratch().free(writer_buf);

    var writer = file.writer(writer_buf);
    try std.json.fmt(try GraphicsMetadataJSON.fromMetadata(info), .{}).format(&writer.interface);
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
