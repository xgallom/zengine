const std = @import("std");
const assert = std.debug.assert;

const entity = @import("entity.zig");
const Entity = entity.Entity;

pub fn ComponentArrayList(comptime C: type) type {
    return struct {
        components: ArrayList,

        const Self = @This();
        pub const ArrayList = std.MultiArrayList(C);

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            var self = Self{ .components = .{} };
            try self.components.ensureTotalCapacity(allocator, capacity);
            return self;
        }

        pub fn push(self: *Self, value: C) u32 {
            if (self.components.len >= self.components.capacity - 1) {
                return 0;
            }

            const index = self.components.addOneAssumeCapacity();
            self.components.set(index, value);
        }
    };
}

pub fn PrimitiveComponentArrayList(comptime C: type) type {
    return struct {
        components: ArrayList,

        const Self = @This();
        pub const ArrayList = std.ArrayListUnmanaged(C);

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            var self = Self{ .components = .{} };
            try self.components.ensureTotalCapacity(allocator, capacity);
            return self;
        }
    };
}

pub const OpaqueComponentArrayList = ComponentArrayList(struct {});
pub const OpaquePrimitiveComponentArrayList = PrimitiveComponentArrayList(u64);
pub const FlagsBitSet = std.bit_set.ArrayBitSet(u32, 512);

pub const ComponentManager = struct {
    components: ComponentsHashMap,
    primitive_components: PrimitiveComponentsHashMap,
    flags: FlagsBitSet,

    const Self = @This();
    const ComponentsHashMap = std.StringArrayHashMapUnmanaged(OpaqueComponentArrayList);
    const PrimitiveComponentsHashMap = std.StringArrayHashMapUnmanaged(OpaquePrimitiveComponentArrayList);

    pub fn init(allocator: std.mem.Allocator) !Self {
        var components = ComponentsHashMap{};
        try components.ensureTotalCapacity(allocator, 512);

        var primitive_components = PrimitiveComponentsHashMap{};
        try primitive_components.ensureTotalCapacity(allocator, 512);

        return .{
            .components = components,
            .primitive_components = primitive_components,
            .flags = FlagsBitSet.initEmpty(),
        };
    }

    pub fn register(self: *Self, C: type, allocator: std.mem.Allocator, component_allocator: std.mem.Allocator, component_capacity: usize) !void {
        const type_info = @typeInfo(C);
        const key = @typeName(C);

        switch (type_info) {
            .Struct, .Union => {
                assert(!self.components.contains(key));

                var item = try ComponentArrayList(C).init(component_allocator, component_capacity);
                const ptr: *OpaqueComponentArrayList = @ptrCast(&item);
                try self.components.put(
                    allocator,
                    key,
                    ptr.*,
                );
            },
            else => {
                assert(!self.primitive_components.contains(key));

                var item = try PrimitiveComponentArrayList(C).init(component_allocator, component_capacity);
                const ptr: *OpaquePrimitiveComponentArrayList = @ptrCast(&item);
                try self.primitive_components.put(
                    allocator,
                    key,
                    ptr.*,
                );
            },
        }
    }

    pub fn getComponentArrayList(self: *const Self, comptime C: type) *ComponentArrayList(C) {
        switch (@typeInfo(C)) {
            .Struct, .Union => {
                const entry = self.components.getEntry(@typeName(C)).?;
                return @ptrCast(entry.value_ptr);
            },
            else => @compileError("Invalid type requested from components"),
        }
    }

    pub fn getPrimitiveComponentArrayList(self: *const Self, comptime C: type) *PrimitiveComponentArrayList(C) {
        switch (@typeInfo(C)) {
            .Struct, .Union => @compileError("Invalid type requested from primitive_components"),
            else => {
                const entry = self.primitive_components.getEntry(@typeName(C)).?;
                return @ptrCast(entry.value_ptr);
            },
        }
    }

    pub fn unregister(self: *Self, C: type, component_allocator: std.mem.Allocator) void {
        switch (@typeInfo(C)) {
            .Struct, .Union => {
                assert(self.components.contains(@typeName(C)));

                const item = self.getComponentArrayList(C);
                item.components.deinit(component_allocator);
            },
            else => {
                assert(self.primitive_components.contains(@typeName(C)));

                const item = self.getPrimitiveComponentArrayList(C);
                item.components.deinit(component_allocator);
            },
        }
    }
};
