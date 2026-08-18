//!
//! The zengine blend pass implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const GPUCommandBuffer = @import("../GPUCommandBuffer.zig");
const GPUGraphicsPipeline = @import("../GPUGraphicsPipeline.zig");
const GPUTexture = @import("../GPUTexture.zig");
const Loader = @import("../Loader.zig");
const Renderer = @import("../Renderer.zig");
const types = @import("../types.zig");
const Interface = @import("Interface.zig");

const log = std.log.scoped(.gfx_pass_bloom);

load_op: types.LoadOp = .load,
sampler: [:0]const u8 = "bilinear_clamp_to_edge",

const Self = @This();

pub fn render(
    self: *const Self,
    renderer: *const Renderer,
    command_buffer: GPUCommandBuffer,
    src: GPUTexture,
    dst: GPUTexture,
) !void {
    const pipeline = renderer.pipelines.graphics.get("blend");
    const sampler = renderer.samplers.get(self.sampler);

    {
        var render_pass = try command_buffer.renderPass(&.{
            .{ .texture = dst, .load_op = self.load_op, .store_op = .store },
        }, null);
        defer render_pass.end();

        render_pass.bindPipeline(pipeline);

        try render_pass.bindSamplers(.fragment, 0, &.{
            .{ .texture = src, .sampler = sampler },
        });

        render_pass.drawScreen();
    }
}

pub fn interface(self: *const Self) Interface {
    return .{
        .ptr = @ptrCast(@constCast(self)),
        .renderFn = @ptrCast(&render),
    };
}
