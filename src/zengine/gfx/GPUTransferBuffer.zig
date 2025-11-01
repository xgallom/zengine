//!
//! The zengine gpu texture implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");
const Error = @import("Error.zig").Error;
const GPUDevice = @import("GPUDevice.zig");
const types = @import("types.zig");

const log = std.log.scoped(.gfx_gpu_transfer_buffer);

ptr: ?*c.SDL_GPUTransferBuffer = null,

const Self = @This();
pub const invalid: Self = .{};

comptime {
    assert(@sizeOf(Self) == @sizeOf(*c.SDL_GPUTransferBuffer));
    assert(@alignOf(Self) == @alignOf(*c.SDL_GPUTransferBuffer));
}

pub const CreateInfo = struct {
    usage: Usage = .default,
    size: u32 = 0,
};

pub fn init(gpu_device: GPUDevice, info: *const CreateInfo) !Self {
    return fromOwned(try create(gpu_device, info));
}

pub fn deinit(self: *Self, gpu_device: GPUDevice) void {
    if (self.isValid()) release(gpu_device, self.toOwned());
}

pub fn create(gpu_device: GPUDevice, info: *const CreateInfo) !*c.SDL_GPUTransferBuffer {
    assert(gpu_device.isValid());
    const ptr = c.SDL_CreateGPUTransferBuffer(gpu_device.ptr, &c.SDL_GPUTransferBufferCreateInfo{
        .usage = @intFromEnum(info.usage),
        .size = info.size,
    });
    if (ptr == null) {
        log.err("failed creating gpu transfer buffer: {s}", .{c.SDL_GetError()});
        return Error.TransferBufferFailed;
    }
    return ptr.?;
}

pub fn release(gpu_device: GPUDevice, ptr: *c.SDL_GPUTransferBuffer) void {
    assert(gpu_device.isValid());
    c.SDL_ReleaseGPUTransferBuffer(gpu_device.ptr, ptr);
}

pub fn fromOwned(ptr: *c.SDL_GPUTransferBuffer) Self {
    return .{ .ptr = ptr };
}

pub fn toOwned(self: *Self) *c.SDL_GPUTransferBuffer {
    assert(self.isValid());
    defer self.ptr = null;
    return self.ptr.?;
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}

pub const Mapping = struct {
    gpu_device: GPUDevice,
    tr_buf: Self,
    ptr: [*]u8,
    offset: usize = 0,

    pub fn unmap(m: Mapping) void {
        m.gpu_device.unmap(m.tr_buf);
    }

    pub fn copy(m: *Mapping, slice: anytype) void {
        const bytes = std.mem.sliceAsBytes(slice);
        @memcpy(m.ptr[m.offset .. m.offset + bytes.len], bytes);
        m.offset += bytes.len;
    }
};

pub const Usage = enum(c.SDL_GPUTransferBufferUsage) {
    upload = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
    download = c.SDL_GPU_TRANSFERBUFFERUSAGE_DOWNLOAD,
    pub const default = .upload;
};
