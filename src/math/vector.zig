const std = @import("std");
const assert = std.debug.assert;

const types = @import("types.zig");
const Scalar = types.Scalar;

pub fn VectorMath(comptime N: usize) type {
    return struct {
        const Self = [N]Scalar;

        pub fn add(vector: *Self, other: *const Self) void {
            for (0..N) |n| {
                vector[n] += other[n];
            }
        }

        pub fn sub(vector: *Self, other: *const Self) void {
            for (0..N) |n| {
                vector[n] -= other[n];
            }
        }

        pub fn mul(vector: *Self, other: *const Self) void {
            for (0..N) |n| {
                vector[n] *= other[n];
            }
        }

        pub fn div(vector: *Self, other: *const Self) void {
            for (0..N) |n| {
                vector[n] /= other[n];
            }
        }

        pub fn mul_add(vector: *Self, other: *const Self, multiplier: Scalar) void {
            for (0..N) |n| {
                vector[n] = @mulAdd(Scalar, other[n], multiplier, vector[n]);
            }
        }

        pub fn mul_sub(vector: *Self, other: *const Self, multiplier: Scalar) void {
            for (0..N) |n| {
                vector[n] = @mulAdd(Scalar, other[n], -multiplier, vector[n]);
            }
        }

        pub fn scale(vector: *Self, multiplier: Scalar) void {
            for (0..N) |n| {
                vector[n] *= multiplier;
            }
        }

        pub fn scale_recip(vector: *Self, recip: Scalar) void {
            for (0..N) |n| {
                vector[n] /= recip;
            }
        }

        pub fn square_length(vector: *const Self) Scalar {
            return dot(vector, vector);
        }

        pub fn length(vector: *const Self) Scalar {
            return @sqrt(square_length(vector));
        }

        pub fn normalize(vector: *Self) void {
            const vector_length = length(vector);
            for (0..N) |n| {
                vector[n] /= vector_length;
            }
        }

        pub fn dot(lhs: *const Self, rhs: *const Self) Scalar {
            var sum: Scalar = 0;
            for (0..N) |n| {
                sum = @mulAdd(Scalar, lhs[n], rhs[n], sum);
            }
            return sum;
        }

        pub usingnamespace if (N == 3) struct {
            pub const Coordinates = struct {
                front: Self,
                right: Self,
                up: Self,
            };

            pub fn cross(result: *Self, lhs: *const Self, rhs: *const Self) void {
                result.* = .{
                    lhs[1] * rhs[2] - lhs[2] * rhs[1],
                    lhs[2] * rhs[0] - lhs[0] * rhs[2],
                    lhs[0] * rhs[1] - lhs[1] * rhs[0],
                };
            }

            pub fn local_coordinates(result: *Coordinates, direction: *const Self, up: *const Self) void {
                result.front = direction.*;
                normalize(&result.front);
                cross(&result.right, up, &result.front);
                normalize(&result.right);
                cross(&result.up, &result.front, &result.right);
            }
        } else struct {};
    };
}

pub const vector3 = VectorMath(3);
pub const vector4 = VectorMath(4);
