//!
//! Zengine thread pool implementation
//!

const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const options = @import("../options.zig").options;
const time = @import("../time.zig");
const Zengine = @import("../zengine.zig").Zengine;

const Barrier = @import("Barrier.zig");
const ThreadInfo = @import("ThreadInfo.zig");
const platform = @import("platform.zig");

const log = std.log.scoped(.sched_thread_pool);

const max_threads = options.max_threads;

pub const GroupConfig = struct {
    ctx: type,
    len: Length,
    priority: platform.ThreadPriority = .default,

    pub const Length = enum(u32) {
        remaining,
        one,
        _,

        pub fn init(len: u32) @This() {
            return @enumFromInt(len);
        }
    };

    pub fn handlerFn(comptime self: @This()) type {
        return HandlerFn(self.ctx);
    }
};

fn Handlers(comptime configs: []const GroupConfig) type {
    var fields: []const type = &.{};
    inline for (configs) |config| fields = fields ++ &[_]type{config.handlerFn()};
    return @Tuple(fields);
}

fn Contexts(comptime configs: []const GroupConfig) type {
    var fields: []const type = &.{};
    inline for (configs) |config| fields = fields ++ &[_]type{config.ctx};
    return @Tuple(fields);
}

fn HandlerFn(comptime Ctx: type) type {
    return fn (
        self: *Zengine,
        info: *const ThreadInfo,
        global_state: *ThreadInfo.GroupSharedState,
        ctx: Ctx,
    ) anyerror!bool;
}

pub const State = enum(u32) {
    init,
    running,
    stopping,
};

pub const Data = extern struct {
    state: State = .init,
    len: u32,
    spawned: u32 = 0,
    pad: [pad_len]u8 = undefined,
    items: [max_threads]*anyopaque = undefined,

    const pad_len = std.atomic.cache_line - @sizeOf([max_threads]*anyopaque) -
        @sizeOf(u32) * 2 - @sizeOf(State);
    comptime {
        // Nothing breaks but cache-alignment should be reworked in case this does not hold,
        // possibly just by swapping pad and items.
        assert(std.atomic.cache_line == 128);
        assert(max_threads <= 12);
        assert(pad_len > 0);
    }
};

pub fn ThreadPool(comptime groups: []const GroupConfig, comptime handlers: Handlers(groups)) type {
    return struct {
        data: Data align(std.atomic.cache_line),
        pool_state: ThreadInfo.GroupSharedState = undefined,
        group_states: [groups.len]ThreadInfo.GroupSharedState = undefined,

        const Self = @This();

        pub const static_len = blk: {
            var result = 0;
            for (groups) |config| switch (config.len) {
                .remaining => {},
                else => result += @intFromEnum(config.len),
            };
            break :blk result;
        };
        pub const has_remaining = for (groups) |config| {
            if (config.len == .remaining) break true;
        } else false;

        pub fn create() !*Self {
            const thread_count = @min(try std.Thread.getCpuCount(), max_threads);
            const self = try allocators.global().create(Self);
            log.info("thread pool size: {}", .{thread_count});
            self.* = .{ .data = .{ .len = @intCast(thread_count) } };
            return self;
        }

        pub fn deinit(self: *Self) void {
            if (self.data.spawned > 0) {
                self.sendQuit();
                self.join();
            }
        }

        /// This function is not thread-safe.
        /// Caller ensures this is run from single-threaded context.
        /// Call to this function once the thread pool is running returns an error.
        pub fn run(
            self: *Self,
            zengine: *Zengine,
            ctx: Contexts(groups),
        ) !void {
            if (builtin.single_threaded) {
                @compileError("Spawning thread pool in single-threaded mode");
            }

            if (has_remaining) {
                // At least one thread for remaining group
                if (self.data.len <= static_len) return error.InvalidThreadCount;
            } else {
                if (self.data.len != static_len) return error.InvalidThreadCount;
            }
            if (self.loadState(.acquire) != .init) return error.AlreadyRunning;

            assert(self.data.spawned == 0);
            self.pool_state.barrier = .init(self.data.len);
            errdefer self.deinit();

            const items = self.threads();
            var g_start: u32 = 0;
            inline for (groups, 0..) |config, gn| {
                const len: u32 = switch (config.len) {
                    .remaining => @intCast(items.len - static_len),
                    else => @intFromEnum(config.len),
                };
                self.group_states[gn].barrier = .init(len);
                log.info("spawning thread group {} with size {}", .{ gn, len });
                for (0..len) |n| {
                    const idx = g_start + @as(u32, @intCast(n));
                    items[idx] = try std.Thread.spawn(
                        .{ .allocator = allocators.gpa() },
                        handlerWrapper(config, handlers[gn], gn),
                        .{ self, zengine, idx, idx - g_start, len, ctx[gn] },
                    );
                    self.data.spawned = idx + 1;
                }
                g_start += len;
            }

            self.setState(.running, .release);
        }

        /// Waits for the thread pool to finish.
        /// It is safe to call run again after this function returns.
        pub fn join(self: *Self) void {
            for (self.threads()[0..self.data.spawned]) |thread| thread.join();
            self.data.spawned = 0;
            self.setState(.init, .monotonic);
        }

        /// Send the stopping signal, allowing the other threads to end after their handlers finish.
        /// This function is thread-safe.
        pub fn sendQuit(self: *Self) void {
            self.setState(.stopping, .release);
        }

        fn threads(self: *Self) []std.Thread {
            comptime assert(@sizeOf(std.Thread) == @sizeOf(@TypeOf(self.data.items[0])));
            comptime assert(@alignOf(std.Thread) == @alignOf(@TypeOf(self.data.items[0])));
            const items: []std.Thread = @ptrCast(@alignCast(&self.data.items));
            return items[0..self.data.len];
        }

        fn loadState(self: *const Self, comptime order: std.builtin.AtomicOrder) State {
            return @atomicLoad(State, &self.data.state, order);
        }

        fn setState(self: *Self, value: State, comptime order: std.builtin.AtomicOrder) void {
            @atomicStore(State, &self.data.state, value, order);
        }

        fn handlerWrapper(
            comptime config: GroupConfig,
            comptime handler: config.handlerFn(),
            comptime group_n: comptime_int,
        ) fn (
            self: *Self,
            zengine: *Zengine,
            thread_idx: u32,
            group_idx: u32,
            group_len: u32,
            ctx: config.ctx,
        ) anyerror!void {
            const Impl = struct {
                fn impl(
                    self: *Self,
                    zengine: *Zengine,
                    thread_idx: u32,
                    group_idx: u32,
                    group_len: u32,
                    ctx: config.ctx,
                ) anyerror!void {
                    var started_at: u64 = std.math.maxInt(u64);
                    defer log.debug(
                        "thread {} stopped: {f}",
                        .{
                            thread_idx,
                            std.Io.Duration.fromNanoseconds(time.getNano() -| started_at),
                        },
                    );
                    try platform.setPriority(config.priority);

                    while (true) switch (self.loadState(.acquire)) {
                        .init => std.Thread.yield() catch @panic("Failed yielding thread"),
                        .running => break,
                        .stopping => return,
                    };

                    log.debug("thread {} running", .{thread_idx});
                    started_at = time.getNano();
                    defer _ = self.loadState(.acquire);

                    const info: ThreadInfo = .init(
                        thread_idx,
                        self.data.len,
                        group_idx,
                        group_len,
                        &self.group_states[group_n].barrier,
                        &self.group_states[group_n].buffer,
                    );
                    while (true) {
                        if (config.len != .one) {
                            var state: State = undefined;
                            if (info.isPrimary()) state = self.loadState(.monotonic);
                            info.broadcastValue(State, &state, .primary);
                            if (state != .running) return;
                        } else if (self.loadState(.monotonic) != .running) return;
                        if (!try handler(
                            zengine,
                            &info,
                            &self.pool_state,
                            ctx,
                        )) self.sendQuit();
                    }
                }
            };
            return Impl.impl;
        }
    };
}
