//!
//! The zengine gpu shader implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");
const Error = @import("Error.zig").Error;
const GPUDevice = @import("GPUDevice.zig");
const GPUShader = @import("GPUShader.zig");
const GPUTexture = @import("GPUTexture.zig");
const types = @import("types.zig");

const log = std.log.scoped(.gfx_gpu_graphics_pipeline);

ptr: ?*c.SDL_GPUGraphicsPipeline = null,

const Self = @This();
pub const invalid: Self = .{};

pub const CreateInfo = struct {
    vertex_shader: GPUShader = .invalid,
    fragment_shader: GPUShader = .invalid,
    vertex_input_state: types.VertexInputState = .{},
    primitive_type: types.PrimitiveType = .default,
    rasterizer_state: types.RasterizerState = .{},
    multisample_state: types.MultisampleState = .{},
    depth_stencil_state: types.DepthStencilState = .{},
    target_info: TargetInfo = .{},

    pub fn toSDL(self: *const @This(), gpa: std.mem.Allocator) !c.SDL_GPUGraphicsPipelineCreateInfo {
        return .{
            .vertex_shader = self.vertex_shader.ptr,
            .fragment_shader = self.fragment_shader.ptr,
            .vertex_input_state = try self.vertex_input_state.toSDL(gpa),
            .primitive_type = @intFromEnum(self.primitive_type),
            .rasterizer_state = self.rasterizer_state.toSDL(),
            .multisample_state = self.multisample_state.toSDL(),
            .depth_stencil_state = self.depth_stencil_state.toSDL(),
            .target_info = try self.target_info.toSDL(gpa),
        };
    }
};

pub fn init(gpu_device: GPUDevice, info: *const CreateInfo) !Self {
    return fromOwnedGPUGraphicsPipeline(try create(gpu_device, info));
}

pub fn deinit(self: *Self, gpu_device: GPUDevice) void {
    if (self.ptr != null) release(gpu_device, self.toOwnedGPUGraphicsPipeline());
}

fn create(gpu_device: GPUDevice, info: *const CreateInfo) !*c.SDL_GPUGraphicsPipeline {
    var arena = allocators.initArena();
    defer arena.deinit();
    const ptr = c.SDL_CreateGPUGraphicsPipeline(gpu_device.ptr, &try info.toSDL(arena.allocator()));
    if (ptr == null) {
        log.err("failed creating gpu graphics pipeline: {s}", .{c.SDL_GetError()});
        return Error.PipelineFailed;
    }
    return ptr.?;
}

fn release(gpu_device: GPUDevice, ptr: *c.SDL_GPUGraphicsPipeline) void {
    c.SDL_ReleaseGPUGraphicsPipeline(gpu_device.ptr, ptr);
}

pub fn fromOwnedGPUGraphicsPipeline(ptr: *c.SDL_GPUGraphicsPipeline) Self {
    return .{ .ptr = ptr };
}

pub fn toOwnedGPUGraphicsPipeline(self: *Self) *c.SDL_GPUGraphicsPipeline {
    assert(self.ptr != null);
    defer self.ptr = null;
    return self.ptr.?;
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}

pub const TargetInfo = struct {
    color_target_descriptions: []const types.ColorTargetDescription = &.{},
    depth_stencil_format: GPUTexture.Format = .default,
    has_depth_stencil_target: bool = false,

    pub fn toSDL(self: *const @This(), gpa: std.mem.Allocator) !c.SDL_GPUGraphicsPipelineTargetInfo {
        const color_target_descriptions = try gpa.alloc(
            c.SDL_GPUColorTargetDescription,
            self.color_target_descriptions.len,
        );
        for (color_target_descriptions, self.color_target_descriptions) |*to, *from| {
            to.* = from.toSDL();
        }
        return .{
            .color_target_descriptions = color_target_descriptions.ptr,
            .num_color_targets = @intCast(color_target_descriptions.len),
            .depth_stencil_format = @intFromEnum(self.depth_stencil_format),
            .has_depth_stencil_target = self.has_depth_stencil_target,
        };
    }
};
