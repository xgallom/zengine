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
