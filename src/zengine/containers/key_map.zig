//!
//! The zengine key map implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const log = std.log.scoped(.key_tree);

/// Key map data structure
pub fn ArrayKeyMap(comptime V: type, comptime options: struct {
    pool_options: std.heap.MemoryPoolOptions = .{},
    is_big: bool = @sizeOf(V) > 16,
}) type {
    return struct {
        pool: Pool,
        map: std.StringArrayHashMapUnmanaged(*V) = .empty,

        pub const Self = @This();
        pub const Value = V;
        const Pool = std.heap.MemoryPoolExtra(V, options.pool_options);
        const ValIn = if (options.is_big) *const V else V;

        // Initializes the map
        pub fn init(allocator: std.mem.Allocator, preheat: usize) !Self {
            var result: Self = .{
                .pool = try Pool.initPreheated(allocator, preheat),
            };
            try result.map.ensureTotalCapacity(allocator, preheat);
            return result;
        }

        /// Deinitializes the map
        pub fn deinit(self: *Self) void {
            self.map.deinit(self.gpa());
            self.pool.deinit();
        }

        pub fn contains(self: *const Self, key: []const u8) bool {
            return self.map.contains(key);
        }

        pub fn get(self: *const Self, key: []const u8) V {
            const ptr = self.map.get(key);
            assert(ptr != null);
            return ptr.?.*;
        }

        pub fn getOrNull(self: *const Self, key: []const u8) ?V {
            if (self.map.get(key)) |ptr| return ptr.*;
            return null;
        }

        pub fn getPtr(self: *const Self, key: []const u8) *V {
            const ptr = self.map.get(key);
            assert(ptr != null);
            return ptr.?;
        }

        pub fn getPtrOrNull(self: *const Self, key: []const u8) ?*V {
            return self.map.get(key);
        }

        // Creates a new uninitialized value
        pub fn create(self: *Self, key: []const u8) !*V {
            const item = try self.pool.create();
            try self.map.putNoClobber(self.gpa(), key, item);
            return item;
        }

        /// Inserts new value into the map
        pub fn insert(self: *Self, key: []const u8, value: ValIn) !*V {
            const item = try self.create(key);
            item.* = if (comptime options.is_big) value.* else value;
            return item;
        }

        /// Removes a value from the map
        pub fn remove(self: *Self, key: []const u8) void {
            const entry = self.map.fetchSwapRemove(key);
            assert(entry != null);
            self.pool.destroy(entry.?.value);
        }

        inline fn gpa(self: *const Self) std.mem.Allocator {
            return self.pool.arena.child_allocator;
        }
    };
}

/// Pointer key map data structure
pub fn ArrayPtrKeyMap(comptime V: type) type {
    return struct {
        map: HashMap = .empty,

        pub const Self = @This();
        pub const Value = V;
        pub const HashMap = std.StringArrayHashMapUnmanaged(*V);

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

        pub fn contains(self: *const Self, key: []const u8) bool {
            return self.map.contains(key);
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

        pub fn values(self: *const Self) []*V {
            return self.map.values();
        }
    };
}

/// Sparse key map data structure
pub fn KeyMap(comptime V: type, comptime options: struct {
    pool_options: std.heap.MemoryPoolOptions = .{},
    is_big: bool = @sizeOf(V) > 16,
}) type {
    return struct {
        pool: Pool,
        map: PtrHashMap(V) = .empty,

        pub const Self = @This();
        const Pool = std.heap.MemoryPoolExtra(V, options.pool_options);
        const ValIn = if (options.is_big) *const V else V;

        // Initializes the map
        pub fn init(allocator: std.mem.Allocator, preheat: u32) !Self {
            var result: Self = .{
                .pool = try Pool.initPreheated(allocator, preheat),
            };
            try result.map.ensureTotalCapacity(allocator, preheat);
            return result;
        }

        /// Deinitializes the map
        pub fn deinit(self: *Self) void {
            self.map.deinit(self.gpa());
            self.pool.deinit();
        }

        pub fn contains(self: *const Self, key: []const u8) bool {
            return self.map.contains(key);
        }

        pub fn get(self: *const Self, key: []const u8) V {
            const ptr = self.map.get(key);
            assert(ptr != null);
            return ptr.?.*;
        }

        pub fn getOrNull(self: *const Self, key: []const u8) ?V {
            if (self.map.get(key)) |ptr| return ptr.*;
            return null;
        }

        pub fn getPtr(self: *const Self, key: []const u8) *V {
            const ptr = self.map.get(key);
            assert(ptr != null);
            return ptr.?;
        }

        pub fn getPtrOrNull(self: *const Self, key: []const u8) ?*V {
            return self.map.get(key);
        }

        // Creates a new uninitialized value
        pub fn create(self: *Self, key: []const u8) !*V {
            const item = try self.pool.create();
            try self.map.putNoClobber(self.gpa(), key, item);
            return item;
        }

        /// Inserts new value into the map
        pub fn insert(self: *Self, key: []const u8, value: ValIn) !*V {
            const item = try self.create(key);
            item.* = if (comptime options.is_big) value.* else value;
            return item;
        }

        /// Removes a value from the map
        pub fn remove(self: *Self, key: []const u8) void {
            const entry = self.map.fetchRemove(key);
            assert(entry != null);
            self.pool.destroy(entry.?.value);
        }

        inline fn gpa(self: *const Self) std.mem.Allocator {
            return self.pool.arena.child_allocator;
        }

        pub fn valueIterator(self: *const Self) ValueIterator {
            return .{ .iter = self.map.valueIterator() };
        }

        pub const ValueIterator = PtrValueIterator(V);
    };
}

/// Sparse pointer key map data structure
pub fn PtrKeyMap(comptime V: type) type {
    return struct {
        map: PtrHashMap(V) = .empty,

        pub const Self = @This();
        pub const Value = V;

        // Initializes the map
        pub fn init(gpa: std.mem.Allocator, preheat: u32) !Self {
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
        pub fn insert(self: *Self, gpa: std.mem.Allocator, key: []const u8, value: *V) !void {
            try self.map.putNoClobber(gpa, key, value);
        }

        /// Removes existing pointer value from the map
        pub fn remove(self: *Self, key: []const u8) void {
            assert(self.map.remove(key));
        }

        pub fn valueIterator(self: *const Self) ValueIterator {
            return .{ .iter = self.map.valueIterator() };
        }

        pub const ValueIterator = PtrValueIterator(V);
    };
}

pub fn PtrValueIterator(comptime V: type) type {
    return struct {
        iter: PtrHashMap(V).ValueIterator,

        pub fn next(i: *@This()) ?*V {
            if (i.iter.next()) |ptr| return ptr.*;
            return null;
        }
    };
}

fn PtrHashMap(comptime V: type) type {
    return std.StringHashMapUnmanaged(*V);
}
