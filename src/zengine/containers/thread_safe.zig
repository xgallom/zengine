//!
//! Zengine thread-safe containers implementation
//!

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const sched = @import("../sched.zig");

const log = std.log.scoped(.containers_thread_safe);

/// SPSC lock-free ring-buffer
pub fn RingBuffer(comptime T: type, comptime N: comptime_int) type {
    assert(std.math.isPowerOfTwo(N));
    return struct {
        head: sched.Counter.Unbounded(u32) = .init,
        tail: sched.Counter.Unbounded(u32) = .init,
        items: [capacity]T align(std.atomic.cache_line) = undefined,

        const Self = @This();
        pub const empty: Self = .{};
        pub const capacity = N;
        pub const mask = N - 1;

        pub fn writer(self: *@This()) Writer {
            const w_idx = self.head.load(.monotonic);
            const r_idx = self.tail.load(.acquire);
            return .{ .self = self, .w_idx = w_idx, .r_idx = r_idx };
        }

        pub const Writer = struct {
            self: *Self,
            w_idx: u32,
            r_idx: u32,

            pub fn append(w: *@This(), items: []const T) usize {
                if (items.len == 0) return 0;
                if (capacity - (w.w_idx -% w.r_idx) < items.len) {
                    const r_idx = w.self.tail.load(.acquire);
                    w.r_idx = r_idx;
                    if (w.w_idx -% r_idx >= capacity) return 0;
                }
                const start = w.w_idx & mask;
                const end = w.r_idx & mask;
                if (start < end) {
                    const len = @min(end - start, items.len);
                    @memcpy(w.self.items[start .. start + len], items[0..len]);
                    w.w_idx +%= len;
                    return len;
                } else {
                    const len = @min(capacity - (start - end), items.len);
                    if (start + len > capacity) {
                        const split = capacity - start;
                        @memcpy(w.self.items[start..capacity], items[0..split]);
                        @memcpy(w.self.items[0 .. len - split], items[split..len]);
                    } else @memcpy(w.self.items[start .. start + len], items[0..len]);
                    w.w_idx +%= len;
                    return len;
                }
            }

            pub fn publish(w: @This()) void {
                w.self.head.store(w.w_idx, .release);
            }
        };

        pub fn reader(self: *@This()) Reader {
            const r_idx = self.tail.load(.monotonic);
            const w_idx = self.head.load(.acquire);
            return .{ .self = self, .w_idx = w_idx, .r_idx = r_idx };
        }

        pub const Reader = struct {
            self: *Self,
            w_idx: u32,
            r_idx: u32,

            pub fn available(r: *@This()) ?[2][]T {
                if (r.r_idx == r.w_idx) {
                    const w_idx = r.self.head.load(.acquire);
                    r.w_idx = w_idx;
                    if (r.r_idx == w_idx) return null;
                }
                const start = r.r_idx & mask;
                const end = r.w_idx & mask;
                return if (start < end)
                    .{ r.self.items[start..end], &.{} }
                else
                    .{ r.self.items[start..capacity], r.self.items[0..end] };
            }

            pub fn consumeAvailable(r: *@This()) void {
                log.debug("consuming {}-{}", .{ r.r_idx, r.w_idx });
                const w_idx = r.w_idx;
                r.r_idx = w_idx;
                r.self.tail.store(w_idx, .release);
            }
        };
    };
}
