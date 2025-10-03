//!
//! The zengine scene node transform implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");

const log = std.log.scoped(.scene_transform);

translation: math.Vertex = math.vertex.zero,
order: math.TransformOrder = .default,
rotation: math.Euler = math.vertex.zero,
euler_order: math.EulerOrder = .default,
scale: math.Vertex = math.vertex.one,

const Self = @This();

pub const rotation_speed = 0.05;
pub const scale_speed = 0.1;

pub fn transform(self: *const Self, result: *math.Matrix4x4) void {
    result.* = math.matrix4x4.identity;
    math.matrix4x4.transform(
        result,
        &self.translation,
        &self.rotation,
        &self.scale,
        self.order,
        self.euler_order,
    );
}
