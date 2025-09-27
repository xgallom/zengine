const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const math = @import("../math.zig");
const Mesh = @import("Mesh.zig");
const str = @import("../str.zig");

const log = std.log.scoped(.gfx_obj_loader);

const IndexData = [AttrType.arr_len]math.Index;
const FaceData = [ObjFaceType.arr_len]IndexData;
const Verts = std.ArrayList(math.Vertex);
const Faces = std.ArrayList(FaceData);
const Nodes = std.ArrayList(Mesh.Node);
const AttrVerts = std.EnumArray(AttrType, Verts);

pub const MeshInfo = struct {
    mesh: Mesh,
    mtl_path: ?[:0]const u8,
    face_type: MeshFaceType,
    attr_len: u8,
};

const Face = struct {
    data: FaceData = @splat(@splat(math.invalid_index)),
    face_type: ObjFaceType = .invalid,
    attr_len: u8 = 0,
};

const Index = struct {
    data: IndexData = @splat(math.invalid_index),
    attr_len: u8 = 0,
};

const MeshFaceType = enum(u8) {
    invalid,
    point,
    line,
    triangle,
    const arr_len = 3;
};

const ObjFaceType = enum(u8) {
    invalid,
    point,
    line,
    triangle,
    quad,
    const arr_min = 2;
    const arr_len = 4;
};

const AttrType = enum(u8) {
    vertex,
    tex_coord,
    normal,
    const arr_min = 1;
    const arr_len = 3;
};

const vert_orders: std.EnumArray(ObjFaceType, []const []const u8) = .init(.{
    .invalid = &.{},
    .point = &.{&.{0}},
    .line = &.{&.{ 0, 1 }},
    .triangle = &.{&.{ 0, 1, 2 }},
    .quad = &.{ &.{ 0, 1, 2 }, &.{ 0, 2, 3 } },
});

const vert_counts: std.EnumArray(ObjFaceType, usize) = .init(.{
    .invalid = 0,
    .point = 1,
    .line = 2,
    .triangle = 3,
    .quad = 6,
});

const mesh_face_types: std.EnumArray(ObjFaceType, MeshFaceType) = .init(.{
    .invalid = .invalid,
    .point = .invalid,
    // TODO: Implement lines
    .line = .invalid,
    .triangle = .triangle,
    .quad = .triangle,
});

allocator: std.mem.Allocator,
attr_verts: AttrVerts,
faces: Faces,
nodes: Nodes,
mtl_path: ?[:0]const u8 = null,
face_type: ObjFaceType = .invalid,
attr_len: u8 = 0,

const Self = @This();

pub fn loadFile(allocator: std.mem.Allocator, path: []const u8) !MeshInfo {
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const buf = try allocators.scratch().alloc(u8, 1 << 8);
    var reader = file.reader(buf);

    var self: Self = try .init(allocator);
    defer self.deinit();

    while (reader.interface.takeDelimiterExclusive('\n')) |line| {
        try self.parseLine(str.trim(line));
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.StreamTooLong, error.ReadFailed => |e| return e,
    }

    return self.createMesh();
}

fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .allocator = allocator,
        .attr_verts = .init(.{
            .vertex = try .initCapacity(allocator, 128),
            .tex_coord = try .initCapacity(allocator, 128),
            .normal = try .initCapacity(allocator, 128),
        }),
        .faces = try .initCapacity(allocator, 128),
        .nodes = try .initCapacity(allocator, 16),
    };
}

fn deinit(self: *Self) void {
    for (&self.attr_verts.values) |*verts| verts.deinit(self.allocator);
    self.faces.deinit(self.allocator);
    self.nodes.deinit(self.allocator);
}

fn parseLine(self: *Self, line: []const u8) !void {
    if (line.len == 0) return;
    if (line[0] == '#') return;
    var iter = str.splitScalar(line, ' ');
    if (iter.next()) |cmd| {
        if (str.eql(cmd, "v")) {
            const vertex = try parseVertex(&iter);
            try self.attr_verts.getPtr(.vertex).append(self.allocator, vertex);
        } else if (str.eql(cmd, "vt")) {
            const vertex = try parseVertex(&iter);
            try self.attr_verts.getPtr(.tex_coord).append(self.allocator, vertex);
        } else if (str.eql(cmd, "vn")) {
            const vertex = try parseVertex(&iter);
            try self.attr_verts.getPtr(.normal).append(self.allocator, vertex);
        } else if (str.eql(cmd, "f")) {
            const face = try parseFace(&iter);
            if (self.face_type == .invalid) self.face_type = face.face_type;
            if (self.attr_len == 0) self.attr_len = face.attr_len;
            assert(face.face_type == self.face_type);
            assert(face.attr_len == self.attr_len);
            const max_idx = [AttrType.arr_len]usize{
                self.attr_verts.getPtr(.vertex).items.len,
                self.attr_verts.getPtr(.tex_coord).items.len,
                self.attr_verts.getPtr(.normal).items.len,
            };
            for (0..@intFromEnum(face.face_type)) |n| {
                for (0..face.attr_len) |attr_n| {
                    if (face.data[n][attr_n] >= max_idx[attr_n]) return error.InvalidIndex;
                }
            }
            try self.faces.append(self.allocator, face.data);
        } else if (str.eql(cmd, "s")) {
            try self.nodes.append(self.allocator, .{
                .offset = self.faces.items.len,
                .meta = .{ .smoothing = try parseSmoothing(&iter) },
            });
        } else if (str.eql(cmd, "o")) {
            try self.nodes.append(self.allocator, .{
                .offset = self.faces.items.len,
                .meta = .{ .object = try str.dupeZ(str.trimRest(&iter)) },
            });
        } else if (str.eql(cmd, "g")) {
            try self.nodes.append(self.allocator, .{
                .offset = self.faces.items.len,
                .meta = .{ .group = try str.dupeZ(str.trimRest(&iter)) },
            });
        } else if (str.eql(cmd, "usemtl")) {
            try self.nodes.append(self.allocator, .{
                .offset = self.faces.items.len,
                .meta = .{ .material = try str.dupeZ(str.trimRest(&iter)) },
            });
        } else if (str.eql(cmd, "mtllib")) {
            if (self.mtl_path != null) return error.DuplicateCommand;
            self.mtl_path = try str.dupeZ(str.trimRest(&iter));
        } else {
            log.err("\"{s}\"", .{line});
            return error.SyntaxError;
        }
    }
}

fn createMesh(self: *Self) !MeshInfo {
    var result: MeshInfo = .{
        .mesh = try .init(self.allocator),
        .mtl_path = self.mtl_path,
        .face_type = mesh_face_types.get(self.face_type),
        .attr_len = self.attr_len,
    };
    errdefer result.mesh.freeCpuData();

    const vert_order = vert_orders.get(self.face_type);
    const vert_count = vert_counts.get(self.face_type);
    const vert_data = [AttrType.arr_len][]const math.Vertex{
        self.attr_verts.getPtr(.vertex).items,
        self.attr_verts.getPtr(.tex_coord).items,
        self.attr_verts.getPtr(.normal).items,
    };

    const total_count = self.faces.items.len * vert_count;
    try result.mesh.ensureVerticesUnusedCapacity(math.Vertex, total_count * AttrType.arr_len);

    var node_n: usize = 0;
    for (self.faces.items, 0..) |*face, face_n| {
        while (node_n < self.nodes.items.len) {
            if (self.nodes.items[node_n].offset == face_n) {
                const node = self.nodes.items[node_n];
                try result.mesh.appendMeta(node.meta, .vertex);
                node_n += 1;
            } else break;
        }

        for (vert_order) |order| {
            var normal = math.vertex.zero;
            if (self.attr_len <= @intFromEnum(AttrType.normal)) {
                if (order.len == 3) {
                    const verts = self.attr_verts.getPtr(.vertex).items;
                    const attr_n = @intFromEnum(AttrType.vertex);
                    const v = [3]*const math.Vertex{
                        getVertex(verts, face, attr_n, order[0]),
                        getVertex(verts, face, attr_n, order[1]),
                        getVertex(verts, face, attr_n, order[2]),
                    };
                    var lhs = v[1].*;
                    var rhs = v[2].*;
                    math.vertex.sub(&lhs, v[0]);
                    math.vertex.sub(&rhs, v[0]);
                    math.vertex.cross(&normal, &lhs, &rhs);
                    math.vertex.normalize(&normal);
                }
            }

            for (order) |n| {
                result.mesh.appendVerticesAssumeCapacity(math.Vertex, switch (self.attr_len) {
                    1 => &.{
                        getVertex(vert_data[0], face, 0, n).*,
                        math.vertex.zero,
                        normal,
                    },
                    2 => &.{
                        getVertex(vert_data[0], face, 0, n).*,
                        getVertex(vert_data[1], face, 1, n).*,
                        normal,
                    },
                    3 => &.{
                        getVertex(vert_data[0], face, 0, n).*,
                        getVertex(vert_data[1], face, 1, n).*,
                        getVertex(vert_data[2], face, 2, n).*,
                    },
                    else => unreachable,
                });
                result.mesh.vert_len += 1;
            }
        }
    }

    assert(total_count == result.mesh.vert_len);
    return result;
}

inline fn getVertex(
    verts: []const math.Vertex,
    face: *const FaceData,
    attr_n: u8,
    n: u8,
) *const math.Vertex {
    assert(attr_n < AttrType.arr_len);
    assert(n < ObjFaceType.arr_len);
    const idx = face[n][attr_n];
    assert(idx < verts.len);
    return &verts[idx];
}

fn parseVertex(iter: *str.ScalarIterator) !math.Vertex {
    var result = math.vertex.zero;
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

fn parseFace(iter: *str.ScalarIterator) !Face {
    var result: Face = .{};
    var face_len: u8 = 0;

    while (iter.next()) |token| {
        if (token.len == 0) continue;
        if (face_len >= ObjFaceType.arr_len) return error.TooManyArguments;
        const index = try parseIndex(token);
        if (result.attr_len == 0) result.attr_len = index.attr_len;
        assert(result.attr_len == index.attr_len);
        result.data[face_len] = index.data;
        face_len += 1;
    }

    if (face_len < ObjFaceType.arr_min) return error.NotEnoughArguments;
    result.face_type = @enumFromInt(face_len);
    return result;
}

fn parseIndex(line: []const u8) !Index {
    var result: Index = .{};

    var iter = str.splitScalar(line, '/');
    while (iter.next()) |token| {
        if (token.len == 0) continue;
        if (result.attr_len >= AttrType.arr_len) return error.TooManyArguments;
        const index = std.fmt.parseInt(math.Index, token, 10) catch return error.ParseIntError;
        result.data[result.attr_len] = index - 1;
        result.attr_len += 1;
    }

    if (result.attr_len < AttrType.arr_min) return error.NotEnoughArguments;
    return result;
}

fn parseSmoothing(iter: *str.ScalarIterator) !u32 {
    if (iter.next()) |token| {
        return if (str.eql(token, "off")) 0 else std.fmt.parseInt(u32, token, 10) catch error.ParseIntError;
    }
    return error.NotEnoughArguments;
}
