//!
//! The zengine gpu texture implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");
const Error = @import("error.zig").Error;
const GPUDevice = @import("GPUDevice.zig");
const types = @import("types.zig");

const log = std.log.scoped(.gfx_gpu_texture);

ptr: ?*c.SDL_GPUTexture = null,

const Self = @This();
pub const invalid: Self = .{};

comptime {
    assert(@sizeOf(Self) == @sizeOf(*c.SDL_GPUTexture));
    assert(@alignOf(Self) == @alignOf(*c.SDL_GPUTexture));
}

pub const CreateInfo = struct {
    type: Type = .default,
    format: Format = .default,
    usage: UsageFlags = .initEmpty(),
    size: math.Point_u32,
    layer_count_or_depth: u32 = 1,
    num_levels: u32 = 1,
    sample_count: types.SampleCount = .default,
};

pub fn init(gpu_device: GPUDevice, info: *const CreateInfo) !Self {
    return fromOwned(try create(gpu_device, info));
}

pub fn deinit(self: *Self, gpu_device: GPUDevice) void {
    if (self.isValid()) release(gpu_device, self.toOwned());
}

pub fn create(gpu_device: GPUDevice, info: *const CreateInfo) !*c.SDL_GPUTexture {
    assert(gpu_device.isValid());
    const ptr = c.SDL_CreateGPUTexture(gpu_device.ptr, &c.SDL_GPUTextureCreateInfo{
        .type = @intFromEnum(info.type),
        .format = @intFromEnum(info.format),
        .usage = info.usage.bits.mask,
        .width = info.size[0],
        .height = info.size[1],
        .layer_count_or_depth = info.layer_count_or_depth,
        .num_levels = info.num_levels,
        .sample_count = @intFromEnum(info.sample_count),
    });
    if (ptr == null) {
        log.err("failed creating gpu texture: {s}", .{c.SDL_GetError()});
        return Error.TextureFailed;
    }
    return ptr.?;
}

pub fn release(gpu_device: GPUDevice, ptr: *c.SDL_GPUTexture) void {
    assert(gpu_device.isValid());
    c.SDL_ReleaseGPUTexture(gpu_device.ptr, ptr);
}

pub fn fromOwned(ptr: *c.SDL_GPUTexture) Self {
    return .{ .ptr = ptr };
}

pub fn toOwned(self: *Self) *c.SDL_GPUTexture {
    assert(self.isValid());
    defer self.ptr = null;
    return self.ptr.?;
}

pub fn toSDL(self: *const Self) *c.SDL_GPUTexture {
    assert(self.isValid());
    return self.ptr.?;
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}

pub const Location = struct {
    texture: Self = .invalid,
    mip_level: u32 = 0,
    layer: u32 = 0,
    x: u32 = 0,
    y: u32 = 0,
    z: u32 = 0,

    pub fn toSDL(self: *const @This()) c.SDL_GPUTextureLocation {
        assert(self.texture.isValid());
        return .{
            .texture = self.texture.ptr,
            .mip_level = self.mip_level,
            .layer = self.layer,
            .x = self.x,
            .y = self.y,
            .z = self.z,
        };
    }
};

pub const Region = struct {
    texture: Self = .invalid,
    mip_level: u32 = 0,
    layer: u32 = 0,
    x: u32 = 0,
    y: u32 = 0,
    z: u32 = 0,
    w: u32 = 0,
    h: u32 = 0,
    d: u32 = 0,

    pub fn toSDL(self: *const @This()) c.SDL_GPUTextureRegion {
        assert(self.texture.isValid());
        return .{
            .texture = self.texture.ptr,
            .mip_level = self.mip_level,
            .layer = self.layer,
            .x = self.x,
            .y = self.y,
            .z = self.z,
            .w = self.w,
            .h = self.h,
            .d = self.d,
        };
    }
};

pub const BlitRegion = struct {
    texture: Self = .invalid,
    mip_level: u32 = 0,
    layer_or_depth_plane: u32 = 0,
    x: u32 = 0,
    y: u32 = 0,
    w: u32 = 0,
    h: u32 = 0,

    pub fn toSDL(self: *const @This()) c.SDL_GPUBlitRegion {
        assert(self.texture.isValid());
        return .{
            .texture = self.texture.ptr,
            .mip_level = self.mip_level,
            .layer_or_depth_plane = self.layer_or_depth_plane,
            .x = self.x,
            .y = self.y,
            .w = self.w,
            .h = self.h,
        };
    }
};

pub const Type = enum(c.SDL_GPUTextureType) {
    @"2D" = c.SDL_GPU_TEXTURETYPE_2D,
    @"2D_array" = c.SDL_GPU_TEXTURETYPE_2D_ARRAY,
    @"3D" = c.SDL_GPU_TEXTURETYPE_3D,
    cube = c.SDL_GPU_TEXTURETYPE_CUBE,
    cube_array = c.SDL_GPU_TEXTURETYPE_CUBE_ARRAY,
    pub const default = .@"2D";
};

pub const Usage = enum(c.SDL_GPUTextureUsageFlags) {
    sampler = c.SDL_GPU_TEXTUREUSAGE_SAMPLER,
    color_target = c.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET,
    depth_stencil_target = c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
    graphics_storage_read = c.SDL_GPU_TEXTUREUSAGE_GRAPHICS_STORAGE_READ,
    compute_storage_read = c.SDL_GPU_TEXTUREUSAGE_COMPUTE_STORAGE_READ,
    compute_storage_write = c.SDL_GPU_TEXTUREUSAGE_COMPUTE_STORAGE_WRITE,
    compute_storage_read_write = c.SDL_GPU_TEXTUREUSAGE_COMPUTE_STORAGE_SIMULTANEOUS_READ_WRITE,
};
pub const UsageFlags = std.EnumSet(Usage);

pub const Format = enum(c.SDL_GPUTextureFormat) {
    invalid = c.SDL_GPU_TEXTUREFORMAT_INVALID,
    A8_unorm = c.SDL_GPU_TEXTUREFORMAT_A8_UNORM,
    R8_unorm = c.SDL_GPU_TEXTUREFORMAT_R8_UNORM,
    R8G8_unorm = c.SDL_GPU_TEXTUREFORMAT_R8G8_UNORM,
    R8G8B8A8_unorm = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
    R16_unorm = c.SDL_GPU_TEXTUREFORMAT_R16_UNORM,
    R16G16_unorm = c.SDL_GPU_TEXTUREFORMAT_R16G16_UNORM,
    R16G16B16A16_unorm = c.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_UNORM,
    R10G10B10A2_unorm = c.SDL_GPU_TEXTUREFORMAT_R10G10B10A2_UNORM,
    B5G6R5_unorm = c.SDL_GPU_TEXTUREFORMAT_B5G6R5_UNORM,
    B5G5R5A1_unorm = c.SDL_GPU_TEXTUREFORMAT_B5G5R5A1_UNORM,
    B4G4R4A4_unorm = c.SDL_GPU_TEXTUREFORMAT_B4G4R4A4_UNORM,
    B8G8R8A8_unorm = c.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM,
    BC1_RGBA_unorm = c.SDL_GPU_TEXTUREFORMAT_BC1_RGBA_UNORM,
    BC2_RGBA_unorm = c.SDL_GPU_TEXTUREFORMAT_BC2_RGBA_UNORM,
    BC3_RGBA_unorm = c.SDL_GPU_TEXTUREFORMAT_BC3_RGBA_UNORM,
    BC4_R_unorm = c.SDL_GPU_TEXTUREFORMAT_BC4_R_UNORM,
    BC5_RG_unorm = c.SDL_GPU_TEXTUREFORMAT_BC5_RG_UNORM,
    BC7_RGBA_unorm = c.SDL_GPU_TEXTUREFORMAT_BC7_RGBA_UNORM,
    BC6H_RGB_f = c.SDL_GPU_TEXTUREFORMAT_BC6H_RGB_FLOAT,
    BC6H_RGB_uf = c.SDL_GPU_TEXTUREFORMAT_BC6H_RGB_UFLOAT,
    R8_snorm = c.SDL_GPU_TEXTUREFORMAT_R8_SNORM,
    R8G8_snorm = c.SDL_GPU_TEXTUREFORMAT_R8G8_SNORM,
    R8G8B8A8_snorm = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_SNORM,
    R16_snorm = c.SDL_GPU_TEXTUREFORMAT_R16_SNORM,
    R16G16_snorm = c.SDL_GPU_TEXTUREFORMAT_R16G16_SNORM,
    R16G16B16A16_snorm = c.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_SNORM,
    R16_f = c.SDL_GPU_TEXTUREFORMAT_R16_FLOAT,
    R16G16_f = c.SDL_GPU_TEXTUREFORMAT_R16G16_FLOAT,
    R16G16B16A16_f = c.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT,
    R32_f = c.SDL_GPU_TEXTUREFORMAT_R32_FLOAT,
    R32G32_f = c.SDL_GPU_TEXTUREFORMAT_R32G32_FLOAT,
    R32G32B32A32_f = c.SDL_GPU_TEXTUREFORMAT_R32G32B32A32_FLOAT,
    R11G11B10_uf = c.SDL_GPU_TEXTUREFORMAT_R11G11B10_UFLOAT,
    R8_u = c.SDL_GPU_TEXTUREFORMAT_R8_UINT,
    R8G8_u = c.SDL_GPU_TEXTUREFORMAT_R8G8_UINT,
    R8G8B8A8_u = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UINT,
    R16_u = c.SDL_GPU_TEXTUREFORMAT_R16_UINT,
    R16G16_u = c.SDL_GPU_TEXTUREFORMAT_R16G16_UINT,
    R16G16B16A16_u = c.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_UINT,
    R32_u = c.SDL_GPU_TEXTUREFORMAT_R32_UINT,
    R32G32_u = c.SDL_GPU_TEXTUREFORMAT_R32G32_UINT,
    R32G32B32A32_u = c.SDL_GPU_TEXTUREFORMAT_R32G32B32A32_UINT,
    R8_I = c.SDL_GPU_TEXTUREFORMAT_R8_INT,
    R8G8_i = c.SDL_GPU_TEXTUREFORMAT_R8G8_INT,
    R8G8B8A8_i = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_INT,
    R16_i = c.SDL_GPU_TEXTUREFORMAT_R16_INT,
    R16G16_i = c.SDL_GPU_TEXTUREFORMAT_R16G16_INT,
    R16_G16_B16_A16_i = c.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_INT,
    R32_j = c.SDL_GPU_TEXTUREFORMAT_R32_INT,
    R32G32_i = c.SDL_GPU_TEXTUREFORMAT_R32G32_INT,
    R32G32B32A32_i = c.SDL_GPU_TEXTUREFORMAT_R32G32B32A32_INT,
    R8G8B8A8_unorm_sRGB = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB,
    B8R8G8A8_unorm_sRGB = c.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM_SRGB,
    BC1_RGBA_unorm_sRGB = c.SDL_GPU_TEXTUREFORMAT_BC1_RGBA_UNORM_SRGB,
    BC2_RGBA_unorm_sRGB = c.SDL_GPU_TEXTUREFORMAT_BC2_RGBA_UNORM_SRGB,
    BC3_RGBA_unorm_sRGB = c.SDL_GPU_TEXTUREFORMAT_BC3_RGBA_UNORM_SRGB,
    BC7_RGBA_unorm_sRGB = c.SDL_GPU_TEXTUREFORMAT_BC7_RGBA_UNORM_SRGB,
    D16_unorm = c.SDL_GPU_TEXTUREFORMAT_D16_UNORM,
    D24_unorm = c.SDL_GPU_TEXTUREFORMAT_D24_UNORM,
    D32_f = c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT,
    D24_unorm_S8_u = c.SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT,
    D32_f_S8_u = c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT_S8_UINT,
    ASTC_4x4_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_4x4_UNORM,
    ASTC_5x4_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_5x4_UNORM,
    ASTC_5x5_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_5x5_UNORM,
    ASTC_6x5_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_6x5_UNORM,
    ASTC_6x6_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_6x6_UNORM,
    ASTC_9x5_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_8x5_UNORM,
    ASTC_8x6_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_8x6_UNORM,
    ASTC_8x8_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_8x8_UNORM,
    ASTC_10x5_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x5_UNORM,
    ASTC_10x6_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x6_UNORM,
    ASTC_10x8_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x8_UNORM,
    ASTC_10x10_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x10_UNORM,
    ASTC_12x10_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_12x10_UNORM,
    ASTC_12x12_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_12x12_UNORM,
    ASTC_4x4_unorm_sRGB = c.SDL_GPU_TEXTUREFORMAT_ASTC_4x4_UNORM_SRGB,
    ASTC_5x4_unorm_sRGB = c.SDL_GPU_TEXTUREFORMAT_ASTC_5x4_UNORM_SRGB,
    ASTC_5x5_unorm_sRGB = c.SDL_GPU_TEXTUREFORMAT_ASTC_5x5_UNORM_SRGB,
    ASTC_6x5_unorm_sRGB = c.SDL_GPU_TEXTUREFORMAT_ASTC_6x5_UNORM_SRGB,
    ASTC_6x6_unorm_sRGB = c.SDL_GPU_TEXTUREFORMAT_ASTC_6x6_UNORM_SRGB,
    ASTC_9x5_unorm_sRGB = c.SDL_GPU_TEXTUREFORMAT_ASTC_8x5_UNORM_SRGB,
    ASTC_8x6_unorm_sRGB = c.SDL_GPU_TEXTUREFORMAT_ASTC_8x6_UNORM_SRGB,
    ASTC_8x8_unorm_sRGB = c.SDL_GPU_TEXTUREFORMAT_ASTC_8x8_UNORM_SRGB,
    ASTC_10x5_unorm_sRGB = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x5_UNORM_SRGB,
    ASTC_10x6_unorm_sRGB = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x6_UNORM_SRGB,
    ASTC_10x8_unorm_sRGB = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x8_UNORM_SRGB,
    ASTC_10x10_unorm_sRGB = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x10_UNORM_SRGB,
    ASTC_12x10_unorm_sRGB = c.SDL_GPU_TEXTUREFORMAT_ASTC_12x10_UNORM_SRGB,
    ASTC_12x12_unorm_sRGB = c.SDL_GPU_TEXTUREFORMAT_ASTC_12x12_UNORM_SRGB,
    ASTC_4x4_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_4x4_FLOAT,
    ASTC_5x4_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_5x4_FLOAT,
    ASTC_5x5_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_5x5_FLOAT,
    ASTC_6x5_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_6x5_FLOAT,
    ASTC_6x6_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_6x6_FLOAT,
    ASTC_9x5_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_8x5_FLOAT,
    ASTC_8x6_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_8x6_FLOAT,
    ASTC_8x8_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_8x8_FLOAT,
    ASTC_10x5_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x5_FLOAT,
    ASTC_10x6_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x6_FLOAT,
    ASTC_10x8_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x8_FLOAT,
    ASTC_10x10_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x10_FLOAT,
    ASTC_12x10_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_12x10_FLOAT,
    ASTC_12x12_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_12x12_FLOAT,
    pub const default: Format = .R8G8B8A8_unorm;
    pub const hdr_f: Format = .R16G16B16A16_f;
};
