const std = @import("std");

const types = @import("types.zig");
const ComponentFlagsBitSet = types.ComponentFlagsBitSet;
const ComponentFlag = types.ComponentFlag;
const Entity = types.Entity;

pub const ComponentFlagsArrayListUnmanaged = struct {
    flags: ArrayList = .{},

    pub const Self = @This();
    pub const ArrayList = std.ArrayListUnmanaged(ComponentFlagsBitSet);

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
        return .{
            .flags = try ArrayList.initCapacity(allocator, capacity),
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        defer self.flags.deinit(allocator);
    }

    pub fn push(self: *Self, allocator: std.mem.Allocator, entity: Entity, component_flag: ComponentFlag) !void {
        if (self.flags.items.len > entity) {} else {
            self.flags.ensureTotalCapacity(allocator, entity);
            const empty_flags = ComponentFlagsBitSet.initEmpty();
            for (self.flags.items.len..entity) |n| {
                self.flags.insertAssumeCapacity(n, empty_flags);
            }
        }

        self.flags.items[entity].set(component_flag);
    }

    pub fn remove(self: *Self, entity: Entity, component_flag: ComponentFlag) void {
        self.flags.items[entity].unset(component_flag);
    }

    pub fn remove_entity(self: *Self, entity: Entity) void {
        self.flags.items[entity] = ComponentFlagsBitSet.initEmpty();
    }
};
