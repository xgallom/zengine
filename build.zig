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
    const build_ext_cmd = try std.fs.path.join(b.allocator, &.{
        "build-scripts",
        b.fmt("build-{t}.sh", .{options.ext_cmd orelse .external}),
    });
    const build_ext = b.addSystemCommand(&.{
        build_ext_cmd,
        ext_optimize.get(optimize),
        options.ext_cmd_cmake_args,
        options.ext_cmd_make_args,
        options.ext_cmd_make_install_args,
    });
    const build_ext_step = b.step("ext", "Build external dependencies");
    build_ext_step.dependOn(&build_ext.step);

    const clean_ext_cmd = try std.fs.path.join(b.allocator, &.{
        "build-scripts",
        b.fmt("clean-{t}.sh", .{options.ext_cmd orelse .cache}),
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
        .strip = false,
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
        .name = "zengine",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .imports = &.{
                .{ .name = "zengine", .module = zengine },
            },
            .target = target,
            .optimize = optimize,
            .pic = true,
            .strip = false,
        }),
    });

    const install_assembly = b.addInstallBinFile(exe.getEmittedAsm(), "zengine.S");
    const install_exe = b.addInstallArtifact(exe, .{});
    install_exe.step.dependOn(&install_assembly.step);

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
        .linux => {},
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
        .install_dir = .prefix,
        .install_subdir = "docs",
    });

    const docs_step = b.step("docs", "Install documentation");
    docs_step.dependOn(&install_docs.step);

    const zengine_step = b.step("zengine", "Build Zengine");
    zengine_step.dependOn(&install_shaders_dir.step);
    zengine_step.dependOn(&install_exe.step);
    zengine_step.dependOn(&install_docs.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(zengine_step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run Zengine");
    run_step.dependOn(&run_cmd.step);
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

pub fn getOptions(b: *std.Build) Options {
    return .{
        .compile_shaders = b.option(bool, "compile-shaders", "Force shader compilation") orelse false,
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
