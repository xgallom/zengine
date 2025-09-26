const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const math = @import("../math.zig");
const Mesh = @import("Mesh.zig");
const str = @import("../str.zig");

const log = std.log.scoped(.gfx_obj_loader);

pub const Result = struct {
    mesh: Mesh,
    mtl_path: ?[]const u8 = null,
};

pub fn loadFile(gpa: std.mem.Allocator, path: []const u8) !Result {
    var result = Result{ .mesh = try .init(gpa) };
    errdefer result.mesh.freeCpuData();
    errdefer if (result.mtl_path) |mtl_path| gpa.free(mtl_path);

    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const buf = try allocators.scratch().alloc(u8, 1 << 8);
    var reader = file.reader(buf);

    var verts = try std.ArrayList(math.Vertex).initCapacity(gpa, 128);
    defer verts.deinit(gpa);
    var normals = try std.ArrayList(math.Vertex).initCapacity(gpa, 128);
    defer normals.deinit(gpa);
    var tex_coords = try std.ArrayList(math.Vertex).initCapacity(gpa, 128);
    defer tex_coords.deinit(gpa);
    var faces = try std.ArrayList([3][4]math.Index).initCapacity(gpa, 128);
    defer faces.deinit(gpa);
    var nodes = try std.ArrayList(Mesh.Node).initCapacity(gpa, 16);
    defer nodes.deinit(gpa);

    var face_len: usize = 0;
    var face_elem_len: usize = 0;
    var elems_present: std.bit_set.IntegerBitSet(3) = .initEmpty();

    while (reader.interface.takeDelimiterExclusive('\n')) |full_line| {
        const line = str.trim(full_line);
        if (line.len == 0) continue;
        if (line[0] == '#') continue;
        var iter = str.splitScalar(line, ' ');
        if (iter.next()) |cmd| {
            if (str.eql(cmd, "v")) {
                elems_present.set(0);
                const vertex = try parseVertex(&iter);
                try verts.append(gpa, vertex);
            } else if (str.eql(cmd, "vt")) {
                elems_present.set(1);
                const vertex = try parseVertex(&iter);
                try tex_coords.append(gpa, vertex);
            } else if (str.eql(cmd, "vn")) {
                elems_present.set(2);
                const vertex = try parseVertex(&iter);
                try normals.append(gpa, vertex);
            } else if (str.eql(cmd, "f")) {
                const face = try parseFace(&iter);
                const max_idx: [3]usize = .{ verts.items.len, tex_coords.items.len, normals.items.len };
                if (face_elem_len == 0) face_elem_len = face.elem_len;
                if (face_len == 0) face_len = face.len;
                assert(face.elem_len == face_elem_len);
                assert(face.len == face_len);
                for (0..face_elem_len) |elem_n| {
                    // TODO: Skippable texture coordinates
                    if (!elems_present.isSet(elem_n)) continue;
                    for (0..face_len) |n| {
                        if (face.data[elem_n][n] >= max_idx[elem_n]) return error.InvalidIndex;
                    }
                    try faces.append(gpa, face.data);
                }
            } else if (str.eql(cmd, "s")) {
                try nodes.append(gpa, .{
                    .offset = faces.items.len,
                    .meta = .{ .smoothing = try parseSmoothing(&iter) },
                });
            } else if (str.eql(cmd, "o")) {
                try nodes.append(gpa, .{
                    .offset = faces.items.len,
                    .meta = .{ .object = try str.dupe(str.trimRest(&iter)) },
                });
            } else if (str.eql(cmd, "g")) {
                try nodes.append(gpa, .{
                    .offset = faces.items.len,
                    .meta = .{ .group = try str.dupe(str.trimRest(&iter)) },
                });
            } else if (str.eql(cmd, "usemtl")) {
                try nodes.append(gpa, .{
                    .offset = faces.items.len,
                    .meta = .{ .material = try str.dupe(str.trimRest(&iter)) },
                });
            } else if (str.eql(cmd, "mtllib")) {
                if (result.mtl_path != null) return error.DuplicateCommand;
                result.mtl_path = try str.dupe(str.trimRest(&iter));
            } else {
                log.err("\"{s}\"", .{line});
                return error.SyntaxError;
            }
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.StreamTooLong,
        error.ReadFailed,
        => |e| return e,
    }

    const elems: [3][]const math.Vertex = .{ verts.items, tex_coords.items, normals.items };
    const order: []const usize = switch (face_len) {
        2 => &.{ 0, 1 },
        3 => &.{ 0, 1, 2 },
        4 => &.{ 0, 1, 2, 0, 2, 3 },
        else => unreachable,
    };
    var node_n: usize = 0;
    for (faces.items, 0..) |face, face_n| {
        while (node_n < nodes.items.len) {
            if (nodes.items[node_n].offset == face_n) {
                const node = nodes.items[node_n];
                try result.mesh.appendMeta(node.meta, .vert);
                node_n += 1;
            } else break;
        }
        for (order) |n| {
            for (0..face_elem_len) |elem_n| {
                try result.mesh.appendVertices(math.Vertex, &.{
                    elems[elem_n][face[elem_n][n]],
                });
            }
        }
    }
    return result;
}

fn parseVertex(iter: *str.ScalarIterator) !math.Vertex {
    var result = math.Vertex{ 0, 0, 0 };
    var step: usize = 0;
    while (iter.next()) |token| {
        if (token.len == 0) continue;
        switch (step) {
            0, 1, 2 => result[step] = std.fmt.parseFloat(math.Scalar, token) catch return error.ParseFloatError,
            3 => log.warn("loaded 4th component of a 3-element vertex", .{}),
            else => return error.TooManyArguments,
        }
        step += 1;
    }

    if (step < 3) return error.NotEnoughArguments;
    return result;
}

const Face = struct {
    len: usize = 0,
    elem_len: usize = 0,
    data: [3][4]math.Index = @splat(@splat(math.invalid_index)),
};

fn parseFace(iter: *str.ScalarIterator) !Face {
    var result: Face = .{};
    var step: usize = 0;

    while (iter.next()) |token| {
        if (token.len == 0) continue;
        if (step >= 4) return error.TooManyArguments;
        const index = try parseIndex(token);
        if (step == 0) result.elem_len = index.elem_len;
        assert(result.elem_len == index.elem_len);
        for (0..result.elem_len) |elem_n| result.data[elem_n][step] = index.data[elem_n];
        step += 1;
    }

    result.len = step;
    if (result.len <= 1) return error.NotEnoughArguments;
    return result;
}

const Index = struct {
    elem_len: usize = 0,
    data: [3]math.Index = @splat(math.invalid_index),
};

fn parseIndex(line: []const u8) !Index {
    var result: Index = .{};
    var step: usize = 0;

    var iter = str.splitScalar(line, '/');
    while (iter.next()) |token| : (step += 1) {
        if (token.len == 0) continue;
        if (step >= 3) return error.TooManyArguments;
        const index = std.fmt.parseInt(math.Index, token, 10) catch return error.ParseIntError;
        result.data[step] = index - 1;
        result.elem_len = step + 1;
    }

    if (result.elem_len == 0) return error.NotEnoughArguments;
    return result;
}

fn parseSmoothing(iter: *str.ScalarIterator) !u32 {
    if (iter.next()) |token| {
        if (str.eql(token, "off")) {
            return 0;
        } else {
            return std.fmt.parseInt(u32, token, 10) catch return error.ParseIntError;
        }
    }
    return error.NotEnoughArguments;
}
