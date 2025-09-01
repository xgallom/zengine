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

pub const std_options: std.Options = .{
    .log_level = .info,
    // .logFn = logFn,
};

const Position = struct {
    x: f32,
    y: f32,
    z: f32,
};

// fn logFn(
//     comptime message_level: std.log.Level,
//     comptime scope: @TypeOf(.enum_literal),
//     comptime format: []const u8,
//     args: anytype,
// ) void {
//     const level_txt = comptime message_level.asText();
//     const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
//
//     const message = std.fmt.allocPrintZ(allocators.arena(), level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
//     sdl.SDL_Log(message);
// }

fn pushPosition(positions: *ecs.PrimitiveComponentManager(Position), position: Position) ecs.Entity {
    std.log.info("pushing {X}", .{@intFromPtr(positions)});
    _ = position;
    return ecs.null_entity;
    // return positions.push(position) catch |err| {
    //     std.log.err("failed pushing position: {s}", .{@errorName(err)});
    //     return ecs.null_entity;
    // };
}

fn removePosition(positions: *ecs.PrimitiveComponentManager(Position), entity: ecs.Entity) void {
    std.log.info("removing", .{});
    positions.remove(entity);
}

const spaces = [1]u8{' '} ** 1024;
pub fn main() !void {
    allocators.init(zengine.allocator.raw_sdl_allocator, 2 << 30); // Memory limit: 2GB
    defer allocators.deinit();

    try global.init(allocators.global());
    defer global.deinit();
    std.log.info("exe dir path: {s}", .{global.exePath()});

    try perf.init(allocators.gpa());
    defer perf.deinit();

    var engine = try Engine.init(allocators.gpa());
    defer engine.deinit();

    var renderer = try gfx.Renderer.init(engine);
    defer renderer.deinit(engine);

    std.log.info("window size: {}", .{engine.window_size});

    var task_list = try scheduler.TaskScheduler.init(allocators.gpa());
    defer task_list.deinit();

    {
        const TreeValue = struct {
            label: []const u8,
            value: u32,
        };
        const Tree = RadixTree(TreeValue);
        var tree1 = try Tree.init(allocators.gpa(), 1024);
        defer tree1.deinit();
        var tree2 = try Tree.init(allocators.gpa(), 1024);
        defer tree2.deinit();

        try tree1.insert("test", .{ .label = "test", .value = 1 });
        try tree1.insert("slow", .{ .label = "slow", .value = 2 });
        try tree1.insert("water", .{ .label = "water", .value = 3 });
        try tree1.insert("slower", .{ .label = "slower", .value = 4 });
        try tree1.insert("tester", .{ .label = "tester", .value = 5 });
        try tree1.insert("team", .{ .label = "team", .value = 6 });
        try tree1.insert("toast", .{ .label = "toast", .value = 7 });
        try tree1.insert("waster", .{ .label = "waster", .value = 8 });

        for (0..27) |n| {
            const data = [3]u8{
                @intCast('a' + n / 9),
                @intCast('a' + (n / 3) % 3),
                @intCast('a' + n % 3),
            };
            try tree2.insert(&data, .{ .label = &.{}, .value = @intCast(1000 + n) });
        }

        const iterTree = struct {
            fn iterTree(node: *const Tree.Node, label: []const u8, offset: usize) !void {
                if (node.value) |value| {
                    std.log.info("{s}[{s}): \"{s}\" {} {X}", .{ spaces[0..offset], label, value.label, value.value, @intFromPtr(node) });
                } else {
                    std.log.info("{s}[{s}]: {X}", .{ spaces[0..offset], label, @intFromPtr(node) });
                }
                var edge_node = node.edges.first;
                while (edge_node != null) : (edge_node = edge_node.?.next) {
                    try iterTree(edge_node.?.data.target, edge_node.?.data.label, offset + 4);
                }
            }
        }.iterTree;
        const searchTree = struct {
            fn searchTree(tree: *const Tree, label: []const u8, search_type: Tree.SearchType) void {
                if (tree.search(label, search_type)) |result| {
                    std.log.info("[{s}]: {} {s}", .{ label, result.value, result.label });
                } else {
                    std.log.info("[{s}]: not found", .{label});
                }
            }
        }.searchTree;
        try iterTree(tree1.root, &.{}, 0);
        // try iterTree(tree2.root, &.{}, 0);

        const st = Tree.SearchType.exact;
        std.log.info("search type: {s}", .{@tagName(st)});
        searchTree(&tree1, "slow", st);
        searchTree(&tree1, "slower", st);
        searchTree(&tree1, "slowest", st);
        searchTree(&tree1, "t", st);
        searchTree(&tree1, "te", st);
        searchTree(&tree1, "tea", st);
        searchTree(&tree1, "team", st);
        searchTree(&tree1, "teamer", st);
        searchTree(&tree1, "tes", st);
        searchTree(&tree1, "test", st);
        searchTree(&tree1, "teste", st);
        searchTree(&tree1, "tester", st);
        searchTree(&tree1, "testere", st);

        try iterTree(tree2.root, &.{}, 0);
    }

    {
        var positions = try ecs.PrimitiveComponentManager(Position).init(allocators.gpa(), 512);
        defer positions.deinit();

        _ = try task_list.prepend(pushPosition, .{ &positions, .{ .x = 10, .y = 15, .z = 22 } });
        _ = try task_list.prepend(pushPosition, .{ &positions, .{ .x = 123, .y = 150, .z = 220 } });
        _ = try task_list.prepend(pushPosition, .{ &positions, .{ .x = 100, .y = 150, .z = 220 } });
        _ = try task_list.prepend(pushPosition, .{ &positions, .{ .x = 100, .y = 155, .z = 220 } });
        _ = try task_list.prepend(pushPosition, .{ &positions, .{ .x = 100, .y = 155, .z = 220 } });
        std.log.info("push 1", .{});
        std.log.info("pushing {X}", .{@intFromPtr(&positions)});
        _ = try positions.push(.{ .x = 100, .y = 150, .z = 225 });
        std.log.info("push 2", .{});
        std.log.info("pushing {X}", .{@intFromPtr(&positions)});
        _ = try positions.push(.{ .x = 1, .y = 15, .z = 120 });

        // const after_task2 = try task_list.prepare(removePosition, .{ &positions, 6 });
        // const after_task3 = try task_list.prepare(removePosition, .{ &positions, 2 });
        // task2.after(&after_task2.node);

        // while (task_list.processFirst()) {
        //     const result = task.promise.tryGet() catch continue;
        //     std.log.info("got promise: {}", .{result});
        //     var task3 = try task_list.append(removePosition, .{ &positions, result });
        //     task3.after(&after_task3.node);
        //     break;
        // }

        try task_list.run();

        // var iter = positions.iter();
        // while (iter.next()) |i| {
        //     std.log.info("positions[{}]: {any}", .{ i.entity, i.item });
        // }
        // iter.deinit();
    }

    var log_timer = time.Timer.init(500);
    var controls = zengine.controls.CameraControls{};

    return mainloop: while (true) {
        const now = time.getNow();
        global.setNow(now);

        defer allocators.frameReset();
        defer global.update(now);
        defer log_timer.update(now);

        perf.update(now);
        if (log_timer.isArmed(now)) std.log.info("framerate: {}", .{perf.framerate()});

        var sdl_event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&sdl_event)) {
            switch (sdl_event.type) {
                sdl.SDL_EVENT_QUIT => break :mainloop,
                sdl.SDL_EVENT_KEY_DOWN => {
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

        const delta: f32 = @floatFromInt(global.sinceUpdate());
        const camera_step = delta / 500.0;

        std.log.debug("coords_norm: {any}", .{coordinates});
        math.vector3.scale(&coordinates.x, camera_step);
        math.vector3.scale(&coordinates.y, camera_step);
        math.vector3.scale(&coordinates.z, camera_step);
        math.vector3.scale(&up, camera_step);

        // math.vector2.localCoords(&coordinates2, &.{ 0, 1 }, &.{ 1, 0 });

        if (controls.has(.yaw_neg))
            math.vector3.rotateDirectionScale(&renderer.camera_direction, &coordinates.x, -1);
        if (controls.has(.yaw_pos))
            math.vector3.rotateDirectionScale(&renderer.camera_direction, &coordinates.x, 1);

        if (controls.has(.pitch_neg))
            math.vector3.rotateDirectionScale(&renderer.camera_direction, &coordinates.y, -1);
        if (controls.has(.pitch_pos))
            math.vector3.rotateDirectionScale(&renderer.camera_direction, &coordinates.y, 1);

        // if (controls.has(.roll_neg))
        //     math.vector3.rotateDirectionScale(&renderer.camera_up, &coordinates.x, -1);
        // if (controls.has(.roll_pos))
        //     math.vector3.rotateDirectionScale(&renderer.camera_up, &coordinates.x, 1);

        if (controls.has(.x_neg))
            math.vector3.translateScale(&renderer.camera_position, &coordinates.x, -8);
        if (controls.has(.x_pos))
            math.vector3.translateScale(&renderer.camera_position, &coordinates.x, 8);

        if (controls.has(.y_neg))
            math.vector3.translateScale(&renderer.camera_position, &up, -8);
        if (controls.has(.y_pos))
            math.vector3.translateScale(&renderer.camera_position, &up, 8);

        if (controls.has(.z_neg))
            math.vector3.translateDirectionScale(&renderer.camera_position, &coordinates.z, -8);
        if (controls.has(.z_pos))
            math.vector3.translateDirectionScale(&renderer.camera_position, &coordinates.z, 8);

        if (controls.has(.fov_neg))
            renderer.fov -= 10 * camera_step;
        if (controls.has(.fov_pos))
            renderer.fov += 10 * camera_step;

        if (controls.hasAny()) {
            math.vector3.normalize(&renderer.camera_direction);
            // math.vector3.normalize(&renderer.camera_up);
            renderer.fov = std.math.clamp(renderer.fov, 15, 130);
        }

        _ = try renderer.draw(engine, global.sinceStart());

        if (log_timer.isArmed(now)) {
            std.log.info(
                "[ {: >8} : {d: >9.3} ] frame: {}, global: {}, total: {}",
                .{
                    global.frameIndex(),
                    time.msToSec(global.sinceStart()),
                    std.fmt.fmtIntSizeBin(allocators.arenaState(.frame).queryCapacity()),
                    std.fmt.fmtIntSizeBin(allocators.arenaState(.global).queryCapacity()),
                    std.fmt.fmtIntSizeBin(allocators.global_state.gpa_state.total_requested_bytes),
                },
            );
        }
    };
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
