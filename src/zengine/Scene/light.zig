//!
//! The zengine lighting implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");

const log = std.log.scoped(.scene_light);

pub const Light = union(Type) {
    ambient: Ambient,
    directional: Directional,
    point: Point,

    pub const Type = enum(u8) {
        ambient,
        directional,
        point,
    };

    pub fn initAmbient(light: Ambient) Light {
        return .{ .ambient = light };
    }

    pub fn initDirectional(light: Directional) Light {
        return .{ .directional = light };
    }

    pub fn initPoint(light: Point) Light {
        return .{ .point = light };
    }

    pub const Data = struct {
        color: math.RGBu8 = math.rgbu8.zero,
        intensity: math.Scalar = 1,
    };

    pub const Ambient = struct {
        light: Data = .{},
    };

    pub const Directional = struct {
        light: Data = .{},
        direction: math.Vertex = .{ 1, 0, 0 },
    };

    pub const Point = struct {
        light: Data = .{},
        position: math.Vertex = math.vertex.zero,
    };
};
