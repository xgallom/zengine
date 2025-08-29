//!
//! The zengine
//!

pub const allocator = @import("allocator.zig");
pub const allocators = @import("allocators.zig");
pub const ecs = @import("ecs.zig");
pub const ext = @import("ext.zig");
pub const gfx = @import("gfx.zig");
pub const global = @import("global.zig");
pub const math = @import("math.zig");
pub const scheduler = @import("scheduler.zig");

pub const engine = @import("engine.zig");
pub usingnamespace engine;

const std = @import("std");
test {
    std.testing.refAllDecls(@This());
}
