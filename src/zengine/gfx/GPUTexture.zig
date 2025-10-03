//!
//! The zengine texture implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");

const log = std.log.scoped(.gfx_ptrture);

ptr: ?*c.SDL_GPUTexture = null,

const Self = @This();
pub const UsageFlags = std.EnumSet(Usage);

pub const State = enum {
    invalid,
    valid,
};

pub const CreateInfo = struct {
    type: Type = .default,
    format: Format = .default,
    usage: UsageFlags,
    size: math.Pointu32,
};

pub const invalid: Self = .{};

pub fn init(gpu_device: ?*c.SDL_GPUDevice, info: *const CreateInfo) !Self {
    var self: Self = .invalid;
    try self.createGPUTexture(gpu_device, info);
    return self;
}

pub fn deinit(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
    if (self.ptr != null) self.releaseGPUTexture(gpu_device);
}

pub fn fromOwnedGPUTexture(ptr: *c.SDL_GPUTexture) Self {
    return .{ .ptr = ptr };
}

pub fn toOwnedGPUTexture(self: *Self) *c.SDL_GPUTexture {
    assert(self.ptr != null);
    defer self.ptr = null;
    return self.ptr.?;
}

pub fn createGPUTexture(self: *Self, gpu_device: ?*c.SDL_GPUDevice, info: *const CreateInfo) !void {
    assert(self.ptr == null);
    self.ptr = c.SDL_CreateGPUTexture(gpu_device, &c.SDL_GPUTextureCreateInfo{
        .type = @intFromEnum(info.type),
        .format = @intFromEnum(info.format),
        .usage = info.usage.bits.mask,
        .width = info.size[0],
        .height = info.size[1],
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = c.SDL_GPU_SAMPLECOUNT_1,
    });
    if (self.ptr == null) {
        log.err("failed creating texture: {s}", .{c.SDL_GetError()});
        return error.TextureFailed;
    }
}

pub fn releaseGPUTexture(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
    assert(self.ptr != null);
    c.SDL_ReleaseGPUTexture(gpu_device, self.ptr);
    self.ptr = null;
}

pub inline fn state(self: Self) State {
    return if (self.ptr != null) .valid else .invalid;
}

pub const Type = enum(c.SDL_GPUTextureType) {
    type_2d = c.SDL_GPU_TEXTURETYPE_2D,
    typ_2D_array = c.SDL_GPU_TEXTURETYPE_2D_ARRAY,
    type_3D = c.SDL_GPU_TEXTURETYPE_3D,
    type_cube = c.SDL_GPU_TEXTURETYPE_CUBE,
    type_cube_array = c.SDL_GPU_TEXTURETYPE_CUBE_ARRAY,
    pub const default = .type_2d;
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

pub const Format = enum(c.SDL_GPUTextureFormat) {
    invalid = c.SDL_GPU_TEXTUREFORMAT_INVALID,
    a8_unorm = c.SDL_GPU_TEXTUREFORMAT_A8_UNORM,
    r8_unorm = c.SDL_GPU_TEXTUREFORMAT_R8_UNORM,
    r8g8_unorm = c.SDL_GPU_TEXTUREFORMAT_R8G8_UNORM,
    r8g8b8a8_unorm = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
    r16_unorm = c.SDL_GPU_TEXTUREFORMAT_R16_UNORM,
    r16g16_unorm = c.SDL_GPU_TEXTUREFORMAT_R16G16_UNORM,
    r16g16b16a16_unorm = c.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_UNORM,
    r10g10b10a2_unorm = c.SDL_GPU_TEXTUREFORMAT_R10G10B10A2_UNORM,
    b5g6r5_unorm = c.SDL_GPU_TEXTUREFORMAT_B5G6R5_UNORM,
    b5g5r5a1_unorm = c.SDL_GPU_TEXTUREFORMAT_B5G5R5A1_UNORM,
    b4g4r4a4_unorm = c.SDL_GPU_TEXTUREFORMAT_B4G4R4A4_UNORM,
    b8g8r8a8_unorm = c.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM,
    bc1_rgba_unorm = c.SDL_GPU_TEXTUREFORMAT_BC1_RGBA_UNORM,
    bc2_rgba_unorm = c.SDL_GPU_TEXTUREFORMAT_BC2_RGBA_UNORM,
    bc3_rgba_unorm = c.SDL_GPU_TEXTUREFORMAT_BC3_RGBA_UNORM,
    bc4_r_unorm = c.SDL_GPU_TEXTUREFORMAT_BC4_R_UNORM,
    bc5_rg_unorm = c.SDL_GPU_TEXTUREFORMAT_BC5_RG_UNORM,
    bc7_rgba_unorm = c.SDL_GPU_TEXTUREFORMAT_BC7_RGBA_UNORM,
    bc6h_rgb_f = c.SDL_GPU_TEXTUREFORMAT_BC6H_RGB_FLOAT,
    bc6h_rgb_uf = c.SDL_GPU_TEXTUREFORMAT_BC6H_RGB_UFLOAT,
    r8_snorm = c.SDL_GPU_TEXTUREFORMAT_R8_SNORM,
    r8g8_snorm = c.SDL_GPU_TEXTUREFORMAT_R8G8_SNORM,
    r8g8b8a8_snorm = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_SNORM,
    r16_snorm = c.SDL_GPU_TEXTUREFORMAT_R16_SNORM,
    r16g16_snorm = c.SDL_GPU_TEXTUREFORMAT_R16G16_SNORM,
    r16g16b16a16_snorm = c.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_SNORM,
    r16_f = c.SDL_GPU_TEXTUREFORMAT_R16_FLOAT,
    r16g16_f = c.SDL_GPU_TEXTUREFORMAT_R16G16_FLOAT,
    r16g16b16a16_f = c.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_FLOAT,
    r32_f = c.SDL_GPU_TEXTUREFORMAT_R32_FLOAT,
    r32g32_f = c.SDL_GPU_TEXTUREFORMAT_R32G32_FLOAT,
    r32g32b32a32_f = c.SDL_GPU_TEXTUREFORMAT_R32G32B32A32_FLOAT,
    r11g11b10_uf = c.SDL_GPU_TEXTUREFORMAT_R11G11B10_UFLOAT,
    r8_u = c.SDL_GPU_TEXTUREFORMAT_R8_UINT,
    r8g8_u = c.SDL_GPU_TEXTUREFORMAT_R8G8_UINT,
    r8g8b8a8_u = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UINT,
    r16_u = c.SDL_GPU_TEXTUREFORMAT_R16_UINT,
    r16g16_u = c.SDL_GPU_TEXTUREFORMAT_R16G16_UINT,
    r16g16b16a16_u = c.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_UINT,
    r32_u = c.SDL_GPU_TEXTUREFORMAT_R32_UINT,
    r32g32_u = c.SDL_GPU_TEXTUREFORMAT_R32G32_UINT,
    r32g32b32a32_u = c.SDL_GPU_TEXTUREFORMAT_R32G32B32A32_UINT,
    r8_i = c.SDL_GPU_TEXTUREFORMAT_R8_INT,
    r8g8_i = c.SDL_GPU_TEXTUREFORMAT_R8G8_INT,
    r8g8b8a8_i = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_INT,
    r16_i = c.SDL_GPU_TEXTUREFORMAT_R16_INT,
    r16g16_i = c.SDL_GPU_TEXTUREFORMAT_R16G16_INT,
    r16_g16_b16_a16_i = c.SDL_GPU_TEXTUREFORMAT_R16G16B16A16_INT,
    r32_j = c.SDL_GPU_TEXTUREFORMAT_R32_INT,
    r32g32_i = c.SDL_GPU_TEXTUREFORMAT_R32G32_INT,
    r32g32b32a32_i = c.SDL_GPU_TEXTUREFORMAT_R32G32B32A32_INT,
    r8g8b8a8_unorm_srgb = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM_SRGB,
    b8r8g8a8_unorm_srgb = c.SDL_GPU_TEXTUREFORMAT_B8G8R8A8_UNORM_SRGB,
    bc1_rgba_unorm_srgb = c.SDL_GPU_TEXTUREFORMAT_BC1_RGBA_UNORM_SRGB,
    bc2_rgba_unorm_srgb = c.SDL_GPU_TEXTUREFORMAT_BC2_RGBA_UNORM_SRGB,
    bc3_rgba_unorm_srgb = c.SDL_GPU_TEXTUREFORMAT_BC3_RGBA_UNORM_SRGB,
    bc7_rgba_unorm_srgb = c.SDL_GPU_TEXTUREFORMAT_BC7_RGBA_UNORM_SRGB,
    d16_unorm = c.SDL_GPU_TEXTUREFORMAT_D16_UNORM,
    d24_unorm = c.SDL_GPU_TEXTUREFORMAT_D24_UNORM,
    d32_f = c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT,
    d24_unorm_s8_u = c.SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT,
    d32_f_s8_u = c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT_S8_UINT,
    astc_4x4_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_4x4_UNORM,
    astc_5x4_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_5x4_UNORM,
    astc_5x5_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_5x5_UNORM,
    astc_6x5_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_6x5_UNORM,
    astc_6x6_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_6x6_UNORM,
    astc_9x5_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_8x5_UNORM,
    astc_8x6_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_8x6_UNORM,
    astc_8x8_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_8x8_UNORM,
    astc_10x5_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x5_UNORM,
    astc_10x6_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x6_UNORM,
    astc_10x8_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x8_UNORM,
    astc_10x10_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x10_UNORM,
    astc_12x10_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_12x10_UNORM,
    astc_12x12_unorm = c.SDL_GPU_TEXTUREFORMAT_ASTC_12x12_UNORM,
    astc_4x4_unorm_srgb = c.SDL_GPU_TEXTUREFORMAT_ASTC_4x4_UNORM_SRGB,
    astc_5x4_unorm_srgb = c.SDL_GPU_TEXTUREFORMAT_ASTC_5x4_UNORM_SRGB,
    astc_5x5_unorm_srgb = c.SDL_GPU_TEXTUREFORMAT_ASTC_5x5_UNORM_SRGB,
    astc_6x5_unorm_srgb = c.SDL_GPU_TEXTUREFORMAT_ASTC_6x5_UNORM_SRGB,
    astc_6x6_unorm_srgb = c.SDL_GPU_TEXTUREFORMAT_ASTC_6x6_UNORM_SRGB,
    astc_9x5_unorm_srgb = c.SDL_GPU_TEXTUREFORMAT_ASTC_8x5_UNORM_SRGB,
    astc_8x6_unorm_srgb = c.SDL_GPU_TEXTUREFORMAT_ASTC_8x6_UNORM_SRGB,
    astc_8x8_unorm_srgb = c.SDL_GPU_TEXTUREFORMAT_ASTC_8x8_UNORM_SRGB,
    astc_10x5_unorm_srgb = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x5_UNORM_SRGB,
    astc_10x6_unorm_srgb = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x6_UNORM_SRGB,
    astc_10x8_unorm_srgb = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x8_UNORM_SRGB,
    astc_10x10_unorm_srgb = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x10_UNORM_SRGB,
    astc_12x10_unorm_srgb = c.SDL_GPU_TEXTUREFORMAT_ASTC_12x10_UNORM_SRGB,
    astc_12x12_unorm_srgb = c.SDL_GPU_TEXTUREFORMAT_ASTC_12x12_UNORM_SRGB,
    astc_4x4_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_4x4_FLOAT,
    astc_5x4_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_5x4_FLOAT,
    astc_5x5_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_5x5_FLOAT,
    astc_6x5_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_6x5_FLOAT,
    astc_6x6_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_6x6_FLOAT,
    astc_9x5_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_8x5_FLOAT,
    astc_8x6_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_8x6_FLOAT,
    astc_8x8_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_8x8_FLOAT,
    astc_10x5_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x5_FLOAT,
    astc_10x6_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x6_FLOAT,
    astc_10x8_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x8_FLOAT,
    astc_10x10_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_10x10_FLOAT,
    astc_12x10_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_12x10_FLOAT,
    astc_12x12_f = c.SDL_GPU_TEXTUREFORMAT_ASTC_12x12_FLOAT,
    pub const default = .r8g8b8a8_unorm;
};
