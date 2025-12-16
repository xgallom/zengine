//!
//! The zengine renderer implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const ArrayPoolMap = @import("../containers.zig").ArrayPoolMap;
const ArrayMap = @import("../containers.zig").ArrayMap;
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
const GPUComputePipeline = @import("GPUComputePipeline.zig");
const GPUDevice = @import("GPUDevice.zig");
const GPUGraphicsPipeline = @import("GPUGraphicsPipeline.zig");
const GPUSampler = @import("GPUSampler.zig");
const GPUShader = @import("GPUShader.zig");
const GPUTextEngine = @import("GPUTextEngine.zig");
const GPUTexture = @import("GPUTexture.zig");
const Light = @import("Light.zig");
const MaterialInfo = @import("MaterialInfo.zig");
const mesh = @import("mesh.zig");
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
shaders: Shaders,
pipelines: Pipelines,
mesh_objs: MeshObjects,
mesh_bufs: MeshBuffers,
storage_bufs: StorageBuffers,
materials: MaterialInfos,
cameras: Cameras,
lights: Lights,
textures: Textures,
samplers: Samplers,
texts: Texts,
stencil_format: GPUTexture.Format,
settings: Settings = .{
    .exposure = 2,
    .gamma = 0.75,
    .config = .{
        .has_agx = true,
        .has_lut = true,
        .has_srgb = false,
    },
},

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
const Shaders = ArrayMap(GPUShader);
const MeshObjects = ArrayPoolMap(mesh.Object, .{});
const MeshBuffers = ArrayPoolMap(mesh.Buffer, .{});
const StorageBuffers = ArrayPoolMap(mesh.Buffer, .{});
const MaterialInfos = ArrayPoolMap(MaterialInfo, .{});
const Cameras = ArrayPoolMap(Camera, .{});
const Lights = ArrayPoolMap(Light, .{});
const Textures = ArrayMap(GPUTexture);
const Samplers = ArrayMap(GPUSampler);
const Texts = ArrayMap(ttf.Text);

pub const Settings = struct {
    camera: [:0]const u8 = "default",
    lut: [:0]const u8 = "lut/basic.cube",
    exposure: f32 = 1,
    exposure_bias: f32 = 0,
    gamma: f32 = 1,
    config: packed struct {
        has_agx: bool = false,
        has_lut: bool = false,
        has_srgb: bool = false,

        pub fn toInt(config: @This()) u32 {
            var result: u32 = 0;
            result |= @as(u32, @intFromBool(config.has_agx)) << 0;
            result |= @as(u32, @intFromBool(config.has_lut)) << 1;
            result |= @as(u32, @intFromBool(config.has_srgb)) << 2;
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
    sections.sub(.init).begin();

    const self = try createSelf(allocators.gpa(), engine);
    errdefer self.deinit();

    if (!self.gpu_device.setAllowedFramesInFlight(3)) {
        log.warn("failed to enable triple-buffering", .{});
    }
    try self.setPresentMode();
    try self.createTextures();
    try self.createSamplers();

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
    for (self.shaders.map.values()) |*shader| self.gpu_device.destroy(shader);
    self.shaders.deinit(gpa);
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
    for (self.texts.map.values()) |*text| text.deinit();
    self.texts.deinit(gpa);

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
        .shaders = try .init(allocator, 128),
        .mesh_objs = try .init(allocator, 128),
        .mesh_bufs = try .init(allocator, 128),
        .storage_bufs = try .init(allocator, 16),
        .materials = try .init(allocator, 16),
        .cameras = try .init(allocator, 16),
        .lights = try .init(allocator, 16),
        .textures = try .init(allocator, 128),
        .samplers = try .init(allocator, 128),
        .texts = try .init(allocator, 128),
        .stencil_format = gpu_device.stencilFormat(),
    };
    return self;
}

fn createTextures(self: *Self) !void {
    const win_size = self.window.pixelSize();

    _ = try self.createTexture("screen_buffer", &.{
        .type = .@"2D",
        .format = .hdr_f,
        .usage = .initMany(&.{ .sampler, .color_target }),
        .size = win_size,
    });

    _ = try self.createTexture("output_buffer", &.{
        .type = .@"2D",
        .format = .hdr_f,
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
        _ = try self.createSampler(
            @tagName(config.filter_mode) ++ "_" ++ @tagName(config.address_mode),
            &.{
                .min_filter = filter_config.filter,
                .mag_filter = filter_config.filter,
                .mipmap_mode = filter_config.mipmap_mode,
                .address_mode_u = config.address_mode,
                .address_mode_v = config.address_mode,
                .address_mode_w = config.address_mode,
            },
        );
    }
}

pub fn createMeshObject(self: *Self, key: []const u8, face_type: mesh.FaceType) !*mesh.Object {
    const mesh_obj = try self.mesh_objs.create(key);
    mesh_obj.* = .init(face_type);
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

pub fn createText(self: *Self, key: []const u8, font: ttf.Font, str: []const u8) !ttf.Text {
    var text = try self.text_engine.text(font, str);
    errdefer text.deinit();
    return self.insertText(key, text.ptr.?);
}

pub fn insertText(self: *Self, key: []const u8, text: *c.TTF_Text) !ttf.Text {
    try self.texts.insert(self.allocator, key, .fromOwned(text));
    return .fromOwned(text);
}

pub fn createGraphicsPipeline(
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

pub fn insertShader(self: *Self, key: []const u8, shader: *c.SDL_GPUShader) !GPUShader {
    try self.shaders.insert(self.allocator, key, .fromOwned(shader));
    return .fromOwned(shader);
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
