//!
//! The zengine renderer implementation
//!

const std = @import("std");
const sdl = @import("../ext.zig").sdl;
const math = @import("../math.zig");
const global = @import("../global.zig");
const Engine = @import("../engine.zig").Engine;
const shader = @import("shader.zig");
const Mesh = @import("mesh.zig").Mesh;
const obj_loader = @import("obj_loader.zig");
const assert = std.debug.assert;

pub const Renderer = struct {
    gpu_device: ?*sdl.SDL_GPUDevice,
    graphics_pipeline: ?*sdl.SDL_GPUGraphicsPipeline,
    mesh: Mesh,
    viewport: sdl.SDL_GPUViewport,
    texture: ?*sdl.SDL_GPUTexture,
    stencil_texture: ?*sdl.SDL_GPUTexture,
    sampler: ?*sdl.SDL_GPUSampler,
    camera_position: math.Vector3,
    camera_direction: math.Vector3,

    const InitError = error{
        GpuFailed,
        ShaderFailed,
        WindowFailed,
        PipelineFailed,
        BufferFailed,
        TextureFailed,
        CommandBufferFailed,
        CopyPassFailed,
        RenderPassFailed,
    };

    pub fn init(engine: Engine) InitError!Renderer {
        const allocator = engine.allocator;
        const window = engine.window;

        const gpu_device = sdl.SDL_CreateGPUDevice(
            sdl.SDL_GPU_SHADERFORMAT_SPIRV | sdl.SDL_GPU_SHADERFORMAT_MSL | sdl.SDL_GPU_SHADERFORMAT_DXIL,
            true,
            null,
        );
        if (gpu_device == null) {
            std.log.err("failed creating gpu_device: {s}", .{sdl.SDL_GetError()});
            return InitError.GpuFailed;
        }
        errdefer sdl.SDL_DestroyGPUDevice(gpu_device);

        const vertex_shader = shader.open(.{
            .allocator = engine.allocator,
            .gpu_device = gpu_device,
            .shader_path = "triangle_vert.vert",
            .stage = sdl.SDL_GPU_SHADERSTAGE_VERTEX,
            .num_uniform_buffers = 1,
        });

        if (vertex_shader == null) {
            std.log.err("failed creating vertex_shader", .{});
            return InitError.ShaderFailed;
        }
        defer sdl.SDL_ReleaseGPUShader(gpu_device, vertex_shader);

        const fragment_shader = shader.open(.{
            .allocator = allocator,
            .gpu_device = gpu_device,
            .shader_path = "solid_color.frag",
            .stage = sdl.SDL_GPU_SHADERSTAGE_FRAGMENT,
            // .num_samplers = 1,
        });

        if (fragment_shader == null) {
            std.log.err("failed creating fragment_shader", .{});
            return InitError.ShaderFailed;
        }
        defer sdl.SDL_ReleaseGPUShader(gpu_device, fragment_shader);

        const path = std.fs.path.join(engine.allocator, &.{ global.exe_path(), "..", "..", "assets", "cow_nonormals.obj" }) catch |err| {
            std.log.err("failed creating obj file path: {}", .{@errorName(err)});
            return InitError.BufferFailed;
        };
        var mesh = obj_loader.load_file(engine.allocator, path) catch |err| {
            std.log.err("failed loading mesh from obj file: {s}", .{@errorName(err)});
            return InitError.BufferFailed;
        };

        try mesh.create_gpu_buffers(gpu_device);
        errdefer mesh.release_gpu_buffers(gpu_device);

        var stencil_format: sdl.SDL_GPUTextureFormat = undefined;
        if (sdl.SDL_GPUTextureSupportsFormat(gpu_device, sdl.SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT, sdl.SDL_GPU_TEXTURETYPE_2D, sdl.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET)) {
            stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT;
        } else if (sdl.SDL_GPUTextureSupportsFormat(gpu_device, sdl.SDL_GPU_TEXTUREFORMAT_D32_FLOAT_S8_UINT, sdl.SDL_GPU_TEXTURETYPE_2D, sdl.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET)) {
            stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_D32_FLOAT_S8_UINT;
        } else {
            stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_D32_FLOAT;
            std.log.err("no supported stencil format", .{});
        }

        if (!sdl.SDL_ClaimWindowForGPUDevice(gpu_device, window)) {
            std.log.err("failed claiming window for gpu_device: {s}", .{sdl.SDL_GetError()});
            return InitError.WindowFailed;
        }

        var present_mode = @as(c_uint, sdl.SDL_GPU_PRESENTMODE_VSYNC);
        if (sdl.SDL_WindowSupportsGPUPresentMode(gpu_device, window, sdl.SDL_GPU_PRESENTMODE_MAILBOX)) {
            present_mode = sdl.SDL_GPU_PRESENTMODE_MAILBOX;
        }

        if (!sdl.SDL_SetGPUSwapchainParameters(gpu_device, window, sdl.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, present_mode)) {
            std.log.err("failed setting swapchain parameters: {s}", .{sdl.SDL_GetError()});
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
                },
                .has_depth_stencil_target = true,
                .depth_stencil_format = stencil_format,
            },
        };

        const graphics_pipeline = sdl.SDL_CreateGPUGraphicsPipeline(gpu_device, &graphics_pipeline_create_info);

        if (graphics_pipeline == null) {
            std.log.err("failed creating graphics_pipeline: {s}", .{sdl.SDL_GetError()});
            return InitError.PipelineFailed;
        }
        errdefer sdl.SDL_ReleaseGPUGraphicsPipeline(gpu_device, graphics_pipeline);

        const stencil_texture = sdl.SDL_CreateGPUTexture(gpu_device, &sdl.SDL_GPUTextureCreateInfo{
            .type = sdl.SDL_GPU_TEXTURETYPE_2D,
            .format = stencil_format,
            .usage = sdl.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET,
            .width = @intCast(engine.window_size.w),
            .height = @intCast(engine.window_size.h),
            .layer_count_or_depth = 1,
            .num_levels = 1,
            .sample_count = sdl.SDL_GPU_SAMPLECOUNT_1,
        });
        if (stencil_texture == null) {
            std.log.err("failed creating stencil_texture: {s}", .{sdl.SDL_GetError()});
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
            std.log.err("failed creating texture: {s}", .{sdl.SDL_GetError()});
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
            std.log.err("failed creating sampler: {s}", .{sdl.SDL_GetError()});
            return InitError.BufferFailed;
        }
        errdefer sdl.SDL_ReleaseGPUSampler(gpu_device, sampler);

        const mesh_upload_transfer_buffer = try mesh.create_upload_transfer_buffer(gpu_device);
        defer mesh_upload_transfer_buffer.release(gpu_device);

        try mesh_upload_transfer_buffer.map(gpu_device);

        const command_buffer = sdl.SDL_AcquireGPUCommandBuffer(gpu_device);
        if (command_buffer == null) {
            std.log.err("failed to acquire gpu_command_buffer: {s}", .{sdl.SDL_GetError()});
            return InitError.CommandBufferFailed;
        }
        errdefer _ = sdl.SDL_CancelGPUCommandBuffer(command_buffer);

        {
            const copy_pass = sdl.SDL_BeginGPUCopyPass(command_buffer);
            if (copy_pass == null) {
                std.log.err("failed to begin copy_pass: {s}", .{sdl.SDL_GetError()});
                return InitError.CopyPassFailed;
            }

            mesh_upload_transfer_buffer.upload(copy_pass);

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
                std.log.err("failed to begin render_pass[{}]: {s}", .{ layer, sdl.SDL_GetError() });
                return InitError.RenderPassFailed;
            }

            sdl.SDL_EndGPURenderPass(render_pass);
        }

        if (!sdl.SDL_SubmitGPUCommandBuffer(command_buffer)) {
            std.log.err("failed submitting command_buffer: {s}", .{sdl.SDL_GetError()});
            return InitError.CommandBufferFailed;
        }

        const viewport = sdl.SDL_GPUViewport{
            .x = -1,
            .y = -1,
            .w = 2,
            .h = 2,
            .min_depth = 0,
            .max_depth = 1,
        };

        return .{
            .gpu_device = gpu_device,
            .mesh = mesh,
            .graphics_pipeline = graphics_pipeline,
            .viewport = viewport,
            .texture = texture,
            .stencil_texture = stencil_texture,
            .sampler = sampler,
            .camera_position = .{ 0, 0, 0 },
            .camera_direction = .{ 1, 1, 1 },
        };
    }

    pub fn deinit(self: *Renderer, engine: Engine) void {
        defer sdl.SDL_DestroyGPUDevice(self.gpu_device);
        defer self.mesh.deinit();
        defer self.mesh.release_gpu_buffers(self.gpu_device);
        defer sdl.SDL_ReleaseWindowFromGPUDevice(self.gpu_device, engine.window);
        defer sdl.SDL_ReleaseGPUGraphicsPipeline(self.gpu_device, self.graphics_pipeline);
        defer sdl.SDL_ReleaseGPUTexture(self.gpu_device, self.texture);
        defer sdl.SDL_ReleaseGPUSampler(self.gpu_device, self.sampler);
        defer sdl.SDL_ReleaseGPUTexture(self.gpu_device, self.stencil_texture);
    }

    const DrawError = error{
        DrawFailed,
        DrawSkipped,
    };

    pub fn draw(self: Renderer, engine: Engine, time: u64) DrawError!void {
        _ = time;
        const gpu_device = self.gpu_device;
        const window = engine.window;
        const graphics_pipeline = self.graphics_pipeline;
        // const viewport = self.viewport;

        const command_buffer = sdl.SDL_AcquireGPUCommandBuffer(gpu_device);
        if (command_buffer == null) {
            std.log.err("failed to acquire command_buffer: {s}", .{sdl.SDL_GetError()});
            return DrawError.DrawFailed;
        }
        errdefer _ = sdl.SDL_CancelGPUCommandBuffer(command_buffer);

        var swapchain_texture: ?*sdl.SDL_GPUTexture = undefined;
        if (!sdl.SDL_AcquireGPUSwapchainTexture(command_buffer, window, &swapchain_texture, null, null)) {
            std.log.err("failed to acquire swapchain_texture: {s}", .{sdl.SDL_GetError()});
            return DrawError.DrawFailed;
        }
        if (swapchain_texture == null) {
            return DrawError.DrawSkipped;
        }

        const render_pass = sdl.SDL_BeginGPURenderPass(
            command_buffer,
            &sdl.SDL_GPUColorTargetInfo{
                .texture = swapchain_texture,
                .clear_color = sdl.SDL_FColor{ .r = 0.05, .g = 0, .b = 0.1, .a = 1 },
                .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
                .store_op = sdl.SDL_GPU_STOREOP_STORE,
            },
            1,
            &sdl.SDL_GPUDepthStencilTargetInfo{
                .texture = self.stencil_texture,
                .clear_depth = 1,
                .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
                .store_op = sdl.SDL_GPU_STOREOP_DONT_CARE,
                .stencil_load_op = sdl.SDL_GPU_LOADOP_DONT_CARE,
                .stencil_store_op = sdl.SDL_GPU_STOREOP_DONT_CARE,
                .cycle = true,
            },
        );
        if (render_pass == null) {
            std.log.err("failed to begin render_pass: {s}", .{sdl.SDL_GetError()});
            return DrawError.DrawFailed;
        }

        var projection: math.Matrix4x4 = undefined;
        math.matrix4x4.perspective_fov(
            &projection,
            39.5978 * std.math.pi / 180.0,
            @as(f32, @floatFromInt(engine.window_size.w)),
            @as(f32, @floatFromInt(engine.window_size.h)),
            0.1,
            100.0,
        );

        var camera: math.Matrix4x4 = undefined;
        math.matrix4x4.camera(
            &camera,
            &self.camera_position,
            &self.camera_direction,
            &comptime global.camera_up(),
        );

        var world: math.Matrix4x4 = undefined;
        math.matrix4x4.world_transform(&world);

        var view: math.Matrix4x4 = undefined;
        math.matrix4x4.dot(&view, &world, &camera);

        var view_projection: math.Matrix4x4 = undefined;
        math.matrix4x4.dot(&view_projection, &view, &projection);

        var model = math.Matrix4x4{
            .{ 1, 0, 0, 0 },
            .{ 0, 1, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 0, 0, 0, 1 },
        };
        // _ = &model;

        std.log.info("xform: {any}", .{camera});
        std.log.info("camera_position: {any}", .{self.camera_position});
        std.log.info("camera_direction: {any}", .{self.camera_direction});

        var uniform_buffer: [32]f32 = undefined;
        @memcpy(uniform_buffer[0..16], math.matrix4x4.slice_len_const(&view_projection));
        @memcpy(uniform_buffer[16..32], math.matrix4x4.slice_len_const(&model));

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
        sdl.SDL_PushGPUVertexUniformData(command_buffer, 0, &uniform_buffer, @sizeOf(@TypeOf(uniform_buffer)));

        // sdl.SDL_SetGPUViewport(render_pass, &self.viewport);
        sdl.SDL_BindGPUGraphicsPipeline(render_pass, graphics_pipeline);
        // sdl.SDL_DrawGPUIndexedPrimitives(render_pass, 36, 1, 0, 0, 0);
        sdl.SDL_DrawGPUIndexedPrimitives(render_pass, @intCast(3 * self.mesh.faces.items.len), 1, 0, 0, 0);
        sdl.SDL_EndGPURenderPass(render_pass);
        if (!sdl.SDL_SubmitGPUCommandBuffer(command_buffer)) {
            std.log.err("failed submitting command_buffer: {s}", .{sdl.SDL_GetError()});
            return DrawError.DrawFailed;
        }
    }
};
