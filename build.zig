const std = @import("std");
const log = std.log;

pub const Options = struct {
    compile_shaders: bool,
    ext_cmd: ?ExtCommand,
    ext_cmd_cmake_args: []const u8,
    ext_cmd_make_args: []const u8,
    ext_cmd_make_install_args: []const u8,
};

pub const ExtCommand = enum {
    external,
    cache,
    sdl,
    sdl_image,
    sdl_mixer,
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

var compile_shaders: ?*std.Build.Step.Compile = null;
var compile_shaders_cmds: std.ArrayList(*std.Build.Step.Run) = .empty;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = getOptions(b);

    _ = try addExternal(b, .{
        .options = options,
        .target = target,
        .optimize = optimize,
    });

    const zengine = b.addModule("zengine", .{
        .root_source_file = b.path("src/zengine/zengine.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
        .pic = true,
    });

    zengine.addLibraryPath(b.path("external/build/lib"));
    zengine.addIncludePath(b.path("external/build/include"));
    zengine.addIncludePath(b.path("external/cimgui/imgui"));
    zengine.addIncludePath(b.path("external/cimgui"));
    zengine.addIncludePath(b.path("external/cimplot"));
    zengine.linkSystemLibrary("SDL3", .{});
    zengine.linkSystemLibrary("SDL3_image", .{});
    zengine.linkSystemLibrary("SDL3_mixer", .{});
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

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .imports = &.{
            .{ .name = "zengine", .module = zengine },
        },
        .target = target,
        .optimize = optimize,
        .pic = true,
    });

    const check_exe = b.addExecutable(.{
        .name = "zengine",
        .root_module = exe_mod,
    });

    const exe = b.addExecutable(.{
        .name = "zengine",
        .root_module = exe_mod,
    });

    const install_libs = try addInstallLibs(b, .{
        .module = zengine,
        .options = options,
        .target = target,
        .optimize = optimize,
    });

    lib.step.dependOn(install_libs);
    lib.each_lib_rpath = false;
    exe.step.dependOn(install_libs);
    exe.each_lib_rpath = false;

    const install_lib = b.addInstallArtifact(lib, .{});
    // const install_lib_asm = b.addInstallLibFile(lib.getEmittedAsm(), "libzengine.S");
    // install_lib.step.dependOn(&install_lib_asm.step);

    const install_exe = b.addInstallArtifact(exe, .{});
    // const install_exe_asm = b.addInstallBinFile(exe.getEmittedAsm(), "zengine.S");
    // install_exe.step.dependOn(&install_exe_asm.step);

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

    const install_assets = try addInstallAssets(b);

    const install_shaders_dir = try addCompileShaders(b, .{
        .module = zengine,
        .options = options,
        .optimize = optimize,
    });

    const unit_tests = b.addTest(.{
        .root_module = zengine,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .{ .custom = "share" },
        .install_subdir = "doc/zengine",
    });

    const docs_step = b.step("docs", "Install documentation");
    docs_step.dependOn(&install_docs.step);

    const zengine_step = b.step("zengine", "Build Zengine");
    zengine_step.dependOn(install_libs);
    zengine_step.dependOn(&install_assets.step);
    zengine_step.dependOn(&install_shaders_dir.step);
    zengine_step.dependOn(&install_exe.step);
    zengine_step.dependOn(&install_lib.step);
    zengine_step.dependOn(&install_docs.step);

    const check_step = b.step("check", "Check Zengine");
    check_step.dependOn(&check_exe.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(zengine_step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run Zengine");
    run_step.dependOn(&run_cmd.step);
}

pub fn addExternal(b: *std.Build, options: struct {
    b: ?*std.Build = null,
    options: Options,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
}) !struct {
    build: *std.Build.Step.Run,
    clean: *std.Build.Step.Run,
} {
    const zb = options.b orelse b;

    const build_ext_cmd = zb.pathFromRoot(try std.fs.path.join(b.allocator, &.{
        "build-scripts",
        b.fmt("build-{t}.{s}", .{
            options.options.ext_cmd orelse .external,
            if (options.target.result.os.tag == .windows) "ps1" else "sh",
        }),
    }));
    const build_ext = switch (options.target.result.os.tag) {
        .windows => b.addSystemCommand(&.{
            "pwsh",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            build_ext_cmd,
            "-Target",
            ext_optimize.get(options.optimize),
            "-CMakeArgs",
            options.options.ext_cmd_cmake_args,
            "-MakeArgs",
            options.options.ext_cmd_make_args,
            "-MakeInstallArgs",
            options.options.ext_cmd_make_install_args,
        }),
        else => b.addSystemCommand(&.{
            build_ext_cmd,
            ext_optimize.get(options.optimize),
            options.options.ext_cmd_cmake_args,
            options.options.ext_cmd_make_args,
            options.options.ext_cmd_make_install_args,
        }),
    };
    const build_ext_step = b.step("ext", "Build external dependencies");
    build_ext_step.dependOn(&build_ext.step);

    const clean_ext_cmd = zb.pathFromRoot(try std.fs.path.join(b.allocator, &.{
        "build-scripts",
        b.fmt("clean-{t}.{s}", .{
            options.options.ext_cmd orelse .cache,
            if (options.target.result.os.tag == .windows) "ps1" else "sh",
        }),
    }));
    const clean_ext = switch (options.target.result.os.tag) {
        .windows => b.addSystemCommand(&.{
            "pwsh",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            clean_ext_cmd,
        }),
        else => b.addSystemCommand(&.{clean_ext_cmd}),
    };
    const clean_ext_step = b.step("ext-clean", "Clean external dependencies");
    clean_ext_step.dependOn(&clean_ext.step);

    return .{ .build = build_ext, .clean = clean_ext };
}

pub fn addInstallLibs(b: *std.Build, options: struct {
    b: ?*std.Build = null,
    module: *std.Build.Module,
    build_ext: ?*std.Build.Step.Run = null,
    options: Options,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
}) !*std.Build.Step {
    const zb = options.b orelse b;

    var path: []const u8 = undefined;
    switch (options.target.result.os.tag) {
        .windows => {
            // TODO: Ensure share gets installed on Windows
            const install_libs = b.addInstallDirectory(.{
                .source_dir = zb.path("external/build/bin"),
                .install_dir = .bin,
                .install_subdir = "",
                .include_extensions = &.{".dll"},
            });
            if (options.build_ext) |build_ext| install_libs.step.dependOn(&build_ext.step);
            return &install_libs.step;
        },
        .macos => {
            options.module.addRPathSpecial("@executable_path/../lib");
            options.module.addRPathSpecial("@executable_path/../Frameworks");
            path = zb.pathFromRoot("external/build/lib/*.dylib");
        },
        .linux => {
            options.module.addRPathSpecial("$ORIGIN/../lib");
            path = zb.pathFromRoot("external/build/lib/*.so");
        },
        else => @panic("Unsupported OS"),
    }
    const install_lib_dir = b.getInstallPath(.lib, "");
    const mkdir = b.addSystemCommand(&.{ "mkdir", "-p", install_lib_dir });
    const cp = b.addSystemCommand(&.{
        "sh",
        "-c",
        b.fmt("cp -P -R {s} {s}", .{
            path,
            install_lib_dir,
        }),
    });
    if (options.build_ext) |build_ext| cp.step.dependOn(&build_ext.step);
    cp.step.dependOn(&mkdir.step);
    const xattr = b.addSystemCommand(&.{ "xattr", "-rc", install_lib_dir });
    xattr.step.dependOn(&cp.step);

    const install_share = b.addInstallDirectory(.{
        .source_dir = zb.path("external/build/share"),
        .install_dir = .prefix,
        .install_subdir = "share",
    });
    if (options.build_ext) |build_ext| install_share.step.dependOn(&build_ext.step);

    const install_libs = b.step("install-libs", "Install libraries");
    install_libs.dependOn(&xattr.step);
    install_libs.dependOn(&install_share.step);

    return install_libs;
}

pub fn addInstallAssets(b: *std.Build) !*std.Build.Step.InstallDir {
    return b.addInstallDirectory(.{
        .source_dir = b.path("assets"),
        .install_dir = .prefix,
        .install_subdir = "assets",
    });
}

pub fn addCompileShaders(b: *std.Build, options: struct {
    b: ?*std.Build = null,
    src: ?std.Build.LazyPath = null,
    module: *std.Build.Module,
    options: Options,
    optimize: std.builtin.OptimizeMode,
}) !*std.Build.Step.InstallDir {
    const zb = options.b orelse b;
    if (compile_shaders == null) {
        compile_shaders = b.addExecutable(.{
            .name = "compile-shaders",
            .root_module = b.addModule("compile_shaders", .{
                .root_source_file = zb.path("src/compile_shaders.zig"),
                .imports = &.{
                    .{ .name = "zengine", .module = options.module },
                },
                .target = b.graph.host,
                .optimize = options.optimize,
            }),
        });
    }

    const compile_shaders_cmd = b.addRunArtifact(compile_shaders.?);
    compile_shaders_cmd.addArg("--include-dir");
    compile_shaders_cmd.addDirectoryArg(zb.path("shaders/include"));
    compile_shaders_cmd.addArg("--input-dir");
    compile_shaders_cmd.addDirectoryArg(options.src orelse zb.path("shaders/src"));
    compile_shaders_cmd.addArg("--output-dir");
    const shaders_output = compile_shaders_cmd.addOutputDirectoryArg("shaders");
    compile_shaders_cmd.has_side_effects = options.options.compile_shaders;

    // 1 because the 0-th element is from the zengine build step and we don't want to invoke it
    if (compile_shaders_cmds.items.len > 1) {
        compile_shaders_cmd.step.dependOn(&compile_shaders_cmds.getLast().step);
    }
    try compile_shaders_cmds.append(b.allocator, compile_shaders_cmd);

    return b.addInstallDirectory(.{
        .source_dir = shaders_output,
        .install_dir = .prefix,
        .install_subdir = "shaders",
    });
}

pub fn addBundleMacOSApp(b: *std.Build, config: struct {
    app_dirname: []const u8,
    exe_app_filename: []const u8,
    install_exe: *std.Build.Step.InstallArtifact,
    install_libs: *std.Build.Step,
    install_resources: []const *std.Build.Step.InstallDir = &.{},
}) !*std.Build.Step {
    const copy_base_dir = b.addInstallDirectory(.{
        .source_dir = b.path("macos"),
        .install_dir = .prefix,
        .install_subdir = config.app_dirname,
        .exclude_extensions = &.{".gitkeep"},
    });

    const exe_path = b.getInstallPath(.prefix, b.pathJoin(&.{
        config.app_dirname,
        "Contents",
        "MacOS",
        config.exe_app_filename,
    }));
    const install_exe = b.addSystemCommand(&.{
        "cp",
        "-f",
        b.getInstallPath(.bin, config.install_exe.artifact.out_filename),
        exe_path,
    });
    install_exe.step.dependOn(&copy_base_dir.step);
    install_exe.step.dependOn(&config.install_exe.step);

    const strip_rpath = b.addSystemCommand(&.{
        "install_name_tool",
        "-delete_rpath",
        "/usr/local/lib",
        exe_path,
    });
    strip_rpath.step.dependOn(&install_exe.step);

    const install_libs = b.addSystemCommand(&.{
        "cp",
        "-PRf",
        b.getInstallPath(.lib, ""),
        b.getInstallPath(.prefix, b.pathJoin(&.{ config.app_dirname, "Contents", "Frameworks" })),
    });
    const install_share = b.addSystemCommand(&.{
        "cp",
        "-rf",
        b.getInstallPath(.prefix, "share"),
        b.getInstallPath(.prefix, b.pathJoin(&.{
            config.app_dirname,
            "Contents",
            "Resources",
            "share",
        })),
    });
    install_libs.step.dependOn(&copy_base_dir.step);
    install_libs.step.dependOn(config.install_libs);
    install_share.step.dependOn(&copy_base_dir.step);
    install_share.step.dependOn(config.install_libs);

    const install_resources = try b.allocator.alloc(
        *std.Build.Step.Run,
        config.install_resources.len,
    );
    for (install_resources, config.install_resources) |*ir, install_resource| {
        ir.* = b.addSystemCommand(&.{
            "cp",
            "-rf",
            b.getInstallPath(
                install_resource.options.install_dir,
                install_resource.options.install_subdir,
            ),
            b.getInstallPath(.prefix, b.pathJoin(&.{
                config.app_dirname,
                "Contents",
                "Resources",
                install_resource.options.install_subdir,
            })),
        });
        ir.*.step.dependOn(&copy_base_dir.step);
        ir.*.step.dependOn(&install_resource.step);
    }

    const add_bundle_macos_app = b.step("bundle-macos", "Bundle MacOS app");
    add_bundle_macos_app.dependOn(&strip_rpath.step);
    add_bundle_macos_app.dependOn(&install_libs.step);
    add_bundle_macos_app.dependOn(&install_share.step);
    for (install_resources) |ir| add_bundle_macos_app.dependOn(&ir.step);
    return add_bundle_macos_app;
}

pub fn getOptions(b: *std.Build) Options {
    return .{
        .compile_shaders = b.option(
            bool,
            "compile-shaders",
            "Force shader compilation",
        ) orelse false,
        .ext_cmd = b.option(ExtCommand, "ext-command", "Project to use for external compilation"),
        .ext_cmd_cmake_args = b.option(
            []const u8,
            "ext-cmake-args",
            "Arguments for external configuration",
        ) orelse "",
        .ext_cmd_make_args = b.option(
            []const u8,
            "ext-make-args",
            "Arguments for external compilation",
        ) orelse "-j",
        .ext_cmd_make_install_args = b.option(
            []const u8,
            "ext-make-install-args",
            "Arguments for external installation",
        ) orelse "",
    };
}
