//!
//! The zengine filesystem implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const zcore = @import("zcore");
const c = zcore.ext;
const allocators = zcore.allocators;

const global = @import("global.zig");

const log = std.log.scoped(.gfx_shader);

pub fn readFile(allocator: std.mem.Allocator, path: []const u8, dir: std.Io.Dir) ![]const u8 {
    const file = try dir.openFile(global.io(), path, .{});
    defer file.close(global.io());
    var reader = file.reader(global.io(), &.{});
    return reader.interface.readAlloc(allocator, try reader.getSize());
}

pub fn readFileAbsolute(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.Io.Dir.openFileAbsolute(global.io(), path, .{});
    defer file.close(global.io());
    var reader = file.reader(global.io(), &.{});
    return reader.interface.readAlloc(allocator, try reader.getSize());
}
