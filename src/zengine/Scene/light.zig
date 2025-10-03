//!
//! The zengine scene light implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");

const log = std.log.scoped(.scene_light);

src: Source,
type: Type,

pub const Self = @This();

pub const Type = enum(u8) {
    ambient,
    directional,
    point,
};

pub fn ambient(src: Source) Self {
    return .{ .src = src, .type = .ambient };
}

pub fn directional(src: Source) Self {
    return .{ .src = src, .type = .directional };
}

pub fn point(src: Source) Self {
    return .{ .src = src, .type = .point };
}

pub const Source = struct {
    color: math.RGBu8 = math.rgbu8.zero,
    intensity: math.Scalar = 1,
};
