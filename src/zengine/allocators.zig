//!
//! The zengine global allocators module
//!

const std = @import("std");
const assert = std.debug.assert;
pub const Arena = std.heap.ArenaAllocator;

const c = @import("ext.zig").c;
const log_allocator = @import("log_allocator.zig");
const options = @import("zengine.zig").options;
const sdl_allocator = @import("sdl_allocator.zig");

const log = std.log.scoped(.alloc);

pub const GPA = std.heap.DebugAllocator(.{
    .enable_memory_limit = true,
});
const LogAllocator = log_allocator.LogAllocator(.debug, .alloc, options.log_allocations);

pub const ArenaKey = enum {
    global,
    frame,
    scratch,
    perf,
    string,
    ui,
    properties,
};

const Self = struct {
    core: std.mem.Allocator = undefined,
    gpa_state: GPA = undefined,
    log_state: LogAllocator = undefined,
    gpa: std.mem.Allocator = undefined,
    arena_states: std.EnumArray(ArenaKey, Arena) = .initUndefined(),
    arenas: std.EnumArray(ArenaKey, std.mem.Allocator) = .initUndefined(),
    max_alloc: usize = 0,

    fn init(self: *Self, core_allocator: std.mem.Allocator, memory_limit: usize) void {
        self.* = .{};
        self.core = core_allocator;

        self.gpa_state = GPA{
            .backing_allocator = self.core,
            .requested_memory_limit = memory_limit,
        };
        self.log_state = LogAllocator{
            .backing_allocator = self.gpa_state.allocator(),
            .alloc_callback = &updateMaxAlloc,
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

    fn logCapacities(self: *const Self) void {
        log.info("gpa: {B:.3} / {B:.3}", .{
            self.gpa_state.total_requested_bytes,
            self.gpa_state.requested_memory_limit,
        });

        var iter = global_state.arena_states.iterator();
        while (iter.next()) |item| log.info(
            "{t}: {B:.3}",
            .{ item.key, item.value.queryCapacity() },
        );
    }
};

var is_init = false;
var global_state: Self = undefined;

pub fn init(memory_limit: usize) void {
    assert(!is_init);
    global_state.init(sdl_allocator.raw, memory_limit);
    is_init = true;
}

pub fn deinit() void {
    assert(is_init);
    const result = global_state.deinit();
    is_init = false;
    if (global_state.max_alloc != 0) log.info(
        "max allocated: {Bi:.3}\n",
        .{global_state.max_alloc},
    );
    assert(result == .ok);
}

pub inline fn maxAlloc() usize {
    assert(is_init);
    return global_state.max_alloc;
}

fn updateMaxAlloc(_: usize, _: std.mem.Alignment) void {
    assert(is_init);
    global_state.max_alloc = @max(
        global_state.max_alloc,
        global_state.gpa_state.total_requested_bytes,
    );
}

pub fn logCapacities() void {
    assert(is_init);
    global_state.logCapacities();
}

pub inline fn core() std.mem.Allocator {
    assert(is_init);
    return global_state.core;
}

pub inline fn sdl() type {
    return sdl_allocator;
}

pub inline fn gpa() std.mem.Allocator {
    assert(is_init);
    return global_state.gpa;
}

pub inline fn memoryLimit() usize {
    assert(is_init);
    return global_state.gpa_state.requested_memory_limit;
}

pub inline fn queryCapacity() usize {
    assert(is_init);
    return global_state.gpa_state.total_requested_bytes;
}

pub inline fn initArena() Arena {
    return std.heap.ArenaAllocator.init(gpa());
}

pub inline fn arenaState(key: ArenaKey) *Arena {
    assert(is_init);
    return global_state.arena_states.getPtr(key);
}

pub inline fn arena(key: ArenaKey) std.mem.Allocator {
    assert(is_init);
    return global_state.arenas.get(key);
}

pub inline fn arenaReset(key: ArenaKey, mode: Arena.ResetMode) bool {
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

pub inline fn frameFree() void {
    _ = arenaReset(.frame, .free_all);
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

pub inline fn string() std.mem.Allocator {
    return arena(.string);
}

pub inline fn ui() std.mem.Allocator {
    return arena(.ui);
}
