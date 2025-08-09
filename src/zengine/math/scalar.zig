//!
//! The zengine batching math scalar helper implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const types = @import("types.zig");

pub fn scalarT(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .float, .comptime_float => struct {
            pub const Self = T;
            pub const Scalar = T;
            pub const len = 1;

            pub const zero: Self = 0;
            pub const one: Self = 1;
            pub const neg_one: Self = -1;

            pub fn init(value: Scalar) Self {
                return value;
            }
        },
        .vector => switch (@typeInfo(@typeInfo(T).Vector.child)) {
            .float, .comptime_float => struct {
                pub const Self = T;
                pub const Scalar = @typeInfo(T).Vector.child;
                pub const len = @typeInfo(T).Vector.len;

                pub const zero: Self = @splat(0);
                pub const one: Self = @splat(1);
                pub const neg_one: Self = @splat(-1);

                pub fn init(value: Scalar) Self {
                    return @splat(value);
                }

                /// computes the number of vectors required to store elem_len values
                // this reduces to binary arithmetic in release mode for power of two-sized batches
                pub fn batch_len(elem_len: usize) usize {
                    var result = batch_index(elem_len);
                    if (batch_offset(elem_len) != 0) result += 1;
                    return result;
                }

                /// computes position of the element in an array of vectors
                // this reduces to binary arithmetic in release mode for power of two-sized batches
                pub fn batch_index(elem_index: usize) usize {
                    return elem_index / len;
                }

                /// computes an offset into the vector on which the element is located
                // this reduces to binary arithmetic in release mode for power of two-sized batches
                pub fn batch_offset(elem_index: usize) usize {
                    return elem_index % len;
                }
            },
            else => @compileError("Unsupported vector scalar type " ++ @typeName(@typeInfo(T).Vector.child)),
        },
        else => @compileError("Unsupported scalar type " ++ @typeName(T)),
    };
}
