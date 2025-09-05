//!
//! Generic matrix implementation
//!
//! Matrix is M rows by N columns,
//! Contains pointers to batches of NB sized vectors of T
//!
//! The underlying type is `[M][N]* @Vector(NB, T)`
//!
//! This interface is intended for batching, first you construct
//! the matrix by setting all the pointers to the beginning of the batches,
//! then use increment() to advance and reuse the object for the next iteration
//!
//! Example usage:
//! ```
//! var matrix = Matrix4x4{
//!     &batch_00, &batch_01, &batch_02, &batch_03,
//!     &batch_10, &batch_11, &batch_12, &batch_13,
//!     &batch_20, &batch_21, &batch_22, &batch_23,
//!     &batch_30, &batch_31, &batch_32, &batch_33,
//! };
//!
//! // assumes len is a multiple of batch_len
//! for (0..(len / matrix4x4.batch_len)) {
//!     do_operation(&matrix);
//!     matrix4x4.increment(&matrix);
//! }
//! ```
//!

const std = @import("std");
const assert = std.debug.assert;

const batchNT = @import("scalar.zig").batchNT;
const types = @import("types.zig");
const vectorNBT = @import("vector.zig").vectorNBT;

pub fn matrixMxNBT(comptime M: comptime_int, comptime N: comptime_int, comptime NB: comptime_int, comptime T: type) type {
    return struct {
        pub const Self = types.MatrixMxNBT(M, N, NB, T);
        pub const CSelf = types.CMatrixMxNBT(M, N, NB, T);
        pub const Item = vector.Item;
        pub const CItem = vector.CItem;
        pub const Scalar = scalar.Self;
        pub const rows = M;
        pub const cols = N;
        pub const len = M * N;
        pub const batch_len = scalar.len;

        const vector = vectorNBT(N, NB, T);
        const scalar = batchNT(NB, T);

        /// advances the matrix in address space to next batch,
        /// assumes bounds checking
        pub fn increment(self: *CSelf) void {
            const s = sliceLenConst(self);
            for (0..len) |n| {
                s[n] += 1;
            }
        }

        /// moves the matrix in address space to previous batch,
        /// assumes bounds checking
        pub fn decrement(self: *CSelf) void {
            const s = sliceLenConst(self);
            for (0..len) |n| {
                s[n] -= 1;
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

        /// Y_mn = L_mn + R_mn
        pub fn add(result: *const Self, lhs: *const CSelf, rhs: *const CSelf) void {
            const y = sliceLen(result);
            const l = sliceLenConst(lhs);
            const r = sliceLenConst(rhs);
            for (0..len) |n| {
                y[n].* = l[n].* + r[n].*;
            }
        }

        /// Y_mn = L_mn - R_mn
        pub fn sub(result: *const Self, lhs: *const CSelf, rhs: *const CSelf) void {
            const y = sliceLen(result);
            const l = sliceLenConst(lhs);
            const r = sliceLenConst(rhs);
            for (0..len) |n| {
                y[n].* = l[n].* - r[n].*;
            }
        }

        /// Y_mn = L_mn * R_mn
        pub fn mul(result: *const Self, lhs: *const CSelf, rhs: *const CSelf) void {
            const y = sliceLen(result);
            const l = sliceLenConst(lhs);
            const r = sliceLenConst(rhs);
            for (0..len) |n| {
                y[n].* = l[n].* * r[n].*;
            }
        }

        /// Y_mn = L_mn / R_mn
        pub fn div(result: *const Self, lhs: *const CSelf, rhs: *const CSelf) void {
            const y = sliceLen(result);
            const l = sliceLenConst(lhs);
            const r = sliceLenConst(rhs);
            for (0..len) |n| {
                y[n].* = l[n].* / r[n].*;
            }
        }

        /// Y_mn = L_mx R_xn
        pub fn dot(result: *const Self, lhs: *const CSelf, rhs: *const CSelf) void {
            comptime assert(rows == cols);
            for (0..rows) |y| {
                for (0..cols) |x| {
                    result[y][x].* = scalar.zero;
                    for (0..cols) |n| {
                        result[y][x].* = @mulAdd(Scalar, lhs[y][n].*, rhs[n][x].*, result[y][x].*);
                    }
                }
            }
        }

        /// Y_mn = X_nm,
        /// swapping pointers - does not swap the underlying data
        pub fn transpose(self: *CSelf) void {
            comptime assert(rows == cols);
            for (0..rows) |y| {
                for (0..y) |x| {
                    const tmp = self[y][x];
                    self[y][x] = self[x][y];
                    self[x][y] = tmp;
                }
            }
        }

        /// Y_m = O_mn X_n
        pub fn apply(result: *const vector.Self, operation: *const CSelf, operand: *const vector.CSelf) void {
            for (0..rows) |y| {
                vector.dot(&result[y], &operation[y], operand);
            }
        }

        /// Y_n = X_m O_mn
        pub fn applyRight(result: *const vector.Self, right_side_operation: *const CSelf, operand: *const vector.CSelf) void {
            var operation: CSelf = right_side_operation.*;
            transpose(&operation);
            apply(result, &operation, operand);
        }
    };
}
