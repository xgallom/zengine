//!
//! The zengine texture implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");

const log = std.log.scoped(.gfx_camera);

surface: ?*c.SDL_Surface = null,
texture: ?*c.SDL_GPUTexture = null,
state: State = .cpu,

const Self = @This();

const State = enum {
    cpu,
    gpu,
    gpu_upload,
    gpu_mapped,
    gpu_uploaded,
};

pub fn init(surface: *c.SDL_Surface) Self {
    return .{ .surface = surface };
}

pub fn deinit(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
    self.releaseTexture(gpu_device);
    self.freeCpuData();
}

pub fn toTextureOwned(self: *Self) *c.SDL_GPUTexture {
    assert(self.state == .gpu);
    assert(self.texture != null);
    const texture = self.texture.?;
    self.texture = null;
    self.state = .cpu;
    return texture;
}

pub fn freeCpuData(self: *Self) void {
    assert(self.state == .cpu or self.state == .gpu);
    if (self.surface != null) c.SDL_DestroySurface(self.surface);
    self.surface = null;
}

pub fn createTexture(self: *Self, gpu_device: ?*c.SDL_GPUDevice) !void {
    assert(self.state == .cpu);
    assert(self.surface != null);
    assert(self.texture == null);

    self.texture = c.SDL_CreateGPUTexture(gpu_device, &c.SDL_GPUTextureCreateInfo{
        .type = c.SDL_GPU_TEXTURETYPE_2D,
        .format = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .usage = c.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = @intCast(self.surface.?.w),
        .height = @intCast(self.surface.?.h),
        .layer_count_or_depth = 1,
        .num_levels = 1,
    });
    if (self.texture == null) {
        log.err("failed creating texture: {s}", .{c.SDL_GetError()});
        return error.TextureFailed;
    }

    self.state = .gpu;
}

pub fn releaseTexture(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
    assert(self.state == .cpu or self.state == .gpu);
    if (self.texture != null) c.SDL_ReleaseGPUTexture(gpu_device, self.texture);
    self.texture = null;
    self.state = .cpu;
}

pub fn createUploadTransferBuffer(self: *Self, gpu_device: ?*c.SDL_GPUDevice) !UploadTransferBuffer {
    assert(self.state == .gpu);
    assert(self.surface != null);

    const transfer_buffer = c.SDL_CreateGPUTransferBuffer(gpu_device, &c.SDL_GPUTransferBufferCreateInfo{
        .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
        .size = @intCast(self.surface.?.h * self.surface.?.pitch),
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
        assert(tb.self.surface != null);

        const transfer_buffer_ptr = c.SDL_MapGPUTransferBuffer(gpu_device, tb.transfer_buffer, false);
        if (transfer_buffer_ptr == null) {
            log.err("failed mapping transfer buffer: {s}", .{c.SDL_GetError()});
            return error.BufferFailed;
        }

        var dest: [*]u8 = @ptrCast(@alignCast(transfer_buffer_ptr));
        {
            const src: [*]const u8 = @ptrCast(@alignCast(tb.self.surface.?.pixels.?));
            const byte_len: usize = @intCast(tb.self.surface.?.h * tb.self.surface.?.pitch);
            assert(byte_len != 0);
            @memcpy(dest[0..byte_len], src[0..byte_len]);
        }

        c.SDL_UnmapGPUTransferBuffer(gpu_device, tb.transfer_buffer);
        tb.self.state = .gpu_mapped;
    }

    pub fn upload(tb: *const UploadTransferBuffer, copy_pass: ?*c.SDL_GPUCopyPass) void {
        assert(tb.self.state == .gpu_mapped);
        assert(tb.self.surface != null);
        assert(tb.self.texture != null);

        c.SDL_UploadToGPUTexture(copy_pass, &c.SDL_GPUTextureTransferInfo{
            .transfer_buffer = tb.transfer_buffer,
            .offset = 0,
            .pixels_per_row = @intCast(tb.self.surface.?.w),
            .rows_per_layer = @intCast(tb.self.surface.?.h),
        }, &c.SDL_GPUTextureRegion{
            .texture = tb.self.texture,
            .w = @intCast(tb.self.surface.?.w),
            .h = @intCast(tb.self.surface.?.h),
        }, false);

        tb.self.state = .gpu_uploaded;
    }
};
