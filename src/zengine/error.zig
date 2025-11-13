//!
//! The zengine error type
//!

pub const gfx = @import("gfx/error.zig");

pub const Error = error{
    EngineFailed,
    WindowFailed,
    PropertiesFailed,
    PropertyFailed,
};
