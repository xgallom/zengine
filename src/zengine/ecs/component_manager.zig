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
const ui_mod = @import("../ui.zig");

const log = std.log.scoped(.ecs_component_manager);

fn AnyComponentManager(comptime C: type, comptime AL: type) type {
    return struct {
        components: ArrayList,
        component_flags: FlagsBitSet,
        lock: std.Thread.Mutex = .{},

        pub const Self = @This();
        pub const ArrayList = AL;

        pub fn init(allocator: std.mem.Allocator, capacity: usize) !Self {
            var self = Self{
                .components = try .init(allocator, capacity, 0),
                .component_flags = try .initEmpty(allocator, capacity),
            };
            self.remove(try self.push(undefined));
            return self;
        }

        pub fn deinit(self: *Self) void {
            defer self.components.deinit();
            defer self.component_flags.deinit(self.components.allocator);
        }

        pub fn getPtr(self: *const Self, entity: Entity) *C {
            assert(self.component_flags.isSet(entity));
            return self.components.getPtr(entity);
        }

        pub fn push(self: *Self, value: C) !Entity {
            self.lock.lock();
            defer self.lock.unlock();

            // std.Thread.sleep(1_000_000_000);
            const cap = @atomicLoad(usize, &self.components.components.capacity, .seq_cst);
            const bit_len = @atomicLoad(usize, &self.component_flags.bit_length, .seq_cst);
            log.debug("before 0x{x} 0x{x} {} {}", .{ std.Thread.getCurrentId(), @intFromPtr(self), cap, bit_len });

            const entity = try self.components.push(value);
            log.debug("after {} {}", .{ self.components.cap(), self.components.len() });

            if (self.component_flags.capacity() < self.components.cap()) {
                log.debug("resize flags {} {}", .{ self.component_flags.capacity(), self.components.cap() });
                try self.component_flags.resize(self.components.allocator, self.components.cap(), false);
            }
            self.component_flags.set(entity);
            log.debug("flags set", .{});

            log.debug("after_flags {} {any}", .{ std.Thread.getCurrentId(), self });
            return entity;
        }

        pub fn remove(self: *Self, entity: Entity) void {
            self.lock.lock();
            defer self.lock.unlock();

            self.component_flags.unset(entity);
        }

        pub fn iterator(self: *Self) Iterator {
            self.lock.lock();
            return .{
                .self = self,
                .idx = 0,
            };
        }

        pub const Iterator = struct {
            self: *Self,
            idx: Entity,

            pub fn deinit(i: *Iterator) void {
                i.self.lock.unlock();
            }

            pub fn next(i: *Iterator) ?struct { entity: Entity, item: *C } {
                while (true) : (i.idx += 1) {
                    if (i.idx >= i.self.components.len()) return null;
                    if (i.self.component_flags.isSet(i.idx)) break;
                }
                const idx = i.idx;
                i.idx += 1;
                const result = i.self.components.getPtr(idx);
                return .{
                    .entity = idx,
                    .item = result,
                };
            }
        };

        pub fn propertyEditorNode(
            self: *Self,
            editor: *ui_mod.PropertyEditorWindow,
            parent: *ui_mod.PropertyEditorWindow.Item,
        ) !*ui_mod.PropertyEditorWindow.Item {
            const root_id = @typeName(C);
            const root_node = try editor.appendChildNode(parent, root_id, @typeName(C));
            var iter = self.iterator();
            var buf: [128]u8 = undefined;
            defer iter.deinit();
            while (iter.next()) |entry| {
                const id = try std.fmt.bufPrintZ(&buf, "{s}#{}", .{ @typeName(C), entry.entity });
                const name = try std.fmt.bufPrintZ(buf[id.len + 1 ..], "{}", .{entry.entity});
                _ = try editor.appendChild(
                    root_node,
                    entry.item.propertyEditor(),
                    id,
                    name,
                );
            }
            return root_node;
        }
    };
}

pub fn ComponentManager(comptime C: type) type {
    return AnyComponentManager(C, ComponentArrayList(C));
}

pub fn PrimitiveComponentManager(comptime C: type) type {
    return AnyComponentManager(C, PrimitiveComponentArrayList(C));
}
