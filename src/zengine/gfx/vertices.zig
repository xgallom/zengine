const std = @import("std");
const assert = std.debug.assert;

const math = @import("../math.zig");
const batch = math.batch;

pub const Vertices = struct {
    allocator: std.mem.Allocator,
    items: [dims][*]batch.Batch,
    /// the number of vertices stored, not the same as number of batches
    len: usize,

    const Self = @This();
    const ArrayList = std.ArrayList(batch.Batch);

    const dims = 4;

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .items = .{ &[_]batch.Batch{}, &[_]batch.Batch{}, &[_]batch.Batch{}, &[_]batch.Batch{} },
            .len = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        for (0..dims) |n| {
            var array_list = self.item_array_list(n);
            array_list.deinit();
        }
    }

    pub fn push(self: *Self, vertices: []const math.Vertex) !void {
        const total_len = self.len + vertices.len;
        const capacity = batch.batch.batch_len(total_len);
        for (0..dims) |n| {
            var array_list = self.item_array_list(n);
            try array_list.ensureTotalCapacityPrecise(capacity);
            self.items[n] = array_list.items.ptr;
        }

        for (0..vertices.len) |v| {
            const dest = self.len + v;
            const dest_index = batch.batch.batchIndex(dest);
            const dest_offset = batch.batch.batchOffset(dest);
            for (0..dims) |n| {
                self.items[n][dest_index][dest_offset] = vertices[v][n];
            }
        }

        self.len = total_len;
    }

    pub fn itemArrayList(self: *const Self, index: usize) ArrayList {
        assert(index < dims);
        const real_len = self.batch_len();
        return .{
            .allocator = self.allocator,
            .items = self.items[index][0..real_len],
            .capacity = real_len,
        };
    }

    pub fn batchLen(self: *const Self) usize {
        return batch.batch.batch_len(self.len);
    }

    pub fn toVector(self: *const Self) batch.Vector4 {
        return self.items;
    }

    pub fn iterate(self: *Self) batch.vector4.Iterator {
        return batch.vector4.iterate(&self.items, self.len);
    }
};
