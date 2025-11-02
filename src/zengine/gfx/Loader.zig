//!
//! The zengine gfx loader module
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const ArrayPoolMap = @import("../containers.zig").ArrayPoolMap;
const ecs = @import("../ecs.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const perf = @import("../perf.zig");
const str = @import("../str.zig");
const ui_mod = @import("../ui.zig");
const Error = @import("Error.zig").Error;
const GPUBuffer = @import("GPUBuffer.zig");
const img_loader = @import("img_loader.zig");
const lgh_loader = @import("lgh_loader.zig");
const MaterialInfo = @import("MaterialInfo.zig");
const MeshBuffer = @import("MeshBuffer.zig");
const MeshObject = @import("MeshObject.zig");
const mtl_loader = @import("mtl_loader.zig");
const obj_loader = @import("obj_loader.zig");
const Renderer = @import("Renderer.zig");
const Scene = @import("Scene.zig");
const Surface = @import("Surface.zig");
const SurfaceTexture = @import("SurfaceTexture.zig");
const UploadTransferBuffer = @import("UploadTransferBuffer.zig");

const log = std.log.scoped(.gfx_loader);

pub const Target = enum {
    mesh_buffer,
    storage_buffer,
    surface_texture,
};

renderer: *Renderer,
surface_textures: SurfaceTextures,
modifs: std.EnumArray(Target, std.ArrayList([]const u8)),

const Self = @This();
const SurfaceTextures = ArrayPoolMap(SurfaceTexture, .{});

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
}

pub fn commit(self: *Self) !void {
    try self.createGPUData();
    try self.uploadTransferBuffers();
    try self.commitSurfaceTextures();
    self.cancel();
}

pub fn flagModified(self: *Self, comptime target: Target, key: []const u8) !void {
    return self.modifs.getPtr(target).append(self.renderer.allocator, key);
}

pub fn loadMesh(self: *Self, asset_path: []const u8) !*MeshBuffer {
    const mesh_path = try global.assetPath(asset_path);

    var result = obj_loader.loadFile(self.renderer.allocator, mesh_path) catch |err| {
        log.err("failed loading mesh obj file: {t}", .{err});
        return Error.BufferFailed;
    };
    errdefer {
        result.mesh_buf.deinit(self.renderer.allocator);
        result.deinit();
    }

    if (result.mtl_path) |mtl_path| try self.loadMaterials(mtl_path);
    const mesh_bufs: MeshObject.MeshBuffers = .init(.{
        .mesh = try self.renderer.insertMeshBuffer(asset_path, &.fromCPUBuffer(&result.mesh_buf)),
        .tex_coords = try self.createTexCoordIndicators(asset_path),
        .normals = try self.createNormalIndicators(asset_path),
        .tangents = try self.createTangentIndicators(asset_path),
        .binormals = try self.createBinormalIndicators(asset_path),
    });

    var iter = result.mesh_objs.iterator();
    while (iter.next()) |e| {
        const mesh_obj = e.value_ptr;
        mesh_obj.mesh_bufs = mesh_bufs;
        _ = try self.renderer.insertMeshObject(e.key_ptr.*, mesh_obj);
    }

    result.cleanup();
    try self.flagModified(.mesh_buffer, asset_path);
    return mesh_bufs.get(.mesh);
}

pub fn loadMaterials(self: *Self, asset_path: []const u8) !void {
    const mtl_path = try global.assetPath(asset_path);
    var mtl = mtl_loader.loadFile(self.renderer.allocator, mtl_path) catch |err| {
        log.err("Error loading material: {t}", .{err});
        return Error.MaterialFailed;
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

pub fn loadLights(self: *Self, asset_path: []const u8) !void {
    const lgh_path = try global.assetPath(asset_path);
    var lgh = lgh_loader.loadFile(self.renderer.allocator, lgh_path) catch |err| {
        log.err("Error loading lights: {t}", .{err});
        return Error.LightFailed;
    };
    defer lgh.deinit();

    for (lgh.items) |*item| _ = try self.renderer.insertLight(item.name, item);
}

pub fn loadTexture(self: *Self, asset_path: []const u8) !*SurfaceTexture {
    if (self.surface_textures.getPtrOrNull(asset_path)) |ptr| return ptr;

    const tex_path = try global.assetPath(asset_path);
    const surface = img_loader.loadFile(&.{
        .allocator = self.renderer.allocator,
        .gpu_device = self.renderer.gpu_device,
        .file_path = tex_path,
    }) catch |err| {
        log.err("failed reading image file: {t}", .{err});
        return Error.TextureFailed;
    };

    try surface.flip(.vertical);
    var texture: SurfaceTexture = .init(surface);
    errdefer texture.deinit(self.renderer.gpu_device);

    const tex = try self.surface_textures.insert(asset_path, texture);
    try self.flagModified(.surface_texture, asset_path);
    return tex;
}

pub fn createOriginMesh(self: *Self) !*MeshBuffer {
    const origin_mesh = try self.renderer.createMeshBuffer("origin", .index);

    origin_mesh.appendSlice(self.renderer.allocator, .vertex, math.Vector3, 1, &.{
        .{ 0, 0, 0 },
        .{ 1, 0, 0 },
        .{ 0, 1, 0 },
        .{ 0, 0, 1 },
    }) catch |err| {
        log.err("failed appending origin mesh vertices: {t}", .{err});
        return Error.BufferFailed;
    };

    origin_mesh.appendSlice(self.renderer.allocator, .index, math.LineFaceIndex, 2, &.{
        .{ 0, 1 },
        .{ 0, 2 },
        .{ 0, 3 },
    }) catch |err| {
        log.err("failed appending origin mesh faces: {t}", .{err});
        return Error.BufferFailed;
    };

    try self.flagModified(.mesh_buffer, "origin");
    return origin_mesh;
}

pub fn createIndicators(
    self: *Self,
    key: []const u8,
    comptime suffix: [:0]const u8,
    comptime attr: math.VertexAttr,
) !*MeshBuffer {
    const new_key = try str.join(&.{ key, "." ++ suffix });
    const mesh = self.renderer.mesh_bufs.getPtr(key);
    assert(mesh.type == .vertex);
    const scalars = mesh.slice(.vertex);
    const verts: []math.Vertex = @ptrCast(scalars);

    const result = try self.renderer.createMeshBuffer(new_key, .vertex);

    try result.ensureUnusedCapacity(self.renderer.allocator, .vertex, math.Vector3, 2 * verts.len);
    for (verts) |*_vert| {
        const vert = math.vertex.cmap(_vert);
        var dest = vert.get(.position);
        math.vector3.add(&dest, vert.getPtrConst(attr));
        result.appendSliceAssumeCapacity(.vertex, math.Vector3, 1, &.{ vert.get(.position), dest });
    }

    try self.flagModified(.mesh_buffer, new_key);
    return result;
}

pub fn createTexCoordIndicators(self: *Self, key: []const u8) !*MeshBuffer {
    return self.createIndicators(key, "tex_coords", .tex_coord);
}

pub fn createNormalIndicators(self: *Self, key: []const u8) !*MeshBuffer {
    return self.createIndicators(key, "normals", .normal);
}

pub fn createTangentIndicators(self: *Self, key: []const u8) !*MeshBuffer {
    return self.createIndicators(key, "tangents", .tangent);
}

pub fn createBinormalIndicators(self: *Self, key: []const u8) !*MeshBuffer {
    return self.createIndicators(key, "binormals", .binormal);
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

pub fn createLightsBuffer(self: *Self, flat: ?*const Scene.Flattened) !*MeshBuffer {
    const key = "lights";
    const gpa = self.renderer.allocator;
    const lights_buf = try self.renderer.getOrCreateStorageBuffer(key);

    lights_buf.clearCPUBuffers();

    if (flat == null) return lights_buf;
    assert(self.renderer == flat.?.scene.renderer);

    const lights = flat.?.lights.slice();

    for (lights.items(.target)) |light| {
        if (light.type == .ambient) {
            log.debug("ambient: {any}", .{light.src});
            try lights_buf.append(gpa, .vertex, math.RGBf32, 0, &light.src.color);
            try lights_buf.append(gpa, .vertex, f32, 0, &light.src.power);
        }
    }

    for (lights.items(.target), lights.items(.transform)) |light, *tr| {
        if (light.type == .directional) {
            const direction = math.vector4.ntr_fwd;
            var tr_direction: math.Vector4 = undefined;
            math.matrix4x4.apply(&tr_direction, tr, &direction);
            log.debug("directional: {any} {any}", .{ light.src, tr_direction });
            try lights_buf.append(gpa, .vertex, math.Vector4, 0, &tr_direction);
            try lights_buf.append(gpa, .vertex, math.RGBf32, 0, &light.src.color);
            try lights_buf.append(gpa, .vertex, f32, 0, &light.src.power);
        }
    }

    for (lights.items(.target), lights.items(.transform)) |light, *tr| {
        if (light.type == .point) {
            const pos = math.vector4.tr_zero;
            var tr_pos: math.Vector4 = undefined;
            math.matrix4x4.apply(&tr_pos, tr, &pos);
            log.debug("point: {any} {any}", .{ light.src, tr_pos });
            try lights_buf.append(gpa, .vertex, math.Vector4, 0, &tr_pos);
            try lights_buf.append(gpa, .vertex, math.RGBf32, 0, &light.src.color);
            try lights_buf.append(gpa, .vertex, f32, 0, &light.src.power);
        }
    }

    try self.flagModified(.storage_buffer, key);
    return lights_buf;
}

fn createGPUData(self: *Self) !void {
    const gpu_device = self.renderer.gpu_device;

    for (self.modifs.getPtrConst(.mesh_buffer).items) |key| {
        const mesh = self.renderer.mesh_bufs.getPtr(key);
        try mesh.createGPUBuffers(gpu_device, null);
    }

    for (self.modifs.getPtrConst(.storage_buffer).items) |key| {
        const buf = self.renderer.storage_bufs.getPtr(key);
        try buf.createGPUBuffers(gpu_device, .initOne(.graphics_storage_read));
    }

    for (self.modifs.getPtrConst(.surface_texture).items) |key| {
        const tex = self.surface_textures.getPtr(key);
        try tex.createGPUTexture(gpu_device);
    }
}

fn uploadTransferBuffers(self: *Self) !void {
    const gpu_device = self.renderer.gpu_device;
    const gpa = self.renderer.allocator;

    var tb: UploadTransferBuffer = .empty;
    defer tb.deinit(gpa, gpu_device);

    try tb.mesh_bufs.ensureUnusedCapacity(gpa, self.modifs.getPtrConst(.mesh_buffer).items.len);
    try tb.mesh_bufs.ensureUnusedCapacity(gpa, self.modifs.getPtrConst(.storage_buffer).items.len);
    try tb.surf_texes.ensureUnusedCapacity(gpa, self.modifs.getPtrConst(.surface_texture).items.len);

    for (self.modifs.getPtrConst(.mesh_buffer).items) |key| {
        const buf = self.renderer.mesh_bufs.getPtr(key);
        try buf.gpu_bufs.getPtr(.vertex).resize(gpu_device, &.{
            .size = buf.byteLen(.vertex),
            .usage = .initOne(.vertex),
        });
        if (buf.type == .index) {
            try buf.gpu_bufs.getPtr(.index).resize(gpu_device, &.{
                .size = buf.byteLen(.index),
                .usage = .initOne(.index),
            });
        }
        tb.mesh_bufs.appendAssumeCapacity(buf);
    }

    for (self.modifs.getPtrConst(.storage_buffer).items) |key| {
        const buf = self.renderer.storage_bufs.getPtr(key);
        try buf.gpu_bufs.getPtr(.vertex).resize(gpu_device, &.{
            .size = buf.byteLen(.vertex),
            .usage = .initOne(.graphics_storage_read),
        });
        tb.mesh_bufs.appendAssumeCapacity(buf);
    }

    for (self.modifs.getPtrConst(.surface_texture).items) |key| {
        const surf_tex = self.surface_textures.getPtr(key);
        tb.surf_texes.appendAssumeCapacity(surf_tex);
    }

    try tb.createGPUTransferBuffer(gpu_device);
    try tb.map(gpu_device);

    var command_buffer = try gpu_device.commandBuffer();
    errdefer command_buffer.cancel() catch {};

    {
        var copy_pass = try command_buffer.copyPass();
        tb.upload(copy_pass);
        copy_pass.end();
    }

    try command_buffer.submit();
}

fn commitSurfaceTextures(self: *Self) !void {
    for (self.modifs.getPtrConst(.surface_texture).items) |key| {
        const tex = self.surface_textures.getPtr(key);
        _ = try self.renderer.insertTexture(key, tex.toOwnedGPUTexture());
    }
}
