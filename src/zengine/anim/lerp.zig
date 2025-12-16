//!
//! The zengine interpolation implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const perf = @import("../perf.zig");
const ui_mod = @import("../ui.zig");

const log = std.log.scoped(.anim_lerp);

pub fn LerpFn(comptime T: type) type {
    return fn (t0: T, t1: T, t: math.Scalar) T;
}

pub fn defaultLerpFn(comptime T: type) LerpFn(T) {
    return switch (@typeInfo(T)) {
        .float, .comptime_float => scalarT(T),
        .array => |info| switch (@typeInfo(info.child)) {
            .float, .comptime_float => vectorNT(info.len, info.child),
            else => @compileError("Unsupported array type " ++ @typeName(info.child)),
        },
        .vector => |info| switch (@typeInfo(info.child)) {
            .float, .comptime_float => scalarT(T),
            else => @compileError("Unsupported vector type " ++ @typeName(info.child)),
        },
        else => @compileError("Unsupported type " ++ @typeName(T)),
    };
}

pub fn scalarT(comptime T: type) LerpFn(T) {
    return math.scalarT(T).lerp;
}
pub const scalar = scalarT(math.Scalar);
pub const scalar64 = scalarT(math.Scalar64);

pub fn vectorNT(comptime N: comptime_int, comptime T: type) LerpFn(math.VectorNT(N, T)) {
    return struct {
        const Self = math.VectorNT(N, T);
        fn lerp(t0: Self, t1: Self, t: math.Scalar) Self {
            var result: Self = undefined;
            math.vectorNT(N, T).lerp(&result, &t0, &t1, t);
            return result;
        }
    }.lerp;
}
pub const vector2 = vectorNT(2, math.Scalar);
pub const vector2f64 = vectorNT(2, math.Scalar64);
pub const vector3 = vectorNT(3, math.Scalar);
pub const vector3f64 = vectorNT(3, math.Scalar64);
pub const vector4 = vectorNT(4, math.Scalar);
pub const vector4f64 = vectorNT(4, math.Scalar64);

pub fn quat(t0: math.Quat, t1: math.Quat, t: math.Scalar) math.Quat {
    var result: math.Quat = undefined;
    math.quat.lerp(&result, &t0, &t1, t);
    return result;
}

/// Does linear interpolation between values
pub fn AutoInterpolation(comptime T: type) type {
    return Interpolation(T, defaultLerpFn(T));
}

pub fn Interpolation(comptime T: type, comptime lerpFn: LerpFn(T)) type {
    return struct {
        t0: T,
        t1: T,
        op: *const math.Param,

        const Self = @This();

        pub fn init(t0: T, t1: T, op: *const math.Param) Self {
            return .{ .t0 = t0, .t1 = t1, .op = op };
        }

        pub fn get(self: *const Self, t: math.Scalar) T {
            return lerpFn(self.t0, self.t1, self.op(t));
        }
    };
}
