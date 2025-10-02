//!
//! The zengine string helper functions
//!

const std = @import("std");
const allocators = @import("allocators.zig");

pub const ScalarIterator = std.mem.SplitIterator(u8, .scalar);
const vec_len = std.simd.suggestVectorLength(u8);
const V = if (vec_len) |len| @Vector(len, u8) else u8;

pub inline fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub inline fn splitScalar(str: []const u8, sep: u8) ScalarIterator {
    return std.mem.splitScalar(u8, str, sep);
}

pub inline fn trimRest(iter: *ScalarIterator) []const u8 {
    return trim(iter.rest());
}

pub inline fn trim(str: []const u8) []const u8 {
    return std.mem.trim(u8, str, " \t\n\r");
}

// Duplicate a string slice aligned to 1-byte boundary
pub fn dupe(str: []const u8) ![]const u8 {
    return allocators.string().dupe(u8, str);
}

// Duplicate a string slice aligned as a vector optimal for target platform
// This is used for iterators and searching
pub fn dupeV(str: []const u8) ![]const u8 {
    const ptr = allocators.string().rawAlloc(
        str.len,
        std.mem.Alignment.of(V),
        @returnAddress(),
    ) orelse return std.mem.Allocator.Error.OutOfMemory;
    @memcpy(ptr[0..str.len], str);
    return ptr[0..str.len];
}

// Duplicate a string slice with a terminating 0 aligned to 1-byte boundary
pub fn dupeZ(str: []const u8) ![:0]const u8 {
    return allocators.string().dupeZ(u8, str);
}

// Duplicate a string slice with a terminating 0 aligned as a vector optimal for target platform
// This is used for iterators and searching
pub fn dupeVZ(str: []const u8) ![:0]const u8 {
    const ptr = allocators.string().rawAlloc(
        str.len + 1,
        std.mem.Alignment.of(V),
        @returnAddress(),
    ) orelse return std.mem.Allocator.Error.OutOfMemory;
    @memcpy(ptr[0..str.len], str);
    ptr[str.len] = 0;
    return ptr[0..str.len :0];
}
