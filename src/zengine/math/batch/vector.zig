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

const vectorNT = @import("../vector.zig").vectorNT;
const batchNT = @import("scalar.zig").batchNT;
const types = @import("types.zig");

pub fn vectorNBT(comptime N: comptime_int, comptime NB: comptime_int, comptime T: type) type {
    return struct {
        pub const Self = types.VectorNBT(N, NB, T);
        pub const CSelf = types.CVectorNBT(N, NB, T);
        pub const Item = types.PrimitiveNT(NB, T);
        pub const CItem = types.CPrimitiveNT(NB, T);
        pub const Scalar = scalar.Self;
        pub const len = N;
        pub const batch_len = scalar.len;

        pub const scalar = batchNT(NB, T);
        pub const dense = vectorNT(N, types.BatchNT(NB, T));

        /// advances the vector in address space to next batch,
        /// assumes bounds checking
        pub fn increment(self: *Self, dims: usize) void {
            assert(dims <= len);
            const s = sliceLen(self);
            for (0..dims) |n| {
                s[n] = @ptrCast(@as([*]Scalar, @ptrCast(s[n])) + 1);
            }
        }

        pub fn cincrement(self: *CSelf, dims: usize) void {
            assert(dims <= len);
            const s = sliceLenConst(self);
            for (0..dims) |n| {
                s[n] = @ptrCast(@as([*]const Scalar, @ptrCast(s[n])) + 1);
            }
        }

        /// moves the vector in address space to previous batch,
        /// assumes bounds checking
        pub fn decrement(self: *Self, dims: usize) void {
            assert(dims <= len);
            const s = sliceLen(self);
            for (0..dims) |n| {
                s[n] = @ptrCast(@as([*]Scalar, @ptrCast(s[n])) - 1);
            }
        }

        pub fn cdecrement(self: *CSelf, dims: usize) void {
            assert(dims <= len);
            const s = sliceLenConst(self);
            for (0..dims) |n| {
                s[n] = @ptrCast(@as([*]const Scalar, @ptrCast(s[n])) - 1);
            }
        }

        pub fn slice(comptime L: usize, self: *Self) []Item {
            comptime assert(L <= len);
            return self[0..L];
        }

        pub fn cslice(comptime L: usize, self: *const Self) []const Item {
            comptime assert(L <= len);
            return self[0..L];
        }

        pub fn sliceConst(comptime L: usize, self: *CSelf) []CItem {
            comptime assert(L <= len);
            return self[0..L];
        }

        pub fn csliceConst(comptime L: usize, self: *const CSelf) []const CItem {
            comptime assert(L <= len);
            return self[0..L];
        }

        pub fn sliceLen(self: *Self) []Item {
            return slice(len, self);
        }

        pub fn csliceLen(self: *const Self) []const Item {
            return slice(len, self);
        }

        pub fn sliceLenConst(self: *CSelf) []CItem {
            return sliceConst(len, self);
        }

        pub fn csliceLenConst(self: *const CSelf) []const CItem {
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

        /// Y = L x R
        pub fn cross(result: *Self, lhs: *const CSelf, rhs: *const CSelf) void {
            if (N == 3) {} else unreachable;
            result[0].* = lhs[1].* * rhs[2].* - lhs[2].* * rhs[1].*;
            result[1].* = lhs[2].* * rhs[0].* - lhs[0].* * rhs[2].*;
            result[2].* = lhs[0].* * rhs[1].* - lhs[1].* * rhs[0].*;
        }

        pub fn iterate(self: *const Self, count: usize, dims: usize) Iterator {
            var result = Iterator{
                .dims = dims,
                .remaining = scalar.batchLen(count),
                .data = self.*,
            };
            decrement(&result.data, dims);
            return result;
        }

        pub const Iterator = struct {
            dims: usize,
            remaining: usize,
            data: Self,

            pub fn next(self: *Iterator) ?*const Self {
                if (self.remaining == 0) return null;
                self.remaining -= 1;
                increment(&self.data, self.dims);
                return &self.data;
            }
        };

        pub const CIterator = struct {
            dims: usize,
            remaining: usize,
            data: CSelf,

            pub fn next(self: *Iterator) ?*const CSelf {
                if (self.remaining == 0) return null;
                self.remaining -= 1;
                increment(&self.data, self.dims);
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
