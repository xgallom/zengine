//!
//! The zengine audio source implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const zcore = @import("zcore");
const allocators = zcore.allocators;
const c = zcore.ext;

const Audio = @import("Audio.zig");
const Error = @import("error.zig").Error;
const Mixer = @import("Mixer.zig");

const log = std.log.scoped(.audio_audio);

ptr: ?*c.MIX_Audio = null,

const Self = @This();
pub const invalid: Self = .{};

pub fn deinit(self: *Self) void {
    if (self.isValid()) destroySelf(self.toOwned());
}

fn destroySelf(ptr: *c.MIX_Audio) void {
    c.MIX_DestroyAudio(ptr);
}

pub fn fromOwned(ptr: *c.MIX_Audio) Self {
    return .{ .ptr = ptr };
}

pub fn toOwned(self: *Self) *c.MIX_Audio {
    assert(self.isValid());
    defer self.ptr = null;
    return self.ptr.?;
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}
