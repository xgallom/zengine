//!
//! The zengine plotting ui axis formatters
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const perf = @import("../perf.zig");
const UI = @import("UI.zig");
const time = @import("../time.zig");

const log = std.log.scoped(.ui_plot_fmt);

pub const AxisRange = enum {
    range_0,
    range_pos,
    range_neg,
    range_any,
};

pub fn AxisLimits(comptime T: type, comptime options: struct {
    range_min: AxisRange = .range_any,
    range_max: AxisRange = .range_any,
}) type {
    const Limits = struct { min: f64, max: f64 };
    return struct {
        pub fn applySlice(axis: c.ImAxis, slice: []const []const T) void {
            if (slice.len == 0) return;
            const len = slice[0].len;
            if (len == 0) return;
            for (slice) |values| assert(values.len == len);
            const lims = limits(slice);
            c.ImPlot_SetupAxisLimits(axis, lims.min, lims.max, c.ImPlotCond_Always);
        }

        pub fn apply(axis: c.ImAxis, values: []const T) void {
            if (values.len == 0) return;
            const lims = limits(&.{values});
            c.ImPlot_SetupAxisLimits(axis, lims.min, lims.max, c.ImPlotCond_Always);
        }

        fn limits(slice: []const []const T) Limits {
            return switch (comptime options.range_min) {
                .range_0 => switch (comptime options.range_max) {
                    .range_0 => .{ .min = 0, .max = 0 },
                    else => .{ .min = 0, .max = rangeMax(slice) },
                },
                else => switch (comptime options.range_max) {
                    .range_0 => .{ .min = rangeMin(slice), .max = 0 },
                    else => rangeMinMax(slice),
                },
            };
        }

        fn rangeMin(slice: []const []const T) f64 {
            var min: T = slice[0][0];
            for (slice) |values| {
                for (values) |value| min = @min(min, value);
            }
            return minVal(min);
        }

        fn rangeMax(slice: []const []const T) f64 {
            var max: T = slice[0][0];
            for (slice) |values| {
                for (values) |value| max = @max(max, value);
            }
            return maxVal(max);
        }

        fn rangeMinMax(slice: []const []const T) Limits {
            var min: T = slice[0][0];
            var max: T = slice[0][0];
            for (slice) |values| {
                for (values) |value| {
                    min = @min(min, value);
                    max = @max(max, value);
                }
            }
            return .{ .min = minVal(min), .max = maxVal(max) };
        }

        fn minVal(value: T) f64 {
            const f_val: f64 = switch (@typeInfo(T)) {
                .comptime_int, .int => @floatFromInt(value),
                .comptime_float, .float => value,
                else => @compileError("Unsupported type"),
            };
            return switch (comptime options.range_min) {
                .range_pos => f_val / 1.2,
                .range_neg => f_val * 1.2,
                .range_any => if (f_val >= 0) f_val / 1.2 else f_val * 1.2,
                else => unreachable,
            };
        }

        fn maxVal(value: T) f64 {
            const f_val: f64 = switch (@typeInfo(T)) {
                .comptime_int, .int => @floatFromInt(value),
                .comptime_float, .float => value,
                else => @compileError("Unsupported type"),
            };
            return switch (comptime options.range_max) {
                .range_pos => f_val * 1.2,
                .range_neg => f_val / 1.2,
                .range_any => if (f_val >= 0) f_val * 1.2 else f_val / 1.2,
                else => unreachable,
            };
        }
    };
}

pub fn Metric(comptime unit: []const u8) type {
    return struct {
        const thresholds = [_]f64{ 1e9, 1e6, 1e3, 1e0, 1e-3, 1e-6, 1e-9 };
        const prefixes = [_][]const u8{ "G", "M", "k", "", "m", "u", "n" };
        pub const formatter = &format;

        pub fn format(value: f64, buf: [*c]u8, size: c_int, data: ?*anyopaque) callconv(.c) c_int {
            _ = data;
            if (value == 0) return bufPrintZ(buf, size, "0 {s}", .{unit});
            const abs = @abs(value);
            for (thresholds, prefixes) |threshold, prefix| {
                if (abs >= threshold) return bufPrintZ(buf, size, "{} {s}{s}", .{
                    value / threshold,
                    prefix,
                    unit,
                });
            }
            const threshold = thresholds[thresholds.len - 1];
            const prefix = prefixes[prefixes.len - 1];
            return bufPrintZ(buf, size, "{} {s}{s}", .{
                value / threshold,
                prefix,
                unit,
            });
        }

        pub fn apply(comptime axis: c.ImAxis) void {
            c.ImPlot_SetupAxisFormat_PlotFormatter(axis, &format, null);
        }
    };
}

pub fn Time(comptime unit: time.Unit) type {
    return struct {
        pub fn format(value: f64, buf: [*c]u8, size: c_int, data: ?*anyopaque) callconv(.c) c_int {
            _ = data;
            const i_value: u64 = @intFromFloat(time.Unit.convert(unit, .ns, value));
            return bufPrintZ(buf, size, "{D}", .{i_value});
        }

        pub fn apply(comptime axis: c.ImAxis) void {
            c.ImPlot_SetupAxisFormat_PlotFormatter(axis, &format, null);
        }
    };
}

fn bufPrintZ(buf: [*c]u8, size: c_int, comptime fmt: []const u8, args: anytype) c_int {
    const text = std.fmt.bufPrintZ(buf[0..@intCast(size)], fmt, args) catch unreachable;
    return @intCast(text.len);
}
