//!
//! The zengine render passes module
//!

const std = @import("std");

pub const Bloom = @import("pass/Bloom.zig");
pub const TextureInterface = @import("pass/TextureInterface.zig");

test {
    std.testing.refAllDecls(@This());
}
