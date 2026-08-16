//!
//! The zengine core module
//!

const std = @import("std");
const assert = std.debug.assert;

pub const ext = @import("ext");

pub const allocators = @import("allocators.zig");
pub const ChunkAllocator = @import("ChunkAllocator.zig");
pub const LogAllocator = @import("log_allocator.zig").LogAllocator;
pub const Options = @import("options.zig").Options;
pub const options = @import("options.zig").options;
pub const sched = @import("sched.zig");
pub const sdl_allocator = @import("sdl_allocator.zig");
pub const str = @import("str.zig");
pub const time = @import("time.zig");

test {
    std.testing.log_level = .debug;
    std.testing.refAllDecls(@This());
}
