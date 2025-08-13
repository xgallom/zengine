const std = @import("std");
const zengine = @import("zengine");
const allocators = zengine.allocators;
const ecs_mod = zengine.ecs;
const gfx = zengine.gfx;
const global = zengine.global;
const math = zengine.math;
const sdl = zengine.ext.sdl;
const Engine = zengine.Engine;

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

pub fn main() !void {
    allocators.init(zengine.allocator.raw_sdl_allocator, 2 << 30); // Memory limit: 2GB
    defer allocators.deinit();

    try global.init(allocators.gpa());
    defer global.deinit();

    const engine = try Engine.init(allocators.arena());
    defer engine.deinit();

    var renderer = try gfx.Renderer.init(engine);
    defer renderer.deinit(engine);

    std.log.info("window size: {}", .{engine.window_size});

    {
        var positions = try ecs_mod.ComponentManager(Position).init(allocators.gpa(), 512);
        defer positions.deinit();

        const entity = try positions.push(.{ .x = 10, .y = 15, .z = 22 });
        const position = positions.components.components.get(entity);
        std.log.info("positions[{}]: {any}", .{ entity, position });
    }

    defer renderer.mesh.releaseGpuBuffers(renderer.gpu_device);

    const start_time = sdl.SDL_GetTicks();
    var last_update_time = start_time;

    var framerate_buffer: [512]u64 = [_]u64{0} ** 512;
    var framerate_index: usize = 0;

    var key_matrix: u32 = 0;
    return mainloop: while (true) {
        const now = sdl.SDL_GetTicks();

        const framerate_end_time = now -| 1000;
        var framerate: u32 = 1;
        for (0..framerate_buffer.len) |n| {
            if (framerate_buffer[n] < framerate_end_time)
                framerate_buffer[n] = 0;

            framerate += if (framerate_buffer[n] != 0) 1 else 0;
        }
        framerate_index = (framerate_index + 1) % 512;
        framerate_buffer[framerate_index] = now;
        std.log.info("framerate: {}", .{framerate});

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

        var global_up = comptime global.up();
        var coordinates: math.vector3.Coordinates = undefined;
        math.vector3.localCoordinates(&coordinates, &renderer.camera_direction, &global_up);

        const delta: f32 = @floatFromInt(now - last_update_time);
        const camera_step = delta / 500.0;

        std.log.info("coords_norm: {any}", .{coordinates});
        math.vector3.scale(&coordinates.x, camera_step);
        math.vector3.scale(&coordinates.y, camera_step);
        math.vector3.scale(&coordinates.z, camera_step);
        math.vector3.scale(&global_up, camera_step);

        if (key_matrix & 0x01 != 0)
            math.vector3.rotateDirectionScale(&renderer.camera_direction, &coordinates.x, -1);
        if (key_matrix & 0x02 != 0)
            math.vector3.rotateDirectionScale(&renderer.camera_direction, &coordinates.x, 1);

        if (key_matrix & 0x04 != 0)
            math.vector3.rotateDirectionScale(&renderer.camera_direction, &coordinates.y, -1);
        if (key_matrix & 0x08 != 0)
            math.vector3.rotateDirectionScale(&renderer.camera_direction, &coordinates.y, 1);

        if (key_matrix & 0x10 != 0)
            math.vector3.translateDirectionScale(&renderer.camera_position, &coordinates.z, -8);
        if (key_matrix & 0x20 != 0)
            math.vector3.translateDirectionScale(&renderer.camera_position, &coordinates.z, 8);

        if (key_matrix & 0x40 != 0)
            math.vector3.translateScale(&renderer.camera_position, &global_up, -8);
        if (key_matrix & 0x80 != 0)
            math.vector3.translateScale(&renderer.camera_position, &global_up, 8);

        if (key_matrix != 0) math.vector3.normalize(&renderer.camera_direction);

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
