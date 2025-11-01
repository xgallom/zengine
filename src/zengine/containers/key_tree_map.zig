//!
//! The zengine key tree implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const log = std.log.scoped(.key_tree);

pub const InsertionOrder = enum {
    ordered,
    insert_first,
    insert_last,
};

/// Key tree map data structure
pub fn KeyTreeMap(comptime V: type, comptime options: struct {
    pool_options: std.heap.MemoryPoolOptions = .{},
    insertion_order: InsertionOrder = .ordered,
    separator: u8 = '.',
    has_depth: bool = false,
    is_big: bool = @sizeOf(V) >= 16,
}) type {
    return struct {
        pool: Pool,
        root: *Node = undefined,

        pub const Self = @This();
        pub const Value = V;
        const ValIn = if (options.is_big) *const V else V;

        const Pool = std.heap.MemoryPoolExtra(Edge, options.pool_options);

        pub const Edges = std.SinglyLinkedList;

        pub const Edge = struct {
            edge_node: Edges.Node,
            label: [:0]const u8,
            target: Node,
        };

        pub const Node = struct {
            value: ?Value,
            edges: Edges,
            depth: if (options.has_depth) u32 else void = if (options.has_depth) 0 else {},

            pub fn deinit(node: *Node, self: *Self) usize {
                log.warn("deinit", .{});
                const count = node.clearEdges(self);
                self.destroyNode(node);
                return count + 1;
            }

            fn clearEdges(node: *Node, self: *Self) usize {
                var count: usize = 0;
                while (node.edges.popFirst()) |edge_node| {
                    const edge: *Edge = @fieldParentPtr("edge_node", edge_node);
                    count += edge.target.deinit(self);
                }
                return count;
            }

            pub fn isLeaf(self: *const Node) bool {
                return self.edges.first == null;
            }
        };

        // Initializes the tree
        pub fn init(allocator: std.mem.Allocator, preheat: usize) !Self {
            var result = Self{ .pool = try Pool.initPreheated(allocator, preheat) };
            result.root = &(try result.createEdge(&.{}, null)).target;
            return result;
        }

        /// Deinitializes the tree
        pub fn deinit(self: *Self) void {
            self.pool.deinit();
        }

        pub fn get(self: *const Self, key: []const u8) ?Value {
            if (self.getPtr(key)) |ptr| return ptr.*;
            return null;
        }

        pub fn getPtr(self: *const Self, key: []const u8) ?*Value {
            const node = self.getNode(key);
            if (node == null or node.?.value == null) return null;
            return &node.?.value.?;
        }

        pub fn getNode(self: *const Self, key: []const u8) ?*Node {
            var walk = self.root;
            var iter = std.mem.splitScalar(u8, key, options.separator);

            walk: while (iter.next()) |label| {
                var edge_node = walk.edges.first;

                log.debug("label {s}", .{label});

                while (edge_node != null) : (edge_node = edge_node.?.next) {
                    const edge: *Edge = @fieldParentPtr("edge_node", edge_node.?);

                    if (std.mem.eql(u8, edge.label, label)) {
                        log.debug("traverse edge", .{});
                        walk = &edge.target;
                        continue :walk;
                    }
                }

                return null;
            }

            return walk;
        }

        /// Inserts new value into the tree
        pub fn insert(self: *Self, key: []const u8, value: ValIn) !*Value {
            return self.insertWithOrder(key, value, options.insertion_order);
        }

        pub fn insertWithOrder(self: *Self, key: []const u8, value: ValIn, comptime order: InsertionOrder) !*Value {
            var walk = self.root;
            var iter = std.mem.splitScalar(u8, key, options.separator);

            log.debug("insert [{s}]: ", .{key});
            walk: while (iter.next()) |label| {
                var edge_node = walk.edges.first;

                log.debug("label {s}", .{label});

                while (edge_node != null) : (edge_node = edge_node.?.next) {
                    const edge: *Edge = @fieldParentPtr("edge_node", edge_node.?);

                    if (std.mem.eql(u8, edge.label, label)) {
                        log.debug("traverse edge", .{});
                        walk = &edge.target;
                        continue :walk;
                    }
                }

                log.debug("add node", .{});
                const child = try self.addNode(walk, try self.createLabel(label), order);
                if (comptime options.has_depth) child.depth = walk.depth + 1;
                walk = child;
            }

            walk.value = if (options.is_big) value.* else value;
            return &walk.value.?;
        }

        fn addNode(self: *Self, parent: *Node, label: [:0]const u8, comptime order: InsertionOrder) !*Node {
            const edge = try self.createEdge(label, null);
            switch (comptime order) {
                .ordered => orderedInsert(&parent.edges.first, edge),
                .insert_first => parent.edges.prepend(&edge.edge_node),
                .insert_last => lastInsert(&parent.edges.first, edge),
            }
            return &edge.target;
        }

        fn orderedInsert(head: *?*Edges.Node, edge: *Edge) void {
            const edge_node = &edge.edge_node;

            if (head.* == null or orderEdges(@fieldParentPtr("edge_node", head.*.?), edge).compare(.gte)) {
                edge_node.next = head.*;
                head.* = edge_node;
                return;
            }

            var current = head.*.?;
            while (current.next != null and
                orderEdges(
                    @fieldParentPtr("edge_node", current.next.?),
                    edge,
                ).compare(.lt)) : (current = current.next.?)
            {}

            edge_node.next = current.next;
            current.next = edge_node;
        }

        fn lastInsert(head: *?*Edges.Node, edge: *Edge) void {
            const edge_node = &edge.edge_node;
            if (head.* == null) {
                head.* = edge_node;
            } else {
                head.*.?.findLast().insertAfter(edge_node);
            }
        }

        fn orderEdges(lhs: *Edge, rhs: *Edge) std.math.Order {
            return std.mem.order(u8, lhs.label, rhs.label);
        }

        fn createEdge(self: *Self, label: [:0]const u8, value: ?ValIn) !*Edge {
            const edge = try self.pool.create();
            edge.* = .{
                .edge_node = .{},
                .label = label,
                .target = .{
                    .value = if (comptime options.is_big) (if (value) |v| v.* else null) else value,
                    .edges = .{},
                },
            };
            return edge;
        }

        fn createLabel(self: *Self, label: []const u8) ![:0]const u8 {
            const allocator: std.mem.Allocator = self.pool.arena.allocator();
            return allocator.dupeZ(u8, label);
        }

        fn destroyNode(self: *Self, node: *Node) void {
            log.warn("destroy 0x{x}", .{@intFromPtr(node)});
            self.pool.destroy(@fieldParentPtr("target", node));
        }

        fn destroyEdge(self: *Self, edge: *Edge) void {
            self.pool.destroy(edge);
        }

        pub fn iterate(
            self: *const Self,
            comptime C: type,
            comptime callback: fn (self: *const Self, edge: *Edge, ctx: C) void,
            ctx: C,
        ) void {
            var iter: Iterator(C, callback) = .{ .self = self, .ctx = ctx };
            iter.run(@fieldParentPtr("target", self.root));
        }

        pub fn Iterator(
            comptime C: type,
            comptime callback: fn (self: *const Self, edge: *Edge, ctx: C) void,
        ) type {
            return struct {
                self: *const Self,
                ctx: C,
                pub fn run(i: *const @This(), edge: *Edge) void {
                    callback(i.self, edge, i.ctx);
                    if (edge.target.edges.first) |edge_node| {
                        i.run(@fieldParentPtr("edge_node", edge_node));
                    }
                    if (edge.edge_node.next) |edge_node| {
                        i.run(@fieldParentPtr("edge_node", edge_node));
                    }
                }
            };
        }
    };
}
