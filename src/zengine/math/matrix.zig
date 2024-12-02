const std = @import("std");
const assert = std.debug.assert;

const types = @import("types.zig");
const Scalar = types.Scalar;
const Vector3 = types.Vector3;
const Matrix4x4 = types.Matrix4x4;

const vector = @import("vector.zig");
const vector3 = vector.vector3;

pub const matrix4x4 = struct {
    const Self = Matrix4x4;
    const rows = 4;
    const cols = 4;

    pub fn slice(self: *Self) []f32 {
        return @as(*[16]f32, @alignCast(@ptrCast(self)))[0..16];
    }

    pub fn perspective_fov(result: *Self, field_of_view: Scalar, aspect_ratio: Scalar, near_plane: Scalar, far_plane: Scalar) void {
        const f = 1.0 / @tan(field_of_view * 0.5);

        result.* = .{
            .{ f / aspect_ratio, 0, 0, 0 },
            .{ 0, f, 0, 0 },
            .{ 0, 0, far_plane / (near_plane - far_plane), -1 },
            .{ 0, 0, (near_plane * far_plane) / (near_plane - far_plane), 0 },
        };
    }

    pub fn camera(result: *Self, position: *const Vector3, direction: *const Vector3, up: *const Vector3) void {
        var coordinates: vector3.Coordinates = undefined;
        vector3.local_coordinates(&coordinates, direction, up);

        const x = &coordinates.right;
        const y = &coordinates.up;
        const z = &coordinates.front;

        result.* = .{
            .{ x[0], y[0], z[0], 0 },
            .{ x[1], y[1], z[1], 0 },
            .{ x[2], y[2], z[2], 0 },
            .{ -vector3.dot(x, position), -vector3.dot(y, position), -vector3.dot(z, position), 1 },
        };
    }

    pub fn look_at(result: *Self, position: *const Vector3, target: *const Vector3, up: *const Vector3) void {
        var direction = target.*;
        vector3.sub(&direction, position);
        vector3.normalize(&direction);
        camera(result, position, &direction, up);
    }

    pub fn multiply(result: *Self, lhs: *const Self, rhs: *const Self) void {
        comptime assert(rows == cols);

        for (0..rows) |y| {
            for (0..cols) |x| {
                result[y][x] = blk: {
                    var sum: Scalar = 0;
                    for (0..cols) |n| {
                        sum += lhs[y][n] * rhs[n][x];
                    }
                    break :blk sum;
                };
            }
        }
    }
};
