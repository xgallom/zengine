//!
//! The zengine scalar operations
//!

const std = @import("std");
const assert = std.debug.assert;

const types = @import("types.zig");

const log = std.log.scoped(.math_scalar);

pub fn IntMask(comptime len: comptime_int) type {
    comptime assert(len >= 0);
    return struct {
        pub const uses_mask = @popCount(@as(usize, len)) == 1;

        pub inline fn index(elem_index: anytype) @TypeOf(elem_index) {
            if (comptime len == 0) return elem_index;
            return switch (comptime uses_mask) {
                true => elem_index >> comptime @ctz(len),
                false => elem_index / len,
            };
        }

        pub inline fn offset(elem_index: anytype) @TypeOf(elem_index) {
            if (comptime len == 0) return 0;
            return switch (comptime uses_mask) {
                true => elem_index & comptime (len - 1),
                false => elem_index % len,
            };
        }
    };
}

/// Scalar implementation for a generic type
pub fn scalarT(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .float, .comptime_float => struct {
            pub const Self = T;
            pub const Scalar = T;
            pub const len = 1;
            pub const is_float = true;
            pub const is_int = false;
            pub const is_vec = false;

            pub const @"0": Self = 0;
            pub const @"1": Self = 1;
            pub const @"2": Self = 2;
            pub const @"-1": Self = -1;
            pub const pi: Self = @floatCast(std.math.pi);
            pub const eps: Self = std.math.floatEps(Scalar);
            pub const nan: Self = std.math.nan(Scalar);
            pub const inf: Self = std.math.inf(Scalar);

            pub const min_val = -std.math.inf(Self);
            pub const max_val = std.math.inf(Self);

            pub fn epsAt(value: Scalar) Self {
                return std.math.floatEpsAt(Scalar, value);
            }

            pub fn init(value: Scalar) Self {
                return value;
            }

            pub fn recip(value: Self) Self {
                return @"1" / value;
            }

            pub fn swap(a: *Self, b: *Self) void {
                const tmp = a.*;
                a.* = b.*;
                b.* = tmp;
            }

            pub fn isNan(x: Self) bool {
                return std.math.isNan(x);
            }

            pub fn approxEqAbs(x: Self, y: Self, tolerance: Self) bool {
                return std.math.approxEqAbs(Scalar, x, y, tolerance);
            }

            pub fn approxEqRel(x: Self, y: Self, tolerance: Self) bool {
                return std.math.approxEqRel(Scalar, x, y, tolerance);
            }

            pub fn sin(x: Self) Self {
                return @sin(x);
            }

            pub fn cos(x: Self) Self {
                return @cos(x);
            }

            pub fn asin(x: Self) Self {
                return std.math.asin(x);
            }

            pub fn acos(x: Self) Self {
                return std.math.acos(x);
            }

            pub fn atan2(y: Self, x: Self) Self {
                return std.math.atan2(y, x);
            }

            pub fn lerp(t0: Self, t1: Self, t: types.Scalar) Self {
                const st: Self = @floatCast(t);
                return t0 * (@"1" - st) + t1 * st;
            }

            pub fn to(comptime U: type, value: Scalar) U {
                return switch (@typeInfo(U)) {
                    .float, .comptime_float => @floatCast(value),
                    .int, .comptime_int => @intFromFloat(value),
                    .vector => |u_info| switch (@typeInfo(u_info.child)) {
                        .float, .comptime_float => @splat(@floatCast(value)),
                        .int, .comptime_int => @splat(@intFromFloat(value)),
                        else => @compileError("Unsupported vector type " ++ @typeName(u_info.child)),
                    },
                    else => @compileError("Unsupported scalar type " ++ @typeName(U)),
                };
            }
        },
        .int, .comptime_int => struct {
            pub const Self = T;
            pub const Scalar = T;
            pub const len = 1;
            pub const is_float = false;
            pub const is_int = true;
            pub const is_vec = false;

            pub const @"0": Self = 0;
            pub const @"1": Self = 1;
            pub const @"2": Self = 2;
            pub const @"-1": Self = -1;

            pub const min_val = std.math.minInt(Self);
            pub const max_val = std.math.maxInt(Self);

            pub fn init(value: Scalar) Self {
                return value;
            }

            pub fn recip(value: Self) Self {
                _ = value;
                @compileError("Computing reciprocal of an integer is not posible");
            }

            pub fn swap(a: *Self, b: *Self) void {
                const tmp = a.*;
                a.* = b.*;
                b.* = tmp;
            }

            pub fn lerp(t0: Self, t1: Self, t: types.Scalar) Self {
                _ = t0;
                _ = t1;
                _ = t;
                @compileError("lerp not implemented for " ++ @typeName(Self));
            }

            pub fn to(comptime U: type, value: Scalar) U {
                return switch (@typeInfo(U)) {
                    .float, .comptime_float => @floatFromInt(value),
                    .int, .comptime_int => @intCast(value),
                    .vector => |u_info| switch (@typeInfo(u_info.child)) {
                        .float, .comptime_float => @splat(@floatFromInt(value)),
                        .int, .comptime_int => @splat(@intCast(value)),
                        else => @compileError("Unsupported vector type " ++ @typeName(u_info.child)),
                    },
                    else => @compileError("Unsupported scalar type " ++ @typeName(U)),
                };
            }
        },
        .vector => |info| switch (@typeInfo(info.child)) {
            .float, .comptime_float => struct {
                pub const Self = T;
                pub const Scalar = @typeInfo(T).vector.child;
                pub const Pred = @Vector(len, bool);
                pub const len = @typeInfo(T).vector.len;
                pub const is_float = true;
                pub const is_int = false;
                pub const is_vec = true;

                pub const @"0": Self = @splat(0);
                pub const @"1": Self = @splat(1);
                pub const @"2": Self = @splat(2);
                pub const @"-1": Self = @splat(-1);
                pub const pi: Self = @splat(std.math.pi);
                pub const eps: Self = @splat(std.math.floatEps(Scalar));
                pub const nan: Self = @splat(std.math.nan(Scalar));
                pub const inf: Self = @splat(std.math.inf(Scalar));

                pub const child = scalarT(Scalar);

                pub fn epsAt(value: Scalar) Self {
                    return @splat(child.epsAt(value));
                }

                pub fn init(value: Scalar) Self {
                    return @splat(value);
                }

                pub fn recip(value: Self) Self {
                    return @"1" / value;
                }

                pub fn swap(a: *Self, b: *Self) void {
                    const tmp = a.*;
                    a.* = b.*;
                    b.* = tmp;
                }

                pub fn isNan(x: Self) Pred {
                    var result: Pred = undefined;
                    inline for (0..len) |n| {
                        result[n] = child.isNan(x[n]);
                    }
                    return result;
                }

                pub fn approxEqAbs(x: Self, y: Self, tolerance: Self) Pred {
                    assert(@reduce(.And, tolerance >= @"0"));
                    var result: Pred = undefined;
                    const v_false: Pred = @splat(false);
                    const v_true: Pred = @splat(true);
                    result = @abs(x - y) <= tolerance;
                    result = @select(bool, isNan(x) | isNan(y), v_false, result);
                    result = @select(bool, x == y, v_true, result);
                    return result;
                }

                pub fn approxEqRel(x: Self, y: Self, tolerance: Self) Pred {
                    _ = x;
                    _ = y;
                    _ = tolerance;
                    @compileError("Not implemented");
                }

                pub fn sin(x: Self) Self {
                    var result: Self = undefined;
                    inline for (0..len) |n| {
                        result[n] = child.sin(x[n]);
                    }
                    return result;
                }

                pub fn cos(x: Self) Self {
                    var result: Self = undefined;
                    inline for (0..len) |n| {
                        result[n] = child.cos(x[n]);
                    }
                    return result;
                }

                pub fn asin(x: Self) Self {
                    var result: Self = undefined;
                    inline for (0..len) |n| {
                        result[n] = child.asin(x[n]);
                    }
                    return result;
                }

                pub fn acos(x: Self) Self {
                    var result: Self = undefined;
                    inline for (0..len) |n| {
                        result[n] = child.acos(x[n]);
                    }
                    return result;
                }

                pub fn atan2(y: Self, x: Self) Self {
                    var result: Self = undefined;
                    inline for (0..len) |n| {
                        result[n] = child.atan2(y[n], x[n]);
                    }
                    return result;
                }

                pub fn lerp(t0: Self, t1: Self, t: types.Scalar) Self {
                    const vt = init(@floatCast(t));
                    return t0 * (@"1" - vt) + t1 * vt;
                }

                pub fn to(comptime U: type, value: Scalar) U {
                    return switch (@typeInfo(U)) {
                        .float, .comptime_float => @compileError("Can not convert vector to float"),
                        .int, .comptime_int => @compileError("Can not convert vector to int"),
                        .vector => |u_info| if (comptime info.len == u_info.len) blk: {
                            var result: U = undefined;
                            for (0..info.len) |n| {
                                result[n] = scalarT(Scalar).to(u_info.child, value[n]);
                            }
                            break :blk result;
                        } else @compileError("Vector size mismatch"),
                        else => @compileError("Unsupported scalar type " ++ @typeName(U)),
                    };
                }

                const mask = IntMask(len);

                /// Compute the number of vectors required to store elem_len values.
                // This reduces to binary arithmetic in release mode for power of two-sized batches.
                pub fn batchLen(elem_len: anytype) @TypeOf(elem_len) {
                    var result = batchIndex(elem_len);
                    if (batchOffset(elem_len) != 0) result += 1;
                    return result;
                }

                /// Compute position of the element in an array of vectors.
                pub fn batchIndex(elem_index: anytype) @TypeOf(elem_index) {
                    return mask.index(elem_index);
                }

                /// Compute an offset into the vector in which the element is located.
                pub fn batchOffset(elem_index: anytype) @TypeOf(elem_index) {
                    return mask.offset(elem_index);
                }
            },
            .int, .comptime_int => struct {
                pub const Self = T;
                pub const Scalar = @typeInfo(T).vector.child;
                pub const Pred = @Vector(len, bool);
                pub const len = @typeInfo(T).vector.len;
                pub const is_float = false;
                pub const is_int = true;
                pub const is_vec = true;

                pub const @"0": Self = @splat(0);
                pub const @"1": Self = @splat(1);
                pub const @"2": Self = @splat(2);
                pub const @"-1": Self = @splat(-1);

                pub fn init(value: Scalar) Self {
                    return @splat(value);
                }

                pub fn recip(value: Self) Self {
                    _ = value;
                    @compileError("Computing reciprocal of an integer is not posible");
                }

                pub fn swap(a: *Self, b: *Self) void {
                    const tmp = a.*;
                    a.* = b.*;
                    b.* = tmp;
                }

                pub fn lerp(t0: Self, t1: Self, t: types.Scalar) Self {
                    _ = t0;
                    _ = t1;
                    _ = t;
                    @compileError("lerp not implemented for " ++ @typeName(Self));
                }

                pub fn to(comptime U: type, value: Scalar) U {
                    return switch (@typeInfo(U)) {
                        .float, .comptime_float => @compileError("Can not convert vector to float"),
                        .int, .comptime_int => @compileError("Can not convert vector to int"),
                        .vector => |u_info| if (comptime info.len == u_info.len) blk: {
                            var result: U = undefined;
                            for (0..info.len) |n| {
                                result[n] = scalarT(Scalar).to(u_info.child, value[n]);
                            }
                            break :blk result;
                        } else @compileError("Vector size mismatch"),
                        else => @compileError("Unsupported conversion type " ++ @typeName(U)),
                    };
                }

                const mask = IntMask(len);

                /// Compute the number of vectors required to store elem_len values.
                // This reduces to binary arithmetic in release mode for power of two-sized batches.
                pub fn batchLen(elem_len: anytype) @TypeOf(elem_len) {
                    var result = batchIndex(elem_len);
                    if (batchOffset(elem_len) != 0) result += 1;
                    return result;
                }

                /// Compute position of the element in an array of vectors.
                pub fn batchIndex(elem_index: anytype) @TypeOf(elem_index) {
                    return mask.index(elem_index);
                }

                /// Computes an offset into the vector in which the element is located.
                pub fn batchOffset(elem_index: anytype) @TypeOf(elem_index) {
                    return mask.offset(elem_index);
                }
            },
            else => @compileError("Unsupported vector scalar type " ++ @typeName(info.child)),
        },
        else => @compileError("Unsupported scalar type " ++ @typeName(T)),
    };
}

test "scalar4" {
    const ns = scalarT(@Vector(4, types.Scalar));
    const eps = ns.init(0.000001);
    try std.testing.expectEqual(ns.isNan(.{ 0, ns.child.nan, 0, ns.child.nan }), .{ false, true, false, true });
    try std.testing.expectEqual(ns.approxEqAbs(
        ns.atan2(.{ 0, 0.2, -0.2, 0.34 }, .{ 1, 0.2, 0.2, -0.4 }),
        .{ 0, 0.785398, -0.785398, 2.437099 },
        eps,
    ), .{ true, true, true, true });
    try std.testing.expectEqual(ns.approxEqAbs(
        .{ ns.child.nan, 1, ns.child.nan, ns.child.inf },
        .{ 1, 1, ns.child.nan, ns.child.inf },
        ns.eps,
    ), .{ false, true, false, true });
}
