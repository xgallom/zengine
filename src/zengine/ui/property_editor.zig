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

pub const InputTypeEnum = union(enum) {
    checkbox: void,
    text: void,
    combo: void,
    scalar: Scalar,

    pub const Scalar = enum {
        drag,
        slider,
    };
};

pub const InputType = struct {
    pub const checkbox: InputTypeEnum = .checkbox;
    pub const text: InputTypeEnum = .text;
    pub const combo: InputTypeEnum = .combo;
    pub const drag: InputTypeEnum = .{ .scalar = .drag };
    pub const slider: InputTypeEnum = .{ .scalar = .slider };
};

pub const Options = struct {
    pub const InputCheckbox = struct {
        name: [:0]const u8,
    };

    pub const InputText = struct {
        name: [:0]const u8,
        len: ?usize = null,
    };

    pub const InputCombo = struct {
        name: [:0]const u8,
    };

    pub fn InputScalar(comptime C: type) type {
        return struct {
            name: [:0]const u8,
            min: ?C = null,
            max: ?C = null,
            speed: ?f32 = null,
            input_type: ?InputTypeEnum.Scalar = null,
        };
    }
};

pub fn InputCheckbox(comptime options: Options.InputCheckbox) type {
    const C = bool;
    return struct {
        component: *C,

        pub const Self = @This();
        pub const name = options.name;

        pub fn init(component: *C) Self {
            return .{ .component = component };
        }

        pub fn draw(self: *const Self, ui: *const UI, is_open: *bool) void {
            drawImpl(self.component, ui, is_open);
        }

        pub fn drawImpl(component: *C, _: *const UI, _: *bool) void {
            c.igTableNextRow(0, 0);
            c.igPushID_Str(name);

            _ = c.igTableNextColumn();
            c.igAlignTextToFramePadding();
            c.igTextUnformatted(name, null);

            _ = c.igTableNextColumn();
            _ = c.igCheckbox("##" ++ name, component);

            c.igPopID();
        }

        pub fn element(self: *const Self) UI.Element {
            return .{
                .ptr = @ptrCast(self.component),
                .drawFn = @ptrCast(&drawImpl),
            };
        }
    };
}

pub fn InputText(comptime options: Options.InputText) type {
    return struct {
        component: []u8,

        pub const Self = @This();
        pub const name = options.name;

        pub fn init(component: []u8) Self {
            return .{ .component = component };
        }

        pub fn draw(self: *const Self, ui: *const UI, is_open: *bool) void {
            drawImpl(self.component, ui, is_open);
        }

        pub fn drawImpl(component: []u8, _: *const UI, _: *bool) void {
            c.igTableNextRow(0, 0);
            c.igPushID_Str(name);

            _ = c.igTableNextColumn();
            c.igAlignTextToFramePadding();
            c.igTextUnformatted(name, null);

            _ = c.igTableNextColumn();
            c.igSetNextItemWidth(-std.math.floatMin(f32));
            _ = c.igInputText("##Editor", component.ptr, component.len, 0, null, null);

            c.igPopID();
        }

        pub fn element(self: *const Self) UI.Element {
            return .{
                .ptr = @ptrCast(self),
                .drawFn = @ptrCast(&draw),
            };
        }
    };
}

pub fn InputCombo(comptime C: type, comptime options: Options.InputCombo) type {
    comptime assert(@typeInfo(C) == .@"enum");
    const type_info = @typeInfo(C).@"enum";

    if (!type_info.is_exhaustive) @compileError("Enum must be exhaustive");
    if (type_info.tag_type != c_int and type_info.tag_type != c_uint) {
        @compileError("Enum tag type must be c_int sized");
    }

    comptime var items: []const [*:0]const u8 = &.{};
    inline for (type_info.fields) |field| items = items ++ [_][*:0]const u8{field.name};

    return struct {
        component: *C,

        pub const Self = @This();
        pub const name = options.name;

        pub fn init(component: *C) Self {
            return .{ .component = component };
        }

        pub fn draw(self: *const Self, ui: *const UI, is_open: *bool) void {
            drawImpl(self.component, ui, is_open);
        }

        pub fn drawImpl(component: *C, _: *const UI, _: *bool) void {
            c.igTableNextRow(0, 0);
            c.igPushID_Str(name);

            _ = c.igTableNextColumn();
            c.igAlignTextToFramePadding();
            c.igTextUnformatted(name, null);

            _ = c.igTableNextColumn();
            c.igSetNextItemWidth(-std.math.floatMin(f32));
            _ = c.igCombo_Str_arr("##" ++ name, @ptrCast(@alignCast(component)), items.ptr, items.len, -1);

            c.igPopID();
        }

        pub fn element(self: *const Self) UI.Element {
            return .{
                .ptr = @ptrCast(self.component),
                .drawFn = @ptrCast(&drawImpl),
            };
        }
    };
}

pub fn InputScalar(comptime C: type, comptime count: usize, comptime options: Options.InputScalar(C)) type {
    const data_type: c.ImGuiDataType, const default_min: C, const default_max: C, const default_speed: f32 = switch (@typeInfo(C)) {
        .int => |type_info| .{
            switch (type_info.signedness) {
                .signed => switch (type_info.bits) {
                    1...8 => c.ImGuiDataType_S8,
                    9...16 => c.ImGuiDataType_S16,
                    17...32 => c.ImGuiDataType_S32,
                    33...64 => c.ImGuiDataType_S64,
                    else => @compileError("Unsupported integer width"),
                },
                .unsigned => switch (type_info.bits) {
                    1...8 => c.ImGuiDataType_U8,
                    9...16 => c.ImGuiDataType_U16,
                    17...32 => c.ImGuiDataType_U32,
                    33...64 => c.ImGuiDataType_U64,
                    else => @compileError("Unsupported integer width"),
                },
            },
            std.math.minInt(C),
            std.math.maxInt(C),
            1,
        },
        .float => |type_info| .{
            switch (type_info.bits) {
                1...32 => c.ImGuiDataType_Float,
                33...64 => c.ImGuiDataType_Double,
                else => @compileError("Unsupported float width"),
            },
            -std.math.inf(C),
            std.math.inf(C),
            0.1,
        },
        else => @compileError("Unsupported scalar property"),
    };

    const CPtr = if (count == 1) *C else [*]C;
    return struct {
        component: CPtr,

        pub const Self = @This();
        pub const name = options.name;
        pub const min: C = options.min orelse default_min;
        pub const max: C = options.max orelse default_max;
        pub const speed: f32 = options.speed orelse default_speed;
        pub const input_type: InputTypeEnum.Scalar = options.input_type orelse .drag;

        pub fn init(component: CPtr) Self {
            return .{ .component = component };
        }

        pub fn draw(self: *const Self, ui: *const UI, is_open: *bool) void {
            drawImpl(self.component, ui, is_open);
        }

        pub fn drawImpl(component: CPtr, _: *const UI, _: *bool) void {
            c.igTableNextRow(0, 0);
            c.igPushID_Str(name);

            _ = c.igTableNextColumn();
            c.igAlignTextToFramePadding();
            c.igTextUnformatted(name, null);

            _ = c.igTableNextColumn();
            c.igSetNextItemWidth(-std.math.floatMin(f32));
            switch (comptime input_type) {
                .drag => _ = c.igDragScalarN("##" ++ name, data_type, component, count, speed, &min, &max, null, 0),
                .slider => _ = c.igSliderScalarN("##" ++ name, data_type, component, count, &min, &max, null, 0),
            }

            c.igPopID();
        }

        pub fn element(self: *const Self) UI.Element {
            return .{
                .ptr = @ptrCast(self.component),
                .drawFn = @ptrCast(&drawImpl),
            };
        }
    };
}

pub fn PropertyEditor(comptime C: type) type {
    comptime assert(@typeInfo(C) == .@"struct");
    const type_info = @typeInfo(C).@"struct";

    return struct {
        component: *C,

        pub const fields = type_info.fields;
        pub const Self = @This();
        pub const Component = C;

        pub fn init(component: *C) Self {
            return .{ .component = component };
        }

        pub fn draw(self: *const Self, ui: *const UI, is_open: *bool) void {
            drawImpl(self.component, ui, is_open);
        }

        pub fn drawImpl(component: *C, ui: *const UI, is_open: *bool) void {
            inline for (fields) |field| {
                const field_min = field.name ++ "_min";
                const field_max = field.name ++ "_max";
                const field_speed = field.name ++ "_speed";
                const field_type = field.name ++ "_type";
                const field_ptr = &@field(component, field.name);

                switch (@typeInfo(field.type)) {
                    .bool => InputCheckbox(.{ .name = field.name }).drawImpl(field_ptr, ui, is_open),
                    .int, .float => InputScalar(field.type, 1, .{
                        .name = field.name,
                        .min = if (@hasDecl(C, field_min)) @field(C, field_min) else null,
                        .max = if (@hasDecl(C, field_max)) @field(C, field_max) else null,
                        .speed = if (@hasDecl(C, field_speed)) @field(C, field_speed) else null,
                        .input_type = if (@hasDecl(C, field_type)) @field(C, field_type) else null,
                    }).drawImpl(field_ptr, ui, is_open),
                    .pointer => |field_info| {
                        if (field_info.is_const) @compileError("Unsupported const pointer");
                        if (field_info.size != .slice) @compileError("Unsupported pointer size");
                        if (field_info.child != u8) @compileError("Only strings supported");

                        const len = if (field_info.sentinel() == 0) field_ptr.len + 1 else field_ptr.len;
                        InputText(.{ .name = field.name }).drawImpl(field_ptr[0..len], ui, is_open);
                    },
                    .array => |field_info| {
                        const input_type = if (@hasDecl(C, field_type))
                            @field(C, field_type)
                        else if (field_info.child == u8)
                            InputType.text
                        else
                            InputType.drag;

                        const len = if (input_type == .text and field_info.sentinel() == 0)
                            field_info.len + 1
                        else
                            field_info.len;

                        switch (comptime input_type) {
                            .text => InputText(.{ .name = field.name }).drawImpl(field_ptr[0..len], ui, is_open),
                            .scalar => |scalar_type| InputScalar(field_info.child, len, .{
                                .name = field.name,
                                .min = if (@hasDecl(C, field_min)) @field(C, field_min) else null,
                                .max = if (@hasDecl(C, field_max)) @field(C, field_max) else null,
                                .speed = if (@hasDecl(C, field_speed)) @field(C, field_speed) else null,
                                .input_type = scalar_type,
                            }).drawImpl(field_ptr, ui, is_open),
                            else => @compileError("Unsupported array type"),
                        }
                    },
                    .@"enum" => InputCombo(field.type, .{ .name = field.name }).drawImpl(field_ptr, ui, is_open),
                    else => @compileError("Unsupported property"),
                }
            }
        }

        pub fn element(self: *const Self) UI.Element {
            return .{
                .ptr = @ptrCast(self.component),
                .drawFn = @ptrCast(&drawImpl),
            };
        }
    };
}
