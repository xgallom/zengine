//!
//! The zengine renderer implementation
//!

const std = @import("std");
const sdl = @import("../ext.zig").sdl;
const math = @import("../math.zig");
const Engine = @import("../engine.zig").Engine;
const shader = @import("shader.zig");

const assert = std.debug.assert;

pub const Renderer = struct {
    gpu_device: ?*sdl.SDL_GPUDevice,
    graphics_pipeline: ?*sdl.SDL_GPUGraphicsPipeline,
    viewport: sdl.SDL_GPUViewport,
    vertex_buffer: ?*sdl.SDL_GPUBuffer,
    index_buffer: ?*sdl.SDL_GPUBuffer,
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
            std.log.err("Failed creating gpu_device: {s}", .{sdl.SDL_GetError()});
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
            std.log.err("Failed creating vertex_shader", .{});
            return InitError.ShaderFailed;
        }
        defer sdl.SDL_ReleaseGPUShader(gpu_device, vertex_shader);

        const fragment_shader = shader.open(.{
            .allocator = allocator,
            .gpu_device = gpu_device,
            .shader_path = "sampler_texture.frag",
            .stage = sdl.SDL_GPU_SHADERSTAGE_FRAGMENT,
            .num_samplers = 1,
        });

        if (fragment_shader == null) {
            std.log.err("Failed creating fragment_shader", .{});
            return InitError.ShaderFailed;
        }
        defer sdl.SDL_ReleaseGPUShader(gpu_device, fragment_shader);

        var stencil_format: sdl.SDL_GPUTextureFormat = undefined;
        if (sdl.SDL_GPUTextureSupportsFormat(gpu_device, sdl.SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT, sdl.SDL_GPU_TEXTURETYPE_2D, sdl.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET)) {
            stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_D24_UNORM_S8_UINT;
        } else if (sdl.SDL_GPUTextureSupportsFormat(gpu_device, sdl.SDL_GPU_TEXTUREFORMAT_D32_FLOAT_S8_UINT, sdl.SDL_GPU_TEXTURETYPE_2D, sdl.SDL_GPU_TEXTUREUSAGE_DEPTH_STENCIL_TARGET)) {
            stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_D32_FLOAT_S8_UINT;
        } else {
            stencil_format = sdl.SDL_GPU_TEXTUREFORMAT_D32_FLOAT;
            std.log.err("No supported stencil format", .{});
        }

        if (!sdl.SDL_ClaimWindowForGPUDevice(gpu_device, window)) {
            std.log.err("Failed claiming window for gpu_device: {s}", .{sdl.SDL_GetError()});
            return InitError.WindowFailed;
        }

        var present_mode = @as(c_uint, sdl.SDL_GPU_PRESENTMODE_VSYNC);
        if (sdl.SDL_WindowSupportsGPUPresentMode(gpu_device, window, sdl.SDL_GPU_PRESENTMODE_MAILBOX)) {
            present_mode = sdl.SDL_GPU_PRESENTMODE_MAILBOX;
        }

        if (!sdl.SDL_SetGPUSwapchainParameters(gpu_device, window, sdl.SDL_GPU_SWAPCHAINCOMPOSITION_SDR, present_mode)) {
            std.log.err("Failed setting swapchain parameters: {s}", .{sdl.SDL_GetError()});
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
            std.log.err("Failed creating graphics_pipeline: {s}", .{sdl.SDL_GetError()});
            return InitError.PipelineFailed;
        }
        errdefer sdl.SDL_ReleaseGPUGraphicsPipeline(gpu_device, graphics_pipeline);

        const vertex_buffer = sdl.SDL_CreateGPUBuffer(gpu_device, &sdl.SDL_GPUBufferCreateInfo{
            .usage = sdl.SDL_GPU_BUFFERUSAGE_VERTEX,
            .size = @sizeOf(math.Vertex) * 24,
        });
        if (vertex_buffer == null) {
            std.log.err("Failed creating vertex_buffer: {s}", .{sdl.SDL_GetError()});
            return InitError.BufferFailed;
        }
        errdefer sdl.SDL_ReleaseGPUBuffer(gpu_device, vertex_buffer);

        const index_buffer = sdl.SDL_CreateGPUBuffer(gpu_device, &sdl.SDL_GPUBufferCreateInfo{
            .usage = sdl.SDL_GPU_BUFFERUSAGE_INDEX,
            .size = @sizeOf(u16) * 36,
        });
        if (index_buffer == null) {
            std.log.err("Failed creating index_buffer: {s}", .{sdl.SDL_GetError()});
            return InitError.BufferFailed;
        }
        errdefer sdl.SDL_ReleaseGPUBuffer(gpu_device, index_buffer);

        const transfer_buffer = sdl.SDL_CreateGPUTransferBuffer(gpu_device, &sdl.SDL_GPUTransferBufferCreateInfo{
            .usage = sdl.SDL_GPU_TRANSFERBUFFERUSAGE_UPLOAD,
            .size = (@sizeOf(math.Vertex) * 24) + (@sizeOf(u16) * 36),
        });
        if (transfer_buffer == null) {
            std.log.err("Failed creating transfer_bugffer: {s}", .{sdl.SDL_GetError()});
            return InitError.BufferFailed;
        }
        defer sdl.SDL_ReleaseGPUTransferBuffer(gpu_device, transfer_buffer);

        {
            const transfer_buffer_ptr = sdl.SDL_MapGPUTransferBuffer(gpu_device, transfer_buffer, false);
            if (transfer_buffer_ptr == null) {
                std.log.err("Failed mapping transfer_buffer_ptr: {s}", .{sdl.SDL_GetError()});
                return InitError.BufferFailed;
            }

            const vertex_data = @as([*]math.Vertex, @ptrCast(@alignCast(transfer_buffer_ptr)))[0..25];

            vertex_data[0] = .{ -10, -10, -10 };
            vertex_data[1] = .{ 10, -10, -10 };
            vertex_data[2] = .{ 10, 10, -10 };
            vertex_data[3] = .{ -10, 10, -10 };

            vertex_data[4] = .{ -10, -10, 10 };
            vertex_data[5] = .{ 10, -10, 10 };
            vertex_data[6] = .{ 10, 10, 10 };
            vertex_data[7] = .{ -10, 10, 10 };

            vertex_data[8] = .{ -10, -10, -10 };
            vertex_data[9] = .{ -10, 10, -10 };
            vertex_data[10] = .{ -10, 10, 10 };
            vertex_data[11] = .{ -10, -10, 10 };

            vertex_data[12] = .{ 10, -10, -10 };
            vertex_data[13] = .{ 10, 10, -10 };
            vertex_data[14] = .{ 10, 10, 10 };
            vertex_data[15] = .{ 10, -10, 10 };

            vertex_data[16] = .{ -10, -10, -10 };
            vertex_data[17] = .{ -10, -10, 10 };
            vertex_data[18] = .{ 10, -10, 10 };
            vertex_data[19] = .{ 10, -10, -10 };

            vertex_data[20] = .{ -10, 10, -10 };
            vertex_data[21] = .{ -10, 10, 10 };
            vertex_data[22] = .{ 10, 10, 10 };
            vertex_data[23] = .{ 10, 10, -10 };

            const index_data = @as([*]u16, @ptrCast(@alignCast(&vertex_data[24])))[0..36];
            const indices = &[36]u16{
                0,  1,  2,  0,  2,  3,
                6,  5,  4,  7,  6,  4,
                8,  9,  10, 8,  10, 11,
                14, 13, 12, 15, 14, 12,
                16, 17, 18, 16, 18, 19,
                22, 21, 20, 23, 22, 20,
            };
            @memcpy(index_data, indices);
            for (0..indices.len) |n| {
                std.log.info("{}: {any}", .{ n, vertex_data[indices[n]] });
            }

            sdl.SDL_UnmapGPUTransferBuffer(gpu_device, transfer_buffer);
        }

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
            std.log.err("Failed creating stencil_texture: {s}", .{sdl.SDL_GetError()});
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
            std.log.err("Failed creating texture: {s}", .{sdl.SDL_GetError()});
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
            std.log.err("Failed creating sampler: {s}", .{sdl.SDL_GetError()});
            return InitError.BufferFailed;
        }
        errdefer sdl.SDL_ReleaseGPUSampler(gpu_device, sampler);

        const command_buffer = sdl.SDL_AcquireGPUCommandBuffer(gpu_device);
        if (command_buffer == null) {
            std.log.err("Failed to acquire gpu_command_buffer: {s}", .{sdl.SDL_GetError()});
            return InitError.CommandBufferFailed;
        }
        errdefer _ = sdl.SDL_CancelGPUCommandBuffer(command_buffer);

        const copy_pass = sdl.SDL_BeginGPUCopyPass(command_buffer);
        if (copy_pass == null) {
            std.log.err("Failed to begin copy_pass: {s}", .{sdl.SDL_GetError()});
            return InitError.CopyPassFailed;
        }

        sdl.SDL_UploadToGPUBuffer(copy_pass, &sdl.SDL_GPUTransferBufferLocation{
            .transfer_buffer = transfer_buffer,
            .offset = 0,
        }, &sdl.SDL_GPUBufferRegion{
            .buffer = vertex_buffer,
            .offset = 0,
            .size = @sizeOf(math.Vertex) * 24,
        }, false);

        sdl.SDL_UploadToGPUBuffer(copy_pass, &sdl.SDL_GPUTransferBufferLocation{
            .transfer_buffer = transfer_buffer,
            .offset = @sizeOf(math.Vertex) * 24,
        }, &sdl.SDL_GPUBufferRegion{
            .buffer = index_buffer,
            .offset = 0,
            .size = @sizeOf(u16) * 36,
        }, false);

        sdl.SDL_EndGPUCopyPass(copy_pass);

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
                std.log.err("Failed to begin render_pass[{}]: {s}", .{ layer, sdl.SDL_GetError() });
                return InitError.RenderPassFailed;
            }

            sdl.SDL_EndGPURenderPass(render_pass);
        }

        if (!sdl.SDL_SubmitGPUCommandBuffer(command_buffer)) {
            std.log.err("Failed submitting command_buffer: {s}", .{sdl.SDL_GetError()});
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
            .graphics_pipeline = graphics_pipeline,
            .viewport = viewport,
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .texture = texture,
            .stencil_texture = stencil_texture,
            .sampler = sampler,
            .camera_position = .{ 0, 0, 0 },
            .camera_direction = .{ 1, 1, 1 },
        };
    }

    pub fn deinit(self: Renderer, engine: Engine) void {
        defer sdl.SDL_DestroyGPUDevice(self.gpu_device);
        defer sdl.SDL_ReleaseWindowFromGPUDevice(self.gpu_device, engine.window);
        defer sdl.SDL_ReleaseGPUGraphicsPipeline(self.gpu_device, self.graphics_pipeline);
        defer sdl.SDL_ReleaseGPUBuffer(self.gpu_device, self.vertex_buffer);
        defer sdl.SDL_ReleaseGPUBuffer(self.gpu_device, self.index_buffer);
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
            std.log.err("Failed to acquire command_buffer: {s}", .{sdl.SDL_GetError()});
            return DrawError.DrawFailed;
        }
        errdefer _ = sdl.SDL_CancelGPUCommandBuffer(command_buffer);

        var swapchain_texture: ?*sdl.SDL_GPUTexture = undefined;
        if (!sdl.SDL_AcquireGPUSwapchainTexture(command_buffer, window, &swapchain_texture, null, null)) {
            std.log.err("Failed to acquire swapchain_texture: {s}", .{sdl.SDL_GetError()});
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
            std.log.err("Failed to begin render_pass: {s}", .{sdl.SDL_GetError()});
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
            &.{ 0, 0, 1 },
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
            .buffer = self.vertex_buffer,
            .offset = 0,
        }, 1);
        sdl.SDL_BindGPUIndexBuffer(render_pass, &sdl.SDL_GPUBufferBinding{
            .buffer = self.index_buffer,
            .offset = 0,
        }, sdl.SDL_GPU_INDEXELEMENTSIZE_16BIT);
        sdl.SDL_BindGPUFragmentSamplers(render_pass, 0, &sdl.SDL_GPUTextureSamplerBinding{
            .sampler = self.sampler,
            .texture = self.texture,
        }, 1);
        sdl.SDL_PushGPUVertexUniformData(command_buffer, 0, &uniform_buffer, @sizeOf(@TypeOf(uniform_buffer)));

        // sdl.SDL_SetGPUViewport(render_pass, &self.viewport);
        sdl.SDL_BindGPUGraphicsPipeline(render_pass, graphics_pipeline);
        sdl.SDL_DrawGPUIndexedPrimitives(render_pass, 36, 1, 0, 0, 0);
        sdl.SDL_EndGPURenderPass(render_pass);
        if (!sdl.SDL_SubmitGPUCommandBuffer(command_buffer)) {
            std.log.err("Failed submitting command_buffer: {s}", .{sdl.SDL_GetError()});
            return DrawError.DrawFailed;
        }
    }
};
