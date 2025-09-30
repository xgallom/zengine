//!
//! The zengine .mtl file loader
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const math = @import("../math.zig");
const RGBf32 = math.RGBf32;
const str = @import("../str.zig");
const ui = @import("../ui.zig");
const MaterialInfo = @import("MaterialInfo.zig");

const log = std.log.scoped(.gfx_mtl_loader);

pub const Materials = std.ArrayListUnmanaged(MaterialInfo);
const LineIterator = std.mem.SplitIterator(u8, .scalar);

pub const Result = struct {
    allocator: std.mem.Allocator,
    items: []MaterialInfo = &.{},

    pub fn deinit(self: *Result) void {
        self.allocator.free(self.items);
    }
};

pub fn loadFile(gpa: std.mem.Allocator, path: []const u8) !Result {
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const buf = try allocators.scratch().alloc(u8, 1 << 8);
    var reader = file.reader(buf);

    var materials = try Materials.initCapacity(gpa, 1);
    defer materials.deinit(gpa);

    var material_ptr: ?*MaterialInfo = null;
    while (reader.interface.takeDelimiterExclusive('\n')) |full_line| {
        const line = std.mem.trim(u8, full_line, " \t\n\r");
        if (line.len == 0) continue;
        if (line[0] == '#') continue;
        var iter = std.mem.splitScalar(u8, line, ' ');
        if (iter.next()) |cmd| {
            if (str.eql(cmd, "newmtl")) {
                const name = str.trimRest(&iter);
                if (name.len == 0) return error.SyntaxError;
                material_ptr = try materials.addOne(gpa);
                material_ptr.?.* = .{ .name = try str.dupeZ(name) };
            } else if (material_ptr) |mat| {
                if (str.eql(cmd, "map_Ka")) {
                    mat.texture = try parsePath(&iter);
                } else if (str.eql(cmd, "map_Kd")) {
                    mat.diffuse_map = try parsePath(&iter);
                } else if (str.eql(cmd, "map_bump")) {
                    mat.bump_map = try parsePath(&iter);
                } else if (str.eql(cmd, "bump")) {
                    mat.bump_map = try parsePath(&iter);
                } else if (str.eql(cmd, "Ka")) {
                    mat.clr_ambient = try parseRGBf32(&iter);
                } else if (str.eql(cmd, "Kd")) {
                    mat.clr_diffuse = try parseRGBf32(&iter);
                } else if (str.eql(cmd, "Ks")) {
                    mat.clr_specular = try parseRGBf32(&iter);
                } else if (str.eql(cmd, "Ke")) {
                    mat.clr_emissive = try parseRGBf32(&iter);
                } else if (str.eql(cmd, "Tf")) {
                    mat.clr_filter = try parseRGBf32(&iter);
                } else if (str.eql(cmd, "Ns")) {
                    mat.specular_exp = try parseFloat(&iter);
                } else if (str.eql(cmd, "Ni")) {
                    mat.ior = try parseFloat(&iter);
                } else if (str.eql(cmd, "d")) {
                    mat.alpha = try parseFloat(&iter);
                } else if (str.eql(cmd, "Tr")) {
                    mat.alpha = 1 - try parseFloat(&iter);
                } else if (str.eql(cmd, "illum")) {
                    mat.mode = try parseMode(&iter);
                }
            }
        } else return error.SyntaxError;
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.StreamTooLong,
        error.ReadFailed,
        => |e| return e,
    }

    return .{
        .allocator = gpa,
        .items = try materials.toOwnedSlice(gpa),
    };
}

fn parsePath(iter: *LineIterator) ![:0]const u8 {
    const rest = str.trimRest(iter);
    if (rest.len != 0) return str.dupeZ(rest);
    return error.SyntaxError;
}

fn parseRGBf32(iter: *LineIterator) !math.RGBf32 {
    const r = try parseFloat(iter);
    const g = try parseFloat(iter);
    const b = try parseFloat(iter);
    return .{ r, g, b };
}

fn parseFloat(iter: *LineIterator) !f32 {
    if (iter.next()) |token| return std.fmt.parseFloat(f32, token);
    return error.SyntaxError;
}

fn parseMode(iter: *LineIterator) !u8 {
    if (iter.next()) |token| return std.fmt.parseInt(u8, token, 10);
    return error.SyntaxError;
}
