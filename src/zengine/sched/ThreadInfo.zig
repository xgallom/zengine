//!
//! Zengine thread info implementation
//!

const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;

const log = std.log.scoped(.sched_thread_info);

const Barrier = @import("Barrier.zig");

broadcast_buffer: *BroadcastBuffer align(std.atomic.cache_line),
barrier: *Barrier,
idx: u32,
thread_len: u32,
group_idx: u32,
group_len: u32,

pub const BroadcastBuffer = struct {
    data: [len]u8 align(std.atomic.cache_line) = undefined,
    pub const len = std.atomic.cache_line;
};

pub const GroupIndex = enum(u32) {
    primary = 0,
    _,

    pub fn init(v: u32) @This() {
        return @enumFromInt(v);
    }

    pub fn eql(self: @This(), other: @This()) bool {
        return self == other;
    }
};

pub const GroupRange = struct {
    begin: u32,
    end: u32,

    pub fn init(begin: u32, end: u32) @This() {
        return .{ .begin = begin, .end = end };
    }

    pub fn contains(self: @This(), idx: u32) bool {
        return (idx >= self.begin) & (idx < self.end);
    }

    pub fn subIdx(self: @This(), idx: u32) u32 {
        assert(self.contains(idx));
        return idx - self.begin;
    }
};

pub const GroupSharedState = struct {
    barrier: Barrier,
    buffer: BroadcastBuffer,
};

pub fn init(
    thread_idx: u32,
    thread_len: u32,
    group_idx: u32,
    group_len: u32,
    barrier: *Barrier,
    broadcast_buffer: *BroadcastBuffer,
) @This() {
    return .{
        .broadcast_buffer = broadcast_buffer,
        .barrier = barrier,
        .idx = thread_idx,
        .thread_len = thread_len,
        .group_idx = group_idx,
        .group_len = group_len,
    };
}

/// Returns the master thread-group.
pub fn globalGroup(
    self: *const @This(),
    global_barrier: *Barrier,
    broadcast_buffer: *BroadcastBuffer,
) @This() {
    return .init(
        self.idx,
        self.thread_len,
        self.idx,
        self.thread_len,
        global_barrier,
        broadcast_buffer,
    );
}

/// Splits the current thread-group to N sub-groups.
/// Caller ensures self.group_len is divisible by N.
/// Returns index of the currently active sub-group.
pub fn split(
    self: *const @This(),
    comptime N: comptime_int,
    sub_barriers: [N]*Barrier,
    broadcast_buffers: [N]*BroadcastBuffer,
    result: *@This(),
) usize {
    const parent_g_range = self.groupRange();
    const sub_len = std.math.divExact(u32, self.group_len, N) catch unreachable;
    const idx = self.idx;
    for (0..sub_len) |n| {
        const sub_range: GroupRange = .init(
            parent_g_range.begin + n * sub_len,
            parent_g_range.begin + (n + 1) * sub_len,
        );
        if (sub_range.contains(idx)) {
            result.* = .init(
                idx,
                self.thread_len,
                sub_range.subIdx(idx),
                sub_len,
                sub_barriers[n],
                broadcast_buffers[n],
            );
            return n;
        }
    } else unreachable;
}

/// Computes a range within <0;len) designated for the current thread.
pub fn range(self: *const @This(), len: usize) struct { begin: usize, end: usize } {
    const values_per_thread = len / self.group_len;
    const leftover_count = len % self.group_len;
    const has_leftover = self.group_idx < leftover_count;
    const leftover_before = if (has_leftover) self.group_idx else leftover_count;
    const begin = values_per_thread * self.group_idx + leftover_before;
    const end = begin + values_per_thread + @intFromBool(has_leftover);
    return .{ .begin = begin, .end = end };
}

/// Returns a subslice designated for the current thread.
pub fn slice(self: *const @This(), buf: anytype) @TypeOf(buf) {
    const r = self.range(buf.len);
    return buf[r.begin..r.end];
}

/// Returns whether this thread is primary within the group.
pub fn isPrimary(self: *const @This()) bool {
    return self.group_idx == 0;
}

pub fn groupRange(self: *const @This()) GroupRange {
    const begin = self.idx - self.group_idx;
    return .{ .begin = begin, .end = begin + self.group_len };
}

/// Thread-safe broadcast of a value from source thread to all other threads within the group.
pub fn broadcastValue(
    self: *const @This(),
    comptime T: type,
    value: *T,
    src_group_idx: GroupIndex,
) void {
    comptime assert(@sizeOf(T) <= BroadcastBuffer.len);
    const data = std.mem.asBytes(value);
    if (src_group_idx.eql(.init(self.group_idx))) @memcpy(
        self.broadcast_buffer.data[0..data.len],
        data,
    );
    self.barrier.sync(.spinloop);
    if (!src_group_idx.eql(.init(self.group_idx))) @memcpy(
        data,
        self.broadcast_buffer.data[0..data.len],
    );
    self.barrier.sync(.spinloop);
}

/// Thread-safe broadcast of a slice from source thread to all other threads within the group.
pub fn broadcastSlice(
    self: *const @This(),
    value: []u8,
    src_group_idx: GroupIndex,
) void {
    assert(value.len <= BroadcastBuffer.len);
    if (src_group_idx.eql(.init(self.group_idx))) @memcpy(
        self.broadcast_buffer.data[0..value.len],
        value,
    );
    self.barrier.sync(.spinloop);
    if (!src_group_idx.eql(.init(self.group_idx))) @memcpy(
        value,
        self.broadcast_buffer.data[0..value.len],
    );
    self.barrier.sync(.spinloop);
}
