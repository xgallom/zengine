const std = @import("std");
const simd = std.simd;
const gpu = std.gpu;

const Vec3 = @Vector(3, f32);

const UBO = extern struct {
    time: f32,
};

extern const ubo: UBO addrspace(.uniform);
extern var tex_coord: @Vector(3, f32) addrspace(.input);
extern var frag_color: @Vector(4, f32) addrspace(.output);

export fn main() callconv(.spirv_fragment) void {
    gpu.binding(&ubo, 3, 0);
    gpu.location(&tex_coord, 0);
    gpu.location(&frag_color, 0);

    const positive = @abs(tex_coord);
    const rotated = simd.rotateElementsLeft(positive, 1) * simd.rotateElementsLeft(positive, 2);
    const mapped = positive / splat3(getMax(positive));
    const inv_mapped = rotated / splat3(getMax(positive));

    var distance = @abs(length(mapped) + @abs(fmod(ubo.time, 2) - 1) - 2);
    distance = step(0.1, distance);
    const inv_distance = 1 - distance;

    const result = (mapped * splat3(distance) + inv_mapped * splat3(inv_distance)) / splat3(getMax(mapped) * distance + getMax(inv_mapped) * inv_distance);
    frag_color[0] = result[0];
    frag_color[1] = result[1];
    frag_color[2] = result[2];
    frag_color[3] = 1;
}

fn getMax(v: Vec3) f32 {
    return @max(v[0], v[1], v[2]);
}

fn length(v: Vec3) f32 {
    return sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
}

fn sqrt(x: f32) f32 {
    var z: f32 = 1;
    for (1..11) |_| z -= (z * z - x) / 2 * z;
    return z;
}

fn fmod(x: f32, y: f32) f32 {
    return x - y * @trunc(x / y);
}

fn step(t: f32, x: f32) f32 {
    return if (x >= t) 1 else 0;
}

fn splat3(v: anytype) Vec3 {
    return @splat(v);
}
