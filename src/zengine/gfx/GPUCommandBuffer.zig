//!
//! The zengine gpu command buffer implementation
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
const Error = @import("Error.zig").Error;
const GPUCopyPass = @import("GPUCopyPass.zig");
const GPUDevice = @import("GPUDevice.zig");
const GPURenderPass = @import("GPURenderPass.zig");
const GPUTexture = @import("GPUTexture.zig");
const types = @import("types.zig");

const log = std.log.scoped(.gfx_gpu_texture);

ptr: ?*c.SDL_GPUCommandBuffer = null,

const Self = @This();
pub const invalid: Self = .{};

pub fn fromOwned(ptr: *c.SDL_GPUCommandBuffer) Self {
    return .{ .ptr = ptr };
}

pub fn toOwned(self: *Self) *c.SDL_GPUCommandBuffer {
    assert(self.isValid());
    defer self.ptr = null;
    return self.ptr.?;
}

pub fn submit(self: *Self) !void {
    if (!c.SDL_SubmitGPUCommandBuffer(self.toOwned())) {
        log.err("failed submitting command buffer: {s}", .{c.SDL_GetError()});
        return Error.CommandBufferFailed;
    }
}

pub fn cancel(self: *Self) !void {
    if (!c.SDL_CancelGPUCommandBuffer(self.toOwned())) {
        log.err("failed canceling command buffer: {s}", .{c.SDL_GetError()});
        return Error.CommandBufferFailed;
    }
}

pub fn swapchainTexture(self: Self, window: Window) !GPUTexture {
    assert(self.isValid());
    assert(window.isValid());
    var tex: ?*c.SDL_GPUTexture = undefined;
    if (!c.SDL_AcquireGPUSwapchainTexture(self.ptr, window.ptr, &tex, null, null)) {
        log.err("failed to acquire gpu swapchain texture: {s}", .{c.SDL_GetError()});
        return Error.TextureFailed;
    }
    return .{ .ptr = tex };
}

pub fn renderPass(
    self: Self,
    color_target_infos: []const types.ColorTargetInfo,
    depth_stencil_target_info: ?*const types.DepthStencilTargetInfo,
) !GPURenderPass {
    assert(self.isValid());
    var arena = allocators.initArena();
    defer arena.deinit();
    const ct_infos = try sdl.sliceFrom(arena.allocator(), color_target_infos);
    const ptr = c.SDL_BeginGPURenderPass(
        self.ptr,
        ct_infos.ptr,
        @intCast(ct_infos.len),
        if (depth_stencil_target_info) |info| &info.toSDL() else null,
    );
    if (ptr == null) {
        log.err("failed to begin gpu render pass: {s}", .{c.SDL_GetError()});
        return Error.RenderPassFailed;
    }
    return .fromOwned(ptr.?);
}

pub fn copyPass(self: Self) !GPUCopyPass {
    assert(self.isValid());
    const ptr = c.SDL_BeginGPUCopyPass(self.ptr);
    if (ptr == null) {
        log.err("failed to begin gpu copy pass: {s}", .{c.SDL_GetError()});
        return Error.CopyPassFailed;
    }
    return .fromOwned(ptr.?);
}

pub fn pushVertexUniformData(self: Self, slot_index: u32, data: anytype) void {
    assert(self.isValid());
    const bytes = std.mem.sliceAsBytes(data);
    c.SDL_PushGPUVertexUniformData(self.ptr, slot_index, bytes.ptr, @intCast(bytes.len));
}

pub fn pushFragmentUniformData(self: Self, slot_index: u32, data: anytype) void {
    assert(self.isValid());
    const bytes = std.mem.sliceAsBytes(data);
    c.SDL_PushGPUFragmentUniformData(self.ptr, slot_index, bytes.ptr, @intCast(bytes.len));
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}
