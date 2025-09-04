//!
//! Zengine controls module
//!

const std = @import("std");
const assert = std.debug.assert;

pub fn Controls(comptime K: type) type {
    if (@typeInfo(K) != .@"enum") @compileError("Key must be an enum");
    return struct {
        control_matrix: Value = 0,

        const Self = @This();
        pub const Key = K;
        pub const Value = @typeInfo(Key).@"enum".tag_type;

        pub fn map(key: Key) Value {
            return @intFromEnum(key);
        }

        pub fn set(self: *Self, key: Key) void {
            self.control_matrix |= map(key);
        }

        pub fn clear(self: *Self, key: Key) void {
            self.control_matrix &= ~map(key);
        }

        pub fn has(self: *const Self, key: Key) bool {
            return self.control_matrix & map(key) != 0;
        }

        pub fn hasAny(self: *const Self) bool {
            return self.control_matrix != 0;
        }
    };
}

pub const CameraControls = Controls(enum(u32) {
    yaw_neg = 0x01,
    yaw_pos = 0x02,
    pitch_neg = 0x04,
    pitch_pos = 0x08,
    roll_neg = 0x10,
    roll_pos = 0x20,

    z_neg = 0x40,
    z_pos = 0x80,
    x_neg = 0x0100,
    x_pos = 0x0200,
    y_neg = 0x0400,
    y_pos = 0x0800,

    fov_neg = 0x1000,
    fov_pos = 0x2000,

    first_custom = 0x4000,
    last_custom = 0x8000_0000,
    _,

    const Self = @This();

    const max_custom = blk: {
        var acc: usize = 0;
        const min = @intFromEnum(Self.first_custom);
        const max = @intFromEnum(Self.last_custom);
        var walk: usize = min;
        while (walk <= max) : (walk <<= 1) acc += 1;
        break :blk acc;
    };

    pub fn custom(comptime idx: comptime_int) Self {
        comptime assert(idx >= 0 and idx < max_custom);
        return @enumFromInt(@intFromEnum(Self.first_custom) << idx);
    }
});
