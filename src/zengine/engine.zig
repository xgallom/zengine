//!
//! The zengine engine implementation
//!

const std = @import("std");
const allocators = @import("allocators.zig");
const sdl = @import("ext.zig").sdl;

const assert = std.debug.assert;
const log = std.log.scoped(.engine);

window: ?*sdl.SDL_Window,
window_size: sdl.SDL_Point,
mouse_pos: sdl.SDL_FPoint,

const Self = @This();

const InitError = error{
    InitFailed,
    WindowFailed,
} || std.mem.Allocator.Error;

pub fn init() InitError!*Self {
    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
        log.err("failed init: {s}", .{sdl.SDL_GetError()});
        return InitError.InitFailed;
    }
    errdefer sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow("zeng - Zengine 0.1.0", 1920, 1080, 0);
    if (window == null) {
        log.err("failed creating window: {s}", .{sdl.SDL_GetError()});
        return InitError.WindowFailed;
    }
    errdefer sdl.SDL_DestroyWindow(window);

    var window_size = sdl.SDL_Point{};
    if (!sdl.SDL_GetWindowSizeInPixels(window, &window_size.x, &window_size.y)) {
        log.err("failed obtaining window size: {s}", .{sdl.SDL_GetError()});
        return InitError.WindowFailed;
    }

    const result = try allocators.global().create(Self);
    result.* = .{
        .window = window,
        .window_size = window_size,
        .mouse_pos = .{},
    };
    return result;
}

pub fn deinit(self: *Self) void {
    defer sdl.SDL_Quit();
    defer sdl.SDL_DestroyWindow(self.window);
}
