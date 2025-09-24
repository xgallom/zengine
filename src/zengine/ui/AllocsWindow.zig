//!
//! The zengine memory allocations monitoring window ui
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const perf = @import("../perf.zig");
const UI = @import("UI.zig");
const time = @import("../time.zig");
const plot_fmt = @import("plot_fmt.zig");

const log = std.log.scoped(.ui_allocs_window);

is_open: bool = true,

pub const Self = @This();
pub const window_name = "Allocations";
var buf: [64]u8 = undefined;

pub fn init() Self {
    return .{};
}

pub fn deinit(_: *Self) void {}

pub fn draw(_: *Self, ui: *const UI, is_open: *bool) void {
    _ = ui;
    c.igSetNextWindowSize(.{ .x = 630, .y = 4 * 240 }, c.ImGuiCond_FirstUseEver);
    if (!c.igBegin(window_name, is_open, 0)) {
        c.igEnd();
        return;
    }

    if (c.igBeginChild_Str(
        "##allocs",
        .{},
        c.ImGuiChildFlags_NavFlattened,
        0,
    )) {
        if (c.igBeginTable("##allocs", 2, c.ImGuiTableFlags_ScrollY, .{}, 0)) {
            c.igPushID_Str("allocs");
            c.igTableSetupColumn("name", c.ImGuiTableColumnFlags_WidthFixed, 120, 0);
            c.igTableSetupColumn("value", c.ImGuiTableColumnFlags_WidthStretch, 0, 0);

            {
                c.igTableNextRow(0, 0);
                c.igPushID_Str("##limit");

                _ = c.igTableNextColumn();
                c.igAlignTextToFramePadding();
                c.igTextUnformatted("Memory limit", null);

                _ = c.igTableNextColumn();
                c.igAlignTextToFramePadding();
                const text = std.fmt.bufPrintZ(
                    &buf,
                    "{B:.3}",
                    .{allocators.memoryLimit()},
                ) catch unreachable;
                c.igTextUnformatted(text, null);

                c.igPopID();
            }

            {
                c.igTableNextRow(0, 0);
                c.igPushID_Str("##gpa");

                _ = c.igTableNextColumn();
                c.igAlignTextToFramePadding();
                c.igTextUnformatted("Total allocated", null);

                _ = c.igTableNextColumn();
                c.igAlignTextToFramePadding();
                const text = std.fmt.bufPrintZ(
                    &buf,
                    "{B:.3}",
                    .{allocators.queryCapacity()},
                ) catch unreachable;
                c.igTextUnformatted(text, null);

                c.igPopID();
            }

            inline for (comptime std.enums.values(allocators.ArenaKey)) |arena_key| {
                c.igTableNextRow(0, 0);
                c.igPushID_Str("##" ++ @tagName(arena_key));

                _ = c.igTableNextColumn();
                c.igAlignTextToFramePadding();
                c.igTextUnformatted("Arena " ++ @tagName(arena_key), null);

                _ = c.igTableNextColumn();
                c.igAlignTextToFramePadding();
                const text = std.fmt.bufPrintZ(
                    &buf,
                    "{B:.3}",
                    .{allocators.arenaState(arena_key).queryCapacity()},
                ) catch unreachable;
                c.igTextUnformatted(text, null);

                c.igPopID();
            }

            {
                c.igTableNextRow(0, 0);
                c.igPushID_Str("##max");

                _ = c.igTableNextColumn();
                c.igAlignTextToFramePadding();
                c.igTextUnformatted("Max allocated", null);

                _ = c.igTableNextColumn();
                c.igAlignTextToFramePadding();
                const text = std.fmt.bufPrintZ(
                    &buf,
                    "{B:.3}",
                    .{allocators.maxAlloc()},
                ) catch unreachable;
                c.igTextUnformatted(text, null);

                c.igPopID();
            }

            c.igPopID();
            c.igEndTable();
        }
    }
    c.igEndChild();
    c.igEnd();
}

pub fn element(self: *Self) UI.Element {
    return .{
        .ptr = @ptrCast(self),
        .drawFn = @ptrCast(&draw),
    };
}
