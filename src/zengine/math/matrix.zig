//!
//! Generic dense matrix implementation
//!
//! Matrix is M rows by N columns,
//!
//! The underlying type is `[M][N]T`
//!

const std = @import("std");
const assert = std.debug.assert;

const scalarT = @import("scalar.zig").scalarT;
const types = @import("types.zig");
const vectorNT = @import("vector.zig").vectorNT;

pub fn matrixMxNT(comptime M: comptime_int, comptime N: comptime_int, comptime T: type) type {
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
        pub const identity = makeIdentity();

        fn makeIdentity() Self {
            var result = zero;
            for (0..rows) |i| {
                result[i][i] = scalar.one;
            }
            return result;
        }

        pub fn splat(value: Scalar) Self {
            var result: Self = undefined;
            const r = sliceLen(&result);
            for (0..len) |n| r[n] = value;
            return result;
        }

        pub fn splatInto(result: *Self, value: Scalar) void {
            const r = sliceLen(result);
            for (0..len) |n| r[n] = value;
        }

        pub fn slice(comptime L: usize, self: *Self) []Scalar {
            comptime assert(L <= len);
            return @as([*]Scalar, @ptrCast(@alignCast(self)))[0..L];
        }

        pub fn sliceConst(comptime L: usize, self: *const Self) []const Scalar {
            comptime assert(L <= len);
            return @as([*]const Scalar, @ptrCast(@alignCast(self)))[0..L];
        }

        pub fn sliceLen(self: *Self) []Scalar {
            return slice(len, self);
        }

        pub fn sliceLenConst(self: *const Self) []const Scalar {
            return sliceConst(len, self);
        }

        pub fn neg(self: *Self) void {
            scale(self, scalar.neg_one);
        }

        /// Y_mn += O_mn
        pub fn add(self: *Self, other: *const Self) void {
            const s = sliceLen(self);
            const o = sliceLenConst(other);
            for (0..len) |n| {
                s[n] += o[n];
            }
        }

        /// Y_mn -= O_mn
        pub fn sub(self: *Self, other: *const Self) void {
            const s = sliceLen(self);
            const o = sliceLenConst(other);
            for (0..len) |n| {
                s[n] -= o[n];
            }
        }

        /// Y_mn *= O_mn
        pub fn mul(self: *Self, other: *const Self) void {
            const s = sliceLen(self);
            const o = sliceLenConst(other);
            for (0..len) |n| {
                s[n] *= o[n];
            }
        }

        /// Y_mn /= O_mn
        pub fn div(self: *Self, other: *const Self) void {
            const s = sliceLen(self);
            const o = sliceLenConst(other);
            for (0..len) |n| {
                s[n] /= o[n];
            }
        }

        /// Y_mn += O_mn * mul
        pub fn mulAdd(self: *Self, other: *const Self, multiplier: Scalar) void {
            const s = sliceLen(self);
            const o = sliceLenConst(other);
            for (0..len) |n| {
                s[n] = @mulAdd(Scalar, o[n], multiplier, s[n]);
            }
        }

        /// Y_mn -= O_mn * mul
        pub fn mulSub(self: *Self, other: *const Self, multiplier: Scalar) void {
            const s = sliceLen(self);
            const o = sliceLenConst(other);
            for (0..len) |n| {
                s[n] = @mulAdd(Scalar, o[n], -multiplier, s[n]);
            }
        }

        /// Y_mn *= mul
        pub fn scale(self: *Self, multiplier: Scalar) void {
            const s = sliceLen(self);
            for (0..len) |n| {
                s[n] *= multiplier;
            }
        }

        /// Y_mn *= 1 / mul
        pub fn scaleRecip(self: *Self, multiplier: Scalar) void {
            const s = sliceLen(self);
            const recip = scalar.one / multiplier;
            for (0..len) |n| {
                s[n] *= recip;
            }
        }

        /// Y_m = O_mn X_n
        pub fn apply(result: *vector.Self, operation: *const Self, operand: *const vector.Self) void {
            for (0..rows) |y| {
                vector.dotInto(&result[y], &operation[y], operand);
            }
        }

        /// Y_mn = L_mx R_xn
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

        /// Y_mn = R_mx L_nx
        pub fn dotRight(result: *Self, lhs: *const Self, rhs: *const Self) void {
            comptime assert(rows == cols);
            for (0..rows) |y| {
                for (0..cols) |x| {
                    result[y][x] = scalar.zero;
                    for (0..cols) |n| {
                        result[y][x] = @mulAdd(Scalar, rhs[y][n], lhs[x][n], result[y][x]);
                    }
                }
            }
        }

        /// Y_mn = X_nm
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

        const Vector3 = types.VectorNT(3, T);
        const vector3 = vectorNT(3, T);

        pub fn worldTransform(result: *Self) void {
            if (rows == 4 and cols == 4) {} else @compileError("Wrong matrix dimensions");
            result.* = .{
                .{ scalar.one, scalar.zero, scalar.zero, scalar.zero },
                .{ scalar.zero, scalar.one, scalar.zero, scalar.zero },
                .{ scalar.zero, scalar.zero, scalar.one, scalar.zero },
                .{ scalar.zero, scalar.zero, scalar.zero, scalar.one },
            };
        }

        pub fn ortographicSides(result: *Self, top: Scalar, right: Scalar, bottom: Scalar, left: Scalar, near_plane: Scalar, far_plane: Scalar) void {
            if (rows == 4 and cols == 4) {} else @compileError("Wrong matrix dimensions");
            const x = right - left;
            const y = top - bottom;

            result.* = .{
                .{ 2 / x, scalar.zero, scalar.zero, -(right + left) / x },
                .{ scalar.zero, 2 / y, scalar.zero, -(top + bottom) / y },
                .{ scalar.zero, scalar.zero, 1 / (near_plane - far_plane), near_plane / (near_plane - far_plane) },
                .{ scalar.zero, scalar.zero, scalar.zero, scalar.one },
            };
        }

        pub fn ortographicScale(result: *Self, orto_scale: Scalar, width: Scalar, height: Scalar, near_plane: Scalar, far_plane: Scalar) void {
            if (rows == 4 and cols == 4) {} else @compileError("Wrong matrix dimensions");
            const y: Scalar = orto_scale;
            const x = y * width / height;

            result.* = .{
                .{ 2 / x, scalar.zero, scalar.zero, scalar.zero },
                .{ scalar.zero, 2 / y, scalar.zero, scalar.zero },
                .{ scalar.zero, scalar.zero, 1 / (near_plane - far_plane), near_plane / (near_plane - far_plane) },
                .{ scalar.zero, scalar.zero, scalar.zero, scalar.one },
            };
        }

        pub fn perspectiveFov(result: *Self, fov: Scalar, width: Scalar, height: Scalar, near_plane: Scalar, far_plane: Scalar) void {
            if (rows == 4 and cols == 4) {} else @compileError("Wrong matrix dimensions");
            const y = scalar.one / @tan(scalar.init(0.5) * fov);
            const x = y * height / width;

            result.* = .{
                .{ x, scalar.zero, scalar.zero, scalar.zero },
                .{ scalar.zero, y, scalar.zero, scalar.zero },
                .{ scalar.zero, scalar.zero, far_plane / (near_plane - far_plane), (near_plane * far_plane) / (near_plane - far_plane) },
                .{ scalar.zero, scalar.zero, scalar.neg_one, scalar.zero },
            };
        }

        pub fn camera(result: *Self, position: *const Vector3, direction: *const Vector3, up: *const Vector3) void {
            if (rows == 4 and cols == 4) {} else @compileError("Wrong matrix dimensions");
            var coordinates: vector3.Coords = undefined;
            vector3.cameraCoords(&coordinates, direction, up);

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

        pub fn lookAt(result: *Self, position: *const Vector3, target: *const Vector3, up: *const Vector3) void {
            if (rows == 4 and cols == 4) {} else @compileError("Wrong matrix dimensions");
            var direction = target.*;
            vector3.sub(&direction, position);
            camera(result, position, &direction, up);
        }

        pub fn scaleXYZ(operand: *Self, scales: *const Vector3) void {
            if (rows == 4 and cols == 4) {} else @compileError("Wrong matrix dimensions");
            const operation = scalingXYZ(scales);
            const input = operand.*;
            dot(operand, &operation, &input);
        }

        pub fn scalingXYZ(scales: *const Vector3) Self {
            if (rows == 4 and cols == 4) {} else @compileError("Wrong matrix dimensions");
            return .{
                .{ scales[0], scalar.zero, scalar.zero, scalar.zero },
                .{ scalar.zero, scales[1], scalar.zero, scalar.zero },
                .{ scalar.zero, scalar.zero, scales[2], scalar.zero },
                .{ scalar.zero, scalar.zero, scalar.zero, scalar.one },
            };
        }

        pub fn rotateEuler(operand: *Self, rotation: *const types.Euler, order: types.EulerOrder) void {
            if (rows == 4 and cols == 4) {} else @compileError("Wrong matrix dimensions");
            const operations: [types.Axis3.len]Self = .{
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

        pub fn rotationEuler(rotation: *const types.Euler, order: types.EulerOrder) Self {
            if (rows == 4 and cols == 4) {} else @compileError("Wrong matrix dimensions");
            var result = identity;
            rotateEuler(&result, rotation, order);
            return result;
        }

        pub fn translateXYZ(operand: *Self, translation: *const Vector3) void {
            if (rows == 4 and cols == 4) {} else @compileError("Wrong matrix dimensions");
            const operation = translationXYZ(translation);
            const input = operand.*;
            dot(operand, &operation, &input);
        }

        pub fn translationXYZ(translation: *const Vector3) Self {
            if (rows == 4 and cols == 4) {} else @compileError("Wrong matrix dimensions");
            return .{
                .{ scalar.one, scalar.zero, scalar.zero, translation[0] },
                .{ scalar.zero, scalar.one, scalar.zero, translation[1] },
                .{ scalar.zero, scalar.zero, scalar.one, translation[2] },
                .{ scalar.zero, scalar.zero, scalar.zero, scalar.one },
            };
        }
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
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 3, 6, 9, 12 }, ns.vector.sliceLenConst(&result[0]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 15, 18, 21, 24 }, ns.vector.sliceLenConst(&result[1]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 27, 30, 33, 36 }, ns.vector.sliceLenConst(&result[2]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 39, 42, 45, 48 }, ns.vector.sliceLenConst(&result[3]));
    result = lhs;
    ns.sub(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 2, 3, 4 }, ns.vector.sliceLenConst(&result[0]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 5, 6, 7, 8 }, ns.vector.sliceLenConst(&result[1]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 9, 10, 11, 12 }, ns.vector.sliceLenConst(&result[2]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 13, 14, 15, 16 }, ns.vector.sliceLenConst(&result[3]));
    result = lhs;
    ns.mul(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 8, 18, 32 }, ns.vector.sliceLenConst(&result[0]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 50, 72, 98, 128 }, ns.vector.sliceLenConst(&result[1]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 162, 200, 242, 288 }, ns.vector.sliceLenConst(&result[2]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 338, 392, 450, 512 }, ns.vector.sliceLenConst(&result[3]));
    result = lhs;
    ns.div(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 2, 2, 2 }, ns.vector.sliceLenConst(&result[0]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 2, 2, 2 }, ns.vector.sliceLenConst(&result[1]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 2, 2, 2 }, ns.vector.sliceLenConst(&result[2]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 2, 2, 2 }, ns.vector.sliceLenConst(&result[3]));
    result = lhs;
    ns.mul_add(&result, &rhs, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 8, 12, 16 }, ns.vector.sliceLenConst(&result[0]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 20, 24, 28, 32 }, ns.vector.sliceLenConst(&result[1]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 36, 40, 44, 48 }, ns.vector.sliceLenConst(&result[2]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 52, 56, 60, 64 }, ns.vector.sliceLenConst(&result[3]));
    result = lhs;
    ns.mul_sub(&result, &rhs, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &ns.vector.zero, ns.vector.sliceLenConst(&result[0]));
    try std.testing.expectEqualSlices(ns.Scalar, &ns.vector.zero, ns.vector.sliceLenConst(&result[1]));
    try std.testing.expectEqualSlices(ns.Scalar, &ns.vector.zero, ns.vector.sliceLenConst(&result[2]));
    try std.testing.expectEqualSlices(ns.Scalar, &ns.vector.zero, ns.vector.sliceLenConst(&result[3]));
    result = lhs;
    ns.scale(&result, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 8, 12, 16 }, ns.vector.sliceLenConst(&result[0]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 20, 24, 28, 32 }, ns.vector.sliceLenConst(&result[1]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 36, 40, 44, 48 }, ns.vector.sliceLenConst(&result[2]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 52, 56, 60, 64 }, ns.vector.sliceLenConst(&result[3]));
    result = lhs;
    ns.scale_recip(&result, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 2, 3, 4 }, ns.vector.sliceLenConst(&result[0]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 5, 6, 7, 8 }, ns.vector.sliceLenConst(&result[1]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 9, 10, 11, 12 }, ns.vector.sliceLenConst(&result[2]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 13, 14, 15, 16 }, ns.vector.sliceLenConst(&result[3]));
    {
        var vec_result: ns.Vector = undefined;
        ns.apply(&vec_result, &lhs, &.{ 1, 2, 3, 4 });
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 60, 140, 220, 300 }, ns.vector.sliceLenConst(&vec_result));
    }
    ns.dot(&result, &lhs, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 180, 200, 220, 240 }, ns.vector.sliceLenConst(&result[0]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 404, 456, 508, 560 }, ns.vector.sliceLenConst(&result[1]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 628, 712, 796, 880 }, ns.vector.sliceLenConst(&result[2]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 852, 968, 1084, 1200 }, ns.vector.sliceLenConst(&result[3]));
    result = lhs;
    ns.transpose(&result);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 10, 18, 26 }, ns.vector.sliceLenConst(&result[0]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 12, 20, 28 }, ns.vector.sliceLenConst(&result[1]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 6, 14, 22, 30 }, ns.vector.sliceLenConst(&result[2]));
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 8, 16, 24, 16 }, ns.vector.sliceLenConst(&result[3]));
}
