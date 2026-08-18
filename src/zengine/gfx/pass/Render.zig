//!
//! The zengine render pass implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const math = @import("../../math.zig");
const ui = @import("../../ui.zig");
const GPUCommandBuffer = @import("../GPUCommandBuffer.zig");
const GPUGraphicsPipeline = @import("../GPUGraphicsPipeline.zig");
const GPUTexture = @import("../GPUTexture.zig");
const Loader = @import("../Loader.zig");
const Renderer = @import("../Renderer.zig");
const Interface = @import("Interface.zig");

const log = std.log.scoped(.gfx_pass_bloom);

lut: [:0]const u8 = "lut/basic.cube",
exposure: f32 = 1,
exposure_bias: f32 = 0,
gamma: f32 = 1,
config: packed struct {
    has_agx: bool = false,
    has_lut: bool = false,
    has_srgb: bool = false,
    clear: bool = true,

    pub fn toInt(config: @This()) u32 {
        var result: u32 = 0;
        result |= @as(u32, @intFromBool(config.has_agx)) << 0;
        result |= @as(u32, @intFromBool(config.has_lut)) << 1;
        result |= @as(u32, @intFromBool(config.has_srgb)) << 2;
        return result;
    }

    pub const excluded_properties = &.{.clear};
} = .{},

pub const exposure_min = 0;
pub const exposure_max = 100;
pub const exposure_speed = 0.05;
pub const exposure_bias_min = 0;
pub const exposure_bias_max = 100;
pub const exposure_bias_speed = 0.01;
pub const gamma_min = 0.1;
pub const gamma_max = 4;
pub const gamma_speed = 0.05;

const Self = @This();

pub fn render(
    self: *const Self,
    renderer: *const Renderer,
    command_buffer: GPUCommandBuffer,
    src: GPUTexture,
    dst: GPUTexture,
) !void {
    const render_pipeline = renderer.pipelines.graphics.get("render");
    const screen_sampler = renderer.samplers.get("nearest_clamp_to_edge");
    const lut_sampler = renderer.samplers.get("trilinear_clamp_to_edge");
    const lut_map = renderer.textures.get(self.lut);

    {
        var render_pass = try command_buffer.renderPass(&.{
            .{
                .texture = dst,
                .load_op = if (self.config.clear) .clear else .load,
                .store_op = .store,
            },
        }, null);
        defer render_pass.end();

        render_pass.bindPipeline(render_pipeline);
        command_buffer.pushUniformData(.fragment, 0, &self.uniformBuffer());
        try render_pass.bindSamplers(.fragment, 0, &.{
            .{ .texture = src, .sampler = screen_sampler },
            .{ .texture = lut_map, .sampler = lut_sampler },
        });
        render_pass.drawScreen();
    }
}

pub fn uniformBuffer(self: *const Self) [4]f32 {
    var result: [4]f32 = undefined;
    result[0] = self.exposure;
    result[1] = self.exposure_bias;
    result[2] = self.gamma;
    const ptr_config: *u32 = @ptrCast(&result[3]);
    ptr_config.* = self.config.toInt();
    return result;
}

pub fn interface(self: *const Self) Interface {
    return .{
        .ptr = @ptrCast(@constCast(self)),
        .renderFn = @ptrCast(&render),
    };
}
