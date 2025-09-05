//!
//! The zengine
//!

const std = @import("std");

pub const allocator = @import("allocator.zig");
pub const raw_allocator = allocator.raw_sdl_allocator;
pub const allocators = @import("allocators.zig");
pub const controls = @import("controls.zig");
pub const ecs = @import("ecs.zig");
pub const Engine = @import("Engine.zig");
pub const ext = @import("ext.zig");
pub const gfx = @import("gfx.zig");
pub const global = @import("global.zig");
const KeyTree = @import("key_tree.zig").KeyTree;
pub const math = @import("math.zig");
pub const perf = @import("perf.zig");
const RadixTree = @import("radix_tree.zig").RadixTree;
pub const scheduler = @import("scheduler.zig");
pub const time = @import("time.zig");

test {
    std.testing.refAllDecls(@This());
}
