//!
//! The zengine scene implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("allocators.zig");
const c = @import("ext.zig").c;
const gfx = @import("gfx.zig");
const global = @import("global.zig");
const KeyMap = @import("containers.zig").KeyMap;
const math = @import("math.zig");
const PtrKeyMap = @import("containers.zig").PtrKeyMap;
pub const Camera = @import("Scene/Camera.zig");
pub const Light = @import("Scene/Light.zig");
pub const Node = @import("Scene/Node.zig");
const Nodes = Node.Tree;
pub const Object = @import("Scene/Object.zig");
pub const Transform = @import("Scene/Transform.zig");
const ui = @import("ui.zig");

const log = std.log.scoped(.scene);

allocator: std.mem.Allocator,
cameras: Cameras,
lights: Lights,
objects: Objects,
nodes: Nodes,

const Self = @This();
const Cameras = KeyMap(Camera, .{});
const Lights = KeyMap(Light, .{});
const Objects = PtrKeyMap(Object);
pub const FlatList = std.MultiArrayList(Node.Flat);
pub const Flattened = std.EnumArray(Node.Type, FlatList);

pub fn init() !*Self {
    return createSelf(allocators.gpa());
}

pub fn deinit(self: *Self) void {
    self.cameras.deinit();
    self.lights.deinit();
    self.objects.deinit(self.allocator);
    self.nodes.deinit();
}

pub fn lightCounts(self: *const Self, flat: *const Flattened) std.EnumArray(Light.Type, u32) {
    var result: std.EnumArray(Light.Type, u32) = .initFill(0);
    for (flat.getPtrConst(.light).items(.target)) |target| {
        const light = self.lights.get(target);
        result.getPtr(light.type).* += 1;
    }
    return result;
}

fn createSelf(allocator: std.mem.Allocator) !*Self {
    const self = try allocators.global().create(Self);
    self.* = .{
        .allocator = allocator,
        .cameras = try .init(allocator, 128),
        .lights = try .init(allocator, 128),
        .objects = try .init(allocator, 128),
        .nodes = try .init(allocator, 128),
    };
    return self;
}

pub fn createDefaultCamera(self: *Self) !void {
    var camera_position: math.Vector3 = .{ 4, 8, 10 };
    // var camera_position: math.Vector3 = .{ -1438.067, 2358.586, 2820.102 };
    var camera_direction: math.Vector3 = undefined;

    math.vector3.scale(&camera_position, 50);
    math.vector3.lookAt(&camera_direction, &camera_position, &math.vector3.zero);

    _ = try self.createCamera("default", &.{
        .type = .perspective,
        .position = camera_position,
        .direction = camera_direction,
    });
}

pub fn createCamera(self: *Self, key: []const u8, camera: *const Camera) !*Camera {
    return self.cameras.insert(key, camera);
}

pub fn createLight(self: *Self, key: []const u8, light: Light) !*Light {
    return self.lights.insert(key, light);
}

pub fn createObject(self: *Self, key: []const u8, object: *Object) !*Object {
    try self.objects.insert(self.allocator, key, object);
    return object;
}

pub fn createRootNode(self: *Self, target: Node.Target, transform: *const Transform) !*Node {
    return Node.selfNode(try self.nodes.insert(.{
        .target = target,
        .transform = transform.*,
    }));
}

pub fn createChildNode(
    self: *Self,
    parent: *Node,
    target: Node.Target,
    transform: *const Transform,
) !*Node {
    return Node.selfNode(try parent.treeNode().insert(&self.nodes, .{
        .target = target,
        .transform = transform.*,
    }));
}

pub fn flatten(self: *const Self) !Flattened {
    var transforms: std.ArrayList(math.Matrix4x4) = .empty;
    var list: Flattened = .initFill(.empty);

    var tr_scratch: math.Matrix4x4 = undefined;
    const tr_root = try transforms.addOne(allocators.frame());
    tr_root.* = math.matrix4x4.identity;

    var iter = self.nodes.iteratorConst();
    while (iter.next()) |node| try walkScene(
        &node.value,
        0,
        &tr_scratch,
        &list,
        &transforms,
    );

    return list;
}

fn walkScene(
    node: *const Node,
    tr_parent: usize,
    tr_scratch: *math.Matrix4x4,
    list: *Flattened,
    transforms: *std.ArrayList(math.Matrix4x4),
) !void {
    const tr = try transforms.addOne(allocators.frame());
    const tr_n = transforms.items.len - 1;

    node.transform.transform(tr_scratch);
    math.matrix4x4.dot(tr, &transforms.items[tr_parent], tr_scratch);
    switch (node.target.type) {
        .object, .light, .camera => |node_type| try list.getPtr(node_type).append(allocators.frame(), .{
            .target = node.target.key,
            .transform = tr.*,
        }),
        else => {},
    }

    log.debug("walk scene", .{});
    log.debug("type: {t}", .{node.target.type});
    log.debug("key: {s}", .{node.target.key});
    log.debug("node: {any}", .{node.transform});
    log.debug("tr_n: {any}", .{tr_n});
    log.debug("node_tr: {any}", .{tr_scratch});
    log.debug("tr: {any}\n", .{tr});

    var iter = node.childrenIterator();
    while (iter.next()) |child| try walkScene(
        child,
        tr_n,
        tr_scratch,
        list,
        transforms,
    );
}

pub fn propertyEditorNode(
    self: *Self,
    editor: *ui.PropertyEditorWindow,
    parent: *ui.PropertyEditorWindow.Item,
) !*ui.PropertyEditorWindow.Item {
    const root_id = @typeName(Self);
    const root_node = try editor.appendChildNode(parent, root_id, "Scene");

    {
        const node = try editor.appendChildNode(root_node, root_id ++ ".cameras", "Cameras");
        var iter = self.cameras.map.iterator();
        var buf: [64]u8 = undefined;
        while (iter.next()) |entry| {
            const id = try std.fmt.bufPrint(
                &buf,
                "{s}#{s}",
                .{ @typeName(Camera), entry.key_ptr.* },
            );
            _ = try editor.appendChild(
                node,
                entry.value_ptr.*.propertyEditor(),
                id,
                entry.key_ptr.*,
            );
        }
    }
    {
        const node = try editor.appendChildNode(root_node, root_id ++ ".lights", "Lights");
        var iter = self.lights.map.iterator();
        var buf: [64]u8 = undefined;
        while (iter.next()) |entry| {
            const id = try std.fmt.bufPrint(
                &buf,
                "{s}#{s}",
                .{ @typeName(Light), entry.key_ptr.* },
            );
            _ = try editor.appendChild(
                node,
                entry.value_ptr.*.propertyEditor(),
                id,
                entry.key_ptr.*,
            );
        }
    }
    {
        const node = try editor.appendChildNode(root_node, root_id ++ ".nodes", "Nodes");
        var iter = self.nodes.iterator();
        while (iter.next()) |tree_node| {
            try walkPropertyEditorNode(self, editor, node, Node.selfNode(tree_node));
        }
    }
    return root_node;
}

const walkPropertyEditorNode = struct {
    var buf: [64]u8 = undefined;
    var n: usize = 0;
    fn walk(
        self: *Self,
        editor: *ui.PropertyEditorWindow,
        parent: *ui.PropertyEditorWindow.Item,
        node: *Node,
    ) !void {
        n += 1;
        const id = try std.fmt.bufPrint(
            &buf,
            "{s}#node_{}",
            .{ @typeName(Node), n },
        );
        const editor_node = try editor.appendChild(
            parent,
            node.propertyEditor(),
            id,
            node.target.key,
        );
        var iter = node.childrenIterator();
        while (iter.next()) |child| {
            try walk(self, editor, editor_node, child);
        }
    }
}.walk;
