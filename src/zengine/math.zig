//!
//! The zengine math module
//!

const std = @import("std");

pub const batch = @import("math/batch.zig");
pub const matrixMxNT = @import("math/matrix.zig").matrixMxNT;
pub const paramT = @import("math/param.zig").paramT;
pub const quatT = @import("math/quat.zig").quatT;
pub const IntMask = @import("math/scalar.zig").IntMask;
pub const scalarT = @import("math/scalar.zig").scalarT;
const types = @import("math/types.zig");
pub const Scalar = types.Scalar;
pub const Scalar64 = types.Scalar64;
pub const Param = types.Param;
pub const Param64 = types.Param64;
pub const Vector2 = types.Vector2;
pub const Vector2f64 = types.Vector2f64;
pub const Vector2i32 = types.Vector2i32;
pub const Vector2u32 = types.Vector2u32;
pub const Vector3 = types.Vector3;
pub const Vector3f64 = types.Vector3f64;
pub const Vector3i32 = types.Vector3i32;
pub const Vector3u32 = types.Vector3u32;
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
pub const Point_i32 = types.Point_i32;
pub const Point_u32 = types.Point_u32;
pub const Point_f32 = types.Point_f32;
pub const Point_f64 = types.Point_f64;
pub const RGBu8 = types.RGBu8;
pub const RGBf16 = types.RGBf16;
pub const RGBf32 = types.RGBf32;
pub const RGBf64 = types.RGBf64;
pub const RGBAu8 = types.RGBAu8;
pub const RGBAf16 = types.RGBAf16;
pub const RGBAf32 = types.RGBAf32;
pub const RGBAf64 = types.RGBAf64;
pub const Vertex = types.Vertex;
pub const Vertex4 = types.Vertex4;
pub const TexCoord = types.TexCoord;
pub const Euler = types.Euler;
pub const Quat = types.Quat;
pub const Index = types.Index;
pub const LineFaceIndex = types.LineFaceIndex;
pub const FaceIndex = types.FaceIndex;
pub const QuadFaceIndex = types.QuadFaceIndex;
pub const Ease = types.Ease;
pub const RGB = types.RGB;
pub const RGBA = types.RGBA;
pub const VertexAttr = types.VertexAttr;
pub const Axis3 = types.Axis3;
pub const Axis4 = types.Axis4;
pub const TransformOp = types.TransformOp;
pub const TransformOrder = types.TransformOrder;
pub const EulerOrder = types.EulerOrder;
pub const vectorNT = @import("math/vector.zig").vectorNT;
pub const vertexNT = @import("math/vertex.zig").vertexNT;

pub fn vector2T(comptime T: type) type {
    return vectorNT(2, T);
}
pub fn vector3T(comptime T: type) type {
    return vectorNT(3, T);
}
pub fn vector4T(comptime T: type) type {
    return vectorNT(4, T);
}

pub fn matrix3x3T(comptime T: type) type {
    return matrixMxNT(3, 3, T);
}
pub fn matrix4x4T(comptime T: type) type {
    return matrixMxNT(4, 4, T);
}

pub const scalar = scalarT(types.Scalar);
pub const scalar64 = scalarT(types.Scalar64);

pub const param = paramT(types.Scalar);
pub const param64 = paramT(types.Scalar64);
pub const binom = paramT(comptime_int).binom;
pub const binoms = paramT(comptime_int).binoms;

pub const vector2 = vectorNT(2, types.Scalar);
pub const vector2f64 = vectorNT(2, types.Scalar64);
pub const vector2i32 = vectorNT(2, i32);
pub const vector2u32 = vectorNT(2, u32);
pub const vector3 = vectorNT(3, types.Scalar);
pub const vector3f64 = vectorNT(3, types.Scalar64);
pub const vector3i32 = vectorNT(3, i32);
pub const vector3u32 = vectorNT(3, u32);
pub const vector4 = vectorNT(4, types.Scalar);
pub const vector4f64 = vectorNT(4, types.Scalar64);

pub const matrix3x3 = matrixMxNT(3, 3, types.Scalar);
pub const matrix3x3f64 = matrixMxNT(3, 3, types.Scalar64);
pub const matrix4x4 = matrixMxNT(4, 4, types.Scalar);
pub const matrix4x4f64 = matrixMxNT(4, 4, types.Scalar64);

pub const point_i32 = vector2T(i32);
pub const point_u32 = vector2T(u32);
pub const point_f32 = vector2T(f32);
pub const point_f64 = vector2T(f64);

pub const rgb_u8 = vector3T(u8);
pub const rgb_f32 = vector3T(f32);
pub const rgb_f64 = vector3T(f64);

pub const rgba_u8 = vector4T(u8);
pub const rgba_f32 = vector4T(f32);
pub const rgba_f64 = vector4T(f64);

pub const vertex = vertexNT(3, f32);
pub const vertex4 = vertexNT(4, f32);
pub const tex_coord = vector2T(f32);
pub const euler = vector3T(f32);
pub const quat = quatT(f32);

pub const index = scalarT(Index);
pub const line_face_index = vector2T(Index);
pub const face_index = vector3T(Index);
pub const quad_face_index = vector4T(Index);

pub const invalid_index = std.math.maxInt(Index);

pub fn percent(x: anytype) @TypeOf(x) {
    return x * 100;
}

pub fn elemSize(comptime T: type) comptime_int {
    return @sizeOf(Elem(T));
}

pub fn elemLen(comptime T: type) comptime_int {
    return switch (@typeInfo(T)) {
        .int, .float => 1,
        inline .array, .vector => |type_info| type_info.len * elemLen(type_info.child),
        else => @compileError("Expected int, float, array or vector type, found '" ++ @typeName(T) ++ "'"),
    };
}

pub fn Elem(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .int, .float, .comptime_int, .comptime_float => T,
        inline .array, .vector => |type_info| Elem(type_info.child),
        else => @compileError("Expected int, float, array or vector type, found '" ++ @typeName(T) ++ "'"),
    };
}

test {
    std.testing.refAllDecls(@This());
}
