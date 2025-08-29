const std = @import("std");
const sdl = @import("ext/sdl.zig");
const assert = std.debug.assert;

pub const GPA = std.heap.DebugAllocator(.{
    .enable_memory_limit = true,
    .thread_safe = false,
    // .safety = false,
});

pub const Arena = std.heap.ArenaAllocator;

pub const Allocators = struct {
    core: std.mem.Allocator = undefined,
    gpa_state: GPA = undefined,
    arena_state: Arena = undefined,
    frame_arena_state: Arena = undefined,

    const Self = @This();

    pub fn init(self: *Self, core_allocator: std.mem.Allocator, memory_limit: usize) void {
        self.core = core_allocator;

        self.gpa_state = GPA{
            .backing_allocator = self.core,
            .requested_memory_limit = memory_limit,
        };

        self.arena_state = Arena.init(self.gpa_state.allocator());
        self.frame_arena_state = Arena.init(self.gpa_state.allocator());
    }

    pub fn deinit(self: *Self) std.heap.Check {
        self.arena_state.deinit();
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
    return global_state.gpa_state.allocator();
}

pub fn arena() std.mem.Allocator {
    assert(is_init);
    return global_state.arena_state.allocator();
}

pub fn frameArena() std.mem.Allocator {
    assert(is_init);
    return global_state.frame_arena_state.allocator();
}
