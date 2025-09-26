//!
//! The zengine shader implementation
//!

const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const fs = @import("../fs.zig");

const log = std.log.scoped(.gfx_shader);

pub const OpenConfig = struct {
    allocator: std.mem.Allocator,
    gpu_device: ?*c.SDL_GPUDevice,
    shader_path: []const u8,
    stage: Stage,
};

pub const Stage = enum(c.SDL_GPUShaderStage) {
    vertex = c.SDL_GPU_SHADERSTAGE_VERTEX,
    fragment = c.SDL_GPU_SHADERSTAGE_FRAGMENT,
};

const FormatConfig = struct {
    shader_format: c.SDL_GPUShaderFormat,
    shader_ext: []const u8,
    entry_point: []const u8,
};

const GraphicsMetadataJSON = struct {
    num_samplers: u32 = 0,
    num_storage_textures: u32 = 0,
    num_storage_buffers: u32 = 0,
    num_uniform_buffers: u32 = 0,
};

pub fn open(config: OpenConfig) !*c.SDL_GPUShader {
    const format = try pickFormat(&config);

    var shaders_dir = try openShadersDir();
    defer shaders_dir.close();

    const code = try readShaderCode(&config, &format, &shaders_dir);
    defer config.allocator.free(code);

    const meta = try readShaderMeta(&config, &shaders_dir);

    const shader = c.SDL_CreateGPUShader(config.gpu_device, &c.SDL_GPUShaderCreateInfo{
        .code_size = code.len,
        .code = code.ptr,
        .entrypoint = @ptrCast(format.entry_point),
        .format = format.shader_format,
        .stage = @intFromEnum(config.stage),
        .num_samplers = meta.num_samplers,
        .num_storage_textures = meta.num_storage_textures,
        .num_storage_buffers = meta.num_storage_buffers,
        .num_uniform_buffers = meta.num_uniform_buffers,
        .props = 0,
    });

    if (shader == null) {
        log.err("failed creating shader: {s}", .{c.SDL_GetError()});
        return error.CreateFailed;
    }

    return shader.?;
}

pub fn release(gpu_device: ?*c.SDL_GPUDevice, shader: ?*c.SDL_GPUShader) void {
    c.SDL_ReleaseGPUShader(gpu_device, shader);
}

fn pickFormat(config: *const OpenConfig) !FormatConfig {
    const shader_formats = c.SDL_GetGPUShaderFormats(config.gpu_device);

    if (shader_formats & c.SDL_GPU_SHADERFORMAT_DXIL != 0) {
        log.debug("shader format: dxil", .{});
        return .{
            .shader_format = c.SDL_GPU_SHADERFORMAT_DXIL,
            .shader_ext = ".dxil",
            .entry_point = "main",
        };
    } else if (shader_formats & c.SDL_GPU_SHADERFORMAT_MSL != 0) {
        log.debug("shader format: msl", .{});
        return .{
            .shader_format = c.SDL_GPU_SHADERFORMAT_MSL,
            .shader_ext = ".msl",
            .entry_point = "main0",
        };
    } else if (shader_formats & c.SDL_GPU_SHADERFORMAT_SPIRV != 0) {
        log.debug("shader format: spirv", .{});
        return .{
            .shader_format = c.SDL_GPU_SHADERFORMAT_SPIRV,
            .shader_ext = ".spv",
            .entry_point = "main",
        };
    } else {
        log.err("no supported shader format found", .{});
        return error.NoFormat;
    }
}

fn openShadersDir() !std.fs.Dir {
    const shaders_path = try std.fs.path.join(
        allocators.scratch(),
        &.{ global.exePath(), "..", "shaders" },
    );
    return std.fs.openDirAbsolute(shaders_path, .{});
}

fn readShaderCode(
    config: *const OpenConfig,
    format: *const FormatConfig,
    shaders_dir: *std.fs.Dir,
) ![]const u8 {
    const path = try std.fmt.allocPrint(allocators.scratch(), "{s}{s}", .{ config.shader_path, format.shader_ext });
    return fs.readFile(config.allocator, path, shaders_dir) catch |err| {
        log.err("error reading shader code file \"{s}\": {t}", .{ path, err });
        return err;
    };
}

fn readShaderMeta(
    config: *const OpenConfig,
    shaders_dir: *std.fs.Dir,
) !GraphicsMetadataJSON {
    const path = try std.fmt.allocPrint(allocators.scratch(), "{s}{s}", .{ config.shader_path, ".json" });
    const data = fs.readFile(config.allocator, path, shaders_dir) catch |err| {
        log.err("error reading shader meta file \"{s}\": {t}", .{ path, err });
        return err;
    };
    defer config.allocator.free(data);

    return std.json.parseFromSliceLeaky(GraphicsMetadataJSON, allocators.scratch(), data, .{}) catch |err| {
        log.err("error parsing shader meta file \"{s}\": {t}", .{ path, err });
        return err;
    };
}
