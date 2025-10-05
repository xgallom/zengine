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
const KeyMap = @import("../containers.zig").KeyMap;

const log = std.log.scoped(.gfx_object);

pub const FaceType = enum {
    invalid,
    point,
    line,
    triangle,
    pub const arr_len = 3;
};

pub const TestExhaustive = enum(u4) {
    value,
    value1,
    value2,
    value4 = 4,
};

pub const TestNonExhaustive = enum(u4) {
    value,
    value14 = 14,
    _,
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

pub const face_vert_counts: std.EnumArray(FaceType, usize) = .init(.{
    .invalid = 0,
    .point = 1,
    .line = 2,
    .triangle = 3,
});

mesh_buf: *MeshBuffer = undefined,
sections: Sections = .empty,
groups: Groups = .empty,
face_type: FaceType,
has_active: packed struct {
    section: bool = false,
    group: bool = false,
    exhaustive: TestExhaustive = .value2,
    non_exhaustive: TestNonExhaustive = .value14,
} = .{},

const Self = @This();
const Sections = std.ArrayList(Section);
const Groups = std.ArrayList(Group);

pub const exclude_properties: ui.property_editor.PropertyList = &.{ .mesh_buf, .sections, .groups };

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

pub fn propertyEditor(self: *Self) ui.PropertyEditor(Self) {
    return .init(self);
}
