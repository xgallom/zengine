//!
//! The zengine gpu storage buffer implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const math = @import("../math.zig");
const Tree = @import("../containers.zig").Tree;

const log = std.log.scoped(.gfx_mesh);

allocator: std.mem.Allocator,
data: VertexList = .empty,
gpu_buf: ?*c.SDL_GPUBuffer = null,
byte_len: usize = 0,
count: usize = 0,
state: State = .cpu,

const Self = @This();
const VertexList = std.ArrayList(math.Scalar);

const State = enum {
    cpu,
    gpu,
    gpu_upload,
    gpu_mapped,
    gpu_uploaded,
};

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
    self.releaseGPUBuffers(gpu_device);
    self.freeCpuData();
}

pub fn vertices(self: *const Self, comptime T: type) []T {
    const ptr: []T = @ptrCast(self.data.items);
    return ptr;
}

pub fn ensureUnusedCapacity(self: *Self, comptime V: type, count: usize) !void {
    assert(self.state == .cpu);
    try self.data.ensureUnusedCapacity(self.allocator, count * comptime math.elemLen(V));
}

pub fn append(self: *Self, comptime V: type, verts: []const V) !void {
    comptime assert(math.Elem(V) == math.Scalar);
    assert(self.state == .cpu or self.state == .gpu);
    const ptr: [*]const math.Scalar = @ptrCast(verts.ptr);
    const len = verts.len * comptime math.elemLen(V);
    try self.data.appendSlice(self.allocator, ptr[0..len]);
}

pub fn appendAssumeCapacity(self: *Self, comptime V: type, verts: []const V) void {
    comptime assert(math.Elem(V) == math.Scalar);
    assert(self.state == .cpu or self.state == .gpu);
    const ptr: [*]const math.Scalar = @ptrCast(verts.ptr);
    const len = verts.len * comptime math.elemLen(V);
    self.data.appendSliceAssumeCapacity(ptr[0..len]);
}

pub fn appendAll(self: *Self, comptime V: type, verts_all: []const []const V) !void {
    assert(self.state == .cpu or self.state == .gpu);
    for (verts_all) |verts| try self.append(V, verts);
}

pub fn clearCpuData(self: *Self) void {
    assert(self.state == .cpu or self.state == .gpu);
    self.data.clearRetainingCapacity();
}

pub fn freeCpuData(self: *Self) void {
    assert(self.state == .cpu or self.state == .gpu);
    self.data.clearAndFree(self.allocator);
}

pub fn createGPUBuffers(self: *Self, gpu_device: ?*c.SDL_GPUDevice) !void {
    assert(self.state == .cpu or self.state == .gpu);
    self.state = .gpu;

    errdefer self.releaseGPUBuffers(gpu_device);

    self.byte_len = std.mem.sliceAsBytes(self.data.items).len;
    if (self.gpu_buf == null) {
        self.gpu_buf = c.SDL_CreateGPUBuffer(gpu_device, &c.SDL_GPUBufferCreateInfo{
            .usage = c.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ,
            .size = @intCast(self.byte_len),
        });
        if (self.gpu_buf == null) {
            log.err("failed creating buffer: {s}", .{c.SDL_GetError()});
            return error.BufferFailed;
        }
    }
}

pub fn releaseGPUBuffers(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
    assert(self.state == .cpu or self.state == .gpu);

    if (self.gpu_buf != null) c.SDL_ReleaseGPUBuffer(gpu_device, self.gpu_buf);

    self.gpu_buf = null;
    self.byte_len = 0;
    self.count = 0;
    self.state = .cpu;
}

pub fn createUploadTransferBuffer(self: *Self, gpu_device: ?*c.SDL_GPUDevice) !UploadTransferBuffer {
    assert(self.state == .gpu);
    assert(self.byte_len != 0);

    const transfer_buffer = c.SDL_CreateGPUTransferBuffer(gpu_device, &c.SDL_GPUTransferBufferCreateInfo{
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = @intCast(self.byte_len),
    });
    if (transfer_buffer == null) {
        log.err("failed creating transfer buffer: {s}", .{c.SDL_GetError()});
        return error.BufferFailed;
    }

    self.state = .gpu_upload;
    return .{ .self = self, .transfer_buffer = transfer_buffer.? };
}

pub const UploadTransferBuffer = struct {
    self: *Self,
    transfer_buffer: *c.SDL_GPUTransferBuffer,

    pub fn release(tb: *UploadTransferBuffer, gpu_device: ?*c.SDL_GPUDevice) void {
        if (tb.self.state == .gpu_mapped) {
            log.warn("transfer buffer mapped but not uploaded", .{});
            tb.self.state = .gpu_upload;
        }
        assert(tb.self.state == .gpu_upload or tb.self.state == .gpu_uploaded);
        c.SDL_ReleaseGPUTransferBuffer(gpu_device, tb.transfer_buffer);
        tb.self.state = .gpu;
        tb.* = undefined;
    }

    pub fn map(tb: *const UploadTransferBuffer, gpu_device: ?*c.SDL_GPUDevice) !void {
        assert(tb.self.state == .gpu_upload);

        const transfer_buffer_ptr = c.SDL_MapGPUTransferBuffer(gpu_device, tb.transfer_buffer, false);
        if (transfer_buffer_ptr == null) {
            log.err("failed mapping transfer buffer: {s}", .{c.SDL_GetError()});
            return error.BufferFailed;
        }

        var dest: [*]u8 = @ptrCast(@alignCast(transfer_buffer_ptr));
        {
            const src = std.mem.sliceAsBytes(tb.self.data.items);
            const byte_len = tb.self.byte_len;
            assert(byte_len != 0);
            assert(src.len == byte_len);
            @memcpy(dest[0..byte_len], src);
            dest += byte_len;
        }

        c.SDL_UnmapGPUTransferBuffer(gpu_device, tb.transfer_buffer);
        tb.self.state = .gpu_mapped;
    }

    pub fn upload(tb: *const UploadTransferBuffer, copy_pass: ?*c.SDL_GPUCopyPass) void {
        assert(tb.self.state == .gpu_mapped);
        assert(tb.self.gpu_buf != null);

        var tb_offset: usize = 0;
        {
            const byte_len = tb.self.byte_len;
            assert(byte_len != 0);
            c.SDL_UploadToGPUBuffer(copy_pass, &c.SDL_GPUTransferBufferLocation{
                .transfer_buffer = tb.transfer_buffer,
                .offset = @intCast(tb_offset),
            }, &c.SDL_GPUBufferRegion{
                .buffer = tb.self.gpu_buf,
                .offset = 0,
                .size = @intCast(byte_len),
            }, false);
            tb_offset += byte_len;
        }

        tb.self.state = .gpu_uploaded;
    }
};
