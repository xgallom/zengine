//!
//! The zengine main executable
//!

const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

const zengine = @import("zengine");
const allocators = zengine.allocators;
const ecs = zengine.ecs;
const gfx = zengine.gfx;
const Scene = zengine.Scene;
const global = zengine.global;
const math = zengine.math;
const perf = zengine.perf;
const c = zengine.ext.c;
const scheduler = zengine.scheduler;
const time = zengine.time;
const Engine = zengine.Engine;
const UI = zengine.ui.UI;

const log = std.log.scoped(.main);
const main_section = perf.section(@This()).sub(.main);
const sections = main_section.sections(&.{ .init, .load, .frame });

pub const std_options: std.Options = .{
    .log_level = .info,
    .log_scope_levels = &.{
        // .{ .scope = .alloc, .level = .debug },
        // .{ .scope = .engine, .level = .debug },
        // .{ .scope = .gfx_mesh, .level = .debug },
        // .{ .scope = .gfx_obj_loader, .level = .debug },
        // .{ .scope = .gfx_renderer, .level = .debug },
        // .{ .scope = .gfx_shader, .level = .debug },
        // .{ .scope = .gfx_loader, .level = .debug },
        // .{ .scope = .key_tree, .level = .debug },
        // .{ .scope = .radix_tree, .level = .debug },
        // .{ .scope = .scheduler, .level = .debug },
        // .{ .scope = .tree, .level = .debug },
        // .{ .scope = .scene, .level = .debug },
    },
};

pub const zengine_options: zengine.Options = .{
    .has_debug_ui = false,
    .gfx = .{
        .enable_normal_smoothing = true,
        .normal_smoothing_angle_limit = 89,
    },
};

pub fn main() !void {
    // memory limit 1GB, SDL allocations are not tracked
    allocators.init(1_000_000_000);
    defer allocators.deinit();

    const engine = try Engine.create();
    defer engine.deinit();

    try perf.init();
    defer perf.deinit();

    try main_section.register();
    try sections.register();
    try sections.sub(.load)
        .sections(&.{ .gfx, .scene, .ui })
        .register();
    try sections.sub(.frame)
        .sections(&.{ .init, .input, .update, .render })
        .register();

    try global.init();
    defer global.deinit();

    main_section.begin();
    sections.sub(.init).begin();

    try engine.initMainWindow();

    const renderer = try gfx.Renderer.create(engine);
    defer renderer.deinit(engine);

    const scene = try Scene.create();
    defer scene.deinit();

    const ui = try UI.create(engine, renderer);
    defer ui.deinit();

    var task_list = try scheduler.TaskScheduler.init(allocators.gpa());
    defer task_list.deinit();

    var controls = zengine.controls.CameraControls{};
    var speed_change_timer = time.Timer.init(500);
    var speed_scale: f32 = 5;

    try perf.commitGraph();
    defer perf.releaseGraph();

    sections.sub(.init).end();
    sections.sub(.load).begin();
    sections.sub(.load).sub(.gfx).begin();

    var gfx_loader = try gfx.Loader.init(renderer);
    defer gfx_loader.deinit();
    {
        errdefer gfx_loader.cancel();

        _ = try gfx_loader.loadMesh(scene, "Cat", "cat.obj");
        _ = try gfx_loader.loadMesh(scene, "Black Cat", "black_cat.obj");
        _ = try gfx_loader.loadMesh(scene, "Cow", "cow_nonormals.obj");
        _ = try gfx_loader.loadMesh(scene, "Mountain", "mountain.obj");
        _ = try gfx_loader.loadMesh(scene, "Cube", "cube.obj");
        _ = try gfx_loader.createOriginMesh();
        _ = try gfx_loader.createDefaultMaterial();
        _ = try gfx_loader.createTestingMaterial();
        _ = try gfx_loader.createDefaultTexture();

        _ = try scene.createDefaultCamera();

        _ = try scene.createLight("Ambient", .ambient(.{
            .color = .{ 255, 255, 255 },
            .intensity = 0.05,
        }));
        _ = try scene.createLight("Directional Magenta", .directional(.{
            .color = .{ 127, 127, 127 },
            .intensity = 0.1,
        }));
        _ = try scene.createLight("Diffuse Red", .point(.{
            .color = .{ 255, 32, 64 },
            .intensity = 2e4,
        }));
        _ = try scene.createLight("Diffuse Green", .point(.{
            .color = .{ 32, 255, 64 },
            .intensity = 8e3,
        }));
        _ = try scene.createLight("Diffuse Blue", .point(.{
            .color = .{ 64, 32, 255 },
            .intensity = 2e4,
        }));

        _ = try gfx_loader.createLightsBuffer(scene, null);
        try gfx_loader.commit();
    }

    sections.sub(.load).sub(.gfx).end();
    sections.sub(.load).sub(.scene).begin();

    const pi = std.math.pi;

    _ = try scene.createRootNode(.light("Ambient"), &.{});
    const dir_light = try scene.createRootNode(.light("Directional Magenta"), &.{});

    const objects = try scene.createRootNode(.node("Objects"), &.{
        .order = .srt,
    });
    const ground = try scene.createRootNode(.node("Ground"), &.{
        .translation = .{ 0, -450, 0 },
        .scale = .{ 250, 250, 250 },
    });
    const lights = try scene.createRootNode(.node("Lights"), &.{});

    const cat = try scene.createChildNode(objects, .object("Cat"), &.{
        .translation = .{ 200, 0, 0 },
        .rotation = .{ -pi / 2.0, 0, 0 },
    });

    _ = try scene.createRootNode(.object("Black Cat"), &.{
        .translation = .{ 100, 0, 0 },
        .rotation = .{ -pi / 2.0, 0, 0 },
    });

    const cow = try scene.createChildNode(objects, .object("Cow"), &.{
        .translation = .{ 0, 0, 0 },
        .rotation = .{ 0, -pi / 2.0, 0 },
        .scale = .{ 10, 10, 10 },
    });

    _ = try scene.createChildNode(ground, .object("Plane"), &.{});
    _ = try scene.createChildNode(ground, .object("Landscape"), &.{});

    const cube_r = try scene.createChildNode(lights, .node("Red"), &.{
        .translation = .{ 100, 0, 0 },
    });
    _ = try scene.createChildNode(cube_r, .object("Cube Red"), &.{
        .scale = .{ 3, 3, 3 },
    });
    _ = try scene.createChildNode(cube_r, .light("Diffuse Red"), &.{});

    const cube_g = try scene.createChildNode(lights, .node("Green"), &.{
        .translation = .{ 0, 100, 0 },
    });
    _ = try scene.createChildNode(cube_g, .object("Cube Green"), &.{
        .scale = .{ 3, 3, 3 },
    });
    _ = try scene.createChildNode(cube_g, .light("Diffuse Green"), &.{});

    const cube_b = try scene.createChildNode(lights, .node("Blue"), &.{
        .translation = .{ -100, 0, 0 },
    });
    _ = try scene.createChildNode(cube_b, .object("Cube Blue"), &.{
        .scale = .{ 3, 3, 3 },
    });
    _ = try scene.createChildNode(cube_b, .light("Diffuse Blue"), &.{});

    // const cube = try render_items.push(.{
    //     .object = "Cube",
    //     .position = .{ 65, 0, 0 },
    //     .rotation = math.vertex.zero,
    //     .scale = .{ 3, 3, 3 },
    // });
    //
    // const smooth_cube = try render_items.push(.{
    //     .object = "Cube Smooth",
    //     .position = .{ -65, 0, 0 },
    //     .rotation = math.vertex.zero,
    //     .scale = .{ 3, 3, 3 },
    // });

    sections.sub(.load).sub(.scene).end();
    sections.sub(.load).sub(.ui).begin();

    var debug_ui = zengine.ui.DebugUI.init();

    var property_editor = zengine.ui.PropertyEditorWindow.init(allocators.global());
    defer property_editor.deinit();

    const gfx_node = try property_editor.appendNode(@typeName(gfx), "gfx");
    _ = try renderer.propertyEditorNode(&property_editor, gfx_node);

    const scene_node = try property_editor.appendNode(@typeName(Scene), "scene");
    _ = try scene.propertyEditorNode(&property_editor, scene_node);

    // const main_node = try property_editor.appendNode(@typeName(@This()), "main");
    // _ = try render_items.propertyEditorNode(&property_editor, main_node);

    var allocs_window = zengine.ui.AllocsWindow.init();
    var perf_window = zengine.ui.PerfWindow.init(allocators.global());

    sections.sub(.load).sub(.ui).end();
    sections.sub(.load).end();

    allocators.scratchRelease();

    var rnd = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
    var dir: math.Vertex = .{ 1, 0, 0 };

    return mainloop: while (true) {
        defer perf.reset();

        const section = sections.sub(.frame);
        main_section.push();
        section.begin();

        section.sub(.init).begin();

        defer allocators.frameReset();

        global.startFrame();
        defer global.finishFrame();

        const now = global.engineNow();
        perf.update(now);
        perf.updateStats(now, false);

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
                            c.SDLK_ESCAPE => ui.show_ui = !ui.show_ui,
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
                    const props = try engine.main_win.properties();
                    _ = try props.f32.put("mouse_x", sdl_event.motion.x);
                    _ = try props.f32.put("mouse_y", sdl_event.motion.y);
                },
                else => {},
            }
        }

        section.sub(.input).end();
        section.sub(.update).begin();

        const camera = scene.cameras.getPtr("default");

        var coords: math.vector3.Coords = undefined;
        camera.coords(&coords);

        const delta = global.timeSinceLastFrame().toFloat().toValue32(.s);
        const rotation_speed = delta;
        const translation_speed = 20 * delta * speed_scale;
        const scale_speed = 15 * delta;

        log.debug("coords_norm: {any}", .{coords});

        // math.vector2.localCoords(&coordinates2, &.{ 0, 1 }, &.{ 1, 0 });

        const time_s = global.timeSinceStart().toFloat().toValue32(.s) * 2;

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
            const scale = switch (camera.type) {
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
            camera.type = switch (camera.type) {
                .ortographic => .perspective,
                .perspective => .ortographic,
            };
            controls.clear(.custom(2));
        }

        math.vector3.normalize(&camera.direction);
        camera.orto_scale = std.math.clamp(
            camera.orto_scale,
            Scene.Camera.orto_scale_min,
            Scene.Camera.orto_scale_max,
        );
        camera.fov = std.math.clamp(
            camera.fov,
            Scene.Camera.fov_min,
            Scene.Camera.fov_max,
        );

        var flat_scene: Scene.Flattened = undefined;
        {
            errdefer gfx_loader.cancel();

            const cos = @cos(time_s);
            const sin = @sin(time_s);
            const x = 150 * cos;
            const y = 25 * cos;
            const z = 150 * sin;

            const rx: i64 = @intCast(rnd.next() % 31);
            const ry: i64 = @intCast(rnd.next() % 31);
            const rz: i64 = @intCast(rnd.next() % 31);
            const dx: f32 = @floatFromInt(rx - 15);
            const dy: f32 = @floatFromInt(ry - 15);
            const dz: f32 = @floatFromInt(rz - 15);

            var g_pos = cube_g.transform.translation;
            var axis: math.Vertex = .{ dx, dy, dz };
            math.vertex.normalize(&axis);
            math.vertex.rotateDirectionScale(&dir, &axis, 20 * delta);
            math.vertex.normalize(&dir);
            math.vertex.translateScale(&g_pos, &dir, 20 * delta);
            math.vertex.clamp(&g_pos, &.{ -100, -100, -100 }, &.{ 100, 100, 100 });

            const r_pos = .{ x, y + 55, z };
            const b_pos = .{ -x, -y + 55, -z };

            dir_light.transform.rotation[0] = time_s;

            objects.transform.translation[1] = 30 * cos + 30;
            objects.transform.rotation[0] = time_s / pi;
            objects.transform.rotation[1] = time_s;
            cat.transform.rotation[1] = 10 * time_s;
            cat.transform.translation[1] = 25 * @cos(5 * time_s);
            // cow.transform.rotation[0] = time_s;
            _ = cow;

            cube_r.transform.translation = r_pos;
            cube_g.transform.translation = g_pos;
            cube_b.transform.translation = b_pos;

            flat_scene = try scene.flatten();
            _ = try gfx_loader.createLightsBuffer(scene, &flat_scene);
            try gfx_loader.commit();
        }

        section.sub(.update).end();
        section.sub(.render).begin();

        ui.beginDraw();
        ui.drawMainMenuBar(.{
            .allocs_open = &allocs_window.is_open,
            .property_editor_open = &property_editor.is_open,
            .perf_open = &perf_window.is_open,
        });
        ui.drawDock();

        // if (ui.show_ui) c.igShowDemoWindow(&ui.show_ui);
        ui.draw(debug_ui.element(), &debug_ui.is_open);
        ui.draw(property_editor.element(), &property_editor.is_open);
        ui.draw(perf_window.element(), &perf_window.is_open);
        ui.draw(allocs_window.element(), &allocs_window.is_open);

        ui.endDraw();

        {
            var items: gfx.Renderer.Items = .init(&flat_scene);
            _ = try renderer.render(engine, scene, &flat_scene, ui, &items);
        }

        section.sub(.render).end();

        if (global.isFirstFrame()) {
            @branchHint(.cold);
            main_section.end();
            perf.updateStats(0, true);
        }

        section.end();
        main_section.pop();
    };
}
