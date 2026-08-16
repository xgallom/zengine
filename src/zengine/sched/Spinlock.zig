//!
//! Zengine spinlock implementation
//!

const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

const WaitBehavior = @import("../sched.zig").WaitBehavior;

const log = std.log.scoped(.sched_spinlock);

locked: std.atomic.Value(bool) align(std.atomic.cache_line) = .init(false),
pad: [std.atomic.cache_line - @sizeOf(std.atomic.Value(bool))]u8 = undefined,

pub const init: @This() = .{};
const preread_min = 1;
const preread_max = 8;

pub fn tryLock(self: *@This()) bool {
    if (self.locked.load(.monotonic)) return false;
    if (self.locked.swap(true, .acquire)) return false;
    return true;
}

pub fn lock(self: *@This(), comptime behavior: WaitBehavior) void {
    var preread: u32 = preread_min;
    while (!self.tryLockPreread(&preread)) switch (behavior) {
        .spinloop => std.atomic.spinLoopHint(),
        .yield => std.Thread.yield() catch @panic("Failed yielding thread"),
    };
}

fn tryLockPreread(self: *@This(), preread: *u32) bool {
    assert(preread.* >= preread_min);
    assert(preread.* <= preread_max);
    inline for (0..preread_max) |n| {
        const max = preread.*;
        if (n >= max) break;
        if (self.locked.load(.monotonic)) {
            preread.* = @min(max * 2, preread_max);
            return false;
        }
        if (n + 1 < max) std.atomic.spinLoopHint();
    }
    if (self.locked.swap(true, .acquire)) {
        preread.* = @min(preread.* * 2, preread_max);
        return false;
    }
    return true;
}

pub fn unlock(self: *@This()) void {
    self.locked.store(false, .release);
}
