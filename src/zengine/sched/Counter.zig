//!
//! Zengine atomic counter implementation
//!

const std = @import("std");
const assert = std.debug.assert;
const AtomicOrder = std.builtin.AtomicOrder;
const builtin = @import("builtin");

const log = std.log.scoped(.sched_counter);

current: std.atomic.Value(u64) align(std.atomic.cache_line) = .init(0),
len: u64,
pad: [std.atomic.cache_line - @sizeOf(u64) * 2]u8 = undefined,

pub fn init(len: u64) @This() {
    return .{ .len = len };
}

pub fn isFinished(self: *const @This()) bool {
    return self.current.load(.monotonic) >= self.len;
}

pub fn next(self: *@This(), step: u64, comptime order: AtomicOrder) ?u64 {
    if (self.isFinished()) return null;
    const current = self.current.fetchAdd(step, order);
    if (current < self.len) return current;
    return null;
}

pub fn store(self: *@This(), value: u64, comptime order: AtomicOrder) void {
    self.current.store(value, order);
}

pub fn Unbounded(comptime T: type) type {
    assert(@typeInfo(T) == .int);
    assert(@typeInfo(T).int.signedness == .unsigned);
    return struct {
        current: std.atomic.Value(T) align(std.atomic.cache_line) = .init(0),
        pad: [std.atomic.cache_line - @sizeOf(std.atomic.Value(T))]u8 = undefined,

        pub const init: @This() = .{};

        pub fn next(self: *@This(), step: T, comptime order: AtomicOrder) T {
            return self.current.fetchAdd(step, order);
        }

        pub fn load(self: *@This(), comptime order: AtomicOrder) T {
            return self.current.load(order);
        }

        pub fn loadNext(self: *@This(), step: T, comptime order: AtomicOrder) T {
            return self.current.load(order) + step;
        }

        pub fn store(self: *@This(), value: T, comptime order: AtomicOrder) void {
            self.current.store(value, order);
        }
    };
}
