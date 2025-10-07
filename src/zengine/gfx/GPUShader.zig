//!
//! The zengine gpu shader implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");
const Error = @import("Error.zig").Error;
const GPUDevice = @import("GPUDevice.zig");

const log = std.log.scoped(.gfx_gpu_shader);

ptr: ?*c.SDL_GPUShader = null,

const Self = @This();
pub const invalid: Self = .{};

pub const CreateInfo = struct {
    code: []const u8,
    entry_point: [:0]const u8,
    format: Format = .default,
    stage: Stage = .default,
    num_samplers: u32 = 0,
    num_storage_textures: u32 = 0,
    num_storage_buffers: u32 = 0,
    num_uniform_buffers: u32 = 0,
};

pub fn init(gpu_device: GPUDevice, info: *const CreateInfo) !Self {
    return fromOwnedGPUShader(try create(gpu_device, info));
}

pub fn deinit(self: *Self, gpu_device: GPUDevice) void {
    if (self.ptr != null) destroy(gpu_device, self.toOwnedGPUShader());
}

fn create(gpu_device: GPUDevice, info: *const CreateInfo) !*c.SDL_GPUShader {
    const ptr = c.SDL_CreateGPUShader(gpu_device.ptr, &c.SDL_GPUShaderCreateInfo{
        .code = info.code.ptr,
        .code_size = info.code.len,
        .entrypoint = info.entry_point.ptr,
        .format = @intFromEnum(info.format),
        .stage = @intFromEnum(info.stage),
        .num_samplers = info.num_samplers,
        .num_storage_textures = info.num_storage_textures,
        .num_storage_buffers = info.num_storage_buffers,
        .num_uniform_buffers = info.num_uniform_buffers,
    });
    if (ptr == null) {
        log.err("failed creating gpu shader: {s}", .{c.SDL_GetError()});
        return Error.TextureFailed;
    }
    return ptr.?;
}

fn destroy(gpu_device: GPUDevice, ptr: *c.SDL_GPUShader) void {
    c.SDL_ReleaseGPUShader(gpu_device.ptr, ptr);
}

pub fn fromOwnedGPUShader(ptr: *c.SDL_GPUShader) Self {
    return .{ .ptr = ptr };
}

pub fn toOwnedGPUShader(self: *Self) *c.SDL_GPUShader {
    assert(self.ptr != null);
    defer self.ptr = null;
    return self.ptr.?;
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}

pub const Stage = enum(c.SDL_GPUShaderStage) {
    vertex = c.SDL_GPU_SHADERSTAGE_VERTEX,
    fragment = c.SDL_GPU_SHADERSTAGE_FRAGMENT,
    pub const default = .vertex;
};

pub const Format = enum(c.SDL_GPUShaderFormat) {
    invalid = c.SDL_GPU_SHADERFORMAT_INVALID,
    private = c.SDL_GPU_SHADERFORMAT_PRIVATE,
    spirv = c.SDL_GPU_SHADERFORMAT_SPIRV,
    dxbc = c.SDL_GPU_SHADERFORMAT_DXBC,
    dxil = c.SDL_GPU_SHADERFORMAT_DXIL,
    msl = c.SDL_GPU_SHADERFORMAT_MSL,
    metallib = c.SDL_GPU_SHADERFORMAT_METALLIB,
    pub const default = .invalid;
};
pub const FormatFlags = std.EnumSet(enum { private, spirv, dxbc, dxil, msl, metallib });
