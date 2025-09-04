const std = @import("std");
const zengine = @import("zengine");
const allocators = zengine.allocators;
const ecs = zengine.ecs;
const gfx = zengine.gfx;
const global = zengine.global;
const math = zengine.math;
const perf = zengine.perf;
const sdl = zengine.ext.sdl;
const scheduler = zengine.scheduler;
const time = zengine.time;
const Engine = zengine.Engine;
const RadixTree = zengine.RadixTree;

const assert = std.debug.assert;
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

const Position = struct {
    x: f32,
    y: f32,
    z: f32,
};

fn pushPosition(positions: *ecs.PrimitiveComponentManager(Position), position: Position) ecs.Entity {
    log.info("pushing {X}", .{@intFromPtr(positions)});
    _ = position;
    return ecs.null_entity;
    // return positions.push(position) catch |err| {
    //     log.err("failed pushing position: {s}", .{@errorName(err)});
    //     return ecs.null_entity;
    // };
}

fn removePosition(positions: *ecs.PrimitiveComponentManager(Position), entity: ecs.Entity) void {
    log.info("removing", .{});
    positions.remove(entity);
}

pub fn main() !void {
    try allocators.init(zengine.raw_allocator, 2 << 30); // memory limit 2GiB
    defer allocators.deinit();

    const engine = try Engine.init();
    defer engine.deinit();

    try perf.init();
    defer perf.deinit();

    try sections.register();
    sections.items.init.begin();

    try global.init();
    defer global.deinit();

    try engine.initWindow();

    const renderer = try gfx.Renderer.init(engine);
    defer renderer.deinit(engine);

    log.info("window size: {}", .{engine.window_size});

    var task_list = try scheduler.TaskScheduler.init(allocators.gpa());
    defer task_list.deinit();

    // {
    //     const TreeValue = struct {
    //         label: []const u8,
    //         value: u32,
    //     };
    //     const Tree = RadixTree(TreeValue, .{});
    //     var tree1 = try Tree.init(allocators.gpa(), 1024);
    //     defer tree1.deinit();
    //     var tree2 = try Tree.init(allocators.gpa(), 1024);
    //     defer tree2.deinit();
    //
    //     try tree1.insert("test", .{ .label = "test", .value = 1 });
    //     try tree1.insert("slow", .{ .label = "slow", .value = 2 });
    //     try tree1.insert("water", .{ .label = "water", .value = 3 });
    //     try tree1.insert("slower", .{ .label = "slower", .value = 4 });
    //     try tree1.insert("tester", .{ .label = "tester", .value = 5 });
    //     try tree1.insert("team", .{ .label = "team", .value = 6 });
    //     try tree1.insert("toast", .{ .label = "toast", .value = 7 });
    //     try tree1.insert("waster", .{ .label = "waster", .value = 8 });
    //
    //     for (0..27) |n| {
    //         const data = [3]u8{
    //             @intCast('a' + n / 9),
    //             @intCast('a' + (n / 3) % 3),
    //             @intCast('a' + n % 3),
    //         };
    //         try tree2.insert(&data, .{ .label = &.{}, .value = @intCast(1000 + n) });
    //     }
    //
    //     const iterTree = struct {
    //         fn iterTree(node: *const Tree.Node, label: []const u8, offset: usize) !void {
    //             if (node.value) |value| {
    //                 log.info("{s}[{s}): \"{s}\" {} {X}", .{ global.spaces(offset), label, value.label, value.value, @intFromPtr(node) });
    //             } else {
    //                 log.info("{s}[{s}]: {X}", .{ global.spaces(offset), label, @intFromPtr(node) });
    //             }
    //             var edge_node = node.edges.first;
    //             while (edge_node != null) : (edge_node = edge_node.?.next) {
    //                 const edge: *const Tree.Edge = @fieldParentPtr("edge_node", edge_node.?);
    //                 try iterTree(edge.target, edge.label, offset + 4);
    //             }
    //         }
    //     }.iterTree;
    //     const searchTree = struct {
    //         fn searchTree(tree: *const Tree, label: []const u8, search_type: Tree.SearchType) void {
    //             if (tree.search(label, search_type)) |result| {
    //                 log.info("[{s}]: {} {s}", .{ label, result.value.?.value, result.value.?.label });
    //             } else {
    //                 log.info("[{s}]: not found", .{label});
    //             }
    //         }
    //     }.searchTree;
    //     try iterTree(tree1.root, &.{}, 0);
    //     // try iterTree(tree2.root, &.{}, 0);
    //
    //     const st = Tree.SearchType.exact;
    //     log.info("search type: {s}", .{@tagName(st)});
    //     searchTree(&tree1, "slow", st);
    //     searchTree(&tree1, "slower", st);
    //     searchTree(&tree1, "slowest", st);
    //     searchTree(&tree1, "t", st);
    //     searchTree(&tree1, "te", st);
    //     searchTree(&tree1, "tea", st);
    //     searchTree(&tree1, "team", st);
    //     searchTree(&tree1, "teamer", st);
    //     searchTree(&tree1, "tes", st);
    //     searchTree(&tree1, "test", st);
    //     searchTree(&tree1, "teste", st);
    //     searchTree(&tree1, "tester", st);
    //     searchTree(&tree1, "testere", st);
    //
    //     try iterTree(tree2.root, &.{}, 0);
    // }

    // {
    //     var positions = try ecs.PrimitiveComponentManager(Position).init(allocators.gpa(), 32);
    //     defer positions.deinit();
    //
    //     _ = try task_list.prepend(pushPosition, .{ &positions, .{ .x = 10, .y = 15, .z = 22 } });
    //     _ = try task_list.prepend(pushPosition, .{ &positions, .{ .x = 123, .y = 150, .z = 220 } });
    //     _ = try task_list.prepend(pushPosition, .{ &positions, .{ .x = 100, .y = 150, .z = 220 } });
    //     _ = try task_list.prepend(pushPosition, .{ &positions, .{ .x = 100, .y = 155, .z = 220 } });
    //     _ = try task_list.prepend(pushPosition, .{ &positions, .{ .x = 100, .y = 155, .z = 220 } });
    //     log.info("push 1", .{});
    //     log.info("pushing {X}", .{@intFromPtr(&positions)});
    //     _ = try positions.push(.{ .x = 100, .y = 150, .z = 225 });
    //     log.info("push 2", .{});
    //     log.info("pushing {X}", .{@intFromPtr(&positions)});
    //     _ = try positions.push(.{ .x = 1, .y = 15, .z = 120 });
    //
    //     // const after_task2 = try task_list.prepare(removePosition, .{ &positions, 6 });
    //     // const after_task3 = try task_list.prepare(removePosition, .{ &positions, 2 });
    //     // task2.after(&after_task2.node);
    //
    //     // while (task_list.processFirst()) {
    //     //     const result = task.promise.tryGet() catch continue;
    //     //     log.info("got promise: {}", .{result});
    //     //     var task3 = try task_list.append(removePosition, .{ &positions, result });
    //     //     task3.after(&after_task3.node);
    //     //     break;
    //     // }
    //
    //     try task_list.run();
    //
    //     // var iter = positions.iter();
    //     // while (iter.next()) |i| {
    //     //     log.info("positions[{}]: {any}", .{ i.entity, i.item });
    //     // }
    //     // iter.deinit();
    // }

    var log_timer = time.Timer.init(500);
    var controls = zengine.controls.CameraControls{};
    var speed_change_timer = time.Timer.init(500);

    var speed_scale: f32 = 1;

    log.info("commiting perf graph", .{});
    try perf.commitGraph();
    sections.items.init.end();

    return mainloop: while (true) {
        defer allocators.frameReset();

        sections.items.frame.begin();
        defer sections.items.frame.end();

        global.startFrame();
        defer global.finishFrame();

        const now = global.engineNow();
        defer log_timer.update(now);
        perf.update(now);

        var sdl_event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&sdl_event)) {
            switch (sdl_event.type) {
                sdl.SDL_EVENT_QUIT => break :mainloop,
                sdl.SDL_EVENT_KEY_DOWN => {
                    if (sdl_event.key.repeat == true) break;
                    switch (sdl_event.key.key) {
                        sdl.SDLK_A => controls.set(.yaw_neg),
                        sdl.SDLK_D => controls.set(.yaw_pos),
                        sdl.SDLK_F => controls.set(.pitch_neg),
                        sdl.SDLK_R => controls.set(.pitch_pos),
                        // sdl.SDLK_C => controls.set(.roll_neg),
                        // sdl.SDLK_V => controls.set(.roll_pos),

                        sdl.SDLK_S => controls.set(.z_neg),
                        sdl.SDLK_W => controls.set(.z_pos),
                        sdl.SDLK_Q => controls.set(.x_neg),
                        sdl.SDLK_E => controls.set(.x_pos),
                        sdl.SDLK_X => controls.set(.y_neg),
                        sdl.SDLK_SPACE => controls.set(.y_pos),

                        sdl.SDLK_K => controls.set(.fov_neg),
                        sdl.SDLK_L => controls.set(.fov_pos),

                        sdl.SDLK_LEFTBRACKET => controls.set(.custom(0)),
                        sdl.SDLK_RIGHTBRACKET => controls.set(.custom(1)),

                        sdl.SDLK_ESCAPE => break :mainloop,
                        else => {},
                    }
                },
                sdl.SDL_EVENT_KEY_UP => {
                    switch (sdl_event.key.key) {
                        sdl.SDLK_A => controls.clear(.yaw_neg),
                        sdl.SDLK_D => controls.clear(.yaw_pos),
                        sdl.SDLK_F => controls.clear(.pitch_neg),
                        sdl.SDLK_R => controls.clear(.pitch_pos),
                        // sdl.SDLK_C => controls.clear(.roll_neg),
                        // sdl.SDLK_V => controls.clear(.roll_pos),

                        sdl.SDLK_S => controls.clear(.z_neg),
                        sdl.SDLK_W => controls.clear(.z_pos),
                        sdl.SDLK_Q => controls.clear(.x_neg),
                        sdl.SDLK_E => controls.clear(.x_pos),
                        sdl.SDLK_X => controls.clear(.y_neg),
                        sdl.SDLK_SPACE => controls.clear(.y_pos),

                        sdl.SDLK_K => controls.clear(.fov_neg),
                        sdl.SDLK_L => controls.clear(.fov_pos),

                        sdl.SDLK_LEFTBRACKET => {
                            controls.clear(.custom(0));
                            speed_change_timer.reset();
                        },
                        sdl.SDLK_RIGHTBRACKET => {
                            controls.clear(.custom(1));
                            speed_change_timer.reset();
                        },

                        else => {},
                    }
                },
                sdl.SDL_EVENT_MOUSE_MOTION => {
                    engine.mouse_pos = .{
                        .x = sdl_event.motion.x,
                        .y = sdl_event.motion.y,
                    };
                },
                else => {},
            }
        }

        var up = renderer.camera_up;
        var coordinates: math.vector3.Coords = undefined;
        math.vector3.localCoords(&coordinates, &renderer.camera_direction, &renderer.camera_up);

        const delta: f32 = global.timeSinceLastFrame().toFloat(.s);
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
            math.vector3.translateScale(&renderer.camera_position, &up, -translation_speed);
        if (controls.has(.y_pos))
            math.vector3.translateScale(&renderer.camera_position, &up, translation_speed);

        if (controls.has(.z_neg))
            math.vector3.translateDirectionScale(&renderer.camera_position, &coordinates.z, -translation_speed);
        if (controls.has(.z_pos))
            math.vector3.translateDirectionScale(&renderer.camera_position, &coordinates.z, translation_speed);

        if (controls.has(.fov_neg))
            renderer.fov -= fov_speed;
        if (controls.has(.fov_pos))
            renderer.fov += fov_speed;

        if (controls.has(.custom(0))) {
            if (speed_change_timer.updated(now)) speed_scale /= 2;
        } else if (controls.has(.custom(1))) {
            if (speed_change_timer.updated(now)) speed_scale *= 2;
        }

        if (controls.hasAny()) {
            math.vector3.normalize(&renderer.camera_direction);
            // math.vector3.normalize(&renderer.camera_up);
            renderer.fov = std.math.clamp(renderer.fov, 15, 130);
        }

        _ = try renderer.draw(engine);

        if (log_timer.isArmed(now)) {
            perf.updateAvg();
            log.info("frame[{}] t: {d:.3}s", .{ global.frameIndex(), global.timeSinceStart().toFloat(.s) });
            allocators.logCapacities();
            perf.logPerf();
        }
    };
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
