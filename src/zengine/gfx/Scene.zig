//!
//! The zengine scene implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const ArrayMap = @import("../containers.zig").ArrayMap;
const ArrayPoolMap = @import("../containers.zig").ArrayPoolMap;
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const perf = @import("../perf.zig");
const ui = @import("../ui.zig");
const pass = @import("pass.zig");
const Camera = @import("Camera.zig");
const Light = @import("Light.zig");
const mesh = @import("mesh.zig");
const ttf = @import("ttf.zig");
const GPUFence = @import("GPUFence.zig");
const gfx_render = @import("render.zig");
const Renderer = @import("Renderer.zig");
pub const Node = @import("Scene/Node.zig");
const Nodes = Node.Tree;
pub const Transform = @import("Scene/Transform.zig");

const log = std.log.scoped(.gfx_scene);
pub const sections = perf.sections(@This(), &.{.flatten});

allocator: std.mem.Allocator,
renderer: *Renderer,
nodes: Nodes,

const Self = @This();

pub fn FlatList(comptime T: type) type {
    return std.MultiArrayList(Node.Flat(T));
}

pub const Flattened = struct {
    scene: *const Self,
    empty: std.ArrayList(math.Matrix4x4) = .empty,
    cameras: FlatList(Camera) = .empty,
    lights: FlatList(Light) = .empty,
    mesh_objs: FlatList(mesh.Object) = .empty,
    ui_objs: FlatList(mesh.Object) = .empty,
    text_objs: FlatList(ttf.Text) = .empty,

    pub fn lightCounts(self: *const Flattened) std.EnumArray(Light.Type, u32) {
        var result: std.EnumArray(Light.Type, u32) = .initFill(0);
        for (self.lights.items(.target)) |light| result.getPtr(light.type).* += 1;
        return result;
    }

    pub fn render(
        self: *const Flattened,
        ui_ptr: ?*ui.UI,
        items_iter: *gfx_render.Items.Object,
        ui_iter: *gfx_render.Items.Object,
        text_iter: *gfx_render.Items.Text,
        bloom: *const pass.Bloom,
        fence: ?*GPUFence,
    ) !bool {
        return gfx_render.renderScene(
            self.scene.renderer,
            self,
            ui_ptr,
            items_iter,
            ui_iter,
            text_iter,
            bloom,
            fence,
        );
    }

    pub fn batchTriIterator(
        flat: *const Flattened,
        comptime flat_field: @TypeOf(.enum_literal),
        comptime vertex_fields: std.EnumSet(math.VertexAttr),
    ) BatchTriangleIterator(vertex_fields) {
        comptime assert(@hasField(Flattened, @tagName(flat_field)));
        return .{ .items = @field(flat, @tagName(flat_field)).slice() };
    }
};

pub fn BatchTriangleIterator(comptime fields: std.EnumSet(math.VertexAttr)) type {
    comptime var field_list: []const std.builtin.Type.EnumField = &.{};
    {
        var iter = fields.iterator();
        const enum_fields = @typeInfo(math.VertexAttr).@"enum".fields;
        while (iter.next()) |e| {
            const field: std.builtin.Type.EnumField = blk: for (enum_fields) |enum_field| {
                if (enum_field.value == @intFromEnum(e)) break :blk enum_field;
            } else unreachable;
            field_list = field_list ++ &[_]std.builtin.Type.EnumField{field};
        }
    }
    assert(field_list.len > 0);
    const FieldsEnum = @Type(.{ .@"enum" = .{
        .tag_type = u8,
        .fields = field_list,
        .decls = &.{},
        .is_exhaustive = true,
    } });

    return struct {
        items: FlatList(mesh.Object).Slice,
        idx: usize = 0,
        section: usize = 0,
        offset: usize = 0,

        const Iter = @This();

        pub fn next(self: *@This()) ?Item {
            var s: State = undefined;
            while (true) {
                switch (self.currentState(&s)) {
                    .invalid => return null,
                    .next_object => if (!self.nextObject(&s)) return null,
                    .next_section => if (!self.nextSection(&s)) return null,
                    .valid => break,
                }
            }

            var item: Item = .{};
            inline for (0..math.batch.batch_len) |N| {
                assert(self.offset % 3 == 0);
                item.setTri(N, self, &s);
                if (!self.nextOffset(&s)) break;
            }
            return item;
        }

        const State = struct {
            obj: *const mesh.Object,
            mesh_buf: []const math.Vertex,
            section: *const mesh.Object.Section,
            vertex: *const math.Vertex,
        };

        fn currentState(self: *@This(), s: *State) enum { invalid, next_object, next_section, valid } {
            if (self.idx >= self.items.len) return .invalid;
            s.obj = self.items.items(.target)[self.idx];
            if (s.obj.face_type != .triangle) return .next_object;
            const mesh_buf = s.obj.mesh_bufs.get(.mesh);
            s.mesh_buf = @ptrCast(mesh_buf.slice(.vertex));
            if (self.section >= s.obj.sections.items.len) return .next_object;
            s.section = &s.obj.sections.items[self.section];
            if (self.offset >= s.section.len) return .next_section;
            s.vertex = @ptrCast(s.obj.mesh_bufs.get(.mesh).slice(.vertex)[self.offset..]);
            return .valid;
        }

        fn nextObject(self: *@This(), s: *State) bool {
            self.section = 0;
            self.offset = 0;
            while (true) {
                self.idx += 1;
                if (self.idx >= self.items.len) return false;
                s.obj = self.items.items(.target)[self.idx];
                if (s.obj.face_type != .triangle) continue;
                const mesh_buf = s.obj.mesh_bufs.get(.mesh);
                s.mesh_buf = @ptrCast(mesh_buf.slice(.vertex));
                assert(s.mesh_buf.len % 3 == 0);
                return true;
            }
        }

        fn nextSection(self: *@This(), s: *State) bool {
            self.section += 1;
            self.offset = 0;
            while (self.section >= s.obj.sections.items.len) {
                if (!self.nextObject(s)) return false;
            }

            s.section = &s.obj.sections.items[self.section];
            return true;
        }

        fn nextOffset(self: *@This(), s: *State) bool {
            self.offset += 1;
            while (self.offset >= s.section.len) {
                if (!self.nextSection(s)) return false;
            }

            assert(s.section.offset + self.offset < s.mesh_buf.len);
            assert((s.section.offset + self.offset) % 3 == 0);
            s.vertex = &s.mesh_buf[s.section.offset + self.offset];
            return true;
        }

        fn advanceTri(self: *@This(), s: *State) bool {
            self.offset += 1;
            if (self.offset >= s.section.len) return false;
            assert(s.section.offset + self.offset < s.mesh_buf.len);
            s.vertex = &s.mesh_buf[s.section.offset + self.offset];
            return true;
        }

        pub const Item = struct {
            len: usize = 0,
            keys: [math.batch.batch_len][:0]const u8 = @splat(""),
            sections: [math.batch.batch_len]usize = @splat(0),
            offsets: [math.batch.batch_len]usize = @splat(0),
            transform: math.batch.DenseMatrix4x4 = math.batch.dense_matrix4x4.zero,
            verts: [3]Vertex = @splat(.initFill(math.batch.dense_vector4.zero)),

            pub const Vertex = std.EnumArray(FieldsEnum, math.batch.DenseVector4);

            fn setTri(
                item: *Item,
                comptime N: comptime_int,
                self: *Iter,
                s: *State,
            ) void {
                comptime assert(N >= 0 and N < math.batch.batch_len);
                assert(N >= item.len);
                item.len = N + 1;
                item.keys[N] = self.items.items(.key)[self.idx];
                item.sections[N] = self.section;
                item.offsets[N] = self.offset;

                if (std.mem.eql(u8, "Cube", item.keys[N][0..4])) log.info("key: {s}", .{item.keys[N]});
                if (std.mem.eql(u8, "Cube", item.keys[N][0..4])) log.info("section: {}", .{self.section});
                if (std.mem.eql(u8, "Cube", item.keys[N][0..4])) log.info("offset: {}", .{s.section.offset + self.offset});
                {
                    const src = &self.items.items(.transform)[self.idx];
                    const dst = &item.transform;
                    for (0..4) |y| {
                        for (0..4) |x| {
                            dst[y][x][N] = src[y][x];
                        }
                    }
                }

                item.setTriVertex(N, 0, s);
                assert(self.advanceTri(s));
                item.setTriVertex(N, 1, s);
                assert(self.advanceTri(s));
                item.setTriVertex(N, 2, s);
            }

            fn setTriVertex(
                item: *Item,
                comptime N: comptime_int,
                comptime TN: comptime_int,
                s: *const State,
            ) void {
                comptime assert(N >= 0 and N < math.batch.batch_len);
                comptime assert(TN >= 0 and TN < 3);
                if (std.mem.eql(u8, "Cube", item.keys[N][0..4])) log.info("vertex[{}][{}]: {any}", .{ TN, N, s.vertex });
                inline for (field_list) |field| {
                    const src = &s.vertex[field.value];
                    const dst = item.verts[TN].getPtr(@enumFromInt(field.value));
                    for (0..3) |n| dst[n][N] = src[n];
                    dst[3][N] = @as(math.VertexAttr, @enumFromInt(field.value)).transformableElement();
                    if (std.mem.eql(u8, "Cube", item.keys[N][0..4])) log.info("tri[{}][0..3][{}]: {any}", .{ TN, N, src.* });
                    if (std.mem.eql(u8, "Cube", item.keys[N][0..4])) log.info("tri[{}][{}][{}]: {any}", .{ TN, 3, N, dst[3][N] });
                }
            }
        };
    };
}

pub fn create(renderer: *Renderer) !*Self {
    const allocator = allocators.gpa();
    const self = try allocators.global().create(Self);
    self.* = .{
        .allocator = allocator,
        .renderer = renderer,
        .nodes = .empty,
    };
    return self;
}

pub fn deinit(self: *Self) void {
    self.nodes.deinit(self.allocator);
}

pub fn createRootNode(
    self: *Self,
    name: [:0]const u8,
    target: Node.Target,
    transform: *const Transform,
) !Node.Id {
    return try self.nodes.insert(self.allocator, name, target, transform);
}

pub fn createChildNode(
    self: *Self,
    parent: Node.Id,
    name: [:0]const u8,
    target: Node.Target,
    transform: *const Transform,
) !Node.Id {
    return try self.nodes.insertChild(self.allocator, parent, name, target, transform);
}

pub fn copy(self: *Self, node: Node.Id, parent: Node.Id) !Node.Id {
    _ = self;
    _ = node;
    _ = parent;
}

pub fn flatten(self: *const Self) !Flattened {
    sections.sub(.flatten).begin();
    defer sections.sub(.flatten).end();

    var flat: Flattened = .{ .scene = self };
    var tr_scratch: math.Matrix4x4 = undefined;

    const s = self.nodes.slice();
    var walk = self.nodes.head;
    while (walk != .invalid) : (walk = s.node(walk).next) {
        try self.flattenWalk(&flat, &s, walk, &math.matrix4x4.identity, &tr_scratch);
    }

    return flat;
}

fn flattenWalk(
    self: *const Self,
    flat: *Flattened,
    s: *const Node.Tree.Slice,
    node: Node.Id,
    tr_parent: *const math.Matrix4x4,
    tr_scratch: *math.Matrix4x4,
) !void {
    if (!self.nodes.isPresent(node)) return;
    s.transform(node).transform(tr_scratch);
    math.matrix4x4.dot(s.matrix(node), tr_parent, tr_scratch);

    if (!s.flags(node).is_visible) return;

    switch (s.target(node).type) {
        .empty => try flat.empty.append(allocators.frame(), s.matrix(node).*),
        .camera => try flat.cameras.append(allocators.frame(), .{
            .key = s.target(node).key,
            .target = flat.scene.renderer.cameras.getPtr(s.target(node).key),
            .transform = s.matrix(node).*,
        }),
        .light => try flat.lights.append(allocators.frame(), .{
            .key = s.target(node).key,
            .target = flat.scene.renderer.lights.getPtr(s.target(node).key),
            .transform = s.matrix(node).*,
        }),
        .object => try flat.mesh_objs.append(allocators.frame(), .{
            .key = s.target(node).key,
            .target = flat.scene.renderer.mesh_objs.getPtr(s.target(node).key),
            .transform = s.matrix(node).*,
        }),
        .ui => try flat.ui_objs.append(allocators.frame(), .{
            .key = s.target(node).key,
            .target = flat.scene.renderer.mesh_objs.getPtr(s.target(node).key),
            .transform = s.matrix(node).*,
        }),
        .text => try flat.text_objs.append(allocators.frame(), .{
            .key = s.target(node).key,
            .target = flat.scene.renderer.texts.getPtr(s.target(node).key),
            .transform = s.matrix(node).*,
        }),
    }

    log.debug("walk scene", .{});
    log.debug("type: {t}", .{s.target(node).type});
    log.debug("key: {s}", .{s.target(node).key});
    log.debug("node: {any}", .{s.transform(node)});
    // log.debug("tr_n: {any}", .{tr_n});
    // log.debug("node_tr: {any}", .{tr_scratch});
    // log.debug("tr: {any}\n", .{tr});

    var walk = s.node(node).child;
    while (walk != .invalid) : (walk = s.node(walk).next) {
        try self.flattenWalk(flat, s, walk, s.matrix(node), tr_scratch);
    }
}

pub fn propertyEditorNode(
    self: *Self,
    editor: *ui.PropertyEditorWindow,
    parent: *ui.PropertyEditorWindow.Item,
) !*ui.PropertyEditorWindow.Item {
    const root_id = @typeName(Self);
    const root_node = try editor.appendChildNode(parent, root_id, "Scene");

    {
        const node = try editor.appendChildNode(root_node, root_id ++ ".nodes", "Nodes");
        const s = self.nodes.slice();
        var walk = self.nodes.head;
        while (walk != .invalid) : (walk = s.node(walk).next) {
            try walkPropertyEditorNode(self, editor, node, &s, walk);
        }
    }
    return root_node;
}

const walkPropertyEditorNode = struct {
    var buf: [64]u8 = undefined;
    fn walkFn(
        self: *Self,
        editor: *ui.PropertyEditorWindow,
        parent: *ui.PropertyEditorWindow.Item,
        s: *const Nodes.Slice,
        node: Node.Id,
    ) !void {
        const id = try std.fmt.bufPrint(
            &buf,
            "{s}#{f}",
            .{ @typeName(Node), node },
        );
        const editor_node = try editor.appendChild(
            parent,
            try self.nodes.propertyEditor(s, node),
            id,
            s.name(node),
        );
        var walk = s.node(node).child;
        while (walk != .invalid) : (walk = s.node(walk).next) {
            try walkFn(self, editor, editor_node, s, walk);
        }
    }
}.walkFn;
