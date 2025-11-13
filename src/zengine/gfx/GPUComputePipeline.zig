//!
//! The zengine gpu shader implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const sdl = @import("../sdl.zig");
const ui = @import("../ui.zig");
const Error = @import("error.zig").Error;
const GPUDevice = @import("GPUDevice.zig");
const GPUShader = @import("GPUShader.zig");
const GPUTexture = @import("GPUTexture.zig");
const types = @import("types.zig");

const log = std.log.scoped(.gfx_gpu_compute_pipeline);

ptr: ?*c.SDL_GPUComputePipeline = null,

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

    pub fn toSDL(self: *const @This(), gpa: std.mem.Allocator) !c.SDL_GPUComputePipelineCreateInfo {
        return .{
            // code_size: usize = @import("std").mem.zeroes(usize),
            // code: [*c]const Uint8 = @import("std").mem.zeroes([*c]const Uint8),
            // entrypoint: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
            // format: c.SDL_GPUShaderFormat = @import("std").mem.zeroes(SDL_GPUShaderFormat),
            // num_samplers: Uint32 = @import("std").mem.zeroes(Uint32),
            // num_readonly_storage_textures: Uint32 = @import("std").mem.zeroes(Uint32),
            // num_readonly_storage_buffers: Uint32 = @import("std").mem.zeroes(Uint32),
            // num_readwrite_storage_textures: Uint32 = @import("std").mem.zeroes(Uint32),
            // num_readwrite_storage_buffers: Uint32 = @import("std").mem.zeroes(Uint32),
            // num_uniform_buffers: Uint32 = @import("std").mem.zeroes(Uint32),
            // threadcount_x: Uint32 = @import("std").mem.zeroes(Uint32),
            // threadcount_y: Uint32 = @import("std").mem.zeroes(Uint32),
            // threadcount_z: Uint32 = @import("std").mem.zeroes(Uint32),
            .vertex_shader = self.vertex_shader.ptr,
            .fragment_shader = self.fragment_shader.ptr,
            .vertex_input_state = try self.vertex_input_state.toSDL(gpa),
            .primitive_type = @intFromEnum(self.primitive_type),
            .rasterizer_state = self.rasterizer_state.toSDL(),
            .multisample_state = self.multisample_state.toSDL(),
            .depth_stencil_state = self.depth_stencil_state.toSDL(),
        };
    }
};

pub fn init(gpu_device: GPUDevice, info: *const CreateInfo) !Self {
    return fromOwned(try create(gpu_device, info));
}

pub fn deinit(self: *Self, gpu_device: GPUDevice) void {
    if (self.isValid()) release(gpu_device, self.toOwned());
}

pub fn create(gpu_device: GPUDevice, info: *const CreateInfo) !*c.SDL_GPUComputePipeline {
    assert(gpu_device.isValid());
    var arena = allocators.initArena();
    defer arena.deinit();
    const sdl_info = try info.toSDL(arena.allocator());
    const ptr = c.SDL_CreateGPUComputePipeline(gpu_device.ptr, &sdl_info);
    if (ptr == null) {
        log.err("failed creating gpu graphics pipeline: {s}", .{c.SDL_GetError()});
        return Error.PipelineFailed;
    }
    return ptr.?;
}

pub fn release(gpu_device: GPUDevice, ptr: *c.SDL_GPUComputePipeline) void {
    assert(gpu_device.isValid());
    c.SDL_ReleaseGPUComputePipeline(gpu_device.ptr, ptr);
}

pub fn fromOwned(ptr: *c.SDL_GPUComputePipeline) Self {
    return .{ .ptr = ptr };
}

pub fn toOwned(self: *Self) *c.SDL_GPUComputePipeline {
    assert(self.isValid());
    defer self.ptr = null;
    return self.ptr.?;
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}
