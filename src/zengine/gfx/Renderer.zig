//!
//! The zengine renderer implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const KeyMap = @import("../containers.zig").ArrayKeyMap;
const PtrKeyMap = @import("../containers.zig").ArrayPtrKeyMap;
const ecs = @import("../ecs.zig");
const Engine = @import("../Engine.zig");
const c = @import("../ext.zig").c;
const global = @import("../global.zig");
const math = @import("../math.zig");
const perf = @import("../perf.zig");
const Scene = @import("../Scene.zig");
const ui_mod = @import("../ui.zig");
const GPUBuffer = @import("GPUBuffer.zig");
const GPUTexture = @import("GPUTexture.zig");
const MaterialInfo = @import("MaterialInfo.zig");
const MeshBuffer = @import("MeshBuffer.zig");
const MeshObject = @import("MeshObject.zig");
const shader = @import("shader.zig");

const gfx_options = @import("../options.zig").gfx_options;
const default_material = gfx_options.default_material;

const log = std.log.scoped(.gfx_renderer);
pub const sections = perf.sections(@This(), &.{ .init, .render });

allocator: std.mem.Allocator,
gpu_device: *c.SDL_GPUDevice,
pipelines: Pipelines,
mesh_objs: MeshObjects,
mesh_bufs: MeshBuffers,
storage_bufs: StorageBuffers,
materials: MaterialInfos,
textures: Textures,
samplers: Samplers,

const Self = @This();

const Pipelines = PtrKeyMap(c.SDL_GPUGraphicsPipeline);
const MeshObjects = KeyMap(MeshObject, .{});
const MeshBuffers = KeyMap(MeshBuffer, .{});
const StorageBuffers = KeyMap(GPUBuffer, .{});
const MaterialInfos = KeyMap(MaterialInfo, .{});
const Textures = PtrKeyMap(c.SDL_GPUTexture);
const Samplers = PtrKeyMap(c.SDL_GPUSampler);

pub const InitError = error{
    GPUFailed,
    ShaderFailed,
    WindowFailed,
    PipelineFailed,
    BufferFailed,
    MaterialFailed,
    SurfaceFailed,
    TextureFailed,
    SamplerFailed,
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
    object: [:0]const u8,
    transform: *const math.Matrix4x4,

    pub const rotation_speed = 0.1;

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

    const self = try createSelf(allocators.gpa(), engine);
    errdefer self.deinit(engine);

    const stencil_format = self.stencilFormat();
    const swapchain_format = self.swapchainFormat(engine);

    _ = try self.createStencilTexture(engine, stencil_format);
    _ = try self.createSampler("default", &.{
        .min_filter = c.SDL_GPU_FILTER_LINEAR,
        .mag_filter = c.SDL_GPU_FILTER_LINEAR,
        .mipmap_mode = c.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
        .address_mode_u = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_w = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
    });

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
            .color_target_descriptions = &c.SDL_GPUColorTargetDescription{
                .format = swapchain_format,
                .blend_state = .{
                    .src_color_blendfactor = c.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
                    .dst_color_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
                    .color_blend_op = c.SDL_GPU_BLENDOP_ADD,
                    .alpha_blend_op = c.SDL_GPU_BLENDOP_MAX,
                    .color_write_mask = 0x00,
                    .src_alpha_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE,
                    .dst_alpha_blendfactor = c.SDL_GPU_BLENDFACTOR_ONE,
                    .enable_blend = true,
                    .enable_color_write_mask = false,
                },
            },
            .num_color_targets = 1,
            .has_depth_stencil_target = true,
            .depth_stencil_format = @intFromEnum(stencil_format),
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

    sections.sub(.init).end();
    return self;
}

pub fn deinit(self: *Self, engine: *const Engine) void {
    _ = c.SDL_WaitForGPUIdle(self.gpu_device);
    const gpa = self.allocator;
    const gpu_device = self.gpu_device;

    for (self.pipelines.map.values()) |graphics_pipeline| c.SDL_ReleaseGPUGraphicsPipeline(
        self.gpu_device,
        graphics_pipeline,
    );
    self.pipelines.deinit(gpa);

    for (self.mesh_objs.map.values()) |object| object.deinit(gpa);
    self.mesh_objs.deinit();

    self.materials.deinit();

    for (self.mesh_bufs.map.values()) |mesh| mesh.deinit(gpa, gpu_device);
    self.mesh_bufs.deinit();
    for (self.storage_bufs.map.values()) |buf| buf.deinit(gpa, gpu_device);
    self.storage_bufs.deinit();
    for (self.textures.map.values()) |texture| c.SDL_ReleaseGPUTexture(gpu_device, texture);
    self.textures.deinit(gpa);
    for (self.samplers.map.values()) |sampler| c.SDL_ReleaseGPUSampler(gpu_device, sampler);
    self.samplers.deinit(gpa);

    c.SDL_ReleaseWindowFromGPUDevice(self.gpu_device, engine.window);
    c.SDL_DestroyGPUDevice(self.gpu_device);
}

fn stencilFormat(self: *const Self) GPUTexture.Format {
    if (c.SDL_GPUTextureSupportsFormat(
        self.gpu_device,
        c.SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT,
        c.SDL_GPU_TEXTURETYPE_2D,
        c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
    )) {
        return .d24_unorm_s8_u;
    } else if (c.SDL_GPUTextureSupportsFormat(
        self.gpu_device,
        c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT_S8_UINT,
        c.SDL_GPU_TEXTURETYPE_2D,
        c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
    )) {
        return .d32_f_s8_u;
    } else {
        return .d32_f;
    }
}

fn swapchainFormat(self: *const Self, engine: *const Engine) c.SDL_GPUTextureFormat {
    return c.SDL_GetGPUSwapchainTextureFormat(self.gpu_device, engine.window);
}

fn setPresentMode(self: *Self, engine: *const Engine) InitError!void {
    var present_mode: c.SDL_GPUPresentMode = c.SDL_GPU_PRESENTMODE_VSYNC;
    if (c.SDL_WindowSupportsGPUPresentMode(
        self.gpu_device,
        engine.window,
        c.SDL_GPU_PRESENTMODE_MAILBOX,
    )) present_mode = c.SDL_GPU_PRESENTMODE_MAILBOX;

    if (!c.SDL_SetGPUSwapchainParameters(
        self.gpu_device,
        engine.window,
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
        return InitError.GPUFailed;
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
        .mesh_objs = try .init(allocator, 128),
        .mesh_bufs = try .init(allocator, 128),
        .storage_bufs = try .init(allocator, 16),
        .materials = try .init(allocator, 16),
        .textures = try .init(allocator, 128),
        .samplers = try .init(allocator, 128),
    };
    return self;
}

pub fn createMeshObject(
    self: *Self,
    key: []const u8,
    face_type: MeshObject.FaceType,
) !*MeshObject {
    const mesh_obj = try self.mesh_objs.create(key);
    mesh_obj.* = .init(self.allocator, face_type);
    return mesh_obj;
}

pub fn insertMeshObject(
    self: *Self,
    key: []const u8,
    mesh_obj: *const MeshObject,
) !*MeshObject {
    return self.mesh_objs.insert(key, mesh_obj);
}

pub fn createMeshBuffer(self: *Self, key: []const u8, mesh_type: MeshBuffer.Type) !*MeshBuffer {
    const mesh_buf = try self.mesh_bufs.create(key);
    mesh_buf.* = .init(mesh_type);
    return mesh_buf;
}

pub fn insertMeshBuffer(self: *Self, key: []const u8, mesh_buf: *const MeshBuffer) !*MeshBuffer {
    return self.mesh_bufs.insert(key, mesh_buf);
}

pub fn createStorageBuffer(self: *Self, key: []const u8) !*GPUBuffer {
    const gpu_buf = try self.storage_bufs.create(key);
    gpu_buf.* = .empty;
    return gpu_buf;
}

pub fn insertStorageBuffer(
    self: *Self,
    key: []const u8,
    storage_buf: *const GPUBuffer,
) !*GPUBuffer {
    return self.storage_bufs.insert(key, storage_buf);
}

pub fn createMaterial(self: *Self, key: [:0]const u8) !*MaterialInfo {
    const material = try self.materials.create(key);
    material.* = .{ .name = key };
    return material;
}

pub fn insertMaterial(
    self: *Self,
    key: []const u8,
    info: *const MaterialInfo,
) !*MaterialInfo {
    return self.materials.insert(key, info);
}

pub fn insertTexture(
    self: *Self,
    key: []const u8,
    texture: *c.SDL_GPUTexture,
) !*c.SDL_GPUTexture {
    try self.textures.insert(self.allocator, key, texture);
    return texture;
}

pub fn createSampler(
    self: *Self,
    key: []const u8,
    info: *const c.SDL_GPUSamplerCreateInfo,
) !*c.SDL_GPUSampler {
    const sampler = c.SDL_CreateGPUSampler(self.gpu_device, info);
    if (sampler == null) {
        log.err("failed creating sampler: {s}", .{c.SDL_GetError()});
        return InitError.SamplerFailed;
    }
    errdefer c.SDL_ReleaseGPUSampler(self.gpu_device, sampler);
    try self.samplers.insert(self.allocator, key, sampler.?);
    return sampler.?;
}

fn createStencilTexture(
    self: *Self,
    engine: *const Engine,
    stencil_format: GPUTexture.Format,
) !*c.SDL_GPUTexture {
    var stencil_texture = try GPUTexture.init(self.gpu_device, &.{
        .type = .type_2d,
        .format = stencil_format,
        .usage = .init(.{ .depth_stencil_target = true }),
        .size = .{ @intCast(engine.window_size.x), @intCast(engine.window_size.y) },
    });
    if (stencil_texture.state() == .invalid) {
        log.err("failed creating stencil texture: {s}", .{c.SDL_GetError()});
        return InitError.BufferFailed;
    }
    errdefer stencil_texture.deinit(self.gpu_device);
    return self.insertTexture("stencil", stencil_texture.toOwnedGPUTexture());
}

fn createPipeline(
    self: *Self,
    key: []const u8,
    info: *const c.SDL_GPUGraphicsPipelineCreateInfo,
) !*c.SDL_GPUGraphicsPipeline {
    const graphics_pipeline = c.SDL_CreateGPUGraphicsPipeline(self.gpu_device, info);
    if (graphics_pipeline == null) {
        log.err("failed creating graphics pipeline: {s}", .{c.SDL_GetError()});
        return InitError.PipelineFailed;
    }
    errdefer c.SDL_ReleaseGPUGraphicsPipeline(self.gpu_device, graphics_pipeline);
    try self.pipelines.insert(self.allocator, key, graphics_pipeline.?);
    return graphics_pipeline.?;
}

pub fn render(
    self: *const Self,
    engine: *const Engine,
    scene: *const Scene,
    flat: *const Scene.Flattened,
    ui_ptr: ?*ui_mod.UI,
    items_iter: anytype,
) DrawError!bool {
    const section = sections.sub(.render);
    section.begin();

    section.sub(.acquire).begin();

    const gpu_device = self.gpu_device;
    const window = engine.window;
    const graphics_pipeline = self.pipelines.getPtr("default");
    // const origin_graphics_pipeline = self.pipelines.getPtr("origin");
    // const origin_mesh = self.mesh_bufs.getPtr("origin");
    const stencil_texture = self.textures.getPtr("stencil");
    const camera = scene.cameras.getPtr("default");
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
        section.end();
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
    @memcpy(uniform_buffer[0..16], math.matrix4x4.sliceConst(tr_view_projection));

    var frag_uniform_buffer = try fa.alloc(f32, 8 * 4);
    const frag_uniform_buffer_u32: []u32 = @ptrCast(frag_uniform_buffer);
    @memset(frag_uniform_buffer_u32, 0);
    @memcpy(frag_uniform_buffer[24..27], math.vector3.sliceConst(&camera.position));
    const light_counts = scene.lightCounts(flat);
    frag_uniform_buffer_u32[28] = light_counts.get(.ambient);
    frag_uniform_buffer_u32[29] = light_counts.get(.directional);
    frag_uniform_buffer_u32[30] = light_counts.get(.point);

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
                // .cycle = true,
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

        const default_texture = self.textures.getPtr("default");
        const default_sampler = self.samplers.getPtr("default");
        const lights_buffer = self.storage_bufs.getPtr("lights");

        c.SDL_BindGPUFragmentStorageBuffers(render_pass, 0, &lights_buffer.gpu_buf, 1);

        while (items_iter.next()) |_item| {
            const item: Item = _item;
            const object = self.mesh_objs.getPtr(item.object);

            for (object.sections.items) |buf_section| {
                const mtl = if (buf_section.material) |mtl| mtl else default_material;

                const material = self.materials.getPtr(mtl);
                const mesh_buf = object.mesh_buf;

                @memcpy(uniform_buffer[16..32], math.matrix4x4.sliceConst(item.transform));

                c.SDL_PushGPUVertexUniformData(
                    command_buffer,
                    0,
                    uniform_buffer.ptr,
                    @intCast(@sizeOf(f32) * uniform_buffer.len),
                );

                @memcpy(frag_uniform_buffer[0..24], material.uniformBuffer()[0..]);

                c.SDL_PushGPUFragmentUniformData(
                    command_buffer,
                    0,
                    frag_uniform_buffer.ptr,
                    @intCast(@sizeOf(f32) * frag_uniform_buffer.len),
                );

                const texture = if (material.texture) |tex| self.textures.getPtr(tex) else default_texture;
                const diffuse_map = if (material.diffuse_map) |tex| self.textures.getPtr(tex) else default_texture;
                const bump_map = if (material.bump_map) |tex| self.textures.getPtr(tex) else default_texture;

                c.SDL_BindGPUFragmentSamplers(render_pass, 0, &[_]c.SDL_GPUTextureSamplerBinding{
                    .{ .texture = texture, .sampler = default_sampler },
                    .{ .texture = diffuse_map, .sampler = default_sampler },
                    .{ .texture = bump_map, .sampler = default_sampler },
                }, 3);

                c.SDL_BindGPUVertexBuffers(render_pass, 0, &c.SDL_GPUBufferBinding{
                    .buffer = mesh_buf.gpu_bufs.getPtrConst(.vertex).gpu_buf,
                    .offset = 0,
                }, 1);

                switch (mesh_buf.type) {
                    .vertex => c.SDL_DrawGPUPrimitives(
                        render_pass,
                        @intCast(buf_section.len),
                        1,
                        @intCast(buf_section.offset),
                        0,
                    ),
                    .index => {
                        c.SDL_BindGPUIndexBuffer(render_pass, &c.SDL_GPUBufferBinding{
                            .buffer = mesh_buf.gpu_bufs.getPtrConst(.index).gpu_buf,
                            .offset = 0,
                        }, c.SDL_GPU_INDEXELEMENTSIZE_32BIT);
                        c.SDL_DrawGPUIndexedPrimitives(
                            render_pass,
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
        section.sub(.origin).begin();

        const origin_mesh = self.mesh_bufs.getPtr("origin");
        const origin_graphics_pipeline = self.pipelines.getPtr("origin");

        @memcpy(uniform_buffer[16..32], math.matrix4x4.sliceConst(&math.matrix4x4.identity));

        c.SDL_BindGPUVertexBuffers(render_pass, 0, &c.SDL_GPUBufferBinding{
            .buffer = origin_mesh.gpu_bufs.getPtrConst(.vertex).gpu_buf,
            .offset = 0,
        }, 1);
        c.SDL_BindGPUIndexBuffer(render_pass, &c.SDL_GPUBufferBinding{
            .buffer = origin_mesh.gpu_bufs.getPtrConst(.index).gpu_buf,
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
    // {
    //     const node = try editor.appendChildNode(root_node, root_id ++ ".cameras", "Cameras");
    //     var iter = self.cameras.map.iterator();
    //     var buf: [64]u8 = undefined;
    //     while (iter.next()) |entry| {
    //         const id = try std.fmt.bufPrint(&buf, "{s}#{s}", .{ @typeName(Camera), entry.key_ptr.* });
    //         _ = try editor.appendChild(
    //             node,
    //             entry.value_ptr.*.propertyEditor(),
    //             id,
    //             entry.key_ptr.*,
    //         );
    //     }
    // }
    return root_node;
}
