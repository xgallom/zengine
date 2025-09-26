//!
//! The zengine image implementation
//!

const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const fs = @import("../fs.zig");

const log = std.log.scoped(.gfx_jpg);

const Self = @This();

pub const OpenConfig = struct {
    allocator: std.mem.Allocator,
    gpu_device: ?*c.SDL_GPUDevice,
    file_path: []const u8,
};

pub fn open(config: OpenConfig) !Self {
    var assets_dir = try global.assetsDir(.{});
    defer assets_dir.close();

    const buf = try fs.readFile(config.allocator, config.file_path, assets_dir);
    defer config.allocator.free(buf);

    var surf = try load(config, buf);
    errdefer c.SDL_DestroySurface(surf);

    if (surf.format != c.SDL_PIXELFORMAT_RGBA8888) {
        const new_surf = c.SDL_ConvertSurface(surf, c.SDL_PIXELFORMAT_RGBA8888);
        if (new_surf == null) {
            log.err("failed converting surface formats for \"{s}\": {s}", .{ config.file_path, c.SDL_GetError() });
            return error.ConvertFailed;
        }
        c.SDL_DestroySurface(surf);
        surf = new_surf;
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
