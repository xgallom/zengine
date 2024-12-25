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

        pub const scalar = scalarT(T);

        pub const zero = splat(0);
        pub const one = splat(1);
        pub const neg_one = splat(-1);

        pub fn splat(value: Scalar) Self {
            var result: Self = undefined;
            for (0..len) |n| result[n] = value;
            return result;
        }

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

        const self3 = if (N == 3) struct {
            pub const Coordinates = struct {
                x: Self,
                y: Self,
                z: Self,
            };

            pub fn translate_scale(direction: *Self, translation: *const Self, multiplier: Scalar) void {
                mul_add(direction, translation, multiplier);
            }

            pub fn rotate_direction_scale(direction: *Self, rotation: *const Self, multiplier: Scalar) void {
                mul_add(direction, rotation, multiplier);
            }

            pub fn translate_direction_scale(direction: *Self, translation: *const Self, multiplier: Scalar) void {
                mul_sub(direction, translation, multiplier);
            }

            pub fn cross(result: *Self, lhs: *const Self, rhs: *const Self) void {
                result[0] = lhs[1] * rhs[2] - lhs[2] * rhs[1];
                result[1] = lhs[2] * rhs[0] - lhs[0] * rhs[2];
                result[2] = lhs[0] * rhs[1] - lhs[1] * rhs[0];
            }

            pub fn local_coordinates(result: *Coordinates, direction: *const Self, up: *const Self) void {
                assert(length(up) == 1);

                result.z = direction.*;
                normalize(&result.z);
                scale(&result.z, -1);
                cross(&result.x, &result.z, up);
                normalize(&result.x);
                cross(&result.y, &result.x, &result.z);
            }

            pub fn camera_coordinates(result: *Coordinates, direction: *const Self, up: *const Self) void {
                assert(length(up) == 1);

                result.z = direction.*;
                normalize(&result.z);
                scale(&result.z, -1);
                cross(&result.x, &result.z, up);
                normalize(&result.x);
                cross(&result.y, &result.x, &result.z);
            }
        } else struct {};
        pub usingnamespace self3;
    };
}

test "vector3" {
    const ns = vectorNT(3, types.Scalar);
    const lhs = ns.Self{ 2, 4, 6 };
    const rhs = ns.Self{ 1, 2, 3 };

    var result = lhs;
    ns.add(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 3, 6, 9 }, ns.slice_len_const(&result));
    result = lhs;
    ns.sub(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 2, 3 }, ns.slice_len_const(&result));
    result = lhs;
    ns.mul(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 8, 18 }, ns.slice_len_const(&result));
    result = lhs;
    ns.div(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 2, 2 }, ns.slice_len_const(&result));
    result = lhs;
    ns.mul_add(&result, &rhs, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 8, 12 }, ns.slice_len_const(&result));
    result = lhs;
    ns.mul_sub(&result, &rhs, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 0, 0 }, ns.slice_len_const(&result));
    result = lhs;
    ns.scale(&result, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 8, 12 }, ns.slice_len_const(&result));
    result = lhs;
    ns.scale_recip(&result, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 2, 3 }, ns.slice_len_const(&result));
    result = lhs;
    try std.testing.expect(ns.square_length(&result) == 56);
    result = ns.Self{ 2, 2, 1 };
    try std.testing.expect(ns.length(&result) == 3);
    result = ns.Self{ 2, 2, 1 };
    ns.normalize(&result);
    {
        const len = @sqrt(2.0 * 2.0 + 2.0 * 2.0 + 1.0 * 1.0);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 2.0 / len, 2.0 / len, 1.0 / len }, ns.slice_len_const(&result));
    }
    try std.testing.expect(ns.dot(&lhs, &rhs) == (2 * 1 + 4 * 2 + 6 * 3));
    {
        var dot: ns.Scalar = undefined;
        ns.dot_into(&dot, &lhs, &rhs);
    }
    ns.cross(&result, &lhs, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &ns.zero, &result);
    ns.cross(&result, &lhs, &.{ 6, 2, 4 });
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 28, -20 }, &result);
    {
        var coords: ns.Coordinates = undefined;
        ns.local_coordinates(&coords, &.{ 0, 0, 1 }, &.{ 0, 1, 0 });
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 0, 0 }, &coords.x);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 1, 0 }, &coords.y);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 0, 1 }, &coords.z);
        ns.inverse_local_coordinates(&coords, &.{ 0, 0, 1 }, &.{ 0, 1, 0 });
        try std.testing.expectEqualSlices(ns.Scalar, &.{ -1, 0, 0 }, &coords.x);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 1, 0 }, &coords.y);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 0, -1 }, &coords.z);
    }
}

test "vector3f64" {
    const ns = vectorNT(3, types.Scalar64);
    const lhs = ns.Self{ 2, 4, 6 };
    const rhs = ns.Self{ 1, 2, 3 };

    var result = lhs;
    ns.add(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 3, 6, 9 }, ns.slice_len_const(&result));
    result = lhs;
    ns.sub(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 2, 3 }, ns.slice_len_const(&result));
    result = lhs;
    ns.mul(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 8, 18 }, ns.slice_len_const(&result));
    result = lhs;
    ns.div(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 2, 2 }, ns.slice_len_const(&result));
    result = lhs;
    ns.mul_add(&result, &rhs, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 8, 12 }, ns.slice_len_const(&result));
    result = lhs;
    ns.mul_sub(&result, &rhs, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 0, 0 }, ns.slice_len_const(&result));
    result = lhs;
    ns.scale(&result, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 8, 12 }, ns.slice_len_const(&result));
    result = lhs;
    ns.scale_recip(&result, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 2, 3 }, ns.slice_len_const(&result));
    result = lhs;
    try std.testing.expect(ns.square_length(&result) == 56);
    result = ns.Self{ 2, 2, 1 };
    try std.testing.expect(ns.length(&result) == 3);
    result = ns.Self{ 2, 2, 1 };
    ns.normalize(&result);
    {
        const len = @sqrt(2.0 * 2.0 + 2.0 * 2.0 + 1.0 * 1.0);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 2.0 / len, 2.0 / len, 1.0 / len }, ns.slice_len_const(&result));
    }
    try std.testing.expect(ns.dot(&lhs, &rhs) == (2 * 1 + 4 * 2 + 6 * 3));
    {
        var dot: ns.Scalar = undefined;
        ns.dot_into(&dot, &lhs, &rhs);
    }
    ns.cross(&result, &lhs, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &ns.zero, &result);
    ns.cross(&result, &lhs, &.{ 6, 2, 4 });
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 28, -20 }, &result);
    {
        var coords: ns.Coordinates = undefined;
        ns.local_coordinates(&coords, &.{ 0, 0, 1 }, &.{ 0, 1, 0 });
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 0, 0 }, &coords.x);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 1, 0 }, &coords.y);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 0, 1 }, &coords.z);
        ns.inverse_local_coordinates(&coords, &.{ 0, 0, 1 }, &.{ 0, 1, 0 });
        try std.testing.expectEqualSlices(ns.Scalar, &.{ -1, 0, 0 }, &coords.x);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 1, 0 }, &coords.y);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 0, -1 }, &coords.z);
    }
}
