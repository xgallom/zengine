//!
//! The zengine engine implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("allocators.zig");
const c = @import("ext.zig").c;

const log = std.log.scoped(.engine);

window: ?*c.SDL_Window = null,
window_size: c.SDL_Point = .{},
mouse_pos: c.SDL_FPoint = .{},

const Self = @This();

const InitError = error{
    InitFailed,
    WindowFailed,
};

pub fn init() !*Self {
    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        log.err("failed init: {s}", .{c.SDL_GetError()});
        return InitError.InitFailed;
    }

    const result = try allocators.global().create(Self);
    result.* = .{};
    return result;
}

pub fn initWindow(self: *Self) !void {
    const window = c.SDL_CreateWindow(
        "zeng - Zengine 0.1.0",
        1920,
        1080,
        c.SDL_WINDOW_HIGH_PIXEL_DENSITY,
    );
    if (window == null) {
        log.err("failed creating window: {s}", .{c.SDL_GetError()});
        return InitError.WindowFailed;
    }
    errdefer c.SDL_DestroyWindow(window);

    var window_size = c.SDL_Point{};
    if (!c.SDL_GetWindowSizeInPixels(window, &window_size.x, &window_size.y)) {
        log.err("failed obtaining window size: {s}", .{c.SDL_GetError()});
        return InitError.WindowFailed;
    }

    self.window = window;
    self.window_size = window_size;
}

pub fn deinit(self: *Self) void {
    defer c.SDL_Quit();
    if (self.window != null) c.SDL_DestroyWindow(self.window);
    self.* = .{};
}
