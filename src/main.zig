const std = @import("std");
const sdl = @import("ext/sdl.zig");
const math = @import("math.zig");
const ecs = @import("ecs.zig");
const Engine = @import("engine.zig").Engine;
const gfx = @import("gfx.zig");

const assert = std.debug.assert;

pub const std_options = .{
    .log_level = .info,
};

const memory_size = 2 << 30; // 2GB

const Position = struct {
    x: f32,
    y: f32,
    z: f32,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true }){ .requested_memory_limit = memory_size };
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const engine = try Engine.init(arena.allocator());
    defer engine.deinit();

    var component_manager = try ecs.ComponentManager.init(engine.allocator);
    try component_manager.register(Position, engine.allocator, engine.allocator, 512);
    defer component_manager.unregister(Position, engine.allocator);

    var position_array_list = component_manager.getComponentArrayList(Position).components;
    const index = try position_array_list.addOne(engine.allocator);
    position_array_list.set(index, .{
        .x = 4.0,
        .y = 9.0,
        .z = -10.0,
    });
    std.log.info("position[{}] = {}", .{ index, position_array_list });

    var renderer = try gfx.Renderer.init(engine);
    defer renderer.deinit(engine);

    std.log.info("Window size: {}", .{engine.window_size});

    const start_time = sdl.SDL_GetTicks();
    var last_update_time = start_time;

    var framerate_buffer: [512]u64 = [_]u64{0} ** 512;
    var framerate_index: usize = 0;

    var key_matrix: u32 = 0;
    return mainloop: while (true) {
        const now = sdl.SDL_GetTicks();

        const framerate_end_time = if (now < 1000) 0 else now - 1000;
        var framerate: u32 = 1;
        for (0..framerate_buffer.len) |n| {
            if (framerate_buffer[n] < framerate_end_time) {
                framerate_buffer[n] = 0;
            }
            if (framerate_buffer[n] != 0) {
                framerate += 1;
            }
        }
        framerate_index = (framerate_index + 1) % 512;
        framerate_buffer[framerate_index] = now;
        std.log.info("Framerate: {}", .{framerate});

        var sdl_event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&sdl_event)) {
            switch (sdl_event.type) {
                sdl.SDL_EVENT_QUIT => break :mainloop,
                sdl.SDL_EVENT_KEY_DOWN => {
                    switch (sdl_event.key.key) {
                        sdl.SDLK_A => key_matrix |= 0x01,
                        sdl.SDLK_D => key_matrix |= 0x02,
                        sdl.SDLK_Q => key_matrix |= 0x04,
                        sdl.SDLK_E => key_matrix |= 0x08,
                        sdl.SDLK_S => key_matrix |= 0x10,
                        sdl.SDLK_W => key_matrix |= 0x20,
                        sdl.SDLK_X => key_matrix |= 0x40,
                        sdl.SDLK_SPACE => key_matrix |= 0x80,
                        sdl.SDLK_ESCAPE => break :mainloop,
                        else => {},
                    }
                },
                sdl.SDL_EVENT_KEY_UP => {
                    switch (sdl_event.key.key) {
                        sdl.SDLK_A => key_matrix &= ~@as(u32, 0x01),
                        sdl.SDLK_D => key_matrix &= ~@as(u32, 0x02),
                        sdl.SDLK_Q => key_matrix &= ~@as(u32, 0x04),
                        sdl.SDLK_E => key_matrix &= ~@as(u32, 0x08),
                        sdl.SDLK_S => key_matrix &= ~@as(u32, 0x10),
                        sdl.SDLK_W => key_matrix &= ~@as(u32, 0x20),
                        sdl.SDLK_X => key_matrix &= ~@as(u32, 0x40),
                        sdl.SDLK_SPACE => key_matrix &= ~@as(u32, 0x80),
                        else => {},
                    }
                },
                else => {},
            }
        }

        const camera_step = @as(f32, @floatFromInt(now - last_update_time)) / 500.0;
        var coordinates: math.vector3.Coordinates = undefined;
        math.vector3.local_coordinates(&coordinates, &renderer.camera_direction, &.{ 0, 1, 0 });

        math.vector3.scale(&coordinates.front, camera_step);
        math.vector3.scale(&coordinates.right, camera_step);
        math.vector3.scale(&coordinates.up, camera_step);

        if (key_matrix & 0x01 != 0)
            math.vector3.mul_sub(&renderer.camera_direction, &coordinates.right, 1);
        if (key_matrix & 0x02 != 0)
            math.vector3.mul_add(&renderer.camera_direction, &coordinates.right, 1);
        if (key_matrix & 0x04 != 0)
            math.vector3.mul_sub(&renderer.camera_direction, &coordinates.up, 1);
        if (key_matrix & 0x08 != 0)
            math.vector3.mul_add(&renderer.camera_direction, &coordinates.up, 1);
        if (key_matrix & 0x10 != 0)
            math.vector3.mul_sub(&renderer.camera_position, &coordinates.front, -5);
        if (key_matrix & 0x20 != 0)
            math.vector3.mul_add(&renderer.camera_position, &coordinates.front, -5);
        if (key_matrix & 0x40 != 0)
            math.vector3.mul_sub(&renderer.camera_position, &.{0, 1, 0}, 5);
        if (key_matrix & 0x80 != 0)
            math.vector3.mul_add(&renderer.camera_position, &.{0, 1, 0}, 5);

        if (key_matrix != 0) {
            std.log.info("{any}", .{renderer.camera_position});
        }

        try renderer.draw(engine, now - start_time);
        last_update_time = now;
    };
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
