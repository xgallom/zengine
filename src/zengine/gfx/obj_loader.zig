const std = @import("std");
const math = @import("../math.zig");
const mesh = @import("mesh.zig");

pub fn loadFile(allocator: std.mem.Allocator, path: []const u8) !mesh.TriangleMesh {
    var result = mesh.TriangleMesh.init(allocator);
    errdefer result.deinit();

    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    var reader = file.reader();

    var buf: [1024]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(&buf, '\n')) |line| {
        switch (line[0]) {
            '#' => continue,
            'v' => {
                const vertex = try parseVertex(line);
                try result.vertices.append(result.allocator, vertex);
            },
            'f' => {
                const face = try parseFace(line);
                if (face[0] >= result.vertices.items.len) return error.InvalidIndex;
                if (face[1] >= result.vertices.items.len) return error.InvalidIndex;
                if (face[2] >= result.vertices.items.len) return error.InvalidIndex;
                try result.faces.append(result.allocator, face);
            },
            else => return error.SyntaxError,
        }
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
            4 => std.log.warn("loaded 4th component of a 3-element vertex", .{}),
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
