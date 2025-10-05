//!
//! The zengine
//!

const std = @import("std");

pub const allocators = @import("allocators.zig");
pub const containers = @import("containers.zig");
pub const controls = @import("controls.zig");
pub const ecs = @import("ecs.zig");
pub const Engine = @import("Engine.zig");
pub const ext = @import("ext.zig");
pub const fs = @import("fs.zig");
pub const gfx = @import("gfx.zig");
pub const global = @import("global.zig");
pub const math = @import("math.zig");
pub const Options = @import("options.zig").Options;
pub const options = @import("options.zig").options;
pub const perf = @import("perf.zig");
pub const Scene = @import("Scene.zig");
pub const scheduler = @import("scheduler.zig");
pub const sdl_allocator = @import("sdl_allocator.zig");
pub const time = @import("time.zig");
pub const ui = @import("ui.zig");
pub const Window = @import("Window.zig");

test {
    std.testing.refAllDecls(@This());
}
