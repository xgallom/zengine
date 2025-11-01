//!
//! The zengine light implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");

const log = std.log.scoped(.gfx_light);

name: [:0]const u8 = "",
src: Source = .{},
type: Type = .default,

pub const Self = @This();

pub const Source = struct {
    color: math.RGBf32 = math.rgb_f32.zero,
    power: math.Scalar = 1,

    pub const color_max = 1;
    pub const color_min = 0;
    pub const color_speed = 0.05;
    pub const intensity_speed = 0.05;
};

pub const Type = enum {
    ambient,
    directional,
    point,
    pub const default = .ambient;
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

pub fn propertyEditor(self: *Self) ui.UI.Element {
    return ui.PropertyEditor(Self).init(self).element();
}
