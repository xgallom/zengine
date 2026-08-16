//!
//! Zengine thread pool implementation
//!

const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

const allocators = @import("../allocators.zig");
const options = @import("../options.zig").options;

const log = std.log.scoped(.sched_thread_pool);

const c = switch (builtin.os.tag) {
    .macos => @cImport({
        @cInclude("pthread.h");
    }),
    else => @compileError("Unsupported OS"),
};

pub const ThreadPriority = enum { main, default, background };
pub fn setPriority(comptime priority: ThreadPriority) !void {
    switch (builtin.os.tag) {
        .macos => {
            const qos = switch (priority) {
                .main => c.qos_class_main(),
                .default => c.QOS_CLASS_USER_INITIATED,
                .background => c.QOS_CLASS_BACKGROUND,
            };
            switch (std.posix.errno(c.pthread_set_qos_class_self_np(qos, 0))) {
                .SUCCESS => {},
                else => |err| {
                    log.err("failed setting thread priority: {t}", .{err});
                    return error.SetPriorityFailed;
                },
            }
        },
        else => @compileError("Unsupported OS"),
    }
}

pub fn pinToCore(core: u32) !void {
    _ = core;
    @compileError("Unsupported OS");
}
