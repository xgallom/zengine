//!
//! The zengine math module
//!

pub const batch = @import("math/batch.zig");

pub const types = @import("math/types.zig");
pub usingnamespace types;

pub const matrix = @import("math/matrix.zig");
pub const matrixMxNT = matrix.matrixMxNT;

pub fn matrix3x3T(comptime T: type) type {
    return matrixMxNT(3, 3, T);
}
pub fn matrix4x4T(comptime T: type) type {
    return matrixMxNT(4, 4, T);
}

pub const matrix3x3 = matrix3x3T(types.Scalar);
pub const matrix3x3f64 = matrix3x3T(types.Scalar64);
pub const matrix4x4 = matrix4x4T(types.Scalar);
pub const matrix4x4f64 = matrix4x4T(types.Scalar64);

pub const vector = @import("math/vector.zig");
pub const vectorNT = vector.vectorNT;

pub fn vector2T(comptime T: type) type {
    return vectorNT(2, T);
}
pub fn vector3T(comptime T: type) type {
    return vectorNT(3, T);
}
pub fn vector4T(comptime T: type) type {
    return vectorNT(4, T);
}

pub const vector2 = vectorNT(2, types.Scalar);
pub const vector2f64 = vectorNT(2, types.Scalar64);
pub const vector3 = vectorNT(3, types.Scalar);
pub const vector3f64 = vectorNT(3, types.Scalar64);
pub const vector4 = vectorNT(4, types.Scalar);
pub const vector4f64 = vectorNT(4, types.Scalar64);

const std = @import("std");
test {
    std.testing.refAllDecls(@This());
}
