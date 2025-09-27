//!
//! The zengine renderer implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const KeyMap = @import("../containers.zig").KeyMap;
const PtrKeyMap = @import("../containers.zig").PtrKeyMap;
const ecs = @import("../ecs.zig");
const Engine = @import("../Engine.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const perf = @import("../perf.zig");
const ui_mod = @import("../ui.zig");
const Camera = @import("Camera.zig");
const img = @import("img.zig");
const Mesh = @import("Mesh.zig");
const mtl_loader = @import("mtl_loader.zig");
const obj_loader = @import("obj_loader.zig");
const shader = @import("shader.zig");
const MeshInfo = obj_loader.MeshInfo;
const MaterialInfo = mtl_loader.MaterialInfo;
const Texture = @import("Texture.zig");

const log = std.log.scoped(.gfx_renderer);
pub const sections = perf.sections(@This(), &.{ .init, .render });

const Self = @This();

allocator: std.mem.Allocator,
gpu_device: *c.SDL_GPUDevice,
pipelines: Pipelines,
meshes: Meshes,
materials: MaterialInfos,
textures: Textures,
samplers: Samplers,
cameras: Cameras,

const Pipelines = PtrKeyMap(c.SDL_GPUGraphicsPipeline);
const Meshes = KeyMap(Mesh, .{});
const MeshInfos = KeyMap(MeshInfo, .{});
const MaterialInfos = KeyMap(MaterialInfo, .{});
const Textures = PtrKeyMap(c.SDL_GPUTexture);
const Samplers = PtrKeyMap(c.SDL_GPUSampler);
const Cameras = KeyMap(Camera, .{});
const SurfaceTextures = KeyMap(Texture, .{});

const InitState = struct {
    engine: *const Engine,
    surface_textures: SurfaceTextures,
};

pub const InitError = error{
    GpuFailed,
    ShaderFailed,
    WindowFailed,
    PipelineFailed,
    BufferFailed,
    MaterialFailed,
    TextureFailed,
    CommandBufferFailed,
    CopyPassFailed,
    RenderPassFailed,
    OutOfMemory,
};

pub const DrawError = error{
    DrawFailed,
    OutOfMemory,
};

pub const Item = struct {
    mesh: []const u8,
    position: math.Vertex,
    rotation: math.Euler,
    scale: math.Vertex,

    pub const exclude_properties: ui_mod.property_editor.PropertyList = &.{.mesh};

    pub fn propertyEditor(self: *Item) ui_mod.PropertyEditor(Item) {
        return .init(self);
    }
};

pub fn init(engine: *const Engine) InitError!*Self {
    defer allocators.scratchFree();

    try sections.register();
    try sections.sub(.render)
        .sections(&.{ .acquire, .init, .items, .origin, .ui })
        .register();

    sections.sub(.init).begin();
    defer sections.sub(.init).end();

    const self = try createSelf(allocators.gpa(), engine);
    errdefer self.deinit(engine);

    var state: InitState = .{
        .engine = engine,
        .surface_textures = try .init(self.allocator, 16),
    };
    defer self.cleanupInit(&state);

    const stencil_format = self.stencilFormat();
    const swapchain_format = self.swapchainFormat(&state);

    _ = try self.loadMesh(&state, "Cat", "cat.obj");
    _ = try self.loadMesh(&state, "Cow", "cow_nonormals.obj");
    _ = try self.createOriginMesh();
    _ = try self.createDefaultMaterial();
    _ = try self.createDefaultTexture(&state);
    _ = try self.createStencilTexture(&state, stencil_format);
    _ = try self.createDefaultCamera();

    _ = try self.createSampler("default", &.{
        .min_filter = c.SDL_GPU_FILTER_LINEAR,
        .mag_filter = c.SDL_GPU_FILTER_LINEAR,
        .mipmap_mode = c.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
        .address_mode_u = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_w = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
    });

    try self.createGpuData(&state);
    try self.uploadTransferBuffers(&state);
    try self.commitSurfaceTextures(&state);

    const vertex_shader = shader.open(.{
        .allocator = self.allocator,
        .gpu_device = self.gpu_device,
        .shader_path = "triangle_vert.vert",
        .stage = .vertex,
    }) catch |err| {
        log.err("failed creating vertex shader: {t}", .{err});
        return InitError.ShaderFailed;
    };
    defer shader.release(self.gpu_device, vertex_shader);

    const full_vertex_shader = shader.open(.{
        .allocator = self.allocator,
        .gpu_device = self.gpu_device,
        .shader_path = "full.vert",
        .stage = .vertex,
    }) catch |err| {
        log.err("failed creating full vertex shader: {t}", .{err});
        return InitError.ShaderFailed;
    };
    defer shader.release(self.gpu_device, full_vertex_shader);

    const fragment_shader = shader.open(.{
        .allocator = self.allocator,
        .gpu_device = self.gpu_device,
        .shader_path = "sampler_texture.frag",
        .stage = .fragment,
    }) catch |err| {
        log.err("failed creating fragment shader: {t}", .{err});
        return InitError.ShaderFailed;
    };
    defer shader.release(self.gpu_device, fragment_shader);

    const origin_fragment_shader = shader.open(.{
        .allocator = self.allocator,
        .gpu_device = self.gpu_device,
        .shader_path = "rgb_color.frag",
        .stage = .fragment,
    }) catch |err| {
        log.err("failed creating origin fragment shader: {t}", .{err});
        return InitError.ShaderFailed;
    };
    defer shader.release(self.gpu_device, origin_fragment_shader);

    const full_fragment_shader = shader.open(.{
        .allocator = self.allocator,
        .gpu_device = self.gpu_device,
        .shader_path = "full.frag",
        .stage = .fragment,
    }) catch |err| {
        log.err("failed creating full fragment shader: {t}", .{err});
        return InitError.ShaderFailed;
    };
    defer shader.release(self.gpu_device, full_fragment_shader);

    var graphics_pipeline_create_info = c.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &[_]c.SDL_GPUVertexBufferDescription{
                .{
                    .slot = 0,
                    .pitch = 3 * @sizeOf(math.Vertex),
                    .input_rate = c.SDL_GPU_VERTEXINPUTRATE_VERTEX,
                    .instance_step_rate = 0,
                },
            },
            .num_vertex_buffers = 1,
            .vertex_attributes = &[_]c.SDL_GPUVertexAttribute{
                .{
                    .location = 0,
                    .buffer_slot = 0,
                    .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
                    .offset = 0,
                },
                .{
                    .location = 1,
                    .buffer_slot = 0,
                    .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
                    .offset = @sizeOf(math.Vertex),
                },
                .{
                    .location = 2,
                    .buffer_slot = 0,
                    .format = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
                    .offset = 2 * @sizeOf(math.Vertex),
                },
            },
            .num_vertex_attributes = 3,
        },
        .primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .fill_mode = c.SDL_GPU_FILLMODE_FILL,
            .cull_mode = c.SDL_GPU_CULLMODE_NONE,
            .front_face = c.SDL_GPU_FRONTFACE_CLOCKWISE,
            .enable_depth_clip = true,
        },
        .depth_stencil_state = .{
            .compare_op = c.SDL_GPU_COMPAREOP_LESS,
            .compare_mask = 0xFF,
            .write_mask = 0xFF,
            .enable_depth_test = true,
            .enable_depth_write = true,
        },
        .target_info = .{
            .num_color_targets = 1,
            .color_target_descriptions = &c.SDL_GPUColorTargetDescription{
                .format = swapchain_format,
                .blend_state = .{},
            },
            .has_depth_stencil_target = true,
            .depth_stencil_format = stencil_format,
        },
    };

    _ = try self.createPipeline("default", &graphics_pipeline_create_info);

    graphics_pipeline_create_info.fragment_shader = origin_fragment_shader;
    graphics_pipeline_create_info.primitive_type = c.SDL_GPU_PRIMITIVETYPE_LINELIST;
    graphics_pipeline_create_info.rasterizer_state.fill_mode = c.SDL_GPU_FILLMODE_LINE;

    _ = try self.createPipeline("origin", &graphics_pipeline_create_info);

    graphics_pipeline_create_info.vertex_shader = full_vertex_shader;
    graphics_pipeline_create_info.fragment_shader = full_fragment_shader;
    graphics_pipeline_create_info.vertex_input_state = std.mem.zeroes(c.SDL_GPUVertexInputState);
    graphics_pipeline_create_info.primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST;
    graphics_pipeline_create_info.rasterizer_state.fill_mode = c.SDL_GPU_FILLMODE_FILL;

    _ = try self.createPipeline("full", &graphics_pipeline_create_info);

    return self;
}

pub fn deinit(self: *Self, engine: *const Engine) void {
    _ = c.SDL_WaitForGPUIdle(self.gpu_device);

    defer {
        c.SDL_ReleaseWindowFromGPUDevice(self.gpu_device, engine.window);
        c.SDL_DestroyGPUDevice(self.gpu_device);
    }
    defer {
        for (self.meshes.map.map.values()) |mesh| mesh.deinit(self.gpu_device);
        self.meshes.deinit();
    }
    defer self.materials.deinit();
    defer {
        for (self.pipelines.map.values()) |graphics_pipeline| c.SDL_ReleaseGPUGraphicsPipeline(
            self.gpu_device,
            graphics_pipeline,
        );
        self.pipelines.deinit(self.allocator);
    }
    defer {
        for (self.textures.map.values()) |texture| c.SDL_ReleaseGPUTexture(self.gpu_device, texture);
        self.textures.deinit(self.allocator);
    }
    defer {
        for (self.samplers.map.values()) |sampler| c.SDL_ReleaseGPUSampler(self.gpu_device, sampler);
        self.samplers.deinit(self.allocator);
    }
    defer self.cameras.deinit();
}

fn cleanupInit(self: *Self, state: *InitState) void {
    for (self.meshes.map.map.values()) |mesh| mesh.freeCpuData();
    for (state.surface_textures.map.map.values()) |tex| tex.deinit(self.gpu_device);
    state.surface_textures.deinit();
}

fn stencilFormat(self: *const Self) c.SDL_GPUTextureFormat {
    if (c.SDL_GPUTextureSupportsFormat(
        self.gpu_device,
        c.SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT,
        c.SDL_GPU_TEXTURETYPE_2D,
        c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
    )) {
        return c.SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT;
    } else if (c.SDL_GPUTextureSupportsFormat(
        self.gpu_device,
        c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT_S8_UINT,
        c.SDL_GPU_TEXTURETYPE_2D,
        c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
    )) {
        return c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT_S8_UINT;
    } else {
        return c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT;
    }
}

fn swapchainFormat(self: *const Self, state: *const InitState) c.SDL_GPUTextureFormat {
    return c.SDL_GetGPUSwapchainTextureFormat(self.gpu_device, state.engine.window);
}

fn setPresentMode(self: *Self, state: *InitState) InitError!void {
    var present_mode: c.SDL_GPUPresentMode = c.SDL_GPU_PRESENTMODE_VSYNC;
    if (c.SDL_WindowSupportsGPUPresentMode(
        self.gpu_device,
        state.engine.window,
        c.SDL_GPU_PRESENTMODE_MAILBOX,
    )) present_mode = c.SDL_GPU_PRESENTMODE_MAILBOX;

    if (!c.SDL_SetGPUSwapchainParameters(
        self.gpu_device,
        state.engine.window,
        c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR,
        present_mode,
    )) {
        log.err("failed setting swapchain parameters: {s}", .{c.SDL_GetError()});
        return InitError.WindowFailed;
    }
}

fn createSelf(allocator: std.mem.Allocator, engine: *const Engine) InitError!*Self {
    const gpu_device = c.SDL_CreateGPUDevice(
        c.SDL_GPU_SHADERFORMAT_SPIRV | c.SDL_GPU_SHADERFORMAT_DXIL | c.SDL_GPU_SHADERFORMAT_MSL,
        std.debug.runtime_safety,
        null,
    );
    if (gpu_device == null) {
        log.err("failed creating gpu device: {s}", .{c.SDL_GetError()});
        return InitError.GpuFailed;
    }
    errdefer c.SDL_DestroyGPUDevice(gpu_device);

    if (!c.SDL_ClaimWindowForGPUDevice(gpu_device, engine.window)) {
        log.err("failed claiming window for gpu device: {s}", .{c.SDL_GetError()});
        return InitError.WindowFailed;
    }
    errdefer c.SDL_ReleaseWindowFromGPUDevice(gpu_device, engine.window);

    const self = try allocators.global().create(Self);
    self.* = .{
        .allocator = allocator,
        .gpu_device = gpu_device.?,
        .pipelines = try .init(allocator, 128),
        .meshes = try .init(allocator, 128),
        .materials = try .init(allocator, 16),
        .textures = try .init(allocator, 128),
        .samplers = try .init(allocator, 128),
        .cameras = try .init(allocator, 128),
    };
    return self;
}

pub fn createOriginMesh(self: *Self) InitError!*Mesh {
    var origin_mesh = try Mesh.init(self.allocator);
    errdefer origin_mesh.deinit(self.gpu_device);

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
    origin_mesh.vert_len = 4 * 3;
    origin_mesh.appendIndexes(math.LineFaceIndex, &.{
        .{ 0, 1 },
        .{ 0, 2 },
        .{ 0, 3 },
    }) catch |err| {
        log.err("failed appending origin mesh faces: {t}", .{err});
        return InitError.BufferFailed;
    };
    origin_mesh.index_len = 6;

    return self.meshes.insert("origin", origin_mesh);
}

fn createDefaultMaterial(self: *Self) InitError!*MaterialInfo {
    return self.materials.insert("default", .{
        .name = "default",
        .texture = "default",
        .diffuse_map = "default",
        .bump_map = "default",
    });
}

fn createDefaultTexture(self: *Self, state: *InitState) InitError!*Texture {
    const surface = c.SDL_CreateSurface(1, 1, img.pixel_format);
    if (surface == null) {
        log.err("failed creating default texture surface: {s}", .{c.SDL_GetError()});
        return InitError.TextureFailed;
    }
    const pixel = c.SDL_MapSurfaceRGBA(surface, 0xff, 0xff, 0xff, 0xff);
    assert(surface.*.pitch == @sizeOf(@TypeOf(pixel)));
    const pixels: [*]u32 = @ptrCast(@alignCast(surface.*.pixels));
    pixels[0] = pixel;

    var texture = Texture.init(surface);
    errdefer texture.deinit(self.gpu_device);
    return state.surface_textures.insert("default", texture);
}

fn createStencilTexture(
    self: *Self,
    state: *InitState,
    stencil_format: c.SDL_GPUTextureFormat,
) InitError!*c.SDL_GPUTexture {
    const stencil_texture = c.SDL_CreateGPUTexture(self.gpu_device, &c.SDL_GPUTextureCreateInfo{
        .type = c.SDL_GPU_TEXTURETYPE_2D,
        .format = stencil_format,
        .usage = c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
        .width = @intCast(state.engine.window_size.x),
        .height = @intCast(state.engine.window_size.y),
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = c.SDL_GPU_SAMPLECOUNT_1,
    });
    if (stencil_texture == null) {
        log.err("failed creating stencil texture: {s}", .{c.SDL_GetError()});
        return InitError.BufferFailed;
    }
    errdefer c.SDL_ReleaseGPUTexture(self.gpu_device, stencil_texture);
    try self.textures.insert(self.allocator, "stencil", stencil_texture.?);
    return stencil_texture.?;
}

fn createSampler(
    self: *Self,
    key: []const u8,
    info: *const c.SDL_GPUSamplerCreateInfo,
) InitError!*c.SDL_GPUSampler {
    const sampler = c.SDL_CreateGPUSampler(self.gpu_device, info);
    if (sampler == null) {
        log.err("failed creating sampler: {s}", .{c.SDL_GetError()});
        return InitError.BufferFailed;
    }
    errdefer c.SDL_ReleaseGPUSampler(self.gpu_device, sampler);
    try self.samplers.insert(self.allocator, key, sampler.?);
    return sampler.?;
}

fn createPipeline(
    self: *Self,
    key: []const u8,
    info: *const c.SDL_GPUGraphicsPipelineCreateInfo,
) InitError!*c.SDL_GPUGraphicsPipeline {
    const graphics_pipeline = c.SDL_CreateGPUGraphicsPipeline(self.gpu_device, info);
    if (graphics_pipeline == null) {
        log.err("failed creating graphics pipeline: {s}", .{c.SDL_GetError()});
        return InitError.PipelineFailed;
    }
    errdefer c.SDL_ReleaseGPUGraphicsPipeline(self.gpu_device, graphics_pipeline);
    try self.pipelines.insert(self.allocator, key, graphics_pipeline.?);
    return graphics_pipeline.?;
}

fn createDefaultCamera(self: *Self) InitError!*Camera {
    var camera_position: math.Vector3 = .{ 4, 8, 10 };
    var camera_direction: math.Vector3 = undefined;

    math.vector3.scale(&camera_position, 15);
    math.vector3.lookAt(&camera_direction, &camera_position, &math.vector3.zero);

    return self.cameras.insert("default", .{
        .kind = .perspective,
        .position = camera_position,
        .direction = camera_direction,
    });
}

pub fn loadMesh(self: *Self, state: *InitState, key: []const u8, asset_path: []const u8) InitError!*Mesh {
    const mesh_path = try global.assetPath(asset_path);

    var result = obj_loader.loadFile(self.allocator, mesh_path) catch |err| {
        log.err("failed loading mesh obj file: {t}", .{err});
        return InitError.BufferFailed;
    };
    errdefer result.mesh.deinit(self.gpu_device);

    if (result.mtl_path) |mtl_path| try self.loadMaterials(state, mtl_path);
    // TODO: objects and groups
    return self.meshes.insert(key, result.mesh);
}

pub fn loadMaterials(self: *Self, state: *InitState, asset_path: []const u8) InitError!void {
    const mtl_path = try global.assetPath(asset_path);
    var mtl = mtl_loader.loadFile(self.allocator, mtl_path) catch |err| {
        log.err("error loading material: {t}", .{err});
        return InitError.MaterialFailed;
    };
    defer mtl.deinit();
    for (mtl.items) |item| {
        log.info("material {s}:", .{item.name});
        log.info("{?s}, {?s}, {?s}", .{ item.texture, item.diffuse_map, item.bump_map });
        log.info("{any}, {any}, {any}, {any}, {any}", .{
            item.ambient,
            item.diffuse,
            item.specular,
            item.emissive,
            item.filter,
        });
        log.info("{}, {}, {}, {}", .{ item.specular_exp, item.ior, item.alpha, item.mode });
        for (&[_]?[]const u8{ item.texture, item.diffuse_map, item.bump_map }) |opt_tex_path| {
            if (opt_tex_path) |tex_path| _ = try self.loadTexture(state, tex_path);
        }
        _ = try self.materials.insert(item.name, item);
    }
}

pub fn loadTexture(self: *Self, state: *InitState, asset_path: []const u8) InitError!*Texture {
    if (state.surface_textures.getPtrOrNull(asset_path)) |ptr| return ptr;

    const tex_path = try global.assetPath(asset_path);
    const surface = img.open(.{
        .allocator = self.allocator,
        .gpu_device = self.gpu_device,
        .file_path = tex_path,
    }) catch |err| {
        log.err("failed reading image file: {t}", .{err});
        return InitError.TextureFailed;
    };
    var texture = Texture.init(surface);
    errdefer texture.deinit(self.gpu_device);
    return state.surface_textures.insert(asset_path, texture);
}

fn createGpuData(self: *Self, state: *InitState) InitError!void {
    for (self.meshes.map.map.values()) |mesh| try mesh.createGpuBuffers(self.gpu_device);
    for (state.surface_textures.map.map.values()) |tex| try tex.createTexture(self.gpu_device);
}

fn uploadTransferBuffers(self: *Self, state: *InitState) InitError!void {
    const TextureTransferBuffers = std.ArrayList(Texture.UploadTransferBuffer);
    const MeshTransferBuffers = std.ArrayList(Mesh.UploadTransferBuffer);

    var tex_tbs: TextureTransferBuffers = try .initCapacity(self.allocator, state.surface_textures.map.map.count());
    defer {
        for (tex_tbs.items) |*tb| tb.release(self.gpu_device);
        tex_tbs.deinit(self.allocator);
    }

    var mesh_tbs: MeshTransferBuffers = try .initCapacity(self.allocator, self.meshes.map.map.count());
    defer {
        for (mesh_tbs.items) |*tb| tb.release(self.gpu_device);
        mesh_tbs.deinit(self.allocator);
    }

    for (state.surface_textures.map.map.values()) |tex| {
        const tb = try tex.createUploadTransferBuffer(self.gpu_device);
        tex_tbs.appendAssumeCapacity(tb);
    }

    for (self.meshes.map.map.values()) |mesh| {
        const tb = try mesh.createUploadTransferBuffer(self.gpu_device);
        mesh_tbs.appendAssumeCapacity(tb);
    }

    for (tex_tbs.items) |*tb| try tb.map(self.gpu_device);
    for (mesh_tbs.items) |*tb| try tb.map(self.gpu_device);

    const command_buffer = c.SDL_AcquireGPUCommandBuffer(self.gpu_device);
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

        for (tex_tbs.items) |*tb| tb.upload(copy_pass);
        for (mesh_tbs.items) |*tb| tb.upload(copy_pass);

        c.SDL_EndGPUCopyPass(copy_pass);
    }

    if (!c.SDL_SubmitGPUCommandBuffer(command_buffer)) {
        log.err("failed submitting command buffer: {s}", .{c.SDL_GetError()});
        return InitError.CommandBufferFailed;
    }
}

fn commitSurfaceTextures(self: *Self, state: *InitState) InitError!void {
    var iter = state.surface_textures.map.map.iterator();
    while (iter.next()) |i| try self.textures.insert(
        self.allocator,
        i.key_ptr.*,
        i.value_ptr.*.toTextureOwned(),
    );
}

pub fn render(
    self: *const Self,
    engine: *const Engine,
    ui_ptr: ?*ui_mod.UI,
    items_iter: anytype,
) DrawError!bool {
    const section = sections.sub(.render);
    section.begin();
    defer section.end();

    section.sub(.acquire).begin();

    const gpu_device = self.gpu_device;
    const window = engine.window;
    const graphics_pipeline = self.pipelines.getPtr("default");
    // const origin_graphics_pipeline = self.pipelines.getPtr("origin");
    // const origin_mesh = self.meshes.getPtr("origin");
    const stencil_texture = self.textures.getPtr("stencil");
    const camera = self.cameras.getPtr("default");
    // const full_graphics_pipeline = self.full_graphics_pipeline;

    const fa = allocators.frame();

    log.debug("command_buffer", .{});
    const command_buffer = c.SDL_AcquireGPUCommandBuffer(gpu_device);
    if (command_buffer == null) {
        log.err("failed to acquire command_buffer: {s}", .{c.SDL_GetError()});
        return DrawError.DrawFailed;
    }
    errdefer _ = c.SDL_CancelGPUCommandBuffer(command_buffer);

    log.debug("swapchain_texture", .{});
    var swapchain_texture: ?*c.SDL_GPUTexture = undefined;
    if (!c.SDL_WaitAndAcquireGPUSwapchainTexture(command_buffer, window, &swapchain_texture, null, null)) {
        log.err("failed to acquire swapchain_texture: {s}", .{c.SDL_GetError()});
        return DrawError.DrawFailed;
    }

    section.sub(.acquire).end();

    if (swapchain_texture == null) {
        log.debug("skip draw", .{});
        return false;
    }

    section.sub(.init).begin();

    // const tr_world = try fa.create(math.Matrix4x4);
    const tr_projection = try fa.create(math.Matrix4x4);
    const tr_view = try fa.create(math.Matrix4x4);
    const tr_view_projection = try fa.create(math.Matrix4x4);
    const tr_model = try fa.create(math.Matrix4x4);

    // const time_s = global.timeSinceStart().toFloat().toValue32(.s);
    // const aspect_ratio = @as(f32, @floatFromInt(engine.window_size.x)) / @as(f32, @floatFromInt(engine.window_size.y));
    // const mouse_x = engine.mouse_pos.x / @as(f32, @floatFromInt(engine.window_size.x));
    // const mouse_y = engine.mouse_pos.y / @as(f32, @floatFromInt(engine.window_size.y));
    // const pi = std.math.pi;

    camera.projection(
        tr_projection,
        @floatFromInt(engine.window_size.x),
        @floatFromInt(engine.window_size.y),
        7.5,
        10_000.0,
    );
    camera.transform(tr_view);
    math.matrix4x4.dot(tr_view_projection, tr_projection, tr_view);

    log.debug("camera_position: {any}", .{camera.position});
    log.debug("camera_direction: {any}", .{camera.direction});

    var uniform_buffer = try fa.alloc(f32, 32);
    @memcpy(uniform_buffer[0..16], math.matrix4x4.sliceLenConst(tr_view_projection));

    var frag_uniform_buffer = try fa.alloc(f32, 7 * 4);
    @memcpy(frag_uniform_buffer[24..27], math.vector3.sliceLenConst(&camera.position));

    // var frag_uniform_buffer: [4]f32 = .{ time_s, aspect_ratio, mouse_x, mouse_y };
    // var origin_frag_uniform_buffer: [4]f32 = .{ 1, 0, 1, 1 };

    // {
    //     const render_pass = c.SDL_BeginGPURenderPass(
    //         command_buffer,
    //         &c.SDL_GPUColorTargetInfo{
    //             .texture = swapchain_texture,
    //             .clear_color = c.SDL_FColor{ .r = 0.025, .g = 0, .b = 0.05, .a = 1 },
    //             .load_op = c.SDL_GPU_LOADOP_CLEAR,
    //             .store_op = c.SDL_GPU_STOREOP_STORE,
    //         },
    //         1,
    //         &c.SDL_GPUDepthStencilTargetInfo{
    //             .texture = self.stencil_texture,
    //             .clear_depth = 1,
    //             .load_op = c.SDL_GPU_LOADOP_CLEAR,
    //             .store_op = c.SDL_GPU_STOREOP_STORE,
    //             .stencil_load_op = c.SDL_GPU_LOADOP_DONT_CARE,
    //             .stencil_store_op = c.SDL_GPU_STOREOP_DONT_CARE,
    //             // .cycle = true,
    //         },
    //     );
    //     if (render_pass == null) {
    //         log.err("failed to begin render_pass: {s}", .{c.SDL_GetError()});
    //         return DrawError.DrawFailed;
    //     }
    //
    //     c.SDL_PushGPUVertexUniformData(command_buffer, 0, uniform_buffer, @sizeOf(@TypeOf(uniform_buffer)));
    //     c.SDL_PushGPUFragmentUniformData(command_buffer, 0, &frag_uniform_buffer, @sizeOf(@TypeOf(frag_uniform_buffer)));
    //     c.SDL_BindGPUGraphicsPipeline(render_pass, full_graphics_pipeline);
    //     log.debug("draw cow", .{});
    //     c.SDL_DrawGPUPrimitives(render_pass, 6, 1, 0, 0);
    //
    //     log.debug("end render_pass", .{});
    //     c.SDL_EndGPURenderPass(render_pass);
    // }

    {
        log.debug("main render pass", .{});
        const render_pass = c.SDL_BeginGPURenderPass(
            command_buffer,
            &c.SDL_GPUColorTargetInfo{
                .texture = swapchain_texture,
                .clear_color = c.SDL_FColor{ .r = 0.025, .g = 0, .b = 0.05, .a = 1 },
                .load_op = c.SDL_GPU_LOADOP_CLEAR,
                .store_op = c.SDL_GPU_STOREOP_STORE,
            },
            1,
            &c.SDL_GPUDepthStencilTargetInfo{
                .texture = stencil_texture,
                .clear_depth = 1,
                .load_op = c.SDL_GPU_LOADOP_CLEAR,
                .store_op = c.SDL_GPU_STOREOP_STORE,
                .stencil_load_op = c.SDL_GPU_LOADOP_DONT_CARE,
                .stencil_store_op = c.SDL_GPU_STOREOP_DONT_CARE,
                // .cycle = true,
            },
        );
        if (render_pass == null) {
            log.err("failed to begin render_pass: {s}", .{c.SDL_GetError()});
            return DrawError.DrawFailed;
        }

        // c.SDL_BindGPUFragmentSamplers(render_pass, 0, &c.SDL_GPUTextureSamplerBinding{
        //     .sampler = self.sampler,
        //     .texture = self.texture,
        // }, 1);

        section.sub(.init).end();
        section.sub(.items).begin();

        c.SDL_BindGPUGraphicsPipeline(render_pass, graphics_pipeline);

        while (items_iter.next()) |_item| {
            const item: Item = _item;
            const mesh = self.meshes.getPtr(item.mesh);
            const mtl: []const u8 = blk: {
                for (mesh.nodes.items) |node| {
                    if (node.meta == .material) break :blk node.meta.material;
                }
                break :blk "default";
            };

            const material = self.materials.get(mtl);
            const sampler = self.samplers.getPtr("default");

            {
                const result = tr_model;
                result.* = math.matrix4x4.identity;
                // math.matrix4x4.rotateEuler(result, &.{ -time_s * pi / 10, -time_s * pi / 9, 0 }, .xyz);
                const euler_order: math.EulerOrder = .xyz;
                math.matrix4x4.scaleXYZ(result, &item.scale);
                math.matrix4x4.rotateEuler(result, &item.rotation, euler_order);
                math.matrix4x4.translateXYZ(result, &item.position);
            }
            @memcpy(uniform_buffer[16..32], math.matrix4x4.sliceLenConst(tr_model));

            c.SDL_PushGPUVertexUniformData(
                command_buffer,
                0,
                uniform_buffer.ptr,
                @intCast(@sizeOf(f32) * uniform_buffer.len),
            );

            {
                @memcpy(frag_uniform_buffer[0..3], math.vector3.sliceLenConst(&material.ambient));
                @memcpy(frag_uniform_buffer[4..7], math.vector3.sliceLenConst(&material.diffuse));
                @memcpy(frag_uniform_buffer[8..11], math.vector3.sliceLenConst(&material.specular));
                @memcpy(frag_uniform_buffer[12..15], math.vector3.sliceLenConst(&material.emissive));
                @memcpy(frag_uniform_buffer[16..19], math.vector3.sliceLenConst(&material.filter));
                frag_uniform_buffer[20] = material.specular_exp;
                frag_uniform_buffer[21] = material.ior;
                frag_uniform_buffer[22] = material.alpha;
            }

            c.SDL_PushGPUFragmentUniformData(
                command_buffer,
                0,
                frag_uniform_buffer.ptr,
                @intCast(@sizeOf(f32) * frag_uniform_buffer.len),
            );

            c.SDL_BindGPUVertexBuffers(render_pass, 0, &c.SDL_GPUBufferBinding{
                .buffer = mesh.vert_buf,
                .offset = 0,
            }, 1);

            if (material.texture) |tex| {
                const texture = self.textures.getPtr(tex);
                c.SDL_BindGPUFragmentSamplers(render_pass, 0, &c.SDL_GPUTextureSamplerBinding{
                    .texture = texture,
                    .sampler = sampler,
                }, 1);
            }

            if (material.diffuse_map) |tex| {
                const texture = self.textures.getPtr(tex);
                c.SDL_BindGPUFragmentSamplers(render_pass, 1, &c.SDL_GPUTextureSamplerBinding{
                    .texture = texture,
                    .sampler = sampler,
                }, 1);
            }

            if (material.bump_map) |tex| {
                const texture = self.textures.getPtr(tex);
                c.SDL_BindGPUFragmentSamplers(render_pass, 2, &c.SDL_GPUTextureSamplerBinding{
                    .texture = texture,
                    .sampler = sampler,
                }, 1);
            }

            if (mesh.index_buf != null) {
                c.SDL_BindGPUIndexBuffer(render_pass, &c.SDL_GPUBufferBinding{
                    .buffer = mesh.index_buf,
                    .offset = 0,
                }, c.SDL_GPU_INDEXELEMENTSIZE_32BIT);
                c.SDL_DrawGPUIndexedPrimitives(render_pass, @intCast(mesh.index_len), 1, 0, 0, 0);
            } else {
                c.SDL_DrawGPUPrimitives(render_pass, @intCast(mesh.vert_len), 1, 0, 0);
            }
        }

        section.sub(.items).end();
        section.sub(.origin).begin();

        const origin_mesh = self.meshes.getPtr("origin");
        const origin_graphics_pipeline = self.pipelines.getPtr("origin");

        tr_model.* = math.matrix4x4.identity;
        @memcpy(uniform_buffer[16..32], math.matrix4x4.sliceLenConst(tr_model));

        c.SDL_BindGPUVertexBuffers(render_pass, 0, &c.SDL_GPUBufferBinding{
            .buffer = origin_mesh.vert_buf,
            .offset = 0,
        }, 1);
        c.SDL_BindGPUIndexBuffer(render_pass, &c.SDL_GPUBufferBinding{
            .buffer = origin_mesh.index_buf,
            .offset = 0,
        }, c.SDL_GPU_INDEXELEMENTSIZE_32BIT);
        c.SDL_PushGPUVertexUniformData(command_buffer, 0, uniform_buffer.ptr, @intCast(@sizeOf(f32) * uniform_buffer.len));
        c.SDL_BindGPUGraphicsPipeline(render_pass, origin_graphics_pipeline);

        @memcpy(frag_uniform_buffer[0..3], &[_]f32{ 1, 0, 0 });
        c.SDL_PushGPUFragmentUniformData(
            command_buffer,
            0,
            frag_uniform_buffer.ptr,
            @intCast(@sizeOf(f32) * frag_uniform_buffer.len),
        );

        c.SDL_DrawGPUIndexedPrimitives(render_pass, 2, 1, 0, 0, 0);

        @memcpy(frag_uniform_buffer[0..3], &[_]f32{ 0, 1, 0 });
        c.SDL_PushGPUFragmentUniformData(
            command_buffer,
            0,
            frag_uniform_buffer.ptr,
            @intCast(@sizeOf(f32) * frag_uniform_buffer.len),
        );

        c.SDL_DrawGPUIndexedPrimitives(render_pass, 2, 1, 2, 0, 0);

        @memcpy(frag_uniform_buffer[0..3], &[_]f32{ 0, 0, 1 });
        c.SDL_PushGPUFragmentUniformData(
            command_buffer,
            0,
            frag_uniform_buffer.ptr,
            @intCast(@sizeOf(f32) * frag_uniform_buffer.len),
        );
        c.SDL_DrawGPUIndexedPrimitives(render_pass, 2, 1, 4, 0, 0);

        section.sub(.origin).end();

        log.debug("end main render pass", .{});
        c.SDL_EndGPURenderPass(render_pass);
    }

    if (ui_ptr) |ui| {
        section.sub(.ui).begin();
        if (ui.render_ui) try ui.submitPass(
            command_buffer,
            swapchain_texture,
        );
        section.sub(.ui).end();
    }

    // {
    //     log.debug("render_pass 2", .{});
    //     const render_pass = c.SDL_BeginGPURenderPass(
    //         command_buffer,
    //         &c.SDL_GPUColorTargetInfo{
    //             .texture = swapchain_texture,
    //             .load_op = c.SDL_GPU_LOADOP_LOAD,
    //             .store_op = c.SDL_GPU_STOREOP_STORE,
    //         },
    //         1,
    //         &c.SDL_GPUDepthStencilTargetInfo{
    //             .texture = self.stencil_texture,
    //             .load_op = c.SDL_GPU_LOADOP_LOAD,
    //             .store_op = c.SDL_GPU_STOREOP_STORE,
    //             .stencil_load_op = c.SDL_GPU_LOADOP_DONT_CARE,
    //             .stencil_store_op = c.SDL_GPU_STOREOP_DONT_CARE,
    //             // .cycle = true,
    //         },
    //     );
    //     if (render_pass == null) {
    //         log.err("failed to begin render_pass: {s}", .{c.SDL_GetError()});
    //         return DrawError.DrawFailed;
    //     }
    //
    //     // c.SDL_BindGPUFragmentSamplers(render_pass, 0, &c.SDL_GPUTextureSamplerBinding{
    //     //     .sampler = self.sampler,
    //     //     .texture = self.texture,
    //     // }, 1);
    //
    //     c.SDL_EndGPURenderPass(render_pass);
    // }

    log.debug("submit command_buffer", .{});
    if (!c.SDL_SubmitGPUCommandBuffer(command_buffer)) {
        log.err("failed submitting command_buffer: {s}", .{c.SDL_GetError()});
        return DrawError.DrawFailed;
    }

    return true;
}

pub fn format(self: *const Self, w: *std.io.Writer) !void {
    const camera = self.cameras.getPtr("default");
    try w.print(
        ".{{ .camera_position = {any}, .camera_direction = {any}, .kind = {t}, .{s} = {} }}",
        .{
            camera.position,
            camera.direction,
            @as(Camera.Kind, camera.kind),
            switch (camera.kind) {
                .ortographic => "scale",
                .perspective => "fov",
            },
            switch (camera.kind) {
                .ortographic => camera.orto_scale,
                .perspective => camera.fov,
            },
        },
    );
}

pub fn propertyEditorNode(
    self: *Self,
    editor: *ui_mod.PropertyEditorWindow,
    parent: *ui_mod.PropertyEditorWindow.Item,
) !*ui_mod.PropertyEditorWindow.Item {
    const root_id = @typeName(Self);
    const root_node = try editor.appendChildNode(parent, root_id, "Renderer");
    {
        const node = try editor.appendChildNode(root_node, root_id ++ ".materials", "Materials");
        var iter = self.materials.map.map.iterator();
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
        var iter = self.cameras.map.map.iterator();
        var buf: [64]u8 = undefined;
        while (iter.next()) |entry| {
            const id = try std.fmt.bufPrint(&buf, "{s}#{s}", .{ @typeName(Camera), entry.key_ptr.* });
            _ = try editor.appendChild(
                node,
                entry.value_ptr.*.propertyEditor(),
                id,
                entry.key_ptr.*,
            );
        }
    }
    return root_node;
}
