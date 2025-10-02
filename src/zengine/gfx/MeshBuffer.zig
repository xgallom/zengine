//!
//! The zengine gpu mesh buffer implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const math = @import("../math.zig");
const Tree = @import("../containers.zig").Tree;

const log = std.log.scoped(.gfx_mesh);

allocator: std.mem.Allocator,
vert_data: VertexList = .empty,
index_data: IndexList = .empty,
vert_buf: ?*c.SDL_GPUBuffer = null,
index_buf: ?*c.SDL_GPUBuffer = null,
vert_byte_len: usize = 0,
index_byte_len: usize = 0,
vert_count: usize = 0,
index_count: usize = 0,
state: State = .cpu,
type: Type,

const Self = @This();
const VertexList = std.ArrayList(math.Scalar);
const IndexList = std.ArrayList(math.Index);

const State = enum {
    cpu,
    gpu,
    gpu_upload,
    gpu_mapped,
    gpu_uploaded,
};

pub const Type = enum {
    vertex,
    index,
};

pub fn init(allocator: std.mem.Allocator, mesh_type: Type) Self {
    return .{
        .allocator = allocator,
        .type = mesh_type,
    };
}

pub fn deinit(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
    self.releaseGPUBuffers(gpu_device);
    self.freeCpuData();
}

pub fn vertices(self: *const Self) []math.Vertex {
    const ptr: []math.Vertex = @ptrCast(self.vert_data.items);
    return ptr;
}

pub fn ensureVerticesUnusedCapacity(self: *Self, comptime V: type, count: usize) !void {
    assert(self.state == .cpu);
    try self.vert_data.ensureUnusedCapacity(self.allocator, count * comptime math.elemLen(V));
}
pub fn ensureIndexesUnusedCapacity(self: *Self, comptime I: type, count: usize) !void {
    assert(self.state == .cpu);
    try self.index_data.ensureUnusedCapacity(self.allocator, count * comptime math.elemLen(I));
}

pub fn appendVertices(self: *Self, comptime V: type, verts: []const V) !void {
    comptime assert(math.Elem(V) == math.Scalar);
    assert(self.state == .cpu);
    const ptr: [*]const math.Scalar = @ptrCast(verts.ptr);
    const len = verts.len * comptime math.elemLen(V);
    try self.vert_data.appendSlice(self.allocator, ptr[0..len]);
}

pub fn appendVerticesAssumeCapacity(self: *Self, comptime V: type, verts: []const V) void {
    comptime assert(math.Elem(V) == math.Scalar);
    assert(self.state == .cpu);
    const ptr: [*]const math.Scalar = @ptrCast(verts.ptr);
    const len = verts.len * comptime math.elemLen(V);
    self.vert_data.appendSliceAssumeCapacity(ptr[0..len]);
}

pub fn appendVerticesAll(self: *Self, comptime V: type, verts_all: []const []const V) !void {
    assert(self.state == .cpu);
    for (verts_all) |verts| try self.appendVertices(V, verts);
}

pub fn appendIndexes(self: *Self, comptime I: type, indexes: []const I) !void {
    assert(self.state == .cpu);
    assert(self.type == .index);
    const ptr: [*]const math.Index = @ptrCast(indexes.ptr);
    const len = indexes.len * comptime math.elemLen(I);
    try self.index_data.appendSlice(self.allocator, ptr[0..len]);
}

pub fn appendIndexesAll(self: *Self, comptime I: type, indexes_all: []const []const I) !void {
    assert(self.state == .cpu);
    assert(self.type == .index);
    for (indexes_all) |indexes| try self.appendIndexes(I, indexes);
}

pub fn freeCpuData(self: *Self) void {
    assert(self.state == .cpu or self.state == .gpu);
    self.vert_data.clearAndFree(self.allocator);
    self.index_data.clearAndFree(self.allocator);
}

pub fn createGPUBuffers(self: *Self, gpu_device: ?*c.SDL_GPUDevice) !void {
    assert(self.state == .cpu or self.state == .gpu);
    self.state = .gpu;

    errdefer self.releaseGPUBuffers(gpu_device);

    // TODO: solve vert_count and index_count
    // now they are set manually by obj_loader
    self.vert_byte_len = std.mem.sliceAsBytes(self.vert_data.items).len;
    if (self.vert_buf == null) {
        self.vert_buf = c.SDL_CreateGPUBuffer(gpu_device, &c.SDL_GPUBufferCreateInfo{
            .usage = c.SDL_GPU_BUFFERUSAGE_VERTEX,
            .size = @intCast(self.vert_byte_len),
        });
        if (self.vert_buf == null) {
            log.err("failed creating vertex buffer: {s}", .{c.SDL_GetError()});
            return error.BufferFailed;
        }
    }

    if (self.type == .vertex) return;
    self.index_byte_len = std.mem.sliceAsBytes(self.index_data.items).len;
    if (self.index_buf == null) {
        self.index_buf = c.SDL_CreateGPUBuffer(gpu_device, &c.SDL_GPUBufferCreateInfo{
            .usage = c.SDL_GPU_BUFFERUSAGE_INDEX,
            .size = @intCast(self.index_byte_len),
        });
        if (self.index_buf == null) {
            log.err("failed creating index buffer: {s}", .{c.SDL_GetError()});
            return error.BufferFailed;
        }
    }
}

pub fn releaseGPUBuffers(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
    assert(self.state == .cpu or self.state == .gpu);

    if (self.vert_buf != null) c.SDL_ReleaseGPUBuffer(gpu_device, self.vert_buf);
    if (self.index_buf != null) c.SDL_ReleaseGPUBuffer(gpu_device, self.index_buf);

    self.vert_buf = null;
    self.index_buf = null;
    self.vert_byte_len = 0;
    self.index_byte_len = 0;
    self.vert_count = 0;
    self.index_count = 0;
    self.state = .cpu;
}

pub fn createUploadTransferBuffer(self: *Self, gpu_device: ?*c.SDL_GPUDevice) !UploadTransferBuffer {
    assert(self.state == .gpu);
    assert(self.vert_byte_len != 0);

    const transfer_buffer = c.SDL_CreateGPUTransferBuffer(gpu_device, &c.SDL_GPUTransferBufferCreateInfo{
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = @intCast(self.vert_byte_len + self.index_byte_len),
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
            const src = std.mem.sliceAsBytes(tb.self.vert_data.items);
            const byte_len = tb.self.vert_byte_len;
            assert(byte_len != 0);
            assert(src.len == byte_len);
            @memcpy(dest[0..byte_len], src);
            dest += byte_len;
        }
        if (tb.self.index_buf != null) {
            const src = std.mem.sliceAsBytes(tb.self.index_data.items);
            const byte_len = tb.self.index_byte_len;
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
        assert(tb.self.vert_buf != null);

        var tb_offset: usize = 0;
        {
            const byte_len = tb.self.vert_byte_len;
            assert(byte_len != 0);
            c.SDL_UploadToGPUBuffer(copy_pass, &c.SDL_GPUTransferBufferLocation{
                .transfer_buffer = tb.transfer_buffer,
                .offset = @intCast(tb_offset),
            }, &c.SDL_GPUBufferRegion{
                .buffer = tb.self.vert_buf,
                .offset = 0,
                .size = @intCast(byte_len),
            }, false);
            tb_offset += byte_len;
        }
        if (tb.self.index_buf != null) {
            const byte_len = tb.self.vert_byte_len;
            assert(byte_len != 0);
            c.SDL_UploadToGPUBuffer(copy_pass, &c.SDL_GPUTransferBufferLocation{
                .transfer_buffer = tb.transfer_buffer,
                .offset = @intCast(tb_offset),
            }, &c.SDL_GPUBufferRegion{
                .buffer = tb.self.index_buf,
                .offset = 0,
                .size = @intCast(byte_len),
            }, false);
            tb_offset += byte_len;
        }

        tb.self.state = .gpu_uploaded;
    }
};
