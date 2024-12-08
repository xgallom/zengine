//!
//! The zengine dense vector implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const types = @import("types.zig");
const scalarT = @import("scalar.zig").scalarT;

pub fn vectorNT(comptime N: usize, comptime T: type) type {
    return struct {
        pub const Self = [N]T;
        pub const Scalar = T;
        pub const len = N;

        const scalar = scalarT(T);

        pub fn slice(comptime L: usize, self: *Self) []Scalar {
            comptime assert(L <= len);
            return self[0..L];
        }

        pub fn slice_const(comptime L: usize, self: *const Self) []const Scalar {
            comptime assert(L <= len);
            return self[0..L];
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
            for (0..len) |n| {
                self[n] += other[n];
            }
        }

        pub fn sub(self: *Self, other: *const Self) void {
            for (0..len) |n| {
                self[n] -= other[n];
            }
        }

        pub fn mul(self: *Self, other: *const Self) void {
            for (0..len) |n| {
                self[n] *= other[n];
            }
        }

        pub fn div(self: *Self, other: *const Self) void {
            for (0..len) |n| {
                self[n] /= other[n];
            }
        }

        pub fn mul_add(self: *Self, other: *const Self, multiplier: Scalar) void {
            for (0..len) |n| {
                self[n] = @mulAdd(Scalar, other[n], multiplier, self[n]);
            }
        }

        pub fn mul_sub(self: *Self, other: *const Self, multiplier: Scalar) void {
            for (0..len) |n| {
                self[n] = @mulAdd(Scalar, other[n], -multiplier, self[n]);
            }
        }

        pub fn scale(self: *Self, multiplier: Scalar) void {
            for (0..len) |n| {
                self[n] *= multiplier;
            }
        }

        pub fn scale_recip(self: *Self, multiplier: Scalar) void {
            const recip = scalar.one / multiplier;
            for (0..len) |n| {
                self[n] *= recip;
            }
        }

        pub fn square_length(self: *const Self) Scalar {
            return dot(self, self);
        }

        pub fn length(self: *const Self) Scalar {
            return @sqrt(square_length(self));
        }

        pub fn normalize(self: *Self) void {
            const vector_length = scalar.one / length(self);
            for (0..len) |n| {
                self[n] *= vector_length;
            }
        }

        pub fn dot(lhs: *const Self, rhs: *const Self) Scalar {
            var sum = scalar.zero;
            for (0..len) |n| {
                sum = @mulAdd(Scalar, lhs[n], rhs[n], sum);
            }
            return sum;
        }

        pub fn dot_into(result: *Scalar, lhs: *const Self, rhs: *const Self) void {
            result.* = scalar.zero;
            for (0..len) |n| {
                result.* = @mulAdd(Scalar, lhs[n], rhs[n], result.*);
            }
        }

        pub usingnamespace if (N == 3) struct {
            pub const Coordinates = struct {
                x: Self,
                y: Self,
                z: Self,
            };

            pub fn translate_scale(direction: *Self, rotation: *const Self, multiplier: Scalar) void {
                mul_add(direction, rotation, multiplier);
            }

            pub fn rotate_direction_scale(direction: *Self, rotation: *const Self, multiplier: Scalar) void {
                mul_sub(direction, rotation, multiplier);
            }

            pub fn translate_direction_scale(direction: *Self, rotation: *const Self, multiplier: Scalar) void {
                mul_add(direction, rotation, multiplier);
            }

            pub fn cross(result: *Self, lhs: *const Self, rhs: *const Self) void {
                result[0] = lhs[1] * rhs[2] - lhs[2] * rhs[1];
                result[1] = lhs[2] * rhs[0] - lhs[0] * rhs[2];
                result[2] = lhs[0] * rhs[1] - lhs[1] * rhs[0];
            }

            pub fn local_coordinates(result: *Coordinates, direction: *const Self, up: *const Self) void {
                result.z = direction.*;
                cross(&result.x, up, &result.z);
                normalize(&result.x);
                cross(&result.y, &result.z, &result.x);
            }

            pub fn inverse_local_coordinates(result: *Coordinates, direction: *const Self, up: *const Self) void {
                result.z = direction.*;
                scale(&result.z, -1);
                cross(&result.x, up, &result.z);
                normalize(&result.x);
                cross(&result.y, &result.z, &result.x);
            }
        } else struct {};
    };
}
