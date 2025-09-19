//!
//! The zengine key tree implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const log = std.log.scoped(.swapper);

pub fn SwapWrapper(comptime T: type, comptime options: struct {
    len: usize = 2,
    copy_on_advance: bool = false,
}) type {
    return struct {
        items: [options.len]T = undefined,
        idx: usize = 0,

        pub const uses_mask = @popCount(options.len) == 1;
        pub const Self = @This();

        pub fn initDefault(value: T) Self {
            var result = Self{};
            if (comptime options.copy_on_advance) {
                result.items[0] = value;
            } else {
                for (0..options.len) |n| result.items[n] = value;
            }
            return result;
        }

        pub fn initCall(comptime initFn: anytype) if (returnsError(initFn)) ErrorSet(initFn)!Self else Self {
            comptime assert(!options.copy_on_advance);
            var result = Self{};
            if (comptime returnsError(initFn)) {
                for (0..options.len) |n| result.items[n] = try initFn();
            } else {
                for (0..options.len) |n| result.items[n] = initFn();
            }
            return result;
        }

        pub fn deinit(self: *Self, args: anytype) void {
            if (comptime @hasDecl(T, "deinit")) {
                for (0..self.items.len) |n| @call(.auto, T.deinit, .{&self.items[n]} ++ args);
            }
        }

        pub fn getPtr(self: *Self) *T {
            return &self.items[self.idx];
        }

        pub fn advance(self: *Self) *T {
            const next_idx = switch (comptime uses_mask) {
                true => (self.idx + 1) & (options.len - 1),
                false => (self.idx + 1) % options.len,
            };
            if (comptime options.copy_on_advance) self.items[next_idx] = self.items[self.idx];
            self.idx = next_idx;
        }
    };
}

fn returnsError(comptime initFn: anytype) bool {
    if (@typeInfo(@TypeOf(initFn)) != .@"fn") @compileError("initFn must be a function");
    const type_info = @typeInfo(@TypeOf(initFn)).@"fn";
    return @typeInfo(type_info.return_type orelse void) == .error_union;
}

fn ErrorSet(comptime initFn: anytype) type {
    if (@typeInfo(@TypeOf(initFn)) != .@"fn") @compileError("initFn must be a function");
    const type_info = @typeInfo(@TypeOf(initFn)).@"fn";
    if (@typeInfo(type_info.return_type orelse void) != .error_union) @compileError("initFn must return an error union");
    return @typeInfo(type_info.return_type.?).error_union.error_set;
}
