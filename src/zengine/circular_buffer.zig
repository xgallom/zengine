const std = @import("std");
const assert = std.debug.assert;

pub fn CircularBuffer(comptime T: type, comptime capacity: usize) type {
    comptime assert(@popCount(capacity) == 1); // Only ^2 allowed as capacity
    const capacity_mask: usize = capacity - 1;

    return struct {
        buffer: ArrayList,
        start: usize,
        end: usize,

        const Self = @This();
        const ArrayList = std.ArrayList(T);

        fn mask_inc(index: usize) usize {
            return (index +% 1) & capacity_mask;
        }

        pub const Error = error{ Empty, Full };

        pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!Self {
            var buffer = try ArrayList.initCapacity(allocator, capacity);
            buffer.items.len = capacity;

            return .{
                .start = 0,
                .end = 0,
                .buffer = buffer,
            };
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit();
        }

        pub fn length(self: *const Self) usize {
            return (self.end +% self.buffer.capacity -% self.start) & capacity_mask;
        }

        pub fn push(self: *Self, item: T) !void {
            const next_start = mask_inc(self.start);
            if (next_start == self.end)
                return Error.Full;
            const start = self.start;
            self.start = next_start;
            self.buffer.items[start] = item;
        }

        pub fn pop(self: *Self) T {
            assert(self.start != self.end);

            const start = self.start;
            self.start = mask_inc(self.start);
            return self.buffer.items[start];
        }

        pub fn popOrNull(self: *Self) ?T {
            if (self.start == self.end)
                return null;
            return self.pop();
        }

        pub fn getFirst(self: *const Self) T {
            assert(self.start != self.end);
            return self.buffer.items[self.start];
        }

        pub fn getFirstOrNull(self: *const Self) ?T {
            if (self.start == self.end)
                return null;
            return self.getFirst();
        }
    };
}

pub fn DynamicCircularBuffer(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        buffer: ArrayList,
        start: usize,
        end: usize,

        const Self = @This();
        const ArrayList = std.ArrayListUnmanaged(T);

        fn mask(self: *const Self, value: usize) usize {
            return value & (self.buffer.capacity -% 1);
        }

        fn mask_inc(self: *const Self, index: usize) usize {
            return self.mask(index +% 1);
        }

        pub const Error = error{ Empty, Full };

        pub fn init(allocator: std.mem.Allocator, capacity: usize) std.mem.Allocator.Error!Self {
            assert(@popCount(capacity) == 1); // Only ^2 allowed as capacity
            const arena = std.heap.ArenaAllocator.init(allocator);
            var buffer = try ArrayList.initCapacity(arena.allocator(), capacity);
            buffer.items.len = capacity;

            return .{
                .start = 0,
                .end = 0,
                .buffer = buffer,
            };
        }

        pub fn deinit(self: *Self) void {
            self.allocator.deinit();
        }

        pub fn length(self: *const Self) usize {
            return (self.end +% self.buffer.capacity -% self.start) % self.buffer.capacity;
        }

        pub fn push(self: *Self, item: T) !void {
            const next_start = self.mod_inc(self.start);
            if (next_start == self.end)
                return Error.Full;
            const start = self.start;
            self.start = next_start;
            self.buffer.items[start] = item;
        }

        pub fn pop(self: *Self) T {
            assert(self.start != self.end);

            const start = self.start;
            self.start = self.mod_inc(self.start);
            return self.buffer.items[start];
        }

        pub fn popOrNull(self: *Self) ?T {
            if (self.start == self.end)
                return null;
            return self.pop();
        }

        pub fn getFirst(self: *const Self) T {
            assert(self.start != self.end);
            return self.buffer.items[self.start];
        }

        pub fn getFirstOrNull(self: *const Self) ?T {
            if (self.start == self.end)
                return null;
            return self.getFirst();
        }
    };
}
