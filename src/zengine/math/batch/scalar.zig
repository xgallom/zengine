//!
//! The zengine batching math scalar helper implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const scalarT = @import("../scalar.zig").scalarT;
const types = @import("types.zig");

pub fn batchNT(comptime N: usize, comptime T: type) type {
    return scalarT(types.BatchNT(N, T));
}
