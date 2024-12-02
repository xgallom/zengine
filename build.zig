const std = @import("std");

pub fn build(b: *std.Build) void {
    const compile_shaders = b.addExecutable(.{
        .name = "compile_shaders",
        .root_source_file = b.path("src/compile_shaders.zig"),
        .target = b.host,
    });

    const compile_shaders_step = b.addRunArtifact(compile_shaders);
    compile_shaders_step.addArg("--input-dir");
    compile_shaders_step.addDirectoryArg(b.path("shaders"));
    compile_shaders_step.addArg("--output-dir");
    const shaders_output = compile_shaders_step.addOutputDirectoryArg("shaders");

    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
        .source_dir = shaders_output,
        .install_dir = .prefix,
        .install_subdir = "shaders",
    }).step);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zeng",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.addIncludePath(b.path("include"));
    exe.addLibraryPath(b.path("lib"));

    switch (target.result.os.tag) {
        .macos => b.installBinFile("lib/libSDL3.0.dylib", "SDL3.dylib"),
        else => unreachable, // Unsupported target OS
    }

    exe.linkSystemLibrary("SDL3");
    exe.linkLibC();

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
