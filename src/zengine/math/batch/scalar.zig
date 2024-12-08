//!
//! The zengine batching math scalar helper implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const types = @import("types.zig");
const scalarT = @import("../scalar.zig").scalarT;

pub fn batchNT(comptime N: usize, comptime T: type) type {
    return scalarT(types.BatchNT(N, T));
}
