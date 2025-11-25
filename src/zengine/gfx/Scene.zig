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
    ) !bool {
        return gfx_render.renderScene(self.scene.renderer, self, ui_ptr, items_iter, ui_iter, text_iter, bloom);
    }

    pub fn rayCast(flat: *const Flattened, ray_pos: *const math.Vector3, ray_dir: *const math.Vector3) void {
        const s = flat.mesh_objs.slice();
        for (0..s.len) |n| {
            const item = s.get(n);
            const obj = item.target;
            const mesh_buf = obj.mesh_bufs.get(.mesh);
            const verts: []const math.Vertex = mesh_buf.slice(.vertex);
            if (obj.face_type != .triangle) continue;
            for (obj.sections.items) |section| {
                const start = section.offset;
                const end = section.offset + section.len;
                var vn0 = start;
                while (vn0 < end) : (vn0 += 3) {
                    const tri = .{
                        math.vertex.cmap(&verts[vn0]).getPtrConst(.position),
                        math.vertex.cmap(&verts[vn0 + 1]).getPtrConst(.position),
                        math.vertex.cmap(&verts[vn0 + 2]).getPtrConst(.position),
                    };
                    const result = math.vector3.rayIntersectTri(tri, ray_pos, ray_dir);
                    if (result) |point| {
                        log.info("intersected {s} offset {}: {any}", .{ item.key, section.offset, point });
                        log.info(
                            "triangle: [{}]: {any} [{}]: {any} [{}]: {any}",
                            .{ vn0, tri[0].*, vn0 + 1, tri[1].*, vn0 + 2, tri[2].* },
                        );
                    }
                }
            }
        }
    }
};

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

    var flat = Flattened{ .scene = self };
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
