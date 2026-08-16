//!
//! Zengine thread pool implementation
//!

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

const allocators = @import("../allocators.zig");
const options = @import("../options.zig").options;
const max_threads = options.max_threads;
const time = @import("../time.zig");
const Zengine = @import("../zengine.zig").Zengine;
const Barrier = @import("Barrier.zig");
const platform = @import("platform.zig");
const ThreadInfo = @import("ThreadInfo.zig");

const log = std.log.scoped(.sched_thread_pool);

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
