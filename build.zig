const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const compile_shaders_opt = b.option(bool, "compile-shaders", "Force shader compilation");

    const zengine = b.addModule("zengine", .{
        .root_source_file = b.path("src/zengine/zengine.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });

    zengine.linkSystemLibrary("SDL3", .{ .needed = true });
    zengine.addIncludePath(b.path("cimgui"));

    const exe_mod = b.addModule("main", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    exe_mod.addImport("zengine", zengine);

    const lib = b.addLibrary(.{
        .name = "zengine",
        .root_module = zengine,
    });

    const exe = b.addExecutable(.{
        .name = "zeng",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const compile_shaders = b.addExecutable(.{
        .name = "compile_shaders",
        .root_module = b.addModule("compile_shaders", .{
            .root_source_file = b.path("src/compile_shaders.zig"),
            .target = b.graph.host,
        }),
    });

    // switch (target.result.os.tag) {
    //     .macos => b.installBinFile("lib/libSDL3.0.dylib", "SDL3.dylib"),
    //     else => std.zig.fatal("Unsupported target os: {s}", .{@tagName(target.result.os.tag)}),
    // }

    const compile_shaders_cmd = b.addRunArtifact(compile_shaders);
    compile_shaders_cmd.addArg("--input-dir");
    compile_shaders_cmd.addDirectoryArg(b.path("shaders/src"));
    compile_shaders_cmd.addArg("--output-dir");
    const shaders_output = compile_shaders_cmd.addOutputDirectoryArg("shaders");
    compile_shaders_cmd.addArg("--include-dir");
    compile_shaders_cmd.addDirectoryArg(b.path("shaders/include"));

    const install_shaders_directory = b.addInstallDirectory(.{
        .source_dir = shaders_output,
        .install_dir = .prefix,
        .install_subdir = "shaders",
    });

    b.getInstallStep().dependOn(&install_shaders_directory.step);

    compile_shaders_cmd.has_side_effects = compile_shaders_opt orelse false;

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = zengine,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Install documentation");
    docs_step.dependOn(&install_docs.step);
}
