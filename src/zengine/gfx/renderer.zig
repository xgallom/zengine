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

const log = std.log.scoped(.gfx_renderer);
pub const sections = perf.sections(@This(), &.{ .init, .render });

const Self = @This();

gpu_device: *c.SDL_GPUDevice,
pipelines: PtrKeyMap(c.SDL_GPUGraphicsPipeline),
meshes: KeyMap(Mesh, .{}),
textures: PtrKeyMap(c.SDL_GPUTexture),
samplers: PtrKeyMap(c.SDL_GPUSampler),
cameras: KeyMap(Camera, .{}),

pub const InitError = error{
    GpuFailed,
    ShaderFailed,
    WindowFailed,
    PipelineFailed,
    BufferFailed,
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

pub fn init(engine: *const Engine) InitError!*Self {
    defer allocators.scratchFree();

    try sections.register();
    try sections.sub(.render)
        .sections(&.{ .acquire, .init, .items, .origin, .ui })
        .register();

    sections.sub(.init).begin();
    defer sections.sub(.init).end();

    const allocator = allocators.gpa();
    const window = engine.window;

    const gpu_device = c.SDL_CreateGPUDevice(
        c.SDL_GPU_SHADERFORMAT_SPIRV | c.SDL_GPU_SHADERFORMAT_MSL | c.SDL_GPU_SHADERFORMAT_DXIL,
        std.debug.runtime_safety,
        null,
    );
    if (gpu_device == null) {
        log.err("failed creating gpu device: {s}", .{c.SDL_GetError()});
        return InitError.GpuFailed;
    }
    errdefer c.SDL_DestroyGPUDevice(gpu_device);

    var pipelines = try PtrKeyMap(c.SDL_GPUGraphicsPipeline).init(allocator, 128);
    errdefer pipelines.deinit(allocator);
    var meshes = try KeyMap(Mesh, .{}).init(allocator, 128);
    errdefer meshes.deinit();
    var textures = try PtrKeyMap(c.SDL_GPUTexture).init(allocator, 128);
    errdefer textures.deinit(allocator);
    var samplers = try PtrKeyMap(c.SDL_GPUSampler).init(allocator, 128);
    errdefer samplers.deinit(allocator);
    var cameras = try KeyMap(Camera, .{}).init(allocator, 128);
    errdefer cameras.deinit();

    const vertex_shader = shader.open(.{
        .allocator = allocator,
        .gpu_device = gpu_device,
        .shader_path = "triangle_vert.vert",
        .stage = .vertex,
    }) catch |err| {
        log.err("failed creating vertex shader: {t}", .{err});
        return InitError.ShaderFailed;
    };
    defer shader.release(gpu_device, vertex_shader);

    const full_vertex_shader = shader.open(.{
        .allocator = allocator,
        .gpu_device = gpu_device,
        .shader_path = "full.vert",
        .stage = .vertex,
    }) catch |err| {
        log.err("failed creating full_vertex shader: {t}", .{err});
        return InitError.ShaderFailed;
    };
    defer shader.release(gpu_device, full_vertex_shader);

    const fragment_shader = shader.open(.{
        .allocator = allocator,
        .gpu_device = gpu_device,
        .shader_path = "creative.frag",
        .stage = .fragment,
    }) catch |err| {
        log.err("failed creating fragment shader: {t}", .{err});
        return InitError.ShaderFailed;
    };
    defer shader.release(gpu_device, fragment_shader);

    const origin_fragment_shader = shader.open(.{
        .allocator = allocator,
        .gpu_device = gpu_device,
        .shader_path = "rgb_color.frag",
        .stage = .fragment,
    }) catch |err| {
        log.err("failed creating origin fragment shader: {t}", .{err});
        return InitError.ShaderFailed;
    };
    defer shader.release(gpu_device, origin_fragment_shader);

    const full_fragment_shader = shader.open(.{
        .allocator = allocator,
        .gpu_device = gpu_device,
        .shader_path = "full.frag",
        .stage = .fragment,
    }) catch |err| {
        log.err("failed creating full fragment shader: {t}", .{err});
        return InitError.ShaderFailed;
    };
    defer shader.release(gpu_device, full_fragment_shader);

    const mesh = blk: {
        const mesh_path = global.assetPath("cat.obj") catch |err| {
            log.err("failed creating obj file path: {t}", .{err});
            return InitError.BufferFailed;
        };
        var result = obj_loader.loadFile(allocator, mesh_path) catch |err| {
            log.err("failed loading obj file: {t}", .{err});
            return InitError.BufferFailed;
        };
        errdefer result.mesh.deinit(gpu_device);

        if (result.mtl_path) |mtl_path| {
            const asset_path = global.assetPath(mtl_path) catch |err| {
                log.err("failed creating mtl file path: {t}", .{err});
                return InitError.BufferFailed;
            };
            var mtl = mtl_loader.loadFile(allocator, asset_path) catch |err| {
                log.err("failed loading mtl file: {t}", .{err});
                return InitError.BufferFailed;
            };
            for (mtl.materials.items) |item| {
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
            }
            mtl.deinit();
        }

        break :blk try meshes.insert("cow", result.mesh);
    };
    errdefer mesh.deinit(gpu_device);
    defer mesh.freeCpuData();

    try mesh.createGpuBuffers(gpu_device);

    const origin_mesh = blk: {
        var origin_mesh = try Mesh.init(allocator);
        errdefer origin_mesh.deinit(gpu_device);

        origin_mesh.appendVertices(math.Vertex, &.{
            .{ 0, 0, 0 },
            .{ 1, 0, 0 },
            .{ 0, 1, 0 },
            .{ 0, 0, 1 },
        }) catch |err| {
            log.err("failed appending origin mesh vertices: {t}", .{err});
            return InitError.BufferFailed;
        };
        origin_mesh.appendFaces(math.LineFaceIndex, &.{
            .{ 0, 1 },
            .{ 0, 2 },
            .{ 0, 3 },
        }) catch |err| {
            log.err("failed appending origin mesh faces: {t}", .{err});
            return InitError.BufferFailed;
        };

        break :blk try meshes.insert("origin", origin_mesh);
    };
    errdefer origin_mesh.deinit(gpu_device);
    defer origin_mesh.freeCpuData();

    try origin_mesh.createGpuBuffers(gpu_device);

    var stencil_format: c.SDL_GPUTextureFormat = undefined;
    if (c.SDL_GPUTextureSupportsFormat(
        gpu_device,
        c.SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT,
        c.SDL_GPU_TEXTURETYPE_2D,
        c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
    )) {
        stencil_format = c.SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT;
    } else if (c.SDL_GPUTextureSupportsFormat(
        gpu_device,
        c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT_S8_UINT,
        c.SDL_GPU_TEXTURETYPE_2D,
        c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
    )) {
        stencil_format = c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT_S8_UINT;
    } else {
        stencil_format = c.SDL_GPU_TEXTUREFORMAT_D32_FLOAT;
        log.err("no supported stencil format", .{});
    }

    if (!c.SDL_ClaimWindowForGPUDevice(gpu_device, window)) {
        log.err("failed claiming window for gpu device: {s}", .{c.SDL_GetError()});
        return InitError.WindowFailed;
    }

    var present_mode = @as(c_uint, c.SDL_GPU_PRESENTMODE_VSYNC);
    if (c.SDL_WindowSupportsGPUPresentMode(
        gpu_device,
        window,
        c.SDL_GPU_PRESENTMODE_MAILBOX,
    )) {
        present_mode = c.SDL_GPU_PRESENTMODE_MAILBOX;
    }

    if (!c.SDL_SetGPUSwapchainParameters(
        gpu_device,
        window,
        c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR,
        present_mode,
    )) {
        log.err("failed setting swapchain parameters: {s}", .{c.SDL_GetError()});
        return InitError.WindowFailed;
    }

    var graphics_pipeline_create_info = c.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &[_]c.SDL_GPUVertexBufferDescription{
                .{
                    .slot = 0,
                    .pitch = 3 * @sizeOf(math.Vertex),
                    // .pitch = @sizeOf(math.Vertex),
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
            .front_face = c.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
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
                .format = c.SDL_GetGPUSwapchainTextureFormat(gpu_device, window),
                .blend_state = .{},
            },
            .has_depth_stencil_target = true,
            .depth_stencil_format = stencil_format,
        },
    };

    const default_graphics_pipeline = blk: {
        const graphics_pipeline = c.SDL_CreateGPUGraphicsPipeline(
            gpu_device,
            &graphics_pipeline_create_info,
        );

        if (graphics_pipeline == null) {
            log.err("failed creating graphics pipeline: {s}", .{c.SDL_GetError()});
            return InitError.PipelineFailed;
        }
        errdefer c.SDL_ReleaseGPUGraphicsPipeline(gpu_device, graphics_pipeline);

        try pipelines.insert(allocator, "default", graphics_pipeline.?);
        break :blk graphics_pipeline.?;
    };
    errdefer c.SDL_ReleaseGPUGraphicsPipeline(gpu_device, default_graphics_pipeline);

    graphics_pipeline_create_info.fragment_shader = origin_fragment_shader;
    graphics_pipeline_create_info.primitive_type = c.SDL_GPU_PRIMITIVETYPE_LINELIST;
    graphics_pipeline_create_info.rasterizer_state.fill_mode = c.SDL_GPU_FILLMODE_LINE;

    const origin_graphics_pipeline = blk: {
        const graphics_pipeline = c.SDL_CreateGPUGraphicsPipeline(
            gpu_device,
            &graphics_pipeline_create_info,
        );

        if (graphics_pipeline == null) {
            log.err("failed creating origin graphics pipeline: {s}", .{c.SDL_GetError()});
            return InitError.PipelineFailed;
        }
        errdefer c.SDL_ReleaseGPUGraphicsPipeline(gpu_device, graphics_pipeline);

        try pipelines.insert(allocator, "origin", graphics_pipeline.?);
        break :blk graphics_pipeline.?;
    };
    errdefer c.SDL_ReleaseGPUGraphicsPipeline(gpu_device, origin_graphics_pipeline);

    graphics_pipeline_create_info.vertex_shader = full_vertex_shader;
    graphics_pipeline_create_info.fragment_shader = full_fragment_shader;
    graphics_pipeline_create_info.vertex_input_state = std.mem.zeroes(c.SDL_GPUVertexInputState);
    graphics_pipeline_create_info.primitive_type = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST;
    graphics_pipeline_create_info.rasterizer_state.fill_mode = c.SDL_GPU_FILLMODE_FILL;

    const full_graphics_pipeline = blk: {
        const graphics_pipeline = c.SDL_CreateGPUGraphicsPipeline(
            gpu_device,
            &graphics_pipeline_create_info,
        );
        if (graphics_pipeline == null) {
            log.err("failed creating full_graphics_pipeline: {s}", .{c.SDL_GetError()});
            return InitError.PipelineFailed;
        }
        errdefer c.SDL_ReleaseGPUGraphicsPipeline(gpu_device, graphics_pipeline);

        try pipelines.insert(allocator, "full", graphics_pipeline.?);
        break :blk graphics_pipeline.?;
    };
    errdefer c.SDL_ReleaseGPUGraphicsPipeline(gpu_device, full_graphics_pipeline);

    const stencil_texture = c.SDL_CreateGPUTexture(gpu_device, &c.SDL_GPUTextureCreateInfo{
        .type = c.SDL_GPU_TEXTURETYPE_2D,
        .format = stencil_format,
        .usage = c.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
        .width = @intCast(engine.window_size.x),
        .height = @intCast(engine.window_size.y),
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = c.SDL_GPU_SAMPLECOUNT_1,
    });
    if (stencil_texture == null) {
        log.err("failed creating stencil texture: {s}", .{c.SDL_GetError()});
        return InitError.BufferFailed;
    }
    errdefer c.SDL_ReleaseGPUTexture(gpu_device, stencil_texture);
    try textures.insert(allocator, "stencil", stencil_texture.?);

    const cube_texture = c.SDL_CreateGPUTexture(gpu_device, &c.SDL_GPUTextureCreateInfo{
        .type = c.SDL_GPU_TEXTURETYPE_2D,
        .format = c.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .usage = c.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | c.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = 64,
        .height = 64,
        .layer_count_or_depth = 6,
        .num_levels = 1,
    });
    if (cube_texture == null) {
        log.err("failed creating texture: {s}", .{c.SDL_GetError()});
        return InitError.BufferFailed;
    }
    errdefer c.SDL_ReleaseGPUTexture(gpu_device, cube_texture);
    try textures.insert(allocator, "cube", cube_texture.?);

    const sampler = c.SDL_CreateGPUSampler(gpu_device, &c.SDL_GPUSamplerCreateInfo{
        .min_filter = c.SDL_GPU_FILTER_NEAREST,
        .mag_filter = c.SDL_GPU_FILTER_NEAREST,
        .mipmap_mode = c.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
        .address_mode_u = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_w = c.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
    });
    if (sampler == null) {
        log.err("failed creating sampler: {s}", .{c.SDL_GetError()});
        return InitError.BufferFailed;
    }
    errdefer c.SDL_ReleaseGPUSampler(gpu_device, sampler);
    try samplers.insert(allocator, "default", sampler.?);

    {
        var mesh_upload_transfer_buffer = try mesh.createUploadTransferBuffer(gpu_device);
        defer mesh_upload_transfer_buffer.release(gpu_device);

        try mesh_upload_transfer_buffer.map(gpu_device);

        var origin_mesh_upload_transfer_buffer = try origin_mesh.createUploadTransferBuffer(gpu_device);
        defer origin_mesh_upload_transfer_buffer.release(gpu_device);

        try origin_mesh_upload_transfer_buffer.map(gpu_device);

        const command_buffer = c.SDL_AcquireGPUCommandBuffer(gpu_device);
        if (command_buffer == null) {
            log.err("failed to acquire gpu_command_buffer: {s}", .{c.SDL_GetError()});
            return InitError.CommandBufferFailed;
        }
        errdefer _ = c.SDL_CancelGPUCommandBuffer(command_buffer);

        {
            const copy_pass = c.SDL_BeginGPUCopyPass(command_buffer);
            if (copy_pass == null) {
                log.err("failed to begin copy_pass: {s}", .{c.SDL_GetError()});
                return InitError.CopyPassFailed;
            }

            mesh_upload_transfer_buffer.upload(copy_pass);
            origin_mesh_upload_transfer_buffer.upload(copy_pass);

            c.SDL_EndGPUCopyPass(copy_pass);
        }

        const clear_colors = [_]c.SDL_FColor{
            .{ .r = 1, .g = 0, .b = 0, .a = 1 },
            .{ .r = 0, .g = 1, .b = 1, .a = 1 },
            .{ .r = 0, .g = 1, .b = 0, .a = 1 },
            .{ .r = 1, .g = 0, .b = 1, .a = 1 },
            .{ .r = 0, .g = 0, .b = 1, .a = 1 },
            .{ .r = 1, .g = 1, .b = 0, .a = 1 },
        };

        inline for (0..clear_colors.len) |layer| {
            const render_pass = c.SDL_BeginGPURenderPass(
                command_buffer,
                &c.SDL_GPUColorTargetInfo{
                    .texture = cube_texture,
                    .layer_or_depth_plane = @as(u32, layer),
                    .clear_color = clear_colors[layer],
                    .load_op = c.SDL_GPU_LOADOP_CLEAR,
                    .store_op = c.SDL_GPU_STOREOP_STORE,
                },
                1,
                null,
            );

            if (render_pass == null) {
                log.err("failed to begin render_pass[{}]: {s}", .{ layer, c.SDL_GetError() });
                return InitError.RenderPassFailed;
            }

            c.SDL_EndGPURenderPass(render_pass);
        }

        if (!c.SDL_SubmitGPUCommandBuffer(command_buffer)) {
            log.err("failed submitting command_buffer: {s}", .{c.SDL_GetError()});
            return InitError.CommandBufferFailed;
        }
    }

    // var camera_position: math.Vector3 = .{ -1, 1.1, -1.2 };
    var camera_position: math.Vector3 = .{ -1, 0, 0 };
    var camera_direction: math.Vector3 = undefined;
    const target = math.vector3.zero;

    math.vector3.scale(&camera_position, 5);
    math.vector3.lookAt(&camera_direction, &camera_position, &target);

    _ = try cameras.insert("default", .{
        .kind = .perspective,
        .position = camera_position,
        .direction = camera_direction,
    });

    const result = try allocators.global().create(Self);
    result.* = .{
        .gpu_device = gpu_device.?,
        .pipelines = pipelines,
        .meshes = meshes,
        .textures = textures,
        .samplers = samplers,
        .cameras = cameras,
    };
    return result;
}

pub fn deinit(self: *Self, engine: *const Engine) void {
    _ = c.SDL_WaitForGPUIdle(self.gpu_device);
    const allocator = allocators.gpa();

    defer c.SDL_DestroyGPUDevice(self.gpu_device);
    defer {
        for (self.meshes.map.map.values()) |mesh| mesh.deinit(self.gpu_device);
        self.meshes.deinit();
    }
    defer c.SDL_ReleaseWindowFromGPUDevice(self.gpu_device, engine.window);
    defer {
        for (self.pipelines.map.values()) |graphics_pipeline| c.SDL_ReleaseGPUGraphicsPipeline(
            self.gpu_device,
            graphics_pipeline,
        );
        self.pipelines.deinit(allocator);
    }
    defer {
        for (self.textures.map.values()) |texture| c.SDL_ReleaseGPUTexture(self.gpu_device, texture);
        self.textures.deinit(allocator);
    }
    defer {
        for (self.samplers.map.values()) |sampler| c.SDL_ReleaseGPUSampler(self.gpu_device, sampler);
        self.samplers.deinit(allocator);
    }
    defer self.cameras.deinit();
}

pub const Item = struct {
    mesh: []const u8,
    position: math.Vector3,
    rotation: math.Euler,
    scale: math.Vector3,

    pub const exclude_properties: ui_mod.property_editor.PropertyList = &.{.mesh};

    pub fn propertyEditor(self: *Item) ui_mod.PropertyEditor(Item) {
        return .init(self);
    }
};

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

    const tr_world = try fa.create(math.Matrix4x4);
    const tr_projection = try fa.create(math.Matrix4x4);
    const tr_camera = try fa.create(math.Matrix4x4);
    const tr_view = try fa.create(math.Matrix4x4);
    const tr_view_projection = try fa.create(math.Matrix4x4);
    const tr_model = try fa.create(math.Matrix4x4);

    const time_s = global.timeSinceStart().toFloat().toValue32(.s);
    const aspect_ratio = @as(f32, @floatFromInt(engine.window_size.x)) / @as(f32, @floatFromInt(engine.window_size.y));
    const mouse_x = engine.mouse_pos.x / @as(f32, @floatFromInt(engine.window_size.x));
    const mouse_y = engine.mouse_pos.y / @as(f32, @floatFromInt(engine.window_size.y));
    // const pi = std.math.pi;

    math.matrix4x4.worldTransform(tr_world);
    // math.matrix4x4.rotateEuler(tr_world, &.{ -time_s * pi / 10, -time_s * pi / 9, 0 }, .xyz);
    camera.projection(
        tr_projection,
        @floatFromInt(engine.window_size.x),
        @floatFromInt(engine.window_size.y),
        7.5,
        10_000.0,
    );
    // math.matrix4x4.perspectiveFov(
    //     projection,
    //     std.math.degreesToRadians(self.fov),
    //     @floatFromInt(engine.window_size.x),
    //     @floatFromInt(engine.window_size.y),
    //     7.5,
    //     10_000.0,
    // );
    camera.transform(tr_camera);
    math.matrix4x4.dot(tr_view, tr_camera, tr_world);
    math.matrix4x4.dot(tr_view_projection, tr_projection, tr_view);

    log.debug("camera_position: {any}", .{camera.position});
    log.debug("camera_direction: {any}", .{camera.direction});

    var uniform_buffer = try fa.alloc(f32, 32);
    @memcpy(uniform_buffer[0..16], math.matrix4x4.sliceLenConst(tr_view_projection));

    var frag_uniform_buffer: [4]f32 = .{ time_s, aspect_ratio, mouse_x, mouse_y };
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
        c.SDL_PushGPUFragmentUniformData(
            command_buffer,
            0,
            &frag_uniform_buffer,
            @sizeOf(@TypeOf(frag_uniform_buffer)),
        );

        while (items_iter.next()) |_item| {
            const item: Item = _item;
            const mesh = self.meshes.getPtr(item.mesh);

            {
                const result = tr_model;
                result.* = math.matrix4x4.identity;

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

            c.SDL_BindGPUVertexBuffers(render_pass, 0, &c.SDL_GPUBufferBinding{
                .buffer = mesh.vert_buf,
                .offset = 0,
            }, 1);

            if (mesh.index_buf != null) {
                c.SDL_BindGPUIndexBuffer(render_pass, &c.SDL_GPUBufferBinding{
                    .buffer = mesh.index_buf,
                    .offset = 0,
                }, c.SDL_GPU_INDEXELEMENTSIZE_32BIT);
                c.SDL_DrawGPUIndexedPrimitives(render_pass, @intCast(mesh.index_len), 1, 0, 0, 0);
                log.info("index {}", .{mesh.vert_len});
            } else {
                c.SDL_DrawGPUPrimitives(render_pass, @intCast(mesh.vert_len), 1, 0, 0);
                log.info("vertex {}", .{mesh.vert_len});
            }
        }

        section.sub(.items).begin();
        // section.sub(.origin).begin();
        //
        // tr_model.* = math.matrix4x4.identity;
        // @memcpy(uniform_buffer[16..32], math.matrix4x4.sliceLenConst(tr_model));
        //
        // c.SDL_BindGPUVertexBuffers(render_pass, 0, &c.SDL_GPUBufferBinding{
        //     .buffer = origin_mesh.vert_buf,
        //     .offset = 0,
        // }, 1);
        // c.SDL_BindGPUIndexBuffer(render_pass, &c.SDL_GPUBufferBinding{
        //     .buffer = origin_mesh.index_buf,
        //     .offset = 0,
        // }, c.SDL_GPU_INDEXELEMENTSIZE_32BIT);
        // c.SDL_PushGPUVertexUniformData(command_buffer, 0, uniform_buffer.ptr, @intCast(@sizeOf(f32) * uniform_buffer.len));
        // c.SDL_BindGPUGraphicsPipeline(render_pass, origin_graphics_pipeline);
        //
        // origin_frag_uniform_buffer = .{ 1, 0, 0, 1 };
        // c.SDL_PushGPUFragmentUniformData(command_buffer, 0, &origin_frag_uniform_buffer, @sizeOf(@TypeOf(origin_frag_uniform_buffer)));
        // c.SDL_DrawGPUIndexedPrimitives(render_pass, 2, 1, 0, 0, 0);
        //
        // origin_frag_uniform_buffer = .{ 0, 1, 0, 1 };
        // c.SDL_PushGPUFragmentUniformData(command_buffer, 0, &origin_frag_uniform_buffer, @sizeOf(@TypeOf(origin_frag_uniform_buffer)));
        // c.SDL_DrawGPUIndexedPrimitives(render_pass, 2, 1, 2, 0, 0);
        //
        // origin_frag_uniform_buffer = .{ 0, 0, 1, 1 };
        // c.SDL_PushGPUFragmentUniformData(command_buffer, 0, &origin_frag_uniform_buffer, @sizeOf(@TypeOf(origin_frag_uniform_buffer)));
        // c.SDL_DrawGPUIndexedPrimitives(render_pass, 2, 1, 4, 0, 0);
        //
        // section.sub(.origin).end();

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

pub fn propertyEditorNode(self: *Self, editor: *ui_mod.PropertyEditorWindow, parent: *ui_mod.PropertyEditorWindow.Item) !void {
    const root_id = @typeName(Self);
    const root_node = try editor.appendChildNode(parent, root_id, "Renderer");

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
}
