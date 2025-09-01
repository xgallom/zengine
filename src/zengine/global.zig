const std = @import("std");
const assert = std.debug.assert;

const math = @import("math.zig");
const time = @import("time.zig");

const Global = struct {
    exe_path: []const u8,
    frame_idx: u64 = 0,
    now: u64,
    clock: time.Clock,

    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(self: *Self, allocator: std.mem.Allocator) !void {
        const now = time.getNow();
        self.* = .{
            .exe_path = try std.fs.selfExeDirPathAlloc(allocator),
            .now = now,
            .clock = .init(now),

            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.exe_path);
    }

    pub fn update(self: *Self, now: u64) void {
        self.frame_idx += 1;
        self.clock.update(now);
    }
};

var is_init = false;
var global_state: Global = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    assert(!is_init);

    try global_state.init(allocator);
    is_init = true;
}

pub fn deinit() void {
    assert(is_init);

    global_state.deinit();
    is_init = false;
}

pub fn update(now: u64) void {
    assert(is_init);
    global_state.update(now);
}

pub fn exePath() []const u8 {
    assert(is_init);
    return global_state.exe_path;
}

pub fn frameIndex() u64 {
    assert(is_init);
    return global_state.frame_idx;
}

pub fn getNow() u64 {
    assert(is_init);
    return global_state.now;
}

pub fn setNow(now: u64) void {
    assert(is_init);
    global_state.now = now;
}

pub fn sinceStart() u64 {
    assert(is_init);
    return global_state.clock.sinceStart(global_state.now);
}

pub fn sinceUpdate() u64 {
    assert(is_init);
    return global_state.clock.sinceUpdate(global_state.now);
}

pub fn up() math.Vector3 {
    return .{ 0, 1, 0 };
}

pub fn cameraUp() math.Vector3 {
    return .{ 0, 1, 0 };
}
