//!
//! The zengine graphics module
//!

const std = @import("std");

pub const GPUBuffer = @import("gfx/GPUBuffer.zig");
pub const MeshBuffer = @import("gfx/MeshBuffer.zig");
pub const obj_loader = @import("gfx/obj_loader.zig");
pub const img = @import("gfx/img.zig");
pub const MaterialInfo = @import("gfx/MaterialInfo.zig");
pub const MeshObject = @import("gfx/MeshObject.zig");
pub const Loader = @import("gfx/Loader.zig");
pub const Renderer = @import("gfx/Renderer.zig");
pub const shader = @import("gfx/shader.zig");
pub const Vertices = @import("gfx/Vertices.zig");

test {
    std.testing.refAllDecls(@This());
}
