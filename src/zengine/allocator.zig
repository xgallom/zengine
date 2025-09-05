const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

const sdl = @import("ext.zig").sdl;

const RawSDLAllocator = struct {
    const vtable = Allocator.VTable{
        .alloc = alloc,
        .resize = Allocator.noResize,
        .remap = Allocator.noRemap,
        .free = free,
    };

    fn alloc(_: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        return alignedAlloc(len, alignment.toByteUnits());
    }

    fn free(_: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
        _ = alignment;
        _ = ret_addr;
        alignedFree(memory.ptr);
    }

    fn alignedAlloc(size: usize, alignment: usize) ?[*]u8 {
        const ptr = sdl.SDL_aligned_alloc(alignment, size);
        return @ptrCast(@alignCast(ptr));
    }

    fn alignedFree(ptr: [*]u8) void {
        sdl.SDL_aligned_free(@ptrCast(ptr));
    }
};

pub const raw_sdl_allocator: Allocator = .{
    .ptr = undefined,
    .vtable = &RawSDLAllocator.vtable,
};

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

        const vtable = Allocator.VTable{
            .alloc = alloc,
            .resize = resize,
            .remap = remap,
            .free = free,
        };

        const Self = @This();

        pub fn allocator(self: *Self) Allocator {
            return if (comptime enabled and std.log.logEnabled(message_level, scope)) .{
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
            logFn("alloc[{}]@{} {}", .{ len, alignment, result != null });
            return result;
        }

        fn resize(ptr: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
            const self: *Self = @ptrCast(@alignCast(ptr));
            const result = self.backing_allocator.rawResize(memory, alignment, new_len, ret_addr);
            logFn("resize {X}[{} -> {}]@{} {}", .{ @intFromPtr(memory.ptr), memory.len, new_len, alignment, result });
            return result;
        }

        fn remap(ptr: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(ptr));
            const result = self.backing_allocator.rawRemap(memory, alignment, new_len, ret_addr);
            logFn("remap {X}[{} -> {}]@{} {}", .{ @intFromPtr(memory.ptr), memory.len, new_len, alignment, result != null });
            return result;
        }

        fn free(ptr: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            self.backing_allocator.rawFree(memory, alignment, ret_addr);
            logFn("free {X}[{}]@{}", .{ @intFromPtr(memory.ptr), memory.len, alignment });
        }
    };
}
