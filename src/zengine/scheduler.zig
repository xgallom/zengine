const std = @import("std");

pub const Task = struct {
    ptr: *anyopaque,
    invoke: *const fn(ptr: *anyopaque) void,
};

pub const TaskArrayList = struct {
    tasks: ArrayList,

    const Self = @This();
    const ArrayList = std.ArrayList(Task);

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
        return .{
            .tasks = ArrayList.initCapacity(allocator, capacity),
        };
    }
};
