//!
//! Zengine controls module
//!

const std = @import("std");

pub const CameraControls = struct {
    control_matrix: u32 = 0,

    const Self = @This();

    pub const Key = enum(u32) {
        yaw_neg = 0x01,
        yaw_pos = 0x02,
        pitch_neg = 0x04,
        pitch_pos = 0x08,
        roll_neg = 0x10,
        roll_pos = 0x20,

        z_neg = 0x0100,
        z_pos = 0x0200,
        x_neg = 0x0400,
        x_pos = 0x0800,
        y_neg = 0x1000,
        y_pos = 0x2000,

        fov_neg = 0x01_0000,
        fov_pos = 0x02_0000,
    };

    pub fn map(key: Key) u32 {
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
