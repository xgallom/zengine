//!
//! The zengine string helper functions
//!

const std = @import("std");
const allocators = @import("allocators.zig");

pub const ScalarIterator = std.mem.SplitIterator(u8, .scalar);

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

pub inline fn dupe(str: []const u8) ![]const u8 {
    return allocators.string().dupe(u8, str);
}

pub inline fn dupeZ(str: []const u8) ![:0]const u8 {
    return allocators.string().dupeZ(u8, str);
}
