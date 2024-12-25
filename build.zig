const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const install_shaders = b.option(bool, "install_shaders", "Force shaders update");

    const zengine = b.addModule("zengine", .{
        .root_source_file = b.path("src/zengine/zengine.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    zengine.addSystemIncludePath(b.path("include"));
    zengine.addLibraryPath(b.path("lib"));
    zengine.linkSystemLibrary("SDL3", .{ .needed = true });

    const lib = b.addStaticLibrary(.{
        .name = "zengine",
        .root_source_file = b.path("src/zengine/zengine.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    lib.addSystemIncludePath(b.path("include"));
    lib.addLibraryPath(b.path("lib"));
    lib.linkSystemLibrary("SDL3");

    const exe = b.addExecutable(.{
        .name = "zeng",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    exe.addSystemIncludePath(b.path("include"));
    exe.addLibraryPath(b.path("lib"));
    exe.linkSystemLibrary("SDL3");

    exe.root_module.addImport("zengine", zengine);

    b.installArtifact(exe);

    const compile_shaders = b.addExecutable(.{
        .name = "compile_shaders",
        .root_source_file = b.path("src/compile_shaders.zig"),
        .target = b.graph.host,
    });

    switch (target.result.os.tag) {
        .macos => b.installBinFile("lib/libSDL3.0.dylib", "SDL3.dylib"),
        else => std.zig.fatal("Unsupported target os: {s}", .{@tagName(target.result.os.tag)}),
    }

    const compile_shaders_cmd = b.addRunArtifact(compile_shaders);
    compile_shaders_cmd.addArg("--input-dir");
    compile_shaders_cmd.addDirectoryArg(b.path("shaders"));
    compile_shaders_cmd.addArg("--output-dir");

    if (install_shaders orelse false) {
        compile_shaders_cmd.addArg(b.getInstallPath(.prefix, "shaders"));
        b.getInstallStep().dependOn(&compile_shaders_cmd.step);
    } else {
        const shaders_output = compile_shaders_cmd.addOutputDirectoryArg("shaders");
        const install_shaders_directory = b.addInstallDirectory(.{
            .source_dir = shaders_output,
            .install_dir = .prefix,
            .install_subdir = "shaders",
        });
        b.getInstallStep().dependOn(&install_shaders_directory.step);
    }

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/zengine/zengine.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Install documentation");
    docs_step.dependOn(&install_docs.step);
}
