//!
//! The zengine batching math implementation
//!

pub const matrixMxNBT = @import("batch/matrix.zig").matrixMxNBT;
pub const batchNT = @import("batch/scalar.zig").batchNT;
pub const types = @import("batch/types.zig");
pub const Batch = types.Batch;
pub const Batch64 = types.Batch64;
pub const Vector2 = types.Vector2;
pub const CVector2 = types.CVector2;
pub const DenseVector2 = types.DenseVector2;
pub const Vector2f64 = types.Vector2f64;
pub const CVector2f64 = types.CVector2f64;
pub const DenseVector2f64 = types.DenseVector2f64;
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
pub const Vertex = types.Vertex;
pub const CVertex = types.CVertex;
pub const DenseVertex = types.DenseVertex;
pub const Vertex4 = types.Vertex4;
pub const CVertex4 = types.CVertex4;
pub const DenseVertex4 = types.DenseVertex4;
pub const vectorNBT = @import("batch/vector.zig").vectorNBT;
const matrixMxNT = @import("matrix.zig").matrixMxNT;
const vectorNT = @import("vector.zig").vectorNT;
const vertexNT = @import("vertex.zig").vertexNT;

pub const batch_len = types.batch_len;
pub const batch_len64 = types.batch_len64;
pub fn batchN(comptime N: usize) type {
    return batchNT(N, types.Scalar);
}
pub fn batchN64(comptime N: usize) type {
    return batchNT(N, types.Scalar64);
}

pub const batch = batchNT(batch_len, types.Scalar);
pub const batch64 = batchNT(batch_len64, types.Scalar64);

pub fn vector2BT(comptime NB: usize, comptime T: type) type {
    return vectorNBT(2, NB, T);
}
pub fn vector3BT(comptime NB: usize, comptime T: type) type {
    return vectorNBT(3, NB, T);
}
pub fn vector4BT(comptime NB: usize, comptime T: type) type {
    return vectorNBT(4, NB, T);
}

pub const vector2 = vectorNBT(2, batch_len, types.Scalar);
pub const vector2f64 = vectorNBT(2, batch_len64, types.Scalar64);
pub const dense_vector2 = vectorNT(2, types.BatchNT(batch_len, types.Scalar));
pub const dense_vector2f64 = vectorNT(2, types.BatchNT(batch_len64, types.Scalar64));
pub const vector3 = vectorNBT(3, batch_len, types.Scalar);
pub const vector3f64 = vectorNBT(3, batch_len64, types.Scalar64);
pub const dense_vector3 = vectorNT(3, types.BatchNT(batch_len, types.Scalar));
pub const dense_vector3f64 = vectorNT(3, types.BatchNT(batch_len64, types.Scalar64));
pub const vector4 = vectorNBT(4, batch_len, types.Scalar);
pub const vector4f64 = vectorNBT(4, batch_len64, types.Scalar64);
pub const dense_vector4 = vectorNT(4, types.BatchNT(batch_len, types.Scalar));
pub const dense_vector4f64 = vectorNT(4, types.BatchNT(batch_len64, types.Scalar64));

pub fn matrix3x3BT(comptime NB: usize, comptime T: type) type {
    return matrixMxNBT(3, 3, NB, T);
}
pub fn matrix4x4BT(comptime NB: usize, comptime T: type) type {
    return matrixMxNBT(4, 4, NB, T);
}

pub const matrix3x3 = matrixMxNBT(3, 3, batch_len, types.Scalar);
pub const matrix3x3f64 = matrixMxNBT(3, 3, batch_len64, types.Scalar64);
pub const dense_matrix3x3 = matrixMxNT(3, 3, types.BatchNT(batch_len, types.Scalar));
pub const dense_matrix3x3f64 = matrixMxNT(3, 3, types.BatchNT(batch_len, types.Scalar64));
pub const matrix4x4 = matrixMxNBT(4, 4, batch_len, types.Scalar);
pub const matrix4x4f64 = matrixMxNBT(4, 4, batch_len64, types.Scalar64);
pub const dense_matrix4x4 = matrixMxNT(4, 4, types.BatchNT(batch_len, types.Scalar));
pub const dense_matrix4x4f64 = matrixMxNT(4, 4, types.BatchNT(batch_len, types.Scalar64));

pub const dense_vertex = vertexNT(3, types.BatchNT(batch_len, types.Scalar));
pub const dense_vertex4 = vertexNT(4, types.BatchNT(batch_len, types.Scalar));
