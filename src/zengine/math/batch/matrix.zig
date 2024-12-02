const std = @import("std");
const assert = std.debug.assert;

const types = @import("types.zig");
const Batch = types.Batch;
const Vector4 = types.Vector4;
const ConstVector4 = types.ConstVector4;
const Matrix4x4 = types.Matrix4x4;
const ConstMatrix4x4 = types.ConstMatrix4x4;

const vector = @import("vector.zig");
const vector4 = vector.vector4;

pub const matrix4x4 = struct {
    const Self = Matrix4x4;
    const ConstSelf = ConstMatrix4x4;
    const rows = 4;
    const cols = 4;

    pub fn add(result: *const Self, lhs: *const ConstSelf, rhs: *const ConstSelf) void {
        for (0..rows) |y| {
            for (0..cols) |x| {
                result[y][x].* = lhs[y][x].* + rhs[y][x].*;
            }
        }
    }

    pub fn sub(result: *const Self, lhs: *const ConstSelf, rhs: *const ConstSelf) void {
        for (0..rows) |y| {
            for (0..cols) |x| {
                result[y][x].* = lhs[y][x].* - rhs[y][x].*;
            }
        }
    }

    pub fn mul(result: *const Self, lhs: *const ConstSelf, rhs: *const ConstSelf) void {
        for (0..rows) |y| {
            for (0..cols) |x| {
                result[y][x].* = lhs[y][x].* * rhs[y][x].*;
            }
        }
    }

    pub fn div(result: *const Self, lhs: *const ConstSelf, rhs: *const ConstSelf) void {
        for (0..rows) |y| {
            for (0..cols) |x| {
                result[y][x].* = lhs[y][x].* / rhs[y][x].*;
            }
        }
    }

    pub fn dot(result: *const Self, lhs: *const ConstSelf, rhs: *const ConstSelf) void {
        comptime assert(rows == cols);
        for (0..rows) |y| {
            for (0..cols) |x| {
                result[y][x].* = @splat(0);
                for (0..cols) |n| {
                    result[y][x].* += lhs[y][n].* * rhs[n][x].*;
                }
            }
        }
    }

    pub fn apply(result: *const Vector4, operation: *const ConstMatrix4x4, operand: *const ConstVector4) void {
        for (0..rows) |y| {
            vector4.dot(result[y], operation[y], operand);
        }
    }
};
