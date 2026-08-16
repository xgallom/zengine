//!
//! The zengine debug mode ui
//!

const std = @import("std");
const assert = std.debug.assert;

const zcore = @import("zcore");
const allocators = zcore.allocators;
const c = zcore.ext;

const global = @import("../global.zig");
const options = @import("../options.zig").options;
const perf = @import("../perf.zig");
const UI = @import("UI.zig");

const log = std.log.scoped(.ui_debug_ui);

is_open: bool = false,

const Self = @This();

pub fn init() Self {
    return .{};
}

pub fn deinit(_: *Self) void {}

pub fn draw(self: *Self, ui: *const UI, is_open: *bool) void {
    _ = self;
    _ = ui;
    c.igShowDemoWindow(is_open);
    c.ImPlot_ShowDemoWindow(is_open);
}

pub fn element(self: *Self) UI.Element {
    return .{
        .ptr = self,
        .drawFn = @ptrCast(&draw),
    };
}
