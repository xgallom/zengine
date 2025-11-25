//!
//! The zengine gpu text engine implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");
const ttf = @import("ttf.zig");
const Error = @import("error.zig").Error;
const GPUDevice = @import("GPUDevice.zig");
const types = @import("types.zig");

const log = std.log.scoped(.gfx_gpu_text_engine);

ptr: ?*c.TTF_TextEngine = null,

const Self = @This();
pub const invalid: Self = .{};

pub fn init(gpu_device: GPUDevice) !Self {
    return fromOwned(try create(gpu_device));
}

pub fn deinit(self: *Self) void {
    if (self.isValid()) destroy(self.toOwned());
}

pub fn create(gpu_device: GPUDevice) !*c.TTF_TextEngine {
    assert(gpu_device.isValid());
    const ptr = c.TTF_CreateGPUTextEngine(gpu_device.ptr);
    if (ptr == null) {
        log.err("failed creating text engine: {s}", .{c.SDL_GetError()});
        return Error.TextEngineFailed;
    }
    return ptr.?;
}

pub fn destroy(ptr: *c.TTF_TextEngine) void {
    c.TTF_DestroyGPUTextEngine(ptr);
}

pub fn text(self: Self, font: ttf.Font, str: []const u8) !ttf.Text {
    assert(self.isValid());
    return .init(self, font, str);
}

pub fn fromOwned(ptr: *c.TTF_TextEngine) Self {
    return .{ .ptr = ptr };
}

pub fn toOwned(self: *Self) *c.TTF_TextEngine {
    assert(self.isValid());
    defer self.ptr = null;
    return self.ptr.?;
}

pub fn toSDL(self: *const Self) *c.TTF_TextEngine {
    assert(self.isValid());
    return self.ptr.?;
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}
