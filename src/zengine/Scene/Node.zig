//!
//! The zengine scene node implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const TreeContainer = @import("../containers.zig").Tree;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");
const Transform = @import("Transform.zig");

const log = std.log.scoped(.scene_camera);

target: Target,
transform: Transform = .{},

const Self = @This();
pub const Tree = TreeContainer(Self, .{});

pub const Type = enum {
    node,
    camera,
    light,
    object,
};

pub const Target = struct {
    key: [:0]const u8,
    type: Type,

    pub fn node() Target {
        return .{ .key = "", .type = .node };
    }

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

pub const Flat = struct {
    target: [:0]const u8,
    transform: math.Matrix4x4,
};

pub fn parent(self: *const Self) ?*Self {
    return self.treeNode().parent;
}

pub fn next(self: *const Self) ?*Self {
    if (self.treeNodeConst().next()) |tree_node| return selfNode(tree_node);
    return null;
}

pub fn child(self: *const Self) ?*Self {
    if (self.treeNodeConst().edges.first) |tree_node| return selfNode(tree_node);
    return null;
}

pub fn hasChildren(self: *const Self) bool {
    return self.treeNode().edges.first != null;
}

pub fn childrenIterator(self: *const Self) ChildrenIterator {
    return .{ .iter = self.treeNodeConst().iterator() };
}

pub inline fn treeNode(self: *Self) *Tree.Node {
    return @fieldParentPtr("value", self);
}

pub inline fn treeNodeConst(self: *const Self) *const Tree.Node {
    return @fieldParentPtr("value", self);
}

pub inline fn selfNode(tree_node: *Tree.Node) *Self {
    return &tree_node.value;
}

pub const ChildrenIterator = struct {
    iter: Tree.EdgeIterator,

    pub fn next(i: *ChildrenIterator) ?*Self {
        if (i.iter.next()) |tree_node| return selfNode(tree_node);
        return null;
    }
};
