//!
//! The zengine camera implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");

const log = std.log.scoped(.gfx_camera);

name: [:0]const u8 = "",
position: math.Vertex = math.vertex.zero,
direction: math.Vertex = .{ 1, 0, 0 },
up: math.Vertex = global.cameraUp(),
fov: f32 = 50,
orto_scale: f32 = 100,
type: Type = .perspective,

const Self = @This();

pub const Type = enum {
    ortographic,
    perspective,
};

pub const fov_min = 35;
pub const fov_max = 135;
pub const fov_speed = 0.1;
pub const orto_scale_min = 1;
pub const orto_scale_max = 1000;
pub const orto_scale_speed = 1;

pub fn transform(self: *const Self, result: *math.Matrix4x4) void {
    math.matrix4x4.camera(
        result,
        &self.position,
        &self.direction,
        &self.up,
    );
}

pub fn coords(self: *const Self, result: *math.vector3.Coords) void {
    math.vector3.localCoords(
        result,
        &self.direction,
        &self.up,
    );
}

pub fn projection(
    self: *const Self,
    result: *math.Matrix4x4,
    width: f32,
    height: f32,
    near_plane: f32,
    far_plane: f32,
) void {
    switch (self.type) {
        .ortographic => math.matrix4x4.ortographicScale(
            result,
            self.orto_scale,
            width,
            height,
            near_plane,
            far_plane,
        ),
        .perspective => math.matrix4x4.perspectiveFov(
            result,
            std.math.degreesToRadians(self.fov),
            width,
            height,
            near_plane,
            far_plane,
        ),
    }
}

pub fn propertyEditor(self: *Self) ui.UI.Element {
    return ui.PropertyEditor(Self).init(self).element();
}
