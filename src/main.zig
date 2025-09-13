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

    var property_editor = zengine.ui.PropertyEditorWindow.init(allocators.gpa());
    defer property_editor.deinit();
    var editor_open = true;

    const gfx_node = try property_editor.appendNode(@typeName(gfx), "gfx");
    try renderer.addToPropertyEditor(&property_editor, gfx_node);

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

        if (ui.show_ui) controls.reset();

        var sdl_event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&sdl_event)) {
            if (ui.show_ui and c.ImGui_ImplSDL3_ProcessEvent(&sdl_event)) {
                switch (sdl_event.type) {
                    c.SDL_EVENT_QUIT => break :mainloop,
                    c.SDL_EVENT_KEY_DOWN => {
                        if (sdl_event.key.repeat) break;
                        switch (sdl_event.key.key) {
                            c.SDLK_1 => ui.show_ui = !ui.show_ui,
                            c.SDLK_2 => editor_open = !editor_open,
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
                        c.SDLK_0 => controls.set(.custom(2)),

                        c.SDLK_1 => ui.show_ui = !ui.show_ui,
                        c.SDLK_2 => editor_open = !editor_open,
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
                        c.SDLK_0 => controls.clear(.custom(2)),

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

        var coords: math.vector3.Coords = undefined;
        renderer.camera.coords(&coords);

        const delta = global.timeSinceLastFrame().toFloat().toValue32(.s);
        const rotation_speed = delta;
        const translation_speed = 20 * delta * speed_scale;
        const scale_speed = 15 * delta;

        log.debug("coords_norm: {any}", .{coords});

        // math.vector2.localCoords(&coordinates2, &.{ 0, 1 }, &.{ 1, 0 });

        if (controls.has(.yaw_neg))
            math.vector3.rotateDirectionScale(&renderer.camera.direction, &coords.x, -rotation_speed);
        if (controls.has(.yaw_pos))
            math.vector3.rotateDirectionScale(&renderer.camera.direction, &coords.x, rotation_speed);

        if (controls.has(.pitch_neg))
            math.vector3.rotateDirectionScale(&renderer.camera.direction, &coords.y, -rotation_speed);
        if (controls.has(.pitch_pos))
            math.vector3.rotateDirectionScale(&renderer.camera.direction, &coords.y, rotation_speed);

        // if (controls.has(.roll_neg))
        //     math.vector3.rotateDirectionScale(&renderer.camera.up, &coordinates.x, -rotation_speed);
        // if (controls.has(.roll_pos))
        //     math.vector3.rotateDirectionScale(&renderer.camera.up, &coordinates.x, rotation_speed);

        if (controls.has(.x_neg))
            math.vector3.translateScale(&renderer.camera.position, &coords.x, -translation_speed);
        if (controls.has(.x_pos))
            math.vector3.translateScale(&renderer.camera.position, &coords.x, translation_speed);

        if (controls.has(.y_neg))
            math.vector3.translateScale(&renderer.camera.position, &renderer.camera.up, -translation_speed);
        if (controls.has(.y_pos))
            math.vector3.translateScale(&renderer.camera.position, &renderer.camera.up, translation_speed);

        if (controls.has(.z_neg))
            math.vector3.translateDirectionScale(&renderer.camera.position, &coords.z, -translation_speed);
        if (controls.has(.z_pos))
            math.vector3.translateDirectionScale(&renderer.camera.position, &coords.z, translation_speed);

        {
            const scale = switch (renderer.camera.kind) {
                .ortographic => &renderer.camera.orto_scale,
                .perspective => &renderer.camera.fov,
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
            renderer.camera.kind = switch (renderer.camera.kind) {
                .ortographic => .perspective,
                .perspective => .ortographic,
            };
            controls.clear(.custom(2));
        }

        math.vector3.normalize(&renderer.camera.direction);
        renderer.camera.orto_scale = std.math.clamp(
            renderer.camera.orto_scale,
            gfx.Camera.orto_scale_min,
            gfx.Camera.orto_scale_max,
        );
        renderer.camera.fov = std.math.clamp(
            renderer.camera.fov,
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
