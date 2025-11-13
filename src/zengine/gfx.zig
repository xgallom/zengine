//!
//! The zengine graphics module
//!

const std = @import("std");

const Properties = @import("Properties.zig");
pub const Camera = @import("gfx/Camera.zig");
pub const CPUBuffer = @import("gfx/CPUBuffer.zig");
pub const Error = @import("gfx/error.zig").Error;
pub const GPUBuffer = @import("gfx/GPUBuffer.zig");
pub const GPUCommandBuffer = @import("gfx/GPUCommandBuffer.zig");
pub const GPUCopyPass = @import("gfx/GPUCopyPass.zig");
pub const GPUDevice = @import("gfx/GPUDevice.zig");
pub const GPUGraphicsPipeline = @import("gfx/GPUGraphicsPipeline.zig");
pub const GPURenderPass = @import("gfx/GPURenderPass.zig");
pub const GPUSampler = @import("gfx/GPUSampler.zig");
pub const GPUShader = @import("gfx/GPUShader.zig");
pub const GPUTexture = @import("gfx/GPUTexture.zig");
pub const GPUTransferBuffer = @import("gfx/GPUTransferBuffer.zig");
pub const img_loader = @import("gfx/img_loader.zig");
pub const lgh_loader = @import("gfx/lgh_loader.zig");
pub const Light = @import("gfx/Light.zig");
pub const Loader = @import("gfx/Loader.zig");
pub const MaterialInfo = @import("gfx/MaterialInfo.zig");
pub const mesh = @import("gfx/mesh.zig");
pub const mtl_loader = @import("gfx/mtl_loader.zig");
pub const obj_loader = @import("gfx/obj_loader.zig");
pub const Renderer = @import("gfx/Renderer.zig");
pub const Scene = @import("gfx/Scene.zig");
pub const shader_loader = @import("gfx/shader_loader.zig");
pub const Surface = @import("gfx/Surface.zig");
pub const SurfaceTexture = @import("gfx/SurfaceTexture.zig");
pub const types = @import("gfx/types.zig");
pub const UploadTransferBuffer = @import("gfx/UploadTransferBuffer.zig");

pub const registry_list = Properties.registryList(&.{
    SurfaceTexture.Registry,
});
// pub const Vertices = @import("gfx/Vertices.zig");

test {
    std.testing.refAllDecls(@This());
}
