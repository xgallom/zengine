//!
//! The zengine surface implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");
const GPUTexture = @import("GPUTexture.zig");

const log = std.log.scoped(.gfx_surface_texture);

ptr: ?*c.SDL_GPUSampler = null,

const Self = @This();
pub const invalid: Self = .{};

pub const CreateInfo = struct {
    min_filter: Filter = .default,
    mag_filter: Filter = .default,
    mipmap_mode: MipMapMode = .default,
    address_mode_u: AddressMode = .default,
    address_mode_v: AddressMode = .default,
    address_mode_w: AddressMode = .default,
    mip_lod_bias: f32 = 0,
    max_anisotropy: f32 = 0,
    compare_op: CompareOp = .default,
    min_lod: f32 = 0,
    max_lod: f32 = 0,
    enable_anisotropy: bool = false,
    enable_compare: bool = false,
    // props: c.SDL_PropertiesID = @import("std").mem.zeroes(SDL_PropertiesID),
};

pub fn init(gpu_device: ?*c.SDL_GPUDevice, info: *const CreateInfo) !Self {
    return fromOwnedGPUSampler(try create(gpu_device, info));
}

pub fn deinit(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
    if (self.ptr != null) release(gpu_device, self.toOwnedGPUSampler());
}

pub fn create(gpu_device: ?*c.SDL_GPUDevice, info: *const CreateInfo) !*c.SDL_GPUSampler {
    const ptr = c.SDL_CreateGPUSampler(gpu_device, &c.SDL_GPUSamplerCreateInfo{
        .min_filter = @intFromEnum(info.min_filter),
        .mag_filter = @intFromEnum(info.mag_filter),
        .mipmap_mode = @intFromEnum(info.mipmap_mode),
        .address_mode_u = @intFromEnum(info.address_mode_u),
        .address_mode_v = @intFromEnum(info.address_mode_v),
        .address_mode_w = @intFromEnum(info.address_mode_w),
        .mip_lod_bias = info.mip_lod_bias,
        .max_anisotropy = info.max_anisotropy,
        .compare_op = @intFromEnum(info.compare_op),
        .min_lod = info.min_lod,
        .max_lod = info.max_lod,
        .enable_anisotropy = info.enable_anisotropy,
        .enable_compare = info.enable_compare,
    });
    if (ptr == null) {
        log.err("failed creating sampler: {s}", .{c.SDL_GetError()});
        return error.SurfaceFailed;
    }
    return ptr.?;
}

pub fn release(gpu_device: ?*c.SDL_GPUDevice, ptr: *c.SDL_GPUSampler) void {
    c.SDL_ReleaseGPUSampler(gpu_device, ptr);
}

pub fn fromOwnedGPUSampler(ptr: *c.SDL_GPUSampler) Self {
    return .{ .ptr = ptr };
}

pub fn toOwnedGPUSampler(self: *Self) *c.SDL_GPUSampler {
    assert(self.ptr != null);
    defer self.ptr = null;
    return self.ptr.?;
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}

pub const Filter = enum(c.SDL_GPUFilter) {
    nearest = c.SDL_GPU_FILTER_NEAREST,
    linear = c.SDL_GPU_FILTER_LINEAR,
    pub const default = .nearest;
};

pub const MipMapMode = enum(c.SDL_GPUSamplerMipmapMode) {
    nearest = c.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
    linear = c.SDL_GPU_SAMPLERMIPMAPMODE_LINEAR,
    pub const default = .nearest;
};

pub const AddressMode = enum(c.SDL_GPUSamplerAddressMode) {
    repeat = c.SDL_GPU_SAMPLERADDRESSMODE_REPEAT,
    mirrored_repeat = c.SDL_GPU_SAMPLERADDRESSMODE_MIRRORED_REPEAT,
    clamp_to_edge = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
    pub const default = .repeat;
};
pub const CompareOp = enum(c.SDL_GPUCompareOp) {
    invalid = c.SDL_GPU_COMPAREOP_INVALID,
    never = c.SDL_GPU_COMPAREOP_NEVER,
    less = c.SDL_GPU_COMPAREOP_LESS,
    equal = c.SDL_GPU_COMPAREOP_EQUAL,
    less_or_equal = c.SDL_GPU_COMPAREOP_LESS_OR_EQUAL,
    greater = c.SDL_GPU_COMPAREOP_GREATER,
    not_equal = c.SDL_GPU_COMPAREOP_NOT_EQUAL,
    greater_or_equal = c.SDL_GPU_COMPAREOP_GREATER_OR_EQUAL,
    always = c.SDL_GPU_COMPAREOP_ALWAYS,
    pub const default = .invalid;
};
