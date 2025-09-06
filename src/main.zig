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

    log.info("window size: {}", .{engine.window_size});

    var task_list = try scheduler.TaskScheduler.init(allocators.gpa());
    defer task_list.deinit();

    var log_timer = time.Timer.init(5000);

    var controls = zengine.controls.CameraControls{};
    var speed_change_timer = time.Timer.init(500);
    var speed_scale: f32 = 10;

    try perf.commitGraph();
    defer perf.releaseGraph();

    const main_scale = c.SDL_GetDisplayContentScale(c.SDL_GetPrimaryDisplay());
    _ = c.igCreateContext(null);
    const io = c.igGetIO_Nil().?;
    io.*.ConfigFlags |= c.ImGuiConfigFlags_NavEnableKeyboard;
    io.*.ConfigFlags |= c.ImGuiConfigFlags_DockingEnable;
    c.igStyleColorsDark(null);
    const style = c.igGetStyle().?;
    c.ImGuiStyle_ScaleAllSizes(style, main_scale);
    style.*.FontScaleDpi = main_scale;
    io.*.ConfigDpiScaleFonts = true;
    io.*.ConfigDpiScaleViewports = true;

    _ = c.ImGui_ImplSDL3_InitForSDLGPU(engine.window);
    var init_info: c.ImGui_ImplSDLGPU3_InitInfo = .{
        .Device = renderer.gpu_device,
        .ColorTargetFormat = c.SDL_GetGPUSwapchainTextureFormat(renderer.gpu_device, engine.window),
        .MSAASamples = c.SDL_GPU_SAMPLECOUNT_1,
    };
    _ = c.ImGui_ImplSDLGPU3_Init(&init_info);
    sections.sub(.init).end();

    var show_demo_window = false;
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

        if (show_demo_window) controls.reset();

        var sdl_event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&sdl_event)) {
            if (show_demo_window and c.ImGui_ImplSDL3_ProcessEvent(&sdl_event)) {
                switch (sdl_event.type) {
                    c.SDL_EVENT_QUIT => break :mainloop,
                    c.SDL_EVENT_KEY_DOWN => {
                        if (sdl_event.key.repeat) break;
                        switch (sdl_event.key.key) {
                            c.SDLK_1 => show_demo_window = !show_demo_window,
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

                        c.SDLK_K => controls.set(.fov_neg),
                        c.SDLK_L => controls.set(.fov_pos),

                        c.SDLK_LEFTBRACKET => controls.set(.custom(0)),
                        c.SDLK_RIGHTBRACKET => controls.set(.custom(1)),

                        c.SDLK_1 => show_demo_window = !show_demo_window,
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

                        c.SDLK_K => controls.clear(.fov_neg),
                        c.SDLK_L => controls.clear(.fov_pos),

                        c.SDLK_LEFTBRACKET => {
                            controls.clear(.custom(0));
                            // speed_change_timer.reset();
                        },
                        c.SDLK_RIGHTBRACKET => {
                            controls.clear(.custom(1));
                            // speed_change_timer.reset();
                        },

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

        var coordinates: math.vector3.Coords = undefined;
        math.vector3.localCoords(&coordinates, &renderer.camera_direction, &renderer.camera_up);

        const delta = global.timeSinceLastFrame().toFloat().toValue32(.s);
        const rotation_speed = delta;
        const translation_speed = 20 * delta * speed_scale;
        const fov_speed = 15 * delta;

        log.debug("coords_norm: {any}", .{coordinates});

        // math.vector2.localCoords(&coordinates2, &.{ 0, 1 }, &.{ 1, 0 });

        if (controls.has(.yaw_neg))
            math.vector3.rotateDirectionScale(&renderer.camera_direction, &coordinates.x, -rotation_speed);
        if (controls.has(.yaw_pos))
            math.vector3.rotateDirectionScale(&renderer.camera_direction, &coordinates.x, rotation_speed);

        if (controls.has(.pitch_neg))
            math.vector3.rotateDirectionScale(&renderer.camera_direction, &coordinates.y, -rotation_speed);
        if (controls.has(.pitch_pos))
            math.vector3.rotateDirectionScale(&renderer.camera_direction, &coordinates.y, rotation_speed);

        // if (controls.has(.roll_neg))
        //     math.vector3.rotateDirectionScale(&renderer.camera_up, &coordinates.x, -rotation_speed);
        // if (controls.has(.roll_pos))
        //     math.vector3.rotateDirectionScale(&renderer.camera_up, &coordinates.x, rotation_speed);

        if (controls.has(.x_neg))
            math.vector3.translateScale(&renderer.camera_position, &coordinates.x, -translation_speed);
        if (controls.has(.x_pos))
            math.vector3.translateScale(&renderer.camera_position, &coordinates.x, translation_speed);

        if (controls.has(.y_neg))
            math.vector3.translateScale(&renderer.camera_position, &renderer.camera_up, -translation_speed);
        if (controls.has(.y_pos))
            math.vector3.translateScale(&renderer.camera_position, &renderer.camera_up, translation_speed);

        if (controls.has(.z_neg))
            math.vector3.translateDirectionScale(&renderer.camera_position, &coordinates.z, -translation_speed);
        if (controls.has(.z_pos))
            math.vector3.translateDirectionScale(&renderer.camera_position, &coordinates.z, translation_speed);

        if (controls.has(.fov_neg))
            renderer.fov -= fov_speed;
        if (controls.has(.fov_pos))
            renderer.fov += fov_speed;

        if (controls.has(.custom(0))) {
            speed_scale -= 5 * delta;
            // if (speed_change_timer.updated(now)) speed_scale /= 2;
        } else if (controls.has(.custom(1))) {
            speed_scale += 5 * delta;
            // if (speed_change_timer.updated(now)) speed_scale *= 2;
        }
        speed_change_timer.update(now);

        if (controls.hasAny()) {
            math.vector3.normalize(&renderer.camera_direction);
            renderer.fov = std.math.clamp(renderer.fov, 35, 130);
        }

        section.sub(.update).end();
        section.sub(.render).begin();

        _ = try renderer.draw(engine, &show_demo_window);

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
