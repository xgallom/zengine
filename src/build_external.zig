const std = @import("std");
const fatal = std.process.fatal;

const log = std.log.scoped(.compile_external);

pub const std_options: std.Options = .{
    .log_level = .info,
};

const usage =
    \\Usage: ./compile-external [options]
    \\
    \\Options:
    \\  --input-dir INPUT_DIRECTORY
    \\  --output-dir OUTPUT_DIRECTORY
    \\  --cache-dir CACHE_DIRECTORY
    \\
;

const Arguments = struct {
    input_dir: []const u8,
    output_dir: []const u8,
    cache_dir: []const u8,
};

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.raw_c_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const args = (try parseArguments(arena)) orelse return;

    log.info(
        \\running with:
        \\  input-dir: {s}
        \\  output-dir: {s}
        \\  cache-dir: {s}
    , .{
        args.input_dir,
        args.output_dir,
        args.cache_dir,
    });

    const package_redirects_path = try std.fs.path.join(
        arena,
        &.{ args.output_dir, "lib", "cmake" },
    );
    const package_redirects_arg = try std.fmt.allocPrint(
        arena,
        "-DCMAKE_FIND_PACKAGE_REDIRECTS_DIR=\"{s}\"",
        .{package_redirects_path},
    );

    const cimgui_src_dir = try std.fs.path.join(
        arena,
        &.{ args.input_dir, "cimgui" },
    );
    const cimgui_src_arg = try std.fmt.allocPrint(
        arena,
        "-Dcimgui_SOURCE_DIR=\"{s}\"",
        .{cimgui_src_dir},
    );

    var env_map = try std.process.getEnvMap(std.heap.c_allocator);
    defer env_map.deinit();
    try env_map.put("CMAKE_INSTALL_PREFIX", args.output_dir);

    try build(arena, args, "SDL", "SDL", &env_map, &.{
        "-DCMAKE_OSX_ARCHITECTURES=\"x86_64;arm64\"",
        "-DSDL_VULKAN=ON",
        "-DSDL_RENDER_VULKAN=ON",
        "-DSDL_TEST_LIBRARY=OFF",
    });
    try build(arena, args, "SDL Shadercross", "SDL_shadercross", &env_map, &.{
        package_redirects_arg,
        "-DSDLSHADERCROSS_VENDORED=ON",
        "-DBUILD_SHARED_LIBS=ON",
        "-DSDLSHADERCROSS_INSTALL=ON",
        "-DSDL_TEST_LIBRARY=OFF",
    });
    try build(arena, args, "cimgui", "cimgui-build", &env_map, &.{
        package_redirects_arg,
        cimgui_src_arg,
        "-DSDL_TEST_LIBRARY=OFF",
    });
}

fn build(
    arena: std.mem.Allocator,
    args: Arguments,
    project: []const u8,
    project_dir: []const u8,
    env_map: *const std.process.EnvMap,
    cmake_argv: []const []const u8,
) !void {
    const cache_dir = try std.fs.path.join(arena, &.{ args.cache_dir, project_dir });
    try runCmake(arena, args, project, project_dir, env_map, cmake_argv, cache_dir);
    try runMake(project, cache_dir);
    try runMakeInstall(project, cache_dir);
}

fn runCmake(
    arena: std.mem.Allocator,
    args: Arguments,
    project: []const u8,
    project_dir: []const u8,
    env_map: *const std.process.EnvMap,
    argv: []const []const u8,
    cache_dir: []const u8,
) !void {
    const input_dir = try std.fs.path.join(arena, &.{ args.input_dir, project_dir });

    var stdout_writer = std.fs.File.stderr().writer(&.{});
    const stdout = &stdout_writer.interface;
    var i = env_map.iterator();
    while (i.next()) |item| try stdout.print("{s}={s}\n", .{ item.key_ptr.*, item.value_ptr.* });
    try stdout.flush();

    const result = std.process.Child.run(.{
        .allocator = std.heap.c_allocator,
        .argv = try std.mem.concat(arena, []const u8, &.{
            &.{ "cmake", input_dir },
            argv,
        }),
        .env_map = env_map,
        .cwd = cache_dir,
    }) catch |err| {
        if (err == error.FileNotFound) fatal("cmake not found", .{});
        return err;
    };

    switch (result.term) {
        .Exited => {
            if (result.term.Exited != 0) {
                fatal("failed configuration of {s}: {s}", .{ project, result.stderr });
            }
        },
        else => fatal("cmake run failed for {s}", .{project}),
    }
}

fn runMake(
    project: []const u8,
    cache_dir: []const u8,
) !void {
    log.info("make {s}", .{project});
    const result = std.process.Child.run(.{
        .allocator = std.heap.c_allocator,
        .argv = &.{ "make", "-j", "8" },
        .cwd = cache_dir,
    }) catch |err| {
        if (err == error.FileNotFound) fatal("failed running make", .{});
        return err;
    };

    switch (result.term) {
        .Exited => {
            if (result.term.Exited != 0) {
                fatal("failed compilation of {s}: {s}", .{ project, result.stderr });
            }
        },
        else => fatal("make run failed for {s}", .{project}),
    }
}

fn runMakeInstall(
    project: []const u8,
    cache_dir: []const u8,
) !void {
    log.info("make install {s}", .{project});
    const result = std.process.Child.run(.{
        .allocator = std.heap.c_allocator,
        .argv = &.{ "make", "install" },
        .cwd = cache_dir,
    }) catch |err| {
        if (err == error.FileNotFound) fatal("failed running make install", .{});
        return err;
    };

    switch (result.term) {
        .Exited => {
            if (result.term.Exited != 0) {
                fatal("failed installation of {s}: {s}", .{ project, result.stderr });
            }
        },
        else => fatal("make install run failed for {s}", .{project}),
    }
}

fn parseArguments(allocator: std.mem.Allocator) !?Arguments {
    const args = try std.process.argsAlloc(allocator);

    var input_dir: ?[]const u8 = null;
    var output_dir: ?[]const u8 = null;
    var cache_dir: ?[]const u8 = null;

    {
        var n: usize = 1;
        while (n < args.len) : (n += 1) {
            const arg = args[n];
            if (std.mem.eql(u8, "-h", arg) or std.mem.eql(u8, "--help", arg)) {
                const stdout_buf = try allocator.alloc(u8, 256);
                defer allocator.free(stdout_buf);
                var stdout_writer = std.fs.File.stdout().writer(stdout_buf);
                const stdout = &stdout_writer.interface;
                try stdout.writeAll(usage);
                try stdout.flush();
                return null;
            } else if (std.mem.eql(u8, "--input-dir", arg)) {
                n += 1;
                if (n >= args.len) fatal("expected argument after '{s}'", .{arg});
                if (input_dir != null) fatal("duplicated argument {s}", .{arg});
                input_dir = args[n];
            } else if (std.mem.eql(u8, "--output-dir", arg)) {
                n += 1;
                if (n >= args.len) fatal("expected argument after '{s}'", .{arg});
                if (output_dir != null) fatal("duplicated argument {s}", .{arg});
                output_dir = args[n];
            } else if (std.mem.eql(u8, "--cache-dir", arg)) {
                n += 1;
                if (n >= args.len) fatal("expected argument after '{s}'", .{arg});
                if (cache_dir != null) fatal("duplicated argument {s}", .{arg});
                cache_dir = args[n];
            } else {
                fatal("unrecognized argument: {s}", .{arg});
            }
        }
    }

    return .{
        .input_dir = input_dir orelse fatal("missing argument --input-dir", .{}),
        .output_dir = output_dir orelse fatal("missing argument --output-dir", .{}),
        .cache_dir = cache_dir orelse fatal("missing argument --cache-dir", .{}),
    };
}
