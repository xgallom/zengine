//!
//! The zengine LUT implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");
const Error = @import("error.zig").Error;
const GPUDevice = @import("GPUDevice.zig");
const GPUTexture = @import("GPUTexture.zig");
const Surface = @import("Surface.zig");

const log = std.log.scoped(.gfx_surface_texture);

data: []math.RGBAf32 = &.{},
gpu_tex: GPUTexture = .invalid,
dim_len: u32 = 0,

const Self = @This();
pub const IsValid = packed struct { data: bool, gpu_tex: bool };
pub const invalid: Self = .{};

pub fn init(data: []math.RGBAf32, dim_len: u32) Self {
    return .{ .data = data, .dim_len = dim_len };
}

pub fn deinit(self: *Self, gpa: std.mem.Allocator, gpu_device: GPUDevice) void {
    self.gpu_tex.deinit(gpu_device);
    gpa.free(self.data);
    self.data = &.{};
    self.dim_len = 0;
}

pub fn bytes(self: *const Self) []u8 {
    return std.mem.sliceAsBytes(self.data);
}

pub fn byteLen(self: *const Self) u32 {
    assert(self.dim_len * self.dim_len * self.dim_len == self.data.len);
    return @intCast(self.bytes().len);
}

pub fn toOwnedGPUTexture(self: *Self) *c.SDL_GPUTexture {
    return self.gpu_tex.toOwned();
}

pub fn createGPUTexture(self: *Self, gpu_device: GPUDevice) !void {
    assert(self.isValid().data);
    self.gpu_tex = try gpu_device.texture(&.{
        .type = .@"3D",
        .format = .R32G32B32A32_f,
        .usage = .initOne(.sampler),
        .size = .{ self.dim_len, self.dim_len },
        .layer_count_or_depth = self.dim_len,
    });
}

pub fn releaseGPUTexture(self: *Self, gpu_device: GPUDevice) void {
    self.gpu_tex.deinit(gpu_device);
}

pub inline fn isValid(self: Self) IsValid {
    return .{
        .data = self.data.len > 0,
        .gpu_tex = self.gpu_tex.isValid(),
    };
}
