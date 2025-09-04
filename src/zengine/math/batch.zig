//!
//! The zengine batching math implementation
//!

pub const types = @import("batch/types.zig");

pub const Batch = types.Batch;
pub const Batch64 = types.Batch64;
pub const Vector3 = types.Vector3;
pub const CVector3 = types.CVector3;
pub const DenseVector3 = types.DenseVector3;
pub const Vector3f64 = types.Vector3f64;
pub const CVector3f64 = types.CVector3f64;
pub const DenseVector3f64 = types.DenseVector3f64;
pub const Vector4 = types.Vector4;
pub const CVector4 = types.CVector4;
pub const DenseVector4 = types.DenseVector4;
pub const Vector4f64 = types.Vector4f64;
pub const CVector4f64 = types.CVector4f64;
pub const DenseVector4f64 = types.DenseVector4f64;
pub const Matrix4x4 = types.Matrix4x4;
pub const CMatrix4x4 = types.CMatrix4x4;
pub const DenseMatrix4x4 = types.DenseMatrix4x4;
pub const Matrix4x4f64 = types.Matrix4x4f64;
pub const CMatrix4x4f64 = types.CMatrix4x4f64;
pub const DenseMatrix4x4f64 = types.DenseMatrix4x4f64;

pub const batchNT = @import("batch/scalar.zig").batchNT;

pub fn batchN(comptime N: usize) type {
    return batchNT(N, types.Scalar);
}
pub fn batchN64(comptime N: usize) type {
    return batchNT(N, types.Scalar64);
}

pub const batch = batchNT(types.batch_len, types.Scalar);
pub const batch64 = batchNT(types.batch_len64, types.Scalar64);

pub const vectorNBT = @import("batch/vector.zig").vectorNBT;

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

pub const matrixMxNBT = @import("batch/matrix.zig").matrixMxNBT;

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
