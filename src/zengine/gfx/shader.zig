//!
//! The zengine shader implementation
//!

const std = @import("std");
const builtin = @import("builtin");
const sdl = @import("../ext.zig").sdl;
const global = @import("../global.zig");

pub const OpenConfig = struct {
    allocator: std.mem.Allocator,
    gpu_device: ?*sdl.SDL_GPUDevice,
    shader_path: []const u8,
    stage: sdl.SDL_GPUShaderStage,
    num_samplers: u32 = 0,
    num_storage_textures: u32 = 0,
    num_storage_buffers: u32 = 0,
    num_uniform_buffers: u32 = 0,
};

fn open_shader_dir(config: OpenConfig) !std.fs.Dir {
    const shaders_path = try std.fs.path.join(config.allocator, &.{ global.exe_path(), "..", "shaders" });
    return try std.fs.openDirAbsolute(shaders_path, .{});
}

pub fn open(config: OpenConfig) ?*sdl.SDL_GPUShader {
    const shader_formats = sdl.SDL_GetGPUShaderFormats(config.gpu_device);

    var shader_format: sdl.SDL_GPUShaderFormat = undefined;
    var shader_ext: []const u8 = undefined;
    var entry_point: []const u8 = undefined;

    if (shader_formats & sdl.SDL_GPU_SHADERFORMAT_DXIL != 0) {
        std.log.info("shader_format: dxil", .{});
        shader_format = sdl.SDL_GPU_SHADERFORMAT_DXIL;
        shader_ext = ".dxil";
        entry_point = "main";
    } else if (shader_formats & sdl.SDL_GPU_SHADERFORMAT_MSL != 0) {
        std.log.info("shader_format: msl", .{});
        shader_format = sdl.SDL_GPU_SHADERFORMAT_MSL;
        shader_ext = ".msl";
        entry_point = "main0";
    } else if (shader_formats & sdl.SDL_GPU_SHADERFORMAT_SPIRV != 0) {
        std.log.info("shader_format: spirv", .{});
        shader_format = sdl.SDL_GPU_SHADERFORMAT_SPIRV;
        shader_ext = ".spv";
        entry_point = "main";
    } else {
        std.log.err("no supported shader format found", .{});
        return null;
    }

    var shaders_dir = open_shader_dir(config) catch |err| {
        std.log.err("error opening shaders_dir: {s}", .{@errorName(err)});
        return null;
    };
    defer shaders_dir.close();

    const shader_path = std.fmt.allocPrint(config.allocator, "{s}{s}", .{ config.shader_path, shader_ext }) catch |err| {
        std.log.err("error creating shader_path: {s}", .{@errorName(err)});
        return null;
    };

    const shader_file = shaders_dir.openFile(shader_path, .{}) catch |err| {
        std.log.err("failed opening shader_file \"{s}\": {s}", .{ shader_path, @errorName(err) });
        return null;
    };
    defer shader_file.close();

    const code_stat = shader_file.stat() catch |err| {
        std.log.err("failed obtaining shader_file code_stat: {s}", .{@errorName(err)});
        return null;
    };

    var code_size = code_stat.size;
    const code = config.allocator.alloc(u8, code_size) catch |err| {
        std.log.err("failed to allocate code ([{d}]u8): {s}", .{ code_size, @errorName(err) });
        return null;
    };

    code_size = shader_file.readAll(code) catch |err| {
        std.log.err("failed reading code: {s}", .{@errorName(err)});
        return null;
    };

    const shader = sdl.SDL_CreateGPUShader(config.gpu_device, &sdl.SDL_GPUShaderCreateInfo{
        .code_size = code_size,
        .code = code.ptr,
        .entrypoint = @ptrCast(entry_point),
        .format = shader_format,
        .stage = config.stage,
        .num_samplers = config.num_samplers,
        .num_storage_textures = config.num_storage_textures,
        .num_storage_buffers = config.num_storage_buffers,
        .num_uniform_buffers = config.num_uniform_buffers,
        .props = 0,
    });
    if (shader == null) {
        std.log.err("failed creating shader: {s}", .{sdl.SDL_GetError()});
        return null;
    }

    return shader;
}
