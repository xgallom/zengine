//!
//! The zengine string helper functions
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("allocators.zig");

pub const ScalarIterator = std.mem.SplitIterator(u8, .scalar);
const vec_len = std.simd.suggestVectorLength(u8);
const V = if (vec_len) |len| @Vector(len, u8) else u8;

pub fn commonStart(label: []const u8, needle: []const u8) usize {
    const end = @min(label.len, needle.len);
    for (0..end, label[0..end], needle[0..end]) |n, a, b| {
        if (a != b) return n;
    }
    return end;
}

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

pub fn join(strs: []const []const u8) ![]const u8 {
    var len: usize = 0;
    for (strs) |str| len += str.len;
    const buf = try allocators.string().alloc(u8, len);
    var off: usize = 0;
    for (strs) |str| {
        @memcpy(buf[off .. off + str.len], str);
        off += str.len;
    }
    assert(len == off);
    return buf;
}

pub fn joinZ(strs: []const []const u8) ![:0]const u8 {
    var len: usize = 0;
    for (strs) |str| len += str.len;
    const buf = try allocators.string().alloc(u8, len + 1);
    var off: usize = 0;
    for (strs) |str| {
        @memcpy(buf[off .. off + str.len], str);
        off += str.len;
    }
    buf[off] = 0;
    assert(len == off);
    return buf[0..off :0];
}

// Duplicate a string slice aligned to 1-byte boundary
// Allocates in default string arena
pub fn dupe(str: []const u8) ![]u8 {
    return allocators.string().dupe(u8, str);
}

// Duplicate a string slice aligned as a vector optimal for target platform
// This is used for iterators and searching
// Allocates in default string arena
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
// Allocates in default string arena
pub fn dupeZ(str: []const u8) ![:0]u8 {
    return allocators.string().dupeZ(u8, str);
}

// Duplicate a string slice with a terminating 0 aligned as a vector optimal for target platform
// This is used for iterators and searching
// Allocates in default string arena
pub fn dupeVZ(str: []const u8) ![:0]u8 {
    const ptr = allocators.string().rawAlloc(
        str.len + 1,
        std.mem.Alignment.of(V),
        @returnAddress(),
    ) orelse return std.mem.Allocator.Error.OutOfMemory;
    @memcpy(ptr[0..str.len], str);
    ptr[str.len] = 0;
    return ptr[0..str.len :0];
}

// Frees a string allocated with dupe
// Since this is backed by an arena, only last allocated string will be actually freed
pub fn free(str: anytype) void {
    allocators.string().free(str);
}
