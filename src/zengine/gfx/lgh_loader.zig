//!
//! The zengine .lgh file loader
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const math = @import("../math.zig");
const RGBf32 = math.RGBf32;
const str = @import("../str.zig");
const ui = @import("../ui.zig");
const Light = @import("Light.zig");

const log = std.log.scoped(.gfx_lgh_loader);

pub const Lights = std.ArrayList(Light);

pub const Result = struct {
    allocator: std.mem.Allocator,
    items: []Light = &.{},

    pub fn deinit(self: *Result) void {
        self.allocator.free(self.items);
    }
};

pub fn loadFile(gpa: std.mem.Allocator, path: []const u8) !Result {
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const buf = try allocators.scratch().alloc(u8, 1 << 8);
    var reader = file.reader(buf);

    var lights = try Lights.initCapacity(gpa, 1);
    defer lights.deinit(gpa);

    var lgh_ptr: ?*Light = null;
    while (reader.interface.takeDelimiterInclusive('\n')) |full_line| {
        const line = str.trim(full_line);
        if (line.len == 0) continue;
        if (line[0] == '#') continue;

        var iter = std.mem.splitScalar(u8, line, ' ');
        if (iter.next()) |cmd| {
            if (str.eql(cmd, "newlgh")) {
                const name = str.trimRest(&iter);
                if (name.len == 0) return error.SyntaxError;
                lgh_ptr = try lights.addOne(gpa);
                lgh_ptr.?.* = .{ .name = try str.dupeZ(name) };
            } else if (lgh_ptr) |lgh| {
                if (str.eql(cmd, "T")) {
                    lgh.type = try parseType(&iter);
                } else if (str.eql(cmd, "K")) {
                    lgh.src.color = try parseRGBf32(&iter);
                } else if (str.eql(cmd, "P")) {
                    lgh.src.power = try parseFloat(&iter);
                } else return error.SyntaxError;
            } else return error.SyntaxError;
        } else return error.SyntaxError;
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.StreamTooLong,
        error.ReadFailed,
        => |e| return e,
    }

    return .{
        .allocator = gpa,
        .items = try lights.toOwnedSlice(gpa),
    };
}

fn parseRGBf32(iter: *str.ScalarIterator) !math.RGBf32 {
    const r = try parseFloat(iter);
    const g = try parseFloat(iter);
    const b = try parseFloat(iter);
    return .{ r, g, b };
}

fn parseFloat(iter: *str.ScalarIterator) !f32 {
    if (iter.next()) |token| return std.fmt.parseFloat(f32, token);
    return error.SyntaxError;
}

fn parseType(iter: *str.ScalarIterator) !Light.Type {
    const rest = str.trimRest(iter);
    if (checkType(rest, .ambient)) return .ambient;
    if (checkType(rest, .directional)) return .directional;
    if (checkType(rest, .point)) return .point;
    return error.InvalidLightType;
}

fn checkType(rest: []const u8, comptime lgh_type: Light.Type) bool {
    return str.eql(rest, @tagName(lgh_type));
}
