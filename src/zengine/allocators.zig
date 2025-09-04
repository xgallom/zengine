const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("ext/sdl.zig");
const assert = std.debug.assert;
const allocator = @import("allocator.zig");

pub const GPA = std.heap.DebugAllocator(.{
    .enable_memory_limit = true,
});
pub const Arena = std.heap.ArenaAllocator;

const LogAllocator = allocator.LogAllocator(.debug, .alloc, std.debug.runtime_safety);

pub const ArenaType = enum {
    global,
    frame,
    scratch,
};

const Self = struct {
    core: std.mem.Allocator = undefined,
    gpa_state: GPA = undefined,
    log_state: LogAllocator,
    gpa: std.mem.Allocator = undefined,
    arena_states: std.EnumArray(ArenaType, Arena) = .initUndefined(),
    arenas: std.EnumArray(ArenaType, std.mem.Allocator) = .initUndefined(),

    fn init(self: *Self, core_allocator: std.mem.Allocator, memory_limit: usize) void {
        self.core = core_allocator;

        self.gpa_state = GPA{
            .backing_allocator = self.core,
            .requested_memory_limit = memory_limit,
        };
        self.log_state = LogAllocator{
            .backing_allocator = self.gpa_state.allocator(),
        };
        self.gpa = self.log_state.allocator();

        var iter = self.arena_states.iterator();
        while (iter.next()) |item| {
            item.value.* = Arena.init(self.gpa);
            self.arenas.set(item.key, item.value.allocator());
        }
    }

    fn deinit(self: *Self) std.heap.Check {
        var iter = self.arena_states.iterator();
        while (iter.next()) |item| item.value.deinit();
        return self.gpa_state.deinit();
    }
};

var is_init = false;
var global_state: Self = undefined;

pub fn init(core_allocator: std.mem.Allocator, memory_limit: usize) void {
    assert(!is_init);
    global_state.init(core_allocator, memory_limit);
    is_init = true;
}

pub fn deinit() void {
    assert(is_init);
    const result = global_state.deinit();
    is_init = false;
    assert(result == .ok);
}

pub inline fn core() std.mem.Allocator {
    assert(is_init);
    return global_state.core;
}

pub inline fn gpa() std.mem.Allocator {
    assert(is_init);
    return global_state.gpa;
}

pub inline fn queryCapacity() usize {
    assert(is_init);
    return global_state.gpa_state.total_requested_bytes;
}

pub inline fn arenaState(key: ArenaType) *Arena {
    assert(is_init);
    return global_state.arena_states.getPtr(key);
}

pub inline fn arena(key: ArenaType) std.mem.Allocator {
    assert(is_init);
    return global_state.arenas.get(key);
}

pub inline fn arenaReset(key: ArenaType, mode: Arena.ResetMode) bool {
    return arenaState(key).reset(mode);
}

pub inline fn global() std.mem.Allocator {
    return arena(.global);
}

pub inline fn frame() std.mem.Allocator {
    return arena(.frame);
}

pub inline fn frameReset() void {
    _ = arenaReset(.frame, .retain_capacity);
}

pub inline fn scratch() std.mem.Allocator {
    return arena(.scratch);
}

pub inline fn scratchRelease() void {
    _ = arenaReset(.scratch, .retain_capacity);
}

pub inline fn scratchFree() void {
    _ = arenaReset(.scratch, .{ .retain_with_limit = 1 << 10 });
}
