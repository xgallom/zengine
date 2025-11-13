//!
//! The zengine debug mode ui
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const perf = @import("../perf.zig");
const UI = @import("UI.zig");
const options = @import("../options.zig").options;

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
