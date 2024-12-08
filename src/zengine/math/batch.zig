//!
//! The zengine batching math implementation
//!

pub const types = @import("batch/types.zig");
pub usingnamespace types;

pub const scalar = @import("batch/scalar.zig");
pub const batchNT = scalar.batchNT;

pub fn batchN(comptime N: usize) type {
    return batchNT(N, types.Scalar);
}
pub fn batchN64(comptime N: usize) type {
    return batchNT(N, types.Scalar64);
}

pub const batch = batchNT(types.batch_len, types.Scalar);
pub const batch64 = batchNT(types.batch_len64, types.Scalar64);

pub const vector = @import("batch/vector.zig");
pub const vectorNBT = vector.vectorNBT;

pub fn vector2BT(comptime NB: usize, comptime T: type) type {
    return vectorNBT(2, NB, T);
}
pub fn vector3BT(comptime NB: usize, comptime T: type) type {
    return vectorNBT(3, NB, T);
}
pub fn vector4BT(comptime NB: usize, comptime T: type) type {
    return vectorNBT(4, NB, T);
}

pub const vector2 = vectorNBT(2, types.batch_len, types.Scalar);
pub const vector2f64 = vectorNBT(2, types.batch_len64, types.Scalar64);
pub const vector3 = vectorNBT(3, types.batch_len, types.Scalar);
pub const vector3f64 = vectorNBT(3, types.batch_len64, types.Scalar64);
pub const vector4 = vectorNBT(4, types.batch_len, types.Scalar);
pub const vector4f64 = vectorNBT(4, types.batch_len64, types.Scalar64);

pub const matrix = @import("batch/matrix.zig");
pub const matrixMxNBT = matrix.matrixMxNBT;

pub fn matrix2x2BT(comptime NB: usize, comptime T: type) type {
    return matrixMxNBT(2, 2, NB, T);
}
pub fn matrix3x3BT(comptime NB: usize, comptime T: type) type {
    return matrixMxNBT(3, 3, NB, T);
}
pub fn matrix4x4BT(comptime NB: usize, comptime T: type) type {
    return matrixMxNBT(4, 4, NB, T);
}

pub const matrix2x2 = matrixMxNBT(2, 2, types.batch_len, types.Scalar);
pub const matrix2x2f64 = matrixMxNBT(2, 2, types.batch_len64, types.Scalar64);
pub const matrix3x3 = matrixMxNBT(3, 3, types.batch_len, types.Scalar);
pub const matrix3x3f64 = matrixMxNBT(3, 3, types.batch_len64, types.Scalar64);
pub const matrix4x4 = matrixMxNBT(4, 4, types.batch_len, types.Scalar);
pub const matrix4x4f64 = matrixMxNBT(4, 4, types.batch_len64, types.Scalar64);
