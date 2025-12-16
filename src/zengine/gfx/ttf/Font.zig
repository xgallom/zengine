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
const Surface = @import("../Surface.zig");
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

pub fn renderText(self: Self, text: []const u8, fg: math.RGBAu8) !Surface {
    assert(self.isValid());
    const ptr = c.TTF_RenderText_Blended(
        self.ptr,
        text.ptr,
        text.len,
        .{ .r = fg[0], .g = fg[1], .b = fg[2], .a = fg[3] },
    );
    if (ptr == null) {
        log.err("failed rendering text \"{s}\": {s}", .{ text, c.SDL_GetError() });
        return Error.FontFailed;
    }
    return .fromOwned(ptr.?);
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
