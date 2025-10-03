//!
//! The zengine scene object implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const gfx = @import("../gfx.zig");
const MeshObject = gfx.MeshObject;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");

const log = std.log.scoped(.scene_object);

mesh_obj: *MeshObject,

const Self = @This();

pub fn init(renderer: *gfx.Renderer, mesh_obj: []const u8) *Self {
    return fromMeshObject(renderer.mesh_objs.getPtr(mesh_obj));
}

pub fn fromMeshObject(mesh_obj: *MeshObject) *Self {
    return @ptrCast(mesh_obj);
}

pub fn toMeshObject(self: *Self) *MeshObject {
    return @ptrCast(self);
}

pub fn groups(self: *Self) []const MeshObject.Group {
    return self.toMeshObject().groups();
}
