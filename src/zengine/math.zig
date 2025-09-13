//!
//! The zengine math module
//!

const std = @import("std");

pub const batch = @import("math/batch.zig");
pub const matrixMxNT = @import("math/matrix.zig").matrixMxNT;
pub const quatT = @import("math/quat.zig").quatT;
const types = @import("math/types.zig");
pub const Scalar = types.Scalar;
pub const Scalar64 = types.Scalar64;
pub const Vector2 = types.Vector2;
pub const Vector2f64 = types.Vector2f64;
pub const Vector3 = types.Vector3;
pub const Vector3f64 = types.Vector3f64;
pub const Vector4 = types.Vector4;
pub const Vector4f64 = types.Vector4f64;
pub const Matrix3x3 = types.Matrix3x3;
pub const Matrix3x3f64 = types.Matrix3x3f64;
pub const Matrix4x4 = types.Matrix4x4;
pub const Matrix4x4f64 = types.Matrix4x4f64;
pub const Coords3 = types.Coords3;
pub const Coords3f64 = types.Coords3f64;
pub const Coords4 = types.Coords4;
pub const Coords4f64 = types.Coords4f64;
pub const Vertex = types.Vertex;
pub const Position = types.Position;
pub const Displacement = types.Displacement;
pub const Euler = types.Euler;
pub const Quat = types.Quat;
pub const Index = types.Index;
pub const FaceIndex = types.FaceIndex;
pub const LineFaceIndex = types.LineFaceIndex;
pub const Axis3 = types.Axis3;
pub const Axis4 = types.Axis4;
pub const EulerOrder = types.EulerOrder;
pub const vectorNT = @import("math/vector.zig").vectorNT;

pub fn matrix3x3T(comptime T: type) type {
    return matrixMxNT(3, 3, T);
}
pub fn matrix4x4T(comptime T: type) type {
    return matrixMxNT(4, 4, T);
}

pub const matrix3x3 = matrixMxNT(3, 3, types.Scalar);
pub const matrix3x3f64 = matrixMxNT(3, 3, types.Scalar64);
pub const matrix4x4 = matrixMxNT(4, 4, types.Scalar);
pub const matrix4x4f64 = matrixMxNT(4, 4, types.Scalar64);

pub const quat = quatT(types.Scalar);

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

pub fn percent(x: anytype) @TypeOf(x) {
    return x * 100;
}

test {
    std.testing.refAllDecls(@This());
}
