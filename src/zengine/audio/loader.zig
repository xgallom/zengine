//!
//! The zengine audio loader implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("ext");

const allocators = @import("../allocators.zig");
const fs = @import("../fs.zig");
const global = @import("../global.zig");
const Audio = @import("Audio.zig");
const Error = @import("error.zig").Error;
const Mixer = @import("Mixer.zig");

const log = std.log.scoped(.audio_loader);

const Self = @This();

pub const OpenConfig = struct {
    allocator: std.mem.Allocator,
    mixer: Mixer,
    file_path: []const u8,
};

pub fn loadFile(config: *const OpenConfig) !Audio {
    const buf = try fs.readFileAbsolute(config.allocator, config.file_path);
    defer config.allocator.free(buf);

    return try load(config, buf);
}

fn load(config: *const OpenConfig, buf: []const u8) !Audio {
    assert(config.mixer.isValid());
    const audio = c.MIX_LoadAudio_IO(
        config.mixer.ptr,
        c.SDL_IOFromConstMem(buf.ptr, buf.len),
        true,
        true,
    );
    if (audio == null) {
        log.err("audio load failed for \"{s}\": {s}", .{ config.file_path, c.SDL_GetError() });
        return Error.AudioFailed;
    }
    return .fromOwned(audio.?);
}
