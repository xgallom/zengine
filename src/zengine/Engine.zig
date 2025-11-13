//!
//! The zengine engine implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("allocators.zig");
const c = @import("ext.zig").c;
const Error = @import("error.zig").Error;
const ArrayMap = @import("containers.zig").ArrayMap;
pub const Properties = @import("Properties.zig");
pub const Window = @import("Window.zig");
const gfx = @import("gfx.zig");

const log = std.log.scoped(.engine);

const GlobalRegistry = Properties.GlobalRegistry(Properties.registryLists(&.{
    gfx.registry_list,
    Properties.registryList(&.{
        Window.Registry,
    }),
}));

windows: Windows = .empty,

const Self = @This();
const Windows = ArrayMap(Window);

pub const invalid: Self = .{};
var global_self: ?*Self = null;
var global_registry: GlobalRegistry = undefined;

pub fn create() !*Self {
    if (global_self != null) return global_self.?;

    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO)) {
        log.err("init failed: {s}", .{c.SDL_GetError()});
        return Error.EngineFailed;
    }

    c.SDL_SetLogOutputFunction(@ptrCast(&sdlLog), null);

    global_registry = try .init();
    const self = try allocators.global().create(Self);
    self.* = invalid;
    global_self = self;
    return self;
}

pub fn createWindow(self: *Self, key: []const u8, info: *const Window.CreateInfo) !*Window {
    assert(self == global_self);
    try self.windows.insert(allocators.gpa(), key, try .init(info));
    return self.windows.getPtr(key);
}

pub fn createMainWindow(self: *Self) !*Window {
    return self.createWindow("main", &.{
        .title = "Zengine",
        .size = .{ 1920, 1080 },
        .flags = .initMany(&.{.high_pixel_density}),
    });
}

pub fn deinit(self: *Self) void {
    assert(self == global_self);
    for (self.windows.values()) |*win| win.deinit();
    self.windows.deinit(allocators.gpa());
    global_registry.deinit();
    global_self = null;
    c.SDL_Quit();
}

pub inline fn createProperties(comptime Registry: type, key: Registry.Key) !*Properties {
    assert(global_self != null);
    return global_registry.create(Registry, key);
}

pub inline fn destroyProperties(comptime Registry: type, key: Registry.Key) void {
    assert(global_self != null);
    global_registry.destroy(Registry, key);
}

pub inline fn properties(comptime Registry: type, key: Registry.Key) *Properties {
    assert(global_self != null);
    const ptr = global_registry.properties(Registry, key);
    assert(ptr != null);
    return ptr.?;
}

pub inline fn propertiesOrNull(comptime Registry: type, key: Registry.Key) ?*Properties {
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
