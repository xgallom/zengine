const std = @import("std");
const assert = std.debug.assert;

const component_array_list = @import("component_array_list.zig");
const ComponentArrayList = component_array_list.ComponentArrayList;
const PrimitiveComponentArrayList = component_array_list.PrimitiveComponentArrayList;

const types = @import("types.zig");
const FlagsBitSet = types.FlagsBitSet;
const ComponentFlagsBitSet = types.ComponentFlagsBitSet;
const ComponentFlag = types.ComponentFlag;
const Entity = types.Entity;

fn AnyComponentManager(comptime C: type, comptime AL: type) type {
    return struct {
        components: ArrayList,
        component_flags: types.FlagsBitSet,

        pub const Self = @This();
        pub const ArrayList = AL;

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            return .{
                .components = try ArrayList.init(allocator, capacity, 0),
                .component_flags = try FlagsBitSet.initEmpty(allocator, capacity),
            };
        }

        pub fn deinit(self: *Self) void {
            defer self.components.deinit();
            defer self.component_flags.deinit(self.components.allocator);
        }

        pub fn push(self: *Self, value: C) !Entity {
            const entity = try self.components.push(value);
            self.component_flags.set(entity);
            return entity;
        }

        pub fn remove(self: *Self, entity: Entity) void {
            self.component_flags.unset(entity);
        }
    };
}

pub fn ComponentManager(comptime C: type) type {
    return AnyComponentManager(C, ComponentArrayList(C));
}

pub fn PrimitiveComponentManager(comptime C: type) type {
    return AnyComponentManager(C, PrimitiveComponentArrayList(C));
}
