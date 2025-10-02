//!
//! The zengine gpu buffer implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const math = @import("../math.zig");
const Tree = @import("../containers.zig").Tree;

const log = std.log.scoped(.gfx_gpu_buffer);

// TODO: Figure out a good implementation
// TODO: Figure out upload transfer buffers
// Suggestion: use a buffer size limit and add another buffer
// Can reuse transfer buffers, would complicate mesh loading
// Could have a segmented buffer that would automatically extend
// Suggestion: remove allocator?

pub const State = enum(u8) {
    cpu,
    gpu,
    gpu_upload,
    gpu_mapped,
    gpu_uploaded,
};

pub const Usage = enum(c.SDL_GPUBufferUsageFlags) {
    vertex = c.SDL_GPU_BUFFERUSAGE_VERTEX,
    index = c.SDL_GPU_BUFFERUSAGE_INDEX,
    indirect = c.SDL_GPU_BUFFERUSAGE_INDIRECT,
    graphics_storage_read = c.SDL_GPU_BUFFERUSAGE_GRAPHICS_STORAGE_READ,
    compute_storage_read = c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_READ,
    compute_storage_write = c.SDL_GPU_BUFFERUSAGE_COMPUTE_STORAGE_WRITE,
};
pub const UsageFlags = std.EnumSet(Usage);

allocator: std.mem.Allocator,
cpu_data: CPUData = .empty,
gpu_buf: ?*c.SDL_GPUBuffer = null,
gpu_len: u32 = 0,
state: State = .cpu,

const Self = @This();
pub const CPUData = std.array_list.Aligned(u8, .max(.of(math.Vector4), .of(math.batch.Batch)));

pub fn init(allocator: std.mem.Allocator) !Self {
    return .{ .allocator = allocator };
}

pub fn deinit(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
    self.releaseGPUBuffer(gpu_device);
    self.freeCPUData();
}

pub fn slice(self: *const Self, comptime T: type) []T {
    return @ptrCast(self.cpu_data.items);
}

pub fn ensureUnusedCapacity(self: *Self, comptime T: type, count: usize) !void {
    assert(self.state == .cpu);
    try self.cpu_data.ensureUnusedCapacity(
        self.allocator,
        count * comptime math.elemLen(T),
    );
}

pub fn append(self: *Self, comptime T: type, items: []const T) !void {
    assert(self.state == .cpu);
    return self.cpu_data.appendSlice(std.mem.sliceAsBytes(items));
}

pub fn appendAssumeCapacity(self: *Self, comptime T: type, items: []const T) void {
    assert(self.state == .cpu);
    return self.cpu_data.appendSliceAssumeCapacity(std.mem.sliceAsBytes(items));
}

pub fn appendSlice(self: *Self, comptime T: type, items_all: []const []const T) !void {
    for (items_all) |items| try self.append(T, items);
}

pub fn appendSliceAssumeCapacity(self: *Self, comptime T: type, items_all: []const []const T) void {
    for (items_all) |items| self.appendAssumeCapacity(T, items);
}

pub fn freeCPUData(self: *Self) void {
    assert(self.state == .cpu or self.state == .gpu);
    self.cpu_data.clearAndFree(self.allocator);
}

pub fn createGPUBuffer(self: *Self, gpu_device: ?*c.SDL_GPUDevice, usage: UsageFlags) !void {
    assert(self.state == .cpu);
    assert(self.gpu_buf == null);
    assert(self.gpu_len == 0);

    errdefer self.releaseGPUBuffer(gpu_device);

    self.gpu_len = self.cpu_data.items.len;
    self.gpu_buf = c.SDL_CreateGPUBuffer(gpu_device, &c.SDL_GPUBufferCreateInfo{
        .usage = usage.bits.mask,
        .size = self.gpu_len,
    });
    if (self.gpu_buf == null) {
        log.err("failed creating buffer: {s}", .{c.SDL_GetError()});
        return error.BufferFailed;
    }
    self.state = .gpu;
}

pub fn releaseGPUBuffer(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
    assert(self.state == .cpu or self.state == .gpu);
    if (self.gpu_buf != null) c.SDL_ReleaseGPUBuffer(gpu_device, self.gpu_buf);
    self.gpu_buf = null;
    self.gpu_len = 0;
    self.state = .cpu;
}

pub fn createUploadTransferBuffer(self: *Self, gpu_device: ?*c.SDL_GPUDevice) !UploadTransferBuffer {
    assert(self.state == .gpu);
    assert(self.gpu_buf != null);
    assert(self.gpu_len != 0);

    const transfer_buffer = c.SDL_CreateGPUTransferBuffer(gpu_device, &c.SDL_GPUTransferBufferCreateInfo{
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = self.gpu_len,
    });
    if (transfer_buffer == null) {
        log.err("failed creating transfer buffer: {s}", .{c.SDL_GetError()});
        return error.BufferFailed;
    }

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
            const src = std.mem.sliceAsBytes(tb.self.cpu_data.items);
            const byte_len = tb.self.gpu_len;
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

        var tb_offset: u32 = 0;
        {
            const byte_len = tb.self.gpu_len;
            assert(byte_len != 0);
            c.SDL_UploadToGPUBuffer(copy_pass, &c.SDL_GPUTransferBufferLocation{
                .transfer_buffer = tb.transfer_buffer,
                .offset = tb_offset,
            }, &c.SDL_GPUBufferRegion{
                .buffer = tb.self.gpu_buf,
                .offset = 0,
                .size = byte_len,
            }, false);
            tb_offset += byte_len;
        }

        tb.self.state = .gpu_uploaded;
    }
};
