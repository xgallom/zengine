const std = @import("std");
const sdl = @import("ext/sdl.zig");

const assert = std.debug.assert;

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();

    var allocator = arena.allocator();

    if (!sdl.SDL_Init(sdl.SDL_INIT_VIDEO)) {
        std.debug.print("Failed init: {s}", .{sdl.SDL_GetError()});
        return;
    }
    defer sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow("hello gamedev", 640, 400, 0);
    if (window == null) {
        std.debug.print("Failed creating window: {s}", .{sdl.SDL_GetError()});
        return;
    }
    defer sdl.SDL_DestroyWindow(window);

    // const renderer = sdl.SDL_CreateRenderer(window, undefined);
    // defer sdl.SDL_DestroyRenderer(renderer);

    const gpu_device = sdl.SDL_CreateGPUDevice(sdl.SDL_GPU_SHADERFORMAT_SPIRV, true, null);
    if (gpu_device == null) {
        std.debug.print("Failed creating gpu_device: {s}", .{sdl.SDL_GetError()});
        return;
    }
    defer sdl.SDL_DestroyGPUDevice(gpu_device);

    const shader_formats = sdl.SDL_GetGPUShaderFormats(gpu_device);
    if (shader_formats & sdl.SDL_GPU_SHADERFORMAT_SPIRV == 0) {
        std.debug.print("Unsupported SPIRV shader format", .{});
        return;
    }

    const dir = std.fs.cwd();

    const vertex_shader_file = dir.openFile("shaders/bin/triangle_raw.vert.spv", .{}) catch |err| {
        std.debug.print("Failed opening vertex_file: {s}", .{@errorName(err)});
        return;
    };

    var vertex_code_size = (try vertex_shader_file.stat()).size;
    const vertex_code = try allocator.alloc(u8, vertex_code_size);
    vertex_code_size = vertex_shader_file.readAll(vertex_code) catch |err| {
        std.debug.print("Failed reading vertex_file: {s}", .{@errorName(err)});
        vertex_shader_file.close();
        return;
    };
    vertex_shader_file.close();

    const vertex_shader = sdl.SDL_CreateGPUShader(gpu_device, &sdl.SDL_GPUShaderCreateInfo{
        .code_size = vertex_code_size,
        .code = vertex_code.ptr,
        .entrypoint = "main",
        .format = sdl.SDL_GPU_SHADERFORMAT_SPIRV,
        .stage = sdl.SDL_GPU_SHADERSTAGE_VERTEX,
        .num_samplers = 0,
        .num_storage_textures = 0,
        .num_storage_buffers = 0,
        .num_uniform_buffers = 0,
        .props = 0,
    });
    if (vertex_shader == null) {
        std.debug.print("Failed creating vertex_shader: {s}", .{sdl.SDL_GetError()});
        return;
    }
    defer sdl.SDL_ReleaseGPUShader(gpu_device, vertex_shader);

    const fragment_shader_file = dir.openFile("shaders/bin/solid_color.frag.spv", .{}) catch |err| {
        std.debug.print("Failed opening fragment_file: {s}", .{@errorName(err)});
        return;
    };

    var fragment_code_size = (try fragment_shader_file.stat()).size;
    const fragment_code = try allocator.alloc(u8, fragment_code_size);
    fragment_code_size = fragment_shader_file.readAll(fragment_code) catch |err| {
        std.debug.print("Failed reading fragment_file: {s}", .{@errorName(err)});
        fragment_shader_file.close();
        return;
    };
    fragment_shader_file.close();

    const fragment_shader = sdl.SDL_CreateGPUShader(gpu_device, &sdl.SDL_GPUShaderCreateInfo{
        .code_size = fragment_code_size,
        .code = fragment_code.ptr,
        .entrypoint = "main",
        .format = sdl.SDL_GPU_SHADERFORMAT_SPIRV,
        .stage = sdl.SDL_GPU_SHADERSTAGE_FRAGMENT,
        .num_samplers = 0,
        .num_storage_textures = 0,
        .num_storage_buffers = 0,
        .num_uniform_buffers = 0,
        .props = 0,
    });
    if (fragment_shader == null) {
        std.debug.print("Failed creating fragment_shader: {s}", .{sdl.SDL_GetError()});
        return;
    }
    defer sdl.SDL_ReleaseGPUShader(gpu_device, fragment_shader);

    if (!sdl.SDL_ClaimWindowForGPUDevice(gpu_device, window)) {
        std.debug.print("Failed claiming window for gpu_device: {s}", .{sdl.SDL_GetError()});
        return;
    }
    defer sdl.SDL_ReleaseWindowFromGPUDevice(gpu_device, window);

    const pipeline = sdl.SDL_CreateGPUGraphicsPipeline(gpu_device, &sdl.SDL_GPUGraphicsPipelineCreateInfo{
        .vertex_shader = vertex_shader,
        .fragment_shader = fragment_shader,
        .primitive_type = sdl.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
        .rasterizer_state = .{
            .fill_mode = sdl.SDL_GPU_FILLMODE_FILL,
        },
        .target_info = .{
            .num_color_targets = 1,
            .color_target_descriptions = &sdl.SDL_GPUColorTargetDescription{
                .format = sdl.SDL_GetGPUSwapchainTextureFormat(gpu_device, window)
            }
        }
    });
    if (pipeline == null) {
        std.debug.print("Failed creating pipeline: {s}", .{sdl.SDL_GetError()});
        return;
    }
    defer sdl.SDL_ReleaseGPUGraphicsPipeline(gpu_device, pipeline);

    const viewport = sdl.SDL_GPUViewport{
        .x = 160,
        .y = 120,
        .w = 320,
        .h = 240,
        .min_depth = 0.1,
        .max_depth = 1.0,
    };

    return mainloop: while (true) {
        var sdl_event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&sdl_event)) {
            switch (sdl_event.type) {
                sdl.SDL_EVENT_QUIT => break :mainloop,
                sdl.SDL_EVENT_KEY_DOWN => break :mainloop,
                else => {},
            }
        }

        if (sdl.SDL_AcquireGPUCommandBuffer(gpu_device)) |command_buffer| {
            var swapchain_texture: ?*sdl.SDL_GPUTexture = undefined;
            if (!sdl.SDL_AcquireGPUSwapchainTexture(command_buffer, window, &swapchain_texture, null, null)) {
                std.debug.print("Failed acquiring swapchain_texture: {s}", .{sdl.SDL_GetError()});
            }
            if (swapchain_texture != null) {
                const color_target_info = sdl.SDL_GPUColorTargetInfo{
                    .texture = swapchain_texture,
                    .clear_color = sdl.SDL_FColor{ .a = 1 },
                    .load_op = sdl.SDL_GPU_LOADOP_CLEAR,
                    .store_op = sdl.SDL_GPU_STOREOP_STORE,
                };

                const render_pass = sdl.SDL_BeginGPURenderPass(command_buffer, &color_target_info, 1, null);
                if (render_pass == null) {
                    std.debug.print("render_pass is null", .{});
                }

                sdl.SDL_BindGPUGraphicsPipeline(render_pass, pipeline);
                sdl.SDL_SetGPUViewport(render_pass, &viewport);
                sdl.SDL_DrawGPUPrimitives(render_pass, 3, 1, 0, 0);
                sdl.SDL_EndGPURenderPass(render_pass);
            } else {
                std.debug.print("swapchain_texture is null", .{});
            }

            if (!sdl.SDL_SubmitGPUCommandBuffer(command_buffer)) {
                std.debug.print("Failed submitting command_buffer: {s}", .{sdl.SDL_GetError()});
            }
        } else {
            std.debug.print("Failed to acquire gpu_command_buffer: {s}", .{sdl.SDL_GetError()});
        }
    };
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
