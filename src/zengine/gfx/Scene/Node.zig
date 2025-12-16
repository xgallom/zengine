//!
//! The zengine scene node implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../../allocators.zig");
const global = @import("../../global.zig");
const math = @import("../../math.zig");
const ui = @import("../../ui.zig");
const ecs = @import("../../ecs.zig");
const Transform = @import("Transform.zig");

const log = std.log.scoped(.gfx_scene_node);

node: Tree.Node = .{},
name: [:0]const u8,
target: Target,
flags: Flags,
transform: Transform = .{},
matrix: math.Matrix4x4 = math.matrix4x4.identity,

const Self = @This();

pub const excluded_properties: ui.property_editor.PropertyList = &.{.matrix};

pub const Id = ecs.Id;

pub const Type = enum {
    empty,
    camera,
    light,
    object,
    ui,
    text,
};

pub const Target = struct {
    key: [:0]const u8,
    type: Type,

    pub fn node() Target {
        return .{ .key = "", .type = .empty };
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

    pub fn ui(key: [:0]const u8) Target {
        return .{ .key = key, .type = .ui };
    }

    pub fn text(key: [:0]const u8) Target {
        return .{ .key = key, .type = .text };
    }
};

pub const Flags = packed struct {
    is_visible: bool = true,
};

pub fn Flat(comptime T: type) type {
    return struct {
        key: [:0]const u8,
        target: *T,
        transform: math.Matrix4x4,
    };
}

pub const Tree = struct {
    storage: ecs.MultiComponentStorage(Self) = .empty,
    removed: std.ArrayList(Id) = .empty,
    head: Id = .invalid,
    tail: Id = .invalid,

    pub const empty: Tree = .{};
    pub const type_id = ecs.MultiComponentStorage(Self).type_id;

    pub const Slice = struct {
        slice: ecs.MultiComponentStorage(Self).Slice,

        pub fn nodeIdx(self: Slice, idx: Id.Idx) *Node {
            return &self.slice.items(.node)[idx];
        }

        pub fn node(self: Slice, id: Id) *Node {
            return self.nodeIdx(id.idx());
        }

        pub fn name(self: Slice, id: Id) [:0]const u8 {
            return self.slice.items(.name)[id.idx()];
        }

        pub fn namePtr(self: Slice, id: Id) *[:0]const u8 {
            return &self.slice.items(.name)[id.idx()];
        }

        pub fn target(self: Slice, id: Id) *Target {
            return &self.slice.items(.target)[id.idx()];
        }

        pub fn flags(self: Slice, id: Id) *Flags {
            return &self.slice.items(.flags)[id.idx()];
        }

        pub fn transform(self: Slice, id: Id) *Transform {
            return &self.slice.items(.transform)[id.idx()];
        }

        pub fn matrix(self: Slice, id: Id) *math.Matrix4x4 {
            return &self.slice.items(.matrix)[id.idx()];
        }
    };

    pub const Node = struct {
        parent: Id = .invalid,
        prev: Id = .invalid,
        next: Id = .invalid,
        child: Id = .invalid,

        fn assertNew(node: *Node, comptime hasParent: bool) void {
            assert(if (comptime hasParent) node.parent != .invalid else node.parent == .invalid);
            assert(node.prev == .invalid);
            assert(node.next == .invalid);
            assert(node.child == .invalid);
        }
    };

    pub fn deinit(self: *Tree, gpa: std.mem.Allocator) void {
        self.storage.deinit(gpa);
        self.removed.deinit(gpa);
        self.head = .invalid;
        self.tail = .invalid;
    }

    pub fn insert(
        self: *Tree,
        gpa: std.mem.Allocator,
        name: [:0]const u8,
        target: Target,
        transform: *const Transform,
    ) !Id {
        const id = try self.addOne(gpa);
        const s = self.slice();
        const node = s.node(id);
        node.* = .{};
        s.namePtr(id).* = name;
        s.target(id).* = target;
        s.flags(id).* = .{};
        s.transform(id).* = transform.*;
        transform.transform(s.matrix(id));

        if (self.tail == .invalid) {
            assert(self.head == .invalid);
            self.head = id;
        } else {
            const tail_node = s.node(self.tail);
            node.prev = self.tail;
            tail_node.next = id;
        }
        self.tail = id;
        return id;
    }

    pub fn insertChild(
        self: *Tree,
        gpa: std.mem.Allocator,
        parent: Id,
        name: [:0]const u8,
        target: Target,
        transform: *const Transform,
    ) !Id {
        const id = try self.addOne(gpa);
        const s = self.slice();
        const parent_node = s.node(parent);
        const node = s.node(id);
        node.* = .{ .parent = parent };
        s.namePtr(id).* = name;
        s.target(id).* = target;
        s.flags(id).* = .{};
        s.transform(id).* = transform.*;
        var tr: math.Matrix4x4 = undefined;
        transform.transform(&tr);
        math.matrix4x4.dot(s.matrix(id), s.matrix(parent), &tr);

        if (parent_node.child == .invalid) {
            parent_node.child = id;
        } else {
            var child = parent_node.child;
            while (true) {
                const child_node = s.node(child);
                if (child_node.next == .invalid) {
                    node.prev = child;
                    child_node.next = id;
                    break;
                }
                child = child_node.next;
            }
        }
        return id;
    }

    fn addOne(self: *Tree, gpa: std.mem.Allocator) !Id {
        return self.storage.addOne(gpa);
    }

    pub fn remove(self: *Tree, gpa: std.mem.Allocator, id: Id) !void {
        assert(self.storage.isPresent(id));
        try self.removed.append(gpa, id);
    }

    pub fn cleanupRemoved(self: *Tree, gpa: std.mem.Allocator) !void {
        const s = self.slice();
        while (self.removed.pop()) |id| {
            const node = s.node(id);
            if (node.parent.isValid()) {
                const parent = s.node(node.parent);
                if (parent.child == id) parent.child = node.next;
            }
            try self.cleanupNode(gpa, &s, id);
        }
    }

    fn cleanupNode(self: *Tree, gpa: std.mem.Allocator, s: *const Slice, id: Id) !void {
        const node = s.node(id);
        if (self.head == id) self.head = .invalid;
        if (self.tail == id) self.tail = .invalid;
        if (node.prev.isValid()) s.node(node.prev).next = node.next;
        if (node.next.isValid()) s.node(node.next).prev = node.prev;
        node.parent = .invalid;
        node.prev = .invalid;
        node.next = .invalid;
        if (node.child.isValid()) {
            var walk = node.child;
            node.child = .invalid;
            while (walk.isValid()) {
                const next = s.node(walk).next;
                try @call(.always_tail, cleanupNode, .{ self, gpa, s, walk });
                walk = next;
            }
        }
        try self.storage.remove(gpa, id);
    }

    pub fn get(self: *const Tree, id: Id) Self {
        return self.storage.get(id);
    }

    pub fn set(self: *const Tree, id: Id, value: Self) void {
        self.storage.set(id, value);
    }

    pub fn slice(self: *const Tree) Slice {
        return .{ .slice = self.storage.data.slice() };
    }

    pub fn isPresent(self: *const Tree, id: Id) bool {
        return self.storage.isPresent(id);
    }

    pub fn propertyEditor(self: *const Tree, s: *const Slice, id: Id) !ui.Element {
        _ = self;
        try ui.RefPropertyEditor(Self, Id).register();
        return ui.RefPropertyEditor(Self, Id).init(id, .{
            .node = s.node(id),
            .name = s.namePtr(id),
            .target = s.target(id),
            .flags = s.flags(id),
            .transform = s.transform(id),
        });
    }
};

pub fn hasChildren(self: *const Self) bool {
    return self.node.child != .invalid;
}

test Tree {
    const gpa = std.testing.allocator;
    var self: Tree = .empty;
    defer self.deinit(gpa);
    const a = try self.insert(gpa, "A", .node(), &.{});
    try std.testing.expectEqual(self.storage.data.len, 1);
    try std.testing.expectEqual(self.storage.gens.items.len, self.storage.capacity());
    try std.testing.expectEqual(self.removed.items.len, 0);
    try std.testing.expectEqual(self.storage.free.items.len, 0);
    try std.testing.expect(self.storage.present.isSet(0));
    try std.testing.expectEqual(self.head, a);
    try std.testing.expectEqual(self.tail, a);
    {
        const s = self.slice();
        try std.testing.expectEqual(s.node(a).parent, .invalid);
        try std.testing.expectEqual(s.node(a).prev, .invalid);
        try std.testing.expectEqual(s.node(a).next, .invalid);
        try std.testing.expectEqual(s.node(a).child, .invalid);
    }
}
