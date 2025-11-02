//!
//! The zengine mesh object implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const ui = @import("../ui.zig");
const MeshBuffer = @import("MeshBuffer.zig");

const log = std.log.scoped(.gfx_mesh_object);

pub const MeshBufferType = enum {
    mesh,
    tex_coords,
    normals,
    tangents,
    binormals,
};

pub const FaceType = enum {
    invalid,
    point,
    line,
    triangle,
    pub const arr_len = 3;
};

pub const face_vert_counts: std.EnumArray(FaceType, usize) = .init(.{
    .invalid = 0,
    .point = 1,
    .line = 2,
    .triangle = 3,
});

mesh_bufs: MeshBuffers = .initUndefined(),
sections: Sections = .empty,
groups: Groups = .empty,
face_type: FaceType,
has_active: packed struct {
    section: bool = false,
    group: bool = false,
} = .{},
is_visible: std.EnumSet(MeshBufferType) = .initOne(.mesh),

const Self = @This();
pub const MeshBuffers = std.EnumArray(MeshBufferType, *MeshBuffer);
const Sections = std.ArrayList(Section);
const Groups = std.ArrayList(Group);

pub const exclude_properties: ui.property_editor.PropertyList = &.{ .mesh_bufs, .sections, .groups };
pub const is_visible_input = struct {
    ptr: *std.EnumSet(MeshBufferType),

    pub fn init(ptr: *std.EnumSet(MeshBufferType)) @This() {
        return .{ .ptr = ptr };
    }

    pub fn draw(self: *const @This(), ui_ptr: *const ui.UI, is_open: *bool) void {
        ui.property_editor.InputFields(
            packed struct {
                mesh: bool,
                tex_coords: bool,
                normals: bool,
                tangents: bool,
                binormals: bool,
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

pub fn init(face_type: FaceType) Self {
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
