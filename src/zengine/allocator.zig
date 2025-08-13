const std = @import("std");
const sdl = @import("ext/sdl.zig");

const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

fn alignedAlloc(size: usize, alignment: usize) ?[*]u8 {
    const ptr = sdl.SDL_aligned_alloc(alignment, size);
    return @ptrCast(@alignCast(ptr));
}

fn alignedFree(ptr: [*]u8) void {
    sdl.SDL_aligned_free(@ptrCast(@alignCast(ptr)));
}

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
};

pub const raw_sdl_allocator: Allocator = .{
    .ptr = undefined,
    .vtable = &RawSDLAllocator.vtable,
};

// pub const SDLAllocator = struct {
//     buffer_allocator: std.heap.ArenaAllocator,
//     buffer_list: BufferList,
//
//     const Self = @This();
//     const BufferList = std.SinglyLinkedList([]u8);
//     const vtable = Allocator.VTable{
//         .alloc = alloc,
//         .resize = resize,
//         .remap = remap,
//         .free = free,
//     };
//
//     pub fn init() Self {
//         .{
//             .buffer_allocator = std.heap.ArenaAllocator.init(raw_sdl_allocator),
//             .buffer_list = .{},
//         };
//     }
//
//     pub fn deinit() std.heap.Check {
//         // TODO: Implement
//         return .leak;
//     }
//
//     pub fn allocator(self: *Self) Allocator {
//         return .{
//             .ptr = self,
//             .vtable = &vtable,
//         };
//     }
//
//     fn insertBuffer(self: *Self, buf: []u8) !void {
//         const node_ptr = alignedAlloc(@sizeOf(BufferList.Node), @alignOf(BufferList.Node));
//         if (node_ptr) |ptr| {
//             const node: *BufferList.Node = @ptrCast(@alignCast(ptr));
//             node.data = buf;
//             self.buffer_list.prepend(node);
//         } else {
//             return Allocator.Error.OutOfMemory;
//         }
//     }
//
//     fn removeBuffer(self: *Self, buf: []u8) !void {
//         var node = &self.buffer_list.first;
//         while (node.* != null) : (node = &node.*.?.next) {
//             if (node.*.?.data.ptr == buf.ptr) {
//                 node.* = node.*.?.next;
//                 return;
//             }
//         }
//         return error.NotFound;
//     }
//
//     fn alloc(ctx: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
//         const self: *Self = @ptrCast(@alignCast(ctx));
//         return alignedAlloc(len, alignment.toByteUnits());
//     }
//
//     fn resize(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
//         const self: *Self = @ptrCast(@alignCast(ctx));
//         _ = &self;
//
//         return false;
//     }
//
//     fn remap(ctx: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {}
//
//     fn free(ctx: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
//         _ = ret_addr;
//         const self: *Self = @ptrCast(@alignCast(ctx));
//         _ = &self;
//
//         alignedFree(buf.ptr);
//     }
// };
