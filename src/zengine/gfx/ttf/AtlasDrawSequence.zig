//!
//! The zengine gpu atlas draw sequence implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../../ext.zig").c;
const global = @import("../../global.zig");
const math = @import("../../math.zig");
const ui = @import("../../ui.zig");
const Error = @import("../error.zig").Error;
const types = @import("../types.zig");
const Text = @import("Text.zig");
const GPUTexture = @import("../GPUTexture.zig");

const log = std.log.scoped(.gfx_ttf_atlas_draw_sequence);

ptr: ?*c.TTF_GPUAtlasDrawSequence = null,

const Self = @This();
pub const invalid: Self = .{};

pub fn init(text: Text) !Self {
    return fromOwned(try create(text));
}

pub fn deinit(self: *Self) void {
    if (self.isValid()) destroy(self.toOwned());
}

pub fn create(text: Text) !*c.TTF_GPUAtlasDrawSequence {
    assert(text.isValid());
    const ptr = c.TTF_GetGPUTextDrawData(text.ptr);
    if (ptr == null) {
        log.err("failed creating text draw data: {s}", .{c.SDL_GetError()});
        return Error.TextFailed;
    }
    return ptr.?;
}

pub fn destroy(ptr: *c.TTF_GPUAtlasDrawSequence) void {
    c.TTF_DestroyText(ptr);
}

pub fn texture(self: Self) GPUTexture {
    assert(self.isValid());
    return .fromOwned(self.ptr.?.atlas_texture);
}

pub fn xy(self: Self) math.Point_f32 {
    assert(self.isValid());
    assert(self.ptr.?.xy != null);
    return .{ self.ptr.?.xy.*.x, self.ptr.?.xy.*.y };
}

pub fn uv(self: Self) math.Point_f32 {
    assert(self.isValid());
    assert(self.ptr.?.uv != null);
    return .{ self.ptr.?.uv.*.x, self.ptr.?.uv.*.y };
}

pub fn numVertices(self: Self) u32 {
    assert(self.isValid());
    return self.ptr.?.num_vertices;
}

pub fn indices(self: Self) []c_int {
    assert(self.isValid());
    return self.ptr.?.indices[0..self.ptr.?.num_indices];
}

pub fn imageType(self: Self) ImageType {
    assert(self.isValid());
    return @enumFromInt(self.ptr.?.image_type);
}

pub fn next(self: Self) ?Self {
    assert(self.isValid());
    return if (self.ptr.?.next) |n| .fromOwned(n) else null;
}

pub fn fromOwned(ptr: *c.TTF_GPUAtlasDrawSequence) Self {
    return .{ .ptr = ptr };
}

pub fn toOwned(self: *Self) *c.TTF_GPUAtlasDrawSequence {
    assert(self.isValid());
    defer self.ptr = null;
    return self.ptr.?;
}

pub fn toSDL(self: *const Self) *c.TTF_GPUAtlasDrawSequence {
    assert(self.isValid());
    return self.ptr.?;
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}

pub const ImageType = enum(c.TTF_ImageType) {
    invalid = c.TTF_IMAGE_INVALID,
    alpha = c.TTF_IMAGE_ALPHA,
    color = c.TTF_IMAGE_COLOR,
    sdf = c.TTF_IMAGE_SDF,
    pub const default: ImageType = .invalid;
};
