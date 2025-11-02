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

        pub const zero = splat(scalar.zero);
        pub const one = splat(scalar.one);
        pub const neg_one = splat(scalar.neg_one);
        pub const ntr_zero = makeNonTransformable(vectorNT(len - 1, T).zero);
        pub const ntr_fwd = makeNonTransformableFwd(scalar.one);
        pub const tr_zero = makeTransformable(vectorNT(len - 1, T).zero);
        pub const tr_fwd = makeTransformableFwd(scalar.one);

        pub fn makeNonTransformable(value: types.VectorNT(len - 1, T)) Self {
            return value ++ .{scalar.zero};
        }

        pub fn makeTransformable(value: types.VectorNT(len - 1, T)) Self {
            return value ++ .{scalar.one};
        }

        fn makeNonTransformableFwd(fwd: Scalar) Self {
            comptime if (len == 4) {} else @compileError("forward not supported for vector of " ++ len);
            var result = zero;
            result[2] = -fwd;
            return result;
        }

        fn makeTransformableFwd(fwd: Scalar) Self {
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
            scale(self, scalar.neg_one);
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
                const recip = scalar.one / multiplier;
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
            const vector_length = scalar.one / mag(self);
            for (0..len) |n| self[n] *= vector_length;
        }

        pub fn normalized(self: *const Self) Self {
            var result = self.*;
            normalize(&result);
            return result;
        }

        pub fn dot(lhs: *const Self, rhs: *const Self) Scalar {
            var sum = scalar.zero;
            for (0..len) |n| sum = @mulAdd(Scalar, lhs[n], rhs[n], sum);
            return sum;
        }

        pub fn dotInto(result: *Scalar, lhs: *const Self, rhs: *const Self) void {
            result.* = scalar.zero;
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

        pub fn angle(lhs: *const Self, rhs: *const Self) Scalar {
            return std.math.acos(std.math.clamp(
                dot(lhs, rhs) / (mag(lhs) * mag(rhs)),
                scalar.neg_one,
                scalar.one,
            ));
        }

        pub fn cross(result: *Self, lhs: *const Self, rhs: *const Self) void {
            comptime if (len == 3) {} else @compileError("cross not supported for vector of " ++ len);
            result[0] = lhs[1] * rhs[2] - lhs[2] * rhs[1];
            result[1] = lhs[2] * rhs[0] - lhs[0] * rhs[2];
            result[2] = lhs[0] * rhs[1] - lhs[1] * rhs[0];
        }

        pub fn localCoords(result: *Coords, direction: *const Self, up: *const Self) void {
            assert(mag(up) <= 1.001);

            result.z = direction.*;
            normalize(&result.z);
            scale(&result.z, -1);
            cross(&result.x, &result.z, up);
            normalize(&result.x);
            cross(&result.y, &result.x, &result.z);
        }

        pub fn cameraCoords(result: *Coords, direction: *const Self, up: *const Self) void {
            assert(mag(up) <= 1.001);

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
    try std.testing.expect(ns.squareLength(&result) == 56);
    result = ns.Self{ 2, 2, 1 };
    try std.testing.expect(ns.length(&result) == 3);
    result = ns.Self{ 2, 2, 1 };
    ns.normalize(&result);
    {
        const len = @sqrt(2.0 * 2.0 + 2.0 * 2.0 + 1.0 * 1.0);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 2.0 / len, 2.0 / len, 1.0 / len }, ns.sliceConst(&result));
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
    try std.testing.expect(ns.squareLength(&result) == 56);
    result = ns.Self{ 2, 2, 1 };
    try std.testing.expect(ns.length(&result) == 3);
    result = ns.Self{ 2, 2, 1 };
    ns.normalize(&result);
    {
        const len = @sqrt(2.0 * 2.0 + 2.0 * 2.0 + 1.0 * 1.0);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 2.0 / len, 2.0 / len, 1.0 / len }, ns.sliceConst(&result));
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
        var coords: ns.Coords = undefined;
        ns.localCoordinates(&coords, &.{ 0, 0, 1 }, &.{ 0, 1, 0 });
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 1, 0, 0 }, &coords.x);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 1, 0 }, &coords.y);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 0, 1 }, &coords.z);
        ns.inverseLocalCoordinates(&coords, &.{ 0, 0, 1 }, &.{ 0, 1, 0 });
        try std.testing.expectEqualSlices(ns.Scalar, &.{ -1, 0, 0 }, &coords.x);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 1, 0 }, &coords.y);
        try std.testing.expectEqualSlices(ns.Scalar, &.{ 0, 0, -1 }, &coords.z);
    }
}
