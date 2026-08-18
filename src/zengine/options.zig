//!
//! The zcore global options
//!

const std = @import("std");
const builtin = @import("builtin");
const root = @import("root");

const zcore = @import("zcore");

const gfx = @import("gfx.zig");
const math = @import("math.zig");

pub const Options = struct {
    core: Zcore = if (@hasDecl(root, "zcore_options")) root.zcore_options else .{},
    has_renderer: bool = true,
    has_scene: bool = true,
    has_ui: bool = true,
    has_debug_ui: bool = std.debug.runtime_safety,
    gfx: Gfx = .{},

    pub const Zcore = zcore.Options;
    pub const Gfx = struct {
        wanted_swapchain_composition: gfx.types.SwapchainComposition = .HDR_extended_linear,
        wanted_present_mode: gfx.types.PresentMode = .mailbox,
        create_textures: bool = true,
        default_material: [:0]const u8 = if (std.debug.runtime_safety) "testing" else "default",
        enable_normal_smoothing: bool = false,
        normal_smoothing_angle_limit: math.Scalar = 90.0,
    };
};

pub const options: Options = if (@hasDecl(root, "zengine_options")) root.zengine_options else .{};
pub const zcore_options = options.core;
pub const gfx_options = options.gfx;
