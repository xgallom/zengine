//!
//! The zengine material information
//! TODO: Implement materials
//!

const std = @import("std");

const math = @import("../math.zig");
const ui = @import("../ui.zig");

const log = std.log.scoped(.gfx_material_info);

name: [:0]const u8 = "",
texture: ?[:0]const u8 = null,
diffuse_map: ?[:0]const u8 = null,
bump_map: ?[:0]const u8 = null,

clr_ambient: math.RGBf32 = math.rgb_f32.one,
clr_diffuse: math.RGBf32 = math.rgb_f32.one,
clr_specular: math.RGBf32 = math.rgb_f32.zero,
clr_emissive: math.RGBf32 = math.rgb_f32.zero,
clr_filter: math.RGBf32 = math.rgb_f32.one,
specular_exp: f32 = 1,
ior: f32 = 1,
alpha: f32 = 1,
mode: u8 = 0,

const Self = @This();

pub const clr_ambient_min = 0;
pub const clr_ambient_max = 1;
pub const clr_ambient_speed = 0.01;
pub const clr_diffuse_min = 0;
pub const clr_diffuse_max = 1;
pub const clr_diffuse_speed = 0.01;
pub const clr_specular_min = 0;
pub const clr_specular_max = 1;
pub const clr_specular_speed = 0.01;
pub const clr_emissive_min = 0;
pub const clr_emissive_max = 1;
pub const clr_emissive_speed = 0.01;
pub const clr_filter_min = 0;
pub const clr_filter_max = 1;
pub const clr_filter_speed = 0.01;
pub const specular_exp_min = 0.1;
pub const specular_exp_speed = 0.1;
pub const alpha_min = 0;
pub const alpha_max = 1;
pub const alpha_speed = 0.05;

pub fn config(self: *const Self) u32 {
    var result: std.bit_set.IntegerBitSet(32) = .initEmpty();
    if (self.texture != null) result.set(0);
    if (self.diffuse_map != null) result.set(1);
    if (self.bump_map != null) result.set(2);
    result.set(3);
    // if (!math.rgbf32.eqlExact(&self.clr_filter, &math.rgbf32.zero)) result.set(3);
    return result.mask;
}

pub fn uniformBuffer(self: *const Self) [24]f32 {
    var result: [24]f32 = undefined;
    @memcpy(result[0..3], self.clr_ambient[0..]);
    @memcpy(result[4..7], self.clr_diffuse[0..]);
    @memcpy(result[8..11], self.clr_specular[0..]);
    @memcpy(result[12..15], self.clr_emissive[0..]);
    @memcpy(result[16..19], self.clr_filter[0..]);
    result[20] = self.specular_exp;
    result[21] = self.ior;
    result[22] = self.alpha;
    const ptr_config: *u32 = @ptrCast(&result[23]);
    ptr_config.* = self.config();
    return result;
}

pub fn propertyEditor(self: *Self) ui.UI.Element {
    return ui.PropertyEditor(Self).init(self).element();
}
