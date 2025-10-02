//!
//! The zengine image implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const fs = @import("../fs.zig");

const log = std.log.scoped(.gfx_jpg);

const Self = @This();

pub const pixel_format: c.SDL_PixelFormat = c.SDL_PIXELFORMAT_ABGR8888;

pub const OpenConfig = struct {
    allocator: std.mem.Allocator,
    gpu_device: ?*c.SDL_GPUDevice,
    file_path: []const u8,
};

pub fn open(config: OpenConfig) !*c.SDL_Surface {
    const buf = try fs.readFileAbsolute(config.allocator, config.file_path);
    defer config.allocator.free(buf);

    var surf = try load(config, buf);
    errdefer c.SDL_DestroySurface(surf);

    if (surf.format != pixel_format) {
        const new_surf = c.SDL_ConvertSurface(surf, pixel_format);
        if (new_surf == null) {
            log.err("failed converting surface formats for \"{s}\": {s}", .{ config.file_path, c.SDL_GetError() });
            return error.ConvertFailed;
        }
        c.SDL_DestroySurface(surf);
        surf = new_surf.?;
    }

    return surf;
}

fn load(config: OpenConfig, buf: []const u8) !*c.SDL_Surface {
    const surf = c.IMG_Load_IO(c.SDL_IOFromConstMem(buf.ptr, buf.len), true);
    if (surf == null) {
        log.err("image load failed for \"{s}\": {s}", .{ config.file_path, c.SDL_GetError() });
        return error.LoadFailed;
    }
    return surf.?;
}
