//!
//! The zengine global options
//!

const std = @import("std");
const root = @import("root");

const math = @import("math.zig");

pub const Options = struct {
    has_debug_ui: bool = std.debug.runtime_safety,
    log_allocations: bool = std.debug.runtime_safety,
    gfx: Gfx = .{},

    pub const Gfx = struct {
        default_material: [:0]const u8 = if (std.debug.runtime_safety) "testing" else "default",
        enable_normal_smoothing: bool = false,
        normal_smoothing_angle_limit: math.Scalar = 90.0,
    };
};

pub const options: Options = if (@hasDecl(root, "zengine_options")) root.zengine_options else .{};
pub const gfx_options = options.gfx;
