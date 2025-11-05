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
usage: UsageFlags = .initEmpty(),

const Self = @This();
pub const invalid: Self = .{};

pub const CreateInfo = struct {
    usage: UsageFlags,
    size: u32,
};

pub fn init(gpu_device: GPUDevice, info: *const CreateInfo) !Self {
    return .{
        .ptr = try create(gpu_device, info),
        .size = info.size,
        .usage = info.usage,
    };
}

pub fn deinit(self: *Self, gpu_device: GPUDevice) void {
    if (self.isValid()) release(gpu_device, self.toOwned());
}

pub fn toOwned(self: *Self) *c.SDL_GPUBuffer {
    assert(self.isValid());
    defer self.ptr = null;
    return self.ptr.?;
}

pub fn toSDL(self: *const Self) *c.SDL_GPUBuffer {
    assert(self.isValid());
    return self.ptr.?;
}

pub fn create(gpu_device: GPUDevice, info: *const CreateInfo) !*c.SDL_GPUBuffer {
    assert(gpu_device.isValid());
    const ptr = c.SDL_CreateGPUBuffer(gpu_device.ptr, &c.SDL_GPUBufferCreateInfo{
        .usage = info.usage.bits.mask,
        .size = info.size,
    });
    if (ptr == null) {
        log.err("failed creating gpu buffer: {s}", .{c.SDL_GetError()});
        return Error.BufferFailed;
    }
    return ptr.?;
}

pub fn release(gpu_device: GPUDevice, ptr: *c.SDL_GPUBuffer) void {
    assert(gpu_device.isValid());
    c.SDL_ReleaseGPUBuffer(gpu_device.ptr, ptr);
}

pub fn resize(self: *Self, gpu_device: GPUDevice, info: *const CreateInfo) !void {
    assert(gpu_device.isValid());
    if (self.size != info.size) {
        self.deinit(gpu_device);
        self.* = try gpu_device.buffer(info);
    }
}

pub inline fn byteLen(self: *const Self) u32 {
    return self.size;
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}

pub inline fn isnNotEmpty(self: Self) bool {
    return self.ptr != null and self.byte_len > 0;
}

pub const Location = struct {
    buffer: Self,
    offset: u32,

    pub fn toSDL(self: *const @This()) c.SDL_GPUBufferLocation {
        return .{
            .buffer = self.buffer.ptr,
            .offset = self.offset,
        };
    }
};

pub const Region = struct {
    buffer: Self = .invalid,
    offset: u32 = 0,
    size: u32 = 0,

    pub fn toSDL(self: *const @This()) c.SDL_GPUBufferRegion {
        return .{
            .buffer = self.buffer.ptr,
            .offset = self.offset,
            .size = self.size,
        };
    }
};

pub const Binding = struct {
    buffer: Self = .invalid,
    offset: u32 = 0,

    pub fn toSDL(self: *const @This()) c.struct_SDL_GPUBufferBinding {
        return .{
            .buffer = self.buffer.ptr,
            .offset = self.offset,
        };
    }
};

pub const Usage = enum(c.SDL_GPUBufferUsageFlags) {
    vertex = c.SDL_GPU_BUFFERUSAGE_VERTEX,
    index = c.SDL_GPU_BUFFERUSAGE_INDEX,
    indirect = c.SDL_GPU_BUFFERUSAGE_INDIRECT,
    graphics_storage_read = c.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ,
    compute_storage_read = c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ,
    compute_storage_write = c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE,
};
pub const UsageFlags = std.EnumSet(Usage);
