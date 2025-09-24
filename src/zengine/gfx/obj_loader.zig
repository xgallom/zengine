const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const math = @import("../math.zig");
const mesh = @import("mesh.zig");

const log = std.log.scoped(.gfx_obj_loader);

pub fn loadFile(allocator: std.mem.Allocator, path: []const u8) !mesh.TriangleMesh {
    var result = mesh.TriangleMesh.init(allocator);
    errdefer result.freeCpuData();

    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const buf = try allocators.scratch().alloc(u8, 1 << 8);
    var reader = file.reader(buf);

    while (reader.interface.takeDelimiterExclusive('\n')) |line| {
        switch (line[0]) {
            '#' => continue,
            'v' => {
                const vertex = try parseVertex(line);
                try result.appendVertex(vertex);
            },
            'f' => {
                const face = try parseFace(line);
                if (face[0] >= result.verts.items.len) return error.InvalidIndex;
                if (face[1] >= result.verts.items.len) return error.InvalidIndex;
                if (face[2] >= result.verts.items.len) return error.InvalidIndex;
                try result.appendFace(face);
            },
            else => return error.SyntaxError,
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.StreamTooLong,
        error.ReadFailed,
        => |e| return e,
    }

    return result;
}

fn parseVertex(line: []const u8) !math.Vertex {
    var result = math.Vertex{ 0, 0, 0 };
    var iterator = std.mem.splitScalar(u8, line, ' ');
    var step: usize = 0;
    while (iterator.next()) |token| : (step += 1) {
        switch (step) {
            0 => if (!std.mem.eql(u8, token, "v")) return error.SyntaxError,
            1, 2, 3 => {
                result[step - 1] = std.fmt.parseFloat(math.Scalar, token) catch {
                    return error.ParseFloatError;
                };
            },
            4 => log.warn("loaded 4th component of a 3-element vertex", .{}),
            else => return error.TooManyArguments,
        }
    }

    if (step < 4) return error.NotEnoughArguments;
    return result;
}

fn parseFace(line: []const u8) !math.FaceIndex {
    var result: math.FaceIndex = undefined;
    var iterator = std.mem.splitScalar(u8, line, ' ');
    var step: usize = 0;
    while (iterator.next()) |token| : (step += 1) {
        switch (step) {
            0 => if (!std.mem.eql(u8, token, "f")) return error.SyntaxError,
            1, 2, 3 => {
                const face_int = std.fmt.parseInt(math.Index, token, 10) catch {
                    return error.ParseIntError;
                };
                result[step - 1] = face_int - 1;
            },
            else => return error.TooManyArguments,
        }
    }

    if (step < 4) return error.NotEnoughArguments;
    return result;
}
