//!
//! Zengine thread grooup sync barrier implementation
//!

const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

const WaitBehavior = @import("../sched.zig").WaitBehavior;

const log = std.log.scoped(.scheduler_barrier);

current: std.atomic.Value(u32) align(std.atomic.cache_line) = .init(0),
gen: std.atomic.Value(u32) = .init(0),
len: u32,
pad: [std.atomic.cache_line - @sizeOf(u32) * 3]u8 = undefined,

pub var invalid: @This() = .init(0);

pub fn init(len: u32) @This() {
    return .{ .len = len };
}

pub fn sync(self: *@This(), comptime behavior: WaitBehavior) void {
    assert(self.len > 0);
    const gen = self.gen.load(.monotonic);
    const prev = self.current.fetchAdd(1, .acq_rel);
    assert(prev < self.len);
    if (prev + 1 >= self.len) {
        self.current.store(0, .monotonic);
        const next_gen = gen +% 1;
        if (next_gen == 0) {
            @branchHint(.cold);
            self.gen.store(1, .release);
        } else self.gen.store(next_gen, .release);
    } else while (self.gen.load(.acquire) == gen) switch (behavior) {
        .spinloop => std.atomic.spinLoopHint(),
        .yield => std.Thread.yield() catch @panic("Failed yielding thread"),
    };
    log.debug("synced barrier {x:016}@{}", .{ @intFromPtr(self), gen });
}

pub fn ranOnce(self: *@This()) bool {
    assert(self.len > 0);
    return self.gen.load(.acquire) != 0;
}
