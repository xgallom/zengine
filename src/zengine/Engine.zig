//!
//! The zengine engine implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("allocators.zig");
const c = @import("ext.zig").c;
const KeyMap = @import("containers.zig").KeyMap;
const KeyTree = @import("containers.zig").KeyTree;
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
