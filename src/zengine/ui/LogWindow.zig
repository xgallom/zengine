//!
//! The zengine log window ui
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("ext");
const containers = @import("../containers.zig");
const global = @import("../global.zig");
const sched = @import("../sched.zig");
const UI = @import("UI.zig");

allocator: std.mem.Allocator = undefined,
buffer: Buffer = .invalid,
line_offsets: LineOffsets = .invalid,
is_init: bool = false,
is_open: bool = true,
is_auto_scroll_enabled: bool = true,
filter: c.ImGuiTextFilter = .{},
lock: sched.Spinlock = .init,

const Self = @This();
const Buffer = containers.RingBuffer(u8, max_lines * max_line_len);
const LineOffsets = containers.RingBuffer(usize, max_lines);
pub const window_name = "Debug Log";
pub const invalid: Self = .{};
const max_line_len = 1 << 8;
const max_lines = 16 << 10;

pub fn init(gpa: std.mem.Allocator) !Self {
    var line_offsets = try containers.RingBuffer(usize, max_lines).init(gpa);
    errdefer line_offsets.deinit(gpa);
    line_offsets.appendAssumeCapacity(0);
    return .{
        .allocator = gpa,
        .buffer = try .init(gpa),
        .line_offsets = line_offsets,
        .is_init = true,
    };
}

pub fn deinit(self: *Self) void {
    if (self.is_init) {
        self.buffer.deinit(self.allocator);
        self.line_offsets.deinit(self.allocator);
        self.is_init = false;
    }
}

pub fn clear(self: *Self) void {
    if (!self.is_init) return;
    self.lock.lock(.spinloop);
    defer self.lock.unlock();

    // WARN: This function must not use std.log!

    self.clearImpl();
}

fn clearImpl(self: *Self) void {
    assert(self.is_init);
    self.buffer.reset();
    self.line_offsets.reset();
    self.line_offsets.appendAssumeCapacity(0);
}

/// Only intended to be called from the log handler, which ensures every call ends with a newline.
/// Calling this without a newline such that a single line exceeds max_line_len is safety-checked
/// illegal behavior.
pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) !void {
    if (!self.is_init) return;
    self.lock.lock(.spinloop);
    defer self.lock.unlock();

    // WARN: This function must not use std.log!

    nosuspend {
        var msg_buf: [max_line_len]u8 = undefined;
        const msg = try std.fmt.bufPrint(&msg_buf, fmt, args);
        var w = self.buffer.writer(&msg_buf);
        w.interface.end = msg.len;
        while (true) {
            const start = self.buffer.head;
            _ = w.drain(&.{""}, 0) catch {};
            const removed_lines = self.indexLines(start, self.buffer.head);
            if (w.interface.end == 0) {
                break;
            } else if (removed_lines == 0) self.removeFirstLine();
        }
    }
}

fn indexLines(self: *Self, start: usize, end: usize) usize {
    var idx: usize = start;
    var removed_lines: usize = 0;
    while (idx != end) : (idx +%= 1) {
        if (self.buffer.get(idx) == '\n') {
            self.line_offsets.append(idx +% 1) catch {
                self.removeFirstLine();
                self.line_offsets.appendAssumeCapacity(idx +% 1);
                removed_lines += 1;
            };
        }
    }
    return removed_lines;
}

fn removeFirstLine(self: *Self) void {
    assert(self.line_offsets.length() > 1);
    const old_tail = self.line_offsets.popFirst().?;
    assert(old_tail == self.buffer.tail);
    self.buffer.tail = self.line_offsets.getFirst();
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
        self.lock.lock(.spinloop);
        defer self.lock.unlock();

        // WARN: This block must not use std.log!

        if (clear_pressed) self.clearImpl();
        if (copy_pressed) c.igLogToClipboard(-1);

        c.igPushStyleVar_Vec2(c.ImGuiStyleVar_ItemSpacing, .{});

        var msg_buf: [max_line_len]u8 = undefined;
        const buf = self.buffer.allocatedSlice();
        if (c.ImGuiTextFilter_IsActive(&self.filter)) {
            var los = self.line_offsets.iterator();
            const start_n = los.cursor.tail;
            const end_n = los.cursor.head;
            assert(end_n > start_n);
            for (start_n..end_n - 1) |n| {
                _ = n;
                const tail = los.next() orelse unreachable;
                const head = if (los.peek()) |l| l -% 1 else unreachable;
                const msg = getLine(&msg_buf, buf, tail, head);
                if (c.ImGuiTextFilter_PassFilter(&self.filter, msg.ptr, msg.ptr + msg.len)) {
                    c.igTextUnformatted(msg.ptr, msg.ptr + msg.len);
                }
            }
        } else {
            var clipper: c.ImGuiListClipper = .{};
            assert(self.line_offsets.length() > 0);
            c.ImGuiListClipper_Begin(&clipper, @intCast(self.line_offsets.length() - 1), -1);
            while (c.ImGuiListClipper_Step(&clipper)) {
                const start_n: usize = @intCast(clipper.DisplayStart);
                const end_n: usize = @intCast(clipper.DisplayEnd);
                var los = self.line_offsets.iterator();
                los.cursor.tail +%= start_n;
                for (start_n..end_n) |n| {
                    _ = n;
                    const tail = los.next() orelse unreachable;
                    const head = if (los.peek()) |l| l -% 1 else unreachable;
                    const msg = getLine(&msg_buf, buf, tail, head);
                    c.igTextUnformatted(msg.ptr, msg.ptr + msg.len);
                }
            }
            c.ImGuiListClipper_End(&clipper);
        }

        c.igPopStyleVar(1);
        if (self.is_auto_scroll_enabled and c.igGetScrollY() >= c.igGetScrollMaxY()) {
            c.igSetScrollHereY(1.0);
        }
    }
    c.igEndChild();
    c.igEnd();
}

fn getLine(dst: []u8, src: []const u8, tail: usize, head: usize) []const u8 {
    const start = Buffer.mask.offset(tail);
    const end = Buffer.mask.offset(head);
    var len: usize = 0;
    if (start < end) {
        len = end - start;
        assert(len <= dst.len);
        @memcpy(dst[0..len], src[start..end]);
    } else if (start > end) {
        const len_0 = Buffer.capacity - start;
        len = len_0 + end;
        assert(len <= dst.len);
        @memcpy(dst[0..len_0], src[start..]);
        @memcpy(dst[len_0..len], src[0..end]);
    }
    return dst[0..len];
}

pub fn element(self: *Self) UI.Element {
    return .{
        .ptr = self,
        .drawFn = @ptrCast(&draw),
    };
}
