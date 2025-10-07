//!
//! The zengine gpu device implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");
const Window = @import("../Window.zig");
const Error = @import("Error.zig").Error;
const GPUShader = @import("GPUShader.zig");
const types = @import("types.zig");

const log = std.log.scoped(.gfx_gpu_device);

ptr: ?*c.SDL_GPUDevice = null,

const Self = @This();
pub const invalid: Self = .{};

pub fn init(format_flags: GPUShader.FormatFlags, debug_mode: bool, name: ?[:0]const u8) !Self {
    return fromOwnedGPUDevice(try create(format_flags, debug_mode, name));
}

pub fn deinit(self: *Self) void {
    if (self.isValid()) destroy(self.toOwnedGPUDevice());
}

pub fn create(format_flags: GPUShader.FormatFlags, debug_mode: bool, name: ?[:0]const u8) !*c.SDL_GPUDevice {
    const ptr = c.SDL_CreateGPUDevice(format_flags.bits.mask, debug_mode, @ptrCast(name));
    if (ptr == null) {
        log.err("failed creating gpu device: {s}", .{c.SDL_GetError()});
        return Error.GPUFailed;
    }
    return ptr.?;
}

pub fn destroy(ptr: *c.SDL_GPUDevice) void {
    c.SDL_DestroyGPUDevice(ptr);
}

pub fn fromOwnedGPUDevice(ptr: *c.SDL_GPUDevice) Self {
    return .{ .ptr = ptr };
}

pub fn toOwnedGPUDevice(self: *Self) *c.SDL_GPUDevice {
    assert(self.isValid());
    defer self.ptr = null;
    return self.ptr.?;
}

pub fn formatFlags(self: Self) GPUShader.FormatFlags {
    assert(self.isValid());
    return .{ .bits = .{ .mask = @intCast(c.SDL_GetGPUShaderFormats(self.ptr)) } };
}

pub fn claimWindow(self: Self, window: Window) !void {
    assert(self.isValid());
    assert(window.isValid());
    if (!c.SDL_ClaimWindowForGPUDevice(self.ptr, window.ptr)) {
        log.err("failed claiming window for gpu device: {s}", .{c.SDL_GetError()});
        return Error.WindowFailed;
    }
}

pub fn releaseWindow(self: Self, window: Window) void {
    assert(self.isValid());
    assert(window.isValid());
    c.SDL_ReleaseWindowFromGPUDevice(self.ptr, window.ptr);
}

pub fn setAllowedFramesInFlight(self: Self, count: u32) bool {
    return c.SDL_SetGPUAllowedFramesInFlight(self.ptr, count);
}
pub fn setSwapchainParameters(
    self: Self,
    window: Window,
    swapchain_composition: types.SwapchainComposition,
    present_mode: types.PresentMode,
) !void {
    if (!c.SDL_SetGPUSwapchainParameters(
        self.ptr,
        window.ptr,
        @intFromEnum(swapchain_composition),
        @intFromEnum(present_mode),
    )) {
        log.err("failed setting swapchain parameters: {s}", .{c.SDL_GetError()});
        return Error.WindowFailed;
    }
}

pub fn supportsPresentMode(self: Self, window: Window, present_mode: types.PresentMode) bool {
    assert(self.isValid());
    assert(window.isValid());
    return c.SDL_WindowSupportsGPUPresentMode(self.ptr, window.ptr, @intFromEnum(present_mode));
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}
