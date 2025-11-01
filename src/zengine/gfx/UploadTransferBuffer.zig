//!
//! The zengine upload transfer buffer implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const math = @import("../math.zig");
const Error = @import("Error.zig").Error;
const GPUDevice = @import("GPUDevice.zig");
const MeshBuffer = @import("MeshBuffer.zig");
const GPUTransferBuffer = @import("GPUTransferBuffer.zig");
const SurfaceTexture = @import("SurfaceTexture.zig");
const GPUCopyPass = @import("GPUCopyPass.zig");

const log = std.log.scoped(.gfx_upload_transfer_buffer);

mesh_bufs: MeshBuffers = .empty,
surf_texes: SurfaceTextures = .empty,
tr_buf: GPUTransferBuffer = .invalid,
len: u32 = 0,
state: State = .invalid,

const Self = @This();
pub const MeshBuffers = std.ArrayList(*const MeshBuffer);
pub const SurfaceTextures = std.ArrayList(*const SurfaceTexture);
pub const State = enum { invalid, upload, mapped, uploaded };
pub const empty: Self = .{};

pub fn deinit(self: *Self, gpa: std.mem.Allocator, gpu_device: GPUDevice) void {
    self.mesh_bufs.deinit(gpa);
    self.surf_texes.deinit(gpa);

    if (self.state == .invalid) {
        assert(!self.tr_buf.isValid());
        return;
    }

    if (self.state == .mapped) {
        log.warn("transfer buffer mapped but not uploaded", .{});
        self.state = .upload;
    }
    self.tr_buf.deinit(gpu_device);
}

pub fn createGPUTransferBuffer(self: *Self, gpu_device: GPUDevice) !void {
    assert(self.state == .invalid);
    assert(!self.tr_buf.isValid());
    assert(self.len == 0);

    for (self.mesh_bufs.items) |gpu_buf| {
        self.len += gpu_buf.byteLen(.vertex);
        self.len += gpu_buf.byteLen(.index);
    }
    for (self.surf_texes.items) |surf_tex| self.len += surf_tex.surf.byteLen();

    self.tr_buf = GPUTransferBuffer.init(gpu_device, &.{
        .usage = .upload,
        .size = self.len,
    }) catch |err| {
        self.len = 0;
        return err;
    };

    self.state = .upload;
}

pub fn releaseGPUTransferBuffer(self: *Self, gpu_device: GPUDevice) void {
    assert(self.state == .upload or self.state == .uploaded);
    self.tr_buf.deinit(gpu_device);
    self.len = 0;
    self.state = .invalid;
}

pub fn map(self: *Self, gpu_device: GPUDevice) !void {
    assert(self.state == .upload);
    if (self.len == 0) {
        self.state = .mapped;
        return;
    }

    var mapping = try gpu_device.map(self.tr_buf, false);
    for (self.mesh_bufs.items) |mesh_buf| {
        const bufs = mesh_buf.slices();
        mapping.copy(bufs.vertex);
        if (bufs.index.len == 0) continue;
        if (mesh_buf.gpu_bufs.get(.index).size == 0) continue;
        mapping.copy(bufs.index);
    }

    for (self.surf_texes.items) |surf_tex| {
        mapping.copy(surf_tex.surf.slice(u8));
    }

    assert(mapping.offset == self.len);
    mapping.unmap();
    self.state = .mapped;
}

pub fn upload(self: *Self, copy_pass: GPUCopyPass) void {
    assert(self.state == .mapped);
    if (self.len == 0) {
        self.state = .uploaded;
        return;
    }

    var tb_offset: u32 = 0;
    for (self.mesh_bufs.items) |mesh_buf| {
        const len = mesh_buf.byteLens();
        copy_pass.uploadToBuffer(&.{
            .transfer_buffer = self.tr_buf,
            .offset = tb_offset,
        }, &.{
            .buffer = mesh_buf.gpu_bufs.get(.vertex),
            .offset = 0,
            .size = len.get(.vertex),
        }, false);
        tb_offset += len.get(.vertex);

        if (len.get(.index) == 0) continue;

        copy_pass.uploadToBuffer(&.{
            .transfer_buffer = self.tr_buf,
            .offset = tb_offset,
        }, &.{
            .buffer = mesh_buf.gpu_bufs.get(.index),
            .offset = 0,
            .size = len.get(.index),
        }, false);
        tb_offset += len.get(.index);
    }

    for (self.surf_texes.items) |surf_tex| {
        const is_valid = surf_tex.isValid();
        assert(is_valid.surf and is_valid.gpu_tex);

        copy_pass.uploadToTexture(&.{
            .transfer_buffer = self.tr_buf,
            .offset = tb_offset,
            .pixels_per_row = surf_tex.surf.width(),
            .rows_per_layer = surf_tex.surf.height(),
        }, &.{
            .texture = surf_tex.gpu_tex,
            .w = surf_tex.surf.width(),
            .h = surf_tex.surf.height(),
        }, false);
        tb_offset += surf_tex.surf.byteLen();
    }

    assert(tb_offset == self.len);
    self.state = .uploaded;
}
