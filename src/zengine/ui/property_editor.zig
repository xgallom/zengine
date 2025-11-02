//!
//! The zengine property editor ui
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const UI = @import("UI.zig");
const cache = @import("cache.zig");
const StdType = std.builtin.Type;

const log = std.log.scoped(.ui_property_editor);
// pub const sections = perf.sections(@This(), &.{ .init, .draw });

pub const PropertyList = []const @TypeOf(.enum_literal);
pub const PropertyListImpl = struct {
    list: PropertyList,

    pub fn init(comptime prop_list: PropertyList) PropertyListImpl {
        return .{ .list = prop_list };
    }

    pub fn contains(comptime self: PropertyListImpl, comptime prop: [:0]const u8) bool {
        comptime {
            for (self.list) |list_prop| {
                if (std.mem.eql(u8, prop, @tagName(list_prop))) return true;
            }
            return false;
        }
    }
};

pub const InputTypeEnum = union(enum) {
    fields: void,
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
    pub const fields: InputTypeEnum = .fields;
    pub const checkbox: InputTypeEnum = .checkbox;
    pub const text: InputTypeEnum = .text;
    pub const combo: InputTypeEnum = .combo;
    pub const scalar: InputTypeEnum = .{ .scalar = .drag };
    pub const drag: InputTypeEnum = .{ .scalar = .drag };
    pub const slider: InputTypeEnum = .{ .scalar = .slider };
};

pub const ScalarSpeedType = enum {
    absolute,
    relative,
};

pub const Options = struct {
    pub const InputNull = struct {
        name: [:0]const u8 = "value",
        show_value: bool = true,
    };

    pub const InputFields = struct {
        name: ?[:0]const u8 = null,
    };

    pub const InputCheckbox = struct {
        name: [:0]const u8 = "value",
    };

    pub const InputText = struct {
        name: [:0]const u8 = "value",
        read_only: bool = false,
    };

    pub const InputCombo = struct {
        name: [:0]const u8 = "value",
    };

    pub fn InputScalar(comptime C: type) type {
        return struct {
            name: [:0]const u8 = "value",
            min: ?C = null,
            max: ?C = null,
            speed: ?f32 = null,
            speed_type: ?ScalarSpeedType = null,
            input_type: ?InputTypeEnum.Scalar = null,
        };
    }
};

pub fn PropertyEditor(comptime C: type) type {
    return InputFields(C, .{});
}

pub fn RefPropertyEditor(comptime C: type, comptime K: type) type {
    comptime assert(@typeInfo(C) == .@"struct");
    const type_info = @typeInfo(C).@"struct";
    const field_resolver = FieldResolver(C);

    const exclude_properties = field_resolver.propertyList("exclude_properties");

    return struct {
        ref: CRef = undefined,

        pub const Self = @This();
        pub const CRef = @Type(.{ .@"struct" = .{
            .layout = .auto,
            .fields = ref_fields,
            .decls = &.{},
            .is_tuple = type_info.is_tuple,
        } });
        pub const fields = type_info.fields;
        pub const ref_fields = refFields(fields);

        var cc: cache.Cache(K) = .empty;

        pub fn init(key: K, ref: CRef) UI.Element {
            const result = cc.getOrPut(Self, key, .{ .ref = ref });
            return result.value.element;
        }

        pub fn register() !void {
            try cc.register();
        }

        pub fn draw(self: *Self, ui: *const UI, is_open: *bool) void {
            fields: inline for (type_info.fields) |field| {
                comptime if (exclude_properties.contains(field.name)) continue :fields;

                const field_ptr = @field(self.ref, field.name);
                const Input = InputField(C, field);
                if (comptime isOptional(field.type)) {
                    if (field_ptr.* == null) {
                        InputNull(.{ .name = field.name }).draw(ui, is_open);
                        return;
                    } else Input.drawFieldImpl(@ptrCast(field_ptr), ui, is_open);
                } else Input.drawFieldImpl(field_ptr, ui, is_open);
            }
        }

        pub fn element(self: *Self) UI.Element {
            return .{
                .ptr = @ptrCast(self),
                .drawFn = @ptrCast(&draw),
            };
        }
    };
}

pub const PropertyEditorNull = struct {
    const Self = @This();

    pub fn draw(ui: *const UI, is_open: *bool) void {
        drawImpl(null, ui, is_open);
    }

    pub fn drawImpl(_: ?*anyopaque, _: *const UI, _: *bool) void {}

    pub fn element() UI.Element {
        return .{
            .ptr = null,
            .drawFn = @ptrCast(&drawImpl),
        };
    }
};

pub fn InputField(comptime C: type, comptime field: StdType.StructField) type {
    comptime assert(@hasField(C, field.name));
    const field_name = field.name ++ "_name";
    const field_input = field.name ++ "_input";
    const field_min = field.name ++ "_min";
    const field_max = field.name ++ "_max";
    const field_speed = field.name ++ "_speed";
    const field_speed_type = field.name ++ "_speed_type";
    const field_type = field.name ++ "_type";
    const field_resolver = FieldResolver(C);

    return struct {
        component: *C,

        pub const Self = @This();
        pub const name = field_resolver.default(field_name, field.name);

        pub fn init(component: *C) Self {
            return .{ .component = component };
        }

        pub fn draw(self: *const Self, ui: *const UI, is_open: *bool) void {
            drawImpl(self.component, ui, is_open);
        }

        pub fn drawImpl(component: *C, ui: *const UI, is_open: *bool) void {
            const field_ptr = &@field(component, field.name);
            if (comptime isOptional(field.type)) {
                if (field_ptr.* == null) {
                    InputNull(.{ .name = name }).draw(ui, is_open);
                } else drawFieldImpl(@ptrCast(field_ptr), ui, is_open);
            } else drawFieldImpl(field_ptr, ui, is_open);
        }

        fn drawFieldImpl(
            field_ptr: *StripOptional(field.type),
            ui: *const UI,
            is_open: *bool,
        ) void {
            if (comptime field_resolver.has(field_input)) {
                const Input = field_resolver.required(field_input);
                Input.init(field_ptr).draw(ui, is_open);
                return;
            } else {
                switch (@typeInfo(StripOptional(field.type))) {
                    .bool => inputBool(field_ptr, ui, is_open),
                    .int, .float => inputIntOrFloat(field.type, field_ptr, ui, is_open),
                    .pointer => |field_info| switch (field_info.size) {
                        .one => switch (@typeInfo(field_info.child)) {
                            .bool => inputBool(field_ptr.*, ui, is_open),
                            .int, .float => inputIntOrFloat(field_info.child, field_ptr.*, ui, is_open),
                            .array => inputArray(field_info.child, field_ptr.*, ui, is_open),
                            .@"struct" => inputStruct(field_info.child, field_ptr.*, ui, is_open),
                            .@"enum" => inputEnum(field_info.child, field_ptr.*, ui, is_open),
                            inline else => {
                                @compileLog(field_info);
                                @compileError("Unsupported pointer property");
                            },
                        },
                        .slice => inputSlice(StripOptional(field.type), field_ptr, ui, is_open),
                        inline else => {
                            @compileLog(field_info);
                            @compileError("Unsupported pointer size");
                        },
                    },
                    .array => inputArray(field.type, field_ptr, ui, is_open),
                    .@"struct" => inputStruct(field.type, field_ptr, ui, is_open),
                    .@"enum" => inputEnum(field.type, field_ptr, ui, is_open),
                    inline else => |field_info| {
                        @compileLog(field_info);
                        @compileError("Unsupported property");
                    },
                }
            }
        }

        pub fn element(self: *const Self) UI.Element {
            return .{
                .ptr = @ptrCast(self.component),
                .drawFn = @ptrCast(&drawImpl),
            };
        }

        fn inputBool(ptr: *bool, ui: *const UI, is_open: *bool) void {
            _ = InputCheckbox(.{ .name = name }).drawImpl(ptr, ui, is_open);
        }

        fn inputIntOrFloat(comptime T: type, ptr: *T, ui: *const UI, is_open: *bool) void {
            _ = InputScalar(T, 1, .{
                .name = name,
                .min = field_resolver.optional(field_min),
                .max = field_resolver.optional(field_max),
                .speed = field_resolver.optional(field_speed),
                .speed_type = field_resolver.optional(field_speed_type),
                .input_type = field_resolver.optional(field_type),
            }).drawImpl(ptr, ui, is_open);
        }

        fn inputSlice(comptime T: type, ptr: *T, ui: *const UI, is_open: *bool) void {
            comptime assert(@typeInfo(T) == .pointer);
            const field_info = @typeInfo(T).pointer;

            comptime {
                assert(field_info.size == .slice);
                if (field_info.child != u8) {
                    @compileLog(field_info);
                    @compileError("Only string slices supported");
                }
                if (field_info.sentinel() != 0) {
                    @compileLog(field_info);
                    @compileError("Only zero-terminated string slices supported");
                }
            }

            _ = InputText(.{
                .name = name,
                .read_only = field_info.is_const,
            }).drawImpl(@constCast(ptr.*), ui, is_open);
        }

        fn inputArray(comptime T: type, ptr: *T, ui: *const UI, is_open: *bool) void {
            comptime assert(@typeInfo(T) == .array);
            const field_info = @typeInfo(T).array;

            const input_type = comptime field_resolver.default(
                field_type,
                if (field_info.child == u8) InputType.text else InputType.scalar,
            );
            if (input_type == .text and field_info.sentinel() != 0) {
                @compileError("Only zero-terminated strings supported");
            }
            const len = field_info.len;

            switch (comptime input_type) {
                .text => _ = InputText(.{ .name = name }).drawImpl(ptr[0..len :0], ui, is_open),
                .scalar => |scalar_type| _ = InputScalar(field_info.child, len, .{
                    .name = name,
                    .min = field_resolver.optional(field_min),
                    .max = field_resolver.optional(field_max),
                    .speed = field_resolver.optional(field_speed),
                    .speed_type = field_resolver.optional(field_speed_type),
                    .input_type = scalar_type,
                }).drawImpl(ptr, ui, is_open),
                else => @compileError("Unsupported array type"),
            }
        }

        fn inputStruct(comptime T: type, ptr: *T, ui: *const UI, is_open: *bool) void {
            InputFields(T, .{ .name = name }).init(ptr).draw(ui, is_open);
        }

        fn inputEnum(comptime T: type, ptr: *T, ui: *const UI, is_open: *bool) void {
            comptime assert(@typeInfo(T) == .@"enum");
            const field_info = @typeInfo(T).@"enum";

            switch (field_info.is_exhaustive) {
                false => _ = InputScalar(field_info.tag_type, 1, .{
                    .name = name,
                    .min = field_resolver.optional(field_min),
                    .max = field_resolver.optional(field_max),
                    .speed = 1,
                    .input_type = .drag,
                }).drawImpl(@ptrCast(ptr), ui, is_open),
                true => InputCombo(field.type, .{ .name = name }).init(ptr).draw(ui, is_open),
            }
        }
    };
}

pub fn InputFields(comptime C: type, comptime options: Options.InputFields) type {
    comptime assert(@typeInfo(C) == .@"struct");
    const type_info = @typeInfo(C).@"struct";
    const field_resolver = FieldResolver(C);

    const exclude_properties = field_resolver.propertyList("exclude_properties");

    return switch (type_info.layout) {
        .auto, .@"extern" => struct {
            component: *C,

            pub const Self = @This();
            pub const name = options.name;
            pub const fields = type_info.fields;

            pub fn init(component: *C) Self {
                return .{ .component = component };
            }

            pub fn draw(self: *const Self, ui: *const UI, is_open: *bool) void {
                drawImpl(self.component, ui, is_open);
            }

            pub fn drawImpl(component: *C, ui: *const UI, is_open: *bool) void {
                if (comptime name != null) {
                    InputNull(.{
                        .name = name.?,
                        .show_value = false,
                    }).draw(ui, is_open);
                }

                fields: inline for (fields) |field| {
                    comptime if (exclude_properties.contains(field.name)) continue :fields;
                    InputField(C, field).drawImpl(component, ui, is_open);
                }
            }

            pub fn element(self: *const Self) UI.Element {
                return .{
                    .ptr = @ptrCast(self.component),
                    .drawFn = @ptrCast(&drawImpl),
                };
            }
        },
        .@"packed" => struct {
            component: *C,
            unpacked: @Type(.{ .@"struct" = .{
                .layout = .auto,
                .fields = unpacked_fields,
                .decls = &.{},
                .is_tuple = type_info.is_tuple,
            } }) = undefined,

            pub const Self = @This();
            pub const name = options.name;
            pub const fields = type_info.fields;
            pub const unpacked_fields = unpackFields(fields);

            pub fn init(component: *C) UI.Element {
                const result = cache.getOrPut(Self, @intFromPtr(component), .{
                    .component = component,
                    .unpacked = undefined,
                });

                fields: inline for (fields) |field| {
                    comptime if (exclude_properties.contains(field.name)) continue :fields;
                    @field(result.value.item.unpacked, field.name) = @field(component, field.name);
                }

                return result.value.element;
            }

            pub fn draw(self: *Self, ui: *const UI, is_open: *bool) void {
                if (comptime name != null) {
                    InputNull(.{
                        .name = name.?,
                        .show_value = false,
                    }).draw(ui, is_open);
                }

                fields: inline for (unpacked_fields) |field| {
                    comptime if (exclude_properties.contains(field.name)) continue :fields;

                    const target_ptr = &@field(self.component, field.name);
                    const field_ptr = &@field(self.unpacked, field.name);
                    // TODO: Value changed
                    const Input = InputField(C, field);
                    if (comptime isOptional(field.type)) {
                        if (field_ptr.* == null) {
                            InputNull(.{ .name = name }).draw(ui, is_open);
                            return;
                        } else Input.drawFieldImpl(@ptrCast(field_ptr), ui, is_open);
                    } else Input.drawFieldImpl(field_ptr, ui, is_open);
                    const value_changed = target_ptr.* != field_ptr.*;
                    if (value_changed) target_ptr.* = field_ptr.*;
                }
            }

            pub fn element(self: *Self) UI.Element {
                return .{
                    .ptr = @ptrCast(self),
                    .drawFn = @ptrCast(&draw),
                };
            }
        },
    };
}

pub fn InputNull(comptime options: Options.InputNull) type {
    return struct {
        pub const Self = @This();
        pub const name = options.name;
        pub const show_value = options.show_value;

        pub fn init() Self {
            return .{};
        }

        pub fn draw(ui: *const UI, is_open: *bool) void {
            drawImpl(null, ui, is_open);
        }

        pub fn drawImpl(_: ?*anyopaque, _: *const UI, _: *bool) void {
            c.igTableNextRow(0, 0);
            c.igPushID_Str(name);

            _ = c.igTableNextColumn();
            c.igAlignTextToFramePadding();
            c.igTextUnformatted(name, null);

            _ = c.igTableNextColumn();
            if (comptime show_value) {
                c.igAlignTextToFramePadding();
                c.igTextUnformatted("null", null);
            }

            c.igPopID();
        }

        pub fn element() UI.Element {
            return .{
                .ptr = null,
                .drawFn = @ptrCast(&drawImpl),
            };
        }
    };
}

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
            _ = drawImpl(self.component, ui, is_open);
        }

        fn drawElement(component: *C, ui: *const UI, is_open: *bool) void {
            _ = drawImpl(component, ui, is_open);
        }

        pub fn drawImpl(component: *C, _: *const UI, _: *bool) bool {
            c.igTableNextRow(0, 0);
            c.igPushID_Str(name);

            _ = c.igTableNextColumn();
            c.igAlignTextToFramePadding();
            c.igTextUnformatted(name, null);

            _ = c.igTableNextColumn();
            const value_changed = c.igCheckbox("##" ++ name, component);

            c.igPopID();
            return value_changed;
        }

        pub fn element(self: *const Self) UI.Element {
            return .{
                .ptr = @ptrCast(self.component),
                .drawFn = @ptrCast(&drawElement),
            };
        }
    };
}

pub fn InputText(comptime options: Options.InputText) type {
    comptime var flags: c.ImGuiInputFlags = 0;
    if (options.read_only) flags |= c.ImGuiInputTextFlags_ReadOnly;
    return struct {
        component: [:0]u8,

        pub const Self = @This();
        pub const name = options.name;

        pub fn init(component: [:0]u8) Self {
            return .{ .component = component };
        }

        pub fn draw(self: *const Self, ui: *const UI, is_open: *bool) void {
            drawImpl(self.component, ui, is_open);
        }

        pub fn drawImpl(component: [:0]u8, _: *const UI, _: *bool) bool {
            c.igTableNextRow(0, 0);
            c.igPushID_Str(name);

            _ = c.igTableNextColumn();
            c.igAlignTextToFramePadding();
            c.igTextUnformatted(name, null);

            _ = c.igTableNextColumn();
            c.igSetNextItemWidth(-std.math.floatMin(f32));
            const value_changed = c.igInputText("##Editor", component.ptr, component.len + 1, flags, null, null);

            c.igPopID();
            return value_changed;
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

    const Items = std.EnumArray(C, [*:0]const u8);
    const Indexer = Items.Indexer;
    const items = blk: {
        var result: Items = .initUndefined();
        for (0..result.values.len) |n| result.values[n] = @tagName(Indexer.keyForIndex(n));
        break :blk result;
    };
    const is_direct = @sizeOf(type_info.tag_type) == @sizeOf(c_int) and
        @alignOf(type_info.tag_type) == @alignOf(c_int) and
        std.enums.directEnumArrayLen(C, std.math.maxInt(usize)) == type_info.fields.len;

    return if (is_direct) struct {
        component: *C,

        pub const Self = @This();
        pub const name = options.name;

        pub fn init(component: *C) Self {
            return .{ .component = component };
        }

        pub fn draw(self: *const Self, ui: *const UI, is_open: *bool) void {
            _ = drawImpl(self.component, ui, is_open);
        }

        fn drawElement(component: *C, ui: *const UI, is_open: *bool) void {
            _ = drawImpl(component, ui, is_open);
        }

        pub fn drawImpl(component: *C, ui: *const UI, is_open: *bool) bool {
            _ = ui;
            _ = is_open;
            c.igTableNextRow(0, 0);
            c.igPushID_Str(name);

            _ = c.igTableNextColumn();
            c.igAlignTextToFramePadding();
            c.igTextUnformatted(name, null);

            _ = c.igTableNextColumn();
            c.igSetNextItemWidth(-std.math.floatMin(f32));
            const value_changed = c.igCombo_Str_arr("##" ++ name, @ptrCast(component), &items.values, items.values.len, -1);

            c.igPopID();

            return value_changed;
        }

        pub fn element(self: *const Self) UI.Element {
            return .{
                .ptr = @ptrCast(self.component),
                .drawFn = @ptrCast(&drawElement),
            };
        }
    } else struct {
        component: *C,
        value: c_int = undefined,

        pub const Self = @This();
        pub const name = options.name;

        pub fn init(component: *C) UI.Element {
            const result = cache.getOrPut(Self, @intFromPtr(component), .{ .component = component });
            if (!result.found_existing or component.* != Indexer.keyForIndex(@intCast(result.value.item.value))) {
                result.value.item.value = @intCast(Indexer.indexOf(component.*));
            }
            return result.value.element;
        }

        pub fn draw(self: *Self, _: *const UI, _: *bool) void {
            c.igTableNextRow(0, 0);
            c.igPushID_Str(name);

            _ = c.igTableNextColumn();
            c.igAlignTextToFramePadding();
            c.igTextUnformatted(name, null);

            _ = c.igTableNextColumn();
            c.igSetNextItemWidth(-std.math.floatMin(f32));
            const value_changed = c.igCombo_Str_arr("##" ++ name, &self.value, &items.values, items.values.len, -1);
            if (value_changed) self.component.* = Indexer.keyForIndex(@intCast(self.value));

            c.igPopID();
        }

        pub fn element(self: *Self) UI.Element {
            return .{
                .ptr = @ptrCast(self),
                .drawFn = @ptrCast(&draw),
            };
        }
    };
}

pub fn InputScalar(comptime C: type, comptime count: usize, comptime options: Options.InputScalar(C)) type {
    const data_type: c.ImGuiDataType, const defaults: struct {
        min: C,
        max: C,
        speed: f32 = 1,
        input_type: InputTypeEnum.Scalar = InputType.scalar.scalar,
    } = switch (@typeInfo(C)) {
        .int => |type_info| .{
            switch (type_info.signedness) {
                .signed => switch (type_info.bits) {
                    1...8 => c.ImGuiDataType_S8,
                    9...16 => c.ImGuiDataType_S16,
                    17...32 => c.ImGuiDataType_S32,
                    33...64 => c.ImGuiDataType_S64,
                    else => @compileError("Unsupported integer width for " ++ options.name),
                },
                .unsigned => switch (type_info.bits) {
                    1...8 => c.ImGuiDataType_U8,
                    9...16 => c.ImGuiDataType_U16,
                    17...32 => c.ImGuiDataType_U32,
                    33...64 => c.ImGuiDataType_U64,
                    else => @compileError("Unsupported integer width for " ++ options.name),
                },
            },
            .{
                .min = std.math.minInt(C),
                .max = std.math.maxInt(C),
            },
        },
        .float => |type_info| .{
            switch (type_info.bits) {
                1...32 => c.ImGuiDataType_Float,
                33...64 => c.ImGuiDataType_Double,
                else => @compileError("Unsupported float width for " ++ options.name),
            },
            .{
                .min = -std.math.inf(C),
                .max = std.math.inf(C),
            },
        },
        else => @compileError("Unsupported scalar property " ++ options.name),
    };

    const CPtr = if (count == 1) *C else [*]C;
    return struct {
        component: CPtr,

        pub const Self = @This();
        pub const name = options.name;
        pub const depth = 0;
        pub const min = options.min orelse defaults.min;
        pub const max = options.max orelse defaults.max;
        pub const speed = options.speed orelse defaults.speed;
        pub const speed_type = options.speed_type orelse ScalarSpeedType.absolute;
        pub const input_type = options.input_type orelse defaults.input_type;

        pub fn init(component: CPtr) Self {
            return .{ .component = component };
        }

        pub fn draw(self: *const Self, ui: *const UI, is_open: *bool) void {
            drawImpl(self.component, ui, is_open);
        }

        fn drawElement(component: CPtr, ui: *const UI, is_open: *bool) void {
            _ = drawImpl(component, ui, is_open);
        }

        pub fn drawImpl(component: CPtr, _: *const UI, _: *bool) bool {
            c.igTableNextRow(0, 0);
            c.igPushID_Str(name);

            _ = c.igTableNextColumn();
            c.igAlignTextToFramePadding();
            c.igTextUnformatted(name, null);

            _ = c.igTableNextColumn();
            c.igSetNextItemWidth(-std.math.floatMin(f32));
            const value_changed = switch (comptime input_type) {
                .drag => blk: {
                    const speed_val = switch (comptime speed_type) {
                        .absolute => speed,
                        .relative => relSpeed(component),
                    };

                    break :blk c.igDragScalarN("##" ++ name, data_type, component, count, speed_val, &min, &max, null, 0);
                },
                .slider => c.igSliderScalarN("##" ++ name, data_type, component, count, &min, &max, null, 0),
            };

            c.igPopID();

            return value_changed;
        }

        pub fn element(self: *const Self) UI.Element {
            return .{
                .ptr = @ptrCast(self.component),
                .drawFn = @ptrCast(&drawElement),
            };
        }

        fn relSpeed(component: *C) f32 {
            var x = @abs(component.*);
            var acc = speed;
            if ((comptime @typeInfo(C) == .float) and x != @floor(x)) {
                return 1;
            } else {
                while (@mod(x, 10) == 0) : (x /= 10) {
                    acc *= 10;
                }
            }
            return acc;
        }
    };
}

fn FieldResolver(comptime C: type) type {
    return struct {
        pub fn has(comptime field_name: [:0]const u8) bool {
            comptime return @hasDecl(C, field_name);
        }

        pub fn TypeOf(comptime field_name: [:0]const u8) type {
            return @TypeOf(optional(field_name));
        }

        pub fn default(
            comptime field_name: [:0]const u8,
            comptime default_value: anytype,
        ) if (@hasDecl(C, field_name)) @TypeOf(@field(C, field_name)) else @TypeOf(default_value) {
            comptime return if (@hasDecl(C, field_name)) @field(C, field_name) else default_value;
        }

        pub fn required(comptime field_name: [:0]const u8) @TypeOf(@field(C, field_name)) {
            comptime return @field(C, field_name);
        }

        pub fn optional(
            comptime field_name: [:0]const u8,
        ) if (@hasDecl(C, field_name)) @TypeOf(@field(C, field_name)) else @TypeOf(null) {
            comptime return if (@hasDecl(C, field_name)) @field(C, field_name) else null;
        }

        pub fn propertyList(comptime field_name: [:0]const u8) PropertyListImpl {
            comptime return .init(if (@hasDecl(C, field_name)) @field(C, field_name) else &.{});
        }
    };
}

fn unpackFields(comptime fields: []const StdType.StructField) []const StdType.StructField {
    comptime {
        var result: []const StdType.StructField = &[_]StdType.StructField{};
        for (fields) |field| result = result ++ &[_]StdType.StructField{.{
            .name = field.name,
            .type = field.type,
            .default_value_ptr = field.default_value_ptr,
            .is_comptime = field.is_comptime,
            .alignment = @alignOf(field.type),
        }};
        return result;
    }
}

fn isOptional(comptime T: type) bool {
    return @typeInfo(T) == .optional;
}

fn StripOptional(comptime T: type) type {
    return if (isOptional(T)) StripOptional(std.meta.Child(T)) else T;
}

fn refFields(comptime fields: []const StdType.StructField) []const StdType.StructField {
    comptime {
        var result: []const StdType.StructField = &[_]StdType.StructField{};
        for (fields) |field| result = result ++ &[_]StdType.StructField{.{
            .name = field.name,
            .type = *field.type,
            .default_value_ptr = null,
            .is_comptime = field.is_comptime,
            .alignment = @alignOf(*field.type),
        }};
        return result;
    }
}
