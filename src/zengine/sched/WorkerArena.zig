//!
//! Zengine thread pool implementation
//!

const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const allocators = @import("../allocators.zig");
const options = @import("../options.zig").options;
const time = @import("../time.zig");
const Zengine = @import("../zengine.zig").Zengine;

const Barrier = @import("Barrier.zig");
const ThreadInfo = @import("ThreadInfo.zig");
const platform = @import("platform.zig");

const log = std.log.scoped(.sched_thread_pool);

const max_threads = options.max_threads;

inner: std.heap.ArenaAllocator align(std.atomic.cache_line),

pub const Array = [max_threads]@This();

pub fn createArray(child_allocator: Allocator) !*Array {
    const result = try allocators.global().create(Array);
    for (result) |*self| self.inner = .init(child_allocator);
    return result;
}

pub fn deinitArray(array: *Array) void {
    for (array) |*self| self.inner.deinit();
}

pub fn allocator(self: *@This()) Allocator {
    return self.inner.allocator();
}
