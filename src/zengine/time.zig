//!
//! The zengine time module
//!

const std = @import("std");
const assert = std.debug.assert;

const sdl = @import("ext.zig").sdl;

pub inline fn getNow() u64 {
    return sdl.SDL_GetTicks();
}

pub fn getMS() Time {
    return .{ .ms = getNow() };
}

pub inline fn getNano() u64 {
    return sdl.SDL_GetTicksNS();
}

pub fn getNS() Time {
    return .{ .ns = getNano() };
}

pub const Unit = enum {
    ns,
    us,
    ms,
    s,
    min,
    hour,
    day,
    week,

    pub fn makePer(comptime left: Unit, comptime right: Unit) comptime_int {
        return @field(std.time, @tagName(left) ++ "_per_" ++ @tagName(right));
    }

    pub fn convert(comptime from: Unit, comptime to: Unit, value: anytype) @TypeOf(value) {
        if (comptime from == to) {
            return value;
        } else if (comptime (@intFromEnum(to) > @intFromEnum(from))) {
            return value / makePer(from, to);
        } else {
            return value * makePer(to, from);
        }
    }

    pub fn asText(comptime unit: Unit) []const u8 {
        return switch (unit) {
            .ns => "ns",
            .us => "us",
            .ms => "ms",
            .s => "s",
            .min => "min",
            .hour => "hour",
            .day => "day",
            .week => "week",
        };
    }

    pub fn toString(unit: Unit) []const u8 {
        return switch (unit) {
            inline else => |u| asText(u),
        };
    }
};

pub const FloatTime = union(Unit) {
    ns: f64,
    us: f64,
    ms: f64,
    s: f64,
    min: f64,
    hour: f64,
    day: f64,
    week: f64,

    pub fn toCardinal(time: FloatTime) FloatTime {
        switch (@as(Unit, time)) {
            inline else => |from| {
                const sn = @intFromEnum(Unit.s);
                inline for (0..sn) |n| {
                    const to: Unit = comptime @enumFromInt(sn - n);
                    const value = Unit.convert(
                        from,
                        to,
                        @field(time, @tagName(from)),
                    );
                    if (value >= 10.0) return @unionInit(
                        FloatTime,
                        @tagName(to),
                        value,
                    );
                }
                return time;
            },
        }
    }

    pub fn toTime(from: FloatTime, comptime to: Unit) FloatTime {
        return @unionInit(FloatTime, @tagName(to), from.toValue(to));
    }

    pub fn toValue32(time: FloatTime, comptime to: Unit) f32 {
        return @floatCast(time.toValue(to));
    }

    pub fn toValue(time: FloatTime, comptime to: Unit) f64 {
        return switch (@as(Unit, time)) {
            inline else => |from| Unit.convert(
                from,
                to,
                @field(time, @tagName(from)),
            ),
        };
    }

    pub fn asValue(time: FloatTime) f64 {
        return switch (@as(Unit, time)) {
            inline else => |from| @field(time, @tagName(from)),
        };
    }

    pub fn asUnit(time: FloatTime) Unit {
        return time;
    }
};

pub const Time = union(Unit) {
    ns: u64,
    us: u64,
    ms: u64,
    s: u64,
    min: u64,
    hour: u64,
    day: u64,
    week: u64,

    pub fn toCardinal(time: FloatTime) FloatTime {
        switch (@as(Unit, time)) {
            inline else => |from| {
                const sn = @intFromEnum(Unit.s);
                inline for (0..sn) |n| {
                    const to: Unit = comptime @enumFromInt(sn - n);
                    const value = Unit.convert(
                        from,
                        to,
                        @field(time, @tagName(from)),
                    );
                    if (value >= 10) return @unionInit(
                        FloatTime,
                        @tagName(to),
                        value,
                    );
                }
                return time;
            },
        }
    }

    pub fn toTime(from: Time, comptime to: Unit) Time {
        return @unionInit(Time, @tagName(to), from.toValue(to));
    }

    pub fn toValue(time: Time, comptime to: Unit) u64 {
        return switch (@as(Unit, time)) {
            inline else => |from| Unit.convert(
                from,
                to,
                @field(time, @tagName(from)),
            ),
        };
    }

    pub fn toFloat(time: Time) FloatTime {
        return switch (@as(Unit, time)) {
            inline else => |from| @unionInit(
                FloatTime,
                @tagName(from),
                @floatFromInt(@field(time, @tagName(from))),
            ),
        };
    }

    pub fn asValue(time: Time) u64 {
        return switch (@as(Unit, time)) {
            inline else => |from| @field(time, @tagName(from)),
        };
    }

    pub fn asUnit(time: Time) Unit {
        return time;
    }
};

/// Struct for measuring time
pub const Clock = struct {
    start_time: u64 = 0,

    const Self = @This();

    pub fn init(now: u64) Self {
        return .{
            .start_time = now,
        };
    }

    pub fn isRunning(self: *const Self) bool {
        return self.start_time != 0;
    }

    pub fn start(self: *Self, now: u64) void {
        self.start_time = now;
    }

    pub fn elapsed(self: *const Self, now: u64) u64 {
        assert(self.isRunning());
        return now -| self.start_time;
    }

    pub fn reset(self: *Self) void {
        self.start_time = 0;
    }

    pub fn pause(self: *const Self, pause_clock: *Self, now: u64) void {
        assert(self.isRunning());
        pause_clock.start(now);
    }

    pub fn unpause(self: *Self, pause_clock: *Self, now: u64) void {
        assert(self.isRunning());
        self.start_time = @min(self.start_time +| pause_clock.elapsed(now), now);
        pause_clock.reset();
    }
};

/// Struct for firing intervals
pub const Timer = struct {
    updated_at: u64 = 0,
    interval: u64,

    const Self = @This();

    pub fn init(interval: u64) Self {
        return .{ .interval = interval };
    }

    pub fn isArmed(self: *const Self, now: u64) bool {
        return now -| self.updated_at >= self.interval;
    }

    pub fn set(self: *Self, now: u64) void {
        self.updated_at = now;
    }

    pub fn reset(self: *Self) void {
        self.updated_at = 0;
    }

    pub fn updated(self: *Self, now: u64) bool {
        if (self.isArmed(now)) {
            self.set(now);
            return true;
        }
        return false;
    }

    pub inline fn update(self: *Self, now: u64) void {
        _ = self.updated(now);
    }
};

pub fn toSeconds(time: Time) f32 {
    return time.toFloat(.s);
}
