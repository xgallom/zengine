//!
//! The zengine render implementation
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const global = @import("../global.zig");
const math = @import("../math.zig");
const gfx_options = @import("../options.zig").gfx_options;
const perf = @import("../perf.zig");
const ui_mod = @import("../ui.zig");
const Error = @import("error.zig").Error;
const mesh = @import("mesh.zig");
const ttf = @import("ttf.zig");
const pass = @import("pass.zig");
const Camera = @import("Camera.zig");
const Renderer = @import("Renderer.zig");
const sections = Renderer.sections;
const Scene = @import("Scene.zig");

const log = std.log.scoped(.gfx_render);

pub const Item = struct {
    pub const Object = struct {
        key: [:0]const u8,
        mesh_obj: *mesh.Object,
        transform: *const math.Matrix4x4,

        pub const rotation_speed = 0.1;

        pub fn propertyEditor(self: *Item) ui_mod.UI.Element {
            return ui_mod.PropertyEditor(Item).init(self).element();
        }
    };

    pub const Text = struct {
        atlas: *ttf.AtlasDrawSequence,
        transform: *const math.Matrix4x4,
    };

    pub const Type = enum {
        mesh,
        text,
        ui_mesh,
        ui_text,
    };
};

pub const Items = struct {
    pub const Object = struct {
        items: Scene.FlatList(mesh.Object).Slice,
        idx: usize = 0,

        pub fn init(flat: *const Scene.Flattened, comptime field: @TypeOf(.enum_literal)) @This() {
            return .{ .items = @field(flat, @tagName(field)).slice() };
        }

        pub fn next(self: *@This()) ?Item.Object {
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

        pub fn reset(self: *@This()) void {
            self.idx = 0;
        }
    };

    pub const Text = struct {
        items: Scene.FlatList(ttf.Text).Slice,
        idx: usize = 0,

        pub fn init(flat: *const Scene.Flattened) @This() {
            return .{ .items = flat.text_objs.slice() };
        }

        pub fn next(self: *@This()) ?Item.Text {
            if (self.idx < self.items.len) {
                defer self.idx += 1;
                return .{
                    .atlas = self.items.items(.target)[self.idx].drawData(),
                    .transform = &self.items.items(.transform)[self.idx],
                };
            }
            return null;
        }

        pub fn reset(self: *@This()) void {
            self.idx = 0;
        }
    };
};

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
    self: *const Renderer,
    flat: *const Scene.Flattened,
    ui_ptr: ?*ui_mod.UI,
    items_iter: *Items.Object,
    ui_iter: *Items.Object,
    text_iter: *Items.Text,
    bloom: *const pass.Bloom,
) !bool {
    assert(self == flat.scene.renderer);
    const section = sections.sub(.render);
    section.begin();

    section.sub(.acquire).begin();
    _ = text_iter;

    const material_pipeline = self.pipelines.graphics.get("material");
    const line_pipeline = self.pipelines.graphics.get("line");
    const ui_pipeline = self.pipelines.graphics.get("ui");
    // const blend_pipeline = self.pipelines.get("blend");
    const render_pipeline = self.pipelines.graphics.get("render");
    const origin_mesh = self.mesh_bufs.get("origin");
    const screen_buffer = self.textures.get("screen_buffer");
    const output_buffer = self.textures.get("output_buffer");
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

        while (items_iter.next()) |item| {
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
        log.debug("ui render pass", .{});
        var render_pass = try command_buffer.renderPass(&.{.{
            .texture = screen_buffer,
            .clear_color = math.rgba_f32.tr_zero,
            .load_op = .load,
            .store_op = .store,
        }}, &.{
            .texture = stencil,
            .clear_depth = 1,
            .load_op = .dont_care,
            .store_op = .dont_care,
            .stencil_load_op = .dont_care,
        });

        render_pass.bindPipeline(ui_pipeline);
        @memcpy(uniform_buf[0..16], math.matrix4x4.sliceConst(&math.matrix4x4.identity));
        try render_pass.bindStorageBuffers(.fragment, 0, &.{lights_buffer.gpu_bufs.get(.vertex)});
        command_buffer.pushUniformData(.fragment, 1, &camera.position);
        command_buffer.pushUniformData(.fragment, 2, &light_counts.values);

        while (ui_iter.next()) |item| {
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

        log.debug("end ui render pass", .{});
        render_pass.end();
    }

    try bloom.render(self, command_buffer, screen_buffer, output_buffer);
    {
        var render_pass = try command_buffer.renderPass(&.{
            .{ .texture = swapchain, .load_op = .clear, .store_op = .store },
        }, null);

        render_pass.bindPipeline(render_pipeline);
        command_buffer.pushUniformData(.fragment, 0, &self.settings.uniformBuffer());
        try render_pass.bindSamplers(.fragment, 0, &.{
            .{ .texture = output_buffer, .sampler = screen_sampler },
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
            .load_op = .load,
            .store_op = .store,
            .stencil_load_op = .dont_care,
        });

        render_pass.bindPipeline(line_pipeline);

        for (render_scene_config.line_mesh_types) |mesh_type| {
            command_buffer.pushUniformData(.fragment, 0, render_scene_config.line_mesh_colors.getPtrConst(mesh_type));

            items_iter.reset();
            while (items_iter.next()) |item| {
                const mesh_obj = item.mesh_obj;
                if (!mesh_obj.is_visible.contains(.from(mesh_type))) continue;

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

        items_iter.reset();
        while (items_iter.next()) |item| {
            const mesh_obj = item.mesh_obj;
            if (!mesh_obj.is_visible.contains(.origin)) continue;

            try render_pass.bindVertexBuffers(0, &.{
                .{ .buffer = origin_mesh.gpu_bufs.get(.vertex), .offset = 0 },
            });

            render_pass.bindIndexBuffer(
                &.{ .buffer = origin_mesh.gpu_bufs.get(.index), .offset = 0 },
                .@"32bit",
            );

            @memcpy(uniform_buf[16..32], math.matrix4x4.sliceConst(item.transform));
            command_buffer.pushUniformData(.vertex, 0, uniform_buf);

            command_buffer.pushUniformData(.fragment, 0, &math.RGBAf32{ 1, 0, 0, 1 });
            render_pass.drawIndexedPrimitives(2, 1, 0, 0, 0);

            command_buffer.pushUniformData(.fragment, 0, &math.RGBAf32{ 0, 1, 0, 1 });
            render_pass.drawIndexedPrimitives(2, 1, 2, 0, 0);

            command_buffer.pushUniformData(.fragment, 0, &math.RGBAf32{ 0, 0, 1, 1 });
            render_pass.drawIndexedPrimitives(2, 1, 4, 0, 0);
        }

        section.sub(.origin).end();
        log.debug("end line render pass", .{});
        render_pass.end();
    }

    {
        var render_pass = try command_buffer.renderPass(&.{
            .{ .texture = swapchain, .load_op = .load, .store_op = .store },
        }, null);

        const ui_settings: Renderer.Settings = .{
            .config = .{
                .has_srgb = true,
            },
        };
        render_pass.bindPipeline(render_pipeline);
        command_buffer.pushUniformData(.fragment, 0, &ui_settings.uniformBuffer());
        try render_pass.bindSamplers(.fragment, 0, &.{
            .{ .texture = screen_buffer, .sampler = screen_sampler },
            .{ .texture = lut_map, .sampler = lut_sampler },
        });
        render_pass.drawScreen();
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

                const ui_settings: Renderer.Settings = .{
                    .config = .{
                        .has_srgb = true,
                    },
                };
                render_pass.bindPipeline(render_pipeline);
                command_buffer.pushUniformData(.fragment, 0, &ui_settings.uniformBuffer());
                try render_pass.bindSamplers(.fragment, 0, &.{
                    .{ .texture = screen_buffer, .sampler = screen_sampler },
                    .{ .texture = lut_map, .sampler = lut_sampler },
                });
                render_pass.drawScreen();
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
