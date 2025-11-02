#ifndef _SHADING_HLSL_
#define _SHADING_HLSL_

#include <zengine.hlsl>

inline float3 cameraDir(in float3 world_pos, in float3 camera_pos) {
    return normalize(camera_pos - world_pos);
}

inline float3 cameraRefl(in float3 normal, in float3 camera_dir) {
    return reflect(-camera_dir, normal);
}

struct Highlights {
    float diffuse_falloff;
    float specular_falloff;
};

Highlights shadingBlinn(in float3 normal, in float3 light_dir, in float3 camera_refl, in float specular_exp) {
    Highlights output;

    const float diffuse_falloff = max(0, dot(light_dir, normal));
    const float specular_falloff = pow( max(0, dot(light_dir, camera_refl)), specular_exp );

    output.diffuse_falloff = diffuse_falloff;
    output.specular_falloff = specular_falloff;
    return output;
}

Highlights shadingBlinnPhong(in float3 normal, in float3 light_dir, in float3 camera_dir, in float specular_exp) {
    Highlights output;

    const float diffuse_falloff = max(0, dot(light_dir, normal));
    float specular_falloff = 0;
    [flatten] if (diffuse_falloff >= 0) {
        const float3 half_dir = normalize(light_dir + camera_dir);
        specular_falloff = pow( max(0, dot(normal, half_dir)), specular_exp );
    }

    output.diffuse_falloff = diffuse_falloff;
    output.specular_falloff = specular_falloff;
    return output;
}

#endif
