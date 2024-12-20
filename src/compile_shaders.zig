const std = @import("std");
const fatal = std.zig.fatal;

const usage =
    \\Usage: ./shader_compile [options]
    \\
    \\Options:
    \\  --input-dir INPUT_DIRECTORY
    \\  --output-dir OUTPUT_DIRECTORY
    \\
;

const Arguments = struct {
    input_directory: []const u8,
    output_directory: []const u8,
};

fn parseArguments(allocator: std.mem.Allocator) !?Arguments {
    const args = try std.process.argsAlloc(allocator);

    var input_directory: ?[]const u8 = null;
    var output_directory: ?[]const u8 = null;

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
            } else {
                fatal("unrecognized argument: {s}", .{arg});
            }
        }
    }

    return .{
        .input_directory = input_directory orelse fatal("missing argument --input-dir", .{}),
        .output_directory = output_directory orelse fatal("missing argument --output-dir", .{}),
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
        \\  input-dir: "{s}"
        \\  output-dir: "{s}"
    , .{ arguments.input_directory, arguments.output_directory });

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

        for (output_configs) |output_config| {
            const output_extension = output_config.extension;
            const output_filename = try std.fmt.allocPrint(arena, "{s}{s}", .{ input_basename, output_extension });

            const result = std.process.Child.run(.{
                .allocator = std.heap.c_allocator,
                .argv = &.{
                    "shadercross",
                    try std.fs.path.join(arena, &.{ arguments.input_directory, input_filename }),
                    "-o",
                    try std.fs.path.join(arena, &.{ arguments.output_directory, output_filename }),
                },
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
        }
    }
}
