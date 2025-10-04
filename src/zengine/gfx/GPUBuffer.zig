//!
//! The zengine gpu buffer implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const math = @import("../math.zig");
const Tree = @import("../containers.zig").Tree;

const log = std.log.scoped(.gfx_gpu_buffer);

ptr: ?*c.SDL_GPUBuffer = null,

const Self = @This();

pub const State = enum {
    invalid,
    valid,
};

pub const CreateInfo = struct {
    usage: UsageFlags,
    size: u32,
};

pub const invalid: Self = .{};

pub fn deinit(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
    if (self.ptr != null) self.release(gpu_device);
}

pub inline fn byteLen(self: *const Self) u32 {
    return self.len;
}

pub fn create(self: *Self, gpu_device: ?*c.SDL_GPUDevice, info: *const CreateInfo) !void {
    if (self.ptr != null) self.release();
    self.size = info.size;
    self.ptr = c.SDL_CreateGPUBuffer(gpu_device, &c.SDL_GPUBufferCreateInfo{
        .usage = info.usage.bits.mask,
        .size = self.size,
    });
    if (self.ptr == null) {
        log.err("failed creating gpu buffer: {s}", .{c.SDL_GetError()});
        return error.BufferFailed;
    }
}

pub fn release(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
    assert(self.ptr != null);
    c.SDL_ReleaseGPUBuffer(gpu_device, self.ptr);
    self.ptr = null;
    self.len = 0;
}

pub inline fn state(self: *const Self) State {
    if (self.ptr == null) return .invalid;
    if (self.len == 0) return .empty;
    return .valid;
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
