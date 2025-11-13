//!
//! The zengine gpu copy pass implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const sdl = @import("../sdl.zig");
const ui = @import("../ui.zig");
const Window = @import("../Window.zig");
const Error = @import("error.zig").Error;
const GPUBuffer = @import("GPUBuffer.zig");
const GPUDevice = @import("GPUDevice.zig");
const GPUTexture = @import("GPUTexture.zig");
const GPUTransferBuffer = @import("GPUTransferBuffer.zig");
const types = @import("types.zig");

const log = std.log.scoped(.gfx_copy_pass);

ptr: ?*c.SDL_GPUCopyPass = null,

const Self = @This();
pub const invalid: Self = .{};

pub fn fromOwned(ptr: *c.SDL_GPUCopyPass) Self {
    return .{ .ptr = ptr };
}

pub fn toOwned(self: *Self) *c.SDL_GPUCopyPass {
    assert(self.isValid());
    defer self.ptr = null;
    return self.ptr.?;
}

pub fn end(self: *Self) void {
    c.SDL_EndGPUCopyPass(self.toOwned());
}

pub fn uploadToTexture(
    self: Self,
    source: *const GPUTransferBuffer.TextureTransferInfo,
    destination: *const GPUTexture.Region,
    cycle: bool,
) void {
    assert(self.isValid());
    c.SDL_UploadToGPUTexture(self.ptr, &source.toSDL(), &destination.toSDL(), cycle);
}

pub fn uploadToBuffer(
    self: Self,
    source: *const GPUTransferBuffer.Location,
    destination: *const GPUBuffer.Region,
    cycle: bool,
) void {
    assert(self.isValid());
    c.SDL_UploadToGPUBuffer(self.ptr, &source.toSDL(), &destination.toSDL(), cycle);
}

pub fn copyTextureToTexture(
    self: Self,
    source: *const GPUTexture.Location,
    destination: *const GPUTexture.Location,
    w: u32,
    h: u32,
    d: u32,
    cycle: bool,
) void {
    assert(self.isValid());
    c.SDL_CopyGPUTextureToTexture(self.ptr, &source.toSDL(), &destination.toSDL(), w, h, d, cycle);
}

pub fn copyBufferToBuffer(
    self: Self,
    source: *const GPUBuffer.Location,
    destination: *const GPUBuffer.Location,
    size: u32,
    cycle: bool,
) void {
    assert(self.isValid());
    c.SDL_CopyGPUBufferToBuffer(self.ptr, &source.toSDL(), &destination.toSDL(), size, cycle);
}

pub fn downloadFromTexture(
    self: Self,
    source: *const GPUTexture.Region,
    destination: *const GPUTransferBuffer.TextureTransferInfo,
) void {
    assert(self.isValid());
    c.SDL_DownloadFromGPUTexture(self.ptr, &source.toSDL(), &destination.toSDL());
}

pub fn downloadFromBuffer(
    self: Self,
    source: *const GPUBuffer.Region,
    destination: *const GPUTransferBuffer.Location,
) void {
    assert(self.isValid());
    c.SDL_DownloadFromGPUBuffer(self.ptr, &source.toSDL(), &destination.toSDL());
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}
