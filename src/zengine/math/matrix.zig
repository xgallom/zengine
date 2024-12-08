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
        pub const Scalar = T;
        pub const rows = M;
        pub const cols = N;
        pub const len: usize = M * N;

        pub const vector = vectorNT(N, T);
        pub const scalar = scalarT(T);

        pub fn slice(comptime L: usize, self: *Self) []Scalar {
            comptime assert(L <= len);
            return @as(*[L]Scalar, @ptrCast(@alignCast(&self)))[0..L];
        }

        pub fn slice_const(comptime L: usize, self: *const Self) []const Scalar {
            comptime assert(L <= len);
            return @as(*const [L]Scalar, @ptrCast(@alignCast(&self)))[0..L];
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
                    .{ scalar.zero, scalar.zero, -(far_plane + near_plane) / (far_plane - near_plane), scalar.neg_one },
                    .{ scalar.zero, scalar.zero, -(scalar.init(-2) * far_plane * near_plane) / (far_plane - near_plane), scalar.zero },
                };
            }

            pub fn camera(result: *Self, position: *const Vector3, direction: *const Vector3, up: *const Vector3) void {
                var coordinates: vector3.Coordinates = undefined;
                vector3.inverse_local_coordinates(&coordinates, direction, up);

                const x = &coordinates.x;
                const y = &coordinates.y;
                const z = &coordinates.z;

                result.* = .{
                    .{ x[0], y[0], z[0], scalar.zero },
                    .{ x[1], y[1], z[1], scalar.zero },
                    .{ x[2], y[2], z[2], scalar.zero },
                    .{ -vector3.dot(x, position), -vector3.dot(y, position), -vector3.dot(z, position), scalar.one },
                };
            }

            pub fn look_at(result: *Self, position: *const Vector3, target: *const Vector3, up: *const Vector3) void {
                var direction = target.*;
                vector3.sub(&direction, position);
                vector3.normalize(&direction);
                camera(result, position, &direction, up);
            }
        } else struct {};
    };
}
