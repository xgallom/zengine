//!
//! The zengine letterbox pass implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const math = @import("../../math.zig");
const GPUCommandBuffer = @import("../GPUCommandBuffer.zig");
const GPUGraphicsPipeline = @import("../GPUGraphicsPipeline.zig");
const GPUTexture = @import("../GPUTexture.zig");
const Loader = @import("../Loader.zig");
const Renderer = @import("../Renderer.zig");
const types = @import("../types.zig");
const Interface = @import("Interface.zig");

const log = std.log.scoped(.gfx_pass_bloom);

scale: math.Point_f32,
sampler: [:0]const u8 = "bilinear_clamp_to_edge",

const Self = @This();

pub fn calculateScale(src_size: math.Point_u32, dst_size: math.Point_u32) math.Point_f32 {
    const dst_size_f32 = math.point_u32.to(f32, &dst_size);
    const dst_ratio = dst_size_f32[0] / dst_size_f32[1];
    const src_size_f32 = math.point_u32.to(f32, &src_size);
    const src_ratio = src_size_f32[0] / src_size_f32[1];
    return if (dst_ratio > src_ratio)
        .{ dst_ratio / src_ratio, 1 }
    else
        .{ 1, src_ratio / dst_ratio };
}

pub fn render(
    self: *const Self,
    renderer: *const Renderer,
    command_buffer: GPUCommandBuffer,
    src: GPUTexture,
    dst: GPUTexture,
) !void {
    const pipeline = renderer.pipelines.graphics.get("letterbox");
    const sampler = renderer.samplers.get(self.sampler);

    {
        var render_pass = try command_buffer.renderPass(&.{
            .{ .texture = dst, .load_op = .clear, .store_op = .store },
        }, null);
        defer render_pass.end();

        render_pass.bindPipeline(pipeline);

        command_buffer.pushUniformData(.fragment, 0, &self.scale);
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
