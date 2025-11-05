//!
//! The zengine shader loader implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const c = @import("../ext.zig").c;
const GraphicsMetadata = c.SDL_ShaderCross_GraphicsShaderMetadata;
const GraphicsMetadataIOVar = c.SDL_ShaderCross_IOVarMetadata;
const fs = @import("../fs.zig");
const global = @import("../global.zig");
const GPUDevice = @import("GPUDevice.zig");
const GPUShader = @import("GPUShader.zig");

const log = std.log.scoped(.gfx_shader_loader);

pub const OpenConfig = struct {
    allocator: std.mem.Allocator,
    gpu_device: GPUDevice,
    shader_path: []const u8,
    stage: GPUShader.Stage,
};

const FormatConfig = struct {
    format: GPUShader.Format,
    shader_ext: [:0]const u8,
    entry_point: [:0]const u8,
};

const GraphicsMetadataJSON = struct {
    num_samplers: u32 = 0,
    num_storage_textures: u32 = 0,
    num_storage_buffers: u32 = 0,
    num_uniform_buffers: u32 = 0,
    inputs: []IOVar,
    outputs: []IOVar,

    const IOVar = struct {
        name: [:0]const u8,
        location: u32,
        vector_type: Type,
        vector_size: u32,

        const Type = enum(c.SDL_ShaderCross_IOVarType) {
            unknown = c.SDL_SHADERCROSS_IOVAR_TYPE_UNKNOWN,
            i8 = c.SDL_SHADERCROSS_IOVAR_TYPE_INT8,
            u8 = c.SDL_SHADERCROSS_IOVAR_TYPE_UINT8,
            i16 = c.SDL_SHADERCROSS_IOVAR_TYPE_INT16,
            u16 = c.SDL_SHADERCROSS_IOVAR_TYPE_UINT16,
            i32 = c.SDL_SHADERCROSS_IOVAR_TYPE_INT32,
            u32 = c.SDL_SHADERCROSS_IOVAR_TYPE_UINT32,
            i64 = c.SDL_SHADERCROSS_IOVAR_TYPE_INT64,
            u64 = c.SDL_SHADERCROSS_IOVAR_TYPE_UINT64,
            f16 = c.SDL_SHADERCROSS_IOVAR_TYPE_FLOAT16,
            f32 = c.SDL_SHADERCROSS_IOVAR_TYPE_FLOAT32,
            f64 = c.SDL_SHADERCROSS_IOVAR_TYPE_FLOAT64,
        };
    };
};

pub fn loadFile(config: *const OpenConfig) !GPUShader {
    const format = try pickFormat(config);

    var shaders_dir = try openShadersDir();
    defer shaders_dir.close();

    const code = try readShaderCode(config, &format, &shaders_dir);
    defer config.allocator.free(code);

    const meta = try readShaderMeta(config, &shaders_dir);

    return .init(config.gpu_device, &.{
        .code = code,
        .entry_point = format.entry_point,
        .format = format.format,
        .stage = config.stage,
        .num_samplers = meta.num_samplers,
        .num_storage_textures = meta.num_storage_textures,
        .num_storage_buffers = meta.num_storage_buffers,
        .num_uniform_buffers = meta.num_uniform_buffers,
    });
}

fn pickFormat(config: *const OpenConfig) !FormatConfig {
    const shader_formats = config.gpu_device.formatFlags();
    if (shader_formats.contains(.dxil)) {
        log.debug("shader format: dxil", .{});
        return .{
            .format = .dxil,
            .shader_ext = ".dxil",
            .entry_point = "main",
        };
    } else if (shader_formats.contains(.msl)) {
        log.debug("shader format: msl", .{});
        return .{
            .format = .msl,
            .shader_ext = ".msl",
            .entry_point = "main0",
        };
    } else if (shader_formats.contains(.spirv)) {
        log.debug("shader format: spirv", .{});
        return .{
            .format = .spirv,
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
    defer allocators.scratch().free(shaders_path);
    return std.fs.openDirAbsolute(shaders_path, .{});
}

fn readShaderCode(config: *const OpenConfig, format: *const FormatConfig, shaders_dir: *std.fs.Dir) ![]const u8 {
    const path = try std.fmt.allocPrint(allocators.scratch(), "{s}{s}", .{ config.shader_path, format.shader_ext });
    defer allocators.scratch().free(path);
    return fs.readFile(config.allocator, path, shaders_dir) catch |err| {
        log.err("error reading shader code file \"{s}\": {t}", .{ path, err });
        return err;
    };
}

fn readShaderMeta(config: *const OpenConfig, shaders_dir: *std.fs.Dir) !GraphicsMetadataJSON {
    const path = try std.fmt.allocPrint(allocators.scratch(), "{s}{s}", .{ config.shader_path, ".json" });
    defer allocators.scratch().free(path);
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
