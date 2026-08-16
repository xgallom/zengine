const std = @import("std");

const c = @import("ext");

const allocators = @import("allocators.zig");
pub const Audio = @import("audio/Audio.zig");
pub const Error = @import("audio/error.zig").Error;
pub const loader = @import("audio/loader.zig");
pub const Mixer = @import("audio/Mixer.zig");
pub const Track = @import("audio/Track.zig");
const ArrayMap = @import("containers/key_map.zig").ArrayMap;

const log = std.log.scoped(.audio);

pub const System = struct {
    allocator: std.mem.Allocator,
    mixer: Mixer,
    audios: Audios,
    tracks: Tracks,

    const Self = @This();
    pub const Audios = ArrayMap(Audio);
    pub const Tracks = ArrayMap(Track);

    pub fn create() !*Self {
        return try createSelf(allocators.gpa());
    }

    pub fn deinit(self: *Self) void {
        const gpa = self.allocator;

        for (self.audios.map.values()) |*audio| audio.deinit();
        self.audios.deinit(gpa);
        for (self.tracks.map.values()) |*track| track.deinit();
        self.tracks.deinit(gpa);

        self.mixer.deinit();
    }

    fn createSelf(allocator: std.mem.Allocator) !*Self {
        var mixer: Mixer = try .init();
        if (!mixer.isValid()) {
            log.err("failed creating audio mixer: {s}", .{c.SDL_GetError()});
            return Error.MixerFailed;
        }
        errdefer mixer.deinit();

        const self = try allocators.global().create(Self);
        self.* = .{
            .allocator = allocator,
            .mixer = mixer,
            .audios = try .init(allocator, 128),
            .tracks = try .init(allocator, 128),
        };
        return self;
    }
};
