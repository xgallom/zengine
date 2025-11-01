//!
//! The zengine main executable
//!

const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

const zengine = @import("zengine");
const ZEngine = zengine.ZEngine;
const allocators = zengine.allocators;
const ecs = zengine.ecs;
const Event = zengine.Event;
const gfx = zengine.gfx;
const Scene = zengine.gfx.Scene;
const global = zengine.global;
const math = zengine.math;
const perf = zengine.perf;
const c = zengine.ext.c;
const scheduler = zengine.scheduler;
const time = zengine.time;
const Engine = zengine.Engine;
const UI = zengine.ui.UI;
var mouse_motion: math.Point_f32 = math.point_f32.zero;

const log = std.log.scoped(.main);

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
        // .{ .scope = .gfx_shader_loader, .level = .debug },
        // .{ .scope = .tree, .level = .debug },
        // .{ .scope = .scene, .level = .debug },
    },
};

pub const zengine_options: zengine.Options = .{
    .has_debug_ui = false,
    .gfx = .{
        .enable_normal_smoothing = true,
        .normal_smoothing_angle_limit = 89.9,
    },
};

const Config = struct {
    flags: packed struct {
        mouse_captured: bool = true,
        mouse_y_inverted: bool = true,
        camera_controls: CameraControlsType = .y_up,
    } = .{},

    pub const CameraControlsType = enum(u1) {
        y_up,
        y_dynamic,
    };

    pub fn propertyEditor(self: *Config) UI.Element {
        return zengine.ui.PropertyEditor(Config).init(self).element();
    }
};

var flat_scene: Scene.Flattened = undefined;
var gfx_loader: gfx.Loader = undefined;

var controls = zengine.controls.CameraControls{};
var speed_scale: f32 = 10;

var rnd: std.Random.DefaultPrng = undefined;
var dir: math.Vertex = .{ 1, 0, 0 };

var debug_ui: zengine.ui.DebugUI = undefined;
var property_editor: zengine.ui.PropertyEditorWindow = undefined;
var allocs_window: zengine.ui.AllocsWindow = undefined;
var perf_window: zengine.ui.PerfWindow = undefined;

var scene_map: zengine.containers.ArrayMap(Scene.Node.Id) = .empty;

var config: Config = .{};

pub fn main() !void {
    // memory limit 1GB, SDL allocations are not tracked
    allocators.init(1_000_000_000);
    defer allocators.deinit();

    var engine: ZEngine = try .init(.{
        .load = &load,
        .unload = &unload,
        .input = &input,
        .update = &update,
        .render = &render,
    });
    defer engine.deinit();
    return engine.run();
}

fn load(self: *const ZEngine) !bool {
    rnd = .init(@intCast(std.time.milliTimestamp()));
    scene_map = try .init(self.scene.allocator, 128);
    var task_list = try scheduler.TaskScheduler.init(allocators.gpa());
    defer task_list.deinit();

    ZEngine.sections.sub(.load).sub(.gfx).begin();

    gfx_loader = try .init(self.renderer);
    errdefer gfx_loader.deinit();
    {
        errdefer gfx_loader.cancel();

        _ = try gfx_loader.loadMesh("Cat", "cat.obj");
        _ = try gfx_loader.loadMesh("Black Cat", "black_cat.obj");
        _ = try gfx_loader.loadMesh("Cow", "cow_nonormals.obj");
        _ = try gfx_loader.loadMesh("Mountain", "mountain.obj");
        _ = try gfx_loader.loadMesh("Cube", "cube.obj");
        _ = try gfx_loader.loadMesh("Cottage", "cottage_obj.obj");

        _ = try gfx_loader.createOriginMesh();
        _ = try gfx_loader.createDefaultMaterial();
        _ = try gfx_loader.createTestingMaterial();
        _ = try gfx_loader.createDefaultTexture();

        {
            var camera_position: math.Vertex = .{ 4, 8, 10 };
            var camera_direction: math.Vertex = undefined;

            math.vector3.scale(&camera_position, 50);
            math.vector3.lookAt(&camera_direction, &camera_position, &math.vector3.zero);

            _ = try self.renderer.insertCamera("default", &.{
                .type = .perspective,
                .position = camera_position,
                .direction = camera_direction,
            });
        }

        _ = try gfx_loader.loadLights("scene.lgh");
        _ = try gfx_loader.createLightsBuffer(null);
        try gfx_loader.commit();
    }

    ZEngine.sections.sub(.load).sub(.gfx).end();
    ZEngine.sections.sub(.load).sub(.scene).begin();

    const pi = std.math.pi;

    _ = try self.scene.createRootNode("Ambient Light", .light("Ambient"), &.{});
    const dir_light = try self.scene.createRootNode("Directional Light", .light("Directional"), &.{
        .rotation = .{ pi, -pi / 4.0, -pi / 3.0 },
    });

    const environment = try self.scene.createRootNode("Environment", .node(), &.{
        .translation = .{ 712, -54, 542 },
        .rotation = .{ 0, 4, 0 },
    });
    const cottage = try self.scene.createChildNode(environment, "Cottage", .node(), &.{
        .translation = .{ -346, -334, 1540 },
        .rotation = .{ -0.35, 2.45, -0.2 },
    });
    const ground = try self.scene.createChildNode(environment, "Ground", .node(), &.{
        .translation = .{ 0, -450, 0 },
        .scale = .{ 500, 250, 500 },
    });

    _ = try self.scene.createChildNode(cottage, "Cottage", .object("Cottage"), &.{
        .scale = .{ 20, 20, 20 },
    });

    _ = try self.scene.createChildNode(ground, "Plane", .object("Plane"), &.{});
    _ = try self.scene.createChildNode(ground, "Landscape", .object("Landscape"), &.{});

    const objects = try self.scene.createRootNode("Objects", .node(), &.{});
    const lights = try self.scene.createRootNode("Cubes", .node(), &.{
        .translation = .{ -58, -83, 18 },
        .scale = .{ 2.5, 2.5, 2.5 },
        .order = .trs,
    });

    const cat = try self.scene.createChildNode(objects, "Cat", .object("Cat"), &.{
        .translation = .{ -294, -176, 44 },
        .rotation = .{ -1.671, 0.4, 0.4 },
    });
    _ = try self.scene.createChildNode(objects, "Black Cat", .object("Black Cat"), &.{
        .translation = .{ -304, -176, 90 },
        .rotation = .{ -1.971, 2.1, 0 },
    });
    _ = try self.scene.createChildNode(objects, "Cow", .object("Cow"), &.{
        .translation = .{ -174, -237, -196 },
        .rotation = .{ 5.95, -1.721, 0 },
        .scale = .{ 10, 10, 10 },
        .euler_order = .zyx,
    });

    const cube_r = try self.scene.createChildNode(lights, "Red", .node(), &.{
        .translation = .{ 100, 0, 0 },
        .euler_order = .yxz,
    });
    _ = try self.scene.createChildNode(cube_r, "Light", .light("Cube Red"), &.{});
    _ = try self.scene.createChildNode(cube_r, "Mesh", .object("Cube Red"), &.{
        .scale = .{ 3, 3, 3 },
    });

    const cube_g = try self.scene.createChildNode(lights, "Green", .node(), &.{
        .translation = .{ 0, 100, 0 },
        .euler_order = .yxz,
    });
    _ = try self.scene.createChildNode(cube_g, "Light", .light("Cube Green"), &.{});
    _ = try self.scene.createChildNode(cube_g, "Mesh", .object("Cube Green"), &.{
        .scale = .{ 3, 3, 3 },
    });

    const cube_b = try self.scene.createChildNode(lights, "Blue", .node(), &.{
        .translation = .{ -100, 0, 0 },
        .euler_order = .yxz,
    });
    _ = try self.scene.createChildNode(cube_b, "Light", .light("Cube Blue"), &.{});
    _ = try self.scene.createChildNode(cube_b, "Mesh", .object("Cube Blue"), &.{
        .scale = .{ 3, 3, 3 },
    });

    try scene_map.insert(self.scene.allocator, "dir_light", dir_light);
    try scene_map.insert(self.scene.allocator, "objects", objects);
    try scene_map.insert(self.scene.allocator, "ground", ground);
    try scene_map.insert(self.scene.allocator, "lights", lights);
    try scene_map.insert(self.scene.allocator, "cat", cat);
    try scene_map.insert(self.scene.allocator, "cube_r", cube_r);
    try scene_map.insert(self.scene.allocator, "cube_g", cube_g);
    try scene_map.insert(self.scene.allocator, "cube_b", cube_b);

    ZEngine.sections.sub(.load).sub(.scene).end();
    ZEngine.sections.sub(.load).sub(.ui).begin();

    debug_ui = .init();
    property_editor = .init(allocators.global());
    allocs_window = .init();
    perf_window = .init(allocators.global());

    const gfx_node = try property_editor.appendNode(@typeName(gfx), "gfx");
    _ = try self.renderer.propertyEditorNode(&property_editor, gfx_node);

    const scene_node = try property_editor.appendNode(@typeName(Scene), "scene");
    _ = try self.scene.propertyEditorNode(&property_editor, scene_node);

    const main_node = try property_editor.appendNode(@typeName(@This()), "main");
    _ = try property_editor.appendChild(main_node, config.propertyEditor(), @typeName(Config), "config");

    self.engine.main_win.setRelativeMouseMode(config.flags.mouse_captured);

    ZEngine.sections.sub(.load).sub(.ui).end();
    allocators.scratchRelease();
    return true;
}

fn unload(self: *const ZEngine) void {
    scene_map.deinit(self.scene.allocator);
    gfx_loader.deinit();
    debug_ui.deinit();
    property_editor.deinit();
    allocs_window.deinit();
    perf_window.deinit();
}

fn input(self: *const ZEngine) !bool {
    if (self.ui.show_ui) {
        controls.reset();
    }

    while (Event.poll()) |event| {
        if (self.ui.show_ui and c.ImGui_ImplSDL3_ProcessEvent(&event.sdl)) {
            switch (event.type) {
                .quit => return false,
                .key_down => {
                    if (event.sdl.key.repeat) break;
                    switch (event.sdl.key.key) {
                        c.SDLK_F1 => {
                            self.ui.show_ui = !self.ui.show_ui;
                            self.engine.main_win.setRelativeMouseMode(!self.ui.show_ui and config.flags.mouse_captured);
                        },
                        c.SDLK_ESCAPE => {
                            self.ui.show_ui = !self.ui.show_ui;
                            self.engine.main_win.setRelativeMouseMode(!self.ui.show_ui and config.flags.mouse_captured);
                        },
                        else => {},
                    }
                },
                else => {},
            }
            continue;
        }

        switch (event.type) {
            .quit => return false,
            .key_down => {
                if (event.sdl.key.repeat) break;
                switch (event.sdl.key.key) {
                    c.SDLK_Q => controls.set(if (config.flags.mouse_captured) .x_neg else .yaw_neg),
                    c.SDLK_E => controls.set(if (config.flags.mouse_captured) .x_pos else .yaw_pos),
                    c.SDLK_F => controls.set(if (config.flags.mouse_captured) .y_neg else .pitch_neg),
                    c.SDLK_R => controls.set(if (config.flags.mouse_captured) .y_pos else .pitch_pos),
                    c.SDLK_C => controls.set(.roll_neg),
                    c.SDLK_V => controls.set(.roll_pos),

                    c.SDLK_S => controls.set(.z_neg),
                    c.SDLK_W => controls.set(.z_pos),
                    c.SDLK_A => controls.set(.x_neg),
                    c.SDLK_D => controls.set(.x_pos),
                    c.SDLK_X => controls.set(.y_neg),
                    c.SDLK_SPACE => controls.set(.y_pos),

                    c.SDLK_K => controls.set(.scale_neg),
                    c.SDLK_L => controls.set(.scale_pos),

                    c.SDLK_LEFTBRACKET => controls.set(.custom(0)),
                    c.SDLK_RIGHTBRACKET => controls.set(.custom(1)),
                    c.SDLK_EQUALS => controls.set(.custom(2)),

                    c.SDLK_F1 => {
                        self.ui.show_ui = !self.ui.show_ui;
                        self.engine.main_win.setRelativeMouseMode(!self.ui.show_ui and config.flags.mouse_captured);
                    },
                    c.SDLK_F2 => {
                        config.flags.mouse_captured = !config.flags.mouse_captured;
                        self.engine.main_win.setRelativeMouseMode(config.flags.mouse_captured);
                    },
                    c.SDLK_ESCAPE => return false,
                    else => {},
                }
            },
            .key_up => {
                switch (event.sdl.key.key) {
                    c.SDLK_Q => controls.clear(if (config.flags.mouse_captured) .x_neg else .yaw_neg),
                    c.SDLK_E => controls.clear(if (config.flags.mouse_captured) .x_pos else .yaw_pos),
                    c.SDLK_F => controls.clear(if (config.flags.mouse_captured) .y_neg else .pitch_neg),
                    c.SDLK_R => controls.clear(if (config.flags.mouse_captured) .y_pos else .pitch_pos),
                    c.SDLK_C => controls.clear(.roll_neg),
                    c.SDLK_V => controls.clear(.roll_pos),

                    c.SDLK_S => controls.clear(.z_neg),
                    c.SDLK_W => controls.clear(.z_pos),
                    c.SDLK_A => controls.clear(.x_neg),
                    c.SDLK_D => controls.clear(.x_pos),
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
            .mouse_motion => {
                const props = try self.engine.main_win.properties();
                _ = try props.f32.put("mouse_x", event.sdl.motion.x);
                _ = try props.f32.put("mouse_y", event.sdl.motion.y);
                _ = try props.f32.put("mouse_x_rel", event.sdl.motion.xrel);
                _ = try props.f32.put("mouse_y_rel", event.sdl.motion.yrel);
                if (self.engine.main_win.is_relative_mouse_mode_enabled) {
                    mouse_motion = .{
                        event.sdl.motion.xrel,
                        if (config.flags.mouse_y_inverted) -event.sdl.motion.yrel else event.sdl.motion.yrel,
                    };
                }
            },
            else => {
                log.info("{}", .{event.type});
            },
        }
    }

    return true;
}

fn update(self: *const ZEngine) !bool {
    const delta = global.timeSinceLastFrame().toFloat().toValue32(.s);
    switch (config.flags.camera_controls) {
        inline else => |controls_type| updateCameraControls(self, delta, controls_type),
    }
    updateScene(self, delta);

    {
        errdefer gfx_loader.cancel();
        flat_scene = try self.scene.flatten();
        _ = try gfx_loader.createLightsBuffer(&flat_scene);
        try gfx_loader.commit();
    }

    return true;
}

fn render(self: *const ZEngine) !void {
    self.ui.beginDraw();
    self.ui.drawMainMenuBar(.{
        .allocs_open = &allocs_window.is_open,
        .property_editor_open = &property_editor.is_open,
        .perf_open = &perf_window.is_open,
    });
    self.ui.drawDock();

    self.ui.draw(debug_ui.element(), &debug_ui.is_open);
    self.ui.draw(property_editor.element(), &property_editor.is_open);
    self.ui.draw(perf_window.element(), &perf_window.is_open);
    self.ui.draw(allocs_window.element(), &allocs_window.is_open);

    self.ui.endDraw();

    var items: gfx.Renderer.Items = .init(&flat_scene);
    _ = try flat_scene.render(self.ui, &items);
}

fn updateScene(self: *const ZEngine, delta: f32) void {
    const pi = std.math.pi;
    const time_s = global.timeSinceStart().toFloat().toValue32(.s);
    const s = self.scene.nodes.slice();

    // const cat = s.transform(scene_map.get("cat"));
    // const objects = s.transform(scene_map.get("objects"));

    const cube_r = s.transform(scene_map.get("cube_r"));
    const cube_g = s.transform(scene_map.get("cube_g"));
    const cube_b = s.transform(scene_map.get("cube_b"));

    const cos = @cos(1.5 * time_s);
    const sin = @sin(1.5 * time_s);
    const x = 150 * cos;
    const y = 25 * cos;
    const z = 150 * sin;

    const rx: i64 = @intCast(rnd.next() % 31);
    const ry: i64 = @intCast(rnd.next() % 31);
    const rz: i64 = @intCast(rnd.next() % 31);
    const dx: f32 = @floatFromInt(rx - 15);
    const dy: f32 = @floatFromInt(ry - 15);
    const dz: f32 = @floatFromInt(rz - 15);

    var g_pos = cube_g.translation;
    var axis: math.Vertex = .{ dx, dy, dz };
    math.vertex.normalize(&axis);
    math.vertex.rotateDirectionScale(&dir, &axis, 20 * delta);
    math.vertex.normalize(&dir);
    math.vertex.translateScale(&g_pos, &dir, 20 * delta);
    math.vertex.clamp(&g_pos, &.{ -300, 0, -300 }, &.{ 300, 300, 300 });

    const r_pos = .{ x, y + 55, z };
    const b_pos = .{ -x, -y + 55, -z };

    // objects.translation[1] = 30 * cos + 30;
    // objects.rotation[0] = 2 * time_s / pi;
    // objects.rotation[1] = 2 * time_s;
    // cat.rotation[1] = 20 * time_s;
    // cat.translation[1] = 25 * @cos(10 * time_s);

    cube_r.translation = r_pos;
    cube_r.rotation[0] = time_s;
    cube_r.rotation[1] = 25 * time_s;
    cube_r.rotation[2] = time_s + pi;
    cube_g.translation = g_pos;
    cube_g.rotation[0] = time_s;
    cube_g.rotation[1] = 25 * time_s;
    cube_g.rotation[2] = time_s + pi;
    cube_b.translation = b_pos;
    cube_b.rotation[0] = time_s;
    cube_b.rotation[1] = 25 * time_s;
    cube_b.rotation[2] = time_s + pi;
}

fn updateCameraControls(self: *const ZEngine, delta: f32, comptime controls_type: Config.CameraControlsType) void {
    const camera = self.renderer.cameras.getPtr(self.renderer.camera);
    var coords: math.vector3.Coords = undefined;
    camera.coords(&coords);

    const rotation_speed = delta;
    const mouse_speed = 0.5;
    const translation_speed = 20 * delta * speed_scale;
    const scale_speed = 15 * delta;

    camera.up = switch (comptime controls_type) {
        .y_up => global.cameraUp(),
        .y_dynamic => coords.y,
    };

    if (mouse_motion[0] != 0) {
        math.vector3.rotateDirectionScale(
            &camera.direction,
            &coords.x,
            rotation_speed * mouse_speed * mouse_motion[0],
        );
        mouse_motion[0] = 0;
    }
    if (mouse_motion[1] != 0) {
        math.vector3.rotateDirectionScale(
            &camera.direction,
            &coords.y,
            rotation_speed * mouse_speed * mouse_motion[1],
        );
        mouse_motion[1] = 0;
    }

    if (controls.has(.yaw_neg))
        math.vector3.rotateDirectionScale(&camera.direction, &coords.x, -rotation_speed);
    if (controls.has(.yaw_pos))
        math.vector3.rotateDirectionScale(&camera.direction, &coords.x, rotation_speed);

    if (controls.has(.pitch_neg))
        math.vector3.rotateDirectionScale(&camera.direction, &coords.y, -rotation_speed);
    if (controls.has(.pitch_pos))
        math.vector3.rotateDirectionScale(&camera.direction, &coords.y, rotation_speed);

    if (comptime controls_type == .y_dynamic) {
        if (controls.has(.roll_neg))
            math.vector3.rotateDirectionScale(&camera.up, &coords.x, -rotation_speed);
        if (controls.has(.roll_pos))
            math.vector3.rotateDirectionScale(&camera.up, &coords.x, rotation_speed);
    }

    if (controls.has(.x_neg))
        math.vector3.translateScale(&camera.position, &coords.x, -translation_speed);
    if (controls.has(.x_pos))
        math.vector3.translateScale(&camera.position, &coords.x, translation_speed);

    if (controls.has(.y_neg))
        math.vector3.translateScale(&camera.position, &coords.y, -translation_speed);
    if (controls.has(.y_pos))
        math.vector3.translateScale(&camera.position, &coords.y, translation_speed);

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

    if (controls.has(.custom(2))) {
        camera.type = switch (camera.type) {
            .ortographic => .perspective,
            .perspective => .ortographic,
        };
        controls.clear(.custom(2));
    }

    math.vector3.normalize(&camera.direction);
    math.vector3.normalize(&camera.up);
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
}
