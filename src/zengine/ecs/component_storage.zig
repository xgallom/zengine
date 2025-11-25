//!
//! The zengine component storage
//!

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Alignment = std.mem.Alignment;

const Id = @import("types.zig").Id;

const log = std.log.scoped(.ecs_component_storage);

pub fn ComponentStorage(comptime C: type) type {
    return struct {
        data: ArrayList = .empty,
        gens: std.ArrayList(Id.Gen) = &.{},
        present: std.DynamicBitSetUnmanaged = .{},
        free: std.ArrayList(Id.Idx) = .empty,

        pub const Self = @This();
        pub const ArrayList = std.ArrayList(C);
        pub const empty: Self = .{};

        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.data.deinit(gpa);
            self.gens.deinit(gpa);
            self.present.deinit(gpa);
            self.free.deinit(gpa);
        }

        pub fn insert(self: *Self, gpa: Allocator, value: C) !Id {
            const id = try self.addOne(gpa);
            self.data.items[id.idx()] = value;
            return id;
        }

        pub fn addOne(self: *Self, gpa: Allocator) !Id {
            if (self.free.pop()) |idx| {
                self.present.set(idx);
                self.gens.items[idx] += 1;
                return .compose(.{ .gen = self.gens.items[idx], .idx = idx });
            } else {
                const idx = self.len();
                try self.data.addOne(gpa);
                if (self.gens.capacity < self.capacity()) {
                    try self.gens.ensureTotalCapacityPrecise(gpa, self.capacity());
                    self.gens.appendNTimesAssumeCapacity(0, self.capacity() - self.gens.items.len);
                }
                if (self.present.capacity() < self.capacity()) self.present.resize(gpa, self.capacity(), false);
                self.present.set(idx);
                return .compose(.{ .gen = 0, .idx = idx });
            }
        }

        pub fn remove(self: *Self, gpa: Allocator, id: Id) !void {
            assert(self.isPresent(id));
            const idx = id.idx();
            self.present.unset(idx);
            try self.free.append(gpa, idx);
        }

        pub fn get(self: *const Self, id: Id) C {
            assert(self.isPresent(id));
            return self.data.items[id.idx()];
        }

        pub fn set(self: *const Self, id: Id, value: C) void {
            assert(self.isPresent(id));
            self.data.items[id.idx()] = value;
        }

        pub fn isPresent(self: *const Self, id: Id) bool {
            const d = id.decompose();
            if (d.idx >= self.data.items.len) return false;
            assert(d.idx < self.present.capacity());
            if (!self.present.isSet(d.idx)) return false;
            assert(d.idx < self.gens.items.len);
            if (d.gen != self.gens.items[d.idx]) return false;
            return true;
        }

        pub inline fn len(self: *const Self) Id.Idx {
            return @intCast(self.data.items.len);
        }

        pub inline fn capacity(self: *const Self) usize {
            return self.data.capacity;
        }
    };
}

pub fn MultiComponentStorage(comptime C: type) type {
    return struct {
        data: ArrayList = .empty,
        gens: std.ArrayList(Id.Gen) = .empty,
        present: std.DynamicBitSetUnmanaged = .{},
        free: std.ArrayList(Id.Idx) = .empty,

        pub const Self = @This();
        pub const ArrayList = std.MultiArrayList(C);
        pub const empty: Self = .{};

        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.data.deinit(gpa);
            self.gens.deinit(gpa);
            self.present.deinit(gpa);
            self.free.deinit(gpa);
        }

        pub fn insert(self: *Self, gpa: Allocator, value: C) !Id {
            const id = try self.addOne(gpa);
            self.data.set(id.idx(), value);
            return id;
        }

        pub fn addOne(self: *Self, gpa: Allocator) !Id {
            if (self.free.pop()) |idx| {
                self.gens.items[idx] += 1;
                self.present.set(idx);
                return .compose(.{ .gen = self.gens.items[idx], .idx = idx });
            } else {
                const idx = self.len();
                _ = try self.data.addOne(gpa);
                log.debug("add one {} {}", .{ idx, self.len() });
                if (self.gens.capacity < self.capacity()) {
                    log.debug("resize gens {} {}", .{ self.gens.capacity, self.capacity() });
                    log.debug("lens {} {}", .{ self.gens.items.len, self.len() });
                    try self.gens.ensureTotalCapacityPrecise(gpa, self.capacity());
                    self.gens.appendNTimesAssumeCapacity(0, self.capacity() - self.gens.items.len);
                }
                if (self.present.capacity() < self.capacity()) try self.present.resize(gpa, self.capacity(), false);
                self.present.set(idx);
                return .compose(.{ .gen = self.gens.items[idx], .idx = idx });
            }
        }

        pub fn remove(self: *Self, gpa: Allocator, id: Id) !void {
            assert(self.isPresent(id));
            const idx = id.idx();
            self.present.unset(idx);
            try self.free.append(gpa, idx);
        }

        pub fn get(self: *const Self, id: Id) C {
            assert(self.isPresent(id));
            return self.data.get(id.idx());
        }

        pub fn set(self: *const Self, id: Id, value: C) void {
            assert(self.isPresent(id));
            self.data.set(id.idx(), value);
        }

        pub fn isPresent(self: *const Self, id: Id) bool {
            const d = id.decompose();
            if (d.idx >= self.data.len) return false;
            assert(d.idx < self.present.capacity());
            if (!self.present.isSet(d.idx)) return false;
            assert(d.idx < self.gens.items.len);
            if (d.gen != self.gens.items[d.idx]) return false;
            return true;
        }

        pub inline fn len(self: *const Self) Id.Idx {
            return @intCast(self.data.len);
        }

        pub inline fn capacity(self: *const Self) usize {
            return self.data.capacity;
        }
    };
}
