//!
//! The zengine build functions
//!

const std = @import("std");

pub fn addExecutable(
    b: *std.Build,
) !std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = "zengine",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .imports = &.{
                .{ .name = "zengine", .module = zengine },
            },
            .target = target,
            .optimize = optimize,
            .pic = true,
        }),
    });
}
