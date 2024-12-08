const std = @import("std");
const sdl = @import("../ext/sdl.zig");

pub const SDLAllocator = struct {
    buffer_list: BufferList,

    const Self = @This();
    const BufferList = std.SinglyLinkedList([]u8);
    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .free = free,
    };

    pub fn init() Self {
        return .{
            .buffer_list = .{},
        };
    }

    pub fn deinit() std.heap.Check {
        // TODO: Implement
        return .leak;
    }

    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &vtable,
        };
    }

    fn insert_buffer(self: *Self, buf: []u8) !void {
        const node_ptr = Self.aligned_alloc(@sizeOf(BufferList.Node), @alignOf(BufferList.Node));
        if (node_ptr) |ptr| {
            const node: *BufferList.Node = @ptrCast(@alignCast(ptr));
            node.data = buf;
            self.buffer_list.prepend(node);
        } else {
            return std.mem.Allocator.Error.OutOfMemory;
        }
    }

    fn aligned_alloc(size: usize, alignment: usize) ?[*]u8 {
        const ptr = sdl.SDL_aligned_alloc(alignment, size);
        return @ptrCast(@alignCast(ptr));
    }

    fn aligned_free(ptr: [*]u8) void {
        sdl.SDL_aligned_free(@ptrCast(@alignCast(ptr)));
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = &self;
        const alignment = @as(usize, 1) << @as(std.mem.Allocator.Log2Align, @intCast(ptr_align));
        return Self.aligned_alloc(len, alignment);
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = ret_addr;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = &self;

        // TODO: Implement
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        _ = ret_addr;
        _ = buf;
        _ = buf_align;
        const self: *Self = @ptrCast(@alignCast(ctx));
        _ = &self;

        // TODO: Implement
    }
};
