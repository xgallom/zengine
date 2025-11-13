//!
//! The zengine scalar operations
//!

const std = @import("std");
const assert = std.debug.assert;

const types = @import("types.zig");

pub fn IntMask(comptime len: comptime_int) type {
    comptime assert(len > 0);
    return struct {
        pub const uses_mask = @popCount(@as(usize, len)) == 1;

        pub inline fn index(elem_index: anytype) @TypeOf(elem_index) {
            return switch (comptime uses_mask) {
                true => elem_index >> comptime @ctz(len),
                false => elem_index / len,
            };
        }

        pub inline fn offset(elem_index: anytype) @TypeOf(elem_index) {
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
        .vector => |field_info| switch (@typeInfo(field_info.child)) {
            .float, .comptime_float => struct {
                pub const Self = T;
                pub const Scalar = @typeInfo(T).vector.child;
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

                pub fn epsAt(value: Scalar) Self {
                    return @splat(std.math.floatEpsAt(Scalar, value));
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

                pub fn to(comptime U: type, value: Scalar) U {
                    return switch (@typeInfo(U)) {
                        .float, .comptime_float => @compileError("Can not convert vector to float"),
                        .int, .comptime_int => @compileError("Can not convert vector to int"),
                        .vector => |u_info| if (comptime field_info.len == u_info.len) blk: {
                            var result: U = undefined;
                            for (0..field_info.len) |n| {
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

                pub fn to(comptime U: type, value: Scalar) U {
                    return switch (@typeInfo(U)) {
                        .float, .comptime_float => @compileError("Can not convert vector to float"),
                        .int, .comptime_int => @compileError("Can not convert vector to int"),
                        .vector => |u_info| if (comptime field_info.len == u_info.len) blk: {
                            var result: U = undefined;
                            for (0..field_info.len) |n| {
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
            else => @compileError("Unsupported vector scalar type " ++ @typeName(field_info.child)),
        },
        else => @compileError("Unsupported scalar type " ++ @typeName(T)),
    };
}
