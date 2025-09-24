//!
//! The zengine graphics module
//!

const std = @import("std");

pub const Camera = @import("gfx/Camera.zig");
pub const mesh = @import("gfx/mesh.zig");
pub const obj_loader = @import("gfx/obj_loader.zig");
pub const Renderer = @import("gfx/Renderer.zig");
pub const shader = @import("gfx/shader.zig");
pub const Vertices = @import("gfx/Vertices.zig");

test {
    std.testing.refAllDecls(@This());
}
