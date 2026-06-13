//!
//! The zengine render pass interface
//!

const std = @import("std");
const assert = std.debug.assert;

const math = @import("../../math.zig");
const GPUCommandBuffer = @import("../GPUCommandBuffer.zig");
const GPUTexture = @import("../GPUTexture.zig");
const Renderer = @import("../Renderer.zig");

const log = std.log.scoped(.gfx_pass_interface);

ptr: ?*anyopaque,
renderFn: *const RenderFn,

const Self = @This();
pub const RenderFn = fn (
    ptr: ?*anyopaque,
    renderer: *const Renderer,
    command_buffer: GPUCommandBuffer,
    src: GPUTexture,
    dst: GPUTexture,
) anyerror!void;

pub fn render(
    self: Self,
    renderer: *const Renderer,
    command_buffer: GPUCommandBuffer,
    src: GPUTexture,
    dst: GPUTexture,
) !void {
    try self.renderFn(self.ptr, renderer, command_buffer, src, dst);
}
