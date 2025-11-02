//!
//! The zengine gfx module types
//!

const std = @import("std");
const assert = std.debug.assert;

const c = @import("../ext.zig").c;
const math = @import("../math.zig");
const sdl = @import("../sdl.zig");
const GPUBuffer = @import("GPUBuffer.zig");
const GPUSampler = @import("GPUSampler.zig");
const GPUTexture = @import("GPUTexture.zig");
const GPUTransferBuffer = @import("GPUTransferBuffer.zig");

pub const FlipMode = enum(c.SDL_FlipMode) {
    none = c.SDL_FLIP_NONE,
    horitontal = c.SDL_FLIP_HORIZONTAL,
    vertical = c.SDL_FLIP_VERTICAL,
    horizontal_and_vertical = c.SDL_FLIP_HORIZONTAL_AND_VERTICAL,
    pub const default = .none;
};

pub const PrimitiveType = enum(c.SDL_GPUPrimitiveType) {
    triangle_list = c.SDL_GPU_PRIMITIVETYPE_TRIANGLELIST,
    triangle_strip = c.SDL_GPU_PRIMITIVETYPE_TRIANGLESTRIP,
    line_list = c.SDL_GPU_PRIMITIVETYPE_LINELIST,
    line_strip = c.SDL_GPU_PRIMITIVETYPE_LINESTRIP,
    point_list = c.SDL_GPU_PRIMITIVETYPE_POINTLIST,
    pub const default = .triangle_list;
};

pub const LoadOp = enum(c.SDL_GPULoadOp) {
    load = c.SDL_GPU_LOADOP_LOAD,
    clear = c.SDL_GPU_LOADOP_CLEAR,
    dont_care = c.SDL_GPU_LOADOP_DONT_CARE,
    pub const default = .load;
};

pub const StoreOp = enum(c.SDL_GPUStoreOp) {
    store = c.SDL_GPU_STOREOP_STORE,
    dont_care = c.SDL_GPU_STOREOP_DONT_CARE,
    resolve = c.SDL_GPU_STOREOP_RESOLVE,
    resolve_and_store = c.SDL_GPU_STOREOP_RESOLVE_AND_STORE,
    pub const default = .store;
};

pub const IndexElementSize = enum(c.SDL_GPUIndexElementSize) {
    @"16bit" = c.SDL_GPU_INDEXELEMENTSIZE_16BIT,
    @"32bit" = c.SDL_GPU_INDEXELEMENTSIZE_32BIT,
    pub const default = .@"16bit";
};
pub const SampleCount = enum(c.SDL_GPUSampleCount) {
    @"1" = c.SDL_GPU_SAMPLECOUNT_1,
    @"2" = c.SDL_GPU_SAMPLECOUNT_2,
    @"4" = c.SDL_GPU_SAMPLECOUNT_4,
    @"8" = c.SDL_GPU_SAMPLECOUNT_8,
    pub const default = .@"1";
};

pub const VertexElementFormat = enum(c.SDL_GPUVertexElementFormat) {
    invalid = c.SDL_GPU_VERTEXELEMENTFORMAT_INVALID,
    i32 = c.SDL_GPU_VERTEXELEMENTFORMAT_INT,
    i32_2 = c.SDL_GPU_VERTEXELEMENTFORMAT_INT2,
    i32_3 = c.SDL_GPU_VERTEXELEMENTFORMAT_INT3,
    i32_4 = c.SDL_GPU_VERTEXELEMENTFORMAT_INT4,
    u32 = c.SDL_GPU_VERTEXELEMENTFORMAT_UINT,
    u32_2 = c.SDL_GPU_VERTEXELEMENTFORMAT_UINT2,
    u32_3 = c.SDL_GPU_VERTEXELEMENTFORMAT_UINT3,
    u32_4 = c.SDL_GPU_VERTEXELEMENTFORMAT_UINT4,
    f32 = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT,
    f32_2 = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT2,
    f32_3 = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT3,
    f32_4 = c.SDL_GPU_VERTEXELEMENTFORMAT_FLOAT4,
    i8_2 = c.SDL_GPU_VERTEXELEMENTFORMAT_BYTE2,
    i8_4 = c.SDL_GPU_VERTEXELEMENTFORMAT_BYTE4,
    u8_2 = c.SDL_GPU_VERTEXELEMENTFORMAT_UBYTE2,
    u8_4 = c.SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4,
    i8_2_norm = c.SDL_GPU_VERTEXELEMENTFORMAT_BYTE2_NORM,
    i8_4_norm = c.SDL_GPU_VERTEXELEMENTFORMAT_BYTE4_NORM,
    u8_2_norm = c.SDL_GPU_VERTEXELEMENTFORMAT_UBYTE2_NORM,
    u8_4_norm = c.SDL_GPU_VERTEXELEMENTFORMAT_UBYTE4_NORM,
    i16_2 = c.SDL_GPU_VERTEXELEMENTFORMAT_SHORT2,
    i16_4 = c.SDL_GPU_VERTEXELEMENTFORMAT_SHORT4,
    u16_2 = c.SDL_GPU_VERTEXELEMENTFORMAT_USHORT2,
    u16_4 = c.SDL_GPU_VERTEXELEMENTFORMAT_USHORT4,
    i16_2_norm = c.SDL_GPU_VERTEXELEMENTFORMAT_SHORT2_NORM,
    i16_4_norm = c.SDL_GPU_VERTEXELEMENTFORMAT_SHORT4_NORM,
    u16_2_norm = c.SDL_GPU_VERTEXELEMENTFORMAT_USHORT2_NORM,
    u16_4_norm = c.SDL_GPU_VERTEXELEMENTFORMAT_USHORT4_NORM,
    f16_2 = c.SDL_GPU_VERTEXELEMENTFORMAT_HALF2,
    f16_4 = c.SDL_GPU_VERTEXELEMENTFORMAT_HALF4,
    pub const default = .invalid;
};

pub const VertexInputRate = enum(c.SDL_GPUVertexInputRate) {
    vertex = c.SDL_GPU_VERTEXINPUTRATE_VERTEX,
    instance = c.SDL_GPU_VERTEXINPUTRATE_INSTANCE,
    pub const default = .vertex;
};

pub const FillMode = enum(c.SDL_GPUFillMode) {
    fill = c.SDL_GPU_FILLMODE_FILL,
    line = c.SDL_GPU_FILLMODE_LINE,
    pub const default = .fill;
};

pub const CullMode = enum(c.SDL_GPUCullMode) {
    none = c.SDL_GPU_CULLMODE_NONE,
    front = c.SDL_GPU_CULLMODE_FRONT,
    back = c.SDL_GPU_CULLMODE_BACK,
    pub const default = .none;
};

pub const FrontFace = enum(c.SDL_GPUFrontFace) {
    counter_clockwise = c.SDL_GPU_FRONTFACE_COUNTER_CLOCKWISE,
    clockwise = c.SDL_GPU_FRONTFACE_CLOCKWISE,
    pub const default = .counter_clockwise;
};

pub const CompareOp = enum(c.SDL_GPUCompareOp) {
    invalid = c.SDL_GPU_COMPAREOP_INVALID,
    never = c.SDL_GPU_COMPAREOP_NEVER,
    less = c.SDL_GPU_COMPAREOP_LESS,
    equal = c.SDL_GPU_COMPAREOP_EQUAL,
    less_or_equal = c.SDL_GPU_COMPAREOP_LESS_OR_EQUAL,
    greater = c.SDL_GPU_COMPAREOP_GREATER,
    not_equal = c.SDL_GPU_COMPAREOP_NOT_EQUAL,
    greater_or_equal = c.SDL_GPU_COMPAREOP_GREATER_OR_EQUAL,
    always = c.SDL_GPU_COMPAREOP_ALWAYS,
    pub const default = .invalid;
};

pub const StencilOp = enum(c.SDL_GPUStencilOp) {
    invalid = c.SDL_GPU_STENCILOP_INVALID,
    keep = c.SDL_GPU_STENCILOP_KEEP,
    zero = c.SDL_GPU_STENCILOP_ZERO,
    replace = c.SDL_GPU_STENCILOP_REPLACE,
    inc_clamp = c.SDL_GPU_STENCILOP_INCREMENT_AND_CLAMP,
    dec_clamp = c.SDL_GPU_STENCILOP_DECREMENT_AND_CLAMP,
    invert = c.SDL_GPU_STENCILOP_INVERT,
    inc_wrap = c.SDL_GPU_STENCILOP_INCREMENT_AND_WRAP,
    dec_wrap = c.SDL_GPU_STENCILOP_DECREMENT_AND_WRAP,
    pub const default = .invalid;
};

pub const BlendOp = enum(c.SDL_GPUBlendOp) {
    invalid = c.SDL_GPU_BLENDOP_INVALID,
    add = c.SDL_GPU_BLENDOP_ADD,
    sub = c.SDL_GPU_BLENDOP_SUBTRACT,
    reverse_sub = c.SDL_GPU_BLENDOP_REVERSE_SUBTRACT,
    min = c.SDL_GPU_BLENDOP_MIN,
    max = c.SDL_GPU_BLENDOP_MAX,
    pub const default = .invalid;
};

pub const BlendFactor = enum(c.SDL_GPUBlendFactor) {
    invalid = c.SDL_GPU_BLENDFACTOR_INVALID,
    zero = c.SDL_GPU_BLENDFACTOR_ZERO,
    one = c.SDL_GPU_BLENDFACTOR_ONE,
    src_color = c.SDL_GPU_BLENDFACTOR_SRC_COLOR,
    one_minus_src_color = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_COLOR,
    dst_color = c.SDL_GPU_BLENDFACTOR_DST_COLOR,
    one_minus_dst_color = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_DST_COLOR,
    src_alpha = c.SDL_GPU_BLENDFACTOR_SRC_ALPHA,
    one_minus_src_alpha = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
    dst_alpha = c.SDL_GPU_BLENDFACTOR_DST_ALPHA,
    one_minus_dst_alpha = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_DST_ALPHA,
    constant_color = c.SDL_GPU_BLENDFACTOR_CONSTANT_COLOR,
    one_minus_constant_color = c.SDL_GPU_BLENDFACTOR_ONE_MINUS_CONSTANT_COLOR,
    src_alpha_saturate = c.SDL_GPU_BLENDFACTOR_SRC_ALPHA_SATURATE,
    pub const default = .invalid;
};

pub const Filter = enum(c.SDL_GPUFilter) {
    nearest = c.SDL_GPU_FILTER_NEAREST,
    linear = c.SDL_GPU_FILTER_LINEAR,
    pub const default = .nearest;
};

pub const PresentMode = enum(c.SDL_GPUPresentMode) {
    vsync = c.SDL_GPU_PRESENTMODE_VSYNC,
    immediate = c.SDL_GPU_PRESENTMODE_IMMEDIATE,
    mailbox = c.SDL_GPU_PRESENTMODE_MAILBOX,
};

pub const SwapchainComposition = enum(c.SDL_GPUSwapchainComposition) {
    SDR = c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR,
    SDR_linear = c.SDL_GPU_SWAPCHAINCOMPOSITION_SDR_LINEAR,
    HDR_extended_linear = c.SDL_GPU_SWAPCHAINCOMPOSITION_HDR_EXTENDED_LINEAR,
    HDR10_ST2084 = c.SDL_GPU_SWAPCHAINCOMPOSITION_HDR10_ST2084,
};

pub const TextureTransferInfo = struct {
    transfer_buffer: GPUTransferBuffer = .invalid,
    offset: u32 = 0,
    pixels_per_row: u32 = 0,
    rows_per_layer: u32 = 0,

    pub fn toSDL(self: *const @This()) c.SDL_GPUTextureTransferInfo {
        return .{
            .transfer_buffer = self.transfer_buffer.ptr,
            .offset = self.offset,
            .pixels_per_row = self.pixels_per_row,
            .rows_per_layer = self.rows_per_layer,
        };
    }
};

pub const TransferBufferLocation = struct {
    transfer_buffer: GPUTransferBuffer = .invalid,
    offset: u32 = 0,

    pub fn toSDL(self: *const @This()) c.SDL_GPUTransferBufferLocation {
        return .{
            .transfer_buffer = self.transfer_buffer.ptr,
            .offset = self.offset,
        };
    }
};

pub const VertexBufferDescription = struct {
    slot: u32 = 0,
    pitch: u32 = 0,
    input_rate: VertexInputRate = .default,
    instance_step_rate: u32 = 0,

    pub fn toSDL(self: *const @This()) c.SDL_GPUVertexBufferDescription {
        return .{
            .slot = self.slot,
            .pitch = self.pitch,
            .input_rate = @intFromEnum(self.input_rate),
            .instance_step_rate = self.instance_step_rate,
        };
    }
};

pub const VertexInputState = struct {
    vertex_buffer_descriptions: []const VertexBufferDescription = &.{},
    vertex_attributes: []const VertexAttribute = &.{},

    pub fn toSDL(self: *const @This(), gpa: std.mem.Allocator) !c.SDL_GPUVertexInputState {
        const vertex_buffer_descriptions = try sdl.sliceFrom(gpa, self.vertex_buffer_descriptions);
        const vertex_attributes = try sdl.sliceFrom(gpa, self.vertex_attributes);
        return .{
            .vertex_buffer_descriptions = vertex_buffer_descriptions.ptr,
            .num_vertex_buffers = @intCast(vertex_buffer_descriptions.len),
            .vertex_attributes = vertex_attributes.ptr,
            .num_vertex_attributes = @intCast(vertex_attributes.len),
        };
    }
};

pub const VertexAttribute = struct {
    location: u32 = 0,
    buffer_slot: u32 = 0,
    format: VertexElementFormat = .default,
    offset: u32 = 0,

    pub fn toSDL(self: *const @This()) c.SDL_GPUVertexAttribute {
        return .{
            .location = self.location,
            .buffer_slot = self.buffer_slot,
            .format = @intFromEnum(self.format),
            .offset = self.offset,
        };
    }
};

pub const RasterizerState = struct {
    fill_mode: FillMode = .default,
    cull_mode: CullMode = .default,
    front_face: FrontFace = .default,
    depth_bias_constant_factor: f32 = 0,
    depth_bias_clamp: f32 = 0,
    depth_bias_slope_factor: f32 = 0,
    enable_depth_bias: bool = false,
    enable_depth_clip: bool = false,

    pub fn toSDL(self: *const @This()) c.SDL_GPURasterizerState {
        return .{
            .fill_mode = @intFromEnum(self.fill_mode),
            .cull_mode = @intFromEnum(self.cull_mode),
            .front_face = @intFromEnum(self.front_face),
            .depth_bias_constant_factor = self.depth_bias_constant_factor,
            .depth_bias_clamp = self.depth_bias_clamp,
            .depth_bias_slope_factor = self.depth_bias_slope_factor,
            .enable_depth_bias = self.enable_depth_bias,
            .enable_depth_clip = self.enable_depth_clip,
        };
    }
};

pub const MultisampleState = struct {
    sample_count: SampleCount = .default,
    sample_mask: u32 = 0,
    enable_mask: bool = false,
    enable_alpha_to_coverage: bool = false,

    pub fn toSDL(self: *const @This()) c.SDL_GPUMultisampleState {
        return .{
            .sample_count = @intFromEnum(self.sample_count),
            .sample_mask = self.sample_mask,
            .enable_mask = self.enable_mask,
            .enable_alpha_to_coverage = self.enable_alpha_to_coverage,
        };
    }
};

pub const DepthStencilState = struct {
    compare_op: CompareOp = .default,
    back_stencil_state: StencilOpState = .{},
    front_stencil_state: StencilOpState = .{},
    compare_mask: u8 = 0,
    write_mask: u8 = 0,
    enable_depth_test: bool = false,
    enable_depth_write: bool = false,
    enable_stencil_test: bool = false,

    pub fn toSDL(self: *const @This()) c.SDL_GPUDepthStencilState {
        return .{
            .compare_op = @intFromEnum(self.compare_op),
            .back_stencil_state = self.back_stencil_state.toSDL(),
            .front_stencil_state = self.front_stencil_state.toSDL(),
            .compare_mask = self.compare_mask,
            .write_mask = self.write_mask,
            .enable_depth_test = self.enable_depth_test,
            .enable_depth_write = self.enable_depth_write,
            .enable_stencil_test = self.enable_stencil_test,
        };
    }
};

pub const StencilOpState = struct {
    fail_op: StencilOp = .default,
    pass_op: StencilOp = .default,
    depth_fail_op: StencilOp = .default,
    compare_op: CompareOp = .default,

    pub fn toSDL(self: *const @This()) c.SDL_GPUStencilOpState {
        return .{
            .fail_op = @intFromEnum(self.fail_op),
            .pass_op = @intFromEnum(self.pass_op),
            .depth_fail_op = @intFromEnum(self.depth_fail_op),
            .compare_op = @intFromEnum(self.compare_op),
        };
    }
};

pub const ColorTargetBlendState = struct {
    src_color_blendfactor: BlendFactor = .default,
    dst_color_blendfactor: BlendFactor = .default,
    color_blend_op: BlendOp = .default,
    src_alpha_blendfactor: BlendFactor = .default,
    dst_alpha_blendfactor: BlendFactor = .default,
    alpha_blend_op: BlendOp = .default,
    color_write_mask: u8 = 0,
    enable_blend: bool = false,
    enable_color_write_mask: bool = false,

    pub fn toSDL(self: *const @This()) c.SDL_GPUColorTargetBlendState {
        return .{
            .src_color_blendfactor = @intFromEnum(self.src_color_blendfactor),
            .dst_color_blendfactor = @intFromEnum(self.dst_color_blendfactor),
            .color_blend_op = @intFromEnum(self.color_blend_op),
            .src_alpha_blendfactor = @intFromEnum(self.src_alpha_blendfactor),
            .dst_alpha_blendfactor = @intFromEnum(self.dst_alpha_blendfactor),
            .alpha_blend_op = @intFromEnum(self.alpha_blend_op),
            .color_write_mask = self.color_write_mask,
            .enable_blend = self.enable_blend,
            .enable_color_write_mask = self.enable_color_write_mask,
        };
    }
};

pub const ColorTargetDescription = struct {
    format: GPUTexture.Format = .default,
    blend_state: ColorTargetBlendState = .{},

    pub fn toSDL(self: *const @This()) c.SDL_GPUColorTargetDescription {
        return .{
            .format = @intFromEnum(self.format),
            .blend_state = self.blend_state.toSDL(),
        };
    }
};

pub const ColorTargetInfo = struct {
    texture: GPUTexture = .invalid,
    mip_level: u32 = 0,
    layer_or_depth_plane: u32 = 0,
    clear_color: math.RGBAf32 = math.rgba_f32.zero,
    load_op: LoadOp = .default,
    store_op: StoreOp = .default,
    resolve_texture: GPUTexture = .invalid,
    resolve_mip_level: u21 = 0,
    resolve_layer: u32 = 0,
    cycle: bool = false,
    cycle_resolve_texture: bool = false,

    pub fn toSDL(self: *const @This()) c.SDL_GPUColorTargetInfo {
        return .{
            .texture = self.texture.ptr,
            .mip_level = self.mip_level,
            .layer_or_depth_plane = self.layer_or_depth_plane,
            .clear_color = .{
                .r = self.clear_color[0],
                .g = self.clear_color[1],
                .b = self.clear_color[2],
                .a = self.clear_color[3],
            },
            .load_op = @intFromEnum(self.load_op),
            .store_op = @intFromEnum(self.store_op),
            .resolve_texture = self.resolve_texture.ptr,
            .resolve_mip_level = self.resolve_mip_level,
            .resolve_layer = self.resolve_layer,
            .cycle = self.cycle,
            .cycle_resolve_texture = self.cycle_resolve_texture,
        };
    }
};

pub const DepthStencilTargetInfo = struct {
    texture: GPUTexture = .invalid,
    clear_depth: f32 = 0,
    load_op: LoadOp = .default,
    store_op: StoreOp = .default,
    stencil_load_op: LoadOp = .default,
    stencil_store_op: StoreOp = .default,
    cycle: bool = false,
    clear_stencil: u8 = 0,

    pub fn toSDL(self: *const @This()) c.SDL_GPUDepthStencilTargetInfo {
        return .{
            .texture = self.texture.ptr,
            .clear_depth = self.clear_depth,
            .load_op = @intFromEnum(self.load_op),
            .store_op = @intFromEnum(self.store_op),
            .stencil_load_op = @intFromEnum(self.stencil_load_op),
            .stencil_store_op = @intFromEnum(self.stencil_store_op),
            .cycle = self.cycle,
            .clear_stencil = self.clear_stencil,
        };
    }
};

pub const TextureSamplerBinding = struct {
    texture: GPUTexture = .invalid,
    sampler: GPUSampler = .invalid,

    pub fn toSDL(self: *const @This()) c.SDL_GPUTextureSamplerBinding {
        return .{
            .texture = self.texture.ptr,
            .sampler = self.sampler.ptr,
        };
    }
};
