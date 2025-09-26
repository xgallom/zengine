//!
//! The zengine mesh implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const math = @import("../math.zig");
const Tree = @import("../containers.zig").Tree;

const log = std.log.scoped(.gfx_mesh);

allocator: std.mem.Allocator,
nodes: NodeList = .empty,
vert_data: VertexList = .empty,
index_data: IndexList = .empty,
vert_buf: ?*c.SDL_GPUBuffer = null,
index_buf: ?*c.SDL_GPUBuffer = null,
vert_byte_len: usize = 0,
index_byte_len: usize = 0,
vert_len: usize = 0,
index_len: usize = 0,
state: State = .cpu,

const Self = @This();
const NodeList = std.ArrayList(Node);
const VertexList = std.ArrayList(math.Scalar);
const IndexList = std.ArrayList(math.Index);

const State = enum {
    cpu,
    gpu,
    gpu_upload,
    gpu_mapped,
    gpu_uploaded,
};

pub const Node = struct {
    offset: usize,
    meta: Meta,

    pub const Target = enum {
        vert,
        index,
    };

    pub const Type = enum {
        object,
        group,
        smoothing,
        material,
    };

    pub const Meta = union(Type) {
        object: ?[]const u8,
        group: []const u8,
        smoothing: u32,
        material: []const u8,
    };
};

pub fn init(allocator: std.mem.Allocator) !Self {
    var result = Self{ .allocator = allocator };
    try result.appendMeta(.{ .object = null }, .vert);
    return result;
}

pub fn deinit(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
    self.releaseGpuBuffers(gpu_device);
    self.freeCpuData();
    self.nodes.deinit(self.allocator);
}

pub fn appendVertices(self: *Self, comptime V: type, verts: []const V) !void {
    assert(self.state == .cpu);
    const ptr: [*]const math.Scalar = @ptrCast(verts.ptr);
    const len = verts.len * comptime math.elemLen(V);
    try self.vert_data.appendSlice(self.allocator, ptr[0..len]);
}

pub fn appendVerticesAll(self: *Self, comptime V: type, verts_all: []const []const V) !void {
    assert(self.state == .cpu);
    for (verts_all) |verts| {
        const ptr: [*]const math.Scalar = @ptrCast(verts.ptr);
        const len = verts.len * comptime math.elemLen(V);
        try self.vert_data.appendSlice(self.allocator, ptr[0..len]);
    }
}

pub fn appendFaces(self: *Self, comptime F: type, faces: []const F) !void {
    assert(self.state == .cpu);
    const ptr: [*]const math.Index = @ptrCast(faces.ptr);
    const len = faces.len * comptime math.elemLen(F);
    try self.index_data.appendSlice(self.allocator, ptr[0..len]);
}

pub fn appendFacesAll(self: *Self, comptime F: type, faces_all: []const []const F) !void {
    assert(self.state == .cpu);
    for (faces_all) |faces| {
        const ptr: [*]const math.Index = @ptrCast(faces.ptr);
        const len = faces.len * comptime math.elemLen(F);
        try self.index_data.appendSlice(self.allocator, ptr[0..len]);
    }
}

pub fn appendMeta(self: *Self, meta: Node.Meta, comptime target: Node.Target) !void {
    const offset = switch (comptime target) {
        .vert => self.vert_data.items.len,
        .index => self.index_data.items.len,
    };
    try self.nodes.append(self.allocator, .{
        .offset = offset,
        .meta = meta,
    });
}

pub fn freeCpuData(self: *Self) void {
    assert(self.state == .cpu or self.state == .gpu);
    self.vert_data.clearAndFree(self.allocator);
    self.index_data.clearAndFree(self.allocator);
}

pub fn createGpuBuffers(self: *Self, gpu_device: ?*c.SDL_GPUDevice) !void {
    assert(self.state == .cpu);
    assert(self.vert_buf == null);
    assert(self.index_buf == null);
    assert(self.vert_byte_len == 0);
    assert(self.index_byte_len == 0);
    assert(self.vert_len == 0);
    assert(self.index_len == 0);
    self.state = .gpu;

    errdefer self.releaseGpuBuffers(gpu_device);

    // self.vert_len = @divFloor(self.vert_data.items.len, math.elemLen(math.Vertex));
    self.vert_len = @divFloor(self.vert_data.items.len, 3 * math.elemLen(math.Vertex));
    self.vert_byte_len = std.mem.sliceAsBytes(self.vert_data.items).len;
    self.vert_buf = c.SDL_CreateGPUBuffer(gpu_device, &c.SDL_GPUBufferCreateInfo{
        .usage = c.SDL_GPU_BUFFERUSAGE_VERTEX,
        .size = @intCast(self.vert_byte_len),
    });
    if (self.vert_buf == null) {
        log.err("failed creating vertex buffer: {s}", .{c.SDL_GetError()});
        return error.BufferFailed;
    }

    if (self.index_data.items.len == 0) return;
    self.index_len = self.index_data.items.len;
    self.index_byte_len = std.mem.sliceAsBytes(self.index_data.items).len;
    self.index_buf = c.SDL_CreateGPUBuffer(gpu_device, &c.SDL_GPUBufferCreateInfo{
        .usage = c.SDL_GPU_BUFFERUSAGE_INDEX,
        .size = @intCast(self.index_byte_len),
    });
    if (self.index_buf == null) {
        log.err("failed creating index buffer: {s}", .{c.SDL_GetError()});
        return error.BufferFailed;
    }
}

pub fn releaseGpuBuffers(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
    assert(self.state == .cpu or self.state == .gpu);

    if (self.vert_buf != null) c.SDL_ReleaseGPUBuffer(gpu_device, self.vert_buf);
    if (self.index_buf != null) c.SDL_ReleaseGPUBuffer(gpu_device, self.index_buf);

    self.vert_buf = null;
    self.index_buf = null;
    self.vert_byte_len = 0;
    self.index_byte_len = 0;
    self.vert_len = 0;
    self.index_len = 0;
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
