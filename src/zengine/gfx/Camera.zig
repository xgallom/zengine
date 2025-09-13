//!
//! The zengine camera implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");

const log = std.log.scoped(.gfx_camera);

const Self = @This();

kind: Kind,
position: math.Vector3,
direction: math.Vector3,
up: math.Vector3 = global.cameraUp(),
fov: f32 = 45,
orto_scale: f32 = 1,

pub const position_min: math.Vector3 = @splat(-1000);
pub const position_max: math.Vector3 = @splat(1000);
pub const direction_min: math.Vector3 = @splat(-1000);
pub const direction_max: math.Vector3 = @splat(1000);
pub const fov_min = 35;
pub const fov_max = 135;
pub const fov_speed = 1;
pub const orto_scale_min = 1;
pub const orto_scale_max = 500;
pub const orto_scale_speed = 1;

pub const Kind = enum(c_uint) {
    ortographic,
    perspective,
};

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

pub fn projection(self: *const Self, result: *math.Matrix4x4, width: f32, height: f32, near_plane: f32, far_plane: f32) void {
    switch (self.kind) {
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

pub fn propertyEditor(self: *Self) ui.PropertyEditor(Self, "Camera") {
    return .init(self);
}
