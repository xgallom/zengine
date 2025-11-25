//!
//! Zengine controls module
//!

const std = @import("std");
const assert = std.debug.assert;

pub fn Controls(comptime K: type) type {
    if (@typeInfo(K) != .@"enum") @compileError("Key must be an enum");
    return struct {
        control_matrix: std.bit_set.IntegerBitSet(max_key + 1) = .initEmpty(),

        pub const Self = @This();
        pub const Key = K;
        pub const Value = @typeInfo(Key).@"enum".tag_type;
        const max_key = std.math.maxInt(Value);
        pub const init: Self = .{};

        comptime {
            assert(max_key <= std.math.maxInt(std.math.Log2Int(usize)));
        }

        pub fn set(self: *Self, key: Key) void {
            self.control_matrix.set(@intFromEnum(key));
        }

        pub fn clear(self: *Self, key: Key) void {
            self.control_matrix.unset(@intFromEnum(key));
        }

        pub fn has(self: *const Self, key: Key) bool {
            return self.control_matrix.isSet(@intFromEnum(key));
        }

        pub fn hasAny(self: *const Self) bool {
            return self.control_matrix.mask != 0;
        }

        pub fn reset(self: *Self) void {
            self.control_matrix = .initEmpty();
        }
    };
}

pub const CameraControls = Controls(enum(std.math.Log2Int(u32)) {
    yaw_neg,
    yaw_pos,
    pitch_neg,
    pitch_pos,
    roll_neg,
    roll_pos,

    z_neg,
    z_pos,
    x_neg,
    x_pos,
    y_neg,
    y_pos,

    scale_neg,
    scale_pos,

    first_custom,
    _,

    pub const Self = @This();

    const last_custom = std.math.maxInt(std.math.Log2Int(u32));
    const max_custom = Self.last_custom - @intFromEnum(Self.first_custom);

    pub fn custom(comptime idx: comptime_int) Self {
        comptime assert(idx >= 0 and idx <= max_custom);
        return @enumFromInt(@intFromEnum(Self.first_custom) + idx);
    }
});
