//!
//! The zengine property editor ui
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const UI = @import("UI.zig");

const log = std.log.scoped(.ui_property_editor);
// pub const sections = perf.sections(@This(), &.{ .init, .draw });

pub fn PropertyEditor(comptime C: type, comptime name: ?[*:0]const u8) type {
    comptime assert(@typeInfo(C) == .@"struct");
    const type_info = @typeInfo(C).@"struct";

    return struct {
        component: *Component,

        pub const component_id = @typeName(C);
        pub const component_name = name orelse component_id;
        pub const fields = type_info.fields;
        pub const Self = @This();
        pub const Component = C;

        pub fn init(component: *Component) Self {
            return .{
                .component = component,
            };
        }

        pub fn draw(component: *Component, _: *const UI, _: *bool) void {
            inline for (fields) |field| {
                c.igTableNextRow(0, 0);
                c.igPushID_Str(field.name);
                _ = c.igTableNextColumn();
                c.igAlignTextToFramePadding();
                c.igTextUnformatted(field.name, null);
                _ = c.igTableNextColumn();
                const field_ptr = &@field(component, field.name);
                switch (@typeInfo(field.type)) {
                    .bool => {
                        _ = c.igCheckbox("##Editor", field_ptr);
                    },
                    .int => |int| {
                        const field_min = field.name ++ "_min";
                        const field_max = field.name ++ "_max";
                        const min: field.type = if (@hasDecl(Component, field_min)) @field(Component, field_min) else std.math.minInt(field.type);
                        const max: field.type = if (@hasDecl(Component, field_max)) @field(Component, field_max) else std.math.maxInt(field.type);
                        const data_type = comptime switch (int.signedness) {
                            .signed => switch (int.bits) {
                                1...8 => c.ImGuiDataType_S8,
                                9...16 => c.ImGuiDataType_S16,
                                17...32 => c.ImGuiDataType_S32,
                                33...64 => c.ImGuiDataType_S64,
                                else => @compileError("Unsupported integer width"),
                            },
                            .unsigned => switch (int.bits) {
                                1...8 => c.ImGuiDataType_U8,
                                9...16 => c.ImGuiDataType_U16,
                                17...32 => c.ImGuiDataType_U32,
                                33...64 => c.ImGuiDataType_U64,
                                else => @compileError("Unsupported integer width"),
                            },
                        };

                        c.igSetNextItemWidth(-std.math.floatMin(f32));
                        _ = c.igDragScalarN("##Editor", data_type, field_ptr, 1, 1, &min, &max, null, 0);
                    },
                    .float => |float| {
                        const field_min = field.name ++ "_min";
                        const field_max = field.name ++ "_max";
                        const min: field.type = if (@hasDecl(Component, field_min)) @field(Component, field_min) else 0.0;
                        const max: field.type = if (@hasDecl(Component, field_max)) @field(Component, field_max) else 1.0;
                        const speed: f32 = if (@hasDecl(Component, field.name ++ "_speed")) @field(Component, field.name ++ "_speed") else 0.001;
                        const data_type = comptime switch (float.bits) {
                            1...32 => c.ImGuiDataType_Float,
                            33...64 => c.ImGuiDataType_Double,
                            else => @compileError("Unsupported float width"),
                        };

                        c.igSetNextItemWidth(-std.math.floatMin(f32));
                        // _ = c.igSliderScalarN("##Editor", data_type, field_ptr, 1, &min, &max, null, 0);
                        _ = c.igDragScalarN("##Editor", data_type, field_ptr, 1, speed, &min, &max, null, 0);
                    },
                    .pointer => |pointer| {
                        if (pointer.child != u8) @compileError("Unsupported pointer type");
                        if (pointer.is_const) @compileError("Unsupported const pointer");
                        if (pointer.size != .slice) @compileError("Only slices supported");

                        const len = if (pointer.sentinel() == 0) field_ptr.len + 1 else field_ptr.len;
                        c.igSetNextItemWidth(-std.math.floatMin(f32));
                        _ = c.igInputText("##Editor", field_ptr.ptr, len, 0, null, null);
                    },
                    .array => |array| {
                        if (array.child == u8) {
                            const len = if (array.sentinel() == 0) array.len + 1 else array.len;
                            c.igSetNextItemWidth(-std.math.floatMin(f32));
                            _ = c.igInputText("##Editor", field_ptr, len, 0, null, null);
                        } else {
                            switch (@typeInfo(array.child)) {
                                .int => |int| {
                                    const field_min = field.name ++ "_min";
                                    const field_max = field.name ++ "_max";
                                    const min: field.type = if (@hasDecl(Component, field_min)) @field(Component, field_min) else @splat(std.math.minInt(field.type));
                                    const max: field.type = if (@hasDecl(Component, field_max)) @field(Component, field_max) else @splat(std.math.maxInt(field.type));
                                    const data_type = comptime switch (int.signedness) {
                                        .signed => switch (int.bits) {
                                            1...8 => c.ImGuiDataType_S8,
                                            9...16 => c.ImGuiDataType_S16,
                                            17...32 => c.ImGuiDataType_S32,
                                            33...64 => c.ImGuiDataType_S64,
                                            else => @compileError("Unsupported integer width"),
                                        },
                                        .unsigned => switch (int.bits) {
                                            1...8 => c.ImGuiDataType_U8,
                                            9...16 => c.ImGuiDataType_U16,
                                            17...32 => c.ImGuiDataType_U32,
                                            33...64 => c.ImGuiDataType_U64,
                                            else => @compileError("Unsupported integer width"),
                                        },
                                    };

                                    c.igSetNextItemWidth(-std.math.floatMin(f32));
                                    _ = c.igDragScalarN("##Editor", data_type, field_ptr, array.len, 1, &min, &max, null, 0);
                                },
                                .float => |float| {
                                    const field_min = field.name ++ "_min";
                                    const field_max = field.name ++ "_max";
                                    const min: field.type = if (@hasDecl(Component, field_min)) @field(Component, field_min) else @splat(0.0);
                                    const max: field.type = if (@hasDecl(Component, field_max)) @field(Component, field_max) else @splat(1.0);
                                    const speed: f32 = if (@hasDecl(Component, field.name ++ "_speed")) @field(Component, field.name ++ "_speed") else 0.001;
                                    const data_type = comptime switch (float.bits) {
                                        1...32 => c.ImGuiDataType_Float,
                                        33...64 => c.ImGuiDataType_Double,
                                        else => @compileError("Unsupported float width"),
                                    };

                                    c.igSetNextItemWidth(-std.math.floatMin(f32));
                                    // _ = c.igSliderScalarN("##Editor", data_type, field_ptr, 1, &min, &max, null, 0);
                                    _ = c.igDragScalarN("##Editor", data_type, field_ptr, array.len, speed, &min, &max, null, 0);
                                },
                                else => @compileError("Unsupported array type"),
                            }
                        }
                    },
                    .@"enum" => |enum_info| {
                        if (enum_info.is_exhaustive) {
                            if (enum_info.tag_type != c_int and enum_info.tag_type != c_uint) @compileError("Enum must be c_int sized");
                            comptime var items: []const [*:0]const u8 = &.{};
                            inline for (enum_info.fields) |enum_field| items = items ++ [_][*:0]const u8{enum_field.name};
                            c.igSetNextItemWidth(-std.math.floatMin(f32));
                            _ = c.igCombo_Str_arr("##Editor", @ptrCast(@alignCast(field_ptr)), items.ptr, items.len, -1);
                        } else {
                            @compileError("Enum must be exhaustive");
                        }
                    },
                    else => @compileError("Unsupported property"),
                }

                c.igPopID();
            }
        }

        pub fn element(self: *const Self) UI.Element {
            return .{
                .ptr = @ptrCast(self.component),
                .draw = @ptrCast(&draw),
            };
        }
    };
}
