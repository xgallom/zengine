//!
//! The zengine vertices
//!

const std = @import("std");
const assert = std.debug.assert;

const math = @import("../math.zig");
const batch = math.batch;
const dims = math.vector3.len;

allocator: std.mem.Allocator,
items: [math.vector4.len][*]batch.Batch,
/// the number of vertices stored, not the same as number of batches
len: usize,

const Self = @This();
const ArrayList = std.ArrayList(batch.Batch);
pub fn init(allocator: std.mem.Allocator, w: math.Scalar) !Self {
    const none = &[_]batch.Batch{};
    const wp = try allocator.create(batch.Batch);
    wp.* = @splat(w);
    return .{
        .allocator = allocator,
        .items = .{ none, none, none, wp },
        .len = 0,
    };
}

pub fn deinit(self: *Self) void {
    for (0..dims) |n| {
        var array_list = self.itemArrayList(n);
        array_list.deinit(self.allocator);
    }
    self.allocator.free(self.items[3][0..1]);
}

pub fn push(self: *Self, vertices: []const math.Vector3) !void {
    const total_len = self.len + vertices.len;
    const capacity = batch.batch.batchLen(total_len);
    inline for (0..dims) |d| {
        var array_list = self.itemArrayList(d);
        try array_list.ensureTotalCapacityPrecise(self.allocator, capacity);
        self.items[d] = array_list.items.ptr;
    }

    inline for (0..dims) |d| {
        for (0..vertices.len) |v| {
            const dest = self.len + v;
            const dest_index = batch.batch.batchIndex(dest);
            const dest_offset = batch.batch.batchOffset(dest);

            self.items[d][dest_index][dest_offset] = vertices[v][d];
        }
    }

    self.len = total_len;
}

pub fn itemArrayList(self: *const Self, index: usize) ArrayList {
    assert(index < dims);
    const real_len = self.batchLen();
    return .{
        .items = self.items[index][0..real_len],
        .capacity = real_len,
    };
}

pub fn batchLen(self: *const Self) usize {
    return batch.batch.batchLen(self.len);
}

pub fn toVector3(self: *const Self) batch.Vector3 {
    return .{ @ptrCast(self.items[0]), @ptrCast(self.items[1]), @ptrCast(self.items[2]) };
}

pub fn toVector4(self: *const Self) batch.Vector4 {
    return self.items;
}

pub fn iterate3(self: *Self) batch.vector3.Iterator {
    return batch.vector3.iterate(&self.toVector3(), self.len, dims);
}

pub fn iterate4(self: *Self) batch.vector4.Iterator {
    return batch.vector4.iterate(@ptrCast(&self.items), self.len, dims);
}
