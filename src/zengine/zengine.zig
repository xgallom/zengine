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
pub const perf = @import("perf.zig");
pub const scheduler = @import("scheduler.zig");
pub const time = @import("time.zig");

pub const RadixTree = @import("radix.zig").RadixTree;

pub const WindowSize = @import("engine.zig").WindowSize;
pub const Engine = @import("engine.zig").Engine;

const std = @import("std");
test {
    std.testing.refAllDecls(@This());
}
