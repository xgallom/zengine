//!
//! The zengine math types
//!
//! These are all available also in the top-level math module
//!

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

pub const Vector2 = Vector2T(Scalar);
pub const Vector2f64 = Vector2T(Scalar64);
pub const Vector3 = Vector3T(Scalar);
pub const Vector3f64 = Vector3T(Scalar64);
pub const Vector4 = Vector4T(Scalar);
pub const Vector4f64 = Vector4T(Scalar64);

pub const Matrix3x3 = Matrix3x3T(Scalar);
pub const Matrix3x3f64 = Matrix3x3T(Scalar64);
pub const Matrix4x4 = Matrix4x4T(Scalar);
pub const Matrix4x4f64 = Matrix4x4T(Scalar64);

pub const Coords3 = Coords3T(Scalar);
pub const Coords3f64 = Coords3T(Scalar64);
pub const Coords4 = Coords4T(Scalar);
pub const Coords4f64 = Coords4T(Scalar64);

pub const Vertex = Vector3;
pub const Position = Vector4;
pub const Displacement = Vector4;
pub const Euler = Vector3;
pub const Quaternion = Vector4;
pub const Index = u32;
pub const FaceIndex = Vector3T(Index);
pub const LineFaceIndex = Vector2T(Index);

pub const Axis3 = enum {
    x,
    y,
    z,
    pub const len = 3;
};
pub const Axis4 = enum {
    x,
    y,
    z,
    w,
    pub const len = 4;
};

pub const EulerOrder = enum {
    xyz,
    xzy,
    yxz,
    yzx,
    zxy,
    zyx,

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
