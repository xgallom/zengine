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
        component_flags: FlagsBitSet,

        pub const Self = @This();
        pub const ArrayList = AL;

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            var self = Self{
                .components = try ArrayList.init(allocator, capacity, 0),
                .component_flags = try FlagsBitSet.initEmpty(allocator, capacity),
            };
            self.remove(try self.push(undefined));
            return self;
        }

        pub fn deinit(self: *Self) void {
            defer self.components.deinit();
            defer self.component_flags.deinit(self.components.allocator);
        }

        pub fn push(self: *Self, value: C) !Entity {
            const entity = try self.components.push(value);

            if (self.component_flags.capacity() < self.components.len()) {
                try self.component_flags.resize(self.components.allocator, self.components.cap(), false);
            }
            self.component_flags.set(entity);

            return entity;
        }

        pub fn remove(self: *Self, entity: Entity) void {
            self.component_flags.unset(entity);
        }

        pub fn iter(self: *const Self) Iterator {
            return .{
                .self = self,
                .idx = 0,
            };
        }

        pub const Iterator = struct {
            self: *const Self,
            idx: Entity,

            pub fn next(i: *Iterator) ?struct { entity: Entity, item: C } {
                while (true) : (i.idx += 1) {
                    if (i.idx >= i.self.components.len()) return null;
                    if (i.self.component_flags.isSet(i.idx)) break;
                }
                const idx = i.idx;
                i.idx += 1;
                const result = i.self.components.get(idx);
                return .{
                    .entity = idx,
                    .item = result,
                };
            }
        };
    };
}

pub fn ComponentManager(comptime C: type) type {
    return AnyComponentManager(C, ComponentArrayList(C));
}

pub fn PrimitiveComponentManager(comptime C: type) type {
    return AnyComponentManager(C, PrimitiveComponentArrayList(C));
}
