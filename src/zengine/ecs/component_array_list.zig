const std = @import("std");
const assert = std.debug.assert;

const types = @import("types.zig");
const ComponentFlag = types.ComponentFlag;
const Entity = types.Entity;

pub fn ComponentArrayList(comptime C: type) type {
    return struct {
        allocator: std.mem.Allocator = undefined,
        components: ArrayList = .{},
        component_flag: ComponentFlag = 0,

        pub const Self = @This();
        pub const Item = C;
        pub const ArrayList = std.MultiArrayList(C);

        pub fn init(allocator: std.mem.Allocator, capacity: usize, component_flag: ComponentFlag) !Self {
            var self = Self{
                .allocator = allocator,
                .component_flag = component_flag,
            };
            try self.components.ensureTotalCapacity(allocator, capacity);
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.components.deinit(self.allocator);
        }

        pub fn push(self: *Self, value: C) !Entity {
            const entity = try self.components.addOne(self.allocator);
            self.components.set(entity, value);
            return @intCast(entity);
        }

        pub fn set(self: *Self, entity: Entity, value: C) void {
            assert(entity < self.len());
            self.components.set(entity, value);
        }

        pub fn get(self: *const Self, entity: Entity) C {
            assert(entity < self.len());
            return self.components.get(entity);
        }

        pub fn len(self: *const Self) usize {
            return self.components.len;
        }

        pub fn cap(self: *const Self) usize {
            return self.components.capacity;
        }
    };
}

pub fn PrimitiveComponentArrayList(comptime C: type) type {
    return struct {
        allocator: std.mem.Allocator = undefined,
        components: ArrayList = .{},
        component_flag: ComponentFlag = 0,

        pub const Self = @This();
        pub const Item = C;
        pub const ArrayList = std.ArrayListUnmanaged(C);

        pub fn init(allocator: std.mem.Allocator, capacity: usize, component_flag: ComponentFlag) !Self {
            var self = Self{
                .allocator = allocator,
                .component_flag = component_flag,
            };
            try self.components.ensureTotalCapacity(allocator, capacity);
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.components.deinit(self.allocator);
        }

        pub fn push(self: *Self, value: C) !Entity {
            const ptr = try self.components.addOne(self.allocator);
            ptr.* = value;
            return self.len() - 1;
        }

        pub fn set(self: *Self, entity: Entity, value: C) void {
            assert(entity < self.len());
            self.components.items[entity] = value;
        }

        pub fn get(self: *const Self, entity: Entity) C {
            assert(entity < self.len());
            return self.components.items[entity];
        }

        pub fn len(self: *const Self) usize {
            return self.components.items.len;
        }

        pub fn cap(self: *const Self) usize {
            return self.components.capacity;
        }
    };
}
