const std = @import("std");
const assert = std.debug.assert;

const math = @import("math.zig");

pub const Global = struct {
    exe_path: []const u8,

    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(self: *Self, allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        self.exe_path = try std.fs.selfExeDirPathAlloc(self.allocator);
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.exe_path);
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

pub fn exe_path() []const u8 {
    assert(is_init);
    return global_state.exe_path;
}

pub fn up() math.Vector3 {
    return .{ 0, 1, 0 };
}

pub fn camera_up() math.Vector3 {
    return .{ 0, 1, 0 };
}
