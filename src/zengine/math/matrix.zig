//!
//! The zengine dense matrix implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const types = @import("types.zig");
const scalarT = @import("scalar.zig").scalarT;
const vectorNT = @import("vector.zig").vectorNT;

pub fn matrixMxNT(comptime M: usize, comptime N: usize, comptime T: type) type {
    return struct {
        pub const Self = types.MatrixMxNT(M, N, T);
        pub const Vector = types.VectorNT(N, T);
        pub const Scalar = T;
        pub const rows = M;
        pub const cols = N;
        pub const len: usize = M * N;

        pub const vector = vectorNT(N, T);
        pub const scalar = scalarT(T);

        pub const zero = splat(scalar.zero);
        pub const one = splat(scalar.one);
        pub const neg_one = splat(scalar.neg_one);
        pub const identity = make_identity();

        fn make_identity() Self {
            var result = zero;
            for (0..rows) |i| {
                result[i][i] = scalar.one;
            }
            return result;
        }

        pub fn splat(value: Scalar) Self {
            var result: Self = undefined;
            const r = slice_len(&result);
            for (0..len) |n| r[n] = value;
            return result;
        }

        pub fn slice(comptime L: usize, self: *Self) []Scalar {
            comptime assert(L <= len);
            return @as([*]Scalar, @ptrCast(@alignCast(self)))[0..L];
        }

        pub fn slice_const(comptime L: usize, self: *const Self) []const Scalar {
            comptime assert(L <= len);
            return @as([*]const Scalar, @ptrCast(@alignCast(self)))[0..L];
        }

        pub fn slice_len(self: *Self) []Scalar {
            return slice(len, self);
        }

        pub fn slice_len_const(self: *const Self) []const Scalar {
            return slice_const(len, self);
        }

        pub fn neg(self: *Self) void {
            scale(self, scalar.neg_one);
        }

        pub fn add(self: *Self, other: *const Self) void {
            const s = slice_len(self);
            const o = slice_len_const(other);
            for (0..len) |n| {
                s[n] += o[n];
            }
        }

        pub fn sub(self: *Self, other: *const Self) void {
            const s = slice_len(self);
            const o = slice_len_const(other);
            for (0..len) |n| {
                s[n] -= o[n];
            }
        }

        pub fn mul(self: *Self, other: *const Self) void {
            const s = slice_len(self);
            const o = slice_len_const(other);
            for (0..len) |n| {
                s[n] *= o[n];
            }
        }

        pub fn div(self: *Self, other: *const Self) void {
            const s = slice_len(self);
            const o = slice_len_const(other);
            for (0..len) |n| {
                s[n] /= o[n];
            }
        }

        pub fn mul_add(self: *Self, other: *const Self, multiplier: Scalar) void {
            const s = slice_len(self);
            const o = slice_len_const(other);
            for (0..len) |n| {
                s[n] = @mulAdd(Scalar, o[n], multiplier, s[n]);
            }
        }

        pub fn mul_sub(self: *Self, other: *const Self, multiplier: Scalar) void {
            const s = slice_len(self);
            const o = slice_len_const(other);
            for (0..len) |n| {
                s[n] = @mulAdd(Scalar, o[n], -multiplier, s[n]);
            }
        }

        pub fn scale(self: *Self, multiplier: Scalar) void {
            const s = slice_len(self);
            for (0..len) |n| {
                s[n] *= multiplier;
            }
        }

        pub fn scale_recip(self: *Self, multiplier: Scalar) void {
            const s = slice_len(self);
            const recip = scalar.one / multiplier;
            for (0..len) |n| {
                s[n] *= recip;
            }
        }

        pub fn apply(result: *vector.Self, operation: *const Self, operand: *const vector.Self) void {
            for (0..rows) |y| {
                vector.dot_into(&result[y], &operation[y], operand);
            }
        }

        pub fn dot(result: *Self, lhs: *const Self, rhs: *const Self) void {
            comptime assert(rows == cols);
            for (0..rows) |y| {
                for (0..cols) |x| {
                    result[y][x] = scalar.zero;
                    for (0..cols) |n| {
                        result[y][x] = @mulAdd(Scalar, lhs[y][n], rhs[n][x], result[y][x]);
                    }
                }
            }
        }

        pub fn transpose(self: *Self) void {
            comptime assert(rows == cols);
            for (0..rows) |y| {
                for (0..y) |x| {
                    const tmp = self[y][x];
                    self[y][x] = self[x][y];
                    self[x][y] = tmp;
                }
            }
        }

        pub usingnamespace if (rows == 4 and cols == 4) struct {
            pub const Vector3 = types.VectorNT(3, T);
            pub const vector3 = vectorNT(3, T);

            pub fn world_transform(result: *Self) void {
                result.* = .{
                    .{ scalar.one, scalar.zero, scalar.zero, scalar.zero },
                    .{ scalar.zero, scalar.one, scalar.zero, scalar.zero },
                    .{ scalar.zero, scalar.zero, scalar.one, scalar.zero },
                    .{ scalar.zero, scalar.zero, scalar.zero, scalar.one },
                };
            }

            pub fn perspective_fov(result: *Self, field_of_view: Scalar, width: Scalar, height: Scalar, near_plane: Scalar, far_plane: Scalar) void {
                const y = scalar.one / @tan(scalar.init(0.5) * field_of_view);
                const x = y * height / width;

                result.* = .{
                    .{ x, scalar.zero, scalar.zero, scalar.zero },
                    .{ scalar.zero, y, scalar.zero, scalar.zero },
                    .{ scalar.zero, scalar.zero, far_plane / (near_plane - far_plane), (near_plane * far_plane) / (near_plane - far_plane) },
                    .{ scalar.zero, scalar.zero, scalar.neg_one, scalar.zero },
                };
            }

            pub fn camera(result: *Self, position: *const Vector3, direction: *const Vector3, up: *const Vector3) void {
                var coordinates: vector3.Coordinates = undefined;
                vector3.camera_coordinates(&coordinates, direction, up);

                const x = &coordinates.x;
                const y = &coordinates.y;
                const z = &coordinates.z;

                result.* = .{
                    .{ x[0], x[1], x[2], -vector3.dot(x, position) },
                    .{ y[0], y[1], y[2], -vector3.dot(y, position) },
                    .{ z[0], z[1], z[2], -vector3.dot(z, position) },
                    .{ scalar.zero, scalar.zero, scalar.zero, scalar.one },
                };
            }

            pub fn look_at(result: *Self, position: *const Vector3, target: *const Vector3, up: *const Vector3) void {
                var direction = target.*;
                vector3.sub(&direction, position);
                camera(result, position, &direction, up);
            }

            pub fn scale_xyz(operand: *Self, scales: *const Vector3) void {
                const operation: Self = .{
                    .{ scales[0], scalar.zero, scalar.zero, scalar.zero },
                    .{ scalar.zero, scales[1], scalar.zero, scalar.zero },
                    .{ scalar.zero, scalar.zero, scales[2], scalar.zero },
                    .{ scalar.zero, scalar.zero, scalar.zero, scalar.one },
                };
                const input = operand.*;
                dot(operand, &operation, &input);
            }

            pub fn scaling_xyz(scales: *const Vector3) Self {
                var result = identity;
                scale_xyz(&result, scales);
                return result;
            }

            pub fn rotate_euler(operand: *Self, rotation: *const types.Euler, order: types.EulerOrder) void {
                const operations: []const Self = &.{
                    // x
                    .{
                        .{ scalar.one, scalar.zero, scalar.zero, scalar.zero },
                        .{ scalar.zero, @cos(rotation[0]), -@sin(rotation[0]), scalar.zero },
                        .{ scalar.zero, @sin(rotation[0]), @cos(rotation[0]), scalar.zero },
                        .{ scalar.zero, scalar.zero, scalar.zero, scalar.one },
                    },
                    // y
                    .{
                        .{ @cos(rotation[1]), scalar.zero, @sin(rotation[1]), scalar.zero },
                        .{ scalar.zero, scalar.one, scalar.zero, scalar.zero },
                        .{ -@sin(rotation[1]), scalar.zero, @cos(rotation[1]), scalar.zero },
                        .{ scalar.zero, scalar.zero, scalar.zero, scalar.one },
                    },
                    // z
                    .{
                        .{ @cos(rotation[2]), -@sin(rotation[2]), scalar.zero, scalar.zero },
                        .{ @sin(rotation[2]), @cos(rotation[2]), scalar.zero, scalar.zero },
                        .{ scalar.zero, scalar.zero, scalar.one, scalar.zero },
                        .{ scalar.zero, scalar.zero, scalar.zero, scalar.one },
                    },
                };
                inline for (order.axes()) |axis| {
                    const input = operand.*;
                    dot(operand, &operations[@intFromEnum(axis)], &input);
                }
            }

            pub fn rotation_euler(rotation: *const types.Euler, order: types.EulerOrder) Self {
                var result = identity;
                rotate_euler(&result, rotation, order);
                return result;
            }

            pub fn translate_xyz(operand: *Self, translation: *const Vector3) void {
                const operation = Self{
                    .{ scalar.one, scalar.zero, scalar.zero, translation[0] },
                    .{ scalar.zero, scalar.one, scalar.zero, translation[1] },
                    .{ scalar.zero, scalar.zero, scalar.one, translation[2] },
                    .{ scalar.zero, scalar.zero, scalar.zero, scalar.one },
                };
                const input = operand.*;
                dot(operand, &operation, &input);
            }
            pub fn translation_xyz(translation: *const Vector3) Self {
                var result = identity;
                translate_xyz(&result, translation);
                return result;
            }
        } else struct {};
    };
}

test "matrix4x4" {
    const ns = matrixMxNT(4, 4, types.Scalar);
    const lhs = ns.Self{
        .{ 2, 4, 6, 8 },
        .{ 10, 12, 14, 16 },
        .{ 18, 20, 22, 24 },
        .{ 26, 28, 30, 32 },
    };
    const rhs = ns.Self{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    };

    var result = lhs;
    ns.add(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 3, 6, 9, 12 }, ns.vector.slice_len_const(&result[0]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 15, 18, 21, 24 }, ns.vector.slice_len_const(&result[1]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 27, 30, 33, 36 }, ns.vector.slice_len_const(&result[2]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 39, 42, 45, 48 }, ns.vector.slice_len_const(&result[3]));
    result = lhs;
    ns.sub(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 2, 3, 4 }, ns.vector.slice_len_const(&result[0]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 5, 6, 7, 8 }, ns.vector.slice_len_const(&result[1]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 9, 10, 11, 12 }, ns.vector.slice_len_const(&result[2]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 13, 14, 15, 16 }, ns.vector.slice_len_const(&result[3]));
    result = lhs;
    ns.mul(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 8, 18, 32 }, ns.vector.slice_len_const(&result[0]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 50, 72, 98, 128 }, ns.vector.slice_len_const(&result[1]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 162, 200, 242, 288 }, ns.vector.slice_len_const(&result[2]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 338, 392, 450, 512 }, ns.vector.slice_len_const(&result[3]));
    result = lhs;
    ns.div(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 2, 2, 2 }, ns.vector.slice_len_const(&result[0]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 2, 2, 2 }, ns.vector.slice_len_const(&result[1]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 2, 2, 2 }, ns.vector.slice_len_const(&result[2]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 2, 2, 2 }, ns.vector.slice_len_const(&result[3]));
    result = lhs;
    ns.mul_add(&result, &rhs, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 8, 12, 16 }, ns.vector.slice_len_const(&result[0]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 20, 24, 28, 32 }, ns.vector.slice_len_const(&result[1]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 36, 40, 44, 48 }, ns.vector.slice_len_const(&result[2]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 52, 56, 60, 64 }, ns.vector.slice_len_const(&result[3]));
    result = lhs;
    ns.mul_sub(&result, &rhs, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &ns.vector.zero, ns.vector.slice_len_const(&result[0]));
    try std.testing.expectEqualSlices(ns.Scalar, &ns.vector.zero, ns.vector.slice_len_const(&result[1]));
    try std.testing.expectEqualSlices(ns.Scalar, &ns.vector.zero, ns.vector.slice_len_const(&result[2]));
    try std.testing.expectEqualSlices(ns.Scalar, &ns.vector.zero, ns.vector.slice_len_const(&result[3]));
    result = lhs;
    ns.scale(&result, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 8, 12, 16 }, ns.vector.slice_len_const(&result[0]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 20, 24, 28, 32 }, ns.vector.slice_len_const(&result[1]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 36, 40, 44, 48 }, ns.vector.slice_len_const(&result[2]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 52, 56, 60, 64 }, ns.vector.slice_len_const(&result[3]));
    result = lhs;
    ns.scale_recip(&result, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 2, 3, 4 }, ns.vector.slice_len_const(&result[0]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 5, 6, 7, 8 }, ns.vector.slice_len_const(&result[1]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 9, 10, 11, 12 }, ns.vector.slice_len_const(&result[2]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 13, 14, 15, 16 }, ns.vector.slice_len_const(&result[3]));
    {
        var vec_result: ns.Vector = undefined;
        ns.apply(&vec_result, &lhs, &.{ 1, 2, 3, 4 });
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 60, 140, 220, 300 }, ns.vector.slice_len_const(&vec_result));
    }
    ns.dot(&result, &lhs, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 180, 200, 220, 240 }, ns.vector.slice_len_const(&result[0]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 404, 456, 508, 560 }, ns.vector.slice_len_const(&result[1]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 628, 712, 796, 880 }, ns.vector.slice_len_const(&result[2]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 852, 968, 1084, 1200 }, ns.vector.slice_len_const(&result[3]));
    result = lhs;
    ns.transpose(&result);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 10, 18, 26 }, ns.vector.slice_len_const(&result[0]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 12, 20, 28 }, ns.vector.slice_len_const(&result[1]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 6, 14, 22, 30 }, ns.vector.slice_len_const(&result[2]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 8, 16, 24, 16 }, ns.vector.slice_len_const(&result[3]));
}
