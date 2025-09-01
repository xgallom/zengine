//!
//! The zengine graphics module
//!

pub const Mesh = @import("gfx/mesh.zig").Mesh;
pub const LineMesh = @import("gfx/mesh.zig").LineMesh;
pub const TriangleMesh = @import("gfx/mesh.zig").TriangleMesh;
pub const Renderer = @import("gfx/renderer.zig").Renderer;

pub const obj_loader = @import("gfx/obj_loader.zig");
pub const shader = @import("gfx/shader.zig");
