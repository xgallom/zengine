//!
//! The zengine surface texture implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");
const Surface = @import("Surface.zig");
const GPUTexture = @import("GPUTexture.zig");

const log = std.log.scoped(.gfx_surface_texture);

surf: Surface = .invalid,
gpu_tex: GPUTexture = .invalid,

const Self = @This();
pub const IsValid = packed struct { surf: bool, gpu_tex: bool };
pub const invalid: Self = .{};

pub fn init(surf: Surface) Self {
    return .{ .surf = surf };
}

pub fn deinit(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
    self.gpu_tex.deinit(gpu_device);
    self.surf.deinit();
}

pub fn toOwnedGPUTexture(self: *Self) *c.SDL_GPUTexture {
    return self.gpu_tex.toOwnedGPUTexture();
}

pub fn createGPUTexture(self: *Self, gpu_device: ?*c.SDL_GPUDevice) !void {
    assert(self.surf.isValid());
    self.gpu_tex = try .init(gpu_device, &.{
        .type = .default,
        .format = .default,
        .usage = .initOne(.sampler),
        .size = .{ self.surf.width(), self.surf.height() },
    });
}

pub fn releaseGPUTexture(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
    self.gpu_tex.releaseGPUTexture(gpu_device);
}

pub inline fn isValid(self: Self) IsValid {
    return .{
        .surf = self.surf.isValid(),
        .gpu_tex = self.gpu_tex.isValid(),
    };
}
