const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const math = @import("../math.zig");
const Mesh = @import("Mesh.zig");
const str = @import("../str.zig");

const log = std.log.scoped(.gfx_obj_loader);

const VertData = [AttrType.arr_len]math.Vertex;
const IndexData = [AttrType.arr_len]math.Index;
const FaceData = [ObjFaceType.arr_len]IndexData;
const Verts = std.ArrayList(math.Vertex);
const Faces = std.ArrayList(Face);
const Nodes = std.ArrayList(Mesh.Node);
const AttrVerts = std.EnumArray(AttrType, Verts);
const AttrsPresent = std.EnumSet(AttrType);

pub const ObjInfo = struct {
    mesh: Mesh,
    mtl_path: ?[:0]const u8,
    face_type: FaceType,
    attrs_present: AttrsPresent = .initEmpty(),
};

const Face = struct {
    face_type: ObjFaceType = .invalid,
    attrs_present: AttrsPresent = .initEmpty(),
    data: FaceData = @splat(@splat(math.invalid_index)),
};

const Index = struct {
    attrs_present: AttrsPresent = .initEmpty(),
    data: IndexData = @splat(math.invalid_index),
};

const FaceType = enum(u8) {
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

const face_vert_orders: std.EnumArray(ObjFaceType, []const []const u8) = .init(.{
    .invalid = &.{},
    .point = &.{&.{0}},
    .line = &.{&.{ 0, 1 }},
    .triangle = &.{&.{ 0, 1, 2 }},
    .quad = &.{ &.{ 0, 1, 2 }, &.{ 0, 2, 3 } },
});

const face_vert_counts: std.EnumArray(ObjFaceType, usize) = .init(.{
    .invalid = 0,
    .point = 1,
    .line = 2,
    .triangle = 3,
    .quad = 6,
});

const face_types_from_obj: std.EnumArray(ObjFaceType, FaceType) = .init(.{
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
attrs_present: AttrsPresent = .initEmpty(),

const Self = @This();

pub fn loadFile(allocator: std.mem.Allocator, path: []const u8) !ObjInfo {
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const buf = try allocators.scratch().alloc(u8, 1 << 8);
    defer allocators.scratch().free(buf);
    var reader = file.reader(buf);

    var self: Self = try .init(allocator);
    defer self.deinit();

    while (reader.interface.takeDelimiterExclusive('\n')) |line| {
        try self.parseLine(str.trim(line));
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.StreamTooLong, error.ReadFailed => |e| return e,
    }

    return self.createInfo();
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
            if (self.attrs_present.eql(.initEmpty())) self.attrs_present = face.attrs_present;
            assert(face.face_type == self.face_type);
            assert(face.attrs_present.eql(self.attrs_present));
            // TODO: Implement face groups
            try self.faces.append(self.allocator, face);
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

fn createInfo(self: *const Self) !ObjInfo {
    var result: ObjInfo = .{
        .mesh = try .init(self.allocator),
        .mtl_path = self.mtl_path,
        .face_type = face_types_from_obj.get(self.face_type),
        .attrs_present = self.attrs_present,
    };
    errdefer result.mesh.freeCpuData();

    try self.processFaces(&result);

    assert(vert_count == result.mesh.vert_count);
    return result;
}

fn processFaces(self: *const Self, result: *ObjInfo) !void {
    assert(self.attrs_present.contains(.vertex));
    return switch (self.attrs_present.contains(.tex_coord)) {
        inline else => |has_tex_coord| switch (self.attrs_present.contains(.normal)) {
            inline else => |has_normal| switch (result.face_type) {
                inline else => |face_type| ProcessFaces(.{
                    .has_tex_coord = has_tex_coord,
                    .has_normal = has_normal,
                    .face_type = face_type,
                }).processFaces(self, result),
            },
        },
    };
}

fn ProcessFaces(comptime config: struct {
    has_tex_coord: bool,
    has_normal: bool,
    face_type: FaceType,
}) type {
    return struct {
        fn processFaces(
            self: *const Self,
            result: *ObjInfo,
        ) !void {
            const face_vert_count = face_vert_counts.get(self.face_type);
            const vert_count = self.faces.items.len * face_vert_count;
            try result.mesh.ensureVerticesUnusedCapacity(math.Vertex, vert_count * AttrType.arr_len);

            const vert_orders = face_vert_orders.get(self.face_type);
            const vert_data: [AttrType.arr_len][]const math.Vertex = .{
                self.attr_verts.getPtrConst(.vertex).items,
                self.attr_verts.getPtrConst(.tex_coord).items,
                self.attr_verts.getPtrConst(.normal).items,
            };

            var node_n: usize = 0;
            for (self.faces.items, 0..) |*face, face_n| {
                while (node_n < self.nodes.items.len) {
                    if (self.nodes.items[node_n].offset == face_n) {
                        const node = self.nodes.items[node_n];
                        try result.mesh.appendMeta(node.meta, .vertex);
                        node_n += 1;
                    } else break;
                }

                for (vert_orders) |vert_order| {
                    const normal = computeNormal(vert_data[0], &face.data, vert_order);
                    for (vert_order) |vert_n| {
                        result.mesh.appendVerticesAssumeCapacity(math.Vertex, &getVertices(
                            vert_data,
                            &face.data,
                            &normal,
                            vert_n,
                        ));
                        result.mesh.vert_count += 1;
                    }
                }
            }
        }

        inline fn computeNormal(
            verts: []const math.Vertex,
            face: *const FaceData,
            vert_order: []const u8,
        ) math.Vertex {
            if (comptime !config.has_normal and config.face_type == .triangle) {
                var normal: math.Vertex = undefined;
                const v = [3]*const math.Vertex{
                    getVertex(verts, face, 0, vert_order[0]),
                    getVertex(verts, face, 0, vert_order[1]),
                    getVertex(verts, face, 0, vert_order[2]),
                };
                var lhs = v[1].*;
                var rhs = v[2].*;
                math.vertex.sub(&lhs, v[0]);
                math.vertex.sub(&rhs, v[0]);
                math.vertex.cross(&normal, &lhs, &rhs);
                math.vertex.normalize(&normal);
                return normal;
            } else {
                return math.vertex.zero;
            }
        }

        inline fn getVertices(
            vert_data: [AttrType.arr_len][]const math.Vertex,
            face: *const FaceData,
            normal: *const math.Vertex,
            vert_n: u8,
        ) VertData {
            return .{
                getVertex(vert_data[0], face, 0, vert_n).*,
                if (comptime config.has_tex_coord)
                    getVertex(vert_data[1], face, 1, vert_n).*
                else
                    math.vertex.zero,
                if (comptime config.has_normal)
                    getVertex(vert_data[2], face, 2, vert_n).*
                else
                    normal.*,
            };
        }
    };
}

inline fn getVertex(
    verts: []const math.Vertex,
    face: *const FaceData,
    attr_n: u8,
    vert_n: u8,
) *const math.Vertex {
    assert(attr_n < AttrType.arr_len);
    assert(vert_n < ObjFaceType.arr_len);
    const idx = face[vert_n][attr_n];
    assert(idx < verts.len);
    return &verts[idx];
}

fn parseVertex(iter: *str.ScalarIterator) !math.Vertex {
    var result = math.vertex.zero;
    var n: usize = 0;

    while (iter.next()) |token| {
        if (token.len == 0) continue;
        switch (n) {
            0, 1, 2 => result[n] = std.fmt.parseFloat(math.Scalar, token) catch return error.ParseFloatError,
            3 => log.warn("loaded 4th component of a 3-element vertex", .{}),
            else => return error.TooManyArguments,
        }
        n += 1;
    }

    if (n < math.vertex.len) return error.NotEnoughArguments;
    return result;
}

fn parseFace(iter: *str.ScalarIterator) !Face {
    var result: Face = .{};
    var n: u8 = 0;

    while (iter.next()) |token| {
        if (token.len == 0) continue;
        if (n >= ObjFaceType.arr_len) return error.TooManyArguments;
        const index = try parseIndex(token);
        if (result.attrs_present.eql(.initEmpty())) result.attrs_present = index.attrs_present;
        assert(result.attrs_present.eql(index.attrs_present));
        result.data[n] = index.data;
        n += 1;
    }

    if (n < ObjFaceType.arr_min) return error.NotEnoughArguments;
    result.face_type = @enumFromInt(n);
    return result;
}

fn parseIndex(line: []const u8) !Index {
    var result: Index = .{};
    var iter = str.splitScalar(line, '/');
    var n: u8 = 0;

    while (iter.next()) |token| : (n += 1) {
        if (token.len == 0) continue;
        if (n >= AttrType.arr_len) return error.TooManyArguments;
        const index = std.fmt.parseInt(math.Index, token, 10) catch return error.ParseIntError;
        result.attrs_present.insert(@enumFromInt(n));
        result.data[n] = index - 1;
    }

    if (n < AttrType.arr_min) return error.NotEnoughArguments;
    return result;
}

fn parseSmoothing(iter: *str.ScalarIterator) !u32 {
    if (iter.next()) |token| {
        return if (str.eql(token, "off")) 0 else std.fmt.parseInt(u32, token, 10) catch error.ParseIntError;
    }
    return error.NotEnoughArguments;
}
