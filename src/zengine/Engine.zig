//!
//! The zengine engine implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("allocators.zig");
const c = @import("ext.zig").c;
pub const Properties = @import("Properties.zig");
pub const Window = @import("Window.zig");

const log = std.log.scoped(.engine);

const GlobalRegistry = Properties.GlobalRegistry(&.{
    Window.Registry,
});

main_win: Window = .invalid,

const Self = @This();
pub const invalid: Self = .{};
var global_self: ?*Self = null;
var global_registry: GlobalRegistry = undefined;

pub fn create() !*Self {
    if (global_self != null) return global_self.?;

    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO)) {
        log.err("init failed: {s}", .{c.SDL_GetError()});
        return error.InitFailed;
    }

    c.SDL_SetLogOutputFunction(@ptrCast(&sdlLog), null);

    global_registry = try .init();
    const self = try allocators.global().create(Self);
    self.* = invalid;
    global_self = self;
    return self;
}

pub fn initMainWindow(self: *Self) !void {
    assert(self == global_self);
    assert(!self.main_win.isValid());
    self.main_win = try .init(&.{
        .title = "zeng - Zengine 0.1.0",
        .size = .{ 1920, 1080 },
        .flags = .initOne(.high_pixel_density),
    });

    const props = try self.main_win.properties();
    _ = try props.f32.insert("mouse_x", 0);
    _ = try props.f32.insert("mouse_y", 0);
}

pub fn deinit(self: *Self) void {
    assert(self == global_self);
    global_self = null;
    self.main_win.deinit();
    global_registry.deinit();
    c.SDL_Quit();
}

pub inline fn properties(comptime Registry: type, key: Registry.Key) !*Properties {
    assert(global_self != null);
    return global_registry.properties(Registry, key);
}

fn sdlLog(_: ?*anyopaque, category: LogCategory, priority: LogPriority, msg: [*:0]const u8) callconv(.c) void {
    const level: std.log.Level = switch (priority) {
        .invalid => unreachable,
        .trace, .verbose, .debug, .count => .debug,
        .info => .info,
        .warn => .warn,
        .err, .critical => .err,
    };
    switch (level) {
        .debug => switch (category) {
            .app => std.options.logFn(.debug, .sdl_app, "{s}", .{msg}),
            .err => std.options.logFn(.debug, .sdl_err, "{s}", .{msg}),
            .assert => std.options.logFn(.debug, .sdl_assert, "{s}", .{msg}),
            .system => std.options.logFn(.debug, .sdl_system, "{s}", .{msg}),
            .audio => std.options.logFn(.debug, .sdl_audio, "{s}", .{msg}),
            .video => std.options.logFn(.debug, .sdl_video, "{s}", .{msg}),
            .render => std.options.logFn(.debug, .sdl_render, "{s}", .{msg}),
            .input => std.options.logFn(.debug, .sdl_input, "{s}", .{msg}),
            .@"test" => std.options.logFn(.debug, .sdl_test, "{s}", .{msg}),
            .gpu => std.options.logFn(.debug, .sdl_gpu, "{s}", .{msg}),
            .custom => std.options.logFn(.debug, .sdl_custom, "{s}", .{msg}),
        },
        .info => switch (category) {
            .app => std.options.logFn(.info, .sdl_app, "{s}", .{msg}),
            .err => std.options.logFn(.info, .sdl_err, "{s}", .{msg}),
            .assert => std.options.logFn(.info, .sdl_assert, "{s}", .{msg}),
            .system => std.options.logFn(.info, .sdl_system, "{s}", .{msg}),
            .audio => std.options.logFn(.info, .sdl_audio, "{s}", .{msg}),
            .video => std.options.logFn(.info, .sdl_video, "{s}", .{msg}),
            .render => std.options.logFn(.info, .sdl_render, "{s}", .{msg}),
            .input => std.options.logFn(.info, .sdl_input, "{s}", .{msg}),
            .@"test" => std.options.logFn(.info, .sdl_test, "{s}", .{msg}),
            .gpu => std.options.logFn(.info, .sdl_gpu, "{s}", .{msg}),
            .custom => std.options.logFn(.info, .sdl_custom, "{s}", .{msg}),
        },
        .warn => switch (category) {
            .app => std.options.logFn(.warn, .sdl_app, "{s}", .{msg}),
            .err => std.options.logFn(.warn, .sdl_err, "{s}", .{msg}),
            .assert => std.options.logFn(.warn, .sdl_assert, "{s}", .{msg}),
            .system => std.options.logFn(.warn, .sdl_system, "{s}", .{msg}),
            .audio => std.options.logFn(.warn, .sdl_audio, "{s}", .{msg}),
            .video => std.options.logFn(.warn, .sdl_video, "{s}", .{msg}),
            .render => std.options.logFn(.warn, .sdl_render, "{s}", .{msg}),
            .input => std.options.logFn(.warn, .sdl_input, "{s}", .{msg}),
            .@"test" => std.options.logFn(.warn, .sdl_test, "{s}", .{msg}),
            .gpu => std.options.logFn(.warn, .sdl_gpu, "{s}", .{msg}),
            .custom => std.options.logFn(.warn, .sdl_custom, "{s}", .{msg}),
        },
        .err => switch (category) {
            .app => std.options.logFn(.err, .sdl_app, "{s}", .{msg}),
            .err => std.options.logFn(.err, .sdl_err, "{s}", .{msg}),
            .assert => std.options.logFn(.err, .sdl_assert, "{s}", .{msg}),
            .system => std.options.logFn(.err, .sdl_system, "{s}", .{msg}),
            .audio => std.options.logFn(.err, .sdl_audio, "{s}", .{msg}),
            .video => std.options.logFn(.err, .sdl_video, "{s}", .{msg}),
            .render => std.options.logFn(.err, .sdl_render, "{s}", .{msg}),
            .input => std.options.logFn(.err, .sdl_input, "{s}", .{msg}),
            .@"test" => std.options.logFn(.err, .sdl_test, "{s}", .{msg}),
            .gpu => std.options.logFn(.err, .sdl_gpu, "{s}", .{msg}),
            .custom => std.options.logFn(.err, .sdl_custom, "{s}", .{msg}),
        },
    }
    if (priority == .critical) std.process.exit(1);
}

const LogCategory = enum(c.SDL_LogCategory) {
    app = c.SDL_LOG_CATEGORY_APPLICATION,
    err = c.SDL_LOG_CATEGORY_ERROR,
    assert = c.SDL_LOG_CATEGORY_ASSERT,
    system = c.SDL_LOG_CATEGORY_SYSTEM,
    audio = c.SDL_LOG_CATEGORY_AUDIO,
    video = c.SDL_LOG_CATEGORY_VIDEO,
    render = c.SDL_LOG_CATEGORY_RENDER,
    input = c.SDL_LOG_CATEGORY_INPUT,
    @"test" = c.SDL_LOG_CATEGORY_TEST,
    gpu = c.SDL_LOG_CATEGORY_GPU,
    custom = c.SDL_LOG_CATEGORY_CUSTOM,
};

const LogPriority = enum(c.SDL_LogPriority) {
    invalid = c.SDL_LOG_PRIORITY_INVALID,
    trace = c.SDL_LOG_PRIORITY_TRACE,
    verbose = c.SDL_LOG_PRIORITY_VERBOSE,
    debug = c.SDL_LOG_PRIORITY_DEBUG,
    info = c.SDL_LOG_PRIORITY_INFO,
    warn = c.SDL_LOG_PRIORITY_WARN,
    err = c.SDL_LOG_PRIORITY_ERROR,
    critical = c.SDL_LOG_PRIORITY_CRITICAL,
    count = c.SDL_LOG_PRIORITY_COUNT,
};
