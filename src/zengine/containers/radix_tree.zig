//!
//! The zengine radix tree implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const log = std.log.scoped(.radix_tree);

/// Radix tree data structure
pub fn RadixTree(comptime V: type, comptime options: std.heap.MemoryPoolOptions) type {
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
            label: [:0]const u8,
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

        // Initializes the radix tree
        pub fn init(allocator: std.mem.Allocator, preheat: usize) !Self {
            var result = Self{ .pool = try Pool.initPreheated(allocator, preheat) };
            result.root = try result.createNode(null);
            return result;
        }

        /// Deinitializes the radix tree
        pub fn deinit(self: *Self) void {
            self.pool.deinit();
        }

        /// .prefix: returns any value with label shorter or equal to searched label
        /// .exact : returns value matching searched label exactly
        /// .suffix: returns first value with smallest label longer or equal to search label
        pub const SearchType = enum {
            prefix,
            exact,
            suffix,
        };

        /// Searches tree according to one of the search types
        pub fn search(self: *const Self, label: []const u8, search_type: SearchType) ?*const Node {
            return switch (search_type) {
                .prefix => self.searchPrefix(label),
                .exact => self.searchExact(label),
                .suffix => self.searchSuffix(label),
            };
        }

        /// Searches tree and returns any value with label shorter or equal to searched label
        pub fn searchPrefix(self: *const Self, label: []const u8) ?*const Node {
            var walk = self.root;
            var needle = label;

            log.debug("searchPrefix [{s}]", .{label});
            loop: while (true) {
                var edge_node = walk.edges.first;
                var edge_found = false;
                while (edge_node != null) : (edge_node = edge_node.?.next) {
                    const edge: *Edge = @fieldParentPtr("edge_node", edge_node.?);
                    if (edge.label.len == 0) continue;

                    const common = commonStart(edge.label, needle);
                    log.debug("common {s} ( {s} & {s} )", .{ edge.label[0..common], edge.label, needle });

                    if (common >= edge.label.len) {
                        walk = edge.target;
                        if (common == needle.len) break :loop;

                        log.debug("traverse edge", .{});
                        edge_found = true;
                        needle = needle[edge.label.len..];
                        break;
                    }
                }

                if (!edge_found) break;
            }

            log.debug("found edge", .{});
            if (walk.isLeaf()) return walk;
            const edge: *const Edge = @fieldParentPtr("edge_node", walk.edges.first.?);
            if (edge.label.len == 0) return edge.target;
            return null;
        }

        /// Searches tree and returns value matching searched label exactly
        pub fn searchExact(self: *const Self, label: []const u8) ?*const Node {
            var walk = self.root;
            var needle = label;

            log.debug("searchExact [{s}]", .{label});
            loop: while (true) {
                var edge_node = walk.edges.first;
                var edge_found = false;
                while (edge_node != null) : (edge_node = edge_node.?.next) {
                    const edge: *Edge = @fieldParentPtr("edge_node", edge_node.?);
                    if (edge.label.len == 0) continue;

                    const common = commonStart(edge.label, needle);
                    log.debug("common {s} ( {s} & {s} )", .{ edge.label[0..common], edge.label, needle });

                    if (common >= edge.label.len) {
                        walk = edge.target;
                        if (common == needle.len) break :loop;

                        log.debug("traverse edge", .{});
                        edge_found = true;
                        needle = needle[edge.label.len..];
                        break;
                    }
                }

                if (!edge_found) return null;
            }

            log.debug("found edge", .{});
            if (walk.isLeaf()) return walk;
            const edge: *const Edge = @fieldParentPtr("edge_node", walk.edges.first.?);
            if (edge.label.len == 0) return edge.target;
            return null;
        }

        /// Searches tree and returns first value with smallest label longer or equal to search label
        pub fn searchSuffix(self: *const Self, label: []const u8) ?*const Node {
            var walk = self.root;
            var needle = label;

            log.debug("searchSuffix [{s}]", .{label});
            loop: while (true) {
                var edge_node = walk.edges.first;
                var edge_found = false;
                while (edge_node != null) : (edge_node = edge_node.?.next) {
                    const edge: *Edge = @fieldParentPtr("edge_node", edge_node.?);
                    if (edge.label.len == 0) continue;

                    const common = commonStart(edge.label, needle);
                    log.debug("common {s} ( {s} & {s} )", .{ edge.label[0..common], edge.label, needle });

                    if (common >= edge.label.len) {
                        walk = edge.target;
                        if (common == needle.len) break :loop;

                        log.debug("traverse edge", .{});
                        edge_found = true;
                        needle = needle[edge.label.len..];
                        break;
                    }
                    if (common >= needle.len and needle.len != 0) {
                        walk = edge.target;
                        break :loop;
                    }
                }

                if (!edge_found) return null;
            }

            log.debug("found edge", .{});
            while (!walk.isLeaf()) {
                const edge: *const Edge = @fieldParentPtr("edge_node", walk.edges.first.?);
                walk = edge.target;
            }
            return walk;
        }

        /// Inserts new value into the tree
        pub fn insert(self: *Self, label: []const u8, value: Value) !void {
            var walk = self.root;
            var needle = label;

            log.debug("insert [{s}]: ", .{label});
            while (true) {
                var edge_node = walk.edges.first;
                var edge_found = false;

                while (edge_node != null) : (edge_node = edge_node.?.next) {
                    const edge: *Edge = @fieldParentPtr("edge_node", edge_node.?);

                    const common = commonStart(edge.label, needle);
                    if (common == 0) continue;

                    const base_label = edge.label[0..common];
                    const node_label = edge.label[common..];
                    needle = needle[common..];

                    log.debug("common {s} ( {s} | {s} )", .{ base_label, node_label, needle });

                    if (common == edge.label.len and !edge.target.isLeaf()) {
                        log.debug("traverse edge", .{});
                        edge_found = true;
                        walk = edge.target;
                        break;
                    } else {
                        log.debug("split edge", .{});
                        try self.splitEdge(edge, base_label, node_label, try self.createLabel(needle), value);
                        return;
                    }
                }

                if (!edge_found) {
                    log.debug("add node", .{});
                    try self.addNode(walk, try self.createLabel(needle), value);
                    return;
                }
            }
        }

        pub fn remove(self: *Self, label: []const u8) usize {
            if (label.len == 0) return self.root.clearEdges(self);

            var walk = self.root;
            var needle = label;

            while (true) {
                var edge_node = walk.edges.first;
                var edge_found = false;

                while (edge_node != null) : (edge_node = edge_node.?.next) {
                    const edge: *Edge = @fieldParentPtr("edge_node", edge_node.?);

                    const common = commonStart(edge.label, needle);
                    if (common == 0) continue;

                    if (common >= needle.len) {
                        const count = edge.target.deinit();
                        walk.edges.remove(edge_node);
                        return count;
                    }

                    if (common >= edge.label.len) {
                        edge_found = true;
                        walk = edge.target;
                        needle = needle[common..];
                        break;
                    }
                }

                if (!edge_found) return 0;
            }
        }

        fn splitEdge(self: *Self, edge: *Edge, base_label: [:0]const u8, node_label: [:0]const u8, new_label: [:0]const u8, new_value: Value) !void {
            const parent = try self.createNode(null);
            const old_node = edge.target;
            edge.label = base_label;
            edge.target = parent;
            try self.reparentNode(parent, node_label, old_node);
            try self.addNode(parent, new_label, new_value);
        }

        fn addNode(self: *Self, parent: *Node, label: [:0]const u8, value: Value) !void {
            try self.reparentNode(parent, label, try self.createNode(value));
        }

        fn reparentNode(self: *Self, parent: *Node, label: [:0]const u8, node: *Node) !void {
            orderedInsert(&parent.edges.first, try self.createEdge(label, node));
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

        fn createEdge(self: *Self, label: [:0]const u8, target: *Node) !*Edge {
            const pool_item: *PoolItem = try self.pool.create();
            pool_item.* = .{ .edge = .{
                .edge_node = .{},
                .label = label,
                .target = target,
            } };
            return &pool_item.edge;
        }

        fn createLabel(self: *Self, label: []const u8) ![:0]const u8 {
            const allocator: std.mem.Allocator = self.pool.arena.allocator();
            return allocator.dupeZ(label);
        }

        fn destroyNode(self: *Self, node: *Node) void {
            self.pool.destroy(@ptrCast(node));
        }

        fn destroyEdge(self: *Self, edge: *Edge) void {
            self.pool.destroy(@ptrCast(edge));
        }

        fn commonStart(label: []const u8, needle: []const u8) usize {
            const end = @min(label.len, needle.len);
            for (0..end, label[0..end], needle[0..end]) |n, a, b| {
                if (a != b) return n;
            }
            return end;
        }
    };
}
