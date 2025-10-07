//!
//! The zengine graphics module
//!

const std = @import("std");

pub const CPUBuffer = @import("gfx/CPUBuffer.zig");
pub const Error = @import("gfx/Error.zig").Error;
pub const GPUBuffer = @import("gfx/GPUBuffer.zig");
pub const GPUDevice = @import("gfx/GPUDevice.zig");
pub const GPUSampler = @import("gfx/GPUSampler.zig");
pub const GPUShader = @import("gfx/GPUShader.zig");
pub const GPUTexture = @import("gfx/GPUTexture.zig");
pub const img_loader = @import("gfx/img_loader.zig");
pub const Loader = @import("gfx/Loader.zig");
pub const MaterialInfo = @import("gfx/MaterialInfo.zig");
pub const MeshBuffer = @import("gfx/MeshBuffer.zig");
pub const MeshObject = @import("gfx/MeshObject.zig");
pub const mtl_loader = @import("gfx/mtl_loader.zig");
pub const obj_loader = @import("gfx/obj_loader.zig");
pub const Renderer = @import("gfx/Renderer.zig");
pub const shader_loader = @import("gfx/shader_loader.zig");
pub const Surface = @import("gfx/Surface.zig");
pub const SurfaceTexture = @import("gfx/SurfaceTexture.zig");
pub const UploadTransferBuffer = @import("gfx/UploadTransferBuffer.zig");
pub const Vertices = @import("gfx/Vertices.zig");

test {
    std.testing.refAllDecls(@This());
}
