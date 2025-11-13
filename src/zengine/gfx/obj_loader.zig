//!
//! The zengine .obj file loader
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const math = @import("../math.zig");
const gfx_options = @import("../options.zig").gfx_options;
const str = @import("../str.zig");
const CPUBuffer = @import("CPUBuffer.zig");
const mesh = @import("mesh.zig");

const log = std.log.scoped(.gfx_obj_loader);

// TODO: Implement disjoint mesh smoothing

const AttrType = enum {
    position,
    tex_coord,
    normal,
    const arr_min = 1;
    const arr_len = 3;
};

const smoothing_groups_len = 32;
// TODO: Implement line and point
const face_arr_min = 3;

const face_vert_orders: std.EnumArray(mesh.FaceType, []const []const u8) = .init(.{
    .invalid = &.{},
    .point = &.{&.{0}},
    .line = &.{&.{ 0, 1 }},
    .triangle = &.{&.{ 0, 1, 2 }},
});

allocator: std.mem.Allocator,
attr_verts: AttrVerts,
faces: Faces,
nodes: Nodes,
face_polygon: FacePolygon,
mtl_path: ?[:0]const u8 = null,
obj_idx: usize = 0,

const Self = @This();
const VertData = [AttrType.arr_len]math.Vector3;
const IndexData = [AttrType.arr_len]math.Index;
const FaceData = [mesh.FaceType.arr_len]IndexData;
const FaceNormals = [mesh.FaceType.arr_len + 2]math.Vector3;
const FaceTangents = [mesh.FaceType.arr_len]math.Vector3;
const Verts = std.ArrayList(math.Vector3);
const FacePolygon = std.ArrayList(IndexData);
const Faces = std.ArrayList(Face);
const Nodes = std.ArrayList(Node);
const AttrVerts = std.EnumArray(AttrType, Verts);
const AttrsPresent = std.EnumSet(AttrType);

const Face = struct {
    info: FaceInfo = .{},
    data: FaceData = @splat(@splat(math.invalid_index)),
};

const FaceInfo = struct {
    face_type: mesh.FaceType = .invalid,
    attrs_present: AttrsPresent = .initEmpty(),
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
        object: Object,
        group: [:0]const u8,
        smoothing: u32,
        material: [:0]const u8,

        pub const Object = struct {
            name: [:0]const u8,
            info: FaceInfo = .{},

            pub fn isDefault(obj: *const Object) bool {
                return obj.name.len == 0;
            }

            pub fn checkInfo(obj: *Object, info: FaceInfo) void {
                if (obj.info.face_type == .invalid) obj.info.face_type = info.face_type;
                if (obj.info.attrs_present.eql(.initEmpty())) obj.info.attrs_present = info.attrs_present;
                assert(obj.info.face_type == info.face_type);
            }
        };
    };
};

pub const ObjResult = struct {
    allocator: std.mem.Allocator,
    mesh_buf: CPUBuffer,
    mesh_objs: std.StringArrayHashMapUnmanaged(mesh.Object),
    mtl_path: ?[:0]const u8,

    pub fn deinit(self: *ObjResult) void {
        self.mesh_buf.free(self.allocator);
        for (self.mesh_objs.values()) |*object| object.deinit(self.allocator);
        self.cleanup();
    }

    pub fn cleanup(self: *ObjResult) void {
        self.mesh_objs.deinit(self.allocator);
    }
};

pub fn loadFile(allocator: std.mem.Allocator, path: []const u8) !ObjResult {
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const buf = try allocators.scratch().alloc(u8, 1 << 10);
    defer allocators.scratch().free(buf);
    var reader = file.reader(buf);

    var self: Self = try .init(allocator);
    defer self.deinit();

    self.nodes.appendAssumeCapacity(.{
        .offset = 0,
        .meta = .{ .object = .{ .name = "" } },
    });

    log.debug("reader: {}", .{try reader.getSize()});
    log.debug("started parsing {s}", .{path});
    var line_n: usize = 1;
    while (reader.interface.takeDelimiterInclusive('\n')) |line_full| {
        const line = str.trim(line_full);
        log.debug("parsing line {} \"{s}\"", .{ line_n, line });
        try self.parseLine(line);
        line_n += 1;
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.StreamTooLong, error.ReadFailed => |e| {
            log.err("failed parsing line {}: {t}", .{ line_n, e });
            return e;
        },
    }

    const obj_node = self.activeObjectNode();
    obj_node.len = self.faces.items.len - obj_node.offset;
    return self.createResult();
}

fn init(allocator: std.mem.Allocator) !Self {
    return .{
        .allocator = allocator,
        .attr_verts = .init(.{
            .position = try .initCapacity(allocator, 128),
            .tex_coord = try .initCapacity(allocator, 128),
            .normal = try .initCapacity(allocator, 128),
        }),
        .faces = try .initCapacity(allocator, 128),
        .face_polygon = try .initCapacity(allocator, 256),
        .nodes = try .initCapacity(allocator, 16),
    };
}

fn deinit(self: *Self) void {
    for (&self.attr_verts.values) |*verts| verts.deinit(self.allocator);
    self.faces.deinit(self.allocator);
    self.nodes.deinit(self.allocator);
    self.face_polygon.deinit(self.allocator);
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
            const vertex = try parseVector(&iter);
            log.debug("parsed position {}", .{self.attr_verts.getPtr(.position).items.len});
            try self.attr_verts.getPtr(.position).append(self.allocator, vertex);
        } else if (str.eql(cmd, "vt")) {
            const vertex = try parseVector(&iter);
            log.debug("parsed tex coord {}", .{self.attr_verts.getPtr(.tex_coord).items.len});
            try self.attr_verts.getPtr(.tex_coord).append(self.allocator, vertex);
        } else if (str.eql(cmd, "vn")) {
            const vertex = try parseVector(&iter);
            log.debug("parsed normal {}", .{self.attr_verts.getPtr(.normal).items.len});
            try self.attr_verts.getPtr(.normal).append(self.allocator, vertex);
        } else if (str.eql(cmd, "f")) {
            const face_info = try parseFace(&iter, &self.face_polygon);
            log.debug("parsed faces {} {}", .{ self.faces.items.len, self.face_polygon.items.len });
            const obj = self.activeObject();
            obj.checkInfo(face_info);

            var face: Face = .{
                .info = face_info,
                .data = undefined,
            };
            if (self.face_polygon.items.len > mesh.FaceType.arr_len) {
                while (self.triangulate()) |face_data| {
                    face.data = face_data;
                    self.checkFace(&face);
                    log.debug("parsed face {}", .{self.faces.items.len});
                    try self.faces.append(self.allocator, face);
                }
            } else {
                @memcpy(face.data[0..self.face_polygon.items.len], self.face_polygon.items);
                self.checkFace(&face);
                log.debug("parsed face {}", .{self.faces.items.len});
                try self.faces.append(self.allocator, face);
                self.face_polygon.clearRetainingCapacity();
            }
        } else if (str.eql(cmd, "s")) {
            const smoothing = try parseSmoothing(&iter);
            log.debug("parsed smoothing group {x}", .{smoothing});
            try self.nodes.append(self.allocator, .{
                .offset = self.faces.items.len,
                .meta = .{ .smoothing = smoothing },
            });
        } else if (str.eql(cmd, "o")) {
            const obj = self.activeObject();
            const name = try str.dupeZ(str.trimRest(&iter));
            log.debug("parsed object {s}", .{name});
            if (obj.isDefault()) {
                @branchHint(.cold);
                assert(self.faces.items.len == 0);
                obj.name = name;
            } else {
                const obj_node = self.activeObjectNode();

                obj_node.len = self.faces.items.len - obj_node.offset;
                self.obj_idx = self.nodes.items.len;

                try self.nodes.append(self.allocator, .{
                    .offset = self.faces.items.len,
                    .meta = .{ .object = .{ .name = name } },
                });
            }
        } else if (str.eql(cmd, "g")) {
            const name = try str.dupeZ(str.trimRest(&iter));
            log.debug("parsed group {s}", .{name});
            try self.nodes.append(self.allocator, .{
                .offset = self.faces.items.len,
                .meta = .{ .group = name },
            });
        } else if (str.eql(cmd, "usemtl")) {
            const material = try str.dupeZ(str.trimRest(&iter));
            log.debug("parsed use material {s}", .{material});
            try self.nodes.append(self.allocator, .{
                .offset = self.faces.items.len,
                .meta = .{ .material = material },
            });
        } else if (str.eql(cmd, "mtllib")) {
            const mtl_path = try str.dupeZ(str.trimRest(&iter));
            log.debug("parsed material library {s}", .{mtl_path});
            if (self.mtl_path != null) return error.DuplicateCommand;
            self.mtl_path = mtl_path;
        } else {
            log.err("\"{s}\"", .{line});
            return error.SyntaxError;
        }
    }
}

fn checkFace(self: *const Self, face: *const Face) void {
    var attr_iter = face.info.attrs_present.iterator();
    while (attr_iter.next()) |attr| {
        const len = self.attr_verts.getPtrConst(attr).items.len;
        for (0..@intFromEnum(face.info.face_type)) |vert_n| {
            const idx = getFaceIndex(&face.data, @intCast(vert_n), attr);
            if (idx >= len) log.err("{} {}: {} >= {}", .{ attr, vert_n, idx, len });
            assert(idx < len);
        }
    }
}

fn triangulate(self: *Self) ?FaceData {
    if (self.face_polygon.items.len == 0) return null;
    assert(self.face_polygon.items.len >= 3);
    if (self.face_polygon.items.len == 3) {
        defer self.face_polygon.clearRetainingCapacity();
        return .{
            self.face_polygon.items[0],
            self.face_polygon.items[1],
            self.face_polygon.items[2],
        };
    }

    const verts = self.attr_verts.getPtrConst(.position).items;
    all: for (0..self.face_polygon.items.len) |n| {
        const prev_n = if (n > 0) n - 1 else self.face_polygon.items.len - 1;
        const next_n = if (n < self.face_polygon.items.len - 1) n + 1 else 0;
        const tri: [3]*const math.Vector3 = .{
            getIndexVector(verts, &self.face_polygon.items[prev_n], .position),
            getIndexVector(verts, &self.face_polygon.items[n], .position),
            getIndexVector(verts, &self.face_polygon.items[next_n], .position),
        };

        var normal: math.Vector3 = undefined;
        math.vector3.triNormal(&normal, tri);
        const angle = math.vector3.triAbsAngle(1, tri);
        if (angle >= math.scalar.pi) continue;

        for (0..self.face_polygon.items.len) |ni| {
            if (ni == prev_n or ni == n or ni == next_n) continue;
            const p = getIndexVector(verts, &self.face_polygon.items[ni], .position);
            if (math.vector3.dot(p, &normal) < math.scalar.eps) {
                if (math.vector3.triContainsPoint(tri, p, &normal)) continue :all;
            }
        }

        defer _ = self.face_polygon.orderedRemove(n);
        return .{
            self.face_polygon.items[prev_n],
            self.face_polygon.items[n],
            self.face_polygon.items[next_n],
        };
    }
    unreachable;
}

fn parseVector(iter: *str.ScalarIterator) !math.Vector3 {
    var result = math.vector3.zero;
    var n: usize = 0;

    while (iter.next()) |token| {
        if (token.len == 0) continue;
        switch (n) {
            0, 1, 2 => result[n] = std.fmt.parseFloat(math.Scalar, token) catch return error.ParseFloatError,
            3 => log.warn("loaded 4th component of a 3-element vector", .{}),
            else => return error.TooManyArguments,
        }
        n += 1;
    }

    // TODO: Parse different vertex types
    if (n < 1) return error.NotEnoughArguments;
    return result;
}

fn parseFace(iter: *str.ScalarIterator, list: *FacePolygon) !FaceInfo {
    var result: FaceInfo = .{};
    var n: u8 = 0;

    while (iter.next()) |token| {
        if (token.len == 0) continue;
        if (n >= list.capacity) return error.TooManyArguments;
        const index = try parseIndex(token);
        if (result.attrs_present.eql(.initEmpty())) result.attrs_present = index.attrs_present;
        assert(result.attrs_present.eql(index.attrs_present));
        list.appendAssumeCapacity(index.data);
        n += 1;
    }

    if (n < face_arr_min) return error.NotEnoughArguments;
    result.face_type = if (n > 3) .triangle else @enumFromInt(n);
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

const CreateResultState = struct {
    vert_idx: usize = 0,
    node_n: usize = 0,
    face_n: usize = 0,
    material_active: ?[:0]const u8 = null,
    smoothing_groups_active: std.bit_set.IntegerBitSet(smoothing_groups_len) = .initEmpty(),
    vert_data: std.EnumArray(AttrType, []const math.Vector3),
    face_normals: std.ArrayList(math.Vector3) = .empty,
    face_tangents: std.ArrayList([2]math.Vector3) = .empty,
    face_angles: std.ArrayList(math.Scalar) = .empty,
    smoothing_groups: [smoothing_groups_len]std.AutoHashMapUnmanaged(
        math.Index,
        std.ArrayList(usize),
    ) = @splat(.empty),

    fn init(self: *const Self) CreateResultState {
        return .{
            .vert_data = .init(.{
                .position = self.attr_verts.getPtrConst(.position).items,
                .tex_coord = self.attr_verts.getPtrConst(.tex_coord).items,
                .normal = self.attr_verts.getPtrConst(.normal).items,
            }),
        };
    }

    fn deinit(state: *CreateResultState, self: *const Self) void {
        state.face_normals.deinit(self.allocator);
        state.face_tangents.deinit(self.allocator);
        state.face_angles.deinit(self.allocator);
        for (&state.smoothing_groups) |*group| {
            var iter = group.valueIterator();
            while (iter.next()) |list| list.deinit(self.allocator);
            group.deinit(self.allocator);
        }
    }
};

fn createResult(self: *const Self) !ObjResult {
    var result: ObjResult = .{
        .allocator = self.allocator,
        .mesh_buf = .empty,
        .mesh_objs = .empty,
        .mtl_path = self.mtl_path,
    };
    errdefer result.deinit();

    var state: CreateResultState = .init(self);
    defer state.deinit(self);

    var node_offset: usize = 0;
    while (state.node_n < self.nodes.items.len) {
        const node = self.nodes.items[state.node_n];
        assert(node.offset == node_offset);
        state.node_n += 1;
        switch (node.meta) {
            .object => {
                try self.processFaces(&result, &state, node);
                node_offset = node.offset + node.len;
            },
            .group => {
                log.err("group node is outside of an object", .{});
                unreachable;
            },
            .smoothing => |smoothing| state.smoothing_groups_active.mask = smoothing,
            .material => |material| state.material_active = material,
        }
    }

    if (comptime gfx_options.enable_normal_smoothing) self.applySmoothing(&result, &state);

    return result;
}

fn processFaces(self: *const Self, result: *ObjResult, state: *CreateResultState, obj_node: Node) !void {
    const obj = obj_node.meta.object;
    assert(obj.info.face_type != .invalid);
    assert(obj.info.attrs_present.contains(.position));
    return switch (obj.info.attrs_present.contains(.tex_coord)) {
        inline else => |has_tex_coord| switch (obj.info.attrs_present.contains(.normal)) {
            inline else => |has_normal| switch (obj.info.face_type) {
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
    face_type: mesh.FaceType,
}) type {
    return struct {
        fn processFaces(
            self: *const Self,
            result: *ObjResult,
            state: *CreateResultState,
            faces_offset: usize,
            faces_len: usize,
            obj: Node.Meta.Object,
        ) !void {
            const oe = try result.mesh_objs.getOrPutValue(
                self.allocator,
                obj.name,
                .init(config.face_type),
            );
            assert(!oe.found_existing);
            const mesh_obj = oe.value_ptr;
            errdefer mesh_obj.deinit(self.allocator);

            try mesh_obj.beginSection(self.allocator, state.vert_idx, state.material_active);
            defer {
                mesh_obj.endSection(state.vert_idx);
                mesh_obj.endGroup(state.vert_idx);
                assert(!mesh_obj.has_active.section and !mesh_obj.has_active.group);
            }

            const faces = self.faces.items[faces_offset .. faces_offset + faces_len];
            const face_vert_count = mesh.Object.face_vert_counts.get(config.face_type);

            var face_count: usize = 0;
            for (faces) |*face| {
                const vert_orders = face_vert_orders.get(face.info.face_type);
                face_count += vert_orders.len;
            }

            const vert_offset = state.vert_idx;
            const vert_count = face_count * face_vert_count;

            try result.mesh_buf.ensureUnusedCapacity(self.allocator, math.Vertex, vert_count);
            try state.face_normals.ensureUnusedCapacity(self.allocator, vert_count);
            try state.face_tangents.ensureUnusedCapacity(self.allocator, vert_count);
            try state.face_angles.ensureUnusedCapacity(self.allocator, vert_count);

            for (faces) |*face| {
                const vert_orders = face_vert_orders.get(face.info.face_type);
                while (state.node_n < self.nodes.items.len) {
                    if (self.nodes.items[state.node_n].offset == state.face_n) {
                        const node = self.nodes.items[state.node_n];
                        switch (node.meta) {
                            .object => {
                                log.err("object node is inside of an object", .{});
                                unreachable;
                            },
                            .group => |name| try mesh_obj.beginGroup(self.allocator, state.vert_idx, name),
                            .smoothing => |smoothing| state.smoothing_groups_active.mask = smoothing,
                            .material => |material| {
                                state.material_active = material;
                                try mesh_obj.beginSection(self.allocator, state.vert_idx, state.material_active);
                            },
                        }
                        state.node_n += 1;
                    } else break;
                }

                for (vert_orders) |vert_order| {
                    const vert_normals = computeFaceNormals(state.vert_data.get(.position), &face.data, vert_order);
                    const vert_tangents = computeFaceTangents(state.vert_data, &face.data, vert_order);

                    for (vert_order, 0..) |vert_n, n| {
                        if (comptime canComputeNormals()) {
                            const idx_n = getFaceIndex(&face.data, vert_n, .position);
                            var iter = state.smoothing_groups_active.iterator(.{});
                            while (iter.next()) |sg| {
                                const group = &state.smoothing_groups[sg];
                                const e = try group.getOrPutValue(self.allocator, idx_n, .empty);
                                const list = e.value_ptr;
                                try list.append(self.allocator, state.vert_idx);
                            }
                        }

                        const face_vert_data = getFaceVertData(state.vert_data, &face.data, &vert_normals[3], vert_n);
                        state.face_normals.appendAssumeCapacity(vert_normals[n]);
                        state.face_tangents.appendAssumeCapacity(.{ vert_tangents[0], vert_tangents[1] });
                        state.face_angles.appendAssumeCapacity(vert_normals[4][n]);

                        result.mesh_buf.appendAssumeCapacity(math.Vertex, 1, &.{
                            face_vert_data[0],
                            face_vert_data[1],
                            face_vert_data[2],
                            vert_tangents[2],
                            vert_tangents[3],
                        });
                        state.vert_idx += 1;
                    }
                }

                state.face_n += 1;
            }

            assert(vert_count == state.vert_idx - vert_offset);
        }

        fn canComputeNormals() bool {
            comptime return !config.has_normal and config.face_type == .triangle;
        }

        fn canComputeTangents() bool {
            comptime return config.has_tex_coord;
        }

        inline fn computeFaceNormals(
            verts: []const math.Vector3,
            face: *const FaceData,
            vert_order: []const u8,
        ) FaceNormals {
            if (comptime canComputeNormals()) {
                var normals: FaceNormals = undefined;

                const tri = [3]*const math.Vector3{
                    getFaceVector(verts, face, vert_order[0], .position),
                    getFaceVector(verts, face, vert_order[1], .position),
                    getFaceVector(verts, face, vert_order[2], .position),
                };

                math.vector3.triNormal(&normals[3], tri);
                normals[0] = normals[3];
                normals[1] = normals[3];
                normals[2] = normals[3];

                normals[4][0] = math.vector3.triAbsAngle(0, tri);
                normals[4][1] = math.vector3.triAbsAngle(1, tri);
                normals[4][2] = math.vector3.triAbsAngle(2, tri);
                math.vector3.scale(&normals[0], normals[4][0]);
                math.vector3.scale(&normals[1], normals[4][1]);
                math.vector3.scale(&normals[2], normals[4][2]);

                return normals;
            } else {
                return @splat(math.vector3.zero);
            }
        }

        inline fn computeFaceTangents(
            vert_data: std.EnumArray(AttrType, []const math.Vector3),
            face: *const FaceData,
            vert_order: []const u8,
        ) [4]math.Vector3 {
            if (comptime canComputeTangents()) {
                const v = [3]*const math.Vector3{
                    getFaceVector(vert_data.get(.position), face, vert_order[0], .position),
                    getFaceVector(vert_data.get(.position), face, vert_order[1], .position),
                    getFaceVector(vert_data.get(.position), face, vert_order[2], .position),
                };

                const uv = [3]*const math.Vector3{
                    getFaceVector(vert_data.get(.tex_coord), face, vert_order[0], .tex_coord),
                    getFaceVector(vert_data.get(.tex_coord), face, vert_order[1], .tex_coord),
                    getFaceVector(vert_data.get(.tex_coord), face, vert_order[2], .tex_coord),
                };

                var lhs = v[1].*;
                var rhs = v[2].*;
                math.vector3.sub(&lhs, v[0]);
                math.vector3.sub(&rhs, v[0]);

                var uv_lhs = uv[1].*;
                var uv_rhs = uv[2].*;
                math.vector3.sub(&uv_lhs, uv[0]);
                math.vector3.sub(&uv_rhs, uv[0]);

                const det = 1.0 / (uv_lhs[0] * uv_rhs[1] - uv_rhs[0] * uv_lhs[1]);
                const tangent: math.Vector3 = .{
                    det * (uv_rhs[1] * lhs[0] - uv_lhs[1] * rhs[0]),
                    det * (uv_rhs[1] * lhs[1] - uv_lhs[1] * rhs[1]),
                    det * (uv_rhs[1] * lhs[2] - uv_lhs[1] * rhs[2]),
                };
                const binormal: math.Vector3 = .{
                    det * (-uv_rhs[0] * lhs[0] + uv_lhs[0] * rhs[0]),
                    det * (-uv_rhs[0] * lhs[1] + uv_lhs[0] * rhs[1]),
                    det * (-uv_rhs[0] * lhs[2] + uv_lhs[0] * rhs[2]),
                };
                return .{
                    tangent,
                    binormal,
                    math.vector3.normalized(&tangent),
                    math.vector3.normalized(&binormal),
                };
            } else {
                return @splat(math.vector3.zero);
            }
        }

        inline fn getFaceVertData(
            vert_data: std.EnumArray(AttrType, []const math.Vector3),
            face: *const FaceData,
            normal: *const math.Vector3,
            vert_n: u8,
        ) VertData {
            return .{
                getFaceVector(vert_data.get(.position), face, vert_n, .position).*,
                if (comptime config.has_tex_coord)
                    getFaceVector(vert_data.get(.tex_coord), face, vert_n, .tex_coord).*
                else
                    math.vector3.zero,
                if (comptime config.has_normal)
                    getFaceVector(vert_data.get(.normal), face, vert_n, .normal).*
                else
                    normal.*,
            };
        }
    };
}

fn applySmoothing(self: *const Self, result: *const ObjResult, state: *const CreateResultState) void {
    _ = self;
    const smoothing_angle_limit = comptime std.math.degreesToRadians(gfx_options.normal_smoothing_angle_limit);
    const verts = result.mesh_buf.slice(math.Vector3);
    for (&state.smoothing_groups) |group| {
        var sg_iter = group.valueIterator();
        while (sg_iter.next()) |vert_list| {
            for (vert_list.items) |dst_vert_idx| {
                const dst_normal = getVector(verts, dst_vert_idx, .normal);
                const dst_tangent = getVector(verts, dst_vert_idx, .tangent);
                const dst_binormal = getVector(verts, dst_vert_idx, .binormal);

                var avg_normal = math.vector3.zero;
                var avg_tangent = math.vector3.zero;
                var avg_binormal = math.vector3.zero;
                for (vert_list.items) |src_vert_idx| {
                    const src_normal = &state.face_normals.items[src_vert_idx];
                    const src_tangent = &state.face_tangents.items[src_vert_idx][0];
                    const src_binormal = &state.face_tangents.items[src_vert_idx][1];

                    const angle = math.vector3.absAngle(dst_normal, src_normal);
                    if (angle <= smoothing_angle_limit) {
                        math.vector3.add(&avg_normal, src_normal);
                        math.vector3.add(&avg_tangent, src_tangent);
                        math.vector3.add(&avg_binormal, src_binormal);
                    }
                }

                // Normal smoothing
                math.vector3.normalize(&avg_normal);
                dst_normal.* = avg_normal;

                // Gram-Schmidt orthogonalization: T' = normalize(T - N * dot(N, T))
                dst_tangent.* = avg_normal;
                math.vector3.scale(dst_tangent, -math.vector3.dot(&avg_normal, &avg_tangent));
                math.vector3.add(dst_tangent, &avg_tangent);
                math.vector3.normalize(dst_tangent);

                // Calculate the handedness/direction of the binormal (needed for MikkTSpace compatibility)
                // Helps fix mirroring issues on some UV seams
                math.vector3.normalize(&avg_binormal);
                dst_binormal.* = avg_binormal;
                var cross: math.Vector3 = undefined;
                math.vector3.cross(&cross, &avg_normal, &avg_tangent);
                const handedness: math.Scalar = if (math.vector3.dot(&cross, &avg_binormal) < 0) -1 else 1;
                math.vector3.scale(dst_tangent, handedness);
            }
        }
    }
}

inline fn getVector(
    verts: []math.Vector3,
    vert_idx: usize,
    attr: math.VertexAttr,
) *math.Vector3 {
    const idx = getVectorIndex(vert_idx, attr);
    assert(idx < verts.len);
    return &verts[idx];
}

inline fn getFaceVector(
    verts: []const math.Vector3,
    face: *const FaceData,
    vert_n: u8,
    attr: AttrType,
) *const math.Vector3 {
    const idx = getFaceIndex(face, vert_n, attr);
    assert(idx < verts.len);
    return &verts[idx];
}

inline fn getIndexVector(
    verts: []const math.Vector3,
    index: *const IndexData,
    attr: AttrType,
) *const math.Vector3 {
    const idx = getIndexIndex(index, attr);
    assert(idx < verts.len);
    return &verts[idx];
}

inline fn getVectorIndex(vert_idx: usize, attr: math.VertexAttr) usize {
    return vert_idx * math.VertexAttr.len + @intFromEnum(attr);
}

inline fn getFaceIndex(face: *const FaceData, vert_n: u8, attr: AttrType) math.Index {
    assert(vert_n < mesh.FaceType.arr_len);
    return getIndexIndex(&face[vert_n], attr);
}

inline fn getIndexIndex(index: *const IndexData, attr: AttrType) math.Index {
    return index[@intFromEnum(attr)];
}
