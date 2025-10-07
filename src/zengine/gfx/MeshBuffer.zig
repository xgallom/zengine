//!
//! The zengine gpu mesh buffer implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const math = @import("../math.zig");
const ui = @import("../ui.zig");
const CPUBuffer = @import("CPUBuffer.zig");
const Error = @import("Error.zig").Error;
const GPUBuffer = @import("GPUBuffer.zig");
const GPUDevice = @import("GPUDevice.zig");

const log = std.log.scoped(.gfx_mesh_buffer);

cpu_bufs: std.EnumArray(Type, CPUBuffer) = .initFill(.empty),
gpu_bufs: std.EnumArray(Type, GPUBuffer) = .initFill(.invalid),
type: Type,

const Self = @This();
pub const Type = enum { vertex, index };
pub const exclude_properties: ui.property_editor.PropertyList = &.{ .cpu_bufs, .gpu_bufs };

pub fn Elem(comptime buf_type: Type) type {
    return switch (buf_type) {
        .vertex => math.Scalar,
        .index => math.Index,
    };
}

pub fn init(mesh_type: Type) Self {
    return .{ .type = mesh_type };
}

pub fn deinit(self: *Self, gpa: std.mem.Allocator, gpu_device: GPUDevice) void {
    self.cpu_bufs.getPtr(.vertex).deinit(gpa);
    self.cpu_bufs.getPtr(.index).deinit(gpa);
    self.gpu_bufs.getPtr(.vertex).deinit(gpu_device);
    self.gpu_bufs.getPtr(.index).deinit(gpu_device);
}

pub fn fromCPUBuffer(vert_buf: *CPUBuffer) Self {
    const self: Self = .{
        .cpu_bufs = .init(.{
            .vertex = vert_buf.*,
            .index = .empty,
        }),
        .type = .vertex,
    };
    vert_buf.* = .empty;
    return self;
}

pub fn fromCPUBuffers(vert_buf: *CPUBuffer, index_buf: *CPUBuffer) Self {
    const self: Self = .{
        .cpu_bufs = .init(.{
            .vertex = vert_buf.*,
            .index = index_buf.*,
        }),
        .type = .index,
    };
    vert_buf.* = .empty;
    index_buf.* = .empty;
    return self;
}

pub fn slice(self: *const Self, comptime buf_type: Type) []Elem(buf_type) {
    return self.cpu_bufs.getPtrConst(buf_type).slice(Elem(buf_type));
}

pub fn vertCount(self: *const Self, comptime buf_type: Type) u32 {
    return self.cpu_bufs.getPtrConst(buf_type).vert_count;
}

pub fn vertCounts(self: *const Self) std.EnumArray(Type, u32) {
    return .init(.{
        .vertex = self.byteLen(.vertex),
        .index = self.byteLen(.index),
    });
}

pub fn byteLen(self: *const Self, comptime buf_type: Type) u32 {
    return self.cpu_bufs.getPtrConst(buf_type).byteLen();
}

pub fn byteLens(self: *const Self) std.EnumArray(Type, u32) {
    return .init(.{
        .vertex = self.byteLen(.vertex),
        .index = self.byteLen(.index),
    });
}

pub fn ensureUnusedCapacity(
    self: *Self,
    gpa: std.mem.Allocator,
    comptime buf_type: Type,
    comptime T: type,
    count: usize,
) !void {
    comptime assert(math.Elem(T) == Elem(buf_type));
    try self.cpu_bufs.getPtr(buf_type).ensureUnusedCapacity(gpa, T, count);
}

pub fn append(
    self: *Self,
    gpa: std.mem.Allocator,
    comptime buf_type: Type,
    comptime T: type,
    comptime verts_in_item: u32,
    item: *const T,
) !void {
    comptime assert(math.Elem(T) == Elem(buf_type));
    try self.cpu_bufs.getPtr(buf_type).append(gpa, T, verts_in_item, item);
}

pub fn appendAssumeCapacity(
    self: *Self,
    comptime buf_type: Type,
    comptime T: type,
    comptime verts_in_item: u32,
    item: *const T,
) void {
    comptime assert(math.Elem(T) == Elem(buf_type));
    self.cpu_bufs.getPtr(buf_type).appendAssumeCapacity(T, verts_in_item, item);
}

pub fn appendSlice(
    self: *Self,
    gpa: std.mem.Allocator,
    comptime buf_type: Type,
    comptime T: type,
    comptime verts_in_item: u32,
    items: []const T,
) !void {
    comptime assert(math.Elem(T) == Elem(buf_type));
    try self.cpu_bufs.getPtr(buf_type).appendSlice(gpa, T, verts_in_item, items);
}

pub fn appendSliceAssumeCapacity(
    self: *Self,
    comptime buf_type: Type,
    comptime T: type,
    comptime verts_in_item: u32,
    items: []const T,
) void {
    comptime assert(math.Elem(T) == Elem(buf_type));
    self.cpu_bufs.getPtr(buf_type).appendSliceAssumeCapacity(T, verts_in_item, items);
}

pub fn clearCPUBuffers(self: *Self) void {
    self.cpu_bufs.getPtr(.vertex).clear();
    self.cpu_bufs.getPtr(.index).clear();
}

pub fn freeCPUBuffers(self: *Self, gpa: std.mem.Allocator) void {
    self.cpu_bufs.getPtr(.vertex).free(gpa);
    self.cpu_bufs.getPtr(.index).free(gpa);
}

pub fn createGPUBuffers(self: *Self, gpu_device: GPUDevice, usage: ?GPUBuffer.UsageFlags) !void {
    try self.gpu_bufs.getPtr(.vertex).create(gpu_device, &.{
        .usage = usage orelse .initOne(.vertex),
        .size = self.byteLen(.vertex),
    });
    if (self.type == .index) try self.gpu_bufs.getPtr(.index).create(gpu_device, &.{
        .usage = .initOne(.index),
        .size = self.byteLen(.index),
    });
}

pub fn releaseGPUBuffers(self: *Self, gpu_device: GPUDevice) void {
    self.gpu_bufs.getPtr(.vertex).release(gpu_device);
    if (self.type == .index) self.gpu_bufs.getPtr(.index).release(gpu_device);
}

pub fn propertyEditor(self: *Self) ui.PropertyEditor(Self) {
    return .init(self);
}
