//!
//! The zengine mesh object implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../../ext.zig").c;
const global = @import("../../global.zig");
const math = @import("../../math.zig");
const ui = @import("../../ui.zig");
const mesh = @import("../mesh.zig");

const log = std.log.scoped(.gfx_mesh_object);

pub const BufferType = enum(u8) {
    mesh,
    tex_coords_u,
    tex_coords_v,
    normals,
    tangents,
    binormals,
};

pub const BufferFlagsType = enum(u8) {
    mesh,
    tex_coords_u,
    tex_coords_v,
    normals,
    tangents,
    binormals,
    origin,

    pub fn from(t: BufferType) BufferFlagsType {
        return @enumFromInt(@intFromEnum(t));
    }
};

pub const face_vert_counts: std.EnumArray(mesh.FaceType, usize) = .init(.{
    .invalid = 0,
    .point = 1,
    .line = 2,
    .triangle = 3,
});

mesh_bufs: Buffers = .initUndefined(),
sections: Sections = .empty,
groups: Groups = .empty,
face_type: mesh.FaceType,
is_visible: BufferFlags = .initOne(.mesh),
has_active: packed struct {
    section: bool = false,
    group: bool = false,
} = .{},

const Self = @This();
pub const Buffers = std.EnumArray(BufferType, *mesh.Buffer);
pub const BufferFlags = std.EnumSet(BufferFlagsType);
const Sections = std.ArrayList(Section);
const Groups = std.ArrayList(Group);

pub const excluded_properties: ui.property_editor.PropertyList = &.{ .mesh_bufs, .groups };
pub const is_visible_input = struct {
    ptr: *BufferFlags,

    pub fn init(ptr: *BufferFlags) @This() {
        return .{ .ptr = ptr };
    }

    pub fn draw(self: *const @This(), ui_ptr: *const ui.UI, is_open: *bool) void {
        ui.property_editor.InputFields(
            packed struct(std.bit_set.IntegerBitSet(BufferFlags.len).MaskInt) {
                mesh: bool,
                tex_coords_u: bool,
                tex_coords_v: bool,
                normals: bool,
                tangents: bool,
                binormals: bool,
                origin: bool,
            },
            .{ .name = "is_visible" },
        ).init(@ptrCast(&self.ptr.bits.mask)).draw(ui_ptr, is_open);
    }
};

pub const Section = struct {
    offset: usize,
    len: usize = 0,
    material: ?[:0]const u8,
};

pub const Group = struct {
    offset: usize,
    len: usize = 0,
    name: [:0]const u8,
};

pub const AddSectionResult = struct {
    group: *Group,
    section: *Section,
};

pub fn init(face_type: mesh.FaceType) Self {
    return .{ .face_type = face_type };
}

pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
    self.sections.deinit(gpa);
    self.groups.deinit(gpa);
}

pub fn beginSection(self: *Self, gpa: std.mem.Allocator, offset: usize, material: ?[:0]const u8) !void {
    self.endSection(offset);
    try self.sections.append(gpa, .{
        .offset = offset,
        .material = material,
    });
    self.has_active.section = true;
}

pub fn endSection(self: *Self, offset: usize) void {
    if (!self.has_active.section) return;
    assert(self.sections.items.len > 0);
    const section = &self.sections.items[self.sections.items.len - 1];
    section.len = offset - section.offset;
    self.has_active.section = false;
}

pub fn beginGroup(self: *Self, gpa: std.mem.Allocator, offset: usize, name: [:0]const u8) !void {
    self.endGroup(offset);
    try self.groups.append(gpa, .{
        .offset = offset,
        .name = name,
    });
    self.has_active.group = true;
}

pub fn endGroup(self: *Self, offset: usize) void {
    if (!self.has_active.group) return;
    assert(self.groups.items.len > 0);
    const group = &self.groups.items[self.groups.items.len - 1];
    group.len = offset - group.offset;
    self.has_active.group = false;
}

pub fn propertyEditor(self: *Self) ui.Element {
    return ui.PropertyEditor(Self).init(self).element();
}
