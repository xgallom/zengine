//!
//! The zengine renderer implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const ArrayPoolMap = @import("../containers.zig").ArrayPoolMap;
const ArrayMap = @import("../containers.zig").ArrayMap;
const ecs = @import("../ecs.zig");
const Engine = @import("../Engine.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const gfx_options = @import("../options.zig").gfx_options;
const perf = @import("../perf.zig");
const ui_mod = @import("../ui.zig");
const Camera = @import("Camera.zig");
const Error = @import("error.zig").Error;
const GPUBuffer = @import("GPUBuffer.zig");
const GPUDevice = @import("GPUDevice.zig");
const GPUComputePipeline = @import("GPUComputePipeline.zig");
const GPUGraphicsPipeline = @import("GPUGraphicsPipeline.zig");
const GPUSampler = @import("GPUSampler.zig");
const GPUTextEngine = @import("GPUTextEngine.zig");
const GPUTexture = @import("GPUTexture.zig");
const Light = @import("Light.zig");
const MaterialInfo = @import("MaterialInfo.zig");
const mesh = @import("mesh.zig");
const Scene = @import("Scene.zig");
const shader_loader = @import("shader_loader.zig");
const ttf = @import("ttf.zig");
const types = @import("types.zig");

const log = std.log.scoped(.gfx_renderer);
pub const sections = perf.sections(@This(), &.{ .init, .render });

allocator: std.mem.Allocator,
window: Engine.Window,
engine: *const Engine,
gpu_device: GPUDevice,
text_engine: GPUTextEngine,
pipelines: Pipelines,
mesh_objs: MeshObjects,
mesh_bufs: MeshBuffers,
storage_bufs: StorageBuffers,
materials: MaterialInfos,
cameras: Cameras,
lights: Lights,
textures: Textures,
samplers: Samplers,
stencil_format: GPUTexture.Format,
settings: Settings = .{},

const Self = @This();
const Pipelines = struct {
    graphics: GraphicsPipelines,
    compute: ComputePipelines,

    pub const Key = enum {
        graphics,
        compute,
    };

    pub fn getPtr(p: *Pipelines, comptime key: Key) *Type(key) {
        return &@field(p, @tagName(key));
    }

    pub fn getPtrConst(p: *const Pipelines, comptime key: Key) *const Type(key) {
        return &@field(p, @tagName(key));
    }

    pub fn Type(comptime key: Key) type {
        return switch (comptime key) {
            .graphics => GraphicsPipelines,
            .compute => ComputePipelines,
        };
    }
};

const GraphicsPipelines = ArrayMap(GPUGraphicsPipeline);
const ComputePipelines = ArrayMap(GPUComputePipeline);
const MeshObjects = ArrayPoolMap(mesh.Object, .{});
const MeshBuffers = ArrayPoolMap(mesh.Buffer, .{});
const StorageBuffers = ArrayPoolMap(mesh.Buffer, .{});
const MaterialInfos = ArrayPoolMap(MaterialInfo, .{});
const Cameras = ArrayPoolMap(Camera, .{});
const Lights = ArrayPoolMap(Light, .{});
const Textures = ArrayMap(GPUTexture);
const Samplers = ArrayMap(GPUSampler);
const Texts = ArrayMap(ttf.Text);

pub const Item = struct {
    key: [:0]const u8,
    mesh_obj: *mesh.Object,
    transform: *const math.Matrix4x4,

    pub const rotation_speed = 0.1;

    pub fn propertyEditor(self: *Item) ui_mod.UI.Element {
        return ui_mod.PropertyEditor(Item).init(self).element();
    }
};

pub const Items = struct {
    items: Scene.FlatList(mesh.Object).Slice,
    idx: usize = 0,

    pub fn init(flat: *const Scene.Flattened) Items {
        return .{ .items = flat.mesh_objs.slice() };
    }

    pub fn next(self: *Items) ?Item {
        if (self.idx < self.items.len) {
            defer self.idx += 1;
            return .{
                .key = self.items.items(.key)[self.idx],
                .mesh_obj = self.items.items(.target)[self.idx],
                .transform = &self.items.items(.transform)[self.idx],
            };
        }
        return null;
    }

    pub fn reset(self: *Items) void {
        self.idx = 0;
    }
};

pub const Settings = struct {
    camera: [:0]const u8 = "default",
    lut: [:0]const u8 = "lut/basic.cube",
    exposure: f32 = 2,
    exposure_bias: f32 = 0,
    gamma: f32 = 0.75,
    config: packed struct {
        has_agx: bool = true,
        has_lut: bool = true,

        pub fn toInt(config: @This()) u32 {
            var result: u32 = 0;
            if (config.has_agx) result |= 1 << 0;
            if (config.has_lut) result |= 1 << 1;
            return result;
        }
    } = .{},

    pub const exposure_min = 0;
    pub const exposure_max = 100;
    pub const exposure_speed = 0.05;
    pub const exposure_bias_min = 0;
    pub const exposure_bias_max = 100;
    pub const exposure_bias_speed = 0.01;
    pub const gamma_min = 0.1;
    pub const gamma_max = 4;
    pub const gamma_speed = 0.05;

    pub fn uniformBuffer(self: *const Settings) [4]f32 {
        var result: [4]f32 = undefined;
        result[0] = self.exposure;
        result[1] = self.exposure_bias;
        result[2] = self.gamma;
        const ptr_config: *u32 = @ptrCast(&result[3]);
        ptr_config.* = self.config.toInt();
        return result;
    }

    pub fn propertyEditor(self: *@This()) ui_mod.Element {
        return ui_mod.PropertyEditor(@This()).init(self).element();
    }
};

pub fn create(engine: *const Engine) !*Self {
    defer allocators.scratchFree();

    try sections.register();
    try sections.sub(.render)
        .sections(&.{ .acquire, .init, .items, .origin, .ui, .submit })
        .register();

    try Scene.sections.register();

    sections.sub(.init).begin();

    const self = try createSelf(allocators.gpa(), engine);
    errdefer self.deinit();

    if (!self.gpu_device.setAllowedFramesInFlight(3)) {
        log.warn("failed to enable triple-buffering", .{});
    }
    try self.setPresentMode();

    try self.createTextures();
    try self.createSamplers();
    try self.createGraphicsPipelines();

    sections.sub(.init).end();
    return self;
}

pub fn deinit(self: *Self) void {
    _ = c.SDL_WaitForGPUIdle(self.gpu_device.ptr);
    const gpa = self.allocator;
    const gpu_device = self.gpu_device;

    for (self.pipelines.graphics.map.values()) |*pipeline| self.gpu_device.release(pipeline);
    self.pipelines.graphics.deinit(gpa);
    for (self.pipelines.compute.map.values()) |*pipeline| self.gpu_device.release(pipeline);
    self.pipelines.compute.deinit(gpa);
    for (self.mesh_objs.map.values()) |mesh_obj| mesh_obj.deinit(gpa);
    self.mesh_objs.deinit();
    for (self.mesh_bufs.map.values()) |mesh_buf| mesh_buf.deinit(gpa, gpu_device);
    self.mesh_bufs.deinit();
    for (self.storage_bufs.map.values()) |storage_buf| storage_buf.deinit(gpa, gpu_device);
    self.storage_bufs.deinit();

    self.materials.deinit();
    self.cameras.deinit();
    self.lights.deinit();

    for (self.textures.map.values()) |*tex| self.gpu_device.release(tex);
    self.textures.deinit(gpa);
    for (self.samplers.map.values()) |*sampler| self.gpu_device.release(sampler);
    self.samplers.deinit(gpa);

    self.text_engine.deinit();
    self.gpu_device.releaseWindow(self.window);
    self.gpu_device.deinit();
}

pub fn activeCamera(self: *const Self) *Camera {
    return self.cameras.getPtr(self.settings.camera);
}

pub fn swapchainFormat(self: *const Self) GPUTexture.Format {
    return @enumFromInt(c.SDL_GetGPUSwapchainTextureFormat(self.gpu_device.ptr, self.window.ptr));
}

pub fn setPresentMode(self: *Self) !void {
    var present_mode: types.PresentMode = .vsync;
    if (self.gpu_device.supportsPresentMode(self.window, .mailbox)) present_mode = .mailbox;
    try self.gpu_device.setSwapchainParameters(self.window, .HDR_extended_linear, present_mode);
}

fn createSelf(allocator: std.mem.Allocator, engine: *const Engine) !*Self {
    var gpu_device: GPUDevice = try .init(
        .initMany(&.{ .dxil, .spirv, .msl }),
        std.debug.runtime_safety,
        null,
    );
    if (!gpu_device.isValid()) {
        log.err("failed creating gpu device: {s}", .{c.SDL_GetError()});
        return Error.GPUFailed;
    }
    errdefer gpu_device.deinit();

    const main_win = engine.windows.get("main");
    try gpu_device.claimWindow(main_win);
    errdefer gpu_device.releaseWindow(main_win);

    const self = try allocators.global().create(Self);
    self.* = .{
        .allocator = allocator,
        .engine = engine,
        .window = main_win,
        .gpu_device = gpu_device,
        .text_engine = try .init(gpu_device),
        .pipelines = .{
            .graphics = try .init(allocator, 128),
            .compute = try .init(allocator, 128),
        },
        .mesh_objs = try .init(allocator, 128),
        .mesh_bufs = try .init(allocator, 128),
        .storage_bufs = try .init(allocator, 16),
        .materials = try .init(allocator, 16),
        .cameras = try .init(allocator, 16),
        .lights = try .init(allocator, 16),
        .textures = try .init(allocator, 128),
        .samplers = try .init(allocator, 128),
        .stencil_format = gpu_device.stencilFormat(),
    };
    return self;
}

fn createTextures(self: *Self) !void {
    const win_size = self.window.pixelSize();

    _ = try self.createTexture("screen_buffer", &.{
        .type = .@"2D",
        .format = self.swapchainFormat(),
        .usage = .initMany(&.{ .sampler, .color_target }),
        .size = win_size,
    });

    _ = try self.createTexture("bloom", &.{
        .type = .@"2D",
        .format = self.swapchainFormat(),
        .usage = .initMany(&.{ .sampler, .color_target }),
        .size = win_size,
    });

    _ = try self.createTexture("stencil", &.{
        .type = .@"2D",
        .format = self.stencil_format,
        .usage = .initOne(.depth_stencil_target),
        .size = win_size,
    });
}

const sampler_configs = struct {
    const Config = struct {
        filter_mode: GPUSampler.FilterMode,
        address_mode: GPUSampler.AddressMode,
    };

    const configs: []const Config = &.{
        .{ .filter_mode = .nearest, .address_mode = .repeat },
        .{ .filter_mode = .nearest, .address_mode = .mirrored_repeat },
        .{ .filter_mode = .nearest, .address_mode = .clamp_to_edge },
        .{ .filter_mode = .linear, .address_mode = .repeat },
        .{ .filter_mode = .linear, .address_mode = .mirrored_repeat },
        .{ .filter_mode = .linear, .address_mode = .clamp_to_edge },
        .{ .filter_mode = .bilinear, .address_mode = .repeat },
        .{ .filter_mode = .bilinear, .address_mode = .mirrored_repeat },
        .{ .filter_mode = .bilinear, .address_mode = .clamp_to_edge },
        .{ .filter_mode = .trilinear, .address_mode = .repeat },
        .{ .filter_mode = .trilinear, .address_mode = .mirrored_repeat },
        .{ .filter_mode = .trilinear, .address_mode = .clamp_to_edge },
    };
};

fn createSamplers(self: *Self) !void {
    inline for (sampler_configs.configs) |config| {
        const filter_config = comptime config.filter_mode.config();
        _ = try self.createSampler(@tagName(config.filter_mode) ++ "_" ++ @tagName(config.address_mode), &.{
            .min_filter = filter_config.filter,
            .mag_filter = filter_config.filter,
            .mipmap_mode = filter_config.mipmap_mode,
            .address_mode_u = config.address_mode,
            .address_mode_v = config.address_mode,
            .address_mode_w = config.address_mode,
        });
    }
}

fn createGraphicsPipelines(self: *Self) !void {
    var screen_vert = shader_loader.loadFile(&.{
        .allocator = self.allocator,
        .gpu_device = self.gpu_device,
        .shader_path = "system/screen.vert",
        .stage = .vertex,
    }) catch |err| {
        log.err("failed creating screen shader: {t}", .{err});
        return Error.ShaderFailed;
    };
    defer screen_vert.deinit(self.gpu_device);

    var position_vert = shader_loader.loadFile(&.{
        .allocator = self.allocator,
        .gpu_device = self.gpu_device,
        .shader_path = "system/position.vert",
        .stage = .vertex,
    }) catch |err| {
        log.err("failed creating position shader: {t}", .{err});
        return Error.ShaderFailed;
    };
    defer position_vert.deinit(self.gpu_device);

    var vertex_vert = shader_loader.loadFile(&.{
        .allocator = self.allocator,
        .gpu_device = self.gpu_device,
        .shader_path = "system/vertex.vert",
        .stage = .vertex,
    }) catch |err| {
        log.err("failed creating vertex shader: {t}", .{err});
        return Error.ShaderFailed;
    };
    defer vertex_vert.deinit(self.gpu_device);

    var color_frag = shader_loader.loadFile(&.{
        .allocator = self.allocator,
        .gpu_device = self.gpu_device,
        .shader_path = "system/color.frag",
        .stage = .fragment,
    }) catch |err| {
        log.err("failed creating color fragment shader: {t}", .{err});
        return Error.ShaderFailed;
    };
    defer color_frag.deinit(self.gpu_device);

    var material_frag = shader_loader.loadFile(&.{
        .allocator = self.allocator,
        .gpu_device = self.gpu_device,
        .shader_path = "system/material.frag",
        .stage = .fragment,
    }) catch |err| {
        log.err("failed creating material fragment shader: {t}", .{err});
        return Error.ShaderFailed;
    };
    defer material_frag.deinit(self.gpu_device);

    var blend_frag = shader_loader.loadFile(&.{
        .allocator = self.allocator,
        .gpu_device = self.gpu_device,
        .shader_path = "system/blend.frag",
        .stage = .fragment,
    }) catch |err| {
        log.err("failed creating blend fragment shader: {t}", .{err});
        return Error.ShaderFailed;
    };
    defer blend_frag.deinit(self.gpu_device);

    var render_frag = shader_loader.loadFile(&.{
        .allocator = self.allocator,
        .gpu_device = self.gpu_device,
        .shader_path = "system/render.frag",
        .stage = .fragment,
    }) catch |err| {
        log.err("failed creating render fragment shader: {t}", .{err});
        return Error.ShaderFailed;
    };
    defer render_frag.deinit(self.gpu_device);

    log.info("swapchain format: {t}", .{self.swapchainFormat()});
    var pipeline: GPUGraphicsPipeline.CreateInfo = .{
        .target_info = .{
            .color_target_descriptions = &.{
                .{ .format = self.swapchainFormat(), .blend_state = .blend },
            },
        },
    };

    pipeline.vertex_shader = screen_vert;
    pipeline.fragment_shader = blend_frag;
    _ = try self.createGraphicsPipeline("blend", &pipeline);

    pipeline.vertex_shader = screen_vert;
    pipeline.fragment_shader = render_frag;
    _ = try self.createGraphicsPipeline("render", &pipeline);

    pipeline.rasterizer_state.enable_depth_clip = true;
    pipeline.depth_stencil_state = .depth_test_and_write;
    pipeline.target_info = .{
        .color_target_descriptions = &.{
            .{ .format = .hdr_f, .blend_state = .blend },
        },
        .has_depth_stencil_target = true,
        .depth_stencil_format = self.stencil_format,
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
    _ = try self.createGraphicsPipeline("line", &pipeline);

    pipeline.rasterizer_state.front_face = .clockwise;
    pipeline.rasterizer_state.cull_mode = .back;

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
    _ = try self.createGraphicsPipeline("material", &pipeline);
}

pub fn createMeshObject(self: *Self, key: []const u8, face_type: mesh.Object.FaceType) !*mesh.Object {
    const mesh_obj = try self.mesh_objs.create(key);
    mesh_obj.* = .init(self.allocator, face_type);
    return mesh_obj;
}

pub fn insertMeshObject(self: *Self, key: []const u8, mesh_obj: *const mesh.Object) !*mesh.Object {
    return self.mesh_objs.insert(key, mesh_obj);
}

pub fn createMeshBuffer(self: *Self, key: []const u8, mesh_type: mesh.Buffer.Type) !*mesh.Buffer {
    const mesh_buf = try self.mesh_bufs.create(key);
    mesh_buf.* = .init(mesh_type);
    return mesh_buf;
}

pub fn insertMeshBuffer(self: *Self, key: []const u8, mesh_buf: *const mesh.Buffer) !*mesh.Buffer {
    return self.mesh_bufs.insert(key, mesh_buf);
}

pub fn getOrCreateStorageBuffer(self: *Self, key: []const u8) !*mesh.Buffer {
    return self.storage_bufs.getPtrOrNull(key) orelse self.createStorageBuffer(key);
}

pub fn createStorageBuffer(self: *Self, key: []const u8) !*mesh.Buffer {
    const gpu_buf = try self.storage_bufs.create(key);
    gpu_buf.* = .init(.vertex);
    return gpu_buf;
}

pub fn insertStorageBuffer(self: *Self, key: []const u8, storage_buf: *const GPUBuffer) !*GPUBuffer {
    return self.storage_bufs.insert(key, storage_buf);
}

pub fn createMaterial(self: *Self, key: [:0]const u8) !*MaterialInfo {
    const material = try self.materials.create(key);
    material.* = .{ .name = key };
    return material;
}

pub fn insertMaterial(self: *Self, key: [:0]const u8, info: *const MaterialInfo) !*MaterialInfo {
    const mtl = try self.materials.insert(key, info);
    mtl.name = key;
    return mtl;
}

pub fn createCamera(self: *Self, key: [:0]const u8) !*Camera {
    const cam = try self.cameras.create(key);
    cam.* = .{ .name = cam };
}

pub fn insertCamera(self: *Self, key: [:0]const u8, camera: *const Camera) !*Camera {
    const cam = try self.cameras.insert(key, camera);
    cam.name = key;
    return cam;
}

pub fn createLight(self: *Self, key: [:0]const u8) !*Light {
    const lgh = try self.lights.create(key);
    lgh.* = .{ .name = key };
    return lgh;
}

pub fn insertLight(self: *Self, key: [:0]const u8, light: *const Light) !*Light {
    const lgh = try self.lights.insert(key, light);
    lgh.name = key;
    return lgh;
}

pub fn createTexture(self: *Self, key: []const u8, info: *const GPUTexture.CreateInfo) !GPUTexture {
    var tex = try self.gpu_device.texture(info);
    errdefer tex.deinit(self.gpu_device);
    return self.insertTexture(key, tex.ptr.?);
}

pub fn insertTexture(self: *Self, key: []const u8, texture: *c.SDL_GPUTexture) !GPUTexture {
    try self.textures.insert(self.allocator, key, .fromOwned(texture));
    return .fromOwned(texture);
}

pub fn createSampler(self: *Self, key: []const u8, info: *const GPUSampler.CreateInfo) !GPUSampler {
    var sampler = try self.gpu_device.sampler(info);
    errdefer sampler.deinit(self.gpu_device);
    return self.insertSampler(key, sampler.ptr.?);
}

pub fn insertSampler(self: *Self, key: []const u8, sampler: *c.SDL_GPUSampler) !GPUSampler {
    try self.samplers.insert(self.allocator, key, .fromOwned(sampler));
    return .fromOwned(sampler);
}

fn createGraphicsPipeline(
    self: *Self,
    key: []const u8,
    info: *const GPUGraphicsPipeline.CreateInfo,
) !GPUGraphicsPipeline {
    var pipeline = try self.gpu_device.graphicsPipeline(info);
    errdefer pipeline.deinit(self.gpu_device);
    return self.insertGraphicsPipeline(key, pipeline.ptr.?);
}

pub fn insertGraphicsPipeline(self: *Self, key: []const u8, pipeline: *c.SDL_GPUGraphicsPipeline) !GPUGraphicsPipeline {
    try self.pipelines.graphics.insert(self.allocator, key, .fromOwned(pipeline));
    return .fromOwned(pipeline);
}

const render_scene_config = struct {
    const line_mesh_types: []const mesh.Object.BufferType = &.{
        .tex_coords_u, .tex_coords_v, .normals, .tangents, .binormals,
    };

    const line_mesh_colors: std.EnumArray(mesh.Object.BufferType, math.RGBAf32) = .initDefault(
        math.rgba_f32.zero,
        .{
            .tex_coords_u = .{ 0, 1, 1, 1 },
            .tex_coords_v = .{ 1, 0, 1, 1 },
            .normals = .{ 0, 0, 1, 1 },
            .tangents = .{ 1, 0, 0, 1 },
            .binormals = .{ 0, 1, 0, 1 },
        },
    );
};

pub fn renderScene(
    self: *const Self,
    flat: *const Scene.Flattened,
    ui_ptr: ?*ui_mod.UI,
    items_iter: anytype,
) !bool {
    assert(self == flat.scene.renderer);
    const section = sections.sub(.render);
    section.begin();

    section.sub(.acquire).begin();

    const material_pipeline = self.pipelines.graphics.get("material");
    const line_pipeline = self.pipelines.graphics.get("line");
    // const blend_pipeline = self.pipelines.get("blend");
    const render_pipeline = self.pipelines.graphics.get("render");
    const origin_mesh = self.mesh_bufs.get("origin");
    const screen_buffer = self.textures.get("screen_buffer");
    const stencil = self.textures.get("stencil");
    const default_texture = self.textures.get("default");
    const texture_sampler = self.samplers.get("trilinear_mirrored_repeat");
    const screen_sampler = self.samplers.get("nearest_clamp_to_edge");
    const lut_sampler = self.samplers.get("trilinear_clamp_to_edge");
    const lights_buffer = self.storage_bufs.getPtr("lights");

    const lut_map = self.textures.get(self.settings.lut);
    const camera = self.activeCamera();

    const fa = allocators.frame();

    log.debug("command buffer", .{});
    var command_buffer = try self.gpu_device.commandBuffer();
    errdefer command_buffer.cancel() catch {};

    log.debug("swapchain texture", .{});
    const swapchain = try command_buffer.swapchainTexture(self.window);

    section.sub(.acquire).end();

    if (!swapchain.isValid()) {
        log.info("skip draw", .{});
        section.pop();
        return false;
    }

    section.sub(.init).begin();

    // const tr_world = try fa.create(math.Matrix4x4);
    const tr_projection = try fa.create(math.Matrix4x4);
    const tr_view = try fa.create(math.Matrix4x4);
    const tr_view_projection = try fa.create(math.Matrix4x4);
    // const tr_model = try fa.create(math.Matrix4x4);

    // const time_s = global.timeSinceStart().toFloat().toValue32(.s);
    // const aspect_ratio = @as(f32, @floatFromInt(engine.window_size.x)) / @as(f32, @floatFromInt(engine.window_size.y));
    const win_size = self.window.logicalSize();
    const mouse_pos = self.window.mousePos();
    const mouse_x = mouse_pos[0] / @as(f32, @floatFromInt(win_size[0]));
    const mouse_y = mouse_pos[1] / @as(f32, @floatFromInt(win_size[1]));
    _ = mouse_x;
    _ = mouse_y;
    // const pi = std.math.pi;

    camera.projection(
        tr_projection,
        @floatFromInt(win_size[0]),
        @floatFromInt(win_size[1]),
        0.1,
        10_000.0,
    );
    camera.transform(tr_view);
    math.matrix4x4.dot(tr_view_projection, tr_projection, tr_view);

    log.debug("camera_position: {any}", .{camera.position});
    log.debug("camera_direction: {any}", .{camera.direction});

    const uniform_buf = try fa.alloc(f32, 32);
    @memcpy(uniform_buf[0..16], math.matrix4x4.sliceConst(tr_view_projection));

    const light_counts = flat.lightCounts();

    section.sub(.init).end();

    {
        section.sub(.items).begin();
        log.debug("main render pass", .{});
        var render_pass = try command_buffer.renderPass(&.{.{
            .texture = screen_buffer,
            .clear_color = math.rgba_f32.tr_zero,
            .load_op = .clear,
            .store_op = .store,
        }}, &.{
            .texture = stencil,
            .clear_depth = 1,
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
        });

        render_pass.bindPipeline(material_pipeline);
        try render_pass.bindStorageBuffers(.fragment, 0, &.{lights_buffer.gpu_bufs.get(.vertex)});
        command_buffer.pushUniformData(.fragment, 1, &camera.position);
        command_buffer.pushUniformData(.fragment, 2, &light_counts.values);

        while (items_iter.next()) |_item| {
            const item: Item = _item;
            const mesh_obj = item.mesh_obj;

            if (!mesh_obj.is_visible.contains(.mesh)) continue;

            @memcpy(uniform_buf[16..32], math.matrix4x4.sliceConst(item.transform));
            command_buffer.pushUniformData(.vertex, 0, uniform_buf);

            const mesh_buf = mesh_obj.mesh_bufs.get(.mesh);
            try render_pass.bindVertexBuffers(0, &.{
                .{ .buffer = mesh_buf.gpu_bufs.get(.vertex), .offset = 0 },
            });

            for (mesh_obj.sections.items) |buf_section| {
                const mtl = if (buf_section.material) |mtl| mtl else gfx_options.default_material;
                const material = self.materials.getPtr(mtl);

                command_buffer.pushUniformData(.fragment, 0, &material.uniformBuffer());

                const texture = if (material.texture) |tex| self.textures.get(tex) else default_texture;
                const diffuse_map = if (material.diffuse_map) |tex| self.textures.get(tex) else default_texture;
                const bump_map = if (material.bump_map) |tex| self.textures.get(tex) else default_texture;

                try render_pass.bindSamplers(.fragment, 0, &.{
                    .{ .texture = texture, .sampler = texture_sampler },
                    .{ .texture = diffuse_map, .sampler = texture_sampler },
                    .{ .texture = bump_map, .sampler = texture_sampler },
                });

                switch (mesh_buf.type) {
                    .vertex => render_pass.drawPrimitives(
                        @intCast(buf_section.len),
                        1,
                        @intCast(buf_section.offset),
                        0,
                    ),
                    .index => {
                        log.info("{s}", .{item.key});
                        render_pass.bindIndexBuffer(&.{
                            .buffer = mesh_buf.gpu_bufs.get(.index),
                            .offset = 0,
                        }, .@"32bit");

                        render_pass.drawIndexedPrimitives(
                            @intCast(buf_section.len),
                            1,
                            @intCast(buf_section.offset),
                            0,
                            0,
                        );
                    },
                }
            }
        }

        section.sub(.items).end();
        log.debug("end main render pass", .{});
        render_pass.end();
    }

    {
        var render_pass = try command_buffer.renderPass(&.{
            .{ .texture = swapchain, .load_op = .clear, .store_op = .store },
        }, null);

        render_pass.bindPipeline(render_pipeline);
        command_buffer.pushUniformData(.fragment, 0, &self.settings.uniformBuffer());
        try render_pass.bindSamplers(.fragment, 0, &.{
            .{ .texture = screen_buffer, .sampler = screen_sampler },
            .{ .texture = lut_map, .sampler = lut_sampler },
        });
        render_pass.drawPrimitives(3, 1, 0, 0);
        render_pass.end();
    }

    {
        log.debug("line render pass", .{});
        var render_pass = try command_buffer.renderPass(&.{.{
            .texture = screen_buffer,
            .clear_color = math.rgba_f32.zero,
            .load_op = .clear,
            .store_op = .store,
        }}, &.{
            .texture = stencil,
            .clear_depth = 1,
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
        });

        render_pass.bindPipeline(line_pipeline);

        for (render_scene_config.line_mesh_types) |mesh_type| {
            command_buffer.pushUniformData(.fragment, 0, render_scene_config.line_mesh_colors.getPtrConst(mesh_type));

            items_iter.reset();
            while (items_iter.next()) |_item| {
                const item: Item = _item;
                const mesh_obj = item.mesh_obj;

                if (!mesh_obj.is_visible.contains(mesh_type)) continue;

                @memcpy(uniform_buf[16..32], math.matrix4x4.sliceConst(item.transform));
                command_buffer.pushUniformData(.vertex, 0, uniform_buf);

                const mesh_buf = mesh_obj.mesh_bufs.get(mesh_type);
                try render_pass.bindVertexBuffers(0, &.{
                    .{ .buffer = mesh_buf.gpu_bufs.get(.vertex), .offset = 0 },
                });

                for (mesh_obj.sections.items) |buf_section| {
                    switch (mesh_buf.type) {
                        .vertex => render_pass.drawPrimitives(
                            @intCast(buf_section.len * 2),
                            1,
                            @intCast(buf_section.offset * 2),
                            0,
                        ),
                        .index => {
                            log.err("index buffer line render", .{});
                            return Error.DrawFailed;
                        },
                    }
                }
            }
        }

        section.sub(.origin).begin();

        @memcpy(uniform_buf[16..32], math.matrix4x4.sliceConst(&math.matrix4x4.identity));

        try render_pass.bindVertexBuffers(0, &.{
            .{ .buffer = origin_mesh.gpu_bufs.get(.vertex), .offset = 0 },
        });

        render_pass.bindIndexBuffer(
            &.{ .buffer = origin_mesh.gpu_bufs.get(.index), .offset = 0 },
            .@"32bit",
        );

        command_buffer.pushUniformData(.vertex, 0, uniform_buf);

        command_buffer.pushUniformData(.fragment, 0, &math.RGBAf32{ 1, 0, 0, 1 });
        render_pass.drawIndexedPrimitives(2, 1, 0, 0, 0);

        command_buffer.pushUniformData(.fragment, 0, &math.RGBAf32{ 0, 1, 0, 1 });
        render_pass.drawIndexedPrimitives(2, 1, 2, 0, 0);

        command_buffer.pushUniformData(.fragment, 0, &math.RGBAf32{ 0, 0, 1, 1 });
        render_pass.drawIndexedPrimitives(2, 1, 4, 0, 0);

        section.sub(.origin).end();
        log.debug("end line render pass", .{});
        render_pass.end();
    }
    {
        var render_pass = try command_buffer.renderPass(&.{
            .{ .texture = swapchain, .load_op = .load, .store_op = .store },
        }, null);

        const ui_settings: Settings = .{
            .gamma = 1,
            .config = .{
                .has_agx = false,
                .has_lut = false,
            },
        };
        render_pass.bindPipeline(render_pipeline);
        command_buffer.pushUniformData(.fragment, 0, &ui_settings.uniformBuffer());
        try render_pass.bindSamplers(.fragment, 0, &.{
            .{ .texture = screen_buffer, .sampler = screen_sampler },
            .{ .texture = lut_map, .sampler = lut_sampler },
        });
        render_pass.drawPrimitives(3, 1, 0, 0);
        render_pass.end();
    }

    if (ui_ptr) |ui| {
        section.sub(.ui).begin();
        if (ui.render_ui) {
            try ui.submitPass(command_buffer, screen_buffer);
            {
                var render_pass = try command_buffer.renderPass(&.{
                    .{ .texture = swapchain, .load_op = .load, .store_op = .store },
                }, null);

                const ui_settings: Settings = .{
                    .gamma = 1.0 / 2.2,
                    .config = .{
                        .has_agx = false,
                        .has_lut = false,
                    },
                };
                render_pass.bindPipeline(render_pipeline);
                command_buffer.pushUniformData(.fragment, 0, &ui_settings.uniformBuffer());
                try render_pass.bindSamplers(.fragment, 0, &.{
                    .{ .texture = screen_buffer, .sampler = screen_sampler },
                    .{ .texture = lut_map, .sampler = lut_sampler },
                });
                render_pass.drawPrimitives(3, 1, 0, 0);
                render_pass.end();
            }
        }
        section.sub(.ui).end();
    }

    section.sub(.submit).begin();
    log.debug("submit command buffer", .{});
    try command_buffer.submit();
    section.sub(.submit).end();

    section.end();
    return true;
}

pub fn propertyEditorNode(
    self: *Self,
    editor: *ui_mod.PropertyEditorWindow,
    parent: *ui_mod.PropertyEditorWindow.Item,
) !*ui_mod.PropertyEditorWindow.Item {
    const root_id = @typeName(Self);
    const root_node = try editor.appendChildNode(parent, root_id, "Renderer");
    {
        const node = try editor.appendChildNode(root_node, root_id ++ ".mesh_objs", "Mesh Objects");
        var iter = self.mesh_objs.map.iterator();
        var buf: [64]u8 = undefined;
        while (iter.next()) |entry| {
            const id = try std.fmt.bufPrint(&buf, "{s}#{s}", .{ @typeName(mesh.Object), entry.key_ptr.* });
            _ = try editor.appendChild(
                node,
                entry.value_ptr.*.propertyEditor(),
                id,
                entry.key_ptr.*,
            );
        }
    }
    {
        const node = try editor.appendChildNode(root_node, root_id ++ ".mesh_bufs", "Mesh Buffers");
        var iter = self.mesh_bufs.map.iterator();
        var buf: [64]u8 = undefined;
        while (iter.next()) |entry| {
            const id = try std.fmt.bufPrint(&buf, "{s}#{s}", .{ @typeName(mesh.Buffer), entry.key_ptr.* });
            _ = try editor.appendChild(
                node,
                entry.value_ptr.*.propertyEditor(),
                id,
                entry.key_ptr.*,
            );
        }
    }
    {
        const node = try editor.appendChildNode(root_node, root_id ++ ".storage_bufs", "Storage Buffers");
        var iter = self.storage_bufs.map.iterator();
        var buf: [64]u8 = undefined;
        while (iter.next()) |entry| {
            const id = try std.fmt.bufPrint(&buf, "{s}#{s}", .{ @typeName(mesh.Buffer), entry.key_ptr.* });
            _ = try editor.appendChild(
                node,
                entry.value_ptr.*.propertyEditor(),
                id,
                entry.key_ptr.*,
            );
        }
    }
    {
        const node = try editor.appendChildNode(root_node, root_id ++ ".materials", "Materials");
        var iter = self.materials.map.iterator();
        var buf: [64]u8 = undefined;
        while (iter.next()) |entry| {
            const id = try std.fmt.bufPrint(&buf, "{s}#{s}", .{ @typeName(MaterialInfo), entry.key_ptr.* });
            _ = try editor.appendChild(
                node,
                entry.value_ptr.*.propertyEditor(),
                id,
                entry.key_ptr.*,
            );
        }
    }
    {
        const node = try editor.appendChildNode(root_node, root_id ++ ".cameras", "Cameras");
        var iter = self.cameras.map.iterator();
        var buf: [64]u8 = undefined;
        while (iter.next()) |entry| {
            const id = try std.fmt.bufPrint(
                &buf,
                "{s}#{s}",
                .{ @typeName(Camera), entry.key_ptr.* },
            );
            _ = try editor.appendChild(
                node,
                entry.value_ptr.*.propertyEditor(),
                id,
                entry.key_ptr.*,
            );
        }
    }
    {
        const node = try editor.appendChildNode(root_node, root_id ++ ".lights", "Lights");
        var iter = self.lights.map.iterator();
        var buf: [64]u8 = undefined;
        while (iter.next()) |entry| {
            const id = try std.fmt.bufPrint(
                &buf,
                "{s}#{s}",
                .{ @typeName(Light), entry.key_ptr.* },
            );
            _ = try editor.appendChild(
                node,
                entry.value_ptr.*.propertyEditor(),
                id,
                entry.key_ptr.*,
            );
        }
    }
    {
        const node = try editor.appendChildNode(root_node, root_id ++ ".textures", "Textures");
        var iter = self.textures.map.iterator();
        var buf: [64]u8 = undefined;
        while (iter.next()) |entry| {
            const id = try std.fmt.bufPrint(&buf, "{s}#{s}", .{ @typeName(GPUTexture), entry.key_ptr.* });
            _ = try editor.appendChild(
                node,
                ui_mod.property_editor.PropertyEditorNull.element(),
                id,
                entry.key_ptr.*,
            );
        }
    }
    {
        const node = try editor.appendChildNode(root_node, root_id ++ ".samplers", "Samplers");
        var iter = self.samplers.map.iterator();
        var buf: [64]u8 = undefined;
        while (iter.next()) |entry| {
            const id = try std.fmt.bufPrint(&buf, "{s}#{s}", .{ @typeName(GPUSampler), entry.key_ptr.* });
            _ = try editor.appendChild(
                node,
                ui_mod.property_editor.PropertyEditorNull.element(),
                id,
                entry.key_ptr.*,
            );
        }
    }

    _ = try editor.appendChild(root_node, self.settings.propertyEditor(), root_id ++ ".settings", "Settings");

    return root_node;
}
