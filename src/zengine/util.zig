//!
//! Zengine utilities implementation
//!

const std = @import("std");

const log = std.log.scoped(.util);

pub fn logStructLayout(comptime T: type) void {
    const type_info = @typeInfo(T);

    if (type_info != .@"struct") {
        @compileError("logStructLayout only accepts struct types, received: " ++ @typeName(T));
    }

    @compileLog(std.fmt.comptimePrint("=== Memory Layout for: {s} ===", .{@typeName(T)}));
    @compileLog(std.fmt.comptimePrint(
        "Total Size: {d} bytes | Alignment: {d} bytes",
        .{ @sizeOf(T), @alignOf(T) },
    ));

    const fields = type_info.@"struct".fields;

    var sorted_fields: [fields.len]std.builtin.Type.StructField = undefined;
    inline for (fields, 0..) |f, n| {
        const offset = @offsetOf(T, f.name);
        var pos: usize = 0;
        inline for (fields, 0..) |g, m| {
            if (n == m) continue;
            const other_offset = @offsetOf(T, g.name);
            if (other_offset < offset) pos += 1;
        }
        sorted_fields[pos] = f;
    }

    var expected_offset: usize = 0;
    inline for (sorted_fields) |field| {
        const actual_offset = @offsetOf(T, field.name); //

        if (actual_offset > expected_offset) {
            const padding_bytes = actual_offset - expected_offset;
            @compileLog(std.fmt.comptimePrint(
                "  [Offset: {d: >2}] <PADDING> ({d} bytes)",
                .{ expected_offset, padding_bytes },
            ));
        }

        @compileLog(std.fmt.comptimePrint(
            "  [Offset: {d: >2}] Field: .{s:<12} Type: {s:<8} (Size: {d}, Align: {d})",
            .{
                actual_offset,
                field.name,
                @typeName(field.type),
                @sizeOf(field.type),
                @alignOf(field.type),
            },
        ));

        expected_offset = actual_offset + @sizeOf(field.type);
    }

    if (expected_offset < @sizeOf(T)) {
        const trailing_padding = @sizeOf(T) - expected_offset;
        @compileLog(std.fmt.comptimePrint(
            "  [Offset: {d: >2}] <TRAILING PADDING> ({d} bytes)",
            .{ expected_offset, trailing_padding },
        ));
    }
}

pub fn sliceFields(comptime fields: []const std.builtin.Type.StructField) struct {
    names: []const []const u8,
    types: []const type,
    attrs: []const std.builtin.Type.StructField.Attributes,
} {
    comptime {
        var field_names: []const [:0]const u8 = &.{};
        var field_types: []const type = &.{};
        var field_attrs: []const std.builtin.Type.StructField.Attributes = &.{};
        for (fields) |field| {
            field_names = field_names ++ &[_][:0]const u8{field.name};
            field_types = field_types ++ &[_]type{field.type};
            field_attrs = field_attrs ++ &[_]std.builtin.Type.StructField.Attributes{.{
                .@"comptime" = field.is_comptime,
                .@"align" = field.alignment,
                .default_value_ptr = field.default_value_ptr,
            }};
        }
        return .{
            .names = field_names,
            .types = field_types,
            .attrs = field_attrs,
        };
    }
}

pub fn sliceEnumFields(
    comptime T: type,
    comptime fields: []const std.builtin.Type.EnumField,
) struct {
    names: []const []const u8,
    values: []const T,
} {
    comptime {
        var field_names: []const [:0]const u8 = &.{};
        var field_values: []const T = &.{};
        for (fields) |field| {
            field_names = field_names ++ &[_][:0]const u8{field.name};
            field_values = field_values ++ &[_]T{field.value};
        }
        return .{
            .names = field_names,
            .values = field_values,
        };
    }
}
