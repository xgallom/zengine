const std = @import("std");

const ExtCommand = enum {
    external,
    sdl,
    sdl_image,
    sdl_ttf,
    shadercross,
    cimgui,
    cimplot,
};

const ext_optimize = std.EnumArray(std.builtin.OptimizeMode, []const u8).init(.{
    .Debug = "Debug",
    .ReleaseSafe = "RelWithDebInfo",
    .ReleaseFast = "Release",
    .ReleaseSmall = "MinSizeRel",
});

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const compile_shaders_opt = b.option(bool, "compile-shaders", "Force shader compilation");
    const ext_cmd_opt = b.option(ExtCommand, "ext-command", "Project to use for external compilation") orelse .external;
    const ext_cmd_cmake_args_opt = b.option(
        []const u8,
        "ext-cmake-args",
        "Arguments for external configuration",
    ) orelse "";
    const ext_cmd_make_args_opt = b.option(
        []const u8,
        "ext-make-args",
        "Arguments for external compilation",
    ) orelse "-j";
    const ext_cmd_make_install_args_opt = b.option(
        []const u8,
        "ext-make-install-args",
        "Arguments for external installation",
    ) orelse "";

    const build_ext_cmd = try std.fs.path.join(b.allocator, &.{
        "build-scripts",
        b.fmt("build-{t}.sh", .{ext_cmd_opt}),
    });
    const build_ext = b.addSystemCommand(&.{
        build_ext_cmd,
        ext_optimize.get(optimize),
        ext_cmd_cmake_args_opt,
        ext_cmd_make_args_opt,
        ext_cmd_make_install_args_opt,
    });
    const build_ext_step = b.step("ext", "Build external dependencies");
    build_ext_step.dependOn(&build_ext.step);

    const clean_ext_cmd = try std.fs.path.join(b.allocator, &.{
        "build-scripts",
        b.fmt("clean-{t}.sh", .{ext_cmd_opt}),
    });
    const clean_ext = b.addSystemCommand(&.{clean_ext_cmd});
    const clean_ext_step = b.step("ext-clean", "Clean external dependencies");
    clean_ext_step.dependOn(&clean_ext.step);

    const zengine = b.addModule("zengine", .{
        .root_source_file = b.path("src/zengine/zengine.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
        .pic = true,
    });

    zengine.addLibraryPath(b.path("external/build/bin"));
    zengine.addLibraryPath(b.path("external/build/lib"));
    zengine.addIncludePath(b.path("external/build/include"));
    zengine.addIncludePath(b.path("external/cimgui"));
    zengine.addIncludePath(b.path("external/cimplot"));

    zengine.linkSystemLibrary("SDL3", .{});
    zengine.linkSystemLibrary("SDL3_image", .{});
    zengine.linkSystemLibrary("SDL3_ttf", .{});
    zengine.linkSystemLibrary("SDL3_shadercross", .{});
    zengine.linkSystemLibrary("cimgui", .{});
    zengine.linkSystemLibrary("cimplot", .{});

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

    // TODO: use instead of hlsl?
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
        .windows => {},
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
    // try addDirectoryWatchInput(b, &compile_shaders_cmd.step, "shaders/include");
    // try addDirectoryWatchInput(b, &compile_shaders_cmd.step, "shaders/src");
    // try addDirectoryWatchInput(b, &install_shaders_dir.step, "shaders/include");
    // try addDirectoryWatchInput(b, &install_shaders_dir.step, "shaders/src");
    // try addDirectoryWatchInput(b, b.getInstallStep(), "shaders/include");
    // try addDirectoryWatchInput(b, b.getInstallStep(), "shaders/src");

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

fn addDirectoryWatchInput(b: *std.Build, step: *std.Build.Step, path: []const u8) !void {
    const allowed_exts = [_][]const u8{".hlsl"};

    if (try step.addDirectoryWatchInput(b.path(path))) {
        var sources: std.ArrayList([]const u8) = .empty;
        var dir = try std.fs.cwd().openDir(path, .{
            .iterate = true,
            .access_sub_paths = true,
        });

        var walker = try dir.walk(b.allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            const ext = std.fs.path.extension(entry.basename);
            const include_file = for (allowed_exts) |e| {
                if (std.mem.eql(u8, ext, e))
                    break true;
            } else false;
            if (include_file) try sources.append(b.allocator, b.pathJoin(&.{ path, entry.path }));
        }

        for (sources.items) |src_path| {
            std.log.info("watch {s}", .{src_path});
            try step.addWatchInput(b.path(src_path));
        }
    }
}
