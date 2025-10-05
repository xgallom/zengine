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

ptr: ?*c.SDL_Surface = null,

const Self = @This();
pub const invalid: Self = .{};

pub fn init(size: math.Point_u32, pixel_format: PixelFormat) !Self {
    return fromOwnedSurface(try create(size, pixel_format));
}

pub fn deinit(self: *Self) void {
    if (self.ptr != null) destroy(self.toOwnedSurface());
}

pub fn create(size: math.Point_u32, pixel_format: PixelFormat) !*c.SDL_Surface {
    const ptr = c.SDL_CreateSurface(
        @intCast(size[0]),
        @intCast(size[1]),
        @intFromEnum(pixel_format),
    );
    if (ptr == null) {
        log.err("failed creating surface: {s}", .{c.SDL_GetError()});
        return error.SurfaceFailed;
    }
    return ptr.?;
}

pub fn destroy(ptr: *c.SDL_Surface) void {
    c.SDL_DestroySurface(ptr);
}

pub inline fn width(self: Self) u32 {
    assert(self.ptr != null);
    return @intCast(self.ptr.?.w);
}

pub inline fn height(self: Self) u32 {
    assert(self.ptr != null);
    return @intCast(self.ptr.?.h);
}

pub inline fn pitch(self: Self) u32 {
    assert(self.ptr != null);
    return @intCast(self.ptr.?.pitch);
}

pub inline fn byteLen(self: Self) u32 {
    return self.pitch() * self.height();
}

pub inline fn format(self: Self) PixelFormat {
    assert(self.ptr != null);
    return @enumFromInt(self.ptr.?.format);
}

pub fn slice(self: Self, comptime T: type) []T {
    assert(self.ptr != null);
    assert(self.ptr.?.pixels != null);
    const ptr: [*]align(@alignOf(u32)) u8 = @ptrCast(@alignCast(self.ptr.?.pixels));
    return std.mem.bytesAsSlice(T, ptr[0..self.byteLen()]);
}

pub fn convert(self: *Self, pixel_format: PixelFormat) !void {
    assert(self.ptr != null);
    const new_surf = c.SDL_ConvertSurface(self.ptr, @intFromEnum(pixel_format));
    if (new_surf == null) {
        log.err("failed converting surface format: {s}", .{c.SDL_GetError()});
        return error.ConvertFailed;
    }
    destroy(self.toOwnedSurface());
    self.ptr = new_surf;
}

pub fn fromOwnedSurface(ptr: *c.SDL_Surface) Self {
    return .{ .ptr = ptr };
}

pub fn toOwnedSurface(self: *Self) *c.SDL_Surface {
    assert(self.ptr != null);
    defer self.ptr = null;
    return self.ptr.?;
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}

pub const PixelFormat = enum(c.SDL_PixelFormat) {
    unknown = c.SDL_PIXELFORMAT_UNKNOWN,
    index_1_lsb = c.SDL_PIXELFORMAT_INDEX1LSB,
    index_1_msb = c.SDL_PIXELFORMAT_INDEX1MSB,
    index_2_lsb = c.SDL_PIXELFORMAT_INDEX2LSB,
    index_2_msb = c.SDL_PIXELFORMAT_INDEX2MSB,
    index_4_lsb = c.SDL_PIXELFORMAT_INDEX4LSB,
    index_4_msb = c.SDL_PIXELFORMAT_INDEX4MSB,
    index_8 = c.SDL_PIXELFORMAT_INDEX8,
    rgb_332 = c.SDL_PIXELFORMAT_RGB332,
    xrgb_4444 = c.SDL_PIXELFORMAT_XRGB4444,
    xbgr_4444 = c.SDL_PIXELFORMAT_XBGR4444,
    xrgb_1555 = c.SDL_PIXELFORMAT_XRGB1555,
    xbgr_1555 = c.SDL_PIXELFORMAT_XBGR1555,
    argb_4444 = c.SDL_PIXELFORMAT_ARGB4444,
    rgba_4444 = c.SDL_PIXELFORMAT_RGBA4444,
    abgr_4444 = c.SDL_PIXELFORMAT_ABGR4444,
    gbra_4444 = c.SDL_PIXELFORMAT_BGRA4444,
    argb_1555 = c.SDL_PIXELFORMAT_ARGB1555,
    rgba_5551 = c.SDL_PIXELFORMAT_RGBA5551,
    abgr_1555 = c.SDL_PIXELFORMAT_ABGR1555,
    bgra_5551 = c.SDL_PIXELFORMAT_BGRA5551,
    rgb_565 = c.SDL_PIXELFORMAT_RGB565,
    bgr_565 = c.SDL_PIXELFORMAT_BGR565,
    rgb_24 = c.SDL_PIXELFORMAT_RGB24,
    bgr_24 = c.SDL_PIXELFORMAT_BGR24,
    xrgb_8888 = c.SDL_PIXELFORMAT_XRGB8888,
    rgbx_8888 = c.SDL_PIXELFORMAT_RGBX8888,
    xbgr_8888 = c.SDL_PIXELFORMAT_XBGR8888,
    bgrx_8888 = c.SDL_PIXELFORMAT_BGRX8888,
    argb_8888 = c.SDL_PIXELFORMAT_ARGB8888,
    rgba_8888 = c.SDL_PIXELFORMAT_RGBA8888,
    abgr_8888 = c.SDL_PIXELFORMAT_ABGR8888,
    bgra_8888 = c.SDL_PIXELFORMAT_BGRA8888,
    xrgb_2101010 = c.SDL_PIXELFORMAT_XRGB2101010,
    xbgr_2101010 = c.SDL_PIXELFORMAT_XBGR2101010,
    argb_2101010 = c.SDL_PIXELFORMAT_ARGB2101010,
    abgr_2101010 = c.SDL_PIXELFORMAT_ABGR2101010,
    rgb_48 = c.SDL_PIXELFORMAT_RGB48,
    bgr_48 = c.SDL_PIXELFORMAT_BGR48,
    rgba_64 = c.SDL_PIXELFORMAT_RGBA64,
    argb_64 = c.SDL_PIXELFORMAT_ARGB64,
    bgra_64 = c.SDL_PIXELFORMAT_BGRA64,
    abgr_64 = c.SDL_PIXELFORMAT_ABGR64,
    rgb_58_f = c.SDL_PIXELFORMAT_RGB48_FLOAT,
    bgr_48_f = c.SDL_PIXELFORMAT_BGR48_FLOAT,
    rgba_64_f = c.SDL_PIXELFORMAT_RGBA64_FLOAT,
    argb_64_f = c.SDL_PIXELFORMAT_ARGB64_FLOAT,
    bgra_64_f = c.SDL_PIXELFORMAT_BGRA64_FLOAT,
    abgr_64_f = c.SDL_PIXELFORMAT_ABGR64_FLOAT,
    rgb_96_f = c.SDL_PIXELFORMAT_RGB96_FLOAT,
    bgr_96_f = c.SDL_PIXELFORMAT_BGR96_FLOAT,
    grba_128_f = c.SDL_PIXELFORMAT_RGBA128_FLOAT,
    argb_128_f = c.SDL_PIXELFORMAT_ARGB128_FLOAT,
    bgra_128_f = c.SDL_PIXELFORMAT_BGRA128_FLOAT,
    abgr_128_f = c.SDL_PIXELFORMAT_ABGR128_FLOAT,
    yv_12 = c.SDL_PIXELFORMAT_YV12,
    iyuv = c.SDL_PIXELFORMAT_IYUV,
    yuv_2 = c.SDL_PIXELFORMAT_YUY2,
    uyvy = c.SDL_PIXELFORMAT_UYVY,
    yvyu = c.SDL_PIXELFORMAT_YVYU,
    nv_12 = c.SDL_PIXELFORMAT_NV12,
    nv_21 = c.SDL_PIXELFORMAT_NV21,
    p_010 = c.SDL_PIXELFORMAT_P010,
    external_oes = c.SDL_PIXELFORMAT_EXTERNAL_OES,
    mjpg = c.SDL_PIXELFORMAT_MJPG,

    pub const rgba_32 = .abgr_8888;
    pub const argb_32 = .bgra_8888;
    pub const bgra_32 = .argb_8888;
    pub const abgr_32 = .rgba_8888;
    pub const rgbx_32 = .xbgr_8888;
    pub const xrgb_32 = .bgrx_8888;
    pub const bgrx_32 = .xrgb_8888;
    pub const xbgr_32 = .rgbx_8888;
    pub const default = .abgr_8888;
};
