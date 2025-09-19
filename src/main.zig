const std = @import("std");
const assert = std.debug.assert;

const zengine = @import("zengine");
const allocators = zengine.allocators;
const ecs = zengine.ecs;
const gfx = zengine.gfx;
const global = zengine.global;
const math = zengine.math;
const perf = zengine.perf;
const c = zengine.ext.c;
const scheduler = zengine.scheduler;
const time = zengine.time;
const Engine = zengine.Engine;
const UI = zengine.ui.UI;
const RadixTree = zengine.RadixTree;

const log = std.log.scoped(.main);
const sections = perf.sections(@This(), &.{ .init, .frame });

pub const std_options: std.Options = .{
    .log_level = .info,
    // .log_scope_levels = &.{
    // .{ .scope = .alloc, .level = .debug },
    // .{ .scope = .engine, .level = .debug },
    // .{ .scope = .gfx_mesh, .level = .debug },
    // .{ .scope = .gfx_obj_loader, .level = .debug },
    // .{ .scope = .gfx_renderer, .level = .debug },
    // .{ .scope = .gfx_shader, .level = .debug },
    // .{ .scope = .key_tree, .level = .debug },
    // .{ .scope = .radix_tree, .level = .debug },
    // .{ .scope = .scheduler, .level = .debug },
    // },
};

pub const zengine_options: zengine.Options = .{};

pub fn main() !void {
    // memory limit 1GB, SDL allocations are not tracked
    try allocators.init(1_000_000_000);
    defer allocators.deinit();

    const engine = try Engine.init();
    defer engine.deinit();

    try perf.init();
    defer perf.deinit();

    try sections.register();
    try sections.sub(.frame)
        .sections(&.{ .init, .input, .update, .render })
        .register();

    sections.sub(.init).begin();

    try global.init();
    defer global.deinit();

    try engine.initWindow();

    const renderer = try gfx.Renderer.init(engine);
    defer renderer.deinit(engine);

    const ui = try UI.init(engine, renderer);
    defer ui.deinit();
    log.info("window size: {}", .{engine.window_size});

    var task_list = try scheduler.TaskScheduler.init(allocators.gpa());
    defer task_list.deinit();

    var log_timer = time.Timer.init(5000);

    var controls = zengine.controls.CameraControls{};
    var speed_change_timer = time.Timer.init(500);
    var speed_scale: f32 = 10;

    try perf.commitGraph();
    defer perf.releaseGraph();

    sections.sub(.init).end();

    const a = math.quat.init(std.math.degreesToRadians(90), &.{ 1, 0, 0 });
    const b = math.quat.init(std.math.degreesToRadians(90), &.{ 0, 1, 0 });

    var result: math.quat.Self = undefined;
    var x: math.Quat = undefined;
    math.quat.mulInto(&x, &b, &a);
    math.quat.apply(&result, &x, &.{ 0, 1, 0, 1 });
    // math.quat.apply(&result, &b, &x);
    log.info("a: {any}", .{a});
    log.info("b: {any}", .{b});
    log.info("r: {any}", .{result});

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

    var property_editor = zengine.ui.PropertyEditorWindow.init(allocators.frame());
    defer property_editor.deinit();
    const gfx_node = try property_editor.appendNode(@typeName(gfx), "gfx");
    try renderer.propertyEditorNode(&property_editor, gfx_node);

    var editor_open = true;

    return mainloop: while (true) {
        const section = sections.sub(.frame);
        section.begin();
        defer section.end();

        section.sub(.init).begin();

        defer allocators.frameReset();

        global.startFrame();
        defer global.finishFrame();

        const now = global.engineNow();
        perf.update(now);

        section.sub(.init).end();
        section.sub(.input).begin();

        if (ui.show_ui) {
            controls.reset();
        }

        var sdl_event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&sdl_event)) {
            if (ui.show_ui and c.ImGui_ImplSDL3_ProcessEvent(&sdl_event)) {
                switch (sdl_event.type) {
                    c.SDL_EVENT_QUIT => break :mainloop,
                    c.SDL_EVENT_KEY_DOWN => {
                        if (sdl_event.key.repeat) break;
                        switch (sdl_event.key.key) {
                            c.SDLK_F1 => ui.show_ui = !ui.show_ui,
                            c.SDLK_F2 => editor_open = !editor_open,
                            c.SDLK_ESCAPE => break :mainloop,
                            else => {},
                        }
                    },
                    else => {},
                }
                continue;
            }

            switch (sdl_event.type) {
                c.SDL_EVENT_QUIT => break :mainloop,
                c.SDL_EVENT_KEY_DOWN => {
                    if (sdl_event.key.repeat) break;
                    switch (sdl_event.key.key) {
                        c.SDLK_A => controls.set(.yaw_neg),
                        c.SDLK_D => controls.set(.yaw_pos),
                        c.SDLK_F => controls.set(.pitch_neg),
                        c.SDLK_R => controls.set(.pitch_pos),

                        c.SDLK_S => controls.set(.z_neg),
                        c.SDLK_W => controls.set(.z_pos),
                        c.SDLK_Q => controls.set(.x_neg),
                        c.SDLK_E => controls.set(.x_pos),
                        c.SDLK_X => controls.set(.y_neg),
                        c.SDLK_SPACE => controls.set(.y_pos),

                        c.SDLK_K => controls.set(.scale_neg),
                        c.SDLK_L => controls.set(.scale_pos),

                        c.SDLK_LEFTBRACKET => controls.set(.custom(0)),
                        c.SDLK_RIGHTBRACKET => controls.set(.custom(1)),
                        c.SDLK_EQUALS => controls.set(.custom(2)),

                        c.SDLK_F1 => ui.show_ui = !ui.show_ui,
                        c.SDLK_F2 => editor_open = !editor_open,
                        c.SDLK_ESCAPE => break :mainloop,
                        else => {},
                    }
                },
                c.SDL_EVENT_KEY_UP => {
                    switch (sdl_event.key.key) {
                        c.SDLK_A => controls.clear(.yaw_neg),
                        c.SDLK_D => controls.clear(.yaw_pos),
                        c.SDLK_F => controls.clear(.pitch_neg),
                        c.SDLK_R => controls.clear(.pitch_pos),

                        c.SDLK_S => controls.clear(.z_neg),
                        c.SDLK_W => controls.clear(.z_pos),
                        c.SDLK_Q => controls.clear(.x_neg),
                        c.SDLK_E => controls.clear(.x_pos),
                        c.SDLK_X => controls.clear(.y_neg),
                        c.SDLK_SPACE => controls.clear(.y_pos),

                        c.SDLK_K => controls.clear(.scale_neg),
                        c.SDLK_L => controls.clear(.scale_pos),

                        c.SDLK_LEFTBRACKET => controls.clear(.custom(0)),
                        c.SDLK_RIGHTBRACKET => controls.clear(.custom(1)),
                        c.SDLK_EQUALS => controls.clear(.custom(2)),

                        else => {},
                    }
                },
                c.SDL_EVENT_MOUSE_MOTION => {
                    engine.mouse_pos = .{
                        .x = sdl_event.motion.x,
                        .y = sdl_event.motion.y,
                    };
                },
                else => {},
            }
        }

        section.sub(.input).end();
        section.sub(.update).begin();

        const camera = renderer.cameras.getPtr("default");

        var coords: math.vector3.Coords = undefined;
        camera.coords(&coords);

        const delta = global.timeSinceLastFrame().toFloat().toValue32(.s);
        const rotation_speed = delta;
        const translation_speed = 20 * delta * speed_scale;
        const scale_speed = 15 * delta;

        log.debug("coords_norm: {any}", .{coords});

        // math.vector2.localCoords(&coordinates2, &.{ 0, 1 }, &.{ 1, 0 });

        if (controls.has(.yaw_neg))
            math.vector3.rotateDirectionScale(&camera.direction, &coords.x, -rotation_speed);
        if (controls.has(.yaw_pos))
            math.vector3.rotateDirectionScale(&camera.direction, &coords.x, rotation_speed);

        if (controls.has(.pitch_neg))
            math.vector3.rotateDirectionScale(&camera.direction, &coords.y, -rotation_speed);
        if (controls.has(.pitch_pos))
            math.vector3.rotateDirectionScale(&camera.direction, &coords.y, rotation_speed);

        // if (controls.has(.roll_neg))
        //     math.vector3.rotateDirectionScale(&renderer.camera.up, &coordinates.x, -rotation_speed);
        // if (controls.has(.roll_pos))
        //     math.vector3.rotateDirectionScale(&renderer.camera.up, &coordinates.x, rotation_speed);

        if (controls.has(.x_neg))
            math.vector3.translateScale(&camera.position, &coords.x, -translation_speed);
        if (controls.has(.x_pos))
            math.vector3.translateScale(&camera.position, &coords.x, translation_speed);

        if (controls.has(.y_neg))
            math.vector3.translateScale(&camera.position, &camera.up, -translation_speed);
        if (controls.has(.y_pos))
            math.vector3.translateScale(&camera.position, &camera.up, translation_speed);

        if (controls.has(.z_neg))
            math.vector3.translateDirectionScale(&camera.position, &coords.z, -translation_speed);
        if (controls.has(.z_pos))
            math.vector3.translateDirectionScale(&camera.position, &coords.z, translation_speed);

        {
            const scale = switch (camera.kind) {
                .ortographic => &camera.orto_scale,
                .perspective => &camera.fov,
            };

            if (controls.has(.scale_neg))
                scale.* -= scale_speed;
            if (controls.has(.scale_pos))
                scale.* += scale_speed;
        }

        if (controls.has(.custom(0)))
            speed_scale -= 5 * delta;
        if (controls.has(.custom(1)))
            speed_scale += 5 * delta;
        _ = &speed_change_timer;
        // speed_change_timer.update(now);

        if (controls.has(.custom(2))) {
            camera.kind = switch (camera.kind) {
                .ortographic => .perspective,
                .perspective => .ortographic,
            };
            controls.clear(.custom(2));
        }

        math.vector3.normalize(&camera.direction);
        camera.orto_scale = std.math.clamp(
            camera.orto_scale,
            gfx.Camera.orto_scale_min,
            gfx.Camera.orto_scale_max,
        );
        camera.fov = std.math.clamp(
            camera.fov,
            gfx.Camera.fov_min,
            gfx.Camera.fov_max,
        );

        section.sub(.update).end();
        section.sub(.render).begin();

        _ = try renderer.draw(engine, ui);

        // if (ui.show_ui) c.igShowDemoWindow(&ui.show_ui);
        ui.draw(property_editor.element(), &editor_open);

        _ = try renderer.endDraw(engine, ui);

        section.sub(.render).end();

        if (log_timer.updated(now)) {
            perf.updateAvg();
            perf.perf_sections.sub(.log).begin();

            log.info("frame[{}]@{D}", .{ global.frameIndex(), global.timeSinceStart().toValue(.ns) });
            allocators.logCapacities();
            perf.logPerf();

            perf.perf_sections.sub(.log).end();
            log.info("{f}", .{renderer});
            log.info("speed scale: {d:.3}", .{speed_scale});
        }
    };
}
