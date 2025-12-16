//!
//! The zengine gfx loader module
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const ArrayMap = @import("../containers.zig").ArrayMap;
const ArrayPoolMap = @import("../containers.zig").ArrayPoolMap;
const ecs = @import("../ecs.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const perf = @import("../perf.zig");
const str = @import("../str.zig");
const ui_mod = @import("../ui.zig");
const cube_loader = @import("cube_loader.zig");
const Error = @import("error.zig").Error;
const GPUBuffer = @import("GPUBuffer.zig");
const GPUFence = @import("GPUFence.zig");
const GPUGraphicsPipeline = @import("GPUGraphicsPipeline.zig");
const GPUShader = @import("GPUShader.zig");
const img_loader = @import("img_loader.zig");
const lgh_loader = @import("lgh_loader.zig");
const LookUpTable = @import("LookUpTable.zig");
const MaterialInfo = @import("MaterialInfo.zig");
const mesh = @import("mesh.zig");
const mtl_loader = @import("mtl_loader.zig");
const obj_loader = @import("obj_loader.zig");
const Renderer = @import("Renderer.zig");
const Scene = @import("Scene.zig");
const shader_loader = @import("shader_loader.zig");
const Surface = @import("Surface.zig");
const SurfaceTexture = @import("SurfaceTexture.zig");
const ttf = @import("ttf.zig");
const ttf_loader = @import("ttf_loader.zig");
const UploadTransferBuffer = @import("UploadTransferBuffer.zig");

const log = std.log.scoped(.gfx_loader);

pub const Target = enum {
    mesh_buffer,
    storage_buffer,
    surface_texture,
    look_up_table,
};

renderer: *Renderer,
fonts: Fonts,
surface_textures: SurfaceTextures,
look_up_tables: LookUpTables,
modifs: std.EnumArray(Target, std.ArrayList([]const u8)),

const Self = @This();
const Fonts = ArrayMap(ttf.Font);
const SurfaceTextures = ArrayPoolMap(SurfaceTexture, .{});
const LookUpTables = ArrayPoolMap(LookUpTable, .{});

pub fn init(renderer: *Renderer) !Self {
    return .{
        .renderer = renderer,
        .fonts = try .init(renderer.allocator, 128),
        .surface_textures = try .init(renderer.allocator, 128),
        .look_up_tables = try .init(renderer.allocator, 128),
        .modifs = .initFill(.empty),
    };
}

pub fn deinit(self: *Self) void {
    const gpa = self.renderer.allocator;
    const gpu_device = self.renderer.gpu_device;

    for (self.fonts.values()) |*font| font.deinit();
    self.fonts.deinit(self.renderer.allocator);
    for (self.surface_textures.map.values()) |tex| tex.deinit(gpu_device);
    self.surface_textures.deinit();
    for (self.look_up_tables.map.values()) |tex| tex.deinit(self.renderer.allocator, self.renderer.gpu_device);
    self.look_up_tables.deinit();

    assert(self.modifs.getPtrConst(.mesh_buffer).items.len == 0);
    assert(self.modifs.getPtrConst(.storage_buffer).items.len == 0);
    assert(self.modifs.getPtrConst(.surface_texture).items.len == 0);
    assert(self.modifs.getPtrConst(.look_up_table).items.len == 0);
    self.modifs.getPtr(.mesh_buffer).deinit(gpa);
    self.modifs.getPtr(.storage_buffer).deinit(gpa);
    self.modifs.getPtr(.surface_texture).deinit(gpa);
    self.modifs.getPtr(.look_up_table).deinit(gpa);
}

pub fn cancel(self: *Self) void {
    self.modifs.getPtr(.mesh_buffer).clearRetainingCapacity();
    self.modifs.getPtr(.storage_buffer).clearRetainingCapacity();
    self.modifs.getPtr(.surface_texture).clearRetainingCapacity();
    self.modifs.getPtr(.look_up_table).clearRetainingCapacity();
}

pub fn commit(self: *Self) !GPUFence {
    try self.createGPUData();
    var fence = try self.uploadTransferBuffers();
    errdefer self.renderer.gpu_device.release(&fence);
    try self.commitSurfaceTextures();
    try self.commitLookUpTables();
    self.cancel();
    return fence;
}

pub fn flagModified(self: *Self, comptime target: Target, key: []const u8) !void {
    return self.modifs.getPtr(target).append(self.renderer.allocator, key);
}

pub fn loadShader(self: *Self, comptime stage: GPUShader.Stage, asset_path: []const u8) !GPUShader {
    log.debug("loading shader {s}", .{asset_path});
    var shader = shader_loader.loadFile(&.{
        .allocator = self.renderer.allocator,
        .gpu_device = self.renderer.gpu_device,
        .shader_path = asset_path,
        .stage = stage,
    }) catch |err| {
        log.err("failed creating {t} shader \"{s}\": {t}", .{ stage, asset_path, err });
        return Error.ShaderFailed;
    };
    assert(shader.isValid());
    errdefer shader.deinit(self.renderer.gpu_device);
    return self.renderer.insertShader(asset_path, shader.ptr.?);
}

pub fn loadImage(self: *Self, asset_path: [:0]const u8) !*mesh.Buffer {
    log.debug("loading image {s}", .{asset_path});
    _ = try self.loadTexture(asset_path);
    const mtl = try self.renderer.createMaterial(asset_path);
    mtl.texture = asset_path;
    mtl.diffuse_map = asset_path;
    const buf = try self.createRectangle(asset_path);
    const mesh_obj = try self.renderer.createMeshObject(asset_path, .triangle);
    mesh_obj.mesh_bufs.set(.mesh, buf);
    try mesh_obj.beginSection(self.renderer.allocator, 0, asset_path);
    mesh_obj.endSection(buf.vertCount(.index));
    return buf;
}

pub fn loadFont(self: *Self, asset_path: [:0]const u8, size_pts: f32) !ttf.Font {
    log.debug("loading font {s}", .{asset_path});
    const font_path = try global.assetPath(asset_path);
    var result = try ttf_loader.loadFile(&.{
        .allocator = self.renderer.allocator,
        .file_path = font_path,
        .size_pts = size_pts,
    });
    errdefer result.deinit();
    _ = try self.fonts.insert(self.renderer.allocator, asset_path, result);
    return result;
}

pub fn loadMesh(self: *Self, asset_path: []const u8) !*mesh.Buffer {
    log.debug("loading mesh {s}", .{asset_path});
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
    const mesh_buf = try self.renderer.insertMeshBuffer(asset_path, &.fromCPUBuffer(&result.mesh_buf));
    const mesh_bufs: mesh.Object.Buffers = .init(.{
        .mesh = mesh_buf,
        .tex_coords_u = try self.createTexCoordUIndicators(asset_path),
        .tex_coords_v = try self.createTexCoordVIndicators(asset_path),
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
        if (item.texture) |tex_path| {
            const tex = try self.loadTexture(tex_path);
            try tex.properties().put(.bool, "is_sRGB", true);
        }
        if (item.diffuse_map) |tex_path| {
            const tex = try self.loadTexture(tex_path);
            try tex.properties().put(.bool, "is_sRGB", true);
        }
        if (item.bump_map) |tex_path| _ = try self.loadTexture(tex_path);
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
    _ = try tex.createProperties();
    try self.flagModified(.surface_texture, asset_path);
    return tex;
}

pub fn unloadTexture(self: *Self, key: []const u8) void {
    const tex = self.surface_textures.getPtr(key);
    tex.destroyProperties();
    tex.deinit(self.renderer.gpu_device);
    self.surface_textures.remove(key);
}

pub fn loadLut(self: *Self, asset_path: []const u8) !*LookUpTable {
    if (self.look_up_tables.getPtrOrNull(asset_path)) |ptr| return ptr;

    const tex_path = try global.assetPath(asset_path);
    var cube = cube_loader.loadFile(self.renderer.allocator, tex_path) catch |err| {
        log.err("failed reading cube file: {t}", .{err});
        return Error.TextureFailed;
    };
    errdefer cube.deinit(self.renderer.allocator, self.renderer.gpu_device);

    const lut = try self.look_up_tables.insert(asset_path, &cube);
    try self.flagModified(.look_up_table, asset_path);
    return lut;
}

pub fn createGraphicsPipelines(self: *Self) !void {
    const screen_vert = try self.loadShader(.vertex, "system/screen.vert");
    const position_vert = try self.loadShader(.vertex, "system/position.vert");
    const vertex_vert = try self.loadShader(.vertex, "system/vertex.vert");

    const color_frag = try self.loadShader(.fragment, "system/color.frag");
    const material_frag = try self.loadShader(.fragment, "system/material.frag");
    // const image_frag = try self.loadShader(.fragment, "system/image.frag");
    const blend_frag = try self.loadShader(.fragment, "system/blend.frag");
    const render_frag = try self.loadShader(.fragment, "system/render.frag");

    log.info("swapchain format: {t}", .{self.renderer.swapchainFormat()});
    var pipeline: GPUGraphicsPipeline.CreateInfo = .{
        .target_info = .{
            .color_target_descriptions = &.{
                .{ .format = self.renderer.swapchainFormat(), .blend_state = .blend },
            },
        },
    };

    pipeline.vertex_shader = screen_vert;
    pipeline.fragment_shader = blend_frag;
    _ = try self.renderer.createGraphicsPipeline("blend", &pipeline);

    pipeline.vertex_shader = screen_vert;
    pipeline.fragment_shader = render_frag;
    _ = try self.renderer.createGraphicsPipeline("render", &pipeline);

    pipeline.rasterizer_state.enable_depth_clip = true;
    pipeline.depth_stencil_state = .depth_test_and_write;
    pipeline.target_info = .{
        .color_target_descriptions = &.{
            .{ .format = .hdr_f, .blend_state = .blend },
        },
        .has_depth_stencil_target = true,
        .depth_stencil_format = self.renderer.stencil_format,
    };

    pipeline.vertex_shader = position_vert;
    pipeline.fragment_shader = color_frag;
    pipeline.vertex_input_state = .{
        .vertex_buffer_descriptions = &.{
            .{ .slot = 0, .pitch = @sizeOf(math.Vector3), .input_rate = .vertex, .instance_step_rate = 0 },
        },
        .vertex_attributes = &.{
            .{ .location = 0, .buffer_slot = 0, .format = .f32_3, .offset = 0 },
        },
    };
    pipeline.primitive_type = .line_list;
    pipeline.rasterizer_state.fill_mode = .line;
    _ = try self.renderer.createGraphicsPipeline("line", &pipeline);

    pipeline.vertex_shader = vertex_vert;
    pipeline.fragment_shader = material_frag;
    pipeline.vertex_input_state = .{
        .vertex_buffer_descriptions = &.{
            .{ .slot = 0, .pitch = @sizeOf(math.Vertex), .input_rate = .vertex, .instance_step_rate = 0 },
        },
        .vertex_attributes = &.{
            .{ .location = 0, .buffer_slot = 0, .format = .f32_3, .offset = 0 },
            .{ .location = 1, .buffer_slot = 0, .format = .f32_3, .offset = @sizeOf(math.Vector3) },
            .{ .location = 2, .buffer_slot = 0, .format = .f32_3, .offset = 2 * @sizeOf(math.Vector3) },
            .{ .location = 3, .buffer_slot = 0, .format = .f32_3, .offset = 3 * @sizeOf(math.Vector3) },
            .{ .location = 4, .buffer_slot = 0, .format = .f32_3, .offset = 4 * @sizeOf(math.Vector3) },
        },
    };
    pipeline.primitive_type = .triangle_list;
    pipeline.rasterizer_state.fill_mode = .fill;

    _ = try self.renderer.createGraphicsPipeline("ui", &pipeline);

    pipeline.rasterizer_state.front_face = .clockwise;
    pipeline.rasterizer_state.cull_mode = .back;

    _ = try self.renderer.createGraphicsPipeline("material", &pipeline);

    // pipeline.fragment_shader = image_frag;
    // _ = try self.renderer.createGraphicsPipeline("image", &pipeline);
}

pub fn createRectangle(self: *Self, name: []const u8) !*mesh.Buffer {
    const rect = try self.renderer.createMeshBuffer(name, .index);

    rect.appendSlice(self.renderer.allocator, .vertex, math.Vertex, 1, &.{
        .{ .{ -1, -1, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 }, .{ 1, 0, 0 }, .{ 0, -1, 0 } },
        .{ .{ 1, -1, 0 }, .{ 1, 1, 0 }, .{ 0, 0, 1 }, .{ 1, 0, 0 }, .{ 0, -1, 0 } },
        .{ .{ 1, 1, 0 }, .{ 1, 0, 0 }, .{ 0, 0, 1 }, .{ 1, 0, 0 }, .{ 0, -1, 0 } },
        .{ .{ -1, 1, 0 }, .{ 0, 0, 0 }, .{ 0, 0, 1 }, .{ 1, 0, 0 }, .{ 0, -1, 0 } },
    }) catch |err| {
        log.err("failed appending rectangle vertices: {t}", .{err});
        return Error.BufferFailed;
    };

    rect.appendSlice(self.renderer.allocator, .index, math.FaceIndex, 3, &.{
        .{ 0, 1, 2 },
        .{ 0, 2, 3 },
    }) catch |err| {
        log.err("failed appending rectangle faces: {t}", .{err});
        return Error.BufferFailed;
    };

    try self.flagModified(.mesh_buffer, name);
    return rect;
}

pub fn createOriginMesh(self: *Self) !*mesh.Buffer {
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
    comptime components: enum { x, y, z, all },
) !*mesh.Buffer {
    const new_key = try str.join(&.{ key, "." ++ suffix });
    const mesh_buf = self.renderer.mesh_bufs.getPtr(key);
    assert(mesh_buf.type == .vertex);
    const scalars = mesh_buf.slice(.vertex);
    const verts: []math.Vertex = @ptrCast(scalars);

    const result = try self.renderer.createMeshBuffer(new_key, .vertex);

    try result.ensureUnusedCapacity(self.renderer.allocator, .vertex, math.Vector3, 2 * verts.len);
    for (verts) |*_vert| {
        const vert = math.vertex.cmap(_vert);
        const pos = vert.get(.position);
        var dest = pos;
        const offset: math.Vector3 = switch (comptime components) {
            .x => .{ vert.getPtrConst(attr)[0], 0, 0 },
            .y => .{ 0, vert.getPtrConst(attr)[1], 0 },
            .z => .{ 0, 0, vert.getPtrConst(attr)[2] },
            .all => vert.get(attr),
        };
        math.vector3.add(&dest, &offset);
        result.appendSliceAssumeCapacity(.vertex, math.Vector3, 1, &.{ pos, dest });
    }

    try self.flagModified(.mesh_buffer, new_key);
    return result;
}

pub fn createTexCoordUIndicators(self: *Self, key: []const u8) !*mesh.Buffer {
    return self.createIndicators(key, "tex_coords_u", .tex_coord, .x);
}

pub fn createTexCoordVIndicators(self: *Self, key: []const u8) !*mesh.Buffer {
    return self.createIndicators(key, "tex_coords_v", .tex_coord, .y);
}

pub fn createNormalIndicators(self: *Self, key: []const u8) !*mesh.Buffer {
    return self.createIndicators(key, "normals", .normal, .all);
}

pub fn createTangentIndicators(self: *Self, key: []const u8) !*mesh.Buffer {
    return self.createIndicators(key, "tangents", .tangent, .all);
}

pub fn createBinormalIndicators(self: *Self, key: []const u8) !*mesh.Buffer {
    return self.createIndicators(key, "binormals", .binormal, .all);
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

pub fn createSurfaceTexture(
    self: *Self,
    key: []const u8,
    size: math.Point_u32,
    pixel_format: Surface.PixelFormat,
) !*SurfaceTexture {
    const surf: Surface = try .init(size, pixel_format);
    const tex = try self.surface_textures.insert(key, .init(surf));
    _ = try tex.createProperties();
    try self.flagModified(.surface_texture, key);
    return tex;
}

pub fn createDefaultTexture(self: *Self) !*SurfaceTexture {
    const key = "default";
    const surf_tex = try self.createSurfaceTexture(key, .{ 1, 1 }, .default);
    const surf = surf_tex.surf;
    assert(surf.pitch() == @sizeOf(u32));
    surf.slice(u32)[0] = surf.rgba(.{ 255, 255, 255, 255 });
    return surf_tex;
}

pub fn createLightsBuffer(self: *Self, flat: ?*const Scene.Flattened) !*mesh.Buffer {
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

// Takes ownership of an existing texture from renderer
pub fn rendererSurfaceTexture(
    self: *Self,
    key: []const u8,
) !*SurfaceTexture {
    const surf_tex = self.surface_textures.getPtr(key);
    if (!surf_tex.gpu_tex.isValid()) {
        surf_tex.gpu_tex = .fromOwned(self.renderer.textures.getPtr(key).toOwned());
        try self.flagModified(.surface_texture, key);
    }
    return surf_tex;
}

pub fn renderText(self: *Self, font: ttf.Font, text: []const u8, fg: math.RGBAu8) !*SurfaceTexture {
    const surf = try font.renderText(text, fg);
    const surf_tex = try self.surface_textures.insert(text, .init(surf));
    const props = try surf_tex.createProperties();
    try props.put(.bool, "is_sRGB", true);
    try self.flagModified(.surface_texture, text);
    return surf_tex;
}

fn createGPUData(self: *Self) !void {
    const gpu_device = self.renderer.gpu_device;

    for (self.modifs.getPtrConst(.mesh_buffer).items) |key| {
        const mesh_buf = self.renderer.mesh_bufs.getPtr(key);
        try mesh_buf.createGPUBuffers(gpu_device, null);
    }

    for (self.modifs.getPtrConst(.storage_buffer).items) |key| {
        const buf = self.renderer.storage_bufs.getPtr(key);
        try buf.createGPUBuffers(gpu_device, .initOne(.graphics_storage_read));
    }

    for (self.modifs.getPtrConst(.surface_texture).items) |key| {
        const tex = self.surface_textures.getPtr(key);
        if (tex.gpu_tex.isValid()) continue;
        log.debug("create gpu surface texture \"{s}\"", .{key});
        try tex.createGPUTexture(gpu_device);
    }

    for (self.modifs.getPtrConst(.look_up_table).items) |key| {
        const tex = self.look_up_tables.getPtr(key);
        try tex.createGPUTexture(gpu_device);
    }
}

fn uploadTransferBuffers(self: *Self) !GPUFence {
    const gpu_device = self.renderer.gpu_device;
    const gpa = self.renderer.allocator;

    var tb: UploadTransferBuffer = .empty;
    defer tb.deinit(gpa, gpu_device);

    try tb.mesh_bufs.ensureUnusedCapacity(gpa, self.modifs.getPtrConst(.mesh_buffer).items.len);
    try tb.mesh_bufs.ensureUnusedCapacity(gpa, self.modifs.getPtrConst(.storage_buffer).items.len);
    try tb.surf_texes.ensureUnusedCapacity(gpa, self.modifs.getPtrConst(.surface_texture).items.len);
    try tb.luts.ensureUnusedCapacity(gpa, self.modifs.getPtrConst(.look_up_table).items.len);

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
        log.debug("upload surface texture \"{s}\"", .{key});
        const surf_tex = self.surface_textures.getPtr(key);
        tb.surf_texes.appendAssumeCapacity(surf_tex);
    }

    for (self.modifs.getPtrConst(.look_up_table).items) |key| {
        const lut = self.look_up_tables.getPtr(key);
        tb.luts.appendAssumeCapacity(lut);
    }

    try tb.createGPUTransferBuffer(gpu_device);
    log.debug("map transfer buffer {Bi:.3}", .{tb.len});
    try tb.map(gpu_device);

    var command_buffer = try gpu_device.commandBuffer();
    errdefer command_buffer.cancel() catch {};

    {
        var copy_pass = try command_buffer.copyPass();
        tb.upload(copy_pass);
        copy_pass.end();
    }

    return command_buffer.submitFence();
}

// Transfers texture ownership to renderer
fn commitSurfaceTextures(self: *Self) !void {
    for (self.modifs.getPtrConst(.surface_texture).items) |key| {
        const surf_tex = self.surface_textures.getPtr(key);
        if (self.renderer.textures.contains(key)) {
            self.renderer.textures.getPtr(key).* = .fromOwned(surf_tex.toOwnedGPUTexture());
        } else {
            _ = try self.renderer.insertTexture(key, surf_tex.toOwnedGPUTexture());
        }
    }
}

fn commitLookUpTables(self: *Self) !void {
    for (self.modifs.getPtrConst(.look_up_table).items) |key| {
        if (self.renderer.textures.contains(key)) continue;
        const tex = self.look_up_tables.getPtr(key);
        log.info("{s}", .{key});
        _ = try self.renderer.insertTexture(key, tex.toOwnedGPUTexture());
    }
}

pub fn propertyEditorNode(
    self: *Self,
    editor: *ui_mod.PropertyEditorWindow,
    parent: *ui_mod.PropertyEditorWindow.Item,
) !*ui_mod.PropertyEditorWindow.Item {
    const root_id = @typeName(Self);
    const root_node = try editor.appendChildNode(parent, root_id, "Loader");
    {
        const node = try editor.appendChildNode(root_node, root_id ++ ".surface_textures", "Surface Textures");
        var iter = self.surface_textures.map.iterator();
        var buf: [64]u8 = undefined;
        while (iter.next()) |entry| {
            const id = try std.fmt.bufPrint(&buf, "{s}#{s}", .{ @typeName(SurfaceTexture), entry.key_ptr.* });
            _ = try editor.appendChild(
                node,
                try entry.value_ptr.*.propertyEditor(),
                id,
                entry.key_ptr.*,
            );
        }
    }
    return root_node;
}
