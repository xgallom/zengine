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
const StorageBuffer = @import("StorageBuffer.zig");
const Scene = @import("../Scene.zig");
const Texture = @import("Texture.zig");

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
const SurfaceTextures = KeyMap(Texture, .{});

pub fn init(renderer: *Renderer) !Self {
    return .{
        .renderer = renderer,
        .surface_textures = try .init(renderer.allocator, 128),
        .modifs = .initDefault(.empty, .{}),
    };
}

pub fn deinit(self: *Self) void {
    const allocator = self.renderer.allocator;
    const gpu_device = self.renderer.gpu_device;

    for (self.renderer.mesh_bufs.map.values()) |mesh_buf| mesh_buf.freeCpuData();
    for (self.renderer.storage_bufs.map.values()) |buf| buf.freeCpuData();
    for (self.surface_textures.map.values()) |tex| tex.deinit(gpu_device);
    self.surface_textures.deinit();

    assert(self.modifs.getPtrConst(.mesh_buffer).items.len == 0);
    assert(self.modifs.getPtrConst(.storage_buffer).items.len == 0);
    assert(self.modifs.getPtrConst(.surface_texture).items.len == 0);
    self.modifs.getPtr(.mesh_buffer).deinit(allocator);
    self.modifs.getPtr(.storage_buffer).deinit(allocator);
    self.modifs.getPtr(.surface_texture).deinit(allocator);
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
        result.mesh_buf.deinit(self.renderer.gpu_device);
        result.deinit(self.renderer.allocator);
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

    result.cleanup(self.renderer.allocator);
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

pub fn loadTexture(self: *Self, asset_path: []const u8) !*Texture {
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
    var texture: Texture = .init(surface);
    errdefer texture.deinit(self.renderer.gpu_device);
    try self.flagModified(.surface_texture, asset_path);
    return self.surface_textures.insert(asset_path, &texture);
}

pub fn createOriginMesh(self: *Self) !*MeshBuffer {
    const origin_mesh = try self.renderer.createMeshBuffer("origin", .index);
    try self.flagModified(.mesh_buffer, "origin");

    origin_mesh.appendVertices(math.Vertex, &.{
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
    origin_mesh.vert_count = 4 * 3;
    origin_mesh.appendIndexes(math.LineFaceIndex, &.{
        .{ 0, 1 },
        .{ 0, 2 },
        .{ 0, 3 },
    }) catch |err| {
        log.err("failed appending origin mesh faces: {t}", .{err});
        return InitError.BufferFailed;
    };
    origin_mesh.index_count = 6;

    return origin_mesh;
}

pub fn createDefaultMaterial(self: *Self) !*MaterialInfo {
    return self.renderer.createMaterial("default");
}

pub fn createTestingMaterial(self: *Self) !*MaterialInfo {
    return self.renderer.insertMaterial("testing", &.{
        .name = "testing",
        .clr_ambient = .{ 0.5, 0.5, 0.5 },
        .clr_diffuse = .{ 0.5, 0.5, 0.5 },
        .clr_specular = .{ 0.5, 0.5, 0.5 },
        .specular_exp = 10,
    });
}

pub fn createDefaultTexture(self: *Self) !*Texture {
    const surface = c.SDL_CreateSurface(1, 1, img.pixel_format);
    if (surface == null) {
        log.err("failed creating default texture surface: {s}", .{c.SDL_GetError()});
        return InitError.TextureFailed;
    }
    const pixel = c.SDL_MapSurfaceRGBA(surface, 0xff, 0x00, 0xff, 0xff);
    assert(surface.*.pitch == @sizeOf(@TypeOf(pixel)));
    const pixels: [*]u32 = @ptrCast(@alignCast(surface.*.pixels));
    pixels[0] = pixel;

    const texture = try self.surface_textures.create("default");
    texture.* = .init(surface);
    try self.flagModified(.surface_texture, "default");
    return texture;
}

pub fn createLightsBuffer(self: *Self, scene: *const Scene) !*StorageBuffer {
    const key = "lights";
    const old_buf = self.renderer.storage_bufs.getPtrOrNull(key);
    const lights_buf = old_buf orelse try self.renderer.createStorageBuffer(key);
    try self.flagModified(.storage_buffer, key);
    lights_buf.clearCpuData();

    {
        var iter = scene.lights.valueIterator();
        while (iter.next()) |light| {
            if (light.* == .ambient) {
                const l = &light.ambient;
                var color = math.rgbu8.to(math.Scalar, &l.light.color);
                math.rgbf32.scaleRecip(&color, 255);
                try lights_buf.append(math.RGBf32, &.{color});
                try lights_buf.append(f32, &.{l.light.intensity});
            }
        }
    }
    {
        var iter = scene.lights.valueIterator();
        while (iter.next()) |light| {
            if (light.* == .point) {
                const l = &light.point;
                var color = math.rgbu8.to(math.Scalar, &l.light.color);
                math.rgbf32.scaleRecip(&color, 255);
                try lights_buf.append(math.Vertex, &.{l.position});
                try lights_buf.append(f32, &.{0});
                try lights_buf.append(math.RGBf32, &.{color});
                try lights_buf.append(f32, &.{l.light.intensity});
            }
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
        try buf.createGPUBuffers(gpu_device);
    }
    for (self.modifs.getPtrConst(.surface_texture).items) |key| {
        const tex = self.surface_textures.getPtr(key);
        try tex.createTexture(gpu_device);
    }
}

fn uploadTransferBuffers(self: *Self) InitError!void {
    const MeshTransferBuffers = std.ArrayList(MeshBuffer.UploadTransferBuffer);
    const StorageTransferBuffers = std.ArrayList(StorageBuffer.UploadTransferBuffer);
    const TextureTransferBuffers = std.ArrayList(Texture.UploadTransferBuffer);

    const gpu_device = self.renderer.gpu_device;
    const allocator = self.renderer.allocator;

    var mesh_tbs: MeshTransferBuffers = try .initCapacity(
        allocator,
        self.modifs.getPtrConst(.mesh_buffer).items.len,
    );
    defer {
        for (mesh_tbs.items) |*tb| tb.release(gpu_device);
        mesh_tbs.deinit(allocator);
    }

    var storage_tbs: StorageTransferBuffers = try .initCapacity(
        allocator,
        self.modifs.getPtrConst(.storage_buffer).items.len,
    );
    defer {
        for (storage_tbs.items) |*tb| tb.release(gpu_device);
        storage_tbs.deinit(allocator);
    }

    var tex_tbs: TextureTransferBuffers = try .initCapacity(
        allocator,
        self.modifs.getPtrConst(.surface_texture).items.len,
    );
    defer {
        for (tex_tbs.items) |*tb| tb.release(gpu_device);
        tex_tbs.deinit(allocator);
    }

    for (self.modifs.getPtrConst(.mesh_buffer).items) |key| {
        const mesh = self.renderer.mesh_bufs.getPtr(key);
        const tb = try mesh.createUploadTransferBuffer(gpu_device);
        mesh_tbs.appendAssumeCapacity(tb);
    }
    for (self.modifs.getPtrConst(.storage_buffer).items) |key| {
        const buf = self.renderer.storage_bufs.getPtr(key);
        const tb = try buf.createUploadTransferBuffer(gpu_device);
        storage_tbs.appendAssumeCapacity(tb);
    }
    for (self.modifs.getPtrConst(.surface_texture).items) |key| {
        const tex = self.surface_textures.getPtr(key);
        const tb = try tex.createUploadTransferBuffer(gpu_device);
        tex_tbs.appendAssumeCapacity(tb);
    }

    for (mesh_tbs.items) |*tb| try tb.map(gpu_device);
    for (storage_tbs.items) |*tb| try tb.map(gpu_device);
    for (tex_tbs.items) |*tb| try tb.map(gpu_device);

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

        for (mesh_tbs.items) |*tb| tb.upload(copy_pass);
        for (storage_tbs.items) |*tb| tb.upload(copy_pass);
        for (tex_tbs.items) |*tb| tb.upload(copy_pass);

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
        _ = try self.renderer.insertTexture(key, tex.toTextureOwned());
    }
}
