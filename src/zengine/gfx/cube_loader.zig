//!
//! The zengine .cube file loader
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const math = @import("../math.zig");
const RGBf32 = math.RGBf32;
const str = @import("../str.zig");
const ui = @import("../ui.zig");
const LookUpTable = @import("LookUpTable.zig");

const log = std.log.scoped(.gfx_cube_loader);

pub const Data = std.ArrayList(math.RGBAf32);

pub fn loadFile(gpa: std.mem.Allocator, path: []const u8) !LookUpTable {
    var file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();

    const buf = try allocators.scratch().alloc(u8, 1 << 8);
    var reader = file.reader(buf);

    var data: Data = .empty;
    defer data.deinit(gpa);

    var dim_len: u32 = 0;

    while (reader.interface.takeDelimiterInclusive('\n')) |full_line| {
        const line = str.trim(full_line);
        if (line.len == 0) continue;
        if (line[0] == '#') continue;

        var iter = std.mem.splitScalar(u8, line, ' ');
        if (iter.next()) |cmd| {
            if (str.eql(cmd, "TITLE")) {
                const name = str.trimRest(&iter);
                if (name.len == 0) return error.SyntaxError;
                log.debug("title {}", .{name});
                // lgh_ptr = try data.addOne(gpa);
                // lgh_ptr.?.* = .{ .name = try str.dupeZ(name) };
            } else if (str.eql(cmd, "LUT_3D_SIZE")) {
                dim_len = try parseSize(&iter);
                try data.ensureTotalCapacityPrecise(gpa, dim_len * dim_len * dim_len);
                log.debug("3D size {}", .{dim_len});
            } else {
                assert(dim_len > 0);
                iter.reset();
                data.appendAssumeCapacity(try parseRGBAf32(&iter));
            }
        } else return error.SyntaxError;
    } else |err| switch (err) {
        error.EndOfStream => {},
        error.StreamTooLong,
        error.ReadFailed,
        => |e| return e,
    }

    assert(data.items.len == dim_len * dim_len * dim_len);
    return .init(try data.toOwnedSlice(gpa), dim_len);
}

fn parseRGBAf32(iter: *str.ScalarIterator) !math.RGBAf32 {
    const r = try parseFloat(iter);
    const g = try parseFloat(iter);
    const b = try parseFloat(iter);
    return .{ r, g, b, 1 };
}

fn parseFloat(iter: *str.ScalarIterator) !f32 {
    if (iter.next()) |token| return std.fmt.parseFloat(f32, token);
    return error.SyntaxError;
}

fn parseSize(iter: *str.ScalarIterator) !u32 {
    if (iter.next()) |token| return std.fmt.parseInt(u32, token, 10);
    return error.SyntaxError;
}
