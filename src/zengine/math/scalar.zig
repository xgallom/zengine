//!
//! The zengine batching math scalar helper implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const types = @import("types.zig");

pub fn scalarT(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .Float, .ComptimeFloat => struct {
            pub const Self = T;
            pub const Scalar = T;
            pub const len = 1;

            pub const zero: Self = 0;
            pub const one: Self = 1;
            pub const neg_one: Self = -1;

            pub fn init(value: Scalar) Self {
                return value;
            }
        },
        .Vector => switch (@typeInfo(@typeInfo(T).Vector.child)) {
            .Float, .ComptimeFloat => struct {
                pub const Self = T;
                pub const Scalar = @typeInfo(T).Vector.child;
                pub const len = @typeInfo(T).Vector.len;

                pub const zero: Self = @splat(0);
                pub const one: Self = @splat(1);
                pub const neg_one: Self = @splat(-1);

                pub fn init(value: Scalar) Self {
                    return @splat(value);
                }
            },
            else => @compileError("Unsupported vector scalar type " ++ @typeName(@typeInfo(T).Vector.child)),
        },
        else => @compileError("Unsupported scalar type " ++ @typeName(T)),
    };
}
