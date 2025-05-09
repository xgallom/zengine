const std = @import("std");
const assert = std.debug.assert;

pub const types = @import("ecs/types.zig");
pub usingnamespace types;
const ComponentFlagsBitSet = types.ComponentFlagsBitSet;
const ComponentFlag = types.ComponentFlag;
const Entity = types.Entity;

pub const component_array_list = @import("ecs/component_array_list.zig");
pub usingnamespace component_array_list;
const ComponentArrayList = component_array_list.ComponentArrayList;
const PrimitiveComponentArrayList = component_array_list.PrimitiveComponentArrayList;

pub const component_flags_array_list = @import("ecs/component_flags_array_list.zig");
pub usingnamespace component_flags_array_list;
const ComponentFlagsArrayListUnmanaged = component_flags_array_list.ComponentFlagsArrayListUnmanaged;

pub const component_manager = @import("ecs/component_manager.zig");
pub usingnamespace component_manager;

pub const OpaqueComponentArrayList = ComponentArrayList(struct {});
pub const OpaquePrimitiveComponentArrayList = PrimitiveComponentArrayList(u64);

pub const ComponentsHashMapUnmanaged = std.StringArrayHashMapUnmanaged(OpaqueComponentArrayList);
pub const PrimitiveComponentsHashMapUnmanaged = std.StringArrayHashMapUnmanaged(OpaquePrimitiveComponentArrayList);

pub fn ECS(comptime config: struct {
    enable_components: bool = true,
    enable_primitive_components: bool = false,
}) type {
    return struct {
        allocator: std.mem.Allocator,
        components: if (config.enable_components) ComponentsHashMapUnmanaged else void = undefined,
        primitive_components: if (config.enable_primitive_components) PrimitiveComponentsHashMapUnmanaged else void = undefined,
        flags: if (config.enable_components) ComponentFlagsArrayListUnmanaged else void = undefined,
        primitive_flags: if (config.enable_primitive_components) ComponentFlagsArrayListUnmanaged else void = undefined,
        last_component_flag: ComponentFlag = 0,
        last_primitive_component_flag: ComponentFlag = 0,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) !Self {
            var self = Self{ .allocator = allocator };

            if (config.enable_components) {
                self.flags = try ComponentFlagsArrayListUnmanaged.init(allocator, 512);
                self.components = .{};
                try self.components.ensureTotalCapacity(allocator, 512);
            }

            if (config.enable_primitive_components) {
                self.primitive_flags = try ComponentFlagsArrayListUnmanaged.init(allocator, 512);
                self.primitive_components = .{};
                try self.primitive_components.ensureTotalCapacity(allocator, 512);
            }

            try self.register(ComponentFlagsBitSet, allocator, 512);
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.unregister(ComponentFlagsBitSet);

            if (config.enable_components) {
                self.components.deinit(self.allocator);
                self.flags.deinit(self.allocator);
            }

            if (config.enable_primitive_components) {
                self.primitive_components.deinit(self.allocator);
                self.primitive_flags.deinit(self.allocator);
            }
        }

        pub fn push(self: *Self, value: anytype) !Entity {
            comptime if (!config.enable_components) @compileError("Components are disabled");
            const C = @TypeOf(value);
            const components = self.componentArrayListCast(C);
            const entity = try self.components.push(value, components);
            try self.flags.push(self.allocator, entity, components.component_flag);
            return entity;
        }

        pub fn push_primitive(self: *Self, value: anytype) !Entity {
            comptime if (!config.enable_primitive_components) @compileError("Primitive components are disabled");
            const C = @TypeOf(value);
            const components = self.primitiveComponentArrayListCast(C);
            const entity = try self.primitive_components.push(value, components);
            try self.primitive_flags.push(self.allocator, entity, components.component_flag);
            return entity;
        }

        pub fn register(self: *Self, C: type, component_allocator: std.mem.Allocator, component_capacity: usize) !void {
            comptime if (!config.enable_components) @compileError("Components are disabled");
            const key = @typeName(C);
            assert(!self.components.contains(key));

            self.last_component_flag += 1;
            var item = try ComponentArrayList(C).init(component_allocator, component_capacity, self.last_component_flag);
            const ptr: *OpaqueComponentArrayList = @ptrCast(&item);
            try self.components.put(
                self.allocator,
                key,
                ptr.*,
            );
        }

        pub fn register_primitive(self: *Self, C: type, component_allocator: std.mem.Allocator, component_capacity: usize) !void {
            comptime if (!config.enable_primitive_components) @compileError("Primitive components are disabled");
            const key = @typeName(C);
            assert(!self.primitive_components.contains(key));

            self.last_component_flag += 1;
            var item = try PrimitiveComponentArrayList(C).init(component_allocator, component_capacity, self.last_component_flag);
            const ptr: *OpaquePrimitiveComponentArrayList = @ptrCast(&item);
            try self.primitive_components.put(
                self.allocator,
                key,
                ptr.*,
            );
        }

        pub fn componentArrayListCast(self: *const Self, comptime C: type) *ComponentArrayList(C) {
            comptime if (!config.enable_components) @compileError("Components are disabled");
            assert(self.components.contains(@typeName(C)));

            switch (@typeInfo(C)) {
                .Struct, .Union => {
                    assert(self.components.contains(@typeName(C)));
                    const entry = self.components.getEntry(@typeName(C)).?;
                    return @ptrCast(entry.value_ptr);
                },
                else => @compileError("Invalid type requested from components"),
            }
        }

        pub fn primitiveComponentArrayListCast(self: *const Self, comptime C: type) *PrimitiveComponentArrayList(C) {
            comptime if (!config.enable_primitive_components) @compileError("Primitive components are disabled");
            assert(self.primitive_components.contains(@typeName(C)));

            const entry = self.primitive_components.getEntry(@typeName(C)).?;
            return @ptrCast(entry.value_ptr);
        }

        pub fn unregister(self: *Self, C: type) void {
            comptime if (!config.enable_components) @compileError("Components are disabled");
            assert(self.components.contains(@typeName(C)));

            const item = self.componentArrayListCast(C);
            item.components.deinit(item.allocator);
        }

        pub fn unregister_primitive(self: *Self, C: type) void {
            comptime if (!config.enable_primitive_components) @compileError("Primitive components are disabled");
            assert(self.primitive_components.contains(@typeName(C)));

            const item = self.primitiveComponentArrayListCast(C);
            item.components.deinit(item.allocator);
        }
    };
}
