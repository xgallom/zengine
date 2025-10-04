//!
//! The zengine ui element cache
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const UI = @import("UI.zig");

const log = std.log.scoped(.ui_cache);
// pub const sections = perf.sections(@This(), &.{ .init, .draw });

var ref_count: std.atomic.Value(usize) = .init(0);
var hash_map: std.AutoHashMapUnmanaged(usize, Value(anyopaque)) = .empty;

pub fn init() void {
    _ = ref_count.fetchAdd(1, .monotonic);
}

pub fn deinit() void {
    if (ref_count.fetchSub(1, .seq_cst) == 1) {
        hash_map.deinit(allocators.gpa());
    }
}

pub fn getOrPut(comptime T: type, key: usize, value: T) GetOrPutResult(T) {
    const entry = hash_map.getOrPut(allocators.gpa(), key) catch unreachable;
    const value_ptr: *Value(T) = @ptrCast(entry.value_ptr);
    if (entry.found_existing) return .{ .value = value_ptr.*, .found_existing = true };
    value_ptr.item = allocators.ui().create(T) catch unreachable;
    log.info("alloc item {}", .{key});
    value_ptr.item.* = value;
    value_ptr.element = value_ptr.item.element();
    return .{ .value = value_ptr.*, .found_existing = false };
}

pub fn Value(comptime T: type) type {
    return struct {
        element: UI.Element,
        item: *T,
    };
}

pub fn GetOrPutResult(comptime T: type) type {
    return struct {
        value: Value(T),
        found_existing: bool,
    };
}
