//!
//! The zengine upload transfer buffer implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const math = @import("../math.zig");
const GPUBuffer = @import("GPUBuffer.zig");
const SurfaceTexture = @import("SurfaceTexture.zig");

const log = std.log.scoped(.gfx_gpu_transfer_buffer);

gpu_bufs: GPUBuffers = .empty,
surf_texes: SurfaceTextures = .empty,
transfer_buffer: ?*c.SDL_GPUTransferBuffer = null,
len: u32 = 0,
state: State = .invalid,

const Self = @This();
pub const GPUBuffers = std.ArrayList(*const GPUBuffer);
pub const SurfaceTextures = std.ArrayList(*const SurfaceTexture);

pub const State = enum {
    invalid,
    upload,
    mapped,
    uploaded,
};

pub const empty: Self = .{};

pub fn deinit(self: *Self, gpa: std.mem.Allocator, gpu_device: *c.SDL_GPUDevice) void {
    self.gpu_bufs.deinit(gpa);
    self.surf_texes.deinit(gpa);

    if (self.state == .invalid) {
        assert(self.transfer_buffer == null);
        return;
    }

    if (self.state == .mapped) {
        log.warn("transfer buffer mapped but not uploaded", .{});
        self.state = .upload;
    }
    self.releaseGPUTransferBuffer(gpu_device);
}

pub fn createGPUTransferBuffer(self: *Self, gpu_device: ?*c.SDL_GPUDevice) !void {
    assert(self.state == .invalid);
    assert(self.transfer_buffer == null);
    assert(self.len == 0);

    for (self.gpu_bufs.items) |gpu_buf| self.len += gpu_buf.byteLen();
    for (self.surf_texes.items) |surf_tex| self.len += surf_tex.surf.byteLen();

    self.transfer_buffer = c.SDL_CreateGPUTransferBuffer(gpu_device, &c.SDL_GPUTransferBufferCreateInfo{
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = self.len,
    });
    if (self.transfer_buffer == null) {
        log.err("failed creating transfer buffer: {s}", .{c.SDL_GetError()});
        self.len = 0;
        return error.BufferFailed;
    }

    self.state = .upload;
}

pub fn releaseGPUTransferBuffer(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
    assert(self.state == .upload or self.state == .uploaded);
    assert(self.transfer_buffer != null);
    c.SDL_ReleaseGPUTransferBuffer(gpu_device, self.transfer_buffer);
    self.transfer_buffer = null;
    self.len = 0;
    self.state = .invalid;
}

pub fn map(self: *Self, gpu_device: *c.SDL_GPUDevice) !void {
    assert(self.state == .upload);
    if (self.len == 0) {
        self.state = .mapped;
        return;
    }

    const tb_ptr = c.SDL_MapGPUTransferBuffer(gpu_device, self.transfer_buffer, false);
    if (tb_ptr == null) {
        log.err("failed mapping transfer buffer: {s}", .{c.SDL_GetError()});
        return error.BufferFailed;
    }

    const start: [*]u8 = @ptrCast(@alignCast(tb_ptr));
    var dest = start;
    for (self.gpu_bufs.items) |gpu_buf| {
        const cpu_buf = gpu_buf.slice(u8);
        assert(gpu_buf.len != 0);
        assert(cpu_buf.len <= gpu_buf.len);
        @memcpy(dest[0..cpu_buf.len], cpu_buf);
        dest += cpu_buf.len;
    }
    for (self.surf_texes.items) |surf_tex| {
        const cpu_buf = surf_tex.surf.slice(u8);
        assert(cpu_buf.len != 0);
        @memcpy(dest[0..cpu_buf.len], cpu_buf);
        dest += cpu_buf.len;
    }
    assert(dest - start == self.len);

    c.SDL_UnmapGPUTransferBuffer(gpu_device, self.transfer_buffer);
    self.state = .mapped;
}

pub fn upload(self: *Self, copy_pass: ?*c.SDL_GPUCopyPass) void {
    assert(self.state == .mapped);
    if (self.len == 0) {
        self.state = .uploaded;
        return;
    }

    var tb_offset: u32 = 0;
    for (self.gpu_bufs.items) |gpu_buf| {
        const len = gpu_buf.byteLen();
        assert(gpu_buf.state() != .cpu);
        c.SDL_UploadToGPUBuffer(copy_pass, &c.SDL_GPUTransferBufferLocation{
            .transfer_buffer = self.transfer_buffer,
            .offset = tb_offset,
        }, &c.SDL_GPUBufferRegion{
            .buffer = gpu_buf.gpu_buf,
            .offset = 0,
            .size = len,
        }, false);
        tb_offset += len;
    }
    for (self.surf_texes.items) |surf_tex| {
        assert(surf_tex.state() == .gpu);
        c.SDL_UploadToGPUTexture(copy_pass, &c.SDL_GPUTextureTransferInfo{
            .transfer_buffer = self.transfer_buffer,
            .offset = tb_offset,
            .pixels_per_row = surf_tex.surf.width(),
            .rows_per_layer = surf_tex.surf.height(),
        }, &c.SDL_GPUTextureRegion{
            .texture = surf_tex.gpu_tex.ptr,
            .w = surf_tex.surf.width(),
            .h = surf_tex.surf.height(),
        }, false);
        tb_offset += surf_tex.surf.byteLen();
    }
    assert(tb_offset == self.len);

    self.state = .uploaded;
}
