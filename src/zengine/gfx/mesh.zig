//!
//! The zengine mesh implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");
pub const Buffer = @import("mesh/Buffer.zig");
pub const Object = @import("mesh/Object.zig");

const log = std.log.scoped(.gfx_mesh);

pub const FaceType = enum {
    invalid,
    point,
    line,
    triangle,
    pub const arr_len = 3;
};

pub const face_vert_counts: std.EnumArray(FaceType, usize) = .init(.{
    .invalid = 0,
    .point = 1,
    .line = 2,
    .triangle = 3,
});
