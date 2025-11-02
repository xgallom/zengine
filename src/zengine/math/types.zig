//!
//! The zengine math types
//!
//! These are all available also in the top-level math module
//!

const std = @import("std");

pub const Scalar = f32;
pub const Scalar64 = f64;

pub fn VectorNT(comptime N: comptime_int, comptime T: type) type {
    return [N]T;
}
pub fn Vector2T(comptime T: type) type {
    return VectorNT(2, T);
}
pub fn Vector3T(comptime T: type) type {
    return VectorNT(3, T);
}
pub fn Vector4T(comptime T: type) type {
    return VectorNT(4, T);
}

pub fn MatrixMxNT(comptime M: comptime_int, comptime N: comptime_int, comptime T: type) type {
    return [M][N]T;
}
pub fn Matrix3x3T(comptime T: type) type {
    return MatrixMxNT(3, 3, T);
}
pub fn Matrix4x4T(comptime T: type) type {
    return MatrixMxNT(4, 4, T);
}

pub fn CoordsNT(comptime N: comptime_int, comptime T: type) type {
    return struct {
        x: Vector,
        y: Vector,
        z: Vector,

        pub const Self = @This();
        pub const Vector = VectorNT(N, T);
    };
}
pub fn Coords3T(comptime T: type) type {
    return CoordsNT(3, T);
}
pub fn Coords4T(comptime T: type) type {
    return CoordsNT(4, T);
}

pub const Vector2 = VectorNT(2, Scalar);
pub const Vector2f64 = VectorNT(2, Scalar64);
pub const Vector3 = VectorNT(3, Scalar);
pub const Vector3f64 = VectorNT(3, Scalar64);
pub const Vector4 = VectorNT(4, Scalar);
pub const Vector4f64 = VectorNT(4, Scalar64);

pub const Matrix3x3 = MatrixMxNT(3, 3, Scalar);
pub const Matrix3x3f64 = MatrixMxNT(3, 3, Scalar64);
pub const Matrix4x4 = MatrixMxNT(4, 4, Scalar);
pub const Matrix4x4f64 = MatrixMxNT(4, 4, Scalar64);

pub const Coords3 = CoordsNT(3, Scalar);
pub const Coords3f64 = CoordsNT(3, Scalar64);
pub const Coords4 = CoordsNT(4, Scalar);
pub const Coords4f64 = CoordsNT(4, Scalar64);

pub const Point_i32 = Vector2T(i32);
pub const Point_u32 = Vector2T(u32);
pub const Point_f32 = Vector2T(f32);
pub const Point_f64 = Vector2T(f64);

pub const RGBu8 = Vector3T(u8);
pub const RGBf32 = Vector3T(f32);
pub const RGBf64 = Vector3T(f64);

pub const RGBAu8 = Vector4T(u8);
pub const RGBAf32 = Vector4T(f32);
pub const RGBAf64 = Vector4T(f64);

pub const Vertex = [VertexAttr.len]Vector3T(f32);
pub const Vertex4 = [VertexAttr.len]Vector4T(f32);
pub const TexCoord = Vector2T(f32);
pub const Euler = Vector3T(f32);
pub const Quat = Vector4T(f32);

pub const Index = u32;
pub const LineFaceIndex = Vector2T(Index);
pub const FaceIndex = Vector3T(Index);
pub const QuadFaceIndex = Vector4T(Index);

pub const Color = enum(u2) {
    r,
    g,
    b,
    a,
    pub const len = 4;
};

pub const VertexAttr = enum {
    position,
    tex_coord,
    normal,
    tangent,
    binormal,
    pub const len = 5;
};

pub const Axis3 = enum(u2) {
    x,
    y,
    z,
    pub const len = 3;
};
pub const Axis4 = enum(u2) {
    x,
    y,
    z,
    w,
    pub const len = 4;
};

pub const TransformOp = enum {
    translate,
    rotate,
    scale,
    pub const len = 3;
};

pub const TransformOrder = enum {
    srt, // scale, rotate, translate
    str, // scale, translate, rotate
    rst, // rotate, scale, translate
    rts, // rotate, translate, scale
    tsr, // translate, scale, rotate
    trs, // translate, rotate, scale

    pub const default = .srt;

    pub fn transforms(self: TransformOrder) [TransformOp.len]TransformOp {
        return switch (self) {
            .srt => .{ .scale, .rotate, .translate },
            .str => .{ .scale, .translate, .rotate },
            .rst => .{ .rotate, .scale, .translate },
            .rts => .{ .rotate, .translate, .scale },
            .tsr => .{ .translate, .scale, .rotate },
            .trs => .{ .translate, .rotate, .scale },
        };
    }
};

pub const EulerOrder = enum {
    xyz,
    xzy,
    yxz,
    yzx,
    zxy,
    zyx,

    pub const default = .xyz;

    pub fn axes(self: EulerOrder) [Axis3.len]Axis3 {
        return switch (self) {
            .xyz => .{ .x, .y, .z },
            .xzy => .{ .x, .z, .y },
            .yxz => .{ .y, .x, .z },
            .yzx => .{ .y, .z, .x },
            .zxy => .{ .z, .x, .y },
            .zyx => .{ .z, .y, .x },
        };
    }
};
