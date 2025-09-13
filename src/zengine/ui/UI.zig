//!
//! The zengine ui renderer
//!

const std = @import("std");
const assert = std.debug.assert;

const allocators = @import("../allocators.zig");
const Engine = @import("../Engine.zig");
const c = @import("../ext.zig").c;
const gfx = @import("../gfx.zig");
const global = @import("../global.zig");
const math = @import("../math.zig");
const perf = @import("../perf.zig");

const log = std.log.scoped(.ui_UI);
pub const sections = perf.sections(@This(), &.{ .init, .draw });

const Self = @This();

draw_data: ?*c.ImDrawData = null,
show_ui: bool = false,

pub const Element = struct {
    ptr: *anyopaque,
    draw: *const fn (ptr: *anyopaque, ui: *const Self, is_open: *bool) void,
};

pub fn init(engine: *Engine, renderer: *gfx.Renderer) gfx.Renderer.InitError!*Self {
    const main_scale = c.SDL_GetDisplayContentScale(c.SDL_GetPrimaryDisplay());
    _ = c.igCreateContext(null);
    const io = c.igGetIO_Nil().?;
    io.*.ConfigFlags |= c.ImGuiConfigFlags_NavEnableKeyboard;
    io.*.ConfigFlags |= c.ImGuiConfigFlags_DockingEnable;
    c.igStyleColorsDark(null);
    const style = c.igGetStyle().?;
    c.ImGuiStyle_ScaleAllSizes(style, main_scale);
    style.*.FontScaleDpi = main_scale;
    io.*.ConfigDpiScaleFonts = true;
    io.*.ConfigDpiScaleViewports = true;

    _ = c.ImGui_ImplSDL3_InitForSDLGPU(engine.window);
    var init_info: c.ImGui_ImplSDLGPU3_InitInfo = .{
        .Device = renderer.gpu_device,
        .ColorTargetFormat = c.SDL_GetGPUSwapchainTextureFormat(renderer.gpu_device, engine.window),
        .MSAASamples = c.SDL_GPU_SAMPLECOUNT_1,
    };
    _ = c.ImGui_ImplSDLGPU3_Init(&init_info);

    const result = try allocators.global().create(Self);
    result.* = .{};
    return result;
}

pub fn deinit(self: *Self) void {
    c.ImGui_ImplSDLGPU3_Shutdown();
    c.ImGui_ImplSDL3_Shutdown();
    allocators.global().destroy(self);
}

pub fn beginDraw(self: *const Self) void {
    if (!self.show_ui) return;

    c.ImGui_ImplSDLGPU3_NewFrame();
    c.ImGui_ImplSDL3_NewFrame();
    c.igNewFrame();

    const viewport = c.igGetMainViewport();
    _ = c.igDockSpaceOverViewport(
        0,
        viewport,
        c.ImGuiDockNodeFlags_PassthruCentralNode,
        null,
    );
}

pub fn draw(self: *const Self, element: Element, is_open: *bool) void {
    if (!self.show_ui or !is_open.*) return;
    element.draw(element.ptr, self, is_open);
}

pub fn endDraw(self: *Self) void {
    if (!self.show_ui) return;
    c.igRender();
    self.draw_data = c.igGetDrawData();
}

pub fn submitPass(self: *Self, command_buffer: ?*c.SDL_GPUCommandBuffer, swapchain_texture: ?*c.SDL_GPUTexture) gfx.Renderer.DrawError!void {
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
        return gfx.Renderer.DrawError.DrawFailed;
    }

    c.ImGui_ImplSDLGPU3_RenderDrawData(self.draw_data, command_buffer, render_pass, null);

    log.debug("end imgui render pass", .{});
    c.SDL_EndGPURenderPass(render_pass);
}
