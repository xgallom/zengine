const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const compile_shaders_opt = b.option(bool, "compile-shaders", "Force shader compilation");

    const build_ext = b.addSystemCommand(&.{"build-scripts/build-external.sh"});
    const build_ext_step = b.step("ext", "Build external dependencies");
    build_ext_step.dependOn(&build_ext.step);

    const clean_ext = b.addSystemCommand(&.{"build-scripts/clean-external.sh"});
    const clean_ext_step = b.step("clean-ext", "Clean external dependencies");
    clean_ext_step.dependOn(&clean_ext.step);

    const zengine = b.addModule("zengine", .{
        .root_source_file = b.path("src/zengine/zengine.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });

    zengine.addLibraryPath(b.path("external/build/lib"));
    zengine.addIncludePath(b.path("external/build/include"));
    zengine.addIncludePath(b.path("external/cimgui"));

    zengine.linkSystemLibrary("SDL3", .{});
    zengine.linkSystemLibrary("SDL3_shadercross", .{});
    zengine.linkSystemLibrary("cimgui", .{});

    const lib = b.addLibrary(.{
        .name = "zengine",
        .root_module = zengine,
        .linkage = .dynamic,
    });

    // TODO: when -femit-h gets fixed
    // const install_header = b.addInstallHeaderFile(lib.getEmittedH(), "zengine.h");
    // b.getInstallStep().dependOn(&install_header.step);

    const exe = b.addExecutable(.{
        .name = "zeng",
        .root_module = b.addModule("main", .{
            .root_source_file = b.path("src/main.zig"),
            .imports = &.{
                .{ .name = "zengine", .module = zengine },
            },
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = true,
        }),
    });

    b.installArtifact(exe);

    const install_assembly = b.addInstallBinFile(exe.getEmittedAsm(), "zeng.s");
    b.getInstallStep().dependOn(&install_assembly.step);

    // const build_ext = b.addExecutable(.{
    //     .name = "build-external",
    //     .root_module = b.addModule("build_external", .{
    //         .root_source_file = b.path("src/build_external.zig"),
    //         .target = b.graph.host,
    //         .optimize = optimize,
    //     }),
    // });
    //
    // const build_ext_cmd = b.addRunArtifact(build_ext);
    // build_ext_cmd.addArg("--input-dir");
    // build_ext_cmd.addDirectoryArg(b.path("external"));
    // build_ext_cmd.addArg("--cache-dir");
    // _ = build_ext_cmd.addOutputDirectoryArg("cache");
    // build_ext_cmd.addArg("--output-dir");
    // const build_ext_output = build_ext_cmd.addOutputDirectoryArg("build");
    //
    // const build_ext_install = b.addInstallDirectory(.{
    //     .source_dir = build_ext_output,
    //     .install_dir = .prefix,
    //     .install_subdir = "",
    // });
    //
    // b.getInstallStep().dependOn(&build_ext_install.step);
    //
    // build_ext_cmd.has_side_effects = compile_ext_opt orelse false;
    //
    // const build_ext_step = b.step("ext", "Builds external dependencies");
    // build_ext_step.dependOn(&build_ext_install.step);

    const compile_shaders = b.addExecutable(.{
        .name = "compile-shaders",
        .root_module = b.addModule("compile_shaders", .{
            .root_source_file = b.path("src/compile_shaders.zig"),
            .imports = &.{
                .{ .name = "zengine", .module = zengine },
            },
            .target = b.graph.host,
            .optimize = optimize,
        }),
    });

    _ = try compile_shaders.step.addDirectoryWatchInput(b.path("shaders/include"));
    _ = try compile_shaders.step.addDirectoryWatchInput(b.path("shaders/src"));

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
    compile_shaders_cmd.addArg("--include-dir");
    compile_shaders_cmd.addDirectoryArg(b.path("shaders/include"));
    compile_shaders_cmd.addArg("--input-dir");
    compile_shaders_cmd.addDirectoryArg(b.path("shaders/src"));
    compile_shaders_cmd.addArg("--output-dir");
    const shaders_output = compile_shaders_cmd.addOutputDirectoryArg("shaders");

    const install_shaders_dir = b.addInstallDirectory(.{
        .source_dir = shaders_output,
        .install_dir = .prefix,
        .install_subdir = "shaders",
    });

    b.getInstallStep().dependOn(&install_shaders_dir.step);

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
