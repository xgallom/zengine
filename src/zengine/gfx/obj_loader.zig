//!
//! The zengine .obj file loader
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const math = @import("../math.zig");
const MeshBuffer = @import("MeshBuffer.zig");
const Object = @import("Object.zig");
const str = @import("../str.zig");

const log = std.log.scoped(.gfx_obj_loader);

const VertData = [AttrType.arr_len]math.Vertex;
const IndexData = [AttrType.arr_len]math.Index;
const FaceData = [ObjFaceType.arr_len]IndexData;
const FaceNormals = [Object.FaceType.arr_len + 1]math.Vertex;
const Verts = std.ArrayList(math.Vertex);
const Faces = std.ArrayList(Face);
const Nodes = std.ArrayList(Node);
const AttrVerts = AttrArray(Verts);
const AttrsPresent = std.EnumSet(AttrType);

fn AttrArray(comptime T: type) type {
    return std.EnumArray(AttrType, T);
}

const Face = struct {
    face_type: ObjFaceType = .invalid,
    attrs_present: AttrsPresent = .initEmpty(),
    data: FaceData = @splat(@splat(math.invalid_index)),
};

const Index = struct {
    attrs_present: AttrsPresent = .initEmpty(),
    data: IndexData = @splat(math.invalid_index),
};

pub const Node = struct {
    offset: usize,
    len: usize = 0,
    meta: Meta,

    pub const Target = enum {};

    pub const Type = enum {
        object,
        group,
        smoothing,
        material,
    };

    pub const Meta = union(Type) {
        object: Meta.Object,
        group: [:0]const u8,
        smoothing: u32,
        material: [:0]const u8,

        pub const Object = struct {
            name: [:0]const u8,
            face_type: ObjFaceType = .invalid,
            attrs_present: AttrsPresent = .initEmpty(),

            pub fn isDefault(o: *const Meta.Object) bool {
                return o.name.len == 0;
            }
        };
    };
};

pub const ObjInfo = struct {
    mesh_buf: MeshBuffer,
    objects: std.StringArrayHashMapUnmanaged(Object),
    mtl_path: ?[:0]const u8,

    pub fn deinit(self: *ObjInfo, allocator: std.mem.Allocator) void {
        self.mesh_buf.freeCpuData();
        for (self.objects.values()) |*object| object.deinit();
        self.cleanup(allocator);
    }

    pub fn cleanup(self: *ObjInfo, allocator: std.mem.Allocator) void {
        self.objects.deinit(allocator);
    }
};

const ObjFaceType = enum(u8) {
    invalid,
    point,
    line,
    triangle,
    quad,
    const arr_min = 3;
    const arr_len = 4;
};

const AttrType = enum(u8) {
    vertex,
    tex_coord,
    normal,
    const arr_min = 1;
    const arr_len = 3;
};

const smoothing_groups_len = 32;

const obj_face_vert_orders: std.EnumArray(ObjFaceType, []const []const u8) = .init(.{
    .invalid = &.{},
    .point = &.{&.{0}},
    .line = &.{&.{ 0, 1 }},
    .triangle = &.{&.{ 0, 1, 2 }},
    .quad = &.{ &.{ 0, 1, 2 }, &.{ 0, 2, 3 } },
});

const face_types_from_obj: std.EnumArray(ObjFaceType, Object.FaceType) = .init(.{
    .invalid = .invalid,
    .point = .invalid,
    // TODO: Implement line
    .line = .invalid,
    .triangle = .triangle,
    .quad = .triangle,
});

const face_vert_counts: std.EnumArray(Object.FaceType, usize) = .init(.{
    .invalid = 0,
    .point = 1,
    .line = 2,
    .triangle = 3,
});

allocator: std.mem.Allocator,
attr_verts: AttrVerts,
faces: Faces,
nodes: Nodes,
mtl_path: ?[:0]const u8 = null,
obj_idx: usize = 0,

const Self = @This();

pub fn loadFile(allocator: std.mem.Allocator, path: []const u8) !ObjInfo {
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const buf = try allocators.scratch().alloc(u8, 1 << 8);
    defer allocators.scratch().free(buf);
    var reader = file.reader(buf);

    var self: Self = try .init(allocator);
    defer self.deinit();

    self.nodes.appendAssumeCapacity(.{
        .offset = 0,
        .meta = .{ .object = .{ .name = "" } },
    });

    while (reader.interface.takeDelimiterExclusive('\n')) |line| {
        try self.parseLine(str.trim(line));
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.StreamTooLong, error.ReadFailed => |e| return e,
    }

    const obj_node = self.activeObjectNode();
    obj_node.len = self.faces.items.len - obj_node.offset;
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

fn activeObjectNode(self: *const Self) *Node {
    return &self.nodes.items[self.obj_idx];
}

fn activeObject(self: *const Self) *Node.Meta.Object {
    return &self.activeObjectNode().meta.object;
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
            const obj = self.activeObject();
            if (obj.face_type == .invalid) obj.face_type = face.face_type;
            if (obj.attrs_present.eql(.initEmpty())) obj.attrs_present = face.attrs_present;
            assert(obj.face_type == face.face_type);
            assert(obj.attrs_present.eql(face.attrs_present));
            var attr_iter = face.attrs_present.iterator();
            while (attr_iter.next()) |attr| {
                const len = self.attr_verts.getPtrConst(attr).items.len;
                for (0..@intFromEnum(face.face_type)) |vert_n| {
                    const idx = getFaceIndex(&face.data, @intCast(vert_n), attr);
                    assert(idx < len);
                }
            }
            try self.faces.append(self.allocator, face);
        } else if (str.eql(cmd, "s")) {
            try self.nodes.append(self.allocator, .{
                .offset = self.faces.items.len,
                .meta = .{ .smoothing = try parseSmoothing(&iter) },
            });
        } else if (str.eql(cmd, "o")) {
            const obj = self.activeObject();
            if (obj.isDefault()) {
                @branchHint(.cold);
                assert(self.faces.items.len == 0);
                obj.name = try str.dupeZ(str.trimRest(&iter));
            } else {
                const obj_node = self.activeObjectNode();
                obj_node.len = self.faces.items.len - obj_node.offset;
                self.obj_idx = self.nodes.items.len;
                try self.nodes.append(self.allocator, .{
                    .offset = self.faces.items.len,
                    .meta = .{ .object = .{ .name = try str.dupeZ(str.trimRest(&iter)) } },
                });
            }
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

    // TODO: Parse different vertex types
    if (n < 1) return error.NotEnoughArguments;
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
        if (str.eql(token, "off")) {
            return 0;
        } else {
            return std.fmt.parseInt(u32, token, 10) catch error.ParseIntError;
        }
    }
    return error.NotEnoughArguments;
}

const CreateInfoState = struct {
    vert_idx: usize = 0,
    node_n: usize = 0,
    face_n: usize = 0,
    material_active: ?[:0]const u8 = null,
    smoothing_groups_active: std.bit_set.IntegerBitSet(smoothing_groups_len) = .initEmpty(),
    vert_data: AttrArray([]const math.Vertex),
    face_normals: std.ArrayList(math.Vertex) = .empty,
    smoothing_groups: [smoothing_groups_len]std.AutoHashMapUnmanaged(
        math.Index,
        std.ArrayList(usize),
    ) = @splat(.empty),

    fn init(self: *const Self) CreateInfoState {
        return .{
            .vert_data = .init(.{
                .vertex = self.attr_verts.getPtrConst(.vertex).items,
                .tex_coord = self.attr_verts.getPtrConst(.tex_coord).items,
                .normal = self.attr_verts.getPtrConst(.normal).items,
            }),
        };
    }

    fn deinit(state: *CreateInfoState, self: *const Self) void {
        state.face_normals.deinit(self.allocator);
        for (&state.smoothing_groups) |*group| {
            var iter = group.valueIterator();
            while (iter.next()) |list| list.deinit(self.allocator);
            group.deinit(self.allocator);
        }
    }
};

fn createInfo(self: *const Self) !ObjInfo {
    var result: ObjInfo = .{
        .mesh_buf = try .init(self.allocator, .vertex),
        .objects = .empty,
        .mtl_path = self.mtl_path,
    };
    errdefer result.deinit(self.allocator);

    var state: CreateInfoState = .init(self);
    defer state.deinit(self);

    while (state.node_n < self.nodes.items.len) {
        const node = self.nodes.items[state.node_n];
        state.node_n += 1;
        switch (node.meta) {
            .object => try self.processFaces(&result, &state, node),
            .group => {
                log.err("group node is outside of an object", .{});
                unreachable;
            },
            .smoothing => |smoothing| state.smoothing_groups_active.mask = smoothing,
            .material => |material| state.material_active = material,
        }
    }

    {
        var iter = result.objects.iterator();
        while (iter.next()) |e| {
            const name = e.key_ptr.*;
            const object = e.value_ptr;
            log.info("{s}: {any}", .{ name, object.sections.items });
            var g_iter = object.groups.iterator();
            while (g_iter.next()) |ge| {
                const group_name = ge.key_ptr.*;
                const group = ge.value_ptr.*;
                log.info("  {s}: {any}", .{ group_name, group });
            }
        }
    }
    return result;
}

fn processFaces(self: *const Self, result: *ObjInfo, state: *CreateInfoState, obj_node: Node) !void {
    const obj = obj_node.meta.object;
    assert(obj.face_type != .invalid);
    assert(obj.attrs_present.contains(.vertex));
    return switch (obj.attrs_present.contains(.tex_coord)) {
        inline else => |has_tex_coord| switch (obj.attrs_present.contains(.normal)) {
            inline else => |has_normal| switch (face_types_from_obj.get(obj.face_type)) {
                .invalid => assert(false),
                inline else => |face_type| ProcessFaces(.{
                    .has_tex_coord = has_tex_coord,
                    .has_normal = has_normal,
                    .face_type = face_type,
                }).processFaces(
                    self,
                    result,
                    state,
                    obj_node.offset,
                    obj_node.len,
                    obj,
                ),
            },
        },
    };
}

fn ProcessFaces(comptime config: struct {
    has_tex_coord: bool,
    has_normal: bool,
    face_type: Object.FaceType,
}) type {
    return struct {
        fn processFaces(
            self: *const Self,
            result: *ObjInfo,
            state: *CreateInfoState,
            faces_offset: usize,
            faces_len: usize,
            obj: Node.Meta.Object,
        ) !void {
            const oe = try result.objects.getOrPutValue(
                self.allocator,
                obj.name,
                .init(self.allocator, config.face_type),
            );
            assert(!oe.found_existing);
            const object = oe.value_ptr;
            errdefer object.deinit();

            try object.beginSection(state.vert_idx, state.material_active);
            defer {
                object.endSection(state.vert_idx);
                object.endGroup();
                assert(!object.has_active_section and !object.has_active_group);
            }

            const faces = self.faces.items[faces_offset .. faces_offset + faces_len];
            const vert_orders = obj_face_vert_orders.get(obj.face_type);
            const face_vert_count = face_vert_counts.get(config.face_type);
            const face_count = faces.len * vert_orders.len;
            const vert_offset = state.vert_idx;
            const vert_count = face_count * face_vert_count;

            try result.mesh_buf.ensureVerticesUnusedCapacity(math.Vertex, vert_count * AttrType.arr_len);
            try state.face_normals.ensureUnusedCapacity(self.allocator, vert_count);

            for (faces) |*face| {
                while (state.node_n < self.nodes.items.len) {
                    if (self.nodes.items[state.node_n].offset == state.face_n) {
                        const node = self.nodes.items[state.node_n];
                        switch (node.meta) {
                            .object => {
                                log.err("object node is inside of an object", .{});
                                unreachable;
                            },
                            .group => |name| try object.beginGroup(name, state.vert_idx),
                            .smoothing => |smoothing| state.smoothing_groups_active.mask = smoothing,
                            .material => |material| {
                                state.material_active = material;
                                try object.beginSection(state.vert_idx, state.material_active);
                            },
                        }
                        state.node_n += 1;
                    } else break;
                }

                for (vert_orders) |vert_order| {
                    const vert_normals = computeFaceNormals(
                        state.vert_data.get(.vertex),
                        &face.data,
                        vert_order,
                    );

                    for (vert_order, 0..) |vert_n, n| {
                        if (comptime canComputeNormals()) {
                            const idx_n = getFaceIndex(&face.data, vert_n, .vertex);

                            var iter = state.smoothing_groups_active.iterator(.{});
                            while (iter.next()) |sg| {
                                const group = &state.smoothing_groups[sg];
                                const e = try group.getOrPutValue(self.allocator, idx_n, .empty);
                                const list = e.value_ptr;
                                try list.append(self.allocator, state.vert_idx);
                            }

                            state.face_normals.appendAssumeCapacity(vert_normals[n]);
                        }

                        const vertices = getFaceVertices(state.vert_data, &face.data, &vert_normals[3], vert_n);
                        result.mesh_buf.appendVerticesAssumeCapacity(math.Vertex, &vertices);
                        result.mesh_buf.vert_count += 1;
                        state.vert_idx += 1;
                    }
                }

                state.face_n += 1;
            }

            assert(vert_count == state.vert_idx - vert_offset);

            if (comptime canComputeNormals()) {
                const verts = result.mesh_buf.vertices();
                for (&state.smoothing_groups) |group| {
                    var sg_iter = group.valueIterator();
                    while (sg_iter.next()) |vert_list| {
                        var avg = math.vertex.zero;
                        for (vert_list.items) |vert_idx| {
                            math.vertex.add(&avg, &state.face_normals.items[vert_idx]);
                        }
                        math.vertex.normalize(&avg);
                        for (vert_list.items) |vert_idx| getVertex(verts, vert_idx, .normal).* = avg;
                    }
                }
            }

            // switch (config.smoothing) {
            //     0 => {},
            //     1 => {
            //         for (vert_indexes.values()) |vert_index| {
            //             var avg = math.vertex.zero;
            //             for (vert_index.items) |vert_idx| {
            //                 const idx = AttrType.arr_len * vert_idx;
            //                 const face_item = verts[idx .. idx + AttrType.arr_len];
            //                 math.vertex.add(&avg, &face_item[@intFromEnum(AttrType.normal)]);
            //             }
            //             math.vertex.normalize(&avg);
            //             for (vert_index.items) |vert_idx| {
            //                 const idx = AttrType.arr_len * vert_idx;
            //                 const face_item = verts[idx .. idx + AttrType.arr_len];
            //                 face_item[@intFromEnum(AttrType.normal)] = avg;
            //             }
            //         }
            //     },
            //     2 => {},
            //     else => log.warn("ignoring mesh smoothing {}", .{config.smoothing}),
            // }
        }

        fn canComputeNormals() bool {
            return config.face_type == .triangle;
        }

        inline fn computeFaceNormals(
            verts: []const math.Vertex,
            face: *const FaceData,
            vert_order: []const u8,
        ) FaceNormals {
            if (comptime canComputeNormals()) {
                var normals: FaceNormals = undefined;

                const v = [3]*const math.Vertex{
                    getFaceVertex(verts, face, vert_order[0], .vertex),
                    getFaceVertex(verts, face, vert_order[1], .vertex),
                    getFaceVertex(verts, face, vert_order[2], .vertex),
                };

                var lhs = v[1].*;
                var rhs = v[2].*;
                math.vertex.sub(&lhs, v[0]);
                math.vertex.sub(&rhs, v[0]);

                math.vertex.cross(&normals[3], &lhs, &rhs);
                math.vertex.normalize(&normals[3]);

                normals[0] = normals[3];
                normals[1] = normals[3];
                normals[2] = normals[3];

                math.vertex.scale(&normals[0], math.vertex.angle(&lhs, &rhs));

                lhs = v[2].*;
                rhs = v[0].*;
                math.vertex.sub(&lhs, v[1]);
                math.vertex.sub(&rhs, v[1]);
                math.vertex.scale(&normals[1], math.vertex.angle(&lhs, &rhs));

                lhs = v[0].*;
                rhs = v[1].*;
                math.vertex.sub(&lhs, v[2]);
                math.vertex.sub(&rhs, v[2]);
                math.vertex.scale(&normals[2], math.vertex.angle(&lhs, &rhs));

                return normals;
            } else {
                return @splat(math.vertex.zero);
            }
        }

        inline fn getFaceVertices(
            vert_data: AttrArray([]const math.Vertex),
            face: *const FaceData,
            normal: *const math.Vertex,
            vert_n: u8,
        ) VertData {
            return .{
                getFaceVertex(vert_data.get(.vertex), face, vert_n, .vertex).*,
                if (comptime config.has_tex_coord)
                    getFaceVertex(vert_data.get(.tex_coord), face, vert_n, .tex_coord).*
                else
                    math.vertex.zero,
                if (comptime config.has_normal)
                    getFaceVertex(vert_data.get(.normal), face, vert_n, .normal).*
                else
                    normal.*,
            };
        }
    };
}

inline fn getVertex(
    verts: []math.Vertex,
    vert_idx: usize,
    attr: AttrType,
) *math.Vertex {
    const idx = getVertIndex(vert_idx, attr);
    assert(idx < verts.len);
    return &verts[idx];
}

inline fn getVertexConst(
    verts: []const math.Vertex,
    vert_idx: usize,
    attr: AttrType,
) *const math.Vertex {
    const idx = getVertIndex(vert_idx, attr);
    assert(idx < verts.len);
    return &verts[idx];
}

inline fn getFaceVertex(
    verts: []const math.Vertex,
    face: *const FaceData,
    vert_n: u8,
    attr: AttrType,
) *const math.Vertex {
    const idx = getFaceIndex(face, vert_n, attr);
    assert(idx < verts.len);
    return &verts[idx];
}

inline fn getVertIndex(vert_idx: usize, attr: AttrType) usize {
    return vert_idx * AttrType.arr_len + @intFromEnum(attr);
}

inline fn getFaceIndex(face: *const FaceData, vert_n: u8, attr: AttrType) math.Index {
    assert(vert_n < ObjFaceType.arr_len);
    return face[vert_n][@intFromEnum(attr)];
}
