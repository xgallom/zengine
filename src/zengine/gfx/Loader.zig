//!
//! The zengine gfx loader module
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const KeyMap = @import("../containers.zig").ArrayKeyMap;
const PtrKeyMap = @import("../containers.zig").ArrayPtrKeyMap;
const ecs = @import("../ecs.zig");
const Renderer = @import("Renderer.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const perf = @import("../perf.zig");
const ui_mod = @import("../ui.zig");
const img = @import("img.zig");
const MaterialInfo = @import("MaterialInfo.zig");
const MeshBuffer = @import("MeshBuffer.zig");
const mtl_loader = @import("mtl_loader.zig");
const obj_loader = @import("obj_loader.zig");
const MeshObject = @import("MeshObject.zig");
const GPUBuffer = @import("GPUBuffer.zig");
const Surface = @import("Surface.zig");
const Scene = @import("../Scene.zig");
const SurfaceTexture = @import("SurfaceTexture.zig");
const UploadTransferBuffer = @import("UploadTransferBuffer.zig");

const log = std.log.scoped(.gfx_loader);

const InitError = Renderer.InitError;

pub const Target = enum {
    mesh_buffer,
    storage_buffer,
    surface_texture,
};

renderer: *Renderer,
surface_textures: SurfaceTextures,
modifs: std.EnumArray(Target, std.ArrayList([]const u8)),

const Self = @This();
const SurfaceTextures = KeyMap(SurfaceTexture, .{});

pub fn init(renderer: *Renderer) !Self {
    return .{
        .renderer = renderer,
        .surface_textures = try .init(renderer.allocator, 128),
        .modifs = .initFill(.empty),
    };
}

pub fn deinit(self: *Self) void {
    const gpa = self.renderer.allocator;
    const gpu_device = self.renderer.gpu_device;

    for (self.renderer.mesh_bufs.map.values()) |mesh_buf| mesh_buf.freeCPUBuffers(gpa);
    for (self.renderer.storage_bufs.map.values()) |buf| buf.freeCPUBuffer(gpa);
    for (self.surface_textures.map.values()) |tex| tex.deinit(gpu_device);
    self.surface_textures.deinit();

    assert(self.modifs.getPtrConst(.mesh_buffer).items.len == 0);
    assert(self.modifs.getPtrConst(.storage_buffer).items.len == 0);
    assert(self.modifs.getPtrConst(.surface_texture).items.len == 0);
    self.modifs.getPtr(.mesh_buffer).deinit(gpa);
    self.modifs.getPtr(.storage_buffer).deinit(gpa);
    self.modifs.getPtr(.surface_texture).deinit(gpa);
}

pub fn cancel(self: *Self) void {
    self.modifs.getPtr(.mesh_buffer).clearRetainingCapacity();
    self.modifs.getPtr(.storage_buffer).clearRetainingCapacity();
    self.modifs.getPtr(.surface_texture).clearRetainingCapacity();
    self.deinit();
}

pub fn commit(self: *Self) !void {
    try self.createGPUData();
    try self.uploadTransferBuffers();
    try self.commitSurfaceTextures();
    self.modifs.getPtr(.mesh_buffer).clearRetainingCapacity();
    self.modifs.getPtr(.storage_buffer).clearRetainingCapacity();
    self.modifs.getPtr(.surface_texture).clearRetainingCapacity();
}

pub fn flagModified(self: *Self, comptime target: Target, key: []const u8) !void {
    return self.modifs.getPtr(target).append(self.renderer.allocator, key);
}

pub fn loadMesh(
    self: *Self,
    scene: *Scene,
    key: []const u8,
    asset_path: []const u8,
) !*MeshBuffer {
    const mesh_path = try global.assetPath(asset_path);

    var result = obj_loader.loadFile(self.renderer.allocator, mesh_path) catch |err| {
        log.err("failed loading mesh obj file: {t}", .{err});
        return InitError.BufferFailed;
    };
    errdefer {
        result.mesh_buf.deinit(self.renderer.allocator, self.renderer.gpu_device);
        result.deinit();
    }

    if (result.mtl_path) |mtl_path| try self.loadMaterials(mtl_path);
    const mesh_buf = try self.renderer.insertMeshBuffer(key, &result.mesh_buf);
    try self.flagModified(.mesh_buffer, key);

    var iter = result.mesh_objs.iterator();
    while (iter.next()) |e| {
        const mesh_obj = e.value_ptr;
        mesh_obj.mesh_buf = mesh_buf;
        _ = try scene.createObject(
            e.key_ptr.*,
            .fromMeshObject(
                try self.renderer.insertMeshObject(
                    e.key_ptr.*,
                    mesh_obj,
                ),
            ),
        );
    }

    result.cleanup();
    return mesh_buf;
}

pub fn loadMaterials(self: *Self, asset_path: []const u8) InitError!void {
    const mtl_path = try global.assetPath(asset_path);
    var mtl = mtl_loader.loadFile(self.renderer.allocator, mtl_path) catch |err| {
        log.err("error loading material: {t}", .{err});
        return InitError.MaterialFailed;
    };
    defer mtl.deinit();
    for (mtl.items) |*item| {
        const tex_paths = [_]?[]const u8{ item.texture, item.diffuse_map, item.bump_map };
        for (&tex_paths) |opt_tex_path| {
            if (opt_tex_path) |tex_path| _ = try self.loadTexture(tex_path);
        }
        _ = try self.renderer.insertMaterial(item.name, item);
    }
}

pub fn loadTexture(self: *Self, asset_path: []const u8) !*SurfaceTexture {
    if (self.surface_textures.getPtrOrNull(asset_path)) |ptr| return ptr;

    const tex_path = try global.assetPath(asset_path);
    const surface = img.open(.{
        .allocator = self.renderer.allocator,
        .gpu_device = self.renderer.gpu_device,
        .file_path = tex_path,
    }) catch |err| {
        log.err("failed reading image file: {t}", .{err});
        return InitError.TextureFailed;
    };
    var texture: SurfaceTexture = .init(surface);
    errdefer texture.deinit(self.renderer.gpu_device);
    try self.flagModified(.surface_texture, asset_path);
    return self.surface_textures.insert(asset_path, texture);
}

pub fn createOriginMesh(self: *Self) !*MeshBuffer {
    const origin_mesh = try self.renderer.createMeshBuffer("origin", .index);
    try self.flagModified(.mesh_buffer, "origin");

    origin_mesh.append(self.renderer.allocator, .vertex, math.Vertex, &.{
        .{ 0, 0, 0 },
        .{ 0, 0, 0 },
        .{ 0, 0, 0 },
        .{ 1, 0, 0 },
        .{ 0, 0, 0 },
        .{ 0, 0, 0 },
        .{ 0, 1, 0 },
        .{ 0, 0, 0 },
        .{ 0, 0, 0 },
        .{ 0, 0, 1 },
        .{ 0, 0, 0 },
        .{ 0, 0, 0 },
    }) catch |err| {
        log.err("failed appending origin mesh vertices: {t}", .{err});
        return InitError.BufferFailed;
    };
    origin_mesh.vert_counts.set(.vertex, 4 * 3);
    origin_mesh.append(self.renderer.allocator, .index, math.LineFaceIndex, &.{
        .{ 0, 1 },
        .{ 0, 2 },
        .{ 0, 3 },
    }) catch |err| {
        log.err("failed appending origin mesh faces: {t}", .{err});
        return InitError.BufferFailed;
    };
    origin_mesh.vert_counts.set(.index, 2 * 3);

    return origin_mesh;
}

pub fn createDefaultMaterial(self: *Self) !*MaterialInfo {
    return self.renderer.createMaterial("default");
}

pub fn createTestingMaterial(self: *Self) !*MaterialInfo {
    const key = "testing";
    return self.renderer.insertMaterial(key, &.{
        .name = key,
        .clr_ambient = .{ 0.5, 0.5, 0.5 },
        .clr_diffuse = .{ 0.7, 0.7, 0.7 },
        .clr_specular = .{ 0.3, 0.3, 0.3 },
        .specular_exp = 10,
    });
}

pub fn createDefaultTexture(self: *Self) !*SurfaceTexture {
    const key = "default";
    const surf: Surface = try .init(.{ 1, 1 }, .default);
    assert(surf.pitch() == @sizeOf(u32));
    surf.slice(u32)[0] = c.SDL_MapSurfaceRGBA(surf.ptr, 0xff, 0x00, 0xff, 0xff);

    const tex = try self.surface_textures.insert(key, .init(surf));
    try self.flagModified(.surface_texture, key);
    return tex;
}

pub fn createLightsBuffer(self: *Self, scene: *const Scene, flat: *const Scene.Flattened) !*GPUBuffer {
    const key = "lights";
    const gpa = self.renderer.allocator;
    const old_buf = self.renderer.storage_bufs.getPtrOrNull(key);
    const lights_buf = old_buf orelse try self.renderer.createStorageBuffer(key);
    try self.flagModified(.storage_buffer, key);
    lights_buf.freeCPUBuffer(gpa);

    const lights = flat.getPtrConst(.light).slice();
    for (lights.items(.target)) |target| {
        const light = scene.lights.getPtr(target);
        if (light.type == .ambient) {
            log.debug("ambient: {any}", .{light.src});
            var color = math.rgbu8.to(math.Scalar, &light.src.color);
            math.rgbf32.scaleRecip(&color, 255);
            try lights_buf.append(gpa, math.RGBf32, &.{color});
            try lights_buf.append(gpa, f32, &.{light.src.intensity});
        }
    }
    for (lights.items(.target), lights.items(.transform)) |target, *tr| {
        const light = scene.lights.getPtr(target);
        if (light.type == .directional) {
            var color = math.rgbu8.to(math.Scalar, &light.src.color);
            const direction = math.vector4.ntr_fwd;
            var tr_direction: math.Vector4 = undefined;
            math.rgbf32.scaleRecip(&color, 255);
            math.matrix4x4.apply(&tr_direction, tr, &direction);
            log.debug("directional: {any} {any}", .{ light.src, tr_direction });
            try lights_buf.append(gpa, math.Vector4, &.{tr_direction});
            try lights_buf.append(gpa, math.RGBf32, &.{color});
            try lights_buf.append(gpa, f32, &.{light.src.intensity});
        }
    }
    for (lights.items(.target), lights.items(.transform)) |target, *tr| {
        const light = scene.lights.getPtr(target);
        if (light.type == .point) {
            var color = math.rgbu8.to(math.Scalar, &light.src.color);
            const pos = math.vector4.tr_zero;
            var tr_pos: math.Vector4 = undefined;
            math.rgbf32.scaleRecip(&color, 255);
            math.matrix4x4.apply(&tr_pos, tr, &pos);
            log.debug("point: {any} {any}", .{ light.src, tr_pos });
            try lights_buf.append(gpa, math.Vector4, &.{tr_pos});
            try lights_buf.append(gpa, math.RGBf32, &.{color});
            try lights_buf.append(gpa, f32, &.{light.src.intensity});
        }
    }

    return lights_buf;
}

fn createGPUData(self: *Self) InitError!void {
    const gpu_device = self.renderer.gpu_device;
    for (self.modifs.getPtrConst(.mesh_buffer).items) |key| {
        const mesh = self.renderer.mesh_bufs.getPtr(key);
        try mesh.createGPUBuffers(gpu_device);
    }
    for (self.modifs.getPtrConst(.storage_buffer).items) |key| {
        const buf = self.renderer.storage_bufs.getPtr(key);
        try buf.createGPUBuffer(gpu_device, .init(.{ .graphics_storage_read = true }));
    }
    for (self.modifs.getPtrConst(.surface_texture).items) |key| {
        const tex = self.surface_textures.getPtr(key);
        try tex.createGPUTexture(gpu_device);
    }
}

fn uploadTransferBuffers(self: *Self) InitError!void {
    const gpu_device = self.renderer.gpu_device;
    const gpa = self.renderer.allocator;

    var tb: UploadTransferBuffer = .empty;
    defer tb.deinit(gpa, gpu_device);

    try tb.gpu_bufs.ensureUnusedCapacity(gpa, self.modifs.getPtrConst(.mesh_buffer).items.len * 2);
    try tb.gpu_bufs.ensureUnusedCapacity(gpa, self.modifs.getPtrConst(.storage_buffer).items.len);
    try tb.surf_texes.ensureUnusedCapacity(gpa, self.modifs.getPtrConst(.surface_texture).items.len);

    for (self.modifs.getPtrConst(.mesh_buffer).items) |key| {
        const mesh = self.renderer.mesh_bufs.getPtr(key);
        tb.gpu_bufs.appendAssumeCapacity(mesh.gpu_bufs.getPtrConst(.vertex));
        if (mesh.type == .index) tb.gpu_bufs.appendAssumeCapacity(mesh.gpu_bufs.getPtrConst(.index));
    }
    for (self.modifs.getPtrConst(.storage_buffer).items) |key| {
        const buf = self.renderer.storage_bufs.getPtr(key);
        tb.gpu_bufs.appendAssumeCapacity(buf);
    }
    for (self.modifs.getPtrConst(.surface_texture).items) |key| {
        const surf_tex = self.surface_textures.getPtr(key);
        tb.surf_texes.appendAssumeCapacity(surf_tex);
    }

    try tb.createGPUTransferBuffer(gpu_device);
    try tb.map(gpu_device);

    const command_buffer = c.SDL_AcquireGPUCommandBuffer(gpu_device);
    if (command_buffer == null) {
        log.err("failed to acquire gpu command buffer: {s}", .{c.SDL_GetError()});
        return InitError.CommandBufferFailed;
    }
    errdefer _ = c.SDL_CancelGPUCommandBuffer(command_buffer);

    {
        const copy_pass = c.SDL_BeginGPUCopyPass(command_buffer);
        if (copy_pass == null) {
            log.err("failed to begin copy pass: {s}", .{c.SDL_GetError()});
            return InitError.CopyPassFailed;
        }

        tb.upload(copy_pass);
        c.SDL_EndGPUCopyPass(copy_pass);
    }

    if (!c.SDL_SubmitGPUCommandBuffer(command_buffer)) {
        log.err("failed submitting command buffer: {s}", .{c.SDL_GetError()});
        return InitError.CommandBufferFailed;
    }
}

fn commitSurfaceTextures(self: *Self) InitError!void {
    for (self.modifs.getPtrConst(.surface_texture).items) |key| {
        const tex = self.surface_textures.getPtr(key);
        _ = try self.renderer.insertTexture(key, tex.toOwnedGPUTexture());
    }
}
