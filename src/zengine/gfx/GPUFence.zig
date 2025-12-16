//!
//! The zengine gpu fence implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const sdl = @import("../sdl.zig");
const ui = @import("../ui.zig");
const Window = @import("../Window.zig");
const Error = @import("error.zig").Error;
const GPUBuffer = @import("GPUBuffer.zig");
const GPUDevice = @import("GPUDevice.zig");
const GPUTexture = @import("GPUTexture.zig");
const GPUTransferBuffer = @import("GPUTransferBuffer.zig");
const types = @import("types.zig");

const log = std.log.scoped(.gfx_fence);

ptr: ?*c.SDL_GPUFence = null,

const Self = @This();
pub const invalid: Self = .{};

pub fn fromOwned(ptr: *c.SDL_GPUFence) Self {
    return .{ .ptr = ptr };
}

pub fn toOwned(self: *Self) *c.SDL_GPUFence {
    assert(self.isValid());
    defer self.ptr = null;
    return self.ptr.?;
}

pub fn toSDL(self: *const Self) *c.SDL_GPUFence {
    assert(self.isValid());
    return self.ptr.?;
}

pub fn release(gpu_device: GPUDevice, ptr: *c.SDL_GPUFence) void {
    assert(gpu_device.isValid());
    c.SDL_ReleaseGPUFence(gpu_device.ptr, ptr);
}

pub fn query(self: *Self, gpu_device: GPUDevice) bool {
    assert(gpu_device.isValid());
    assert(self.isValid());
    return c.SDL_QueryGPUFence(gpu_device.ptr, self.ptr);
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}

pub const WaitBehavior = enum(u1) {
    any,
    all,
};
