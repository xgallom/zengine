//!
//! The zengine bloom pass implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const math = @import("../../math.zig");
const GPUCommandBuffer = @import("../GPUCommandBuffer.zig");
const GPUGraphicsPipeline = @import("../GPUGraphicsPipeline.zig");
const GPUTexture = @import("../GPUTexture.zig");
const Loader = @import("../Loader.zig");
const Renderer = @import("../Renderer.zig");
const Interface = @import("TextureInterface.zig");

const log = std.log.scoped(.gfx_pass_bloom);

const SAMPLE_COUNT = 5;
const DOWNSAMPLING = 0;

threshold: f32 = 1,
intensity: f32 = 0.2,

const Self = @This();

pub const threshold_min = 0.5;
pub const threshold_max = 10;
pub const threshold_speed = 0.01;
pub const intensity_min = 0;
pub const intensity_max = 10;
pub const intensity_speed = 0.01;

fn getShr(comptime n: std.math.Log2Int(u32)) std.math.Log2Int(u32) {
    return n + DOWNSAMPLING;
}

pub fn init(loader: *Loader) !void {
    const win_size = loader.renderer.window.pixelSize();
    inline for (0..SAMPLE_COUNT) |n| {
        var res = win_size;
        math.point_u32.shr(&res, getShr(n));
        _ = try loader.renderer.createTexture(std.fmt.comptimePrint("bloom_buffer_{}", .{n}), &.{
            .type = .@"2D",
            .format = .hdr_f,
            .usage = .initMany(&.{ .sampler, .color_target }),
            .size = res,
        });
    }

    const bright_pass_frag = try loader.loadShader(.fragment, "system/bloom/bright_pass.frag");
    const downsample_frag = try loader.loadShader(.fragment, "system/bloom/downsample.frag");
    const upsample_frag = try loader.loadShader(.fragment, "system/bloom/upsample.frag");
    const composite_frag = try loader.loadShader(.fragment, "system/bloom/composite.frag");
    const screen_vert = loader.renderer.shaders.get("system/screen.vert");

    var pipeline: GPUGraphicsPipeline.CreateInfo = .{
        .vertex_shader = screen_vert,
        .target_info = .{
            .color_target_descriptions = &.{
                .{ .format = .hdr_f },
            },
        },
    };

    pipeline.fragment_shader = bright_pass_frag;
    _ = try loader.renderer.createGraphicsPipeline("bloom_bright_pass", &pipeline);
    pipeline.fragment_shader = downsample_frag;
    _ = try loader.renderer.createGraphicsPipeline("bloom_downsample", &pipeline);
    pipeline.fragment_shader = upsample_frag;
    _ = try loader.renderer.createGraphicsPipeline("bloom_upsample", &pipeline);
    pipeline.fragment_shader = composite_frag;
    _ = try loader.renderer.createGraphicsPipeline("bloom_composite", &pipeline);
}

pub fn render(
    self: *const Self,
    renderer: *const Renderer,
    command_buffer: GPUCommandBuffer,
    src: GPUTexture,
    dst: GPUTexture,
) !void {
    const bloom_buffers = blk: {
        var result: [SAMPLE_COUNT]GPUTexture = undefined;
        inline for (0..SAMPLE_COUNT) |n| result[n] = renderer.textures.get(
            std.fmt.comptimePrint("bloom_buffer_{}", .{n}),
        );
        break :blk result;
    };

    const bright_pass = renderer.pipelines.graphics.get("bloom_bright_pass");
    const downsample = renderer.pipelines.graphics.get("bloom_downsample");
    const upsample = renderer.pipelines.graphics.get("bloom_upsample");
    const composite = renderer.pipelines.graphics.get("bloom_composite");
    const sampler = renderer.samplers.get("bilinear_clamp_to_edge");

    const win_size = renderer.window.pixelSize();
    var uniform_buf: [4]f32 = undefined;
    uniform_buf[0] = self.threshold;
    uniform_buf[1] = self.intensity;

    {
        var render_pass = try command_buffer.renderPass(&.{
            .{ .texture = bloom_buffers[0], .load_op = .clear, .store_op = .store },
        }, null);
        defer render_pass.end();

        render_pass.bindPipeline(bright_pass);
        log.debug("filter[{}]: {any}", .{ 0, win_size });
        const res = math.point_u32.to(f32, &win_size);
        uniform_buf[2] = math.scalar.recip(res[0]);
        uniform_buf[3] = math.scalar.recip(res[1]);
        command_buffer.pushUniformData(.fragment, 0, &uniform_buf);

        try render_pass.bindSamplers(.fragment, 0, &.{
            .{ .texture = src, .sampler = sampler },
        });

        render_pass.drawScreen();
    }

    inline for (0..SAMPLE_COUNT - 1) |n| {
        var render_pass = try command_buffer.renderPass(&.{
            .{ .texture = bloom_buffers[n + 1], .load_op = .clear, .store_op = .store },
        }, null);
        defer render_pass.end();

        render_pass.bindPipeline(downsample);
        var size = win_size;
        math.point_u32.shr(&size, getShr(n));
        log.debug("down[{}]: {any}", .{ n, size });
        const res = math.point_u32.to(f32, &size);
        uniform_buf[2] = math.scalar.recip(res[0]);
        uniform_buf[3] = math.scalar.recip(res[1]);
        command_buffer.pushUniformData(.fragment, 0, &uniform_buf);

        try render_pass.bindSamplers(.fragment, 0, &.{
            .{ .texture = bloom_buffers[n], .sampler = sampler },
        });

        render_pass.drawScreen();
    }

    inline for (1..SAMPLE_COUNT) |inv_n| {
        const n = SAMPLE_COUNT - inv_n;
        var render_pass = try command_buffer.renderPass(&.{
            .{ .texture = bloom_buffers[n - 1], .load_op = .clear, .store_op = .store },
        }, null);
        defer render_pass.end();

        render_pass.bindPipeline(upsample);
        var size = win_size;
        math.point_u32.shr(&size, getShr(n));
        log.debug("up[{}]: {any}", .{ n, size });
        const res = math.point_u32.to(f32, &size);
        uniform_buf[2] = math.scalar.recip(res[0]);
        uniform_buf[3] = math.scalar.recip(res[1]);
        command_buffer.pushUniformData(.fragment, 0, &uniform_buf);

        try render_pass.bindSamplers(.fragment, 0, &.{
            .{ .texture = bloom_buffers[n], .sampler = sampler },
        });

        render_pass.drawScreen();
    }

    {
        var render_pass = try command_buffer.renderPass(&.{
            .{ .texture = dst, .load_op = .dont_care, .store_op = .store },
        }, null);
        defer render_pass.end();

        render_pass.bindPipeline(composite);
        command_buffer.pushUniformData(.fragment, 0, &uniform_buf);

        try render_pass.bindSamplers(.fragment, 0, &.{
            .{ .texture = src, .sampler = sampler },
            .{ .texture = bloom_buffers[0], .sampler = sampler },
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
