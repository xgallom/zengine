//!
//! The zengine ttf module
//!

const std = @import("std");

pub const Font = @import("ttf/Font.zig");
pub const Text = @import("ttf/Text.zig");

test {
    std.testing.refAllDecls(@This());
}
