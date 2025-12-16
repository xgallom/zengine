//!
//! The zengine graphics module
//!

const std = @import("std");

pub const lerp = @import("anim/lerp.zig");
pub const smv = @import("anim/smv.zig");

test {
    std.testing.refAllDecls(@This());
}
