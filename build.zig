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

    zengine.addLibraryPath(b.path("SDL/build"));
    zengine.addIncludePath(b.path("SDL/include"));
    zengine.linkSystemLibrary("SDL3", .{ .needed = true });

    zengine.addLibraryPath(b.path("SDL_shadercross/build"));
    zengine.addIncludePath(b.path("SDL_shadercross/include"));
    zengine.linkSystemLibrary("SDL3_shadercross", .{ .needed = true });

    zengine.addLibraryPath(b.path("cimgui/build"));
    zengine.addIncludePath(b.path("cimgui"));
    zengine.linkSystemLibrary("cimgui", .{ .needed = true });

    const lib = b.addLibrary(.{
        .name = "zengine",
        .root_module = zengine,
        .linkage = .dynamic,
    });

    // TODO: when -femit-h gets fixed
    // const install_header = b.addInstallHeaderFile(lib.getEmittedH(), "zengine.h");
    // b.getInstallStep().dependOn(&install_header.step);

    const exe_mod = b.addModule("main", .{
        .root_source_file = b.path("src/main.zig"),
        .imports = &.{
            .{ .name = "zengine", .module = zengine },
        },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });

    const exe = b.addExecutable(.{
        .name = "zeng",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const install_assembly = b.addInstallBinFile(exe.getEmittedAsm(), "zeng.s");
    b.getInstallStep().dependOn(&install_assembly.step);

    const compile_shaders_mod = b.addModule("compile_shaders", .{
        .root_source_file = b.path("src/compile_shaders.zig"),
        .imports = &.{
            .{ .name = "zengine", .module = zengine },
        },
        .target = b.graph.host,
        .optimize = optimize,
    });

    const compile_shaders = b.addExecutable(.{
        .name = "compile-shaders",
        .root_module = compile_shaders_mod,
    });

    // TODO: Use instead of hlsl?
    //
    // const compile_shader = b.addExecutable(.{
    //     .name = "shader.frag",
    //     .root_module = b.addModule("shader", .{
    //         .root_source_file = b.path("src/shader.zig"),
    //         .target = b.resolveTargetQuery(.{
    //             .cpu_arch = .spirv32,
    //             .cpu_model = .{ .explicit = &std.Target.spirv.cpu.vulkan_v1_2 },
    //             .os_tag = .vulkan,
    //             .ofmt = .spirv,
    //         }),
    //         .optimize = optimize,
    //     }),
    //     .use_llvm = false,
    //     .use_lld = false,
    // });
    //
    // b.installArtifact(compile_shader);

    switch (target.result.os.tag) {
        .macos => {
            // zengine.addRPathSpecial("$ORIGIN/../lib");
            // b.getInstallStep().dependOn(&b.addInstallLibFile(
            //     b.path("SDL/build/libSDL3.0.dylib"),
            //     "libSDL3.0.dylib",
            // ).step);
            // b.getInstallStep().dependOn(&b.addInstallLibFile(
            //     b.path("SDL/build/libSDL3.dylib"),
            //     "libSDL3.dylib",
            // ).step);
            // b.getInstallStep().dependOn(&b.addInstallLibFile(
            //     b.path("cimgui/build/libcimgui_with_backend.dylib"),
            //     "libcimgui_with_backend.dylib",
            // ).step);
            // b.getInstallStep().dependOn(&b.addInstallLibFile(
            //     b.path("cimgui/build/libcimgui_with_backend.dylib"),
            //     "libcimgui.dylib",
            // ).step);
        },
        else => std.process.fatal("Unsupported target os: {s}", .{@tagName(target.result.os.tag)}),
    }

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

    const all_step = b.step("zengine", "Build zengine with docs");
    all_step.dependOn(b.getInstallStep());
    all_step.dependOn(&install_docs.step);
}
