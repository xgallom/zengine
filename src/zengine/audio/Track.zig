//!
//! The zengine audio track implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const Error = @import("error.zig").Error;

const Audio = @import("Audio.zig");
const Mixer = @import("Mixer.zig");
const log = std.log.scoped(.audio_track);

ptr: ?*c.MIX_Track = null,

const Self = @This();
pub const invalid: Self = .{};

const MIX_PROP_STOP_FADE_OUT_MILLISECONDS_NUMBER = "SDL_mixer.stop.fade_out_milliseconds";

pub fn init(mixer: Mixer) !Self {
    return .fromOwned(try create(mixer));
}

pub fn deinit(self: *Self) void {
    if (self.isValid()) destroySelf(self.toOwned());
}

fn create(mixer: Mixer) !*c.MIX_Track {
    assert(mixer.isValid());
    const ptr = c.MIX_CreateTrack(mixer.ptr);
    if (ptr == null) {
        log.err("failed creating audio track: {s}", .{c.SDL_GetError()});
        return Error.TrackFailed;
    }
    return ptr.?;
}

fn destroySelf(ptr: *c.MIX_Track) void {
    c.MIX_DestroyTrack(ptr);
}

pub fn setAudio(self: @This(), audio: Audio) !void {
    assert(self.isValid());
    if (!c.MIX_SetTrackAudio(self.ptr, audio.ptr)) {
        log.err("failed setting track audio: {s}", .{c.SDL_GetError()});
        return Error.TrackFailed;
    }
}

pub fn gain(self: @This()) f32 {
    assert(self.isValid());
    return c.MIX_GetTrackGain(self.ptr);
}

pub fn setGain(self: @This(), value: f32) !void {
    assert(self.isValid());
    if (!c.MIX_SetTrackGain(self.ptr, value)) {
        log.err("failed setting track gain: {s}", .{c.SDL_GetError()});
        return Error.TrackFailed;
    }
}

pub fn setLooping(self: @This(), looping: bool) !void {
    assert(self.isValid());
    if (!c.SDL_SetNumberProperty(
        c.MIX_GetTrackProperties(self.ptr),
        c.MIX_PROP_PLAY_LOOPS_NUMBER,
        if (looping) -1 else 0,
    )) {
        log.err("failed setting track looping: {s}", .{c.SDL_GetError()});
        return Error.TrackFailed;
    }
}

pub fn setFadeIn(self: @This(), fade_in_ms: u64) !void {
    assert(self.isValid());
    if (!c.SDL_SetNumberProperty(
        c.MIX_GetTrackProperties(self.ptr),
        c.MIX_PROP_PLAY_FADE_IN_MILLISECONDS_NUMBER,
        @intCast(fade_in_ms),
    )) {
        log.err("failed setting track fade in: {s}", .{c.SDL_GetError()});
        return Error.TrackFailed;
    }
}

pub fn setFadeOut(self: @This(), fade_out_ms: u64) !void {
    assert(self.isValid());
    if (!c.SDL_SetNumberProperty(
        c.MIX_GetTrackProperties(self.ptr),
        MIX_PROP_STOP_FADE_OUT_MILLISECONDS_NUMBER,
        @intCast(fade_out_ms),
    )) {
        log.err("failed setting track fade out: {s}", .{c.SDL_GetError()});
        return Error.TrackFailed;
    }
}

pub fn play(self: @This()) !void {
    assert(self.isValid());
    if (!c.MIX_PlayTrack(self.ptr, 0)) {
        log.err("failed playing audio track: {s}", .{c.SDL_GetError()});
        return Error.TrackFailed;
    }
}

pub fn stop(self: @This()) !void {
    assert(self.isValid());
    if (!c.MIX_StopTrack(
        self.ptr,
        c.MIX_MSToFrames(44100, c.SDL_GetNumberProperty(
            c.MIX_GetTrackProperties(self.ptr),
            MIX_PROP_STOP_FADE_OUT_MILLISECONDS_NUMBER,
            0,
        )),
    )) {
        log.err("failed stopping audio track: {s}", .{c.SDL_GetError()});
        return Error.TrackFailed;
    }
}

pub fn fromOwned(ptr: *c.MIX_Track) Self {
    return .{ .ptr = ptr };
}

pub fn toOwned(self: *Self) *c.MIX_Track {
    assert(self.isValid());
    defer self.ptr = null;
    return self.ptr.?;
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}
