const std = @import("std");
const assert = std.debug.assert;

pub const allocators = @import("allocators.zig");
const c = @import("ext.zig").c;
const options = @import("options.zig").options;
const str = @import("str.zig");
const math = @import("math.zig");
const time = @import("time.zig");

const spaces_buf_len = 1 << 10;

const Self = struct {
    exe_path: []const u8,
    args: []const [:0]const u8,
    resources_path: [:0]const u8,
    assets_path: [:0]const u8,
    prefs_path: [:0]const u8,
    frame_idx: u64 = 0,
    engine_now_ns: u64,
    engine_clock_ns: time.Clock,
    frame_clock_ns: time.Clock,
    spaces_buf: []const u8,

    pub fn init(self: *Self) !void {
        const engine_now_ns = time.getNano();
        const app_args = try std.process.argsAlloc(allocators.global());
        const exe_path = try std.fs.selfExeDirPathAlloc(allocators.global());
        const is_macos_app = str.contains(exe_path, ".app/Contents/MacOS");
        const resources_path = try std.fs.path.joinZ(
            allocators.global(),
            if (is_macos_app)
                &.{ exe_path, "..", "Resources" }
            else
                &.{ exe_path, ".." },
        );
        const assets_path = try std.fs.path.joinZ(
            allocators.global(),
            &.{ resources_path, "assets" },
        );
        const c_prefs_path = c.SDL_GetPrefPath(
            options.org_identifier.ptr,
            options.app_identifier.ptr,
        );
        defer allocators.sdl().free(c_prefs_path);
        const prefs_path = try allocators.global().dupeZ(
            u8,
            std.mem.trimRight(u8, std.mem.span(c_prefs_path), "\\/"),
        );
        const spaces_buf = try allocators.gpa().alloc(u8, spaces_buf_len);
        @memset(spaces_buf, ' ');

        self.* = .{
            .args = app_args[1..],
            .exe_path = exe_path,
            .resources_path = resources_path,
            .assets_path = assets_path,
            .prefs_path = prefs_path,
            .engine_now_ns = engine_now_ns,
            .engine_clock_ns = .init(engine_now_ns),
            .frame_clock_ns = .init(engine_now_ns),
            .spaces_buf = spaces_buf,
        };
    }

    pub fn deinit(self: *Self) void {
        allocators.gpa().free(self.spaces_buf);
    }

    pub fn startFrame(self: *Self, now: u64) void {
        self.frame_idx += 1;
        self.engine_now_ns = now;
    }

    pub fn finishFrame(self: *Self) void {
        self.frame_clock_ns.start(self.engine_now_ns);
    }
};

// TODO: Replace with bindable pointer for cross-
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
    global_state.startFrame(time.getNano());
}

pub fn finishFrame() void {
    assert(is_init);
    global_state.finishFrame();
}

pub inline fn args() []const [:0]const u8 {
    assert(is_init);
    return global_state.args;
}

pub inline fn arg(n: usize) [:0]const u8 {
    assert(is_init);
    assert(n < global_state.args.len);
    return global_state.args[n];
}

pub inline fn exePath() []const u8 {
    assert(is_init);
    return global_state.exe_path;
}

pub inline fn resourcesPath() [:0]const u8 {
    assert(is_init);
    return global_state.resources_path;
}

pub inline fn assetsPath() [:0]const u8 {
    assert(is_init);
    return global_state.assets_path;
}

pub inline fn assetPath(path: []const u8) ![:0]const u8 {
    assert(is_init);
    return std.fs.path.joinZ(allocators.global(), &.{ assetsPath(), path });
}

pub inline fn assetsDir(flags: std.fs.Dir.OpenOptions) !std.fs.Dir {
    assert(is_init);
    return std.fs.openDirAbsolute(assetsPath(), flags);
}

pub inline fn prefsPath() [:0]const u8 {
    assert(is_init);
    return global_state.prefs_path;
}

pub inline fn prefPath(path: []const u8) ![:0]const u8 {
    assert(is_init);
    return std.fs.path.joinZ(allocators.global(), &.{ prefsPath(), path });
}

pub inline fn prefsDir(flags: std.fs.Dir.OpenOptions) !std.fs.Dir {
    assert(is_init);
    return std.fs.openDirAbsolute(prefsPath(), flags);
}

pub inline fn frameIndex() u64 {
    assert(is_init);
    return global_state.frame_idx;
}

pub inline fn engineStart() u64 {
    assert(is_init);
    return global_state.engine_clock_ns.start_time / std.time.ns_per_ms;
}

pub inline fn engineStartNano() u64 {
    assert(is_init);
    return global_state.engine_clock_ns.start_time;
}

pub inline fn engineLastFrame() u64 {
    assert(is_init);
    return global_state.frame_clock_ns.start_time / std.time.ns_per_ms;
}

pub inline fn engineLastFrameNano() u64 {
    assert(is_init);
    return global_state.frame_clock_ns.start_time;
}

pub inline fn engineNow() u64 {
    assert(is_init);
    return global_state.engine_now_ns / std.time.ns_per_ms;
}

pub inline fn engineNowNano() u64 {
    assert(is_init);
    return global_state.engine_now_ns;
}

pub inline fn engineTime() time.Time {
    return .{ .ms = engineNow() };
}

pub inline fn engineTimeNano() time.Time {
    return .{ .ns = engineNowNano() };
}

pub inline fn sinceStart() u64 {
    assert(is_init);
    return global_state.engine_clock_ns.elapsed(global_state.engine_now_ns) / std.time.ns_per_ms;
}

pub inline fn sinceStartNano() u64 {
    assert(is_init);
    return global_state.engine_clock_ns.elapsed(global_state.engine_now_ns);
}

pub inline fn timeSinceStart() time.Time {
    return .{ .ms = sinceStart() };
}

pub inline fn timeSinceStartNano() time.Time {
    return .{ .ns = sinceStartNano() };
}

pub inline fn sinceLastFrame() u64 {
    assert(is_init);
    return global_state.frame_clock_ns.elapsed(global_state.engine_now_ns) / std.time.ns_per_ms;
}

pub inline fn sinceLastFrameNano() u64 {
    assert(is_init);
    return global_state.frame_clock_ns.elapsed(global_state.engine_now_ns);
}

pub inline fn timeSinceLastFrame() time.Time {
    return .{ .ms = sinceLastFrame() };
}

pub inline fn timeSinceLastFrameNano() time.Time {
    return .{ .ns = sinceLastFrameNano() };
}

pub inline fn spaces(count: usize) []const u8 {
    assert(is_init);
    assert(count <= spaces_buf_len);
    return global_state.spaces_buf[0..count];
}

pub inline fn up() math.Vector3 {
    return .{ 0, 1, 0 };
}

pub inline fn cameraUp() math.Vector3 {
    return .{ 0, 1, 0 };
}
