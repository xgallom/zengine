//!
//! The zengine ttf font implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../../ext.zig").c;
const global = @import("../../global.zig");
const math = @import("../../math.zig");
const ui = @import("../../ui.zig");
const Error = @import("../error.zig").Error;
const GPUTextEngine = @import("../GPUTextEngine.zig");
const types = @import("../types.zig");

const log = std.log.scoped(.gfx_ttf_font);

ptr: ?*c.TTF_Font = null,

const Self = @This();
pub const invalid: Self = .{};

pub fn deinit(self: *Self) void {
    if (self.isValid()) close(self.toOwned());
}

pub fn close(ptr: *c.TTF_Font) void {
    c.TTF_CloseFont(ptr);
}

pub fn fromOwned(ptr: *c.TTF_Font) Self {
    return .{ .ptr = ptr };
}

pub fn toOwned(self: *Self) *c.TTF_Font {
    assert(self.isValid());
    defer self.ptr = null;
    return self.ptr.?;
}

pub fn toSDL(self: *const Self) *c.TTF_Font {
    assert(self.isValid());
    return self.ptr.?;
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}
