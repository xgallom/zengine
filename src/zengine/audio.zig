    const AudioFormat = enum(c_int) {
        unknown = c.SDL_AUDIO_UNKNOWN,
        u8 = c.SDL_AUDIO_U8,
        s8 = c.SDL_AUDIO_S8,
        s16be = c.SDL_AUDIO_S16BE,
        s32be = c.SDL_AUDIO_S32BE,
        f32be = c.SDL_AUDIO_F32BE,
        s16 = c.SDL_AUDIO_S16,
        s32 = c.SDL_AUDIO_S32,
        f32 = c.SDL_AUDIO_F32,

        fn asText(format: @This()) []const u8 {
            return switch (format) {
                inline else => |fmt| @tagName(fmt),
            };
        }
    };

    var in_device_count: c_int = undefined;
    var in_devices: []c.SDL_AudioDeviceID = undefined;
    in_devices.ptr = c.SDL_GetAudioRecordingDevices(&in_device_count) orelse unreachable;
    in_devices.len = @intCast(in_device_count);
    var in_infos = try std.ArrayList(struct {
        name: [*:0]const u8,
        spec: c.SDL_AudioSpec,
        sample_frames: c_int,
    }).initCapacity(allocators.global(), in_devices.len);
    defer allocators.sdl().free(in_devices.ptr);
    for (in_devices) |id| {
        const info = in_infos.addOneAssumeCapacity();
        if (!c.SDL_GetAudioDeviceFormat(id, &info.spec, &info.sample_frames)) {
            log.err("failed getting audio spec for device {}: {s}", .{ id, c.SDL_GetError() });
            return;
        }
        const name = c.SDL_GetAudioDeviceName(id);
        if (name == null) {
            log.err("failed getting name for audio device {}: {s}", .{ id, c.SDL_GetError() });
            return;
        }
        info.name = name.?;
    }
    for (in_infos.items, in_devices) |info, id| {
        const name = info.name;
        const spec = info.spec;
        const sample_frames = info.sample_frames;
        log.info("audio in[{}]: {s} @{}Hz {t} {}ch {}f", .{
            id,
            name,
            spec.freq,
            @as(AudioFormat, @enumFromInt(spec.format)),
            spec.channels,
            sample_frames,
        });
    }

    var out_device_count: c_int = undefined;
    var out_devices: []c.SDL_AudioDeviceID = undefined;
    out_devices.ptr = c.SDL_GetAudioPlaybackDevices(&out_device_count) orelse unreachable;
    out_devices.len = @intCast(out_device_count);
    var out_infos = try std.ArrayList(struct {
        name: [*:0]const u8,
        spec: c.SDL_AudioSpec,
        sample_frames: c_int,
    }).initCapacity(allocators.global(), out_devices.len);
    defer allocators.sdl().free(out_devices.ptr);
    for (out_devices) |id| {
        const info = out_infos.addOneAssumeCapacity();
        if (!c.SDL_GetAudioDeviceFormat(id, &info.spec, &info.sample_frames)) {
            log.err("failed getting audio spec for device {}: {s}", .{ id, c.SDL_GetError() });
            return;
        }
        const name = c.SDL_GetAudioDeviceName(id);
        if (name == null) {
            log.err("failed getting name for audio device {}: {s}", .{ id, c.SDL_GetError() });
            return;
        }
        info.name = name.?;
    }
    for (out_infos.items, out_devices) |info, id| {
        const name = info.name;
        const spec = info.spec;
        const sample_frames = info.sample_frames;
        log.info("audio out[{}]: {s} @{}Hz {t} {}ch {}f", .{
            id,
            name,
            spec.freq,
            @as(AudioFormat, @enumFromInt(spec.format)),
            spec.channels,
            sample_frames,
        });
    }


