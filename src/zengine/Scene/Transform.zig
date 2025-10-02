//!
//! The zengine transform implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");

const log = std.log.scoped(.scene_transform);

translation: math.Vertex = math.vertex.zero,
rotation: math.Euler = math.vertex.zero,
rotation_order: math.EulerOrder = .xyz,
scale: math.Vertex = math.vertex.one,

const Self = @This();

pub fn transform(self: *const Self, result: *math.Matrix4x4) void {
    result.* = math.matrix4x4.identity;
    math.matrix4x4.scaleXYZ(result, &self.scale);
    math.matrix4x4.rotateEuler(result, &self.rotation, self.rotation_order);
    math.matrix4x4.translateXYZ(result, &self.position);
}
