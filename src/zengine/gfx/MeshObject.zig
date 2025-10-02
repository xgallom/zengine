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

pub const FaceType = enum(u8) {
    invalid,
    point,
    line,
    triangle,
    pub const arr_len = 3;
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

allocator: std.mem.Allocator,
mesh_buf: *MeshBuffer = undefined,
sections: Sections = .empty,
groups: Groups = .empty,
face_type: FaceType,
has_active_section: bool = false,
has_active_group: bool = false,

const Self = @This();
const Sections = std.ArrayList(Section);
const Groups = std.ArrayList(Group);

pub fn init(allocator: std.mem.Allocator, face_type: FaceType) Self {
    return .{
        .allocator = allocator,
        .face_type = face_type,
    };
}

pub fn deinit(self: *Self) void {
    self.sections.deinit(self.allocator);
    self.groups.deinit(self.allocator);
}

pub fn beginSection(self: *Self, offset: usize, material: ?[:0]const u8) !void {
    self.endSection(offset);
    try self.sections.append(self.allocator, .{
        .offset = offset,
        .material = material,
    });
    self.has_active_section = true;
}

pub fn endSection(self: *Self, offset: usize) void {
    if (!self.has_active_section) return;
    assert(self.sections.items.len > 0);
    const section = &self.sections.items[self.sections.items.len - 1];
    section.len = offset - section.offset;
    self.has_active_section = false;
}

// fn splitSection(self: *Self, offset: usize) !usize {
//     assert(self.sections.items.len > 0);
//     assert(self.has_active_section);
//
//     const idx = self.sections.items.len - 1;
//     const section = &self.sections.items[idx];
//     if (section.offset == offset) {
//         assert(section.len == 0);
//         return idx;
//     }
//
//     section.len = offset - section.offset;
//     try self.sections.append(self.allocator, .{
//         .offset = offset,
//         .material = section.material,
//     });
//     return idx + 1;
// }

pub fn beginGroup(self: *Self, offset: usize, name: [:0]const u8) !void {
    self.endGroup(offset);
    try self.groups.append(self.allocator, .{
        .offset = offset,
        .name = name,
    });
    self.has_active_group = true;
}

pub fn endGroup(self: *Self, offset: usize) void {
    if (!self.has_active_group) return;
    assert(self.groups.items.len > 0);
    const group = &self.groups.items[self.groups.items.len - 1];
    group.len = offset - group.offset;
    self.has_active_group = false;
}
