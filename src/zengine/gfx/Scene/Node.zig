//!
//! The zengine scene node implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const global = @import("../../global.zig");
const math = @import("../../math.zig");
const ui = @import("../../ui.zig");
const Transform = @import("Transform.zig");

const log = std.log.scoped(.gfx_scene_camera);

node: Tree.Node = .{},
name: [:0]const u8,
target: Target,
transform: Transform = .{},

const Self = @This();

pub const Id = enum(u64) {
    invalid = 0,
    _,

    pub const Meta = enum(u16) { invalid, valid };
    pub const Gen = u16;
    pub const Idx = u32;
    pub const Decomposed = packed struct(u64) {
        meta: Meta = .valid,
        gen: Gen,
        idx: Idx,
    };

    pub inline fn compose(id: Decomposed) Id {
        return @enumFromInt(@as(u64, @bitCast(id)));
    }

    pub inline fn decompose(id: Id) Decomposed {
        return @bitCast(@intFromEnum(id));
    }

    pub inline fn isValid(id: Id) bool {
        return id != .invalid;
    }

    pub inline fn gen(id: Id) Idx {
        return id.decompose().gen;
    }

    pub inline fn idx(id: Id) Idx {
        return id.decompose().idx;
    }
};

pub const Type = enum {
    empty,
    camera,
    light,
    object,
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
};

pub fn Flat(comptime T: type) type {
    return struct {
        key: [:0]const u8,
        target: *T,
        transform: math.Matrix4x4,
    };
}

pub const Tree = struct {
    data: std.MultiArrayList(Self) = .empty,
    gens: std.ArrayList(Id.Gen) = .empty,
    free: std.ArrayList(Id.Idx) = .empty,
    present: std.DynamicBitSetUnmanaged = .{},
    head: Id = .invalid,
    tail: Id = .invalid,

    pub const empty: Tree = .{};

    pub const Slice = struct {
        slice: std.MultiArrayList(Self).Slice,

        pub fn node(self: Slice, id: Id) *Node {
            return &self.slice.items(.node)[id.idx()];
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

        pub fn transform(self: Slice, id: Id) *Transform {
            return &self.slice.items(.transform)[id.idx()];
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
        self.data.deinit(gpa);
        self.gens.deinit(gpa);
        self.free.deinit(gpa);
        self.present.deinit(gpa);
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
        s.transform(id).* = transform.*;

        if (self.tail == .invalid) {
            assert(self.head == .invalid);
            self.head = id;
        } else {
            const tail_node = s.node(self.tail);
            node.prev = self.tail;
            tail_node.next = id;
        }
        self.tail = id;
        log.info("{any} {any} {any} {any}", .{ self.head, self.tail, id, self.data.items(.node) });
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
        self.assertPresent(parent);
        const id = try self.addOne(gpa);
        const s = self.slice();
        const parent_node = s.node(parent);
        const node = s.node(id);
        node.* = .{ .parent = parent };
        s.namePtr(id).* = name;
        s.target(id).* = target;
        s.transform(id).* = transform.*;

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
        if (self.free.pop()) |idx| {
            const gen = self.gens.items[idx];
            self.present.set(idx);
            return .compose(.{ .gen = gen, .idx = idx });
        } else {
            const idx = try self.data.addOne(gpa);
            const gen = 0;
            try self.gens.append(gpa, gen);
            if (self.present.bit_length <= idx) try self.present.resize(gpa, idx + 1, false);
            self.present.set(idx);
            return .compose(.{ .gen = gen, .idx = @intCast(idx) });
        }
    }

    pub fn remove(self: *Tree, gpa: std.mem.Allocator, id: Id) !void {
        const d = id.decompose();
        self.assertPresent(d);
        self.gens.items[d.idx] += 1;
        self.present.unset(d.idx);
        try self.free.append(gpa, d.idx);
    }

    pub fn get(self: *const Tree, id: Id) Self {
        const d = id.decompose();
        self.assertPresent(d);
        return self.data.get(d.idx);
    }

    pub fn set(self: *const Tree, id: Id, value: Self) void {
        const d = id.decompose();
        self.assertPresent(d);
        self.data.set(d.idx, value);
    }

    pub fn slice(self: *const Tree) Slice {
        return .{ .slice = self.data.slice() };
    }

    fn assertPresent(self: *const Tree, id: Id) void {
        const d = id.decompose();
        assert(d.idx < self.data.len);
        assert(d.idx < self.present.bit_length);
        assert(self.present.isSet(d.idx));
        assert(d.idx < self.gens.items.len);
        assert(d.gen == self.gens.items[d.idx]);
    }

    pub fn propertyEditor(self: *const Tree, s: *const Slice, id: Id) !ui.UI.Element {
        _ = self;
        try ui.RefPropertyEditor(Self, Id).register();
        return ui.RefPropertyEditor(Self, Id).init(id, .{
            .node = s.node(id),
            .name = s.namePtr(id),
            .target = s.target(id),
            .transform = s.transform(id),
        });
    }
};

pub fn hasChildren(self: *const Self) bool {
    return self.node.child != .invalid;
}
