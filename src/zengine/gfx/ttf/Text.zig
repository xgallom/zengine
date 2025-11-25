//!
//! The zengine ttf text implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../../ext.zig").c;
const global = @import("../../global.zig");
const math = @import("../../math.zig");
const ui = @import("../../ui.zig");
const Error = @import("../error.zig").Error;
const GPUTextEngine = @import("../GPUTextEngine.zig");
const AtlasDrawSequence = @import("AtlasDrawSequence.zig");
const types = @import("../types.zig");
const Font = @import("Font.zig");

const log = std.log.scoped(.gfx_ttf_text);

ptr: ?*c.TTF_Text = null,

const Self = @This();
pub const invalid: Self = .{};

pub fn init(text_engine: GPUTextEngine, font: Font, str: []const u8) !Self {
    return fromOwned(try create(text_engine, font, str));
}

pub fn deinit(self: *Self) void {
    if (self.isValid()) destroy(self.toOwned());
}

pub fn create(text_engine: GPUTextEngine, font: Font, str: []const u8) !*c.TTF_Text {
    assert(text_engine.isValid());
    assert(font.isValid());
    const ptr = c.TTF_CreateText(text_engine.ptr, font.ptr, str.ptr, str.len);
    if (ptr == null) {
        log.err("failed creating ttf text: {s}", .{c.SDL_GetError()});
        return Error.TextEngineFailed;
    }
    return ptr.?;
}

pub fn destroy(ptr: *c.TTF_Text) void {
    c.TTF_DestroyText(ptr);
}

pub fn drawData(self: Self) !AtlasDrawSequence {
    return .init(self);
}

pub fn fromOwned(ptr: *c.TTF_Text) Self {
    return .{ .ptr = ptr };
}

pub fn toOwned(self: *Self) *c.TTF_Text {
    assert(self.isValid());
    defer self.ptr = null;
    return self.ptr.?;
}

pub fn toSDL(self: *const Self) *c.TTF_Text {
    assert(self.isValid());
    return self.ptr.?;
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}
