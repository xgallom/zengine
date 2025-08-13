//!
//! Generic vector implementation
//!
//! Vector is N columns,
//! Contains pointers to batches of NB sized vectors of T
//!
//! The underlying type is `[N]* @Vector(NB, T)`
//!
//! This interface is intended for batching, first you construct
//! the matrix by setting all the pointers to the beginning of the batches,
//! then use increment() to advance and reuse the object for the next iteration
//!
//! Example usage:
//! ```
//! const vector = Vector3{ &batch_x, &batch_y, &batch_z };
//!
//! var iterator = vector3.iterate(&vector, len);
//! for (iterator.next()) |v| {
//!     do_operation(&v);
//! }
//! ```
//!

const std = @import("std");
const assert = std.debug.assert;

const types = @import("types.zig");
const batchNT = @import("scalar.zig").batchNT;
const vectorNT = @import("../vector.zig").vectorNT;

pub fn vectorNBT(comptime N: usize, comptime NB: usize, comptime T: type) type {
    return struct {
        pub const Self = types.VectorNBT(N, NB, T);
        pub const CSelf = types.CVectorNBT(N, NB, T);
        pub const Item = types.PrimitiveNT(NB, T);
        pub const CItem = types.CPrimitiveNT(NB, T);
        pub const Scalar = scalar.Self;
        pub const len = N;
        pub const batch_len = scalar.len;

        const scalar = batchNT(NB, T);
        pub const dense = vectorNT(N, types.BatchNT(NB, T));

        /// advances the vector in address space to next batch,
        /// assumes bounds checking
        pub fn increment(self: *CSelf) void {
            const s = sliceLenConst(self);
            for (0..len) |n| {
                s[n] += 1;
            }
        }

        /// moves the vector in address space to previous batch,
        /// assumes bounds checking
        pub fn decrement(self: *CSelf) void {
            const s = sliceLenConst(self);
            for (0..len) |n| {
                s[n] += 1;
            }
        }

        pub fn slice(comptime L: usize, self: *const Self) []Item {
            comptime assert(L <= len);
            return self[0..L];
        }

        pub fn sliceConst(comptime L: usize, self: *const CSelf) []CItem {
            comptime assert(L <= len);
            return self[0..L];
        }

        pub fn sliceLen(self: *const Self) []Item {
            return slice(len, self);
        }

        pub fn sliceLenConst(self: *const CSelf) []CItem {
            return sliceConst(len, self);
        }

        /// Y_n = L_n + R_n
        pub fn add(result: *const Self, lhs: *const CSelf, rhs: *const CSelf) void {
            for (0..len) |n| {
                result[n].* = lhs[n].* + rhs[n].*;
            }
        }

        /// Y_n = L_n - R_n
        pub fn sub(result: *const Self, lhs: *const CSelf, rhs: *const CSelf) void {
            for (0..len) |n| {
                result[n].* = lhs[n].* - rhs[n].*;
            }
        }

        /// Y_n = L_n * R_n
        pub fn mul(result: *const Self, lhs: *const CSelf, rhs: *const CSelf) void {
            for (0..len) |n| {
                result[n].* = lhs[n].* * rhs[n].*;
            }
        }

        /// Y_n = L_n / R_n
        pub fn div(result: *const Self, lhs: *const CSelf, rhs: *const CSelf) void {
            for (0..len) |n| {
                result[n].* = lhs[n].* / rhs[n].*;
            }
        }

        /// Y_n = L_n * R_n + C_n
        pub fn mulAdd(result: *const Self, lhs: *const CSelf, rhs: *const CSelf, constant: *const CSelf) void {
            for (0..len) |n| {
                result[n].* = @mulAdd(Scalar, lhs[n].*, rhs[n].*, constant[n].*);
            }
        }

        /// Y_n = X_n * C
        pub fn scale(result: *const Self, vector: *const CSelf, multiplier: CItem) void {
            for (0..len) |n| {
                result[n].* = vector[n].* * multiplier.*;
            }
        }

        /// Y_n = X_n * (1 / C)
        pub fn scaleRecip(result: *const Self, vector: *const CSelf, multiplier: CItem) void {
            const recip = scalar.one / multiplier.*;
            for (0..len) |n| {
                result[n].* = vector[n].* * recip;
            }
        }

        /// Y_n = X_n / |X|
        pub fn normalize(result: *const Self, vector: *const CSelf) void {
            var length: Scalar = undefined;
            dot(&length, vector, vector);
            length = @sqrt(length);

            for (0..len) |n| {
                result[n].* = vector[n].* / length;
            }
        }

        /// Y = L . R
        pub fn dot(result: Item, lhs: *const CSelf, rhs: *const CSelf) void {
            result.* = scalar.zero;
            for (0..len) |n| {
                result.* = @mulAdd(Scalar, lhs[n].*, rhs[n].*, result.*);
            }
        }

        pub usingnamespace if (N == 3) struct {
            /// Y = L x R
            pub fn cross(result: *Self, lhs: *const CSelf, rhs: *const CSelf) void {
                result[0].* = lhs[1].* * rhs[2].* - lhs[2].* * rhs[1].*;
                result[1].* = lhs[2].* * rhs[0].* - lhs[0].* * rhs[2].*;
                result[2].* = lhs[0].* * rhs[1].* - lhs[1].* * rhs[0].*;
            }
        } else struct {};

        pub fn iterate(self: *Self, count: usize) Iterator {
            var result = Iterator{
                .data = self.*,
                .remaining = scalar.batch_len(count),
            };
            decrement(&result.data);
            return result;
        }

        pub const Iterator = struct {
            data: Self,
            remaining: usize,

            pub fn next(self: *Iterator) ?*const Self {
                if (self.remaining == 0) return null;
                self.remaining -= 1;
                increment(&self.data);
                return &self.data;
            }
        };

        pub const CIterator = struct {
            data: CSelf,
            remaining: usize,

            pub fn next(self: *Iterator) ?*const CSelf {
                if (self.remaining == 0) return null;
                self.remaining -= 1;
                increment(&self.data);
                return &self.data;
            }
        };

        pub fn fromDense(dense_vector: types.DenseVectorNBT(N, NB, T)) Self {
            var result: Self = undefined;
            for (0..len) |n| {
                result[n] = &dense_vector[n];
            }
            return result;
        }
    };
}
