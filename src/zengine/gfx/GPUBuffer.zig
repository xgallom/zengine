//!
//! The zengine gpu buffer implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const math = @import("../math.zig");
const Tree = @import("../containers.zig").Tree;

const log = std.log.scoped(.gfx_gpu_buffer);

cpu_buf: CPUBuffer = .empty,
gpu_buf: ?*c.SDL_GPUBuffer = null,
len: u32 = 0,

const Self = @This();
pub const CPUBuffer = std.array_list.Aligned(u8, alignment);
pub const UsageFlags = std.EnumSet(Usage);

pub const State = enum {
    cpu,
    gpu,
    gpu_only,
};

pub const empty: Self = .{};
pub const alignment: std.mem.Alignment = .max(.of(math.Vector4), .of(math.batch.Batch));

pub fn deinit(self: *Self, gpa: std.mem.Allocator, gpu_device: ?*c.SDL_GPUDevice) void {
    if (self.gpu_buf != null) self.releaseGPUBuffer(gpu_device);
    self.freeCPUBuffer(gpa);
}

pub inline fn byteLen(self: *const Self) u32 {
    return @intCast(self.cpu_buf.items.len);
}

pub inline fn slice(self: *const Self, comptime T: type) []T {
    return std.mem.bytesAsSlice(T, self.cpu_buf.items);
}

pub fn ensureUnusedCapacity(self: *Self, gpa: std.mem.Allocator, comptime T: type, count: usize) !void {
    assert(@alignOf(T) <= alignment.toByteUnits());
    try self.cpu_buf.ensureUnusedCapacity(gpa, count * @sizeOf(T));
}

pub fn append(self: *Self, gpa: std.mem.Allocator, comptime T: type, items: []const T) !void {
    return self.cpu_buf.appendSlice(gpa, std.mem.sliceAsBytes(items));
}

pub fn appendAssumeCapacity(self: *Self, comptime T: type, items: []const T) void {
    return self.cpu_buf.appendSliceAssumeCapacity(std.mem.sliceAsBytes(items));
}

pub fn appendSlice(self: *Self, gpa: std.mem.Allocator, comptime T: type, items_all: []const []const T) !void {
    for (items_all) |items| try self.append(gpa, T, items);
}

pub fn appendSliceAssumeCapacity(self: *Self, comptime T: type, items_all: []const []const T) void {
    for (items_all) |items| self.appendAssumeCapacity(T, items);
}

pub fn clearCPUBuffer(self: *Self) void {
    self.cpu_buf.clearRetainingCapacity();
}

pub fn freeCPUBuffer(self: *Self, gpa: std.mem.Allocator) void {
    self.cpu_buf.clearAndFree(gpa);
}

pub fn createGPUBuffer(self: *Self, gpu_device: ?*c.SDL_GPUDevice, usage: UsageFlags) !void {
    if (self.gpu_buf != null) {
        if (self.len < self.slice(u8).len) {
            c.SDL_ReleaseGPUBuffer(gpu_device, self.gpu_buf);
        } else return;
    }

    self.len = @intCast(self.slice(u8).len);
    self.gpu_buf = c.SDL_CreateGPUBuffer(gpu_device, &c.SDL_GPUBufferCreateInfo{
        .usage = usage.bits.mask,
        .size = self.len,
    });
    if (self.gpu_buf == null) {
        log.err("failed creating buffer: {s}", .{c.SDL_GetError()});
        return error.BufferFailed;
    }
}

pub fn releaseGPUBuffer(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
    assert(self.gpu_buf != null);
    c.SDL_ReleaseGPUBuffer(gpu_device, self.gpu_buf);
    self.gpu_buf = null;
    self.len = 0;
}

pub inline fn state(self: *const Self) State {
    if (self.gpu_buf != null) {
        if (self.slice(u8).len == 0) return .gpu_only;
        return .gpu;
    }
    return .cpu;
}

pub const Usage = enum(c.SDL_GPUBufferUsageFlags) {
    vertex = c.SDL_GPU_BUFFERUSAGE_VERTEX,
    index = c.SDL_GPU_BUFFERUSAGE_INDEX,
    indirect = c.SDL_GPU_BUFFERUSAGE_INDIRECT,
    graphics_storage_read = c.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ,
    compute_storage_read = c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ,
    compute_storage_write = c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE,
};
