//!
//! LogAllocator module
//!

const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

pub fn LogAllocator(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime enabled: bool,
) type {
    const log = std.log.scoped(scope);
    const logFn = switch (message_level) {
        .debug => log.debug,
        .info => log.info,
        .warn => log.warn,
        .err => log.err,
    };

    return struct {
        backing_allocator: Allocator,
        alloc_callback: ?*const fn (len: usize, alignment: Alignment) void,

        const vtable = Allocator.VTable{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        };

        pub const Self = @This();

        pub fn allocator(self: *Self) Allocator {
            return if (comptime enabled) .{
                .ptr = self,
                .vtable = &.{
                    .alloc = alloc,
                    .resize = resize,
                    .remap = remap,
                    .free = free,
                },
            } else self.backing_allocator;
        }

        fn alloc(ptr: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(ptr));
            const result = self.backing_allocator.rawAlloc(len, alignment, ret_addr);
            if (comptime std.log.logEnabled(message_level, scope)) logFn(
                "alloc[{}]@{} {}",
                .{ len, alignment, result != null },
            );
            if (self.alloc_callback) |cb| cb(len, alignment);
            return result;
        }

        fn resize(ptr: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
            const self: *Self = @ptrCast(@alignCast(ptr));
            const result = self.backing_allocator.rawResize(memory, alignment, new_len, ret_addr);
            if (comptime std.log.logEnabled(message_level, scope)) logFn(
                "resize 0x{x}[{} -> {}]@{} {}",
                .{ @intFromPtr(memory.ptr), memory.len, new_len, alignment, result },
            );
            return result;
        }

        fn remap(ptr: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(ptr));
            const result = self.backing_allocator.rawRemap(memory, alignment, new_len, ret_addr);
            if (comptime std.log.logEnabled(message_level, scope)) logFn(
                "remap 0x{x}[{} -> {}]@{} {}",
                .{ @intFromPtr(memory.ptr), memory.len, new_len, alignment, result != null },
            );
            return result;
        }

        fn free(ptr: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            self.backing_allocator.rawFree(memory, alignment, ret_addr);
            if (comptime std.log.logEnabled(message_level, scope)) logFn(
                "free 0x{x}[{}]@{}",
                .{ @intFromPtr(memory.ptr), memory.len, alignment },
            );
        }
    };
}
