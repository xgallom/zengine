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
const Scene = @import("../Scene.zig");
const ui_mod = @import("../ui.zig");
const Error = @import("Error.zig").Error;
const GPUBuffer = @import("GPUBuffer.zig");
const GPUDevice = @import("GPUDevice.zig");
const GPUGraphicsPipeline = @import("GPUGraphicsPipeline.zig");
const GPUSampler = @import("GPUSampler.zig");
const GPUTexture = @import("GPUTexture.zig");
const MaterialInfo = @import("MaterialInfo.zig");
const MeshBuffer = @import("MeshBuffer.zig");
const MeshObject = @import("MeshObject.zig");
const shader_loader = @import("shader_loader.zig");
const types = @import("types.zig");

const log = std.log.scoped(.gfx_renderer);
pub const sections = perf.sections(@This(), &.{ .init, .render });

allocator: std.mem.Allocator,
gpu_device: GPUDevice,
pipelines: Pipelines,
mesh_objs: MeshObjects,
mesh_bufs: MeshBuffers,
storage_bufs: StorageBuffers,
materials: MaterialInfos,
textures: Textures,
samplers: Samplers,

const Self = @This();

const Pipelines = ArrayMap(GPUGraphicsPipeline);
const MeshObjects = ArrayPoolMap(MeshObject, .{});
const MeshBuffers = ArrayPoolMap(MeshBuffer, .{});
const StorageBuffers = ArrayPoolMap(MeshBuffer, .{});
const MaterialInfos = ArrayPoolMap(MaterialInfo, .{});
const Textures = ArrayMap(GPUTexture);
const Samplers = ArrayMap(GPUSampler);

pub const Item = struct {
    object: [:0]const u8,
    transform: *const math.Matrix4x4,

    pub const rotation_speed = 0.1;

    pub fn propertyEditor(self: *Item) ui_mod.PropertyEditor(Item) {
        return .init(self);
    }
};

pub const Items = struct {
    items: Scene.FlatList.Slice,
    idx: usize = 0,

    pub fn init(flat: *const Scene.Flattened) Items {
        return .{ .items = flat.getPtrConst(.object).slice() };
    }

    pub fn next(self: *Items) ?Item {
        if (self.idx < self.items.len) {
            defer self.idx += 1;
            return .{
                .object = self.items.items(.target)[self.idx],
                .transform = &self.items.items(.transform)[self.idx],
            };
        }
        return null;
    }

    pub fn reset(self: *Items) void {
        self.idx = 0;
    }
};

pub fn create(engine: *const Engine) !*Self {
    defer allocators.scratchFree();

    try sections.register();
    try sections.sub(.render)
        .sections(&.{ .acquire, .init, .items, .origin, .ui, .submit })
        .register();

    sections.sub(.init).begin();

    const self = try createSelf(allocators.gpa(), engine);
    errdefer self.deinit(engine);

    if (!self.gpu_device.setAllowedFramesInFlight(3)) {
        log.warn("failed to enable triple-buffering", .{});
    }
    try self.setPresentMode(engine);

    const stencil_format = self.stencilFormat();
    _ = try self.createStencilTexture(engine, stencil_format);
    _ = try self.createSampler("default", &.{
        .min_filter = .linear,
        .mag_filter = .linear,
        .mipmap_mode = .nearest,
        .address_mode_u = .clamp_to_edge,
        .address_mode_v = .clamp_to_edge,
        .address_mode_w = .clamp_to_edge,
    });

    var triangle_vert = shader_loader.loadFile(&.{
        .allocator = self.allocator,
        .gpu_device = self.gpu_device,
        .shader_path = "triangle_vert.vert",
        .stage = .vertex,
    }) catch |err| {
        log.err("failed creating vertex shader: {t}", .{err});
        return Error.ShaderFailed;
    };
    defer triangle_vert.deinit(self.gpu_device);

    var full_vert = shader_loader.loadFile(&.{
        .allocator = self.allocator,
        .gpu_device = self.gpu_device,
        .shader_path = "full.vert",
        .stage = .vertex,
    }) catch |err| {
        log.err("failed creating full vertex shader: {t}", .{err});
        return Error.ShaderFailed;
    };
    defer full_vert.deinit(self.gpu_device);

    var sampler_texture_frag = shader_loader.loadFile(&.{
        .allocator = self.allocator,
        .gpu_device = self.gpu_device,
        .shader_path = "sampler_texture.frag",
        .stage = .fragment,
    }) catch |err| {
        log.err("failed creating fragment shader: {t}", .{err});
        return Error.ShaderFailed;
    };
    defer sampler_texture_frag.deinit(self.gpu_device);

    var rgb_color_frag = shader_loader.loadFile(&.{
        .allocator = self.allocator,
        .gpu_device = self.gpu_device,
        .shader_path = "rgb_color.frag",
        .stage = .fragment,
    }) catch |err| {
        log.err("failed creating origin fragment shader: {t}", .{err});
        return Error.ShaderFailed;
    };
    defer rgb_color_frag.deinit(self.gpu_device);

    var full_frag = shader_loader.loadFile(&.{
        .allocator = self.allocator,
        .gpu_device = self.gpu_device,
        .shader_path = "full.frag",
        .stage = .fragment,
    }) catch |err| {
        log.err("failed creating full fragment shader: {t}", .{err});
        return Error.ShaderFailed;
    };
    defer full_frag.deinit(self.gpu_device);

    var pipeline_create_info: GPUGraphicsPipeline.CreateInfo = .{
        .vertex_shader = triangle_vert,
        .fragment_shader = sampler_texture_frag,
        .vertex_input_state = .{
            .vertex_buffer_descriptions = &.{
                .{
                    .slot = 0,
                    .pitch = 3 * @sizeOf(math.Vertex),
                    .input_rate = .vertex,
                    .instance_step_rate = 0,
                },
            },
            .vertex_attributes = &.{
                .{
                    .location = 0,
                    .buffer_slot = 0,
                    .format = .f32_3,
                    .offset = 0,
                },
                .{
                    .location = 1,
                    .buffer_slot = 0,
                    .format = .f32_3,
                    .offset = @sizeOf(math.Vertex),
                },
                .{
                    .location = 2,
                    .buffer_slot = 0,
                    .format = .f32_3,
                    .offset = 2 * @sizeOf(math.Vertex),
                },
            },
        },
        .primitive_type = .triangle_list,
        .rasterizer_state = .{
            .fill_mode = .fill,
            .cull_mode = .none,
            .front_face = .clockwise,
            .enable_depth_clip = true,
        },
        .depth_stencil_state = .{
            .compare_op = .less,
            .compare_mask = 0xFF,
            .write_mask = 0xFF,
            .enable_depth_test = true,
            .enable_depth_write = true,
        },
        .target_info = .{
            .color_target_descriptions = &.{
                .{
                    .format = self.swapchainFormat(engine),
                    .blend_state = .{
                        .src_color_blendfactor = .src_alpha,
                        .dst_color_blendfactor = .one_minus_src_alpha,
                        .color_blend_op = .add,
                        .alpha_blend_op = .max,
                        .color_write_mask = 0x00,
                        .src_alpha_blendfactor = .one,
                        .dst_alpha_blendfactor = .one,
                        .enable_blend = true,
                        .enable_color_write_mask = false,
                    },
                },
            },
            .has_depth_stencil_target = true,
            .depth_stencil_format = stencil_format,
        },
    };

    _ = try self.createGraphicsPipeline("default", &pipeline_create_info);

    pipeline_create_info.fragment_shader = rgb_color_frag;
    pipeline_create_info.primitive_type = .line_list;
    pipeline_create_info.rasterizer_state.fill_mode = .line;

    _ = try self.createGraphicsPipeline("origin", &pipeline_create_info);

    pipeline_create_info.vertex_shader = full_vert;
    pipeline_create_info.fragment_shader = full_frag;
    pipeline_create_info.vertex_input_state = .{};
    pipeline_create_info.primitive_type = .triangle_list;
    pipeline_create_info.rasterizer_state.fill_mode = .fill;

    _ = try self.createGraphicsPipeline("screen", &pipeline_create_info);
    sections.sub(.init).end();
    return self;
}

pub fn deinit(self: *Self, engine: *const Engine) void {
    _ = c.SDL_WaitForGPUIdle(self.gpu_device.ptr);
    const gpa = self.allocator;
    const gpu_device = self.gpu_device;

    for (self.pipelines.map.values()) |*pipeline| self.gpu_device.release(pipeline);
    self.pipelines.deinit(gpa);

    for (self.mesh_objs.map.values()) |object| object.deinit(gpa);
    self.mesh_objs.deinit();

    self.materials.deinit();

    for (self.mesh_bufs.map.values()) |buf| buf.deinit(gpa, gpu_device);
    self.mesh_bufs.deinit();
    for (self.storage_bufs.map.values()) |buf| buf.deinit(gpa, gpu_device);
    self.storage_bufs.deinit();
    for (self.textures.map.values()) |*tex| self.gpu_device.release(tex);
    self.textures.deinit(gpa);
    for (self.samplers.map.values()) |*sampler| self.gpu_device.release(sampler);
    self.samplers.deinit(gpa);

    self.gpu_device.releaseWindow(engine.main_win);
    self.gpu_device.deinit();
}

fn stencilFormat(self: *const Self) GPUTexture.Format {
    if (GPUTexture.supportsFormat(
        self.gpu_device,
        .D24_unorm_S8_u,
        .@"2D",
        .initOne(.depth_stencil_target),
    )) return .D24_unorm_S8_u;
    if (GPUTexture.supportsFormat(
        self.gpu_device,
        .D32_f_S8_u,
        .@"2D",
        .initOne(.depth_stencil_target),
    )) return .D32_f_S8_u;
    return .D32_f;
}

pub fn swapchainFormat(self: *const Self, engine: *const Engine) GPUTexture.Format {
    return @enumFromInt(c.SDL_GetGPUSwapchainTextureFormat(self.gpu_device.ptr, engine.main_win.ptr));
}

pub fn setPresentMode(self: *Self, engine: *const Engine) !void {
    var present_mode: types.PresentMode = .vsync;
    if (self.gpu_device.supportsPresentMode(engine.main_win, .mailbox)) present_mode = .mailbox;
    try self.gpu_device.setSwapchainParameters(engine.main_win, .SDR, present_mode);
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

    try gpu_device.claimWindow(engine.main_win);
    errdefer gpu_device.releaseWindow(engine.main_win);

    const self = try allocators.global().create(Self);
    self.* = .{
        .allocator = allocator,
        .gpu_device = gpu_device,
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

pub fn createMeshObject(self: *Self, key: []const u8, face_type: MeshObject.FaceType) !*MeshObject {
    const mesh_obj = try self.mesh_objs.create(key);
    mesh_obj.* = .init(self.allocator, face_type);
    return mesh_obj;
}

pub fn insertMeshObject(self: *Self, key: []const u8, mesh_obj: *const MeshObject) !*MeshObject {
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

pub fn createStorageBuffer(self: *Self, key: []const u8) !*MeshBuffer {
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

pub fn insertMaterial(self: *Self, key: []const u8, info: *const MaterialInfo) !*MaterialInfo {
    return self.materials.insert(key, info);
}

pub fn createTexture(self: *Self, key: []const u8, info: GPUTexture.CreateInfo) !GPUTexture {
    var tex = try self.gpu_device.texture(info);
    errdefer tex.deinit(self.gpu_device);
    try self.insertTexture(key, tex.ptr.?);
    return tex;
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
    try self.pipelines.insert(self.allocator, key, .fromOwned(pipeline));
    return .fromOwned(pipeline);
}

fn createStencilTexture(self: *Self, engine: *const Engine, stencil_format: GPUTexture.Format) !GPUTexture {
    var stencil_texture = try self.gpu_device.texture(&.{
        .type = .@"2D",
        .format = stencil_format,
        .usage = .initOne(.depth_stencil_target),
        .size = engine.main_win.pixelSize(),
    });
    errdefer stencil_texture.deinit(self.gpu_device);
    return self.insertTexture("stencil", stencil_texture.ptr.?);
}

pub fn render(
    self: *const Self,
    engine: *const Engine,
    scene: *const Scene,
    flat: *const Scene.Flattened,
    ui_ptr: ?*ui_mod.UI,
    items_iter: anytype,
) !bool {
    const section = sections.sub(.render);
    section.begin();

    section.sub(.acquire).begin();

    const default_pipeline = self.pipelines.get("default");
    const origin_pipeline = self.pipelines.get("origin");
    const origin_mesh = self.mesh_bufs.get("origin");
    const stencil = self.textures.get("stencil");
    const camera = scene.cameras.getPtr("default");
    const default_texture = self.textures.get("default");
    const default_sampler = self.samplers.get("default");
    const lights_buffer = self.storage_bufs.getPtr("lights");

    const fa = allocators.frame();

    log.debug("command buffer", .{});
    var command_buffer = self.gpu_device.commandBuffer() catch return Error.DrawFailed;
    errdefer command_buffer.cancel() catch {};

    log.debug("swapchain texture", .{});
    const swapchain = command_buffer.swapchainTexture(engine.main_win) catch return Error.DrawFailed;

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
    const props = try engine.main_win.properties();
    const win_size = engine.main_win.logicalSize();
    const mouse_x = props.f32.get("mouse_x") / @as(f32, @floatFromInt(win_size[0]));
    const mouse_y = props.f32.get("mouse_y") / @as(f32, @floatFromInt(win_size[1]));
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

    const light_counts = scene.lightCounts(flat);

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
    //         return Error.DrawFailed;
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
        var render_pass = command_buffer.renderPass(&.{.{
            .texture = swapchain,
            .clear_color = .{ 0.025, 0, 0.05, 1 },
            .load_op = .clear,
            .store_op = .store,
        }}, &.{
            .texture = stencil,
            .clear_depth = 1,
            .load_op = .clear,
            .store_op = .store,
            .stencil_load_op = .dont_care,
        }) catch return Error.DrawFailed;

        // c.SDL_BindGPUFragmentSamplers(render_pass, 0, &c.SDL_GPUTextureSamplerBinding{
        //     .sampler = self.sampler,
        //     .texture = self.texture,
        // }, 1);

        section.sub(.init).end();
        section.sub(.items).begin();

        render_pass.bindGraphicsPipeline(default_pipeline);
        try render_pass.bindFragmentStorageBuffers(0, &.{lights_buffer.gpu_bufs.getPtrConst(.vertex).*});

        command_buffer.pushFragmentUniformData(1, &camera.position);
        command_buffer.pushFragmentUniformData(2, &light_counts.values);

        while (items_iter.next()) |_item| {
            const item: Item = _item;
            const object = self.mesh_objs.getPtr(item.object);
            const mesh_buf = object.mesh_buf;

            try render_pass.bindVertexBuffers(0, &.{
                .{ .buffer = mesh_buf.gpu_bufs.get(.vertex), .offset = 0 },
            });

            for (object.sections.items) |buf_section| {
                const mtl = if (buf_section.material) |mtl| mtl else gfx_options.default_material;

                const material = self.materials.getPtr(mtl);

                @memcpy(uniform_buf[16..32], math.matrix4x4.sliceConst(item.transform));

                command_buffer.pushVertexUniformData(0, uniform_buf);
                command_buffer.pushFragmentUniformData(0, &material.uniformBuffer());

                const texture = if (material.texture) |tex| self.textures.get(tex) else default_texture;
                const diffuse_map = if (material.diffuse_map) |tex| self.textures.get(tex) else default_texture;
                const bump_map = if (material.bump_map) |tex| self.textures.get(tex) else default_texture;

                try render_pass.bindFragmentSamplers(0, &.{
                    .{ .texture = texture, .sampler = default_sampler },
                    .{ .texture = diffuse_map, .sampler = default_sampler },
                    .{ .texture = bump_map, .sampler = default_sampler },
                });

                switch (mesh_buf.type) {
                    .vertex => c.SDL_DrawGPUPrimitives(
                        render_pass.ptr,
                        @intCast(buf_section.len),
                        1,
                        @intCast(buf_section.offset),
                        0,
                    ),
                    .index => {
                        log.info("{s}", .{item.object});
                        render_pass.bindIndexBuffer(&.{
                            .buffer = mesh_buf.gpu_bufs.get(.index),
                            .offset = 0,
                        }, .@"32bit");
                        c.SDL_DrawGPUIndexedPrimitives(
                            render_pass.ptr,
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

        render_pass.bindGraphicsPipeline(origin_pipeline);

        command_buffer.pushFragmentUniformData(0, &[_]f32{ 1, 0, 1 });

        items_iter.reset();
        while (items_iter.next()) |_item| {
            const item: Item = _item;
            const object = self.mesh_objs.getPtr(item.object);

            if (!object.has_active.normals) continue;

            const mesh_buf = object.normals_buf;

            try render_pass.bindVertexBuffers(0, &.{
                .{ .buffer = mesh_buf.gpu_bufs.get(.vertex), .offset = 0 },
            });

            for (object.sections.items) |buf_section| {
                @memcpy(uniform_buf[16..32], math.matrix4x4.sliceConst(item.transform));
                command_buffer.pushVertexUniformData(0, uniform_buf);

                switch (mesh_buf.type) {
                    .vertex => c.SDL_DrawGPUPrimitives(
                        render_pass.ptr,
                        @intCast(buf_section.len * 2),
                        1,
                        @intCast(buf_section.offset * 2),
                        0,
                    ),
                    .index => {
                        log.err("index buffer normals render", .{});
                        return Error.DrawFailed;
                    },
                }
            }
        }

        section.sub(.items).end();
        section.sub(.origin).begin();

        @memcpy(uniform_buf[16..32], math.matrix4x4.sliceConst(&math.matrix4x4.identity));

        try render_pass.bindVertexBuffers(0, &.{
            .{ .buffer = origin_mesh.gpu_bufs.get(.vertex), .offset = 0 },
        });
        render_pass.bindIndexBuffer(&.{
            .buffer = origin_mesh.gpu_bufs.get(.index),
            .offset = 0,
        }, .@"32bit");

        command_buffer.pushVertexUniformData(0, uniform_buf);
        render_pass.bindGraphicsPipeline(origin_pipeline);

        command_buffer.pushFragmentUniformData(0, &[_]f32{ 1, 0, 0 });
        c.SDL_DrawGPUIndexedPrimitives(render_pass.ptr, 2, 1, 0, 0, 0);

        command_buffer.pushFragmentUniformData(0, &[_]f32{ 0, 1, 0 });
        c.SDL_DrawGPUIndexedPrimitives(render_pass.ptr, 2, 1, 2, 0, 0);

        command_buffer.pushFragmentUniformData(0, &[_]f32{ 0, 0, 1 });
        c.SDL_DrawGPUIndexedPrimitives(render_pass.ptr, 2, 1, 4, 0, 0);

        section.sub(.origin).end();

        log.debug("end main render pass", .{});
        render_pass.end();
    }

    if (ui_ptr) |ui| {
        section.sub(.ui).begin();
        if (ui.render_ui) try ui.submitPass(
            command_buffer.ptr,
            swapchain.ptr,
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
    //         return Error.DrawFailed;
    //     }
    //
    //     // c.SDL_BindGPUFragmentSamplers(render_pass, 0, &c.SDL_GPUTextureSamplerBinding{
    //     //     .sampler = self.sampler,
    //     //     .texture = self.texture,
    //     // }, 1);
    //
    //     c.SDL_EndGPURenderPass(render_pass);
    // }

    section.sub(.submit).begin();
    log.debug("submit command buffer", .{});
    command_buffer.submit() catch return Error.DrawFailed;
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
            const id = try std.fmt.bufPrint(&buf, "{s}#{s}", .{ @typeName(MeshObject), entry.key_ptr.* });
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
            const id = try std.fmt.bufPrint(&buf, "{s}#{s}", .{ @typeName(MeshBuffer), entry.key_ptr.* });
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
            const id = try std.fmt.bufPrint(&buf, "{s}#{s}", .{ @typeName(MeshBuffer), entry.key_ptr.* });
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
        const node = try editor.appendChildNode(root_node, root_id ++ ".textures", "Textures");
        var iter = self.textures.map.iterator();
        var buf: [64]u8 = undefined;
        while (iter.next()) |entry| {
            const id = try std.fmt.bufPrint(&buf, "{s}#{s}", .{ @typeName(GPUTexture), entry.key_ptr.* });
            _ = try editor.appendChild(
                node,
                ui_mod.property_editor.PropertyEditorNull,
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
            const id = try std.fmt.bufPrint(&buf, "{s}#{s}", .{ @typeName(c.SDL_GPUSampler), entry.key_ptr.* });
            _ = try editor.appendChild(
                node,
                ui_mod.property_editor.PropertyEditorNull,
                id,
                entry.key_ptr.*,
            );
        }
    }
    return root_node;
}
