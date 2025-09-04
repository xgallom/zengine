//!
//! The zengine key tree implementation
//!

const std = @import("std");
const assert = std.debug.assert;
const log = std.log.scoped(.key_tree);

/// Key tree data structure
pub fn KeyTree(comptime V: type, comptime options: std.heap.MemoryPoolOptions) type {
    return struct {
        pool: Pool,
        root: *Node = undefined,

        pub const Self = @This();
        pub const Value = V;

        const Pool = std.heap.MemoryPoolExtra(PoolItem, options);
        const PoolItem = union {
            node: Node,
            edge: Edge,
        };

        pub const Edges = std.SinglyLinkedList;

        pub const Edge = struct {
            edge_node: Edges.Node,
            label: []const u8,
            target: *Node,
        };

        pub const Node = struct {
            value: ?Value = null,
            edges: Edges = .{},

            fn deinit(node: *Node, self: *Self) usize {
                const count = node.clearEdges(self);
                self.destroyNode(node);
                return count + 1;
            }

            fn clearEdges(node: *Node, self: *Self) usize {
                var count: usize = 0;
                while (node.edges.popFirst()) |edge_node| {
                    const edge: *Edge = @fieldParentPtr("edge_node", edge_node);
                    count += edge.target.deinit(self);
                    self.destroyEdge(edge);
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
            result.root = try result.createNode(null);
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
            var walk = self.root;
            var iter = std.mem.splitScalar(u8, key, '.');

            walk: while (iter.next()) |label| {
                var edge_node = walk.edges.first;

                log.debug("label {s}", .{label});

                while (edge_node != null) : (edge_node = edge_node.?.next) {
                    const edge: *Edge = @fieldParentPtr("edge_node", edge_node.?);

                    if (std.mem.eql(u8, edge.label, label)) {
                        log.debug("traverse edge", .{});
                        walk = edge.target;
                        continue :walk;
                    }
                }

                return null;
            }

            if (walk.value == null) return null;
            return &walk.value.?;
        }

        /// Inserts new value into the tree
        pub fn insert(self: *Self, key: []const u8, value: Value) !void {
            var walk = self.root;
            var iter = std.mem.splitScalar(u8, key, '.');

            log.debug("insert [{s}]: ", .{key});
            walk: while (iter.next()) |label| {
                var edge_node = walk.edges.first;

                log.debug("label {s}", .{label});

                while (edge_node != null) : (edge_node = edge_node.?.next) {
                    const edge: *Edge = @fieldParentPtr("edge_node", edge_node.?);

                    if (std.mem.eql(u8, edge.label, label)) {
                        log.debug("traverse edge", .{});
                        walk = edge.target;
                        continue :walk;
                    }
                }

                log.debug("add node", .{});
                walk = try self.addNode(walk, try self.createLabel(label));
            }

            walk.value = value;
        }

        fn addNode(self: *Self, parent: *Node, label: []const u8) !*Node {
            const node = try self.createNode(null);
            orderedInsert(&parent.edges.first, try self.createEdge(label, node));
            return node;
        }

        fn orderedInsert(head: *?*Edges.Node, edge: *Edge) void {
            const edge_node = &edge.edge_node;

            if (head.* == null or order(@fieldParentPtr("edge_node", head.*.?), edge).compare(.gte)) {
                edge_node.next = head.*;
                head.* = edge_node;
                return;
            }

            var current = head.*.?;
            while (current.next != null and order(@fieldParentPtr("edge_node", current.next.?), edge).compare(.lt)) : (current = current.next.?) {}

            edge_node.next = current.next;
            current.next = edge_node;
        }

        fn order(lhs: *Edge, rhs: *Edge) std.math.Order {
            return std.mem.order(u8, lhs.label, rhs.label);
        }

        fn createNode(self: *Self, value: ?Value) !*Node {
            const pool_item: *PoolItem = try self.pool.create();
            pool_item.* = .{ .node = .{ .value = value } };
            return &pool_item.node;
        }

        fn createEdge(self: *Self, label: []const u8, target: *Node) !*Edge {
            const pool_item: *PoolItem = try self.pool.create();
            pool_item.* = .{ .edge = .{
                .edge_node = .{},
                .label = label,
                .target = target,
            } };
            return &pool_item.edge;
        }

        fn createLabel(self: *Self, label: []const u8) ![]const u8 {
            const allocator: std.mem.Allocator = self.pool.arena.allocator();
            const result = try allocator.alloc(u8, label.len);
            @memcpy(result, label);
            return result;
        }

        fn destroyNode(self: *Self, node: *Node) void {
            self.pool.destroy(@ptrCast(node));
        }

        fn destroyEdge(self: *Self, edge: *Edge) void {
            self.pool.destroy(@ptrCast(edge));
        }
    };
}
