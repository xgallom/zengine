//!
//! The zengine surface texture implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const Engine = @import("../Engine.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");
const Error = @import("error.zig").Error;
const GPUDevice = @import("GPUDevice.zig");
const GPUTexture = @import("GPUTexture.zig");
const Surface = @import("Surface.zig");

const log = std.log.scoped(.gfx_surface_texture);

surf: Surface = .invalid,
gpu_tex: GPUTexture = .invalid,

const Self = @This();
pub const Registry = Engine.Properties.AutoRegistry(*Self, .{});
pub const IsValid = packed struct { surf: bool, gpu_tex: bool };
pub const invalid: Self = .{};

pub fn init(surf: Surface) Self {
    return .{ .surf = surf };
}

pub fn deinit(self: *Self, gpu_device: GPUDevice) void {
    self.gpu_tex.deinit(gpu_device);
    self.surf.deinit();
}

pub fn toOwnedGPUTexture(self: *Self) *c.SDL_GPUTexture {
    return self.gpu_tex.toOwned();
}

pub fn createGPUTexture(self: *Self, gpu_device: GPUDevice) !void {
    assert(self.surf.isValid());
    const is_sRGB = self.properties().bool.get("is_sRGB");
    self.gpu_tex = try gpu_device.texture(&.{
        .type = .default,
        .format = if (is_sRGB) .R8G8B8A8_unorm_sRGB else .R8G8B8A8_unorm,
        .usage = .initOne(.sampler),
        .size = .{ self.surf.width(), self.surf.height() },
    });
}

pub fn releaseGPUTexture(self: *Self, gpu_device: GPUDevice) void {
    self.gpu_tex.deinit(gpu_device);
}

pub inline fn isValid(self: Self) IsValid {
    return .{
        .surf = self.surf.isValid(),
        .gpu_tex = self.gpu_tex.isValid(),
    };
}

pub fn createProperties(self: *Self) !*Engine.Properties {
    const props = try Engine.createProperties(Registry, self);
    try props.put(.bool, "is_sRGB", false);
    return props;
}

pub fn destroyProperties(self: *Self) void {
    Engine.destroyProperties(Registry, self);
}

pub fn properties(self: *Self) *Engine.Properties {
    return Engine.properties(Registry, self);
}

pub fn propertyEditor(self: *Self) !ui.Element {
    try ui.PropertiesEditor(Registry).register();
    return ui.PropertiesEditor(Registry).init(self);
}
