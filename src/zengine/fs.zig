//!
//! The zengine filesystem implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("allocators.zig");
const c = @import("ext.zig").c;
const global = @import("global.zig");

const log = std.log.scoped(.gfx_shader);

pub fn readFile(allocator: std.mem.Allocator, path: []const u8, dir: *std.fs.Dir) ![]const u8 {
    const file = try dir.openFile(path, .{});
    defer file.close();
    var reader = file.reader(&.{});
    return reader.interface.readAlloc(allocator, try reader.getSize());
}

pub fn readFileAbsolute(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    var reader = file.reader(&.{});
    return reader.interface.readAlloc(allocator, try reader.getSize());
}
