//!
//! SDL allocator module
//!

const std = @import("std");
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

const c = @import("ext.zig").c;

pub const Self = @This();

pub inline fn malloc(size: usize) ?[*]u8 {
    const ptr = c.SDL_malloc(size);
    return @ptrCast(@alignCast(ptr));
}

pub inline fn free(ptr: ?*anyopaque) void {
    c.SDL_free(ptr);
}

pub inline fn alignedAlloc(size: usize, alignment: usize) ?[*]u8 {
    const ptr = c.SDL_aligned_alloc(alignment, size);
    return @ptrCast(@alignCast(ptr));
}

pub inline fn alignedFree(ptr: [*]u8) void {
    c.SDL_aligned_free(@ptrCast(ptr));
}

const RawSDLAllocator = struct {
    const vtable = Allocator.VTable{
        .alloc = rawAlloc,
        .resize = Allocator.noResize,
        .remap = Allocator.noRemap,
        .free = rawFree,
    };

    fn rawAlloc(_: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        return alignedAlloc(len, alignment.toByteUnits());
    }

    fn rawFree(_: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
        _ = alignment;
        _ = ret_addr;
        alignedFree(memory.ptr);
    }
};

pub const raw: Allocator = .{
    .ptr = undefined,
    .vtable = &RawSDLAllocator.vtable,
};
