//!
//! The zengine key tree implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const zcore = @import("zcore");
const sched = zcore.sched;

const math = @import("../math.zig");

const log = std.log.scoped(.swapper);

pub fn SwapWrapper(comptime T: type, comptime options: struct {
    len: usize = 2,
    copy_on_advance: bool = false,
    deinit_method: []const u8 = "deinit",
}) type {
    comptime assert(options.len > 1);
    return struct {
        items: [options.len]T = undefined,
        idx: usize = 0,

        pub const Self = @This();
        const mask = math.IntMask(options.len);

        pub fn initFill(value: T) Self {
            var result = Self{};
            if (comptime options.copy_on_advance) {
                result.items[0] = value;
            } else result.items = @splat(value);
            return result;
        }

        pub fn initCall(comptime initFn: anytype) InitCallResult(Self, initFn) {
            var result = Self{};
            if (comptime options.copy_on_advance) {
                if (comptime returnsError(initFn)) {
                    result.items[0] = try initFn();
                } else result.items[0] = initFn();
            } else {
                if (comptime returnsError(initFn)) {
                    for (0..options.len) |n| result.items[n] = try initFn();
                } else for (0..options.len) |n| result.items[n] = initFn();
            }
            return result;
        }

        pub fn deinit(self: *Self, args: anytype) void {
            if (comptime @hasDecl(T, options.deinit_method)) {
                for (0..self.items.len) |n| @call(
                    .auto,
                    @field(T, options.deinit_method),
                    .{&self.items[n]} ++ args,
                );
            }
        }

        pub fn getPtr(self: *Self) *T {
            return &self.items[self.idx];
        }

        pub fn getPrevPtr(self: *Self) *T {
            return &self.items[mask.offset(self.idx -% 1)];
        }

        pub fn advance(self: *Self) *T {
            const next_idx = mask.offset(self.idx +% 1);
            if (comptime options.copy_on_advance) self.items[next_idx] = self.items[self.idx];
            self.idx = next_idx;
            return self.getPtr();
        }

        /// Swap wrapper synchronized with a spinlock.
        pub const ThreadSafe = struct {
            lock: sched.Spinlock = .init,
            inner: Self = .{},

            /// Function is not thread-safe.
            pub fn initFill(value: T) @This() {
                return .{ .inner = .initFill(value) };
            }

            /// Function is not thread-safe.
            pub fn initCall(comptime initFn: anytype) InitCallResult(@This(), initFn) {
                return .{
                    .inner = if (comptime returnsError(initFn))
                        try .initCall(initFn)
                    else
                        .initCall(initFn),
                };
            }

            /// Function is not thread-safe.
            pub fn deinit(self: *@This(), args: anytype) void {
                self.inner.deinit(args);
            }

            pub fn get(self: *@This()) T {
                self.lock.lock(.spinloop);
                defer self.lock.unlock();
                return self.inner.getPtr().*;
            }

            pub fn getPrev(self: *@This()) T {
                self.lock.lock(.spinloop);
                defer self.lock.unlock();
                return self.inner.getPrevPtr().*;
            }

            pub fn advance(self: *Self) T {
                self.lock.lock(.spinloop);
                defer self.lock.unlock();
                return self.inner.advance().*;
            }
        };
    };
}

fn InitCallResult(comptime Self: type, comptime initFn: anytype) type {
    return if (returnsError(initFn)) ErrorSet(initFn)!Self else Self;
}

fn returnsError(comptime initFn: anytype) bool {
    if (@typeInfo(@TypeOf(initFn)) != .@"fn") @compileError("initFn must be a function");
    const type_info = @typeInfo(@TypeOf(initFn)).@"fn";
    return @typeInfo(type_info.return_type orelse void) == .error_union;
}

fn ErrorSet(comptime initFn: anytype) type {
    if (@typeInfo(@TypeOf(initFn)) != .@"fn") @compileError("initFn must be a function");
    const type_info = @typeInfo(@TypeOf(initFn)).@"fn";
    if (@typeInfo(type_info.return_type orelse void) != .error_union) {
        @compileError("initFn must return an error union");
    }
    return @typeInfo(type_info.return_type.?).error_union.error_set;
}
