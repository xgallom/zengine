//!
//! The zengine gpu render pass implementation
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
const GPUComputePipeline = @import("GPUComputePipeline.zig");
const GPUDevice = @import("GPUDevice.zig");
const GPUTexture = @import("GPUTexture.zig");
const types = @import("types.zig");

const log = std.log.scoped(.gfx_compute_pass);

ptr: ?*c.SDL_GPUComputePass = null,

const Self = @This();
pub const invalid: Self = .{};

pub fn fromOwned(ptr: *c.SDL_GPUComputePass) Self {
    return .{ .ptr = ptr };
}

pub fn toOwned(self: *Self) *c.SDL_GPUComputePass {
    assert(self.isValid());
    defer self.ptr = null;
    return self.ptr.?;
}

pub fn end(self: *Self) void {
    c.SDL_EndGPUComputePass(self.toOwned());
}

pub fn bindPipeline(self: Self, pipeline: GPUComputePipeline) void {
    assert(self.isValid());
    assert(pipeline.isValid());
    c.SDL_BindGPUComputePipeline(self.ptr, pipeline.ptr);
}

pub fn bindSamplers(self: Self, first_slot: u32, bindings: []const types.TextureSamplerBinding) !void {
    assert(self.isValid());
    var arena = allocators.initArena();
    defer arena.deinit();
    const bufs = try sdl.sliceFrom(arena.allocator(), bindings);
    c.SDL_BindGPUComputeSamplers(self.ptr, first_slot, bufs.ptr, @intCast(bufs.len));
}

pub fn bindStorageTextures(self: Self, first_slot: u32, textures: []const GPUTexture) !void {
    assert(self.isValid());
    var arena = allocators.initArena();
    defer arena.deinit();
    const bufs = try sdl.sliceFrom(arena.allocator(), textures);
    c.SDL_BindGPUComputeStorageTextures(self.ptr, first_slot, bufs.ptr, @intCast(bufs.len));
}

pub fn bindStorageBuffers(self: Self, first_slot: u32, buffers: []const GPUBuffer) !void {
    assert(self.isValid());
    var arena = allocators.initArena();
    defer arena.deinit();
    const bufs = try sdl.sliceFrom(arena.allocator(), buffers);
    c.SDL_BindGPUComputeStorageBuffers(self.ptr, first_slot, bufs.ptr, @intCast(bufs.len));
}

pub fn dispatch(self: Self, groupcount_x: u32, groupcount_y: u32, groupcount_z: u32) void {
    assert(self.isValid());
    c.SDL_DispatchGPUCompute(self.ptr, groupcount_x, groupcount_y, groupcount_z);
}

pub fn dispatchIndirect(self: Self, buffer: GPUBuffer, offset: u32) void {
    assert(self.isValid());
    assert(buffer.isValid());
    c.SDL_DispatchGPUComputeIndirect(self.ptr, buffer.ptr, offset);
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}
