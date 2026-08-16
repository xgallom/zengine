//!
//! The zcore global options
//!

const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");
const root = @import("root");

pub const Options = struct {
    org_identifier: [:0]const u8 = "xgallom",
    app_identifier: [:0]const u8 = "zengine",
    log_allocations: bool = std.debug.runtime_safety,
    max_threads: usize = 8,
};

comptime {
    if (@hasDecl(root, "zengine_options") and @hasDecl(root, "zcore_options")) {
        @compileError("Can not use both zengine_options and zcore_options in the same project, " ++
            "use zengine_options.core instead.");
    }
}
pub const options: Options = if (@hasDecl(root, "zengine_options"))
    root.zengine_options.core
else if (@hasDecl(root, "zcore_options"))
    root.zcore_options
else
    .{};
