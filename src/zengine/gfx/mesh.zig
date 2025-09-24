const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const math = @import("../math.zig");

const log = std.log.scoped(.gfx_mesh);

pub fn Mesh(comptime V: type, comptime I: type) type {
    return struct {
        allocator: std.mem.Allocator,
        verts_len: usize = 0,
        faces_len: usize = 0,
        verts: ArrayList = .{},
        faces: IndexArrayList = .{},
        vertex_buffer: ?*c.SDL_GPUBuffer = null,
        index_buffer: ?*c.SDL_GPUBuffer = null,

        const Self = @This();
        pub const Vertex = V;
        pub const FaceIndex = I;
        const ArrayList = std.ArrayListUnmanaged(Vertex);
        const IndexArrayList = std.ArrayListUnmanaged(FaceIndex);

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator,
            };
        }

        pub fn freeCpuData(self: *Self) void {
            self.verts.clearAndFree(self.allocator);
            self.faces.clearAndFree(self.allocator);
        }

        pub fn deinit(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
            self.freeCpuData();
            self.releaseGpuBuffers(gpu_device);
        }

        pub fn appendVertex(self: *Self, vertex: Vertex) !void {
            try self.verts.append(self.allocator, vertex);
        }

        pub fn appendVertices(self: *Self, verts: []const Vertex) !void {
            try self.verts.appendSlice(self.allocator, verts);
        }

        pub fn appendFace(self: *Self, face: FaceIndex) !void {
            try self.faces.append(self.allocator, face);
        }

        pub fn appendFaces(self: *Self, faces: []const FaceIndex) !void {
            try self.faces.appendSlice(self.allocator, faces);
        }

        pub fn createGpuBuffers(self: *Self, gpu_device: ?*c.SDL_GPUDevice) !void {
            assert(self.vertex_buffer == null);
            assert(self.index_buffer == null);

            self.verts_len = self.verts.items.len;
            self.faces_len = self.faces.items.len;

            self.vertex_buffer = c.SDL_CreateGPUBuffer(gpu_device, &c.SDL_GPUBufferCreateInfo{
                .usage = c.SDL_GPU_BUFFERUSAGE_VERTEX,
                .size = @intCast(@sizeOf(Vertex) * self.verts_len),
            });
            if (self.vertex_buffer == null) {
                log.err("failed creating vertex buffer: {s}", .{c.SDL_GetError()});
                return error.BufferFailed;
            }
            errdefer c.SDL_ReleaseGPUBuffer(gpu_device, self.vertex_buffer);

            self.index_buffer = c.SDL_CreateGPUBuffer(gpu_device, &c.SDL_GPUBufferCreateInfo{
                .usage = c.SDL_GPU_BUFFERUSAGE_INDEX,
                .size = @intCast(@sizeOf(FaceIndex) * self.faces_len),
            });
            if (self.index_buffer == null) {
                log.err("failed creating index buffer: {s}", .{c.SDL_GetError()});
                return error.BufferFailed;
            }
            errdefer c.SDL_ReleaseGPUBuffer(gpu_device, self.index_buffer);
        }

        pub fn releaseGpuBuffers(self: *Self, gpu_device: ?*c.SDL_GPUDevice) void {
            if (self.vertex_buffer != null) c.SDL_ReleaseGPUBuffer(gpu_device, self.vertex_buffer);
            if (self.index_buffer != null) c.SDL_ReleaseGPUBuffer(gpu_device, self.index_buffer);
            self.vertex_buffer = null;
            self.index_buffer = null;
            self.verts_len = 0;
            self.faces_len = 0;
        }

        pub fn createUploadTransferBuffer(self: *const Self, gpu_device: ?*c.SDL_GPUDevice) !UploadTransferBuffer {
            assert(self.vertex_buffer != null);
            assert(self.index_buffer != null);

            const transfer_buffer = c.SDL_CreateGPUTransferBuffer(gpu_device, &c.SDL_GPUTransferBufferCreateInfo{
                .usage = c.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
                .size = @intCast((@sizeOf(Vertex) * self.verts_len) + (@sizeOf(FaceIndex) * self.faces_len)),
            });
            if (transfer_buffer == null) {
                log.err("failed creating transfer buffer: {s}", .{c.SDL_GetError()});
                return error.BufferFailed;
            }

            return .{ .mesh = self, .transfer_buffer = transfer_buffer.? };
        }

        pub const UploadTransferBuffer = struct {
            mesh: *const Self,
            transfer_buffer: *c.SDL_GPUTransferBuffer,
            is_mapped: bool = false,

            pub fn release(self: UploadTransferBuffer, gpu_device: ?*c.SDL_GPUDevice) void {
                c.SDL_ReleaseGPUTransferBuffer(gpu_device, self.transfer_buffer);
            }

            pub fn map(self: *UploadTransferBuffer, gpu_device: ?*c.SDL_GPUDevice) !void {
                assert(self.mesh.verts.items.len != 0);
                assert(self.mesh.faces.items.len != 0);

                const mesh = self.mesh;
                const transfer_buffer_ptr = c.SDL_MapGPUTransferBuffer(gpu_device, self.transfer_buffer, false);
                if (transfer_buffer_ptr == null) {
                    log.err("failed mapping transfer buffer: {s}", .{c.SDL_GetError()});
                    return error.BufferFailed;
                }

                const vertex_data = @as([*]Vertex, @ptrCast(@alignCast(transfer_buffer_ptr)));
                @memcpy(vertex_data, mesh.verts.items);

                const index_data = @as([*]FaceIndex, @ptrCast(@alignCast(&vertex_data[mesh.verts.items.len])));
                @memcpy(index_data, mesh.faces.items);

                c.SDL_UnmapGPUTransferBuffer(gpu_device, self.transfer_buffer);
                self.is_mapped = true;
            }

            pub fn upload(self: *const UploadTransferBuffer, copy_pass: ?*c.SDL_GPUCopyPass) void {
                assert(self.mesh.vertex_buffer != null);
                assert(self.mesh.index_buffer != null);
                assert(self.is_mapped);

                c.SDL_UploadToGPUBuffer(copy_pass, &c.SDL_GPUTransferBufferLocation{
                    .transfer_buffer = self.transfer_buffer,
                    .offset = 0,
                }, &c.SDL_GPUBufferRegion{
                    .buffer = self.mesh.vertex_buffer,
                    .offset = 0,
                    .size = @intCast(@sizeOf(Vertex) * self.mesh.verts.items.len),
                }, false);

                c.SDL_UploadToGPUBuffer(copy_pass, &c.SDL_GPUTransferBufferLocation{
                    .transfer_buffer = self.transfer_buffer,
                    .offset = @intCast(@sizeOf(Vertex) * self.mesh.verts.items.len),
                }, &c.SDL_GPUBufferRegion{
                    .buffer = self.mesh.index_buffer,
                    .offset = 0,
                    .size = @intCast(@sizeOf(FaceIndex) * self.mesh.faces.items.len),
                }, false);
            }
        };
    };
}

pub const TriangleMesh = Mesh(math.Vertex, math.FaceIndex);
pub const LineMesh = Mesh(math.Vertex, math.LineFaceIndex);
pub const AnyMesh = union(enum) {
    triangle: TriangleMesh,
    line: LineMesh,
};
