//!
//! The zengine engine implementation
//!
//! These are also available in the top-level zengine module
//!

const std = @import("std");
const sdl = @import("ext/sdl.zig");

const assert = std.debug.assert;

pub const WindowSize = struct {
    w: c_int = 0,
    h: c_int = 0,
};

pub const Engine = struct {
    allocator: std.mem.Allocator,
    window: ?*sdl.SDL_Window,
    window_size: WindowSize,
    mouse_pos: sdl.SDL_FPoint,

    const InitError = error{
        InitFailed,
        WindowFailed,
    };

    pub fn init(allocator: std.mem.Allocator) InitError!Engine {
        if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
            std.log.err("failed init: {s}", .{sdl.SDL_GetError()});
            return InitError.InitFailed;
        }

        const window = sdl.SDL_CreateWindow("zeng - ZEngine 0.1.0", 1920, 1080, 0);
        if (window == null) {
            std.log.err("failed creating window: {s}", .{sdl.SDL_GetError()});
            return InitError.WindowFailed;
        }

        var window_size = WindowSize{};
        if (!sdl.SDL_GetWindowSizeInPixels(window, &window_size.w, &window_size.h)) {
            std.log.err("failed obtaining window size: {s}", .{sdl.SDL_GetError()});
            return InitError.WindowFailed;
        }

        return .{
            .allocator = allocator,
            .window = window,
            .window_size = window_size,
            .mouse_pos = .{},
        };
    }

    pub fn deinit(self: *Engine) void {
        defer sdl.SDL_Quit();
        defer sdl.SDL_DestroyWindow(self.window);
    }
};
