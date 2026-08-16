//!
//! Scheduling system for the engine
//!

const std = @import("std");
const assert = std.debug.assert;
const allocators = @import("allocators.zig");
const AnyTaskList = std.DoublyLinkedList;

const log = std.log.scoped(.sched);

pub const Barrier = @import("sched/Barrier.zig");
pub const Counter = @import("sched/Counter.zig");
pub const Spinlock = @import("sched/Spinlock.zig");
pub const ThreadInfo = @import("sched/ThreadInfo.zig");
pub const ThreadPool = @import("sched/thread_pool.zig").ThreadPool;
pub const WorkerArena = @import("sched/WorkerArena.zig");

pub const WaitBehavior = enum { spinloop, yield };

test {
    std.testing.refAllDecls(@This());
}
