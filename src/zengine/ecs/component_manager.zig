const std = @import("std");
const assert = std.debug.assert;

const entity = @import("entity.zig");
const Entity = entity.Entity;

pub fn ComponentArrayList(comptime C: type) type {
    return struct {
        allocator: std.mem.Allocator,
        components: ArrayList,

        pub const Self = @This();
        pub const Item = C;
        pub const ArrayList = std.MultiArrayList(Item);

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            var self = Self{ .allocator = allocator, .components = .{} };
            try self.components.ensureTotalCapacity(allocator, capacity);
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.components.deinit(self.allocator);
        }

        pub fn push(self: *Self, value: C) !u32 {
            const index = try self.components.addOne(self.allocator);
            self.components.set(index, value);
        }
    };
}

pub fn PrimitiveComponentArrayList(comptime C: type) type {
    return struct {
        allocator: std.mem.Allocator,
        components: ArrayList,

        const Self = @This();
        pub const ArrayList = std.ArrayListUnmanaged(C);

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            var self = Self{ .allocator = allocator, .components = .{} };
            try self.components.ensureTotalCapacity(allocator, capacity);
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.components.deinit(self.allocator);
        }
    };
}

pub const OpaqueComponentArrayList = ComponentArrayList(struct {});
pub const OpaquePrimitiveComponentArrayList = PrimitiveComponentArrayList(u64);
pub const FlagsBitSet = std.DynamicBitSetUnmanaged;

pub const ComponentManager = struct {
    allocator: std.mem.Allocator,
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
            .allocator = allocator,
            .components = components,
            .primitive_components = primitive_components,
            .flags = try FlagsBitSet.initEmpty(allocator, 512),
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
        // TODO: Implement
    }

    pub fn register(self: *Self, C: type, component_allocator: std.mem.Allocator, component_capacity: usize) !void {
        const type_info = @typeInfo(C);
        const key = @typeName(C);

        switch (type_info) {
            .Struct, .Union => {
                assert(!self.components.contains(key));

                var item = try ComponentArrayList(C).init(component_allocator, component_capacity);
                const ptr: *OpaqueComponentArrayList = @ptrCast(&item);
                try self.components.put(
                    self.allocator,
                    key,
                    ptr.*,
                );
            },
            else => {
                assert(!self.primitive_components.contains(key));

                var item = try PrimitiveComponentArrayList(C).init(component_allocator, component_capacity);
                const ptr: *OpaquePrimitiveComponentArrayList = @ptrCast(&item);
                try self.primitive_components.put(
                    self.allocator,
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

    pub fn unregister(self: *Self, C: type) void {
        switch (@typeInfo(C)) {
            .Struct, .Union => {
                assert(self.components.contains(@typeName(C)));

                const item = self.getComponentArrayList(C);
                item.components.deinit(item.allocator);
            },
            else => {
                assert(self.primitive_components.contains(@typeName(C)));

                const item = self.getPrimitiveComponentArrayList(C);
                item.components.deinit(item.allocator);
            },
        }
    }
};
