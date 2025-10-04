//!
//! The zengine gpu mesh buffer implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const math = @import("../math.zig");
const ui = @import("../ui.zig");
const GPUBuffer = @import("GPUBuffer.zig");

const log = std.log.scoped(.gfx_mesh_buffer);

gpu_bufs: std.EnumArray(Type, GPUBuffer) = .initFill(.empty),
vert_counts: std.EnumArray(Type, u32) = .initFill(0),
type: Type,

const Self = @This();
pub const VertElem = math.Scalar;
pub const IndexElem = math.Index;

pub const exclude_properties: ui.property_editor.PropertyList = &.{.gpu_bufs};

pub const Type = enum {
    vertex,
    index,
};

pub fn Elem(comptime buf_type: Type) type {
    return switch (buf_type) {
        .vertex => VertElem,
        .index => IndexElem,
    };
}

pub fn init(mesh_type: Type) Self {
    return .{ .type = mesh_type };
}

pub fn deinit(self: *Self, gpa: std.mem.Allocator, gpu_device: ?*c.SDL_GPUDevice) void {
    self.gpu_bufs.getPtr(.vertex).deinit(gpa, gpu_device);
    self.vert_counts.set(.vertex, 0);
    self.gpu_bufs.getPtr(.index).deinit(gpa, gpu_device);
    self.vert_counts.set(.index, 0);
}

pub fn slice(self: *const Self, comptime buf_type: Type) []Elem(buf_type) {
    return self.gpu_bufs.getPtrConst(buf_type).slice(Elem(buf_type));
}

pub fn ensureUnusedCapacity(
    self: *Self,
    gpa: std.mem.Allocator,
    comptime buf_type: Type,
    comptime T: type,
    count: usize,
) !void {
    comptime assert(math.Elem(T) == Elem(buf_type));
    try self.gpu_bufs.getPtr(buf_type).ensureUnusedCapacity(gpa, T, count);
}

pub fn append(self: *Self, gpa: std.mem.Allocator, comptime buf_type: Type, comptime T: type, items: []const T) !void {
    comptime assert(math.Elem(T) == Elem(buf_type));
    try self.gpu_bufs.getPtr(buf_type).append(gpa, T, items);
}

pub fn appendAssumeCapacity(self: *Self, comptime buf_type: Type, comptime T: type, items: []const T) void {
    comptime assert(math.Elem(T) == Elem(buf_type));
    self.gpu_bufs.getPtr(buf_type).appendAssumeCapacity(T, items);
}

pub fn freeCPUBuffers(self: *Self, gpa: std.mem.Allocator) void {
    self.gpu_bufs.getPtr(.vertex).freeCPUBuffer(gpa);
    self.vert_counts.set(.vertex, 0);
    self.gpu_bufs.getPtr(.index).freeCPUBuffer(gpa);
    self.vert_counts.set(.index, 0);
}

pub fn createGPUBuffers(self: *Self, gpu_device: ?*c.SDL_GPUDevice) !void {
    try self.gpu_bufs.getPtr(.vertex).createGPUBuffer(gpu_device, .initOne(.vertex));
    if (self.type == .index) try self.gpu_bufs.getPtr(.index).createGPUBuffer(gpu_device, .initOne(.index));
}

pub fn releaseGPUBuffers(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
    self.gpu_bufs.getPtr(.vertex).releaseGPUBuffer(gpu_device);
    if (self.type == .index) self.gpu_bufs.getPtr(.index).releaseGPUBuffer(gpu_device);
}

pub fn propertyEditor(self: *Self) ui.PropertyEditor(Self) {
    return .init(self);
}
