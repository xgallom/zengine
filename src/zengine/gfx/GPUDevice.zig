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
const Error = @import("error.zig").Error;
const GPUBuffer = @import("GPUBuffer.zig");
const GPUCommandBuffer = @import("GPUCommandBuffer.zig");
const GPUComputePipeline = @import("GPUComputePipeline.zig");
const GPUGraphcisPipeline = @import("GPUGraphicsPipeline.zig");
const GPUSampler = @import("GPUSampler.zig");
const GPUShader = @import("GPUShader.zig");
const GPUTexture = @import("GPUTexture.zig");
const GPUTransferBuffer = @import("GPUTransferBuffer.zig");
const types = @import("types.zig");

const log = std.log.scoped(.gfx_gpu_device);

ptr: ?*c.SDL_GPUDevice = null,

const Self = @This();
pub const invalid: Self = .{};

pub fn init(format_flags: GPUShader.FormatFlags, debug_mode: bool, name: ?[:0]const u8) !Self {
    return fromOwned(try create(format_flags, debug_mode, name));
}

pub fn deinit(self: *Self) void {
    if (self.isValid()) destroySelf(self.toOwned());
}

pub fn create(format_flags: GPUShader.FormatFlags, debug_mode: bool, name: ?[:0]const u8) !*c.SDL_GPUDevice {
    const ptr = c.SDL_CreateGPUDevice(format_flags.bits.mask, debug_mode, @ptrCast(name));
    if (ptr == null) {
        log.err("failed creating gpu device: {s}", .{c.SDL_GetError()});
        return Error.GPUFailed;
    }
    return ptr.?;
}

pub fn destroySelf(ptr: *c.SDL_GPUDevice) void {
    c.SDL_DestroyGPUDevice(ptr);
}

pub fn fromOwned(ptr: *c.SDL_GPUDevice) Self {
    return .{ .ptr = ptr };
}

pub fn toOwned(self: *Self) *c.SDL_GPUDevice {
    assert(self.isValid());
    defer self.ptr = null;
    return self.ptr.?;
}

pub fn commandBuffer(self: Self) !GPUCommandBuffer {
    assert(self.isValid());
    const ptr = c.SDL_AcquireGPUCommandBuffer(self.ptr);
    if (ptr == null) {
        log.err("failed acquiring gpu command buffer: {s}", .{c.SDL_GetError()});
        return Error.CommandBufferFailed;
    }
    return .fromOwned(ptr.?);
}

pub fn shader(self: Self, info: *const GPUShader.CreateInfo) !GPUShader {
    return .init(self, info);
}

pub fn buffer(self: Self, info: *const GPUBuffer.CreateInfo) !GPUBuffer {
    return .init(self, info);
}

pub fn texture(self: Self, info: *const GPUTexture.CreateInfo) !GPUTexture {
    return .init(self, info);
}

pub fn sampler(self: Self, info: *const GPUSampler.CreateInfo) !GPUSampler {
    return .init(self, info);
}

pub fn computePipeline(self: Self, info: *const GPUComputePipeline.CreateInfo) !GPUComputePipeline {
    return .init(self, info);
}

pub fn graphicsPipeline(self: Self, info: *const GPUGraphcisPipeline.CreateInfo) !GPUGraphcisPipeline {
    return .init(self, info);
}

pub fn transferBuffer(self: Self, info: *const GPUTransferBuffer.CreateInfo) !GPUTransferBuffer {
    return .init(self, info);
}

pub fn destroy(self: Self, item: anytype) void {
    std.meta.Child(@TypeOf(item)).destroy(self, item.toOwned());
}

pub fn release(self: Self, item: anytype) void {
    std.meta.Child(@TypeOf(item)).release(self, item.toOwned());
}

pub fn map(self: Self, tr_buf: GPUTransferBuffer, cycle: bool) !GPUTransferBuffer.Mapping {
    assert(self.isValid());
    assert(tr_buf.isValid());
    const ptr = c.SDL_MapGPUTransferBuffer(self.ptr, tr_buf.ptr, cycle);
    if (ptr == null) {
        log.err("failed mapping transfer buffer: {s}", .{c.SDL_GetError()});
        return Error.TransferBufferFailed;
    }
    return .{ .gpu_device = self, .tr_buf = tr_buf, .ptr = @ptrCast(@alignCast(ptr.?)) };
}

pub fn unmap(self: Self, tr_buf: GPUTransferBuffer) void {
    assert(self.isValid());
    assert(tr_buf.isValid());
    c.SDL_UnmapGPUTransferBuffer(self.ptr, tr_buf.ptr);
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

pub fn textureSupportsFormat(
    self: Self,
    format: GPUTexture.Format,
    tex_type: GPUTexture.Type,
    usage: GPUTexture.UsageFlags,
) bool {
    assert(self.isValid());
    return c.SDL_GPUTextureSupportsFormat(
        self.ptr,
        @intFromEnum(format),
        @intFromEnum(tex_type),
        usage.bits.mask,
    );
}

pub fn stencilFormat(self: Self) GPUTexture.Format {
    assert(self.isValid());
    if (self.textureSupportsFormat(
        .D24_unorm_S8_u,
        .@"2D",
        .initOne(.depth_stencil_target),
    )) return .D24_unorm_S8_u;
    if (self.textureSupportsFormat(
        .D32_f_S8_u,
        .@"2D",
        .initOne(.depth_stencil_target),
    )) return .D32_f_S8_u;
    return .D32_f;
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}
