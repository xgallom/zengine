//!
//! The zengine audio mixer implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("ext");
const Error = @import("error.zig").Error;

const Audio = @import("Audio.zig");
const Mixer = @import("Mixer.zig");
const log = std.log.scoped(.audio_mixer);

ptr: ?*c.MIX_Mixer = null,

const Self = @This();
pub const invalid: Self = .{};

pub fn init() !Self {
    return fromOwned(try create());
}

pub fn deinit(self: *Self) void {
    if (self.isValid()) destroySelf(self.toOwned());
}

pub fn create() !*c.MIX_Mixer {
    const ptr = c.MIX_CreateMixerDevice(c.SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &.{
        .format = c.SDL_AUDIO_S16,
        .channels = 2,
        .freq = 44100,
    });
    if (ptr == null) {
        log.err("failed creating audio mixer: {s}", .{c.SDL_GetError()});
        return Error.MixerFailed;
    }
    return ptr.?;
}

pub fn destroySelf(ptr: *c.MIX_Mixer) void {
    _ = c.MIX_StopAllTracks(ptr, 0);
    c.MIX_DestroyMixer(ptr);
}

pub fn fromOwned(ptr: *c.MIX_Mixer) Self {
    return .{ .ptr = ptr };
}

pub fn toOwned(self: *Self) *c.MIX_Mixer {
    assert(self.isValid());
    defer self.ptr = null;
    return self.ptr.?;
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}
