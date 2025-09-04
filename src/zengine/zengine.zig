//!
//! The zengine
//!

pub const allocators = @import("allocators.zig");
pub const controls = @import("controls.zig");
pub const ecs = @import("ecs.zig");
pub const ext = @import("ext.zig");
pub const gfx = @import("gfx.zig");
pub const global = @import("global.zig");
pub const math = @import("math.zig");
pub const perf = @import("perf.zig");
pub const scheduler = @import("scheduler.zig");
pub const time = @import("time.zig");

pub const RadixTree = @import("radix_tree.zig").RadixTree;
pub const Engine = @import("Engine.zig");

pub const raw_allocator = @import("allocator.zig").raw_sdl_allocator;

const std = @import("std");
test {
    std.testing.refAllDecls(@This());
}
