//!
//! The zengine cpu buffer implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const Tree = @import("../containers.zig").Tree;
const c = @import("../ext.zig").c;
const math = @import("../math.zig");

const log = std.log.scoped(.gfx_cpu_buffer);

buf: ArrayList = .empty,
vert_count: u32 = 0,

const Self = @This();
pub const ArrayList = std.array_list.Aligned(u8, alignment);
pub const empty: Self = .{};
pub const alignment: std.mem.Alignment = .max(.of(math.Vertex4), .of(math.batch.Batch));

pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
    self.free(gpa);
    self.vert_count = 0;
}

pub inline fn byteLen(self: *const Self) u32 {
    return @intCast(self.buf.items.len);
}

pub inline fn slice(self: *const Self, comptime T: type) []T {
    return std.mem.bytesAsSlice(T, self.buf.items);
}

pub fn ensureUnusedCapacity(self: *Self, gpa: std.mem.Allocator, comptime T: type, count: usize) !void {
    assert(@alignOf(T) <= alignment.toByteUnits());
    try self.buf.ensureUnusedCapacity(gpa, count * @sizeOf(T));
}

pub fn append(
    self: *Self,
    gpa: std.mem.Allocator,
    comptime T: type,
    comptime verts_in_item: u32,
    item: *const T,
) !void {
    try self.buf.appendSlice(gpa, std.mem.asBytes(item));
    self.vert_count += verts_in_item;
}

pub fn appendAssumeCapacity(
    self: *Self,
    comptime T: type,
    comptime verts_in_item: u32,
    item: *const T,
) void {
    self.buf.appendSliceAssumeCapacity(std.mem.asBytes(item));
    self.vert_count += verts_in_item;
}

pub fn appendSlice(
    self: *Self,
    gpa: std.mem.Allocator,
    comptime T: type,
    comptime verts_in_item: u32,
    items: []const T,
) !void {
    try self.buf.appendSlice(gpa, std.mem.sliceAsBytes(items));
    self.vert_count += @intCast(items.len * verts_in_item);
}

pub fn appendSliceAssumeCapacity(
    self: *Self,
    comptime T: type,
    comptime verts_in_item: u32,
    items: []const T,
) void {
    self.buf.appendSliceAssumeCapacity(std.mem.sliceAsBytes(items));
    self.vert_count += @intCast(items.len * verts_in_item);
}

pub fn clear(self: *Self) void {
    self.buf.clearRetainingCapacity();
    self.vert_count = 0;
}

pub fn free(self: *Self, gpa: std.mem.Allocator) void {
    self.buf.clearAndFree(gpa);
    self.vert_count = 0;
}

pub inline fn isNotEmpty(self: *const Self) bool {
    return self.vert_count > 0;
}
