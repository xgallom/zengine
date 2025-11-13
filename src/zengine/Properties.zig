//!
//! The zengine properties implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("allocators.zig");
const Map = @import("containers.zig").Map;
const AutoArrayPoolMap = @import("containers.zig").AutoArrayPoolMap;
const c = @import("ext.zig").c;
const math = @import("math.zig");
const str = @import("str.zig");

const log = std.log.scoped(.properties);

pub fn registryList(comptime registry_list: []const type) []const type {
    return registry_list;
}

pub fn registryLists(comptime registry_list: []const []const type) []const type {
    var result: []const type = &.{};
    for (registry_list) |registries| result = result ++ registries;
    return result;
}

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

        pub inline fn create(ra: *RA, comptime Registry: type, key: Registry.Key) !*Self {
            return @field(ra.inner, @typeName(Registry)).create(key);
        }

        pub inline fn destroy(ra: *RA, comptime Registry: type, key: Registry.Key) void {
            @field(ra.inner, @typeName(Registry)).destroy(key);
        }

        pub inline fn properties(ra: *RA, comptime Registry: type, key: Registry.Key) ?*Self {
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
        var empty_properties: Self = .{};

        pub fn init() !R {
            return .{ .map = try .init(allocators.gpa(), options.reg_preheat) };
        }

        pub fn deinit(reg: *R) void {
            for (reg.map.values()) |props| props.deinit();
            reg.map.deinit();
        }

        pub fn create(reg: *R, key: K) !*Self {
            return reg.map.insert(
                key,
                &try .init(allocators.gpa(), options.props_preheat),
            );
        }

        pub fn destroy(reg: *R, key: K) void {
            reg.map.getPtr(key).deinit();
            reg.map.remove(key);
        }

        pub fn properties(reg: *R, key: K) ?*Self {
            return reg.map.getPtrOrNull(key);
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

        pub fn create(reg: *R, key: []const u8) !*Self {
            return reg.map.insert(
                key,
                &try .init(allocators.gpa(), options.props_preheat),
            );
        }

        pub fn destroy(reg: *R, key: []const u8) void {
            reg.map.getPtr(key).deinit();
            reg.map.remove(key);
        }

        pub fn properties(reg: *R, key: []const u8) ?*Self {
            return reg.map.getPtr(key);
        }
    };
}

allocator: std.mem.Allocator,
bool: Map(bool),
u8: Map(u8),
u16: Map(u16),
u32: Map(u32),
u64: Map(u64),
i8: Map(i8),
i16: Map(i16),
i32: Map(i32),
i64: Map(i64),
f32: Map(f32),
f64: Map(f64),
string: Map([:0]u8),

pub const Self = @This();
pub const Type = enum { bool, u8, u16, u32, u64, i8, i16, i32, i64, f32, f64, string };

fn Representation(comptime prop_type: Type) type {
    return switch (prop_type) {
        .string => [:0]u8,
        inline else => |pt| Value(pt),
    };
}

fn Value(comptime prop_type: Type) type {
    return switch (prop_type) {
        .bool => bool,
        .u8 => u8,
        .u16 => u16,
        .u32 => u32,
        .u64 => u64,
        .i8 => i8,
        .i16 => i16,
        .i32 => i32,
        .i64 => i64,
        .f32 => f32,
        .f64 => f64,
        .string => []const u8,
    };
}

pub fn init(gpa: std.mem.Allocator, preheat: u32) !Self {
    return .{
        .allocator = gpa,
        .bool = try .init(gpa, preheat),
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
    self.bool.deinit(self.allocator);
    self.u8.deinit(self.allocator);
    self.u16.deinit(self.allocator);
    self.u32.deinit(self.allocator);
    self.u64.deinit(self.allocator);
    self.i8.deinit(self.allocator);
    self.i16.deinit(self.allocator);
    self.i32.deinit(self.allocator);
    self.i64.deinit(self.allocator);
    self.f32.deinit(self.allocator);
    self.f64.deinit(self.allocator);
    self.string.deinit(self.allocator);
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
        .string => try str.dupeZ(value),
        else => value,
    };
    try @field(self, @tagName(prop_type)).put(self.allocator, key, val);
}
