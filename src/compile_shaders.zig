const std = @import("std");
const fatal = std.process.fatal;

const c = @import("ext");
const ComputeMetadata = c.SDL_ShaderCross_ComputePipelineMetadata;
const GraphicsMetadata = c.SDL_ShaderCross_GraphicsShaderMetadata;
const GraphicsMetadataIOVar = c.SDL_ShaderCross_IOVarMetadata;

const allocators = @import("zengine/allocators.zig");
const options = @import("zengine/options.zig");
const sched = @import("zengine/sched.zig");
const str = @import("zengine/str.zig");
const time = @import("zengine/time.zig");

const log = std.log.scoped(.compile_shaders);

pub const std_options: std.Options = .{
    .log_level = .warn,
    .log_scope_levels = &.{
        .{ .scope = .compile_shaders, .level = .info },
    },
};

const usage =
    \\Usage: ./compile-shaders [options]
    \\
    \\Options:
    \\  --input-dir INPUT_DIRECTORY
    \\  --output-dir OUTPUT_DIRECTORY
    \\  --install-dir INSTALL_DIRECTORY
    \\  --include-dir INCLUDE_DIRECTORY
    \\  --verbose
    \\
;

const Arguments = struct {
    input_directory: [:0]const u8,
    output_directory: [:0]const u8,
    install_directory: ?[:0]const u8,
    include_directory: ?[:0]const u8,
    verbose: bool,
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
            .num_samplers = info.resource_info.num_samplers,
            .num_storage_textures = info.resource_info.num_storage_textures,
            .num_storage_buffers = info.resource_info.num_storage_buffers,
            .num_uniform_buffers = info.resource_info.num_uniform_buffers,
            .inputs = try IOVar.fromMetadata(info.inputs, info.num_inputs),
            .outputs = try IOVar.fromMetadata(info.outputs, info.num_outputs),
        };
    }
};

var io: std.Io = undefined;
pub fn main(init: std.process.Init.Minimal) !void {
    allocators.init(1 << 30);
    defer allocators.deinit();

    var threaded: std.Io.Threaded = .init_single_threaded;
    defer threaded.deinit();
    io = threaded.io();

    const arguments = try parseArguments(allocators.global(), init) orelse return;

    if (!c.SDL_ShaderCross_Init()) fatal(
        "failed initializing shadercross: {s}",
        .{c.SDL_GetError()},
    );
    defer c.SDL_ShaderCross_Quit();

    if (arguments.verbose) log.info(
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

    const dir = std.Io.Dir.cwd();
    dir.createDir(io, arguments.output_directory, .default_dir) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {},
            else => fatal("failed creating output directory: {s}", .{@errorName(err)}),
        }
    };

    var input_dir = try dir.openDir(
        io,
        arguments.input_directory,
        .{ .access_sub_paths = true, .iterate = true },
    );
    defer input_dir.close(io);

    var output_dir = try dir.openDir(
        io,
        arguments.output_directory,
        .{ .access_sub_paths = true },
    );
    defer output_dir.close(io);

    if (arguments.verbose) log.info("starting shader compilation", .{});
    const start = time.getNano();
    defer if (arguments.verbose) log.info(
        "shader compilation took {f}",
        .{std.Io.Duration.fromNanoseconds(time.getNano() - start)},
    );

    var queue: std.ArrayList(FileEntry) = .empty;
    var iter = try input_dir.walk(allocators.gpa());
    defer iter.deinit();
    while (try iter.next(io)) |entry| {
        switch (entry.kind) {
            .file => {
                if (arguments.verbose) log.info("file {s}: {s}", .{ entry.basename, entry.path });
                try queue.append(allocators.global(), .{
                    .basename = try str.dupeZ(entry.basename),
                    .path = try str.dupeZ(entry.path),
                });
            },
            .directory => {
                if (arguments.verbose) log.info("creating output directory {s}", .{entry.path});
                try output_dir.createDirPath(io, entry.path);
            },
            else => if (arguments.verbose) log.info("skipping {t} {s}", .{ entry.kind, entry.path }),
        }
    }

    const arenas = try sched.WorkerArena.createArray(allocators.gpa());
    defer sched.WorkerArena.deinitArray(arenas);
    var thread_pool: *sched.ThreadPool(&.{.{
        .ctx = WorkerCtx,
        .len = .remaining,
    }}, .{spawnThread}) = try .create();
    defer thread_pool.deinit();
    try thread_pool.run(.{.{
        .arguments = &arguments,
        .input_dir = input_dir,
        .output_dir = output_dir,
        .arenas = arenas,
        .queue = queue.items,
    }});
    thread_pool.join();
}

const WorkerCtx = struct {
    arguments: *const Arguments,
    input_dir: std.Io.Dir,
    output_dir: std.Io.Dir,
    arenas: *sched.WorkerArena.Array,
    queue: []const FileEntry,
};

fn spawnThread(
    ctx: WorkerCtx,
    info: *const sched.ThreadInfo,
    global_state: *sched.ThreadInfo.GroupSharedState,
) !bool {
    _ = global_state;
    const items = info.slice(ctx.queue);
    for (items) |item| try processFile(ctx, info, item);
    return false;
}

const ProcessState = struct {
    arguments: *const Arguments,
    output_dir: std.Io.Dir,
};

fn processFile(
    ctx: WorkerCtx,
    info: *const sched.ThreadInfo,
    item: FileEntry,
) !void {
    defer _ = ctx.arenas[info.idx].inner.reset(.retain_capacity);
    const gpa = ctx.arenas[info.idx].allocator();
    const hlsl_code = try readInputFileZ(gpa, item.path, ctx.input_dir);

    const input_extension = std.fs.path.extension(item.basename);
    const input_basename = item.path[0 .. item.path.len - input_extension.len];

    if (!str.eql(FileFormat.extension(.hlsl), input_extension)) {
        if (ctx.arguments.verbose) log.info("skipping {s}", .{item.path});
        return;
    }

    var output_filenames: std.EnumArray(FileFormat, [:0]const u8) = undefined;
    {
        output_filenames = .init(.{
            .spirv = try std.fmt.allocPrintSentinel(
                gpa,
                "{s}" ++ FileFormat.extension(.spirv),
                .{input_basename},
                0,
            ),
            .dxil = try std.fmt.allocPrintSentinel(
                gpa,
                "{s}" ++ FileFormat.extension(.dxil),
                .{input_basename},
                0,
            ),
            .metal = try std.fmt.allocPrintSentinel(
                gpa,
                "{s}" ++ FileFormat.extension(.metal),
                .{input_basename},
                0,
            ),
            .hlsl = try std.fmt.allocPrintSentinel(
                gpa,
                "{s}" ++ FileFormat.extension(.hlsl),
                .{input_basename},
                0,
            ),
            .json = try std.fmt.allocPrintSentinel(
                gpa,
                "{s}" ++ FileFormat.extension(.json),
                .{input_basename},
                0,
            ),
        });
    }

    const shader_stage = ShaderStage.fromFileName(input_basename);
    if (ctx.arguments.verbose) log.info("processing input file {s}", .{item.path});

    const hlsl_info: c.SDL_ShaderCross_HLSL_Info = .{
        .source = hlsl_code.ptr,
        .entrypoint = "main",
        .include_dir = if (ctx.arguments.include_directory) |dir| dir.ptr else null,
        .shader_stage = @intFromEnum(shader_stage),
    };

    {
        var dxil_code: []u8 = undefined;
        const ptr = c.SDL_ShaderCross_CompileDXILFromHLSL(&hlsl_info, &dxil_code.len);
        if (ptr == null) fatal("failed compiling dxil from hlsl: {s}", .{c.SDL_GetError()});
        dxil_code.ptr = @ptrCast(@alignCast(ptr));
        defer allocators.sdl().free(dxil_code.ptr);

        const output_filename = output_filenames.get(.dxil);
        try writeOutputFile(ctx.arguments, dxil_code, output_filename, ctx.output_dir);
        try installFile(ctx.arguments, output_filename);
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
        try writeOutputFile(ctx.arguments, spirv_code, output_filename, ctx.output_dir);
        try installFile(ctx.arguments, output_filename);
    }

    const spirv_info: c.SDL_ShaderCross_SPIRV_Info = .{
        .bytecode = spirv_code.ptr,
        .bytecode_size = spirv_code.len,
        .entrypoint = "main",
        .shader_stage = @intFromEnum(shader_stage),
    };

    {
        var metal_code: [:0]u8 = undefined;
        const ptr = c.SDL_ShaderCross_TranspileMSLFromSPIRV(&spirv_info);
        if (ptr == null) fatal("failed transpiling metal from spirv: {s}", .{c.SDL_GetError()});
        metal_code.ptr = @ptrCast(@alignCast(ptr));
        metal_code.len = std.mem.len(metal_code.ptr);
        defer allocators.sdl().free(metal_code.ptr);

        const output_filename = output_filenames.get(.metal);
        try writeOutputFile(ctx.arguments, metal_code, output_filename, ctx.output_dir);
        try installFile(ctx.arguments, output_filename);
    }

    if (shader_stage == .compute) {
        const spirv_refl = c.SDL_ShaderCross_ReflectComputeSPIRV(spirv_code.ptr, spirv_code.len, 0);
        if (spirv_refl == null) fatal("failed to reflect spirv: {s}", .{c.SDL_GetError()});
        const output_filename = output_filenames.get(.json);
        try writeComputeJsonFile(ctx.arguments, spirv_refl, output_filename, ctx.output_dir);
        try installFile(ctx.arguments, output_filename);
    } else {
        const spirv_refl = c.SDL_ShaderCross_ReflectGraphicsSPIRV(spirv_code.ptr, spirv_code.len, 0);
        if (spirv_refl == null) fatal("failed to reflect spirv: {s}", .{c.SDL_GetError()});
        const output_filename = output_filenames.get(.json);
        try writeGraphicsJsonFile(ctx.arguments, spirv_refl, output_filename, ctx.output_dir);
        try installFile(ctx.arguments, output_filename);
    }
}

fn parseArguments(allocator: std.mem.Allocator, init: std.process.Init.Minimal) !?Arguments {
    const args = try init.args.toSlice(allocator);
    defer allocator.free(args);

    var input_directory: ?[:0]const u8 = null;
    var output_directory: ?[:0]const u8 = null;
    var install_directory: ?[:0]const u8 = null;
    var include_directory: ?[:0]const u8 = null;
    var verbose: bool = false;

    {
        var n: usize = 1;
        while (n < args.len) : (n += 1) {
            const arg = args[n];
            if (str.eql("-h", arg) or str.eql("--help", arg)) {
                const stdout_buf = try allocators.scratch().alloc(u8, 256);
                defer allocators.scratchRelease();
                var stdout_writer = std.Io.File.stdout().writer(io, stdout_buf);
                const stdout = &stdout_writer.interface;
                try stdout.writeAll(usage);
                try stdout.flush();
                return null;
            } else if (str.eql("--verbose", arg)) {
                verbose = true;
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
        .verbose = verbose,
    };
}

fn readInputFileZ(
    allocator: std.mem.Allocator,
    filename: []const u8,
    dir: std.Io.Dir,
) ![:0]const u8 {
    const file = try dir.openFile(io, filename, .{ .lock = .shared });
    defer file.close(io);

    const reader_buf = try allocators.scratch().alloc(u8, 256);
    defer allocators.scratch().free(reader_buf);

    var reader = file.reader(io, reader_buf);
    const size = try reader.getSize();
    const buf = try allocator.allocSentinel(u8, size, 0);
    errdefer allocator.free(buf);

    try reader.interface.readSliceAll(buf);
    return buf;
}

fn writeOutputFile(
    arguments: *const Arguments,
    data: []const u8,
    filename: []const u8,
    dir: std.Io.Dir,
) !void {
    const file = try dir.createFile(io, filename, .{ .lock = .exclusive });
    defer file.close(io);

    const writer_buf = try allocators.scratch().alloc(u8, 256);
    defer allocators.scratch().free(writer_buf);

    var writer = file.writer(io, writer_buf);
    try writer.interface.writeAll(data);
    try writer.end();
    if (arguments.verbose) log.info("processed output file {s}", .{filename});
}

fn writeComputeJsonFile(
    arguments: *const Arguments,
    info: *const ComputeMetadata,
    filename: []const u8,
    dir: std.Io.Dir,
) !void {
    const file = try dir.createFile(io, filename, .{ .lock = .exclusive });
    defer file.close(io);

    const writer_buf = try allocators.scratch().alloc(u8, 256);
    defer allocators.scratch().free(writer_buf);

    var writer = file.writer(io, writer_buf);
    try std.json.fmt(ComputeMetadataJSON.fromMetadata(info), .{}).format(&writer.interface);
    try writer.end();
    if (arguments.verbose) log.info("processed output file {s}", .{filename});
}

fn writeGraphicsJsonFile(
    arguments: *const Arguments,
    info: *const GraphicsMetadata,
    filename: []const u8,
    dir: std.Io.Dir,
) !void {
    const file = try dir.createFile(io, filename, .{ .lock = .exclusive });
    defer file.close(io);

    const writer_buf = try allocators.scratch().alloc(u8, 256);
    defer allocators.scratch().free(writer_buf);

    var writer = file.writer(io, writer_buf);
    try std.json.fmt(try GraphicsMetadataJSON.fromMetadata(info), .{}).format(&writer.interface);
    try writer.end();
    if (arguments.verbose) log.info("processed output file {s}", .{filename});
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

        const dir = std.Io.Dir.cwd();
        const update_stat = dir.updateFile(io, output_path, dir, install_path, .{}) catch |err| {
            fatal("failed installing for {s}: {t}\n- copy\n  from: {s}\n  to: {s}", .{
                output_filename,
                err,
                output_path,
                install_path,
            });
        };

        switch (update_stat) {
            .stale => if (arguments.verbose) log.info(
                "updated install file {s}",
                .{output_filename},
            ),
            .fresh => if (arguments.verbose) log.info(
                "file {s} is already installed",
                .{output_filename},
            ),
        }
    }
}
