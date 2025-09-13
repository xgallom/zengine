//!
//! The zengine quaternion4 implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const scalarT = @import("scalar.zig").scalarT;
const vectorNT = @import("vector.zig").vectorNT;
const types = @import("types.zig");

pub fn quatT(comptime T: type) type {
    return struct {
        pub const Self = types.VectorNT(4, T);
        pub const Scalar = T;
        pub const len = 4;

        const Vector3 = types.VectorNT(3, T);

        pub const scalar = scalarT(T);
        pub const vector = vectorNT(4, T);

        pub const identity: Self = .{ scalar.zero, scalar.zero, scalar.zero, scalar.one };

        pub fn slice(comptime L: usize, self: *Self) []Scalar {
            comptime assert(L <= len);
            return self[0..L];
        }

        pub fn sliceConst(comptime L: usize, self: *const Self) []const Scalar {
            comptime assert(L <= len);
            return self[0..L];
        }

        pub fn sliceLen(self: *Self) []Scalar {
            return slice(len, self);
        }

        pub fn sliceLenConst(self: *const Self) []const Scalar {
            return sliceConst(len, self);
        }

        pub inline fn idx(self: *Self, axis: types.Axis4) *Scalar {
            return &self[@intFromEnum(axis)];
        }

        pub inline fn idx3c(self: *const Vector3, axis: types.Axis3) Scalar {
            return self[@intFromEnum(axis)];
        }

        pub fn init(angle: Scalar, axis: *const Vector3) Self {
            var result: Self = undefined;
            const r = vector.map(&result);
            const a = vectorNT(3, Scalar).cmap(axis);
            idx(&result, .w).* = @cos(angle / 2);
            const s = @sin(angle / 2);
            r.x().* = s * a.x();
            r.y().* = s * a.y();
            r.z().* = s * a.z();
            return result;
        }

        pub fn mul(self: *Self, other: *const Self) void {
            const copy = self.*;
            mulInto(self, &copy, other);
        }

        pub fn mulInto(result: *Self, lhs: *const Self, rhs: *const Self) void {
            const l = vector.cmap(lhs);
            const r = vector.cmap(rhs);
            const y = vector.map(result);
            y.x().* = l.w() * r.x() + l.x() * r.w() + l.y() * r.z() - l.z() * r.y();
            y.y().* = l.w() * r.y() + l.y() * r.w() - l.x() * r.z() + l.z() * r.x();
            y.z().* = l.w() * r.z() + l.z() * r.w() + l.x() * r.y() - l.y() * r.x();
            y.w().* = l.w() * r.w() - l.x() * r.x() - l.y() * r.y() - l.z() * r.z();
        }

        pub fn scale(self: *Self, multiplier: Scalar) void {
            for (0..len) |n| self[n] *= multiplier;
        }

        pub fn scaleRecip(self: *Self, multiplier: Scalar) void {
            const recip = scalar.one / multiplier;
            for (0..len) |n| self[n] *= recip;
        }

        pub fn magSqr(self: *const Self) Scalar {
            return dot(self, self);
        }

        pub fn mag(self: *const Self) Scalar {
            return @sqrt(magSqr(self));
        }

        pub fn normalize(self: *Self) void {
            const vector_length = scalar.one / mag(self);
            for (0..len) |n| self[n] *= vector_length;
        }

        pub fn conjugate(self: *Self) void {
            for (0..len - 1) |n| self[n] *= -1;
        }

        pub fn inverse(self: *Self) void {
            const vector_length = scalar.one / magSqr(self);
            conjugate(self);
            for (0..len) |n| self[n] *= vector_length;
        }

        pub fn dot(lhs: *const Self, rhs: *const Self) Scalar {
            var sum = scalar.zero;
            for (0..len) |n| sum = @mulAdd(Scalar, lhs[n], rhs[n], sum);
            return sum;
        }

        pub fn apply(result: *Self, quat: *const Self, operand: *const Self) void {
            var inv = quat.*;
            inverse(&inv);
            mulInto(result, operand, &inv);
            const int = result.*;
            mulInto(result, quat, &int);
        }
    };
}

// test "vector3" {
//     const ns = vectorNT(3, types.Scalar);
//     const lhs = ns.Self{ 2, 4, 6 };
//     const rhs = ns.Self{ 1, 2, 3 };
//
//     var result = lhs;
//     ns.add(&result, &rhs);
//     try std.testing.expectEqualSlices(ns.Scalar, &.{ 3, 6, 9 }, ns.sliceLenConst(&result));
//     result = lhs;
//     ns.sub(&result, &rhs);
//     try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 2, 3 }, ns.sliceLenConst(&result));
//     result = lhs;
//     ns.mul(&result, &rhs);
//     try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 8, 18 }, ns.sliceLenConst(&result));
//     result = lhs;
//     ns.div(&result, &rhs);
//     try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 2, 2 }, ns.sliceLenConst(&result));
//     result = lhs;
//     ns.mulAdd(&result, &rhs, 2);
//     try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 8, 12 }, ns.sliceLenConst(&result));
//     result = lhs;
//     ns.mulSub(&result, &rhs, 2);
//     try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 0, 0 }, ns.sliceLenConst(&result));
//     result = lhs;
//     ns.scale(&result, 2);
//     try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 8, 12 }, ns.sliceLenConst(&result));
//     result = lhs;
//     ns.scaleRecip(&result, 2);
//     try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 2, 3 }, ns.sliceLenConst(&result));
//     result = lhs;
//     try std.testing.expect(ns.squareLength(&result) == 56);
//     result = ns.Self{ 2, 2, 1 };
//     try std.testing.expect(ns.length(&result) == 3);
//     result = ns.Self{ 2, 2, 1 };
//     ns.normalize(&result);
//     {
//         const len = @sqrt(2.0 * 2.0 + 2.0 * 2.0 + 1.0 * 1.0);
//         try std.testing.expectEqualSlices(ns.Scalar, &.{ 2.0 / len, 2.0 / len, 1.0 / len }, ns.sliceLenConst(&result));
//     }
//     try std.testing.expect(ns.dot(&lhs, &rhs) == (2 * 1 + 4 * 2 + 6 * 3));
//     {
//         var dot: ns.Scalar = undefined;
//         ns.dot_into(&dot, &lhs, &rhs);
//     }
//     ns.cross(&result, &lhs, &rhs);
//     try std.testing.expectEqualSlices(ns.Scalar, &ns.zero, &result);
//     ns.cross(&result, &lhs, &.{ 6, 2, 4 });
//     try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 28, -20 }, &result);
//     {
//         var coords: ns.Coordinates = undefined;
//         ns.local_coordinates(&coords, &.{ 0, 0, 1 }, &.{ 0, 1, 0 });
//         try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 0, 0 }, &coords.x);
//         try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 1, 0 }, &coords.y);
//         try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 0, 1 }, &coords.z);
//         ns.inverse_local_coordinates(&coords, &.{ 0, 0, 1 }, &.{ 0, 1, 0 });
//         try std.testing.expectEqualSlices(ns.Scalar, &.{ -1, 0, 0 }, &coords.x);
//         try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 1, 0 }, &coords.y);
//         try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 0, -1 }, &coords.z);
//     }
// }
//
// test "vector3f64" {
//     const ns = vectorNT(3, types.Scalar64);
//     const lhs = ns.Self{ 2, 4, 6 };
//     const rhs = ns.Self{ 1, 2, 3 };
//
//     var result = lhs;
//     ns.add(&result, &rhs);
//     try std.testing.expectEqualSlices(ns.Scalar, &.{ 3, 6, 9 }, ns.sliceLenConst(&result));
//     result = lhs;
//     ns.sub(&result, &rhs);
//     try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 2, 3 }, ns.sliceLenConst(&result));
//     result = lhs;
//     ns.mul(&result, &rhs);
//     try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 8, 18 }, ns.sliceLenConst(&result));
//     result = lhs;
//     ns.div(&result, &rhs);
//     try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 2, 2 }, ns.sliceLenConst(&result));
//     result = lhs;
//     ns.mulAdd(&result, &rhs, 2);
//     try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 8, 12 }, ns.sliceLenConst(&result));
//     result = lhs;
//     ns.mulSub(&result, &rhs, 2);
//     try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 0, 0 }, ns.sliceLenConst(&result));
//     result = lhs;
//     ns.scale(&result, 2);
//     try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 8, 12 }, ns.sliceLenConst(&result));
//     result = lhs;
//     ns.scaleRecip(&result, 2);
//     try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 2, 3 }, ns.sliceLenConst(&result));
//     result = lhs;
//     try std.testing.expect(ns.squareLength(&result) == 56);
//     result = ns.Self{ 2, 2, 1 };
//     try std.testing.expect(ns.length(&result) == 3);
//     result = ns.Self{ 2, 2, 1 };
//     ns.normalize(&result);
//     {
//         const len = @sqrt(2.0 * 2.0 + 2.0 * 2.0 + 1.0 * 1.0);
//         try std.testing.expectEqualSlices(ns.Scalar, &.{ 2.0 / len, 2.0 / len, 1.0 / len }, ns.sliceLenConst(&result));
//     }
//     try std.testing.expect(ns.dot(&lhs, &rhs) == (2 * 1 + 4 * 2 + 6 * 3));
//     {
//         var dot: ns.Scalar = undefined;
//         ns.dot_into(&dot, &lhs, &rhs);
//     }
//     ns.cross(&result, &lhs, &rhs);
//     try std.testing.expectEqualSlices(ns.Scalar, &ns.zero, &result);
//     ns.cross(&result, &lhs, &.{ 6, 2, 4 });
//     try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 28, -20 }, &result);
//     {
//         var coords: ns.Coords = undefined;
//         ns.localCoordinates(&coords, &.{ 0, 0, 1 }, &.{ 0, 1, 0 });
//         try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 0, 0 }, &coords.x);
//         try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 1, 0 }, &coords.y);
//         try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 0, 1 }, &coords.z);
//         ns.inverseLocalCoordinates(&coords, &.{ 0, 0, 1 }, &.{ 0, 1, 0 });
//         try std.testing.expectEqualSlices(ns.Scalar, &.{ -1, 0, 0 }, &coords.x);
//         try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 1, 0 }, &coords.y);
//         try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 0, -1 }, &coords.z);
//     }
// }
