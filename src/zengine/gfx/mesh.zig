const std = @import("std");
const assert = std.debug.assert;

const math = @import("../math.zig");
const sdl = @import("../ext.zig").sdl;

pub const Mesh = struct {
    allocator: std.mem.Allocator,
    vertices: ArrayList,
    faces: IndexArrayList,
    vertex_buffer: ?*sdl.SDL_GPUBuffer = null,
    index_buffer: ?*sdl.SDL_GPUBuffer = null,

    const Self = @This();
    const ArrayList = std.ArrayListUnmanaged(math.Vertex);
    const IndexArrayList = std.ArrayListUnmanaged(math.FaceIndex);

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .vertices = ArrayList{},
            .faces = IndexArrayList{},
        };
    }

    pub fn deinit(self: *Self) void {
        self.vertices.deinit(self.allocator);
        self.faces.deinit(self.allocator);
    }

    pub fn create_gpu_buffers(self: *Self, gpu_device: ?*sdl.SDL_GPUDevice) !void {
        assert(self.vertex_buffer == null);
        assert(self.index_buffer == null);

        self.vertex_buffer = sdl.SDL_CreateGPUBuffer(gpu_device, &sdl.SDL_GPUBufferCreateInfo{
            .usage = sdl.SDL_GPU_BUFFERUSAGE_VERTEX,
            .size = @intCast(@sizeOf(math.Vertex) * self.vertices.items.len),
        });
        if (self.vertex_buffer == null) {
            std.log.err("failed creating vertex_buffer: {s}", .{sdl.SDL_GetError()});
            return error.BufferFailed;
        }
        errdefer sdl.SDL_ReleaseGPUBuffer(gpu_device, self.vertex_buffer);

        self.index_buffer = sdl.SDL_CreateGPUBuffer(gpu_device, &sdl.SDL_GPUBufferCreateInfo{
            .usage = sdl.SDL_GPU_BUFFERUSAGE_INDEX,
            .size = @intCast(@sizeOf(math.FaceIndex) * self.faces.items.len),
        });
        if (self.index_buffer == null) {
            std.log.err("failed creating index_buffer: {s}", .{sdl.SDL_GetError()});
            return error.BufferFailed;
        }
        errdefer sdl.SDL_ReleaseGPUBuffer(gpu_device, self.index_buffer);
    }

    pub fn release_gpu_buffers(self: *Self, gpu_device: ?*sdl.SDL_GPUDevice) void {
        if (self.vertex_buffer != null) sdl.SDL_ReleaseGPUBuffer(gpu_device, self.vertex_buffer);
        if (self.index_buffer != null) sdl.SDL_ReleaseGPUBuffer(gpu_device, self.index_buffer);
        self.vertex_buffer = null;
        self.index_buffer = null;
    }

    pub const UploadTransferBuffer = struct {
        mesh: *const Self,
        transfer_buffer: *sdl.SDL_GPUTransferBuffer,

        pub fn release(self: UploadTransferBuffer, gpu_device: ?*sdl.SDL_GPUDevice) void {
            sdl.SDL_ReleaseGPUTransferBuffer(gpu_device, self.transfer_buffer);
        }

        pub fn map(self: UploadTransferBuffer, gpu_device: ?*sdl.SDL_GPUDevice) !void {
            const mesh = self.mesh;
            const transfer_buffer_ptr = sdl.SDL_MapGPUTransferBuffer(gpu_device, self.transfer_buffer, false);
            if (transfer_buffer_ptr == null) {
                std.log.err("failed mapping transfer_buffer_ptr: {s}", .{sdl.SDL_GetError()});
                return error.BufferFailed;
            }

            const vertex_data = @as([*]math.Vertex, @ptrCast(@alignCast(transfer_buffer_ptr)));
            @memcpy(vertex_data, mesh.vertices.items);

            const index_data = @as([*]math.FaceIndex, @ptrCast(@alignCast(&vertex_data[mesh.vertices.items.len])));
            @memcpy(index_data, mesh.faces.items);

            sdl.SDL_UnmapGPUTransferBuffer(gpu_device, self.transfer_buffer);
        }

        pub fn upload(self: UploadTransferBuffer, copy_pass: ?*sdl.SDL_GPUCopyPass) void {
            sdl.SDL_UploadToGPUBuffer(copy_pass, &sdl.SDL_GPUTransferBufferLocation{
                .transfer_buffer = self.transfer_buffer,
                .offset = 0,
            }, &sdl.SDL_GPUBufferRegion{
                .buffer = self.mesh.vertex_buffer,
                .offset = 0,
                .size = @intCast(@sizeOf(math.Vertex) * self.mesh.vertices.items.len),
            }, false);

            sdl.SDL_UploadToGPUBuffer(copy_pass, &sdl.SDL_GPUTransferBufferLocation{
                .transfer_buffer = self.transfer_buffer,
                .offset = @intCast(@sizeOf(math.Vertex) * self.mesh.vertices.items.len),
            }, &sdl.SDL_GPUBufferRegion{
                .buffer = self.mesh.index_buffer,
                .offset = 0,
                .size = @intCast(@sizeOf(math.FaceIndex) * self.mesh.faces.items.len),
            }, false);
        }
    };

    pub fn create_upload_transfer_buffer(self: *const Self, gpu_device: ?*sdl.SDL_GPUDevice) !UploadTransferBuffer {
        assert(self.vertex_buffer != null);
        assert(self.index_buffer != null);

        const transfer_buffer = sdl.SDL_CreateGPUTransferBuffer(gpu_device, &sdl.SDL_GPUTransferBufferCreateInfo{
            .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            .size = @intCast((@sizeOf(math.Vertex) * self.vertices.items.len) + (@sizeOf(math.FaceIndex) * self.faces.items.len)),
        });
        if (transfer_buffer == null) {
            std.log.err("failed creating transfer_buffer: {s}", .{sdl.SDL_GetError()});
            return error.BufferFailed;
        }

        return .{ .mesh = self, .transfer_buffer = transfer_buffer.? };
    }
};
