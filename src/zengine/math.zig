//!
//! The zengine math module
//!

pub const batch = @import("math/batch.zig");

pub const types = @import("math/types.zig");
pub usingnamespace types;

pub const matrix = @import("math/matrix.zig");
pub const matrixMxNT = matrix.matrixMxNT;

pub fn matrix4x4T(comptime T: type) type {
    return matrixMxNT(4, 4, T);
}

pub const matrix4x4 = matrixMxNT(4, 4, types.Scalar);
pub const matrix4x4f64 = matrixMxNT(4, 4, types.Scalar64);

pub const vector = @import("math/vector.zig");
pub const vectorNT = vector.vectorNT;

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
