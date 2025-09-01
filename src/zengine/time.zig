//!
//! The zengine time module
//!

const std = @import("std");
const sdl = @import("ext.zig").sdl;

const assert = std.debug.assert;

pub fn getNow() u64 {
    return sdl.SDL_GetTicks();
}

/// Struct for measuring time since creation and update
pub const Clock = struct {
    start_time: u64 = 0,
    updated_at: u64 = 0,

    const Self = @This();

    pub fn init(now: u64) Self {
        return .{
            .start_time = now,
            .updated_at = now,
        };
    }

    pub fn update(self: *Self, now: u64) void {
        self.updated_at = now;
    }

    pub fn sinceStart(self: *const Self, now: u64) u64 {
        return now - self.start_time;
    }

    pub fn sinceUpdate(self: *const Self, now: u64) u64 {
        return now - self.updated_at;
    }
};

/// Struct for measuring repeated intervals based on ms clock
pub const Timer = struct {
    updated_at: u64 = 0,
    interval_ms: u64,

    const Self = @This();

    pub fn init(interval_ms: u64) Self {
        return .{ .interval_ms = interval_ms };
    }

    pub fn update(self: *Self, now: u64) void {
        if (self.isArmed(now)) self.updated_at = now;
    }

    pub fn isArmed(self: *const Self, now: u64) bool {
        return now - self.updated_at >= self.interval_ms;
    }
};

pub fn msToSec(ms: u64) f32 {
    return @as(f32, @floatFromInt(ms)) / 1000.0;
}
