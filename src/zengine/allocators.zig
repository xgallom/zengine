const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("ext/sdl.zig");
const assert = std.debug.assert;

const is_debug = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;
pub const GPA = std.heap.DebugAllocator(.{
    .enable_memory_limit = true,
    .thread_safe = true,
    .safety = true,
    // .safety = false,
});

pub const Arena = std.heap.ArenaAllocator;

pub const ArenaType = enum {
    global,
    frame,
    scratch,
};

const Allocators = struct {
    core: std.mem.Allocator = undefined,
    gpa_state: GPA = undefined,
    gpa: std.mem.Allocator = undefined,
    arenas: std.EnumArray(ArenaType, Arena) = .initUndefined(),

    const Self = @This();

    fn init(self: *Self, core_allocator: std.mem.Allocator, memory_limit: usize) void {
        self.core = core_allocator;

        self.gpa_state = GPA{
            .backing_allocator = self.core,
            .requested_memory_limit = memory_limit,
        };
        self.gpa = if (is_debug) self.gpa_state.allocator() else std.heap.smp_allocator;

        var iter = self.arenas.iterator();
        while (iter.next()) |item| item.value.* = Arena.init(self.gpa);
    }

    fn deinit(self: *Self) std.heap.Check {
        var iter = self.arenas.iterator();
        while (iter.next()) |item| item.value.deinit();
        const result = self.gpa_state.deinit();
        self.* = Self{};
        return result;
    }
};

var is_init = false;
pub var global_state: Allocators = undefined;

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

pub fn core() std.mem.Allocator {
    assert(is_init);
    return global_state.core;
}

pub fn gpa() std.mem.Allocator {
    assert(is_init);
    return global_state.gpa;
}

pub fn arenaState(key: ArenaType) *Arena {
    assert(is_init);
    return global_state.arenas.getPtr(key);
}

pub fn arena(key: ArenaType) std.mem.Allocator {
    return arenaState(key).allocator();
}

pub fn arenaReset(key: ArenaType, mode: Arena.ResetMode) bool {
    return arenaState(key).reset(mode);
}

pub fn global() std.mem.Allocator {
    return arena(.global);
}

pub fn frame() std.mem.Allocator {
    return arena(.frame);
}

pub fn frameReset() void {
    _ = arenaReset(.frame, .retain_capacity);
}

pub fn scratch() std.mem.Allocator {
    return arena(.scratch);
}

pub fn scratchRelease() void {
    _ = arenaReset(.scratch, .retain_capacity);
}

pub fn scratchFree() void {
    _ = arenaReset(.scratch, .free_all);
}
