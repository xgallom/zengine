//!
//! The zengine window implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("allocators.zig");
const c = @import("ext.zig").c;
const Engine = @import("Engine.zig");
const math = @import("math.zig");

const log = std.log.scoped(.window);

ptr: ?*c.SDL_Window = null,
is_relative_mouse_mode_enabled: bool = false,

const Self = @This();
pub const Registry = Engine.Properties.AutoRegistry(?*c.SDL_Window, .{});

pub const invalid: Self = .{};

pub const CreateInfo = struct {
    title: [:0]const u8,
    size: math.Point_u32 = math.point_u32.zero,
    flags: Flags = .initEmpty(),
};

pub fn init(info: *const CreateInfo) !Self {
    return fromOwned(try create(info));
}

pub fn deinit(self: *Self) void {
    if (self.isValid()) destroy(self.toOwned());
}

pub fn fromOwned(ptr: *c.SDL_Window) Self {
    return .{ .ptr = ptr };
}

pub fn toOwned(self: *Self) *c.SDL_Window {
    assert(self.isValid());
    defer self.ptr = null;
    return self.ptr.?;
}

pub fn create(info: *const CreateInfo) !*c.SDL_Window {
    const ptr = c.SDL_CreateWindow(
        info.title.ptr,
        @intCast(info.size[0]),
        @intCast(info.size[1]),
        info.flags.bits.mask,
    );
    if (ptr == null) {
        log.err("failed creating window: {s}", .{c.SDL_GetError()});
        return error.WindowFailed;
    }
    return ptr.?;
}

pub fn destroy(ptr: *c.SDL_Window) void {
    c.SDL_DestroyWindow(ptr);
}

pub fn pixelSize(self: Self) math.Point_u32 {
    assert(self.isValid());
    var result: math.Point_u32 = undefined;
    if (!c.SDL_GetWindowSizeInPixels(self.ptr, @ptrCast(&result[0]), @ptrCast(&result[1]))) {
        log.err("failed getting window size: {s}", .{c.SDL_GetError()});
        std.process.exit(1);
    }
    return result;
}

pub fn logicalSize(self: Self) math.Point_u32 {
    assert(self.isValid());
    var result: math.Point_u32 = undefined;
    if (!c.SDL_GetWindowSize(self.ptr, @ptrCast(&result[0]), @ptrCast(&result[1]))) {
        log.err("failed getting window size: {s}", .{c.SDL_GetError()});
        std.process.exit(1);
    }
    return result;
}

pub fn setRelativeMouseMode(self: *Self, enabled: bool) void {
    self.is_relative_mouse_mode_enabled = enabled;
    assert(c.SDL_SetWindowRelativeMouseMode(self.ptr, enabled));
}

pub inline fn isValid(self: Self) bool {
    return self.ptr != null;
}

pub inline fn properties(self: Self) !*Engine.Properties {
    assert(self.isValid());
    return Engine.properties(Registry, self.ptr);
}

pub const Flag = enum(c.SDL_WindowFlags) {
    fullscreen = c.SDL_WINDOW_FULLSCREEN,
    opengl = c.SDL_WINDOW_OPENGL,
    occluded = c.SDL_WINDOW_OCCLUDED,
    hidden = c.SDL_WINDOW_HIDDEN,
    borderless = c.SDL_WINDOW_BORDERLESS,
    resizable = c.SDL_WINDOW_RESIZABLE,
    minimized = c.SDL_WINDOW_MINIMIZED,
    maximized = c.SDL_WINDOW_MAXIMIZED,
    mouse_grabbed = c.SDL_WINDOW_MOUSE_GRABBED,
    input_focus = c.SDL_WINDOW_INPUT_FOCUS,
    mouse_focus = c.SDL_WINDOW_MOUSE_FOCUS,
    external = c.SDL_WINDOW_EXTERNAL,
    modal = c.SDL_WINDOW_MODAL,
    high_pixel_density = c.SDL_WINDOW_HIGH_PIXEL_DENSITY,
    mouse_capture = c.SDL_WINDOW_MOUSE_CAPTURE,
    mouse_relative_mode = c.SDL_WINDOW_MOUSE_RELATIVE_MODE,
    always_on_top = c.SDL_WINDOW_ALWAYS_ON_TOP,
    utility = c.SDL_WINDOW_UTILITY,
    tooltip = c.SDL_WINDOW_TOOLTIP,
    popup_menu = c.SDL_WINDOW_POPUP_MENU,
    keyboard_grabbed = c.SDL_WINDOW_KEYBOARD_GRABBED,
    vulkan = c.SDL_WINDOW_VULKAN,
    metal = c.SDL_WINDOW_METAL,
    transparent = c.SDL_WINDOW_TRANSPARENT,
    not_focusable = c.SDL_WINDOW_NOT_FOCUSABLE,
};
pub const Flags = std.EnumSet(Flag);
