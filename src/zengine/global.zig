const std = @import("std");
const assert = std.debug.assert;

pub const allocators = @import("allocators.zig");
const math = @import("math.zig");
const time = @import("time.zig");

const spaces_buf_count = 1 << 10;

const Self = struct {
    exe_path: []const u8,
    assets_path: []const u8,
    frame_idx: u64 = 0,
    engine_now: u64,
    engine_clock: time.Clock,
    frame_clock: time.Clock,
    spaces_buf: []const u8,

    pub fn init(self: *Self) !void {
        const engine_now = time.getNow();
        const exe_path = try std.fs.selfExeDirPathAlloc(allocators.global());
        const assets_path = try std.fs.path.join(
            allocators.global(),
            &.{ exe_path, "..", "..", "assets" },
        );
        const spaces_buf = try allocators.gpa().alloc(u8, spaces_buf_count);
        for (spaces_buf) |*space| space.* = ' ';

        self.* = .{
            .exe_path = exe_path,
            .assets_path = assets_path,
            .engine_now = engine_now,
            .engine_clock = .init(engine_now),
            .frame_clock = .init(engine_now),
            .spaces_buf = spaces_buf,
        };
    }

    pub fn deinit(self: *Self) void {
        allocators.gpa().free(self.spaces_buf);
    }

    pub fn startFrame(self: *Self, now: u64) void {
        self.frame_idx += 1;
        self.engine_now = now;
    }

    pub fn finishFrame(self: *Self) void {
        self.frame_clock.start(self.engine_now);
    }
};

var is_init = false;
var global_state: Self = undefined;

pub fn init() !void {
    assert(!is_init);
    try global_state.init();
    is_init = true;
}

pub fn deinit() void {
    assert(is_init);
    global_state.deinit();
    is_init = false;
}

pub fn isFirstFrame() bool {
    assert(is_init);
    return global_state.frame_idx <= 1;
}

pub fn startFrame() void {
    assert(is_init);
    global_state.startFrame(time.getNow());
}

pub fn finishFrame() void {
    assert(is_init);
    global_state.finishFrame();
}

pub inline fn exePath() []const u8 {
    assert(is_init);
    return global_state.exe_path;
}

pub inline fn assetsPath() []const u8 {
    assert(is_init);
    return global_state.assets_path;
}

pub inline fn frameIndex() u64 {
    assert(is_init);
    return global_state.frame_idx;
}

pub inline fn engineStart() u64 {
    assert(is_init);
    return global_state.engine_clock.start_time;
}

pub inline fn engineNow() u64 {
    assert(is_init);
    return global_state.engine_clock.elapsed(global_state.engine_now);
}

pub inline fn engineTime() time.Time {
    return .{ .ms = engineNow() };
}

pub inline fn sinceStart() u64 {
    assert(is_init);
    return global_state.engine_clock.elapsed(global_state.engine_now);
}

pub inline fn timeSinceStart() time.Time {
    return .{ .ms = sinceStart() };
}

pub inline fn sinceLastFrame() u64 {
    assert(is_init);
    return global_state.frame_clock.elapsed(global_state.engine_now);
}

pub inline fn timeSinceLastFrame() time.Time {
    return .{ .ms = sinceLastFrame() };
}

pub inline fn spaces(count: usize) []const u8 {
    assert(is_init);
    assert(count <= spaces_buf_count);
    return global_state.spaces_buf[0..count];
}

pub inline fn up() math.Vector3 {
    return .{ 0, 1, 0 };
}

pub inline fn cameraUp() math.Vector3 {
    return .{ 0, 1, 0 };
}
