const std = @import("std");
const assert = std.debug.assert;

const FRAMERATE_BUF_COUNT = 256;
const FRAMERATE_IDX_MASK = FRAMERATE_BUF_COUNT - 1;

const Perf = struct {
    allocator: std.mem.Allocator,
    framerate_buf: []u64,
    framerate_idx: usize = 0,
    framerate: u32 = 1,

    const Self = @This();

    fn init(allocator: std.mem.Allocator) !Self {
        const framerate_buf = try allocator.alloc(u64, FRAMERATE_BUF_COUNT);
        for (framerate_buf) |*i| i.* = 0;
        return .{
            .allocator = allocator,
            .framerate_buf = framerate_buf,
        };
    }

    fn deinit(self: *Self) void {
        self.allocator.free(self.framerate_buf);
    }

    fn update(self: *Self, now: u64) void {
        const framerate_start_time = (now -| 1001) + 1;
        self.framerate = 1;
        for (self.framerate_buf) |item| {
            if (item >= framerate_start_time) self.framerate += 1;
        }
        self.framerate_idx = (self.framerate_idx + 1) & FRAMERATE_IDX_MASK;
        self.framerate_buf[self.framerate_idx] = now;
    }
};

var is_init = false;
var global_state: Perf = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    assert(!is_init);

    global_state = try Perf.init(allocator);
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

pub fn framerate() u32 {
    assert(is_init);
    return global_state.framerate;
}
