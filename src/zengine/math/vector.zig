//!
//! The zengine dense vector implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const scalarT = @import("scalar.zig").scalarT;
const types = @import("types.zig");

pub fn vectorNT(comptime N: comptime_int, comptime T: type) type {
    return struct {
        pub const Self = types.VectorNT(N, T);
        pub const Scalar = T;
        pub const Coords = types.CoordsNT(N, T);
        pub const len = N;

        pub const scalar = scalarT(T);

        pub const zero = splat(scalar.@"0");
        pub const one = splat(scalar.@"1");
        pub const neg_one = splat(scalar.@"-1");
        /// Non-translatable zero vector
        pub const ntr_zero = makeNonTranslatable(vectorNT(len - 1, T).zero);
        /// Non-translatable forward unit vector
        pub const ntr_fwd = makeNonTranslatableFwd(scalar.@"1");
        /// Translatable zero vector
        pub const tr_zero = makeTranslatable(vectorNT(len - 1, T).zero);
        /// Translatable forward unit vector
        pub const tr_fwd = makeTranslatableFwd(scalar.@"1");

        pub fn makeNonTranslatable(value: types.VectorNT(len - 1, T)) Self {
            return value ++ .{scalar.@"0"};
        }

        pub fn makeTranslatable(value: types.VectorNT(len - 1, T)) Self {
            return value ++ .{scalar.@"1"};
        }

        fn makeNonTranslatableFwd(fwd: Scalar) Self {
            comptime if (len == 4) {} else @compileError("forward not supported for vector of " ++ len);
            var result = zero;
            result[2] = -fwd;
            return result;
        }

        fn makeTranslatableFwd(fwd: Scalar) Self {
            comptime if (len == 4) {} else @compileError("forward not supported for vector of " ++ len);
            var result = zero;
            result[2] = -fwd;
            result[3] = scalar.one;
            return result;
        }

        pub const Map = struct {
            self: *Self,

            pub inline fn r(self: Map) *Scalar {
                comptime assert(len > @intFromEnum(types.Color.r));
                return &self.self[@intFromEnum(types.Color.r)];
            }
            pub inline fn g(self: Map) *Scalar {
                comptime assert(len > @intFromEnum(types.Color.g));
                return &self.self[@intFromEnum(types.Color.g)];
            }
            pub inline fn b(self: Map) *Scalar {
                comptime assert(len > @intFromEnum(types.Color.b));
                return &self.self[@intFromEnum(types.Color.b)];
            }
            pub inline fn a(self: Map) *Scalar {
                comptime assert(len > @intFromEnum(types.Color.a));
                return &self.self[@intFromEnum(types.Color.a)];
            }
            pub inline fn x(self: Map) *Scalar {
                comptime assert(len > @intFromEnum(types.Axis4.x));
                return &self.self[@intFromEnum(types.Axis4.x)];
            }
            pub inline fn y(self: Map) *Scalar {
                comptime assert(len > @intFromEnum(types.Axis4.y));
                return &self.self[@intFromEnum(types.Axis4.y)];
            }
            pub inline fn z(self: Map) *Scalar {
                comptime assert(len > @intFromEnum(types.Axis4.z));
                return &self.self[@intFromEnum(types.Axis4.z)];
            }
            pub inline fn w(self: Map) *Scalar {
                comptime assert(len > @intFromEnum(types.Axis4.w));
                return &self.self[@intFromEnum(types.Axis4.w)];
            }
        };

        pub const CMap = struct {
            self: *const Self,

            pub inline fn r(self: CMap) Scalar {
                comptime assert(len > @intFromEnum(types.Color.r));
                return self.self[@intFromEnum(types.Color.r)];
            }
            pub inline fn g(self: CMap) Scalar {
                comptime assert(len > @intFromEnum(types.Color.g));
                return self.self[@intFromEnum(types.Color.g)];
            }
            pub inline fn b(self: CMap) Scalar {
                comptime assert(len > @intFromEnum(types.Color.b));
                return self.self[@intFromEnum(types.Color.b)];
            }
            pub inline fn a(self: CMap) Scalar {
                comptime assert(len > @intFromEnum(types.Color.a));
                return self.self[@intFromEnum(types.Color.a)];
            }
            pub inline fn x(self: CMap) Scalar {
                comptime assert(len > @intFromEnum(types.Axis4.x));
                return self.self[@intFromEnum(types.Axis4.x)];
            }
            pub inline fn y(self: CMap) Scalar {
                comptime assert(len > @intFromEnum(types.Axis4.y));
                return self.self[@intFromEnum(types.Axis4.y)];
            }
            pub inline fn z(self: CMap) Scalar {
                comptime assert(len > @intFromEnum(types.Axis4.z));
                return self.self[@intFromEnum(types.Axis4.z)];
            }
            pub inline fn w(self: CMap) Scalar {
                comptime assert(len > @intFromEnum(types.Axis4.w));
                return self.self[@intFromEnum(types.Axis4.w)];
            }
        };

        pub inline fn map(self: *Self) Map {
            return .{ .self = self };
        }

        pub inline fn cmap(self: *const Self) CMap {
            return .{ .self = self };
        }

        pub fn from(comptime U: type, self: *const types.VectorNT(len, U)) Self {
            var result: Self = undefined;
            for (0..len) |n| result[n] = scalarT(U).to(Scalar, self[n]);
            return result;
        }

        pub fn to(comptime U: type, self: *const Self) types.VectorNT(len, U) {
            var result: types.VectorNT(len, U) = undefined;
            for (0..len) |n| result[n] = scalar.to(U, self[n]);
            return result;
        }

        pub fn splat(value: Scalar) Self {
            return @splat(value);
        }

        pub fn splatInto(result: *Self, value: Scalar) void {
            result.* = @splat(value);
        }

        pub fn sliceLen(comptime L: usize, self: *Self) []Scalar {
            comptime assert(L <= len);
            return self[0..L];
        }

        pub fn sliceLenConst(comptime L: usize, self: *const Self) []const Scalar {
            comptime assert(L <= len);
            return self[0..L];
        }

        pub fn slice(self: *Self) []Scalar {
            return sliceLen(len, self);
        }

        pub fn sliceConst(self: *const Self) []const Scalar {
            return sliceLenConst(len, self);
        }

        pub fn eqlAbs(self: *const Self, other: *const Self, comptime tolerance: Scalar) bool {
            comptime if (!scalar.is_float) @compileError("eqlAbs not supported for vector of " ++ @typeName(Scalar));
            for (0..len) |n| if (!std.math.approxEqAbs(Scalar, self[n], other[n], tolerance)) return false;
            return true;
        }

        pub fn eqlRel(self: *const Self, other: *const Self, comptime tolerance: Scalar) bool {
            comptime if (!scalar.is_float) @compileError("eqlRel not supported for vector of " ++ @typeName(Scalar));
            for (0..len) |n| if (!std.math.approxEqRel(Scalar, self[n], other[n], tolerance)) return false;
            return true;
        }

        pub fn eqlExact(self: *const Self, other: *const Self) bool {
            for (0..len) |n| if (self[n] != other[n]) return false;
            return true;
        }

        pub fn neg(self: *Self) void {
            scale(self, scalar.@"-1");
        }

        pub fn add(self: *Self, other: *const Self) void {
            for (0..len) |n| self[n] += other[n];
        }

        pub fn sub(self: *Self, other: *const Self) void {
            for (0..len) |n| self[n] -= other[n];
        }

        pub fn mul(self: *Self, other: *const Self) void {
            for (0..len) |n| self[n] *= other[n];
        }

        pub fn div(self: *Self, other: *const Self) void {
            for (0..len) |n| self[n] /= other[n];
        }

        pub fn shl(self: *Self, bits: std.math.Log2Int(@sizeOf(Scalar))) void {
            for (0..len) |n| self[n] <<= bits;
        }

        pub fn shr(self: *Self, bits: std.math.Log2Int(Scalar)) void {
            for (0..len) |n| self[n] >>= bits;
        }

        pub fn mulAdd(self: *Self, other: *const Self, multiplier: Scalar) void {
            for (0..len) |n| self[n] = @mulAdd(Scalar, other[n], multiplier, self[n]);
        }

        pub fn mulSub(self: *Self, other: *const Self, multiplier: Scalar) void {
            for (0..len) |n| self[n] = @mulAdd(Scalar, other[n], -multiplier, self[n]);
        }

        pub fn scale(self: *Self, multiplier: Scalar) void {
            for (0..len) |n| self[n] *= multiplier;
        }

        pub fn scaleRecip(self: *Self, multiplier: Scalar) void {
            if (comptime scalar.is_float) {
                const recip = scalar.recip(multiplier);
                for (0..len) |n| self[n] *= recip;
            } else {
                for (0..len) |n| self[n] /= multiplier;
            }
        }

        pub fn magSqr(self: *const Self) Scalar {
            return dot(self, self);
        }

        pub fn mag(self: *const Self) Scalar {
            comptime if (!scalar.is_float) @compileError("mag not supported for vector of " ++ @typeName(Scalar));
            return @sqrt(magSqr(self));
        }

        pub fn normalize(self: *Self) void {
            comptime if (!scalar.is_float) @compileError("normalize not supported for vector of " ++ @typeName(Scalar));
            scaleRecip(self, mag(self));
        }

        pub fn normalized(self: *const Self) Self {
            var result = self.*;
            normalize(&result);
            return result;
        }

        pub fn dot(lhs: *const Self, rhs: *const Self) Scalar {
            var sum = scalar.@"0";
            for (0..len) |n| sum = @mulAdd(Scalar, lhs[n], rhs[n], sum);
            return sum;
        }

        pub fn dotInto(result: *Scalar, lhs: *const Self, rhs: *const Self) void {
            result.* = scalar.@"0";
            for (0..len) |n| result.* = @mulAdd(Scalar, lhs[n], rhs[n], result.*);
        }

        pub fn clamp(self: *Self, min: *const Self, max: *const Self) void {
            for (0..len) |n| self[n] = @max(@min(self[n], max[n]), min[n]);
        }

        pub fn translateScale(direction: *Self, translation: *const Self, multiplier: Scalar) void {
            mulAdd(direction, translation, multiplier);
        }

        pub fn rotateDirectionScale(direction: *Self, rotation: *const Self, multiplier: Scalar) void {
            mulAdd(direction, rotation, multiplier);
        }

        pub fn translateDirectionScale(direction: *Self, translation: *const Self, multiplier: Scalar) void {
            mulSub(direction, translation, multiplier);
        }

        pub fn lookAt(result: *Self, position: *const Self, target: *const Self) void {
            result.* = target.*;
            sub(result, position);
            normalize(result);
        }

        pub fn cross(result: *Self, lhs: *const Self, rhs: *const Self) void {
            comptime if (len == 3) {} else @compileError("cross not supported for vector of " ++ len);
            result[0] = lhs[1] * rhs[2] - lhs[2] * rhs[1];
            result[1] = lhs[2] * rhs[0] - lhs[0] * rhs[2];
            result[2] = lhs[0] * rhs[1] - lhs[1] * rhs[0];
        }

        /// Returns angle fomr -pi to pi along plane n.
        /// lhs and rhs should be normalized.
        pub fn angle(lhs: *const Self, rhs: *const Self, n: *const Self) Scalar {
            var c: Self = undefined;
            cross(&c, rhs, lhs); // rhs is further clockwise
            return std.math.atan2(dot(&c, n), dot(lhs, rhs));
        }

        /// returns angle from 0 to pi
        pub fn absAngle(lhs: *const Self, rhs: *const Self) Scalar {
            var c: Self = undefined;
            cross(&c, rhs, lhs);
            return std.math.atan2(mag(&c), dot(lhs, rhs));
        }

        pub fn triAngle(comptime S: comptime_int, tri: [3]*const Self, n: *const Self) Scalar {
            assert(S >= 0);
            assert(S <= 2);
            switch (comptime S) {
                0 => {
                    var lhs = tri[1].*;
                    var rhs = tri[2].*;
                    sub(&lhs, tri[0]);
                    sub(&rhs, tri[0]);
                    normalize(&lhs);
                    normalize(&rhs);
                    return angle(&lhs, &rhs, n);
                },
                1 => {
                    var lhs = tri[2].*;
                    var rhs = tri[0].*;
                    sub(&lhs, tri[1]);
                    sub(&rhs, tri[1]);
                    normalize(&lhs);
                    normalize(&rhs);
                    return angle(&lhs, &rhs, n);
                },
                2 => {
                    var lhs = tri[0].*;
                    var rhs = tri[1].*;
                    sub(&lhs, tri[2]);
                    sub(&rhs, tri[2]);
                    normalize(&lhs);
                    normalize(&rhs);
                    return angle(&lhs, &rhs, n);
                },
                else => unreachable,
            }
        }

        pub fn triAbsAngle(comptime S: comptime_int, tri: [3]*const Self) Scalar {
            assert(S >= 0);
            assert(S <= 2);
            switch (comptime S) {
                0 => {
                    var lhs = tri[1].*;
                    var rhs = tri[2].*;
                    sub(&lhs, tri[0]);
                    sub(&rhs, tri[0]);
                    return absAngle(&lhs, &rhs);
                },
                1 => {
                    var lhs = tri[2].*;
                    var rhs = tri[0].*;
                    sub(&lhs, tri[1]);
                    sub(&rhs, tri[1]);
                    return absAngle(&lhs, &rhs);
                },
                2 => {
                    var lhs = tri[0].*;
                    var rhs = tri[1].*;
                    sub(&lhs, tri[2]);
                    sub(&rhs, tri[2]);
                    return absAngle(&lhs, &rhs);
                },
                else => unreachable,
            }
        }

        pub fn triEdgeOrder(
            comptime S: comptime_int,
            tri: [3]*const Self,
            p: *const Self,
            n: *const Self,
        ) std.math.Order {
            assert(S >= 0);
            assert(S <= 2);
            const a = switch (comptime S) {
                0 => blk: {
                    var edge = tri[1].*;
                    var v = p.*;
                    sub(&edge, tri[0]);
                    sub(&v, tri[0]);
                    break :blk angle(&edge, &v, n);
                },
                1 => blk: {
                    var edge = tri[2].*;
                    var v = p.*;
                    sub(&edge, tri[1]);
                    sub(&edge, tri[1]);
                    break :blk angle(&edge, &v, n);
                },
                2 => blk: {
                    var edge = tri[0].*;
                    var v = p.*;
                    sub(&edge, tri[2]);
                    sub(&edge, tri[2]);
                    break :blk angle(&edge, &v, n);
                },
                else => unreachable,
            };
            if (std.math.approxEqAbs(Scalar, a, scalar.@"0", scalar.eps)) return .eq;
            if (a > 0) return .gt;
            return .lt;
        }

        pub fn triContainsPoint(tri: [3]*const Self, p: *const Self, n: *const Self) bool {
            return triEdgeOrder(0, tri, p, n) == .lt and
                triEdgeOrder(1, tri, p, n) == .lt and
                triEdgeOrder(2, tri, p, n) == .lt;
        }

        /// Performs the Möller–Trumbore intersection algorithm.
        pub fn rayIntersectTri(tri: [3]*const Self, ray_pos: *const Self, ray_dir: *const Self) ?Self {
            var lhs = tri[1].*;
            var rhs = tri[2].*;
            sub(&lhs, tri[0]);
            sub(&rhs, tri[0]);

            var ray_c_rhs: Self = undefined;
            cross(&ray_c_rhs, ray_dir, &rhs);

            const det = dot(&lhs, &ray_c_rhs);
            if (det > -scalar.eps and det < scalar.eps) return null;
            const inv_det = scalar.recip(det);

            var s = ray_pos.*;
            sub(&s, tri[0]);

            const u = inv_det * dot(&s, &ray_c_rhs);
            if ((u < scalar.@"0" and @abs(u) > scalar.eps) or
                (u > 1 and @abs(u - scalar.@"1") > scalar.eps)) return null;

            var s_c_lhs: Self = undefined;
            cross(&s_c_lhs, &s, &lhs);

            const v = inv_det * dot(ray_dir, &s_c_lhs);
            if ((v < 0 and @abs(v) > scalar.eps) or
                (u + v > 1 and @abs(u + v - scalar.@"1") > scalar.eps)) return null;

            const t = inv_det * dot(&rhs, &s_c_lhs);
            if (t > scalar.eps) {
                var result = ray_dir.*;
                scale(&result, t);
                add(&result, ray_pos);
                return result;
            }
            return null;
        }

        pub fn triNormal(result: *Self, tri: [3]*const Self) void {
            var lhs = tri[1].*;
            var rhs = tri[2].*;
            sub(&lhs, tri[0]);
            sub(&rhs, tri[0]);
            cross(result, &lhs, &rhs);
            normalize(result);
        }

        pub fn localCoords(result: *Coords, direction: *const Self, up: *const Self) void {
            const m = mag(up);
            assert(m > 0.9999 and m < 1.0001);

            result.z = direction.*;
            normalize(&result.z);
            scale(&result.z, -1);
            cross(&result.x, &result.z, up);
            normalize(&result.x);
            cross(&result.y, &result.x, &result.z);
        }

        pub fn cameraCoords(result: *Coords, direction: *const Self, up: *const Self) void {
            const m = mag(up);
            assert(m > 0.9999 and m < 1.0001);

            result.z = direction.*;
            normalize(&result.z);
            scale(&result.z, -1);
            cross(&result.x, &result.z, up);
            normalize(&result.x);
            cross(&result.y, &result.x, &result.z);
        }
    };
}

test "vector3" {
    const ns = vectorNT(3, types.Scalar);
    const lhs = ns.Self{ 2, 4, 6 };
    const rhs = ns.Self{ 1, 2, 3 };

    var result = lhs;
    ns.add(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 3, 6, 9 }, ns.sliceConst(&result));
    result = lhs;
    ns.sub(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 2, 3 }, ns.sliceConst(&result));
    result = lhs;
    ns.mul(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 8, 18 }, ns.sliceConst(&result));
    result = lhs;
    ns.div(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 2, 2 }, ns.sliceConst(&result));
    result = lhs;
    ns.mulAdd(&result, &rhs, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 8, 12 }, ns.sliceConst(&result));
    result = lhs;
    ns.mulSub(&result, &rhs, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 0, 0 }, ns.sliceConst(&result));
    result = lhs;
    ns.scale(&result, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 8, 12 }, ns.sliceConst(&result));
    result = lhs;
    ns.scaleRecip(&result, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 2, 3 }, ns.sliceConst(&result));
    result = lhs;
    try std.testing.expect(ns.magSqr(&result) == 56);
    result = ns.Self{ 2, 2, 1 };
    try std.testing.expect(ns.mag(&result) == 3);
    result = ns.Self{ 2, 2, 1 };
    ns.normalize(&result);
    {
        const len = @sqrt(2.0 * 2.0 + 2.0 * 2.0 + 1.0 * 1.0);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 2.0 / len, 2.0 / len, 1.0 / len }, ns.sliceConst(&result));
    }
    try std.testing.expect(ns.dot(&lhs, &rhs) == (2 * 1 + 4 * 2 + 6 * 3));
    {
        var dot: ns.Scalar = undefined;
        ns.dotInto(&dot, &lhs, &rhs);
    }
    ns.cross(&result, &lhs, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &ns.zero, &result);
    ns.cross(&result, &lhs, &.{ 6, 2, 4 });
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 28, -20 }, &result);
    {
        var coords: ns.Coords = undefined;
        ns.localCoords(&coords, &.{ 0, 0, 1 }, &.{ 0, 1, 0 });
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 0, 0 }, &coords.x);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 1, 0 }, &coords.y);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 0, -1 }, &coords.z);
        // ns.cameraCoords(&coords, &.{ 0, 0, 1 }, &.{ 0, 1, 0 });
        // try std.testing.expectEqualSlices(ns.Scalar, &.{ -1, 0, 0 }, &coords.x);
        // try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 1, 0 }, &coords.y);
        // try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 0, -1 }, &coords.z);
    }
}

test "vector3f64" {
    const ns = vectorNT(3, types.Scalar64);
    const lhs = ns.Self{ 2, 4, 6 };
    const rhs = ns.Self{ 1, 2, 3 };

    var result = lhs;
    ns.add(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 3, 6, 9 }, ns.sliceConst(&result));
    result = lhs;
    ns.sub(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 2, 3 }, ns.sliceConst(&result));
    result = lhs;
    ns.mul(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 8, 18 }, ns.sliceConst(&result));
    result = lhs;
    ns.div(&result, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 2, 2, 2 }, ns.sliceConst(&result));
    result = lhs;
    ns.mulAdd(&result, &rhs, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 8, 12 }, ns.sliceConst(&result));
    result = lhs;
    ns.mulSub(&result, &rhs, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 0, 0 }, ns.sliceConst(&result));
    result = lhs;
    ns.scale(&result, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 8, 12 }, ns.sliceConst(&result));
    result = lhs;
    ns.scaleRecip(&result, 2);
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 2, 3 }, ns.sliceConst(&result));
    result = lhs;
    try std.testing.expect(ns.magSqr(&result) == 56);
    result = ns.Self{ 2, 2, 1 };
    try std.testing.expect(ns.mag(&result) == 3);
    result = ns.Self{ 2, 2, 1 };
    ns.normalize(&result);
    {
        const len = @sqrt(2.0 * 2.0 + 2.0 * 2.0 + 1.0 * 1.0);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 2.0 / len, 2.0 / len, 1.0 / len }, ns.sliceConst(&result));
    }
    try std.testing.expect(ns.dot(&lhs, &rhs) == (2 * 1 + 4 * 2 + 6 * 3));
    {
        var dot: ns.Scalar = undefined;
        ns.dotInto(&dot, &lhs, &rhs);
    }
    ns.cross(&result, &lhs, &rhs);
    try std.testing.expectEqualSlices(ns.Scalar, &ns.zero, &result);
    ns.cross(&result, &lhs, &.{ 6, 2, 4 });
    try std.testing.expectEqualSlices(ns.Scalar, &.{ 4, 28, -20 }, &result);
    {
        var coords: ns.Coords = undefined;
        ns.localCoords(&coords, &.{ 0, 0, 1 }, &.{ 0, 1, 0 });
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 0, 0 }, &coords.x);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 1, 0 }, &coords.y);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 0, -1 }, &coords.z);
        // ns.inverseLocalCoordinates(&coords, &.{ 0, 0, 1 }, &.{ 0, 1, 0 });
        // try std.testing.expectEqualSlices(ns.Scalar, &.{ -1, 0, 0 }, &coords.x);
        // try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 1, 0 }, &coords.y);
        // try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 0, -1 }, &coords.z);
    }
}
