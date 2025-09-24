//!
//! The zengine key tree implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const log = std.log.scoped(.tree);

pub const InsertionOrder = enum {
    ordered,
    insert_first,
    insert_last,
};

/// Tree data structure
pub fn Tree(comptime V: type, comptime options: struct {
    pool_options: std.heap.MemoryPoolOptions = .{},
    insertion_order: InsertionOrder = .insert_last,
    order_fn: ?*const fn (lhs: *const V, rhs: *const V) std.math.Order = null,
    has_depth: bool = false,
}) type {
    return struct {
        pool: Pool,
        edges: Edges = .{},

        pub const Self = @This();
        pub const Value = V;

        const Pool = std.heap.MemoryPoolExtra(Node, options.pool_options);

        pub const Edges = std.SinglyLinkedList;

        pub const Edge = Node;
        pub const Node = struct {
            parent: ?*Node,
            edge_node: Edges.Node,
            edges: Edges,
            value: Value,
            depth: if (options.has_depth) u32 else void = if (options.has_depth) 0 else {},

            pub fn deinit(node: *Node, self: *Self) usize {
                const count = node.clearEdges(self);
                self.destroyNode(node);
                return count + 1;
            }

            fn clearEdges(node: *Node, self: *Self) usize {
                var count: usize = 0;
                while (node.edges.popFirst()) |edge_node| {
                    const edge: *Node = @fieldParentPtr("edge_node", edge_node);
                    count += edge.deinit(self);
                }
                return count;
            }

            pub fn isLeaf(self: *const Node) bool {
                return self.edges.first == null;
            }

            pub fn insert(parent: *Node, self: *Self, value: Value) !*Node {
                const child = try self.addNode(&parent.edges, value);
                child.parent = parent;
                if (comptime options.has_depth) child.depth = parent.depth + 1;
                return child;
            }

            pub fn iterator(node: *Node) EdgeIterator {
                return .{ .curr = node.edges.first };
            }
        };

        pub const EdgeIterator = struct {
            curr: ?*Edges.Node,

            pub fn next(i: *EdgeIterator) ?*Node {
                if (i.curr) |curr| {
                    defer i.curr = curr.next;
                    return curr;
                }
                return null;
            }
        };

        pub const Pusher = struct {
            self: *Self,
            curr: ?*Node,

            pub fn push(p: *Pusher, value: Value) !*Node {
                if (p.curr) |curr| {
                    log.debug("push {f}", .{value});
                    p.curr = try curr.insert(p.self, value);
                } else {
                    log.debug("push {f}", .{value});
                    p.curr = try p.self.insert(value);
                }
                return p.curr.?;
            }

            pub fn pop(p: *Pusher) ?*Node {
                log.debug("pop", .{});
                if (p.curr) |curr| p.curr = curr.parent;
                return p.curr;
            }
        };

        pub fn iterator(self: *Self) EdgeIterator {
            return .{ .curr = self.edges.first };
        }

        pub fn pusher(self: *Self) Pusher {
            return .{ .self = self, .curr = null };
        }

        // Initializes the tree
        pub fn init(allocator: std.mem.Allocator, preheat: usize) !Self {
            return .{ .pool = try Pool.initPreheated(allocator, preheat) };
        }

        /// Deinitializes the tree
        pub fn deinit(self: *Self) void {
            self.pool.deinit();
        }

        /// Inserts new value into the root
        pub fn insert(self: *Self, value: Value) !*Node {
            return try self.addNode(&self.edges, value);
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            while (self.edges.popFirst()) |edge| {
                const node: *Node = @fieldParentPtr("edge_node", edge);
                _ = node.deinit(self);
            }
        }

        fn addNode(self: *Self, edges: *Edges, value: Value) !*Node {
            const node = try self.createNode(value);
            switch (comptime options.insertion_order) {
                .ordered => orderedInsert(&edges.first, node),
                .insert_first => edges.prepend(&node.edge_node),
                .insert_last => lastInsert(&edges.first, node),
            }
            return node;
        }

        fn orderedInsert(head: *?*Edges.Node, node: *Node) void {
            const edge_node = &node.edge_node;

            if (head.* == null or order(
                @fieldParentPtr("edge_node", head.*.?),
                node,
            ).compare(.gte)) {
                edge_node.next = head.*;
                head.* = edge_node;
                return;
            }

            var current = head.*.?;
            while (current.next != null and order(
                @fieldParentPtr("edge_node", current.next.?),
                node,
            ).compare(.lt)) : (current = current.next.?) {}

            edge_node.next = current.next;
            current.next = edge_node;
        }

        fn lastInsert(head: *?*Edges.Node, node: *Node) void {
            const edge_node = &node.edge_node;
            if (head.* == null) {
                head.* = edge_node;
            } else {
                head.*.?.findLast().insertAfter(edge_node);
            }
        }

        fn order(lhs: *Node, rhs: *Node) std.math.Order {
            comptime if (options.order_fn == null) {
                @compileError("Can not use ordered insert without a compare function");
            };
            return options.order_fn.?(lhs.value.?, rhs.value.?);
        }

        fn createNode(self: *Self, value: Value) !*Node {
            const node = try self.pool.create();
            node.* = .{
                .parent = null,
                .edge_node = .{},
                .edges = .{},
                .value = value,
            };
            return node;
        }

        fn destroyNode(self: *Self, node: *Node) void {
            self.pool.destroy(node);
        }
    };
}
