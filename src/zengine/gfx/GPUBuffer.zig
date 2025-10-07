//!
//! The zengine gpu buffer implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const Tree = @import("../containers.zig").Tree;
const c = @import("../ext.zig").c;
const math = @import("../math.zig");
const Error = @import("Error.zig").Error;
const GPUDevice = @import("GPUDevice.zig");

const log = std.log.scoped(.gfx_gpu_buffer);

ptr: ?*c.SDL_GPUBuffer = null,
size: u32 = 0,

const Self = @This();
pub const invalid: Self = .{};

pub const CreateInfo = struct {
    usage: UsageFlags,
    size: u32,
};

pub fn deinit(self: *Self, gpu_device: GPUDevice) void {
    if (self.ptr != null) self.release(gpu_device);
}

pub inline fn byteLen(self: *const Self) u32 {
    return self.size;
}

pub fn create(self: *Self, gpu_device: GPUDevice, info: *const CreateInfo) !void {
    if (self.ptr != null) self.release(gpu_device);
    self.size = info.size;
    self.ptr = c.SDL_CreateGPUBuffer(gpu_device.ptr, &c.SDL_GPUBufferCreateInfo{
        .usage = info.usage.bits.mask,
        .size = self.size,
    });
    if (self.ptr == null) {
        log.err("failed creating gpu buffer: {s}", .{c.SDL_GetError()});
        return Error.BufferFailed;
    }
}

pub fn release(self: *Self, gpu_device: GPUDevice) void {
    assert(self.ptr != null);
    c.SDL_ReleaseGPUBuffer(gpu_device.ptr, self.ptr);
    self.ptr = null;
    self.size = 0;
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}

pub inline fn isnNotEmpty(self: Self) bool {
    return self.ptr != null and self.byte_len > 0;
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
