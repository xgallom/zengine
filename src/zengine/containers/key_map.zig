//!
//! The zengine key map implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const log = std.log.scoped(.key_tree);

/// Key map data structure
pub fn KeyMap(comptime V: type, comptime options: struct {
    pool_options: std.heap.MemoryPoolOptions = .{},
}) type {
    return struct {
        pool: Pool,
        map: PtrKeyMap(V),

        pub const Self = @This();
        pub const Value = V;

        const Pool = std.heap.MemoryPoolExtra(V, options.pool_options);

        // Initializes the map
        pub fn init(allocator: std.mem.Allocator, preheat: usize) !Self {
            return .{
                .pool = try Pool.initPreheated(allocator, preheat),
                .map = try .init(allocator, preheat),
            };
        }

        /// Deinitializes the map
        pub fn deinit(self: *Self) void {
            self.map.deinit(self.pool.arena.child_allocator);
            self.pool.deinit();
        }

        pub fn get(self: *const Self, key: []const u8) V {
            return self.map.getPtr(key).*;
        }

        pub fn getOrNull(self: *const Self, key: []const u8) ?V {
            if (self.map.getPtrOrNull(key)) |ptr| return ptr.*;
            return null;
        }

        pub fn getPtr(self: *const Self, key: []const u8) *V {
            return self.map.getPtr(key);
        }

        pub fn getPtrOrNull(self: *const Self, key: []const u8) ?*V {
            return self.map.getPtrOrNull(key);
        }

        /// Inserts new value into the map
        pub fn insert(self: *Self, key: []const u8, value: V) !*V {
            const item = try self.pool.create();
            item.* = value;
            try self.map.insert(self.pool.arena.child_allocator, key, item);
            return item;
        }

        /// Removes a value from the map
        pub fn remove(self: *Self, key: []const u8) void {
            const entry = self.map.map.fetchSwapRemove(key);
            assert(entry != null);
            self.pool.destroy(entry.?.value);
        }
    };
}

pub fn PtrKeyMap(comptime V: type) type {
    return struct {
        map: std.StringArrayHashMapUnmanaged(*V) = .empty,

        pub const Self = @This();
        pub const Value = V;

        // Initializes the map
        pub fn init(gpa: std.mem.Allocator, preheat: usize) !Self {
            var result: Self = .{};
            try result.map.ensureTotalCapacity(gpa, preheat);
            return result;
        }

        /// Deinitializes the map
        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            self.map.deinit(gpa);
        }

        pub fn getPtr(self: *const Self, key: []const u8) *V {
            const ptr = self.map.get(key);
            assert(ptr != null);
            return ptr.?;
        }

        pub fn getPtrOrNull(self: *const Self, key: []const u8) ?*V {
            return self.map.get(key);
        }

        /// Inserts new pointer value into the map
        pub fn insert(self: *Self, gpa: std.mem.Allocator, key: []const u8, ptr: *V) !void {
            try self.map.putNoClobber(gpa, key, ptr);
        }

        /// Removes existing pointer value from the map
        pub fn remove(self: *Self, key: []const u8) void {
            const idx = self.map.getIndex(key);
            assert(idx != null);
            self.map.swapRemoveAt(idx);
        }
    };
}

pub fn SparseKeyMap(comptime V: type) type {
    return struct {
        map: std.StringHashMapUnmanaged(V),

        pub const Self = @This();
        pub const Value = V;

        // Initializes the map
        pub fn init(gpa: std.mem.Allocator, preheat: usize) !Self {
            var result = Self{ .map = .empty };
            try result.map.ensureTotalCapacity(gpa, preheat);
            return result;
        }

        /// Deinitializes the map
        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            self.map.deinit(gpa);
        }

        pub fn get(self: *const Self, key: []const u8) V {
            const ptr = self.map.getPtr(key);
            assert(ptr != null);
            return ptr.*;
        }

        pub fn getOrNull(self: *const Self, key: []const u8) ?V {
            if (self.map.getPtr(key)) |ptr| return ptr.*;
            return null;
        }

        pub fn getPtr(self: *const Self, key: []const u8) ?*V {
            return self.map.getPtr(key);
        }

        /// Inserts new pointer value into the map
        pub fn insert(self: *Self, gpa: std.mem.Allocator, key: []const u8, value: V) !void {
            try self.map.putNoClobber(gpa, key, value);
        }

        /// Removes existing pointer value from the map
        pub fn remove(self: *Self, key: []const u8) void {
            assert(self.map.remove(key));
        }
    };
}
