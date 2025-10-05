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

pub const Type = enum {
    ambient,
    directional,
    point,
};

pub const Source = struct {
    color: math.RGBu8 = math.rgb_u8.zero,
    intensity: math.Scalar = 1,

    pub const color_type = ui.property_editor.InputType.scalar;
    pub const intensity_speed = 0.05;
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

pub fn propertyEditor(self: *Self) ui.PropertyEditor(Self) {
    return .init(self);
}
