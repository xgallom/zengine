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
const Camera = @import("Camera.zig");
const Light = @import("Light.zig");
const MeshObject = @import("MeshObject.zig");
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
    mesh_objs: FlatList(MeshObject) = .empty,

    pub fn lightCounts(self: *const Flattened) std.EnumArray(Light.Type, u32) {
        var result: std.EnumArray(Light.Type, u32) = .initFill(0);
        for (self.lights.items(.target)) |light| result.getPtr(light.type).* += 1;
        return result;
    }

    pub fn render(self: *const Flattened, ui_ptr: ?*ui.UI, items_iter: anytype) !bool {
        return self.scene.renderer.renderScene(self, ui_ptr, items_iter);
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

    var transforms: std.ArrayList(math.Matrix4x4) = .empty;
    var flat = Flattened{ .scene = self };

    var tr_scratch: math.Matrix4x4 = undefined;
    const tr_root = try transforms.addOne(allocators.frame());
    tr_root.* = math.matrix4x4.identity;

    const s = self.nodes.slice();
    var walk = self.nodes.head;
    while (walk != .invalid) : (walk = s.node(walk).next) {
        try flattenWalk(&flat, &s, walk, 0, &tr_scratch, &transforms);
    }

    return flat;
}

fn flattenWalk(
    flat: *Flattened,
    s: *const Node.Tree.Slice,
    node: Node.Id,
    tr_parent: usize,
    tr_scratch: *math.Matrix4x4,
    transforms: *std.ArrayList(math.Matrix4x4),
) !void {
    const tr = try transforms.addOne(allocators.frame());
    const tr_n = transforms.items.len - 1;

    s.transform(node).transform(tr_scratch);
    math.matrix4x4.dot(tr, &transforms.items[tr_parent], tr_scratch);

    if (!s.flags(node).is_visible) return;

    switch (s.target(node).type) {
        .empty => try flat.empty.append(allocators.frame(), tr.*),
        .camera => try flat.cameras.append(allocators.frame(), .{
            .key = s.target(node).key,
            .target = flat.scene.renderer.cameras.getPtr(s.target(node).key),
            .transform = tr.*,
        }),
        .light => try flat.lights.append(allocators.frame(), .{
            .key = s.target(node).key,
            .target = flat.scene.renderer.lights.getPtr(s.target(node).key),
            .transform = tr.*,
        }),
        .object => try flat.mesh_objs.append(allocators.frame(), .{
            .key = s.target(node).key,
            .target = flat.scene.renderer.mesh_objs.getPtr(s.target(node).key),
            .transform = tr.*,
        }),
    }

    log.debug("walk scene", .{});
    log.debug("type: {t}", .{s.target(node).type});
    log.debug("key: {s}", .{s.target(node).key});
    log.debug("node: {any}", .{s.transform(node)});
    log.debug("tr_n: {any}", .{tr_n});
    log.debug("node_tr: {any}", .{tr_scratch});
    log.debug("tr: {any}\n", .{tr});

    var walk = s.node(node).child;
    while (walk != .invalid) : (walk = s.node(walk).next) {
        try flattenWalk(flat, s, walk, tr_n, tr_scratch, transforms);
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
