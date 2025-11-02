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
const Error = @import("Error.zig").Error;
const GPUBuffer = @import("GPUBuffer.zig");
const GPUDevice = @import("GPUDevice.zig");
const GPUGraphicsPipeline = @import("GPUGraphicsPipeline.zig");
const GPURenderPass = @import("GPURenderPass.zig");
const GPUTexture = @import("GPUTexture.zig");
const types = @import("types.zig");

const log = std.log.scoped(.gfx_render_pass);

ptr: ?*c.SDL_GPURenderPass = null,

const Self = @This();
pub const invalid: Self = .{};

pub fn fromOwned(ptr: *c.SDL_GPURenderPass) Self {
    return .{ .ptr = ptr };
}

pub fn toOwned(self: *Self) *c.SDL_GPURenderPass {
    assert(self.isValid());
    defer self.ptr = null;
    return self.ptr.?;
}

pub fn end(self: *Self) void {
    c.SDL_EndGPURenderPass(self.toOwned());
}

pub fn bindGraphicsPipeline(self: Self, pipeline: GPUGraphicsPipeline) void {
    assert(self.isValid());
    assert(pipeline.isValid());
    c.SDL_BindGPUGraphicsPipeline(self.ptr, pipeline.ptr);
}

pub fn bindVertexBuffers(self: Self, first_slot: u32, buffers: []const GPUBuffer.Binding) !void {
    assert(self.isValid());
    var arena = allocators.initArena();
    defer arena.deinit();
    const bufs = try sdl.sliceFrom(arena.allocator(), buffers);
    c.SDL_BindGPUVertexBuffers(self.ptr, first_slot, bufs.ptr, @intCast(bufs.len));
}

pub fn bindIndexBuffer(self: Self, buffer: *const GPUBuffer.Binding, size: types.IndexElementSize) void {
    assert(self.isValid());
    const buf = buffer.toSDL();
    c.SDL_BindGPUIndexBuffer(self.ptr, &buf, @intFromEnum(size));
}

pub fn bindFragmentSamplers(self: Self, first_slot: u32, bindings: []const types.TextureSamplerBinding) !void {
    assert(self.isValid());
    var arena = allocators.initArena();
    defer arena.deinit();
    const bufs = try sdl.sliceFrom(arena.allocator(), bindings);
    c.SDL_BindGPUFragmentSamplers(self.ptr, first_slot, bufs.ptr, @intCast(bufs.len));
}

pub fn bindFragmentStorageBuffers(self: Self, first_slot: u32, buffers: []const GPUBuffer) !void {
    assert(self.isValid());
    var arena = allocators.initArena();
    defer arena.deinit();
    const bufs = try sdl.sliceFrom(arena.allocator(), buffers);
    c.SDL_BindGPUFragmentStorageBuffers(self.ptr, first_slot, bufs.ptr, @intCast(bufs.len));
}

pub fn drawPrimitives(
    self: Self,
    num_vertices: u32,
    num_instances: u32,
    first_vertex: u32,
    first_instance: u32,
) void {
    assert(self.isValid());
    c.SDL_DrawGPUPrimitives(self.ptr, num_vertices, num_instances, first_vertex, first_instance);
}

pub fn drawIndexedPrimitives(
    self: Self,
    num_indices: u32,
    num_instances: u32,
    first_index: u32,
    vertex_offset: i32,
    first_instance: u32,
) void {
    assert(self.isValid());
    c.SDL_DrawGPUIndexedPrimitives(self.ptr, num_indices, num_instances, first_index, vertex_offset, first_instance);
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}
