//!
//! The zengine ttf loader implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const fs = @import("../fs.zig");
const global = @import("../global.zig");
const Error = @import("error.zig").Error;
const GPUTextEngine = @import("GPUTextEngine.zig");
const ttf = @import("ttf.zig");

const log = std.log.scoped(.gfx_img_loader);

const Self = @This();

pub const OpenConfig = struct {
    allocator: std.mem.Allocator,
    file_path: []const u8,
    size_pts: f32,
};

pub fn loadFile(config: *const OpenConfig) !ttf.Font {
    const buf = try fs.readFileAbsolute(config.allocator, config.file_path);
    defer config.allocator.free(buf);
    return load(config, buf);
}

fn load(config: *const OpenConfig, buf: []const u8) !ttf.Font {
    const font = c.TTF_OpenFontIO(c.SDL_IOFromConstMem(buf.ptr, buf.len), true, config.size_pts);
    if (font == null) {
        log.err("ttf font load failed for \"{s}\": {s}", .{ config.file_path, c.SDL_GetError() });
        return error.ImageFailed;
    }
    return .fromOwned(font);
}
