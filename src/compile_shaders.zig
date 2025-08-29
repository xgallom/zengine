const std = @import("std");
const fatal = std.zig.fatal;

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
    include_directory: ?[]const u8,
};

fn parseArguments(allocator: std.mem.Allocator) !?Arguments {
    const args = try std.process.argsAlloc(allocator);

    var input_directory: ?[]const u8 = null;
    var output_directory: ?[]const u8 = null;
    var install_directory: ?[]const u8 = null;
    var include_directory: ?[]const u8 = null;

    {
        var n: usize = 1;
        while (n < args.len) : (n += 1) {
            const arg = args[n];
            if (std.mem.eql(u8, "-h", arg) or std.mem.eql(u8, "--help", arg)) {
                try std.io.getStdOut().writeAll(usage);
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
                include_directory = args[n];
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

const OutputConfig = struct {
    extension: []const u8,
};

pub fn main() !void {
    var arena_state = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const arguments = try parseArguments(arena) orelse return;

    std.log.info(
        \\running with:
        \\  --input-dir: {s}
        \\  --output-dir: {s}
        \\  --install-dir: {?s}
        \\  --include-dir: {?s}
    , .{ arguments.input_directory, arguments.output_directory, arguments.install_directory, arguments.include_directory });

    std.fs.makeDirAbsolute(arguments.output_directory) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {},
            else => fatal("failed creating output_directory: {s}", .{@errorName(err)}),
        }
    };

    const shader_directory = try std.fs.cwd().openDir(arguments.input_directory, .{ .iterate = true });
    var iterator = shader_directory.iterate();

    const output_configs = [_]OutputConfig{
        .{ .extension = ".spv" },
        .{ .extension = ".msl" },
        .{ .extension = ".dxil" },
    };

    while (try iterator.next()) |file| {
        const input_filename = file.name;
        const input_extension = std.fs.path.extension(input_filename);
        const input_basename = input_filename[0 .. input_filename.len - input_extension.len];

        if (!std.mem.eql(u8, ".hlsl", input_extension)) {
            std.log.info("skipping {s}", .{input_filename});
            continue;
        }

        std.log.info("processing input file {s}", .{input_filename});
        const input_path = try std.fs.path.join(arena, &.{ arguments.input_directory, input_filename });

        for (output_configs) |output_config| {
            const output_extension = output_config.extension;
            const output_filename = try std.fmt.allocPrint(arena, "{s}{s}", .{ input_basename, output_extension });
            const output_path = try std.fs.path.join(arena, &.{ arguments.output_directory, output_filename });

            var argv: []const []const u8 = &.{ "shadercross", input_path, "-o", output_path };

            if (arguments.include_directory) |include_directory| {
                argv = &.{ "shadercross", input_path, "-o", output_path, "-I", include_directory };
            }

            const result = std.process.Child.run(.{
                .allocator = std.heap.c_allocator,
                .argv = argv,
            }) catch |err| {
                if (err == error.FileNotFound) fatal("failed running shadercross", .{});
                return err;
            };

            switch (result.term) {
                .Exited => {
                    if (result.term.Exited != 0) {
                        fatal("failed conversion for {s}: {s}", .{ output_filename, result.stderr });
                    } else {
                        std.log.info("processed output file {s}", .{output_filename});
                    }
                },
                else => fatal("shadercross run failed for {s}", .{output_filename}),
            }

            if (arguments.install_directory) |install_directory| {
                const install_path = try std.fs.path.join(arena, &.{ install_directory, output_filename });
                const update_stat = std.fs.updateFileAbsolute(output_path, install_path, .{}) catch |err| {
                    fatal("failed installing for {s}: {s}\n- copy\n  from: {s}\n  to: {s}", .{ output_filename, @errorName(err), output_path, install_path });
                };

                switch (update_stat) {
                    .stale => std.log.info("updated install file {s}", .{output_filename}),
                    .fresh => std.log.info("file {s} is already installed", .{output_filename}),
                }
            }
        }
    }
}
