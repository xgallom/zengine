//!
//! The zengine
//!

const std = @import("std");
const root = @import("root");

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
pub const perf = @import("perf.zig");
pub const scheduler = @import("scheduler.zig");
pub const sdl_allocator = @import("sdl_allocator.zig");
pub const time = @import("time.zig");
pub const ui = @import("ui.zig");

pub const Options = struct {
    has_debug_ui: bool = std.debug.runtime_safety,
};

pub const options: Options = if (@hasDecl(root, "zegnine_options")) root.zengine_options else .{};

test {
    std.testing.refAllDecls(@This());
}
