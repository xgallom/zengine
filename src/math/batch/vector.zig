const types = @import("types.zig");
const Batch = types.Batch;

fn VectorMath(comptime N: usize) type {
    return struct {
        const Self = [N]*Batch;
        const ConstSelf = [N]*const Batch;
        const len = N;

        pub fn add(result: *const Self, lhs: *const ConstSelf, rhs: *const ConstSelf) void {
            for (0..N) |n| {
                result[n].* = lhs[n].* + rhs[n].*;
            }
        }

        pub fn sub(result: *const Self, lhs: *const ConstSelf, rhs: *const ConstSelf) void {
            for (0..N) |n| {
                result[n].* = lhs[n].* - rhs[n].*;
            }
        }

        pub fn mul(result: *const Self, lhs: *const ConstSelf, rhs: *const ConstSelf) void {
            for (0..N) |n| {
                result[n].* = lhs[n].* * rhs[n].*;
            }
        }

        pub fn div(result: *const Self, lhs: *const ConstSelf, rhs: *const ConstSelf) void {
            for (0..N) |n| {
                result[n].* = lhs[n].* / rhs[n].*;
            }
        }

        pub fn scale(result: *const Self, vector: *const ConstSelf, multiplier: *const Batch) void {
            for (0..N) |n| {
                result[n].* = vector[n].* * multiplier;
            }
        }

        pub fn normalize(result: *const Self, vector: *const ConstSelf) void {
            var length: Batch = undefined;
            dot(&length, vector, vector);
            length = @sqrt(length);

            for (0..N) |n| {
                result[n].* = vector[n].* / length;
            }
        }

        pub fn dot(result: *Batch, lhs: *const ConstSelf, rhs: *const ConstSelf) void {
            result.* = @splat(0);
            for (0..N) |n| {
                result.* += lhs[n].* * rhs[n].*;
            }
        }

        pub usingnamespace if (N == 3) struct {
            pub fn cross(result: *Self, lhs: *const ConstSelf, rhs: *const ConstSelf) void {
                result.* = .{
                    lhs[1].* * rhs[2].* - lhs[2].* * rhs[1].*,
                    -lhs[0].* * rhs[2].* + lhs[2].* * rhs[0].*,
                    lhs[0].* * rhs[1].* - lhs[1].* * rhs[0].*,
                };
            }
        } else struct {};
    };
}

pub const vector3 = VectorMath(3);
pub const vector4 = VectorMath(4);
