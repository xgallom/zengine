//!
//! The zengine memory allocations monitoring window ui
//!

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const zcore = @import("zcore");
const allocators = zcore.allocators;
const c = zcore.ext;
const str = zcore.str;
const time = zcore.time;

const global = @import("../global.zig");
const perf = @import("../perf.zig");
const plot_fmt = @import("plot_fmt.zig");
const UI = @import("UI.zig");

const log = std.log.scoped(.ui_allocs_window);

is_open: bool = false,
arenas: std.ArrayList(ArenaItem) = .empty,

const Self = @This();
pub const window_name = "Allocations";
var buf: [64]u8 = undefined;

pub const ArenaItem = struct {
    id: [:0]const u8,
    name: [:0]const u8,
    arena: *ArenaAllocator,
};

pub fn init() Self {
    return .{};
}

pub fn deinit(self: *Self, gpa: Allocator) void {
    self.arenas.deinit(gpa);
}

pub fn appendArena(
    self: *Self,
    gpa: Allocator,
    name: [:0]const u8,
    arena: *std.heap.ArenaAllocator,
) !void {
    try self.arenas.append(gpa, .{
        .id = try str.allocPrintZ("##{s}", .{name}),
        .name = try str.allocPrintZ("Arena {s}", .{name}),
        .arena = arena,
    });
}

pub fn draw(self: *Self, ui: *const UI, is_open: *bool) void {
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
                const text = std.fmt.bufPrintSentinel(
                    &buf,
                    "{Bi:.3}",
                    .{allocators.memoryLimit()},
                    0,
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
                const text = std.fmt.bufPrintSentinel(
                    &buf,
                    "{Bi:.3}",
                    .{allocators.queryCapacity()},
                    0,
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
                const text = std.fmt.bufPrintSentinel(
                    &buf,
                    "{Bi:.3}",
                    .{allocators.arenaState(arena_key).queryCapacity()},
                    0,
                ) catch unreachable;
                c.igTextUnformatted(text, null);

                c.igPopID();
            }

            for (self.arenas.items) |item| {
                c.igTableNextRow(0, 0);
                c.igPushID_Str(item.id);

                _ = c.igTableNextColumn();
                c.igAlignTextToFramePadding();
                c.igTextUnformatted(item.name, null);

                _ = c.igTableNextColumn();
                c.igAlignTextToFramePadding();
                const text = std.fmt.bufPrintSentinel(
                    &buf,
                    "{Bi:.3}",
                    .{item.arena.queryCapacity()},
                    0,
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
                const text = std.fmt.bufPrintSentinel(
                    &buf,
                    "{Bi:.3}",
                    .{allocators.maxAlloc()},
                    0,
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
