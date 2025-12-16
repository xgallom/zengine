//!
//! The zengine log window ui
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const perf = @import("../perf.zig");
const UI = @import("UI.zig");

const log = std.log.scoped(.ui_log_window);

allocator: std.mem.Allocator = undefined,
buf: std.ArrayList(u8) = .empty,
line_offsets: std.ArrayList(usize) = .empty,
is_init: bool = false,
is_open: bool = true,
is_auto_scroll_enabled: bool = true,
filter: c.ImGuiTextFilter = .{},

const Self = @This();
pub const window_name = "Debug Log";
pub const invalid: Self = .{};

pub fn init(allocator: std.mem.Allocator) !Self {
    var self: Self = .{
        .allocator = allocator,
        .is_init = true,
    };
    try self.line_offsets.append(self.allocator, 0);
    return self;
}

pub fn deinit(self: *Self) void {
    if (self.is_init) {
        self.buf.deinit(self.allocator);
        self.line_offsets.deinit(self.allocator);
        self.is_init = false;
    }
}

pub fn clear(self: *Self) void {
    assert(self.is_init);
    self.buf.clearAndFree(self.allocator);
    self.line_offsets.clearRetainingCapacity();
    self.line_offsets.appendAssumeCapacity(0);
}

var print_buf: [1 << 10]u8 = undefined;
pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) !void {
    if (!self.is_init) return;
    const start = self.buf.items.len;
    {
        var w: std.Io.Writer.Allocating = .fromArrayList(self.allocator, &self.buf);
        errdefer w.deinit();
        try w.writer.print(fmt, args);
        self.buf = w.toArrayList();
    }
    for (self.buf.items[start..], start..) |ch, n| {
        if (ch == '\n') try self.line_offsets.append(self.allocator, n + 1);
    }
}

pub fn draw(self: *Self, ui: *const UI, is_open: *bool) void {
    _ = ui;
    assert(self.is_init);
    c.igSetNextWindowSize(.{ .x = 630, .y = 240 }, c.ImGuiCond_FirstUseEver);
    if (!c.igBegin(window_name, is_open, 0)) {
        c.igEnd();
        return;
    }

    if (c.igBeginPopup("Options", 0)) {
        _ = c.igCheckbox("Auto-scroll", &self.is_auto_scroll_enabled);
        c.igEndPopup();
    }

    if (c.igButton("Options", .{})) c.igOpenPopup_Str("Options", 0);
    c.igSameLine(0, -1);
    const clear_pressed = c.igButton("Clear", .{});
    c.igSameLine(0, -1);
    const copy_pressed = c.igButton("Copy", .{});
    c.igSameLine(0, -1);
    _ = c.ImGuiTextFilter_Draw(&self.filter, "Filter", -100);

    c.igSeparator();

    if (c.igBeginChild_Str(
        "scroll_x",
        .{},
        c.ImGuiChildFlags_None,
        c.ImGuiWindowFlags_HorizontalScrollbar,
    )) {
        if (clear_pressed) self.clear();
        if (copy_pressed) c.igLogToClipboard(-1);

        c.igPushStyleVar_Vec2(c.ImGuiStyleVar_ItemSpacing, .{});

        const buf = self.buf.items;
        const los = self.line_offsets.items;
        if (c.ImGuiTextFilter_IsActive(&self.filter)) {
            for (los, 0..) |lo, n| {
                const start = buf.ptr + lo;
                const end = buf.ptr + if (n < los.len - 1) los[n + 1] - 1 else buf.len;
                if (c.ImGuiTextFilter_PassFilter(&self.filter, start, end)) {
                    c.igTextUnformatted(start, end);
                }
            }
        } else {
            var clipper: c.ImGuiListClipper = .{};
            c.ImGuiListClipper_Begin(&clipper, @intCast(los.len), -1);
            while (c.ImGuiListClipper_Step(&clipper)) {
                const start_n: usize = @intCast(clipper.DisplayStart);
                const end_n: usize = @intCast(clipper.DisplayEnd);
                for (start_n..end_n) |n| {
                    const start = buf.ptr + los[n];
                    const end = buf.ptr + if (n < los.len - 1) los[n + 1] else buf.len;
                    c.igTextUnformatted(start, end);
                }
            }
            c.ImGuiListClipper_End(&clipper);
        }

        c.igPopStyleVar(1);
        if (self.is_auto_scroll_enabled and c.igGetScrollY() >= c.igGetScrollMaxY()) c.igSetScrollHereY(1.0);
    }
    c.igEndChild();
    c.igEnd();
}

pub fn element(self: *Self) UI.Element {
    return .{
        .ptr = self,
        .drawFn = @ptrCast(&draw),
    };
}
