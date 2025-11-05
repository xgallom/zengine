//!
//! The zengine properties implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("allocators.zig");
const ArrayPoolMap = @import("containers.zig").ArrayPoolMap;
const AutoArrayPoolMap = @import("containers.zig").AutoArrayPoolMap;
const c = @import("ext.zig").c;
const math = @import("math.zig");
const str = @import("str.zig");

const log = std.log.scoped(.properties);

pub fn GlobalRegistry(comptime registries: []const type) type {
    comptime var inner_fields: []const std.builtin.Type.StructField = &[_]std.builtin.Type.StructField{};
    for (registries) |Registry| {
        inner_fields = inner_fields ++ &[_]std.builtin.Type.StructField{.{
            .name = @typeName(Registry),
            .type = Registry,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(Registry),
        }};
    }

    return struct {
        inner: InnerType,

        const RA = @This();
        pub const InnerType = @Type(.{ .@"struct" = .{
            .layout = .auto,
            .fields = inner_fields,
            .decls = &.{},
            .is_tuple = false,
        } });

        pub fn init() !RA {
            var ra: RA = undefined;
            inline for (inner_fields) |field| @field(ra.inner, field.name) = try .init();
            return ra;
        }

        pub fn deinit(ra: *RA) void {
            inline for (inner_fields) |field| @field(ra.inner, field.name).deinit();
        }

        pub inline fn properties(ra: *RA, comptime Registry: type, key: Registry.Key) !*Self {
            return @field(ra.inner, @typeName(Registry)).properties(key);
        }
    };
}

pub const RegistryOptions = struct {
    reg_preheat: usize = 1024,
    props_preheat: usize = 32,
};

pub fn AutoRegistry(comptime K: type, comptime options: RegistryOptions) type {
    return struct {
        map: AutoArrayPoolMap(K, Self, .{}),

        const R = @This();
        pub const Key = K;

        pub fn init() !R {
            return .{ .map = try .init(allocators.gpa(), options.reg_preheat) };
        }

        pub fn deinit(reg: *R) void {
            for (reg.map.values()) |props| props.deinit();
            reg.map.deinit();
        }

        pub fn properties(reg: *R, key: K) !*Self {
            const ptr = reg.map.getPtrOrNull(key);
            if (ptr) |p| return p;
            return reg.map.insert(
                key,
                &try .init(allocators.gpa(), options.props_preheat),
            );
        }
    };
}

pub fn StringRegistry(comptime options: RegistryOptions) type {
    return struct {
        map: AutoArrayPoolMap(Self),

        const R = @This();
        pub const Key = []const u8;

        pub fn init() !R {
            return .{ .map = try .init(allocators.gpa(), options.reg_preheat) };
        }

        pub fn deinit(reg: *R) void {
            for (reg.map.values()) |props| props.deinit();
            reg.map.deinit();
        }

        pub fn properties(reg: *R, key: []const u8) !*Self {
            const ptr = reg.map.getPtrOrNull(key);
            if (ptr) |p| return p;
            return reg.map.insert(
                key,
                &try .init(allocators.gpa(), options.props_preheat),
            );
        }
    };
}

u8: ArrayPoolMap(u8, .{}),
u16: ArrayPoolMap(u16, .{}),
u32: ArrayPoolMap(u32, .{}),
u64: ArrayPoolMap(u64, .{}),
i8: ArrayPoolMap(i8, .{}),
i16: ArrayPoolMap(i16, .{}),
i32: ArrayPoolMap(i32, .{}),
i64: ArrayPoolMap(i64, .{}),
f32: ArrayPoolMap(f32, .{}),
f64: ArrayPoolMap(f64, .{}),
string: ArrayPoolMap([:0]u8, .{}),

pub const Self = @This();
pub const Type = enum { u8, u16, u32, u64, i8, i16, i32, i64, f32, f64, string };

fn Representation(comptime prop_type: Type) type {
    return switch (prop_type) {
        .string => [:0]u8,
        inline else => |pt| Value(pt),
    };
}

fn Value(comptime prop_type: Type) type {
    return switch (prop_type) {
        .u8 => u8,
        .u16 => u16,
        .u32 => u32,
        .u64 => u64,
        .i8 => i8,
        .i16 => i16,
        .i32 => i32,
        .i64 => i64,
        .string => []const u8,
    };
}

pub fn init(gpa: std.mem.Allocator, preheat: usize) !Self {
    return .{
        .u8 = try .init(gpa, preheat),
        .u16 = try .init(gpa, preheat),
        .u32 = try .init(gpa, preheat),
        .u64 = try .init(gpa, preheat),
        .i8 = try .init(gpa, preheat),
        .i16 = try .init(gpa, preheat),
        .i32 = try .init(gpa, preheat),
        .i64 = try .init(gpa, preheat),
        .f32 = try .init(gpa, preheat),
        .f64 = try .init(gpa, preheat),
        .string = try .init(gpa, preheat),
    };
}

pub fn deinit(self: *Self) void {
    self.u8.deinit();
    self.u16.deinit();
    self.u32.deinit();
    self.u64.deinit();
    self.i8.deinit();
    self.i16.deinit();
    self.i32.deinit();
    self.i64.deinit();
    self.f32.deinit();
    self.f64.deinit();
    self.string.deinit();
}

pub fn get(self: *Self, comptime prop_type: Type, key: []const u8) Representation(prop_type) {
    return @field(self, @tagName(prop_type)).get(key);
}

pub fn getOrNull(self: *Self, comptime prop_type: Type, key: []const u8) ?Representation(prop_type) {
    return @field(self, @tagName(prop_type)).getOrNull(key);
}

pub fn getPtr(self: *Self, comptime prop_type: Type, key: []const u8) *Representation(prop_type) {
    return @field(self, @tagName(prop_type)).getPtr(key);
}

pub fn getPtrOrNull(self: *Self, comptime prop_type: Type, key: []const u8) ?*Representation(prop_type) {
    return @field(self, @tagName(prop_type)).getPtrOrNull(key);
}

pub fn put(self: *Self, comptime prop_type: Type, key: []const u8, value: Value(prop_type)) !void {
    const val = switch (comptime prop_type) {
        .str => str.dupeZ(value),
        else => value,
    };
    return @field(self, @tagName(prop_type)).put(key, val);
}
