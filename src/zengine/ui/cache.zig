//!
//! The zengine ui element cache
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const UI = @import("UI.zig");

const log = std.log.scoped(.ui_cache);
// pub const sections = perf.sections(@This(), &.{ .init, .draw });

pub fn Cache(comptime K: type) type {
    return struct {
        map: std.AutoHashMapUnmanaged(K, Value(anyopaque)) = .empty,

        pub const Self = @This();
        pub const empty: Self = .{};

        pub fn register(self: *Self) !void {
            assert(ref_count.load(.monotonic) > 0);
            try cache_registry.put(allocators.gpa(), @intFromPtr(self), .{
                .deinitFn = @ptrCast(&Self.deinit),
            });
        }

        pub fn deinit(self: *Self) void {
            self.map.deinit(allocators.gpa());
        }

        pub fn getOrPut(self: *Self, comptime T: type, key: K, value: T) GetOrPutResult(T) {
            const entry = self.map.getOrPut(allocators.gpa(), key) catch unreachable;
            const value_ptr: *Value(T) = @ptrCast(entry.value_ptr);
            if (entry.found_existing) return .{ .value = value_ptr.*, .found_existing = true };
            value_ptr.item = allocators.ui().create(T) catch unreachable;
            log.info("alloc item {} {any}", .{ @intFromPtr(self), key });
            value_ptr.item.* = value;
            value_ptr.element = value_ptr.item.element();
            return .{ .value = value_ptr.*, .found_existing = false };
        }
    };
}

pub const AnyCache = struct {
    deinitFn: *const fn (self: *anyopaque) void,

    pub fn deinit(ac: AnyCache, key: usize) void {
        ac.deinitFn(@ptrFromInt(key));
    }
};

var ref_count: std.atomic.Value(usize) = .init(0);
var global_cache: Cache(usize) = .empty;
var cache_registry: std.AutoHashMapUnmanaged(usize, AnyCache) = .empty;

pub fn init() void {
    _ = ref_count.fetchAdd(1, .monotonic);
}

pub fn deinit() void {
    if (ref_count.fetchSub(1, .seq_cst) == 1) {
        var iter = cache_registry.iterator();
        while (iter.next()) |i| i.value_ptr.*.deinit(i.key_ptr.*);
        cache_registry.deinit(allocators.gpa());
        global_cache.deinit();
    }
}

pub fn getOrPut(comptime T: type, key: usize, value: T) GetOrPutResult(T) {
    assert(ref_count.load(.monotonic) > 0);
    return global_cache.getOrPut(T, key, value);
}

pub fn Value(comptime T: type) type {
    return struct {
        element: UI.Element,
        item: *T,
    };
}

pub fn GetOrPutResult(comptime T: type) type {
    return struct {
        value: Value(T),
        found_existing: bool,
    };
}
