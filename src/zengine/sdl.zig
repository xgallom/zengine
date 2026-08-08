//!
//! Zengine SDL helper functions
//!

const std = @import("std");
const assert = std.debug.assert;

pub fn sliceFrom(gpa: std.mem.Allocator, items: anytype) ![]SDLTypePtr(@TypeOf(items)) {
    if (items.len == 0) return &.{};
    const result = try gpa.alloc(SDLTypePtr(@TypeOf(items)), items.len);
    if (comptime sdlNeedsAllocatorPtr(@TypeOf(items))) {
        for (result, items) |*to, *from| to.* = try from.toSDL(gpa);
    } else {
        for (result, items) |*to, *from| to.* = from.toSDL();
    }
    return result;
}

pub fn sdlNeedsAllocator(comptime T: type) bool {
    assert(@typeInfo(T) == .@"struct");
    assert(@hasDecl(T, "toSDL"));
    const ToSDL = @TypeOf(T.toSDL);
    assert(@typeInfo(ToSDL) == .@"fn");
    const params_len = @typeInfo(ToSDL).@"fn".params.len;
    assert(params_len <= 2 and params_len > 0);
    return params_len == 2;
}

pub fn sdlNeedsAllocatorPtr(comptime T: type) bool {
    return sdlNeedsAllocator(std.meta.Child(T));
}

pub fn SDLType(comptime T: type) type {
    assert(@typeInfo(T) == .@"struct");
    assert(@hasDecl(T, "toSDL"));
    const ToSDL = @TypeOf(T.toSDL);
    assert(@typeInfo(ToSDL) == .@"fn");
    const ReturnType = @typeInfo(ToSDL).@"fn".return_type.?;
    return if (sdlNeedsAllocator(T)) @typeInfo(ReturnType).error_union.payload else ReturnType;
}

pub fn SDLTypePtr(comptime T: type) type {
    return SDLType(std.meta.Child(T));
}

pub fn Flags(comptime E: type) type {
    assert(@typeInfo(E) == .@"enum");
    const info = @typeInfo(E).@"enum";
    assert(@typeInfo(info.tag_type).int.signedness == .unsigned);
    return struct {
        bits: info.tag_type = 0,

        const Self = @This();

        pub const Key = E;
        pub const len = info.fields.len;

        pub fn init(init_values: std.enums.EnumFieldStruct(E, bool, false)) Self {
            var result: Self = .{};
            inline for (0..len) |n| {
                const key = info.fields[n];
                if (@field(init_values, key.name)) result.bits |= key.value;
            }
            return result;
        }

        pub fn initEmpty() Self {
            return .{};
        }

        const full: Self = initFull();
        pub fn initFull() Self {
            var result: Self = .{};
            inline for (0..len) |n| result.bits |= info.fields[n].value;
        }

        pub fn initMany(keys: []const Key) Self {
            var result = initEmpty();
            for (keys) |key| result.insert(key);
            return result;
        }

        pub fn initOne(key: Key) Self {
            return .{ .bits = @intFromEnum(key) };
        }

        pub fn count(self: Self) usize {
            return @popCount(self.bits);
        }

        pub fn contains(self: Self, key: Key) bool {
            return (self.bits & int(key)) != 0;
        }

        pub fn insert(self: *Self, key: Key) void {
            self.bits |= int(key);
        }

        pub fn remove(self: *Self, key: Key) void {
            self.bits &= ~int(key);
        }

        pub fn setPresent(self: *Self, key: Key, present: bool) void {
            if (present) self.insert(key) else self.remove(key);
        }

        pub fn toggle(self: *Self, key: Key) void {
            self.bits ^= int(key);
        }

        pub fn toggleSet(self: *Self, other: Self) void {
            self.bits ^= other.bits;
        }

        pub fn toggleAll(self: *Self) void {
            self.bits ^= full.bits;
        }

        pub fn setUnion(self: *Self, other: Self) void {
            self.bits |= other.bits;
        }

        pub fn setIntersection(self: *Self, other: Self) void {
            self.bits &= other.bits;
        }

        pub fn eql(self: Self, other: Self) bool {
            return self.bits == other.bits;
        }

        /// Returns true iff all the keys in this set are
        /// in the other set. The other set may have keys
        /// not found in this set.
        pub fn subsetOf(self: Self, other: Self) bool {
            return self.bits & other.bits == self.bits;
        }

        /// Returns true iff this set contains all the keys
        /// in the other set. This set may have keys not
        /// found in the other set.
        pub fn supersetOf(self: Self, other: Self) bool {
            return self.bits & other.bits == other.bits;
        }

        pub fn complement(self: Self) Self {
            return .{ .bits = full.bits & ~self.bits };
        }

        pub fn unionWith(self: Self, other: Self) Self {
            return .{ .bits = self.bits | other.bits };
        }

        pub fn intersectWith(self: Self, other: Self) Self {
            return .{ .bits = self.bits & other.bits };
        }

        pub fn xorWith(self: Self, other: Self) Self {
            return .{ .bits = self.bits ^ other.bits };
        }

        /// Returns a set with keys that are in this set
        /// except for keys in the other set.
        pub fn differenceWith(self: Self, other: Self) Self {
            return .{ .bits = self.bits & ~other.bits };
        }

        pub fn iterator(self: *const Self) Iterator {
            return .{ .self = self };
        }

        pub const Iterator = struct {
            self: *const Self,
            idx: std.math.Log2Int(info.tag_type) = 0,

            pub fn next(i: *Iterator) ?Key {
                while (i.idx < len) : (i.idx += 1) {
                    const key: Key = @enumFromInt(info.fields[i.idx].value);
                    if (i.self.contains(key)) return key;
                }
                return null;
            }
        };

        fn int(key: Key) info.tag_type {
            return @intFromEnum(key);
        }
    };
}
