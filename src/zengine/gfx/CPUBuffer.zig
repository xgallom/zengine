//!
//! The zengine cpu buffer implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const math = @import("../math.zig");
const Tree = @import("../containers.zig").Tree;

const log = std.log.scoped(.gfx_gpu_buffer);

buf: ArrayList = .empty,

const Self = @This();
pub const ArrayList = std.array_list.Aligned(u8, alignment);
pub const State = enum { empty, valid };
pub const StateFlags = std.EnumSet(State);
pub const empty: Self = .{};
pub const alignment: std.mem.Alignment = .max(.of(math.Vertex4), .of(math.batch.Batch));

pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
    self.free(gpa);
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

pub fn append(self: *Self, gpa: std.mem.Allocator, comptime T: type, items: []const T) !void {
    return self.buf.appendSlice(gpa, std.mem.sliceAsBytes(items));
}

pub fn appendAssumeCapacity(self: *Self, comptime T: type, items: []const T) void {
    return self.buf.appendSliceAssumeCapacity(std.mem.sliceAsBytes(items));
}

pub fn appendSlice(self: *Self, gpa: std.mem.Allocator, comptime T: type, items_all: []const []const T) !void {
    for (items_all) |items| try self.append(gpa, T, items);
}

pub fn appendSliceAssumeCapacity(self: *Self, comptime T: type, items_all: []const []const T) void {
    for (items_all) |items| self.appendAssumeCapacity(T, items);
}

pub fn clear(self: *Self) void {
    self.buf.clearRetainingCapacity();
}

pub fn free(self: *Self, gpa: std.mem.Allocator) void {
    self.buf.clearAndFree(gpa);
}

pub inline fn state(self: *const Self) State {
    return if (self.byteLen() > 0) .valid else .empty;
}

pub const Usage = enum(c.SDL_GPUBufferUsageFlags) {
    vertex = c.SDL_GPU_BUFFERUSAGE_VERTEX,
    index = c.SDL_GPU_BUFFERUSAGE_INDEX,
    indirect = c.SDL_GPU_BUFFERUSAGE_INDIRECT,
    graphics_storage_read = c.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ,
    compute_storage_read = c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ,
    compute_storage_write = c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE,
};
pub const UsageFlags = std.EnumSet(Usage);
