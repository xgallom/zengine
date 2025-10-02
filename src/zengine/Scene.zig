//!
//! The zengine scene implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("allocators.zig");
const c = @import("ext.zig").c;
const global = @import("global.zig");
const KeyMap = @import("containers.zig").KeyMap;
const math = @import("math.zig");
const PtrKeyMap = @import("containers.zig").PtrKeyMap;
pub const Camera = @import("Scene/Camera.zig");
pub const Light = @import("Scene/light.zig").Light;
pub const Object = @import("Scene/Object.zig");
pub const Transform = @import("Scene/Transform.zig");
const Tree = @import("containers.zig").Tree;
const ui = @import("ui.zig");

const log = std.log.scoped(.scene);

allocator: std.mem.Allocator,
cameras: Cameras,
lights: Lights,
objects: Objects,
nodes: NodesTree,

const Self = @This();
const Cameras = KeyMap(Camera, .{});
const Lights = KeyMap(Light, .{});
const Objects = PtrKeyMap(Object);
const NodesTree = Tree(Node, .{});

pub const Node = struct {
    target: Target,
    transform: Transform = .{},

    pub const Target = struct {
        key: [:0]const u8,
        type: Type,

        pub const Type = enum {
            camera,
            light,
            object,
        };

        pub fn camera(key: [:0]const u8) Target {
            return .{ .key = key, .type = .camera };
        }

        pub fn light(key: [:0]const u8) Target {
            return .{ .key = key, .type = .light };
        }

        pub fn object(key: [:0]const u8) Target {
            return .{ .key = key, .type = .object };
        }
    };

    pub fn parent(self: *const Node) ?*Node {
        return self.treeNode().parent;
    }

    pub fn next(self: *const Node) ?*Node {
        if (self.treeNode().next()) |tree_node| return selfNode(tree_node);
        return null;
    }

    pub fn hasChildren(self: *const Node) bool {
        return self.treeNode().edges.first != null;
    }

    pub fn children(self: *const Node) ChildrenIterator {
        return .{ .iter = self.treeNode().iterator() };
    }

    inline fn treeNode(self: *const Node) *const NodesTree.Node {
        return @fieldParentPtr("value", self);
    }

    inline fn selfNode(tree_node: *NodesTree.Node) *Node {
        return &tree_node.value;
    }

    pub const ChildrenIterator = struct {
        iter: NodesTree.EdgeIterator,

        pub fn next(i: *ChildrenIterator) ?*Node {
            if (i.iter.next()) |tree_node| return selfNode(tree_node);
            return null;
        }
    };
};

pub fn init() !*Self {
    return createSelf(allocators.gpa());
}

pub fn deinit(self: *Self) void {
    self.cameras.deinit();
    self.lights.deinit();
    self.objects.deinit(self.allocator);
    self.nodes.deinit();
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

    math.vector3.scale(&camera_position, 15);
    math.vector3.lookAt(&camera_direction, &camera_position, &math.vector3.zero);

    _ = try self.createCamera("default", &.{
        .kind = .perspective,
        .position = camera_position,
        .direction = camera_direction,
    });
}

pub fn createDefaultLights(self: *Self) !void {
    _ = try self.createLight("ambient", &.initAmbient(.{
        .light = .{ .color = .{ 255, 255, 255 }, .intensity = 0.05 },
    }));
    _ = try self.createLight("diffuse_r", &.initPoint(.{
        .light = .{ .color = .{ 255, 32, 64 }, .intensity = 2e4 },
        .position = .{ 100, 0, 0 },
    }));
    _ = try self.createLight("diffuse_g", &.initPoint(.{
        .light = .{ .color = .{ 128, 32, 128 }, .intensity = 2e4 },
        .position = .{ 0, 100, 0 },
    }));
    _ = try self.createLight("diffuse_b", &.initPoint(.{
        .light = .{ .color = .{ 64, 32, 255 }, .intensity = 2e4 },
        .position = .{ -100, 0, 0 },
    }));
}

pub fn createCamera(self: *Self, key: []const u8, camera: *const Camera) !*Camera {
    return self.cameras.insert(key, camera);
}

pub fn createLight(self: *Self, key: []const u8, light: *const Light) !*Light {
    return self.lights.insert(key, light);
}

pub fn createObject(self: *Self, key: []const u8, object: *Object) !*Object {
    try self.objects.insert(self.allocator, key, object);
    return object;
}

pub fn createRootNode(self: *Self, target: Node.Target, transform: ?*const Transform) !*Node {
    const node = try self.nodes.insert(.{ .target = target });
    if (transform) |tr| node.value.transform = tr;
    return node.value;
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
            const id = try std.fmt.bufPrint(&buf, "{s}#{s}", .{ @typeName(Camera), entry.key_ptr.* });
            _ = try editor.appendChild(
                node,
                entry.value_ptr.*.propertyEditor(),
                id,
                entry.key_ptr.*,
            );
        }
    }
    return root_node;
}
