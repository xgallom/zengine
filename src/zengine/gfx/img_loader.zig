//!
//! The zengine image loader implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const fs = @import("../fs.zig");
const global = @import("../global.zig");
const Error = @import("error.zig").Error;
const GPUDevice = @import("GPUDevice.zig");
const Surface = @import("Surface.zig");

const log = std.log.scoped(.gfx_img_loader);

const Self = @This();

pub const OpenConfig = struct {
    allocator: std.mem.Allocator,
    gpu_device: GPUDevice,
    file_path: []const u8,
};

pub fn loadFile(config: *const OpenConfig) !Surface {
    const buf = try fs.readFileAbsolute(config.allocator, config.file_path);
    defer config.allocator.free(buf);

    var surf = try load(config, buf);
    errdefer surf.deinit();

    if (surf.format() != Surface.PixelFormat.default) try surf.convert(.default);
    return surf;
}

fn load(config: *const OpenConfig, buf: []const u8) !Surface {
    const surf = c.IMG_Load_IO(c.SDL_IOFromConstMem(buf.ptr, buf.len), true);
    if (surf == null) {
        log.err("image load failed for \"{s}\": {s}", .{ config.file_path, c.SDL_GetError() });
        return Error.ImageFailed;
    }
    return .fromOwned(surf);
}
