//!
//! The zengine ui renderer
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const cache = @import("cache.zig");
const Engine = @import("../Engine.zig");
const c = @import("../ext.zig").c;
const gfx = @import("../gfx.zig");
const global = @import("../global.zig");
const math = @import("../math.zig");
const perf = @import("../perf.zig");
const AllocsWindpw = @import("AllocsWindow.zig");
const PerfWindow = @import("PerfWindow.zig");
const PropertyEditorWindow = @import("PropertyEditorWindow.zig");

const log = std.log.scoped(.ui);
pub const sections = perf.sections(@This(), &.{ .init, .draw });

const Self = @This();

draw_data: ?*c.ImDrawData = null,
show_ui: bool = false,
render_ui: bool = false,
init_docking: bool = true,

pub const Element = struct {
    ptr: ?*anyopaque,
    drawFn: *const DrawFn,

    pub const DrawFn = fn (ptr: ?*anyopaque, ui: *const Self, is_open: *bool) void;

    pub fn draw(e: Element, ui: *const Self, is_open: *bool) void {
        e.drawFn(e.ptr, ui, is_open);
    }
};

var ref_count: std.atomic.Value(usize) = .init(0);

pub fn create(engine: *Engine, renderer: *gfx.Renderer) !*Self {
    try sections.register();

    const section = sections.sub(.init);
    section.begin();
    defer section.end();

    _ = c.igCreateContext(null);
    _ = c.ImPlot_CreateContext();

    const main_scale = c.SDL_GetDisplayContentScale(c.SDL_GetPrimaryDisplay());
    const io = c.igGetIO_Nil().?;
    const style = c.igGetStyle().?;

    io.*.ConfigFlags |= c.ImGuiConfigFlags_NavEnableKeyboard;
    io.*.ConfigFlags |= c.ImGuiConfigFlags_DockingEnable;

    c.igStyleColorsDark(null);
    c.ImGuiStyle_ScaleAllSizes(style, main_scale);

    style.*.FontScaleDpi = main_scale;
    io.*.ConfigDpiScaleFonts = true;
    io.*.ConfigDpiScaleViewports = true;

    _ = c.ImGui_ImplSDL3_InitForSDLGPU(engine.main_win.ptr);
    var init_info: c.ImGui_ImplSDLGPU3_InitInfo = .{
        .Device = renderer.gpu_device.ptr,
        .ColorTargetFormat = @intFromEnum(renderer.swapchainFormat(engine)),
        .MSAASamples = c.SDL_GPU_SAMPLECOUNT_1,
    };
    _ = c.ImGui_ImplSDLGPU3_Init(&init_info);

    const result = try allocators.global().create(Self);
    result.* = .{};
    cache.init();
    return result;
}

pub fn deinit(self: *Self) void {
    cache.deinit();
    c.ImGui_ImplSDLGPU3_Shutdown();
    c.ImGui_ImplSDL3_Shutdown();
    c.ImPlot_DestroyContext(null);
    c.igDestroyContext(null);
    self.* = .{};
}

pub fn beginDraw(self: *Self) void {
    self.render_ui = self.show_ui;
    if (!self.render_ui) return;

    sections.sub(.draw).begin();

    c.ImGui_ImplSDLGPU3_NewFrame();
    c.ImGui_ImplSDL3_NewFrame();
    c.igNewFrame();
}

pub fn draw(self: *const Self, element: Element, is_open: *bool) void {
    if (!self.render_ui or !is_open.*) return;
    element.draw(self, is_open);
}

pub fn drawMainMenuBar(self: *const Self, config: struct {
    allocs_open: *bool,
    property_editor_open: *bool,
    perf_open: *bool,
}) void {
    if (!self.render_ui) return;
    if (c.igBeginMainMenuBar()) {
        if (c.igBeginMenu("Window", true)) {
            if (c.igMenuItem_Bool("Property Editor", null, false, true)) config.property_editor_open.* = true;
            if (c.igMenuItem_Bool("Performance", null, false, true)) config.perf_open.* = true;
            if (c.igMenuItem_Bool("Allocations", null, false, true)) config.allocs_open.* = true;
            c.igEndMenu();
        }
    }
    c.igEndMainMenuBar();
}

pub fn drawDock(self: *Self) void {
    if (!self.render_ui) return;
    const viewport = c.igGetMainViewport();
    const dock_node = c.igDockSpaceOverViewport(
        0,
        viewport,
        c.ImGuiDockNodeFlags_PassthruCentralNode,
        null,
    );

    if (self.init_docking) {
        @branchHint(.cold);
        self.init_docking = false;
        var nodes: [4]c.ImGuiID = undefined;

        c.igDockBuilderRemoveNodeChildNodes(dock_node);
        _ = c.igDockBuilderSplitNode(dock_node, c.ImGuiDir_Left, 1.0 / 4.0, &nodes[0], &nodes[3]);
        _ = c.igDockBuilderSplitNode(nodes[3], c.ImGuiDir_Right, 1.0 / 3.0, &nodes[2], &nodes[1]);

        const view_size = viewport.*.WorkSize;
        const side_size = c.ImVec2{ .x = 630, .y = view_size.y };
        const central_size = c.ImVec2{ .x = view_size.x - 2 * side_size.x, .y = view_size.y };

        c.igDockBuilderSetNodeSize(nodes[0], side_size);
        c.igDockBuilderSetNodeSize(nodes[1], central_size);
        c.igDockBuilderSetNodeSize(nodes[2], side_size);

        c.igDockBuilderDockWindow(PropertyEditorWindow.window_name, nodes[0]);
        c.igDockBuilderDockWindow(PerfWindow.window_name, nodes[2]);
        c.igDockBuilderDockWindow(AllocsWindpw.window_name, nodes[2]);
        c.igDockBuilderFinish(dock_node);
    }
}

pub fn endDraw(self: *Self) void {
    if (!self.render_ui) return;

    c.igRender();
    self.draw_data = c.igGetDrawData();

    sections.sub(.draw).end();
}

pub fn submitPass(self: *Self, command_buffer: ?*c.SDL_GPUCommandBuffer, swapchain_texture: ?*c.SDL_GPUTexture) !void {
    if (!self.show_ui) return;

    assert(self.draw_data != null);
    assert(command_buffer != null);
    assert(swapchain_texture != null);

    c.ImGui_ImplSDLGPU3_PrepareDrawData(self.draw_data, command_buffer);

    log.debug("imgui render pass", .{});
    const render_pass = c.SDL_BeginGPURenderPass(
        command_buffer,
        &c.SDL_GPUColorTargetInfo{
            .texture = swapchain_texture,
            .load_op = c.SDL_GPU_LOADOP_LOAD,
            .store_op = c.SDL_GPU_STOREOP_STORE,
        },
        1,
        null,
    );
    if (render_pass == null) {
        log.err("failed to begin render_pass: {s}", .{c.SDL_GetError()});
        return gfx.Error.DrawFailed;
    }

    c.ImGui_ImplSDLGPU3_RenderDrawData(self.draw_data, command_buffer, render_pass, null);

    log.debug("end imgui render pass", .{});
    c.SDL_EndGPURenderPass(render_pass);
}
