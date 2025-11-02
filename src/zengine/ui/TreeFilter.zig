//!
//! The zengine property editor window ui
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const UI = @import("UI.zig");

const log = std.log.scoped(.ui_tree_filter);
// pub const sections = perf.sections(@This(), &.{ .init, .draw });

pub const Result = enum {
    not_found,
    sub_passed,
    super_passed,
    passed,
    init,
};

filter: c.ImGuiTextFilter = .{},
toggle_state: bool = false,
buf: [256:0]u8 = @splat(0),
text: [:0]const u8 = "",
min_len: usize = 3,
initial_open_depth: usize = 0,

const Self = @This();

pub fn draw(self: *Self, _: *const UI, _: *bool) void {
    self.toggle_state = false;
    c.igSetNextItemWidth(-std.math.floatMin(f32));
    c.igSetNextItemShortcut(c.ImGuiMod_Ctrl | c.ImGuiKey_F, c.ImGuiInputFlags_Tooltip);
    c.igPushItemFlag(c.ImGuiItemFlags_NoNavDefaultFocus, true);
    if (c.igInputTextWithHint(
        "##Filter",
        "incl, -excl",
        @ptrCast(&self.buf),
        self.buf.len,
        c.ImGuiInputTextFlags_EscapeClearsAll | c.ImGuiInputTextFlags_CallbackEdit,
        @ptrCast(&callback),
        @ptrCast(self),
    )) self.prepare();
    c.igPopItemFlag();
}

fn prepare(self: *Self) void {
    self.text = std.mem.sliceTo(&self.buf, 0);
}

fn callback(data: [*c]c.ImGuiInputTextCallbackData) callconv(.c) c_int {
    const self: *Self = @ptrCast(@alignCast(data.*.UserData));
    self.toggle_state = true;
    return 0;
}

pub fn element(self: *Self) UI.Element {
    return .{
        .ptr = @ptrCast(self),
        .drawFn = @ptrCast(&draw),
    };
}

pub fn toggleOpen(self: *Self, res: Result, depth: ?usize) void {
    if (self.text.len < self.min_len) {
        if (depth) |d| {
            c.igSetNextItemOpen(d < self.initial_open_depth, c.ImGuiCond_Appearing);
        } else c.igSetNextItemOpen(true, c.ImGuiCond_Appearing);
        return;
    }
    switch (res) {
        .sub_passed, .passed => c.igSetNextItemOpen(true, c.ImGuiCond_Appearing),
        else => c.igSetNextItemOpen(false, c.ImGuiCond_Appearing),
    }
    if (!self.toggle_state) return;
    switch (res) {
        .sub_passed, .passed => c.igSetNextItemOpen(true, c.ImGuiCond_Always),
        else => c.igSetNextItemOpen(false, c.ImGuiCond_Always),
    }
}

fn defaultTestFn(self: *Self, key: [*:0]const u8) bool {
    const haystack = std.mem.sliceTo(key, 0);
    return std.mem.indexOf(u8, haystack, self.text) != null;
}

pub fn KeyFn(comptime T: type) type {
    return fn (item: T) ?[*:0]const u8;
}

pub fn WalkFn(comptime T: type) type {
    return fn (filter: *Self, item: T) Result;
}

pub const TestFn = fn (filter: *Self, key: [*:0]const u8) bool;

pub fn Filter(
    comptime T: type,
    comptime config: struct {
        keyFn: KeyFn(T),
        walkFn: WalkFn(T),
        testFn: ?TestFn = null,
        min_width: usize = 3,
    },
) type {
    const testKey = comptime if (config.testFn) |testKey| testKey else defaultTestFn;
    return struct {
        pub fn apply(filter: *Self, item: T, parent_res: Result) Result {
            return switch (parent_res) {
                .not_found => .not_found,
                .passed => switch (applyWalk(filter, item)) {
                    .not_found => .super_passed,
                    .passed, .sub_passed => .passed,
                    .super_passed, .init => unreachable,
                },
                .super_passed => .super_passed,
                .sub_passed, .init => applyWalk(filter, item),
            };
        }

        pub fn applyWalk(filter: *Self, item: T) Result {
            if (config.keyFn(item)) |key| {
                if (testKey(filter, key)) return .passed;
            }

            return config.walkFn(filter, item);
        }
    };
}
