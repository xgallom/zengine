//!
//! The zengine renderer implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const Engine = @import("../Engine.zig");
const sdl = @import("../ext.zig").sdl;
const global = @import("../global.zig");
const math = @import("../math.zig");
const perf = @import("../perf.zig");
const LineMesh = @import("mesh.zig").LineMesh;
const obj_loader = @import("obj_loader.zig");
const shader = @import("shader.zig");
const TriangleMesh = @import("mesh.zig").TriangleMesh;

const log = std.log.scoped(.gfx_renderer);
pub const sections = perf.sections(@This(), &.{ .init, .draw });

const Self = @This();

gpu_device: ?*sdl.SDL_GPUDevice,
graphics_pipeline: ?*sdl.SDL_GPUGraphicsPipeline,
origin_graphics_pipeline: ?*sdl.SDL_GPUGraphicsPipeline,
full_graphics_pipeline: ?*sdl.SDL_GPUGraphicsPipeline,

mesh: TriangleMesh,
origin_mesh: LineMesh,
viewport: sdl.SDL_GPUViewport,
texture: ?*sdl.SDL_GPUTexture,
stencil_texture: ?*sdl.SDL_GPUTexture,
sampler: ?*sdl.SDL_GPUSampler,
camera_position: math.Vector3,
camera_direction: math.Vector3,
camera_up: math.Vector3,
fov: math.Scalar,

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
    try sections.sub(.draw)
        .sections(&.{ .init, .cow1, .cow2, .cow3, .origin })
        .register();

    sections.sub(.init).begin();
    defer sections.sub(.init).end();

    const allocator = allocators.gpa();
    const window = engine.window;

    const gpu_device = sdl.SDL_CreateGPUDevice(
        sdl.SDL_GPU_SHADERFORMAT_SPIRV | sdl.SDL_GPU_SHADERFORMAT_MSL | sdl.SDL_GPU_SHADERFORMAT_DXIL,
        true,
        null,
    );
    if (gpu_device == null) {
        log.err("failed creating gpu_device: {s}", .{sdl.SDL_GetError()});
        return InitError.GpuFailed;
    }
    errdefer sdl.SDL_DestroyGPUDevice(gpu_device);

    const vertex_shader = shader.open(.{
        .allocator = allocator,
        .gpu_device = gpu_device,
        .shader_path = "triangle_vert.vert",
        .stage = .vertex,
    }) catch |err| {
        log.err("failed creating vertex_shader: {t}", .{err});
        return InitError.ShaderFailed;
    };
    defer shader.release(gpu_device, vertex_shader);

    const full_vertex_shader = shader.open(.{
        .allocator = allocator,
        .gpu_device = gpu_device,
        .shader_path = "full.vert",
        .stage = .vertex,
    }) catch |err| {
        log.err("failed creating full_vertex_shader: {t}", .{err});
        return InitError.ShaderFailed;
    };
    defer shader.release(gpu_device, full_vertex_shader);

    const fragment_shader = shader.open(.{
        .allocator = allocator,
        .gpu_device = gpu_device,
        .shader_path = "creative.frag",
        .stage = .fragment,
    }) catch |err| {
        log.err("failed creating fragment_shader: {t}", .{err});
        return InitError.ShaderFailed;
    };
    defer shader.release(gpu_device, fragment_shader);

    const origin_fragment_shader = shader.open(.{
        .allocator = allocator,
        .gpu_device = gpu_device,
        .shader_path = "rgb_color.frag",
        .stage = .fragment,
    }) catch |err| {
        log.err("failed creating origin_fragment_shader: {t}", .{err});
        return InitError.ShaderFailed;
    };
    defer shader.release(gpu_device, origin_fragment_shader);

    const full_fragment_shader = shader.open(.{
        .allocator = allocator,
        .gpu_device = gpu_device,
        .shader_path = "full.frag",
        .stage = .fragment,
    }) catch |err| {
        log.err("failed creating full_fragment_shader: {t}", .{err});
        return InitError.ShaderFailed;
    };
    defer shader.release(gpu_device, full_fragment_shader);

    const path = std.fs.path.join(
        allocators.scratch(),
        &.{ global.assetsPath(), "cow_nonormals.obj" },
    ) catch |err| {
        log.err("failed creating obj file path: {t}", .{err});
        return InitError.BufferFailed;
    };

    var mesh = obj_loader.loadFile(allocator, path) catch |err| {
        log.err("failed loading mesh from obj file: {t}", .{err});
        return InitError.BufferFailed;
    };
    defer mesh.deinit();

    try mesh.createGpuBuffers(gpu_device);
    errdefer mesh.releaseGpuBuffers(gpu_device);

    var origin_mesh = LineMesh.init(allocator);
    defer origin_mesh.deinit();
    origin_mesh.appendVertices(&.{
        .{ 0, 0, 0 },
        .{ 1, 0, 0 },
        .{ 0, 1, 0 },
        .{ 0, 0, 1 },
    }) catch |err| {
        log.err("failed appending origin_mesh vertices: {t}", .{err});
        return InitError.BufferFailed;
    };
    origin_mesh.appendFaces(&.{
        .{ 0, 1 },
        .{ 0, 2 },
        .{ 0, 3 },
    }) catch |err| {
        log.err("failed appending origin_mesh faces: {t}", .{err});
        return InitError.BufferFailed;
    };

    try origin_mesh.createGpuBuffers(gpu_device);
    errdefer origin_mesh.releaseGpuBuffers(gpu_device);

    var stencil_format: sdl.SDL_GPUTextureFormat = undefined;
    if (sdl.SDL_GPUTextureSupportsFormat(
        gpu_device,
        sdl.SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT,
        sdl.SDL_GPU_TEXTURETYPE_2D,
        sdl.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
    )) {
        stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT;
    } else if (sdl.SDL_GPUTextureSupportsFormat(
        gpu_device,
        sdl.SDL_GPU_TEXTUREFORMAT_D32_FLOAT_S8_UINT,
        sdl.SDL_GPU_TEXTURETYPE_2D,
        sdl.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
    )) {
        stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_D32_FLOAT_S8_UINT;
    } else {
        stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_D32_FLOAT;
        log.err("no supported stencil format", .{});
    }

    if (!sdl.SDL_ClaimWindowForGPUDevice(gpu_device, window)) {
        log.err("failed claiming window for gpu_device: {s}", .{sdl.SDL_GetError()});
        return InitError.WindowFailed;
    }

    var present_mode = @as(c_uint, sdl.SDL_GPU_PRESENTMODE_VSYNC);
    if (sdl.SDL_WindowSupportsGPUPresentMode(
        gpu_device,
        window,
        sdl.SDL_GPU_PRESENTMODE_MAILBOX,
    )) {
        present_mode = sdl.SDL_GPU_PRESENTMODE_MAILBOX;
    }

    if (!sdl.SDL_SetGPUSwapchainParameters(
        gpu_device,
        window,
        sdl.SDL_GPU_SWAPCHAINCOMPOSITION_SDR,
        present_mode,
    )) {
        log.err("failed setting swapchain parameters: {s}", .{sdl.SDL_GetError()});
        return InitError.WindowFailed;
    }

    var graphics_pipeline_create_info = sdl.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &[_]sdl.SDL_GPUVertexBufferDescription{
                .{
                    .slot = 0,
                    .input_rate = sdl.SDL_GPU_VERTEXINPUTRATE_VERTEX,
                    .instance_step_rate = 0,
                    .pitch = @sizeOf(math.Vertex),
                },
            },
            .num_vertex_buffers = 1,
            .vertex_attributes = &[_]sdl.SDL_GPUVertexAttribute{
                .{
                    .location = 0,
                    .buffer_slot = 0,
                    .format = sdl.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
                    .offset = 0,
                },
            },
            .num_vertex_attributes = 1,
        },
        .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .fill_mode = sdl.SDL_GPU_FILLMODE_FILL,
            .cull_mode = sdl.SDL_GPU_CULLMODE_NONE,
            .front_face = sdl.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
            .enable_depth_clip = true,
        },
        .depth_stencil_state = .{
            .compare_op = sdl.SDL_GPU_COMPAREOP_LESS,
            .compare_mask = 0xFF,
            .write_mask = 0xFF,
            .enable_depth_test = true,
            .enable_depth_write = true,
        },
        .target_info = .{
            .num_color_targets = 1,
            .color_target_descriptions = &sdl.SDL_GPUColorTargetDescription{
                .format = sdl.SDL_GetGPUSwapchainTextureFormat(gpu_device, window),
                .blend_state = .{},
            },
            .has_depth_stencil_target = true,
            .depth_stencil_format = stencil_format,
        },
    };

    const graphics_pipeline = sdl.SDL_CreateGPUGraphicsPipeline(gpu_device, &graphics_pipeline_create_info);

    if (graphics_pipeline == null) {
        log.err("failed creating graphics_pipeline: {s}", .{sdl.SDL_GetError()});
        return InitError.PipelineFailed;
    }
    errdefer sdl.SDL_ReleaseGPUGraphicsPipeline(gpu_device, graphics_pipeline);

    graphics_pipeline_create_info.fragment_shader = origin_fragment_shader;
    graphics_pipeline_create_info.primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_LINELIST;
    graphics_pipeline_create_info.rasterizer_state.fill_mode = sdl.SDL_GPU_FILLMODE_LINE;

    const origin_graphics_pipeline = sdl.SDL_CreateGPUGraphicsPipeline(gpu_device, &graphics_pipeline_create_info);
    if (origin_graphics_pipeline == null) {
        log.err("failed creating origin_graphics_pipeline: {s}", .{sdl.SDL_GetError()});
        return InitError.PipelineFailed;
    }
    errdefer sdl.SDL_ReleaseGPUGraphicsPipeline(gpu_device, origin_graphics_pipeline);

    graphics_pipeline_create_info.vertex_shader = full_vertex_shader;
    graphics_pipeline_create_info.fragment_shader = full_fragment_shader;
    graphics_pipeline_create_info.vertex_input_state = std.mem.zeroes(sdl.SDL_GPUVertexInputState);
    graphics_pipeline_create_info.primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST;
    graphics_pipeline_create_info.rasterizer_state.fill_mode = sdl.SDL_GPU_FILLMODE_FILL;

    const full_graphics_pipeline = sdl.SDL_CreateGPUGraphicsPipeline(gpu_device, &graphics_pipeline_create_info);

    if (full_graphics_pipeline == null) {
        log.err("failed creating full_graphics_pipeline: {s}", .{sdl.SDL_GetError()});
        return InitError.PipelineFailed;
    }
    errdefer sdl.SDL_ReleaseGPUGraphicsPipeline(gpu_device, full_graphics_pipeline);

    const stencil_texture = sdl.SDL_CreateGPUTexture(gpu_device, &sdl.SDL_GPUTextureCreateInfo{
        .type = sdl.SDL_GPU_TEXTURETYPE_2D,
        .format = stencil_format,
        .usage = sdl.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
        .width = @intCast(engine.window_size.x),
        .height = @intCast(engine.window_size.y),
        .layer_count_or_depth = 1,
        .num_levels = 1,
        .sample_count = sdl.SDL_GPU_SAMPLECOUNT_1,
    });
    if (stencil_texture == null) {
        log.err("failed creating stencil_texture: {s}", .{sdl.SDL_GetError()});
        return InitError.BufferFailed;
    }
    errdefer sdl.SDL_ReleaseGPUTexture(gpu_device, stencil_texture);

    const texture = sdl.SDL_CreateGPUTexture(gpu_device, &sdl.SDL_GPUTextureCreateInfo{
        .type = sdl.SDL_GPU_TEXTURETYPE_CUBE,
        .format = sdl.SDL_GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
        .usage = sdl.SDL_GPU_TEXTUREUSAGE_COLOR_TARGET | sdl.SDL_GPU_TEXTUREUSAGE_SAMPLER,
        .width = 64,
        .height = 64,
        .layer_count_or_depth = 6,
        .num_levels = 1,
    });
    if (texture == null) {
        log.err("failed creating texture: {s}", .{sdl.SDL_GetError()});
        return InitError.BufferFailed;
    }
    errdefer sdl.SDL_ReleaseGPUTexture(gpu_device, texture);

    const sampler = sdl.SDL_CreateGPUSampler(gpu_device, &sdl.SDL_GPUSamplerCreateInfo{
        .min_filter = sdl.SDL_GPU_FILTER_NEAREST,
        .mag_filter = sdl.SDL_GPU_FILTER_NEAREST,
        .mipmap_mode = sdl.SDL_GPU_SAMPLERMIPMAPMODE_NEAREST,
        .address_mode_u = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_v = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
        .address_mode_w = sdl.SDL_GPU_SAMPLERADDRESSMODE_CLAMP_TO_EDGE,
    });
    if (sampler == null) {
        log.err("failed creating sampler: {s}", .{sdl.SDL_GetError()});
        return InitError.BufferFailed;
    }
    errdefer sdl.SDL_ReleaseGPUSampler(gpu_device, sampler);

    const mesh_upload_transfer_buffer = try mesh.createUploadTransferBuffer(gpu_device);
    defer mesh_upload_transfer_buffer.release(gpu_device);

    try mesh_upload_transfer_buffer.map(gpu_device);

    const origin_mesh_upload_transfer_buffer = try origin_mesh.createUploadTransferBuffer(gpu_device);
    defer origin_mesh_upload_transfer_buffer.release(gpu_device);

    try origin_mesh_upload_transfer_buffer.map(gpu_device);

    const command_buffer = sdl.SDL_AcquireGPUCommandBuffer(gpu_device);
    if (command_buffer == null) {
        log.err("failed to acquire gpu_command_buffer: {s}", .{sdl.SDL_GetError()});
        return InitError.CommandBufferFailed;
    }
    errdefer _ = sdl.SDL_CancelGPUCommandBuffer(command_buffer);

    {
        const copy_pass = sdl.SDL_BeginGPUCopyPass(command_buffer);
        if (copy_pass == null) {
            log.err("failed to begin copy_pass: {s}", .{sdl.SDL_GetError()});
            return InitError.CopyPassFailed;
        }

        mesh_upload_transfer_buffer.upload(copy_pass);
        origin_mesh_upload_transfer_buffer.upload(copy_pass);

        sdl.SDL_EndGPUCopyPass(copy_pass);
    }

    const clear_colors = [_]sdl.SDL_FColor{
        .{ .r = 1, .g = 0, .b = 0, .a = 1 },
        .{ .r = 0, .g = 1, .b = 1, .a = 1 },
        .{ .r = 0, .g = 1, .b = 0, .a = 1 },
        .{ .r = 1, .g = 0, .b = 1, .a = 1 },
        .{ .r = 0, .g = 0, .b = 1, .a = 1 },
        .{ .r = 1, .g = 1, .b = 0, .a = 1 },
    };

    inline for (0..clear_colors.len) |layer| {
        const render_pass = sdl.SDL_BeginGPURenderPass(
            command_buffer,
            &sdl.SDL_GPUColorTargetInfo{
                .texture = texture,
                .layer_or_depth_plane = @as(u32, layer),
                .clear_color = clear_colors[layer],
                .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
                .store_op = sdl.SDL_GPU_STOREOP_STORE,
            },
            1,
            null,
        );

        if (render_pass == null) {
            log.err("failed to begin render_pass[{}]: {s}", .{ layer, sdl.SDL_GetError() });
            return InitError.RenderPassFailed;
        }

        sdl.SDL_EndGPURenderPass(render_pass);
    }

    if (!sdl.SDL_SubmitGPUCommandBuffer(command_buffer)) {
        log.err("failed submitting command_buffer: {s}", .{sdl.SDL_GetError()});
        return InitError.CommandBufferFailed;
    }

    // DEAD_CODE
    const viewport = sdl.SDL_GPUViewport{
        .x = -1,
        .y = -1,
        .w = 2,
        .h = 2,
        .min_depth = 0,
        .max_depth = 1,
    };

    const result = try allocators.global().create(Self);
    result.* = .{
        .gpu_device = gpu_device,
        .graphics_pipeline = graphics_pipeline,
        .origin_graphics_pipeline = origin_graphics_pipeline,
        .full_graphics_pipeline = full_graphics_pipeline,
        .mesh = mesh,
        .origin_mesh = origin_mesh,
        .viewport = viewport,
        .texture = texture,
        .stencil_texture = stencil_texture,
        .sampler = sampler,
        .camera_position = .{ 10, 10, 10 },
        .camera_direction = .{ -1, -1, -1 },
        .camera_up = comptime global.cameraUp(),
        .fov = 38.5978,
    };
    return result;
}

pub fn deinit(self: *Self, engine: *const Engine) void {
    defer sdl.SDL_DestroyGPUDevice(self.gpu_device);
    defer self.mesh.releaseGpuBuffers(self.gpu_device);
    defer self.origin_mesh.releaseGpuBuffers(self.gpu_device);
    defer sdl.SDL_ReleaseWindowFromGPUDevice(self.gpu_device, engine.window);
    defer sdl.SDL_ReleaseGPUGraphicsPipeline(self.gpu_device, self.graphics_pipeline);
    defer sdl.SDL_ReleaseGPUGraphicsPipeline(self.gpu_device, self.origin_graphics_pipeline);
    defer sdl.SDL_ReleaseGPUTexture(self.gpu_device, self.texture);
    defer sdl.SDL_ReleaseGPUSampler(self.gpu_device, self.sampler);
    defer sdl.SDL_ReleaseGPUTexture(self.gpu_device, self.stencil_texture);
}

pub fn draw(self: *const Self, engine: *const Engine) DrawError!bool {
    const section = sections.sub(.draw);
    section.begin();
    defer section.end();

    section.sub(.cow1).beginPaused();
    section.sub(.cow2).beginPaused();
    section.sub(.cow3).beginPaused();
    defer section.sub(.cow1).end();
    defer section.sub(.cow2).end();
    defer section.sub(.cow3).end();

    section.sub(.init).begin();

    log.debug("draw", .{});
    const gpu_device = self.gpu_device;
    const window = engine.window;
    const graphics_pipeline = self.graphics_pipeline;
    const origin_graphics_pipeline = self.origin_graphics_pipeline;
    // const full_graphics_pipeline = self.full_graphics_pipeline;

    const fa = allocators.frame();

    log.debug("command_buffer", .{});
    const command_buffer = sdl.SDL_AcquireGPUCommandBuffer(gpu_device);
    if (command_buffer == null) {
        log.err("failed to acquire command_buffer: {s}", .{sdl.SDL_GetError()});
        return DrawError.DrawFailed;
    }
    errdefer _ = sdl.SDL_CancelGPUCommandBuffer(command_buffer);

    log.debug("swapchain_texture", .{});
    var swapchain_texture: ?*sdl.SDL_GPUTexture = undefined;
    if (!sdl.SDL_AcquireGPUSwapchainTexture(command_buffer, window, &swapchain_texture, null, null)) {
        log.err("failed to acquire swapchain_texture: {s}", .{sdl.SDL_GetError()});
        return DrawError.DrawFailed;
    }
    if (swapchain_texture == null) {
        log.debug("skip draw", .{});
        return false;
    }

    const world = try fa.create(math.Matrix4x4);
    const projection = try fa.create(math.Matrix4x4);
    const camera = try fa.create(math.Matrix4x4);
    const view = try fa.create(math.Matrix4x4);
    const view_projection = try fa.create(math.Matrix4x4);

    math.matrix4x4.worldTransform(world);
    math.matrix4x4.perspectiveFov(
        projection,
        std.math.degreesToRadians(self.fov),
        @floatFromInt(engine.window_size.x),
        @floatFromInt(engine.window_size.y),
        1.0,
        800.0,
    );
    math.matrix4x4.camera(
        camera,
        &self.camera_position,
        &self.camera_direction,
        &self.camera_up,
    );
    math.matrix4x4.dot(view, camera, world);
    math.matrix4x4.dot(view_projection, projection, view);

    const time_s = global.timeSinceStart().toFloat().toValue32(.s);
    const aspect_ratio = @as(f32, @floatFromInt(engine.window_size.x)) / @as(f32, @floatFromInt(engine.window_size.y));
    const mouse_x = engine.mouse_pos.x / @as(f32, @floatFromInt(engine.window_size.x));
    const mouse_y = engine.mouse_pos.y / @as(f32, @floatFromInt(engine.window_size.y));
    const pi = std.math.pi;

    const model = try fa.create(math.Matrix4x4);

    log.debug("camera_position: {any}", .{self.camera_position});
    log.debug("camera_direction: {any}", .{self.camera_direction});

    var uniform_buffer = try fa.alloc(f32, 32);
    @memcpy(uniform_buffer[0..16], math.matrix4x4.sliceLenConst(view_projection));

    // const frag_uniform_buffer: [1]f32 = .{time_s};
    var frag_uniform_buffer: [4]f32 = .{ time_s, aspect_ratio, mouse_x, mouse_y };
    var origin_frag_uniform_buffer: [4]f32 = .{ 1, 0, 1, 1 };

    // {
    //     const render_pass = sdl.SDL_BeginGPURenderPass(
    //         command_buffer,
    //         &sdl.SDL_GPUColorTargetInfo{
    //             .texture = swapchain_texture,
    //             .clear_color = sdl.SDL_FColor{ .r = 0.025, .g = 0, .b = 0.05, .a = 1 },
    //             .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
    //             .store_op = sdl.SDL_GPU_STOREOP_STORE,
    //         },
    //         1,
    //         &sdl.SDL_GPUDepthStencilTargetInfo{
    //             .texture = self.stencil_texture,
    //             .clear_depth = 1,
    //             .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
    //             .store_op = sdl.SDL_GPU_STOREOP_STORE,
    //             .stencil_load_op = sdl.SDL_GPU_LOADOP_DONT_CARE,
    //             .stencil_store_op = sdl.SDL_GPU_STOREOP_DONT_CARE,
    //             // .cycle = true,
    //         },
    //     );
    //     if (render_pass == null) {
    //         log.err("failed to begin render_pass: {s}", .{sdl.SDL_GetError()});
    //         return DrawError.DrawFailed;
    //     }
    //
    //     sdl.SDL_PushGPUVertexUniformData(command_buffer, 0, uniform_buffer, @sizeOf(@TypeOf(uniform_buffer)));
    //     sdl.SDL_PushGPUFragmentUniformData(command_buffer, 0, &frag_uniform_buffer, @sizeOf(@TypeOf(frag_uniform_buffer)));
    //     sdl.SDL_BindGPUGraphicsPipeline(render_pass, full_graphics_pipeline);
    //     log.debug("draw cow", .{});
    //     sdl.SDL_DrawGPUPrimitives(render_pass, 6, 1, 0, 0);
    //
    //     log.debug("end render_pass", .{});
    //     sdl.SDL_EndGPURenderPass(render_pass);
    // }

    {
        log.debug("render_pass", .{});
        const render_pass = sdl.SDL_BeginGPURenderPass(
            command_buffer,
            &sdl.SDL_GPUColorTargetInfo{
                .texture = swapchain_texture,
                .clear_color = sdl.SDL_FColor{ .r = 0.025, .g = 0, .b = 0.05, .a = 1 },
                .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
                .store_op = sdl.SDL_GPU_STOREOP_STORE,
            },
            1,
            &sdl.SDL_GPUDepthStencilTargetInfo{
                .texture = self.stencil_texture,
                .clear_depth = 1,
                .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
                .store_op = sdl.SDL_GPU_STOREOP_STORE,
                .stencil_load_op = sdl.SDL_GPU_LOADOP_DONT_CARE,
                .stencil_store_op = sdl.SDL_GPU_STOREOP_DONT_CARE,
                // .cycle = true,
            },
        );
        if (render_pass == null) {
            log.err("failed to begin render_pass: {s}", .{sdl.SDL_GetError()});
            return DrawError.DrawFailed;
        }

        log.debug("bind", .{});
        sdl.SDL_BindGPUVertexBuffers(render_pass, 0, &sdl.SDL_GPUBufferBinding{
            .buffer = self.mesh.vertex_buffer,
            .offset = 0,
        }, 1);
        sdl.SDL_BindGPUIndexBuffer(render_pass, &sdl.SDL_GPUBufferBinding{
            .buffer = self.mesh.index_buffer,
            .offset = 0,
        }, sdl.SDL_GPU_INDEXELEMENTSIZE_32BIT);
        // sdl.SDL_BindGPUFragmentSamplers(render_pass, 0, &sdl.SDL_GPUTextureSamplerBinding{
        //     .sampler = self.sampler,
        //     .texture = self.texture,
        // }, 1);

        sdl.SDL_BindGPUGraphicsPipeline(render_pass, graphics_pipeline);

        section.sub(.init).end();

        for (0..8) |zi| {
            for (0..8) |yi| {
                for (0..8) |xi| {
                    var x: f32 = @floatFromInt(xi);
                    var y: f32 = @floatFromInt(yi);
                    var z: f32 = @floatFromInt(zi);
                    const rx = x + 1;
                    const ry = y + 1;
                    const rz = z + 1;
                    const tx = x;
                    const ty = y;
                    const tz = z;
                    x *= 30;
                    y *= 30;
                    z *= 30;

                    section.sub(.cow1).unpause();

                    {
                        const result = model;
                        result.* = math.matrix4x4.identity;

                        const euler_order: math.EulerOrder = .xyz;
                        math.matrix4x4.scaleXYZ(result, &.{ 1, 1, 1 });
                        // math.matrix4x4.rotate_euler(&result, &.{ x_mod_s * pi / 4.0, y_mod_s * pi / 4.0, z_mod_s * pi / 4.0 }, euler_order);
                        math.matrix4x4.rotateEuler(result, &.{ pi / 4.0 + time_s * pi * rx / 4.0, -pi / 4.0, pi / 4.0 }, euler_order);
                        math.matrix4x4.translateXYZ(result, &.{ 0, 5, 0 });
                        math.matrix4x4.translateXYZ(result, &.{ x, y, z });
                    }
                    @memcpy(uniform_buffer[16..32], math.matrix4x4.sliceLenConst(model));

                    frag_uniform_buffer[0] = time_s + tx;

                    sdl.SDL_PushGPUVertexUniformData(command_buffer, 0, uniform_buffer.ptr, @intCast(@sizeOf(f32) * uniform_buffer.len));
                    sdl.SDL_PushGPUFragmentUniformData(command_buffer, 0, &frag_uniform_buffer, @sizeOf(@TypeOf(frag_uniform_buffer)));
                    sdl.SDL_DrawGPUIndexedPrimitives(render_pass, @intCast(3 * self.mesh.faces.items.len), 1, 0, 0, 0);

                    section.sub(.cow1).pause();
                    section.sub(.cow2).unpause();

                    {
                        const result = model;
                        result.* = math.matrix4x4.identity;

                        const euler_order: math.EulerOrder = .xyz;
                        math.matrix4x4.scaleXYZ(result, &.{ 1, 1, 1 });
                        // math.matrix4x4.rotate_euler(&result, &.{ x_mod_s * pi / 4.0, y_mod_s * pi / 4.0, z_mod_s * pi / 4.0 }, euler_order);
                        math.matrix4x4.rotateEuler(result, &.{ pi / 4.0, -pi / 4.0 + time_s * pi * ry / 4.0, pi / 4.0 }, euler_order);
                        math.matrix4x4.translateXYZ(result, &.{ 10, 5, 0 });
                        math.matrix4x4.translateXYZ(result, &.{ x, y, z });
                    }
                    @memcpy(uniform_buffer[16..32], math.matrix4x4.sliceLenConst(model));

                    frag_uniform_buffer[0] = time_s + ty;

                    sdl.SDL_PushGPUVertexUniformData(command_buffer, 0, uniform_buffer.ptr, @intCast(@sizeOf(f32) * uniform_buffer.len));
                    sdl.SDL_PushGPUFragmentUniformData(command_buffer, 0, &frag_uniform_buffer, @sizeOf(@TypeOf(frag_uniform_buffer)));
                    sdl.SDL_DrawGPUIndexedPrimitives(render_pass, @intCast(3 * self.mesh.faces.items.len), 1, 0, 0, 0);

                    section.sub(.cow2).pause();
                    section.sub(.cow3).unpause();

                    {
                        const result = model;
                        result.* = math.matrix4x4.identity;

                        const euler_order: math.EulerOrder = .xyz;
                        math.matrix4x4.scaleXYZ(result, &.{ 1, 1, 1 });
                        // math.matrix4x4.rotate_euler(&result, &.{ x_mod_s * pi / 4.0, y_mod_s * pi / 4.0, z_mod_s * pi / 4.0 }, euler_order);
                        math.matrix4x4.rotateEuler(result, &.{ pi / 4.0, -pi / 4.0, pi / 4.0 + time_s * pi * rz / 4.0 }, euler_order);
                        math.matrix4x4.translateXYZ(result, &.{ -10, 5, 0 });
                        math.matrix4x4.translateXYZ(result, &.{ x, y, z });
                    }
                    @memcpy(uniform_buffer[16..32], math.matrix4x4.sliceLenConst(model));

                    frag_uniform_buffer[0] = time_s + tz;

                    sdl.SDL_PushGPUVertexUniformData(command_buffer, 0, uniform_buffer.ptr, @intCast(@sizeOf(f32) * uniform_buffer.len));
                    sdl.SDL_PushGPUFragmentUniformData(command_buffer, 0, &frag_uniform_buffer, @sizeOf(@TypeOf(frag_uniform_buffer)));
                    sdl.SDL_DrawGPUIndexedPrimitives(render_pass, @intCast(3 * self.mesh.faces.items.len), 1, 0, 0, 0);

                    section.sub(.cow3).pause();
                }
            }
        }

        section.sub(.origin).begin();

        model.* = math.matrix4x4.identity;
        @memcpy(uniform_buffer[16..32], math.matrix4x4.sliceLenConst(model));

        sdl.SDL_BindGPUVertexBuffers(render_pass, 0, &sdl.SDL_GPUBufferBinding{
            .buffer = self.origin_mesh.vertex_buffer,
            .offset = 0,
        }, 1);
        sdl.SDL_BindGPUIndexBuffer(render_pass, &sdl.SDL_GPUBufferBinding{
            .buffer = self.origin_mesh.index_buffer,
            .offset = 0,
        }, sdl.SDL_GPU_INDEXELEMENTSIZE_32BIT);
        sdl.SDL_PushGPUVertexUniformData(command_buffer, 0, uniform_buffer.ptr, @intCast(@sizeOf(f32) * uniform_buffer.len));
        sdl.SDL_BindGPUGraphicsPipeline(render_pass, origin_graphics_pipeline);

        origin_frag_uniform_buffer = .{ 1, 0, 0, 1 };
        sdl.SDL_PushGPUFragmentUniformData(command_buffer, 0, &origin_frag_uniform_buffer, @sizeOf(@TypeOf(origin_frag_uniform_buffer)));
        sdl.SDL_DrawGPUIndexedPrimitives(render_pass, 2, 1, 0, 0, 0);

        origin_frag_uniform_buffer = .{ 0, 1, 0, 1 };
        sdl.SDL_PushGPUFragmentUniformData(command_buffer, 0, &origin_frag_uniform_buffer, @sizeOf(@TypeOf(origin_frag_uniform_buffer)));
        sdl.SDL_DrawGPUIndexedPrimitives(render_pass, 2, 1, 2, 0, 0);

        origin_frag_uniform_buffer = .{ 0, 0, 1, 1 };
        sdl.SDL_PushGPUFragmentUniformData(command_buffer, 0, &origin_frag_uniform_buffer, @sizeOf(@TypeOf(origin_frag_uniform_buffer)));
        sdl.SDL_DrawGPUIndexedPrimitives(render_pass, 2, 1, 4, 0, 0);

        section.sub(.origin).end();

        log.debug("end render_pass", .{});
        sdl.SDL_EndGPURenderPass(render_pass);
    }

    // {
    //     log.debug("render_pass 2", .{});
    //     const render_pass = sdl.SDL_BeginGPURenderPass(
    //         command_buffer,
    //         &sdl.SDL_GPUColorTargetInfo{
    //             .texture = swapchain_texture,
    //             .load_op = sdl.SDL_GPU_LOADOP_LOAD,
    //             .store_op = sdl.SDL_GPU_STOREOP_STORE,
    //         },
    //         1,
    //         &sdl.SDL_GPUDepthStencilTargetInfo{
    //             .texture = self.stencil_texture,
    //             .load_op = sdl.SDL_GPU_LOADOP_LOAD,
    //             .store_op = sdl.SDL_GPU_STOREOP_STORE,
    //             .stencil_load_op = sdl.SDL_GPU_LOADOP_DONT_CARE,
    //             .stencil_store_op = sdl.SDL_GPU_STOREOP_DONT_CARE,
    //             // .cycle = true,
    //         },
    //     );
    //     if (render_pass == null) {
    //         log.err("failed to begin render_pass: {s}", .{sdl.SDL_GetError()});
    //         return DrawError.DrawFailed;
    //     }
    //
    //     // sdl.SDL_BindGPUFragmentSamplers(render_pass, 0, &sdl.SDL_GPUTextureSamplerBinding{
    //     //     .sampler = self.sampler,
    //     //     .texture = self.texture,
    //     // }, 1);
    //
    //     sdl.SDL_EndGPURenderPass(render_pass);
    // }

    log.debug("submit command_buffer", .{});
    if (!sdl.SDL_SubmitGPUCommandBuffer(command_buffer)) {
        log.err("failed submitting command_buffer: {s}", .{sdl.SDL_GetError()});
        return DrawError.DrawFailed;
    }

    return true;
}
