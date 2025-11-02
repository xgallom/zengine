//!
//! The zengine gpu sampler implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");
const Error = @import("Error.zig").Error;
const GPUDevice = @import("GPUDevice.zig");
const types = @import("types.zig");

const log = std.log.scoped(.gfx_gpu_sampler);

ptr: ?*c.SDL_GPUSampler = null,

const Self = @This();
pub const invalid: Self = .{};

comptime {
    assert(@sizeOf(Self) == @sizeOf(*c.SDL_GPUSampler));
    assert(@alignOf(Self) == @alignOf(*c.SDL_GPUSampler));
}

pub const CreateInfo = struct {
    min_filter: types.Filter = .default,
    mag_filter: types.Filter = .default,
    mipmap_mode: MipMapMode = .default,
    address_mode_u: AddressMode = .default,
    address_mode_v: AddressMode = .default,
    address_mode_w: AddressMode = .default,
    mip_lod_bias: f32 = 0,
    max_anisotropy: f32 = 0,
    compare_op: types.CompareOp = .default,
    min_lod: f32 = 0,
    max_lod: f32 = 0,
    enable_anisotropy: bool = false,
    enable_compare: bool = false,
    // props: c.SDL_PropertiesID = @import("std").mem.zeroes(SDL_PropertiesID),
};

pub fn init(gpu_device: GPUDevice, info: *const CreateInfo) !Self {
    return fromOwned(try create(gpu_device, info));
}

pub fn deinit(self: *Self, gpu_device: GPUDevice) void {
    if (self.isValid()) release(gpu_device, self.toOwned());
}

pub fn create(gpu_device: GPUDevice, info: *const CreateInfo) !*c.SDL_GPUSampler {
    assert(gpu_device.isValid());
    const ptr = c.SDL_CreateGPUSampler(gpu_device.ptr, &c.SDL_GPUSamplerCreateInfo{
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
        log.err("failed creating gpu sampler: {s}", .{c.SDL_GetError()});
        return Error.SurfaceFailed;
    }
    return ptr.?;
}

pub fn release(gpu_device: GPUDevice, ptr: *c.SDL_GPUSampler) void {
    assert(gpu_device.isValid());
    c.SDL_ReleaseGPUSampler(gpu_device.ptr, ptr);
}

pub fn fromOwned(ptr: *c.SDL_GPUSampler) Self {
    return .{ .ptr = ptr };
}

pub fn toOwned(self: *Self) *c.SDL_GPUSampler {
    assert(self.isValid());
    defer self.ptr = null;
    return self.ptr.?;
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}

pub const FilterMode = enum {
    nearest,
    linear,
    bilinear,
    trilinear,

    const Config = struct {
        filter: types.Filter,
        mipmap_mode: MipMapMode,
    };

    const configs: std.EnumArray(FilterMode, Config) = .init(.{
        .nearest = .{ .filter = .nearest, .mipmap_mode = .nearest },
        .linear = .{ .filter = .linear, .mipmap_mode = .nearest },
        .bilinear = .{ .filter = .nearest, .mipmap_mode = .linear },
        .trilinear = .{ .filter = .linear, .mipmap_mode = .linear },
    });

    pub fn config(mode: FilterMode) Config {
        return configs.get(mode);
    }
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
