//!
//! The zengine batching math types
//!
//! These are also available in the top-level math.batch module
//!

const std = @import("std");
const types = @import("../types.zig");
pub const Scalar = types.Scalar;
pub const Scalar64 = types.Scalar64;

/// optimal length of a vector for type f32,
/// defaults to 8 (x64 256, ARM 128 - 1024)
pub const batch_len = std.simd.suggestVectorLength(Scalar) orelse 8;
/// optimal length of a vector for type f64,
/// defaults to 4 (x64 256, ARM 128 - 1024)
pub const batch_len64 = std.simd.suggestVectorLength(Scalar64) orelse 4;

/// batch of N elements of type T
pub fn BatchNT(comptime N: comptime_int, comptime T: type) type {
    return @Vector(N, T);
}

/// mutable pointer to a batch of N elements of type T
pub fn PrimitiveNT(comptime N: comptime_int, comptime T: type) type {
    return [*]BatchNT(N, T);
}
/// const pointer to a batch of N elements of type T
pub fn CPrimitiveNT(comptime N: comptime_int, comptime T: type) type {
    return [*]const BatchNT(N, T);
}

/// underlying type of a vector of N mutable pointers to batches of NB elements of type T
pub fn VectorNBT(comptime N: comptime_int, comptime NB: comptime_int, comptime T: type) type {
    return types.VectorNT(N, PrimitiveNT(NB, T));
}
/// underlying type of a vector of N const pointers to batches of NB elements of type T
pub fn CVectorNBT(comptime N: comptime_int, comptime NB: comptime_int, comptime T: type) type {
    return types.VectorNT(N, CPrimitiveNT(NB, T));
}
/// underlying type of a vector of N batches of NB elements of type T
/// - operations of dense vector are implemented in math.vector
pub fn DenseVectorNBT(comptime N: comptime_int, comptime NB: comptime_int, comptime T: type) type {
    return types.VectorNT(N, BatchNT(NB, T));
}

pub fn Vector2BT(comptime NB: comptime_int, comptime T: type) type {
    return VectorNBT(2, NB, T);
}
pub fn CVector2BT(comptime NB: comptime_int, comptime T: type) type {
    return CVectorNBT(2, NB, T);
}
pub fn DenseVector2BT(comptime NB: comptime_int, comptime T: type) type {
    return DenseVectorNBT(2, NB, T);
}
pub fn Vector3BT(comptime NB: comptime_int, comptime T: type) type {
    return VectorNBT(3, NB, T);
}
pub fn CVector3BT(comptime NB: comptime_int, comptime T: type) type {
    return CVectorNBT(3, NB, T);
}
pub fn DenseVector3BT(comptime NB: comptime_int, comptime T: type) type {
    return DenseVectorNBT(3, NB, T);
}
pub fn Vector4BT(comptime NB: comptime_int, comptime T: type) type {
    return VectorNBT(4, NB, T);
}
pub fn CVector4BT(comptime NB: comptime_int, comptime T: type) type {
    return CVectorNBT(4, NB, T);
}
pub fn DenseVector4BT(comptime NB: comptime_int, comptime T: type) type {
    return DenseVectorNBT(4, NB, T);
}

/// underlying type of a matrix of M rows and N columns of mutable pointers to batches of NB elements of type T
pub fn MatrixMxNBT(comptime M: comptime_int, comptime N: comptime_int, comptime NB: comptime_int, comptime T: type) type {
    return types.MatrixMxNT(M, N, PrimitiveNT(NB, T));
}
/// underlying type of a matrix of M rows and N columns of const pointers to batches of NB elements of type T
pub fn CMatrixMxNBT(comptime M: comptime_int, comptime N: comptime_int, comptime NB: comptime_int, comptime T: type) type {
    return types.MatrixMxNT(M, N, CPrimitiveNT(NB, T));
}

pub fn Matrix4x4BT(comptime NB: comptime_int, comptime T: type) type {
    return MatrixMxNBT(4, 4, NB, T);
}
pub fn CMatrix4x4BT(comptime NB: comptime_int, comptime T: type) type {
    return CMatrixMxNBT(4, 4, NB, T);
}

pub const Batch = BatchNT(batch_len, Scalar);
pub const Batch64 = BatchNT(batch_len64, Scalar64);
pub const Vector3 = VectorNBT(3, batch_len, Scalar);
pub const CVector3 = CVectorNBT(3, batch_len, Scalar);
pub const DenseVector3 = DenseVectorNBT(3, batch_len, Scalar);
pub const Vector3f64 = VectorNBT(3, batch_len64, Scalar64);
pub const CVector3f64 = CVectorNBT(3, batch_len64, Scalar64);
pub const DenseVector3f64 = DenseVectorNBT(3, batch_len64, Scalar64);
pub const Vector4 = VectorNBT(4, batch_len, Scalar);
pub const CVector4 = CVectorNBT(4, batch_len, Scalar);
pub const DenseVector4 = DenseVectorNBT(4, batch_len, Scalar);
pub const Vector4f64 = VectorNBT(4, batch_len64, Scalar64);
pub const CVector4f64 = CVectorNBT(4, batch_len64, Scalar64);
pub const DenseVector4f64 = DenseVectorNBT(4, batch_len64, Scalar64);
pub const Matrix4x4 = MatrixMxNBT(4, 4, batch_len, Scalar);
pub const CMatrix4x4 = CMatrixMxNBT(4, 4, batch_len, Scalar);
pub const Matrix4x4f64 = MatrixMxNBT(4, 4, batch_len64, Scalar64);
pub const CMatrix4x4f64 = CMatrixMxNBT(4, 4, batch_len64, Scalar64);
