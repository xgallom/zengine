#ifndef _SHADING_HLSL_
#define _SHADING_HLSL_

#include <zengine.hlsl>

inline float3 cameraDir(float3 world_pos, float3 camera_pos) {
    return normalize(camera_pos - world_pos);
}

inline float3 cameraRefl(float3 normal, float3 camera_dir) {
    return reflect(-camera_dir, normal);
}

struct Highlights {
    float diffuse_falloff;
    float specular_falloff;
};

Highlights shadingBlinn(float3 normal, float3 light_dir, float3 camera_refl, float specular_exp) {
    Highlights output;

    const float diffuse_falloff = max(0, dot(light_dir, normal));
    const float specular_falloff = pow( max(0, dot(light_dir, camera_refl)), specular_exp );

    output.diffuse_falloff = diffuse_falloff;
    output.specular_falloff = specular_falloff;
    return output;
}

Highlights shadingBlinnPhong(float3 normal, float3 light_dir, float3 camera_dir, float specular_exp) {
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

float visG1(float nv, float k) {
    return 1 / (nv * (1 - k) + k);
}

Highlights shadingGGX(float3 normal, float3 light_dir, float3 camera_dir, float roughness, float fres_0) {
    Highlights output;

    const float diffuse_falloff = max(0, dot(light_dir, normal));
    const float alpha = roughness * roughness;
    const float3 half_dir = normalize(light_dir + camera_dir);
    const float nl = saturate(dot(normal, light_dir));
    const float nv = saturate(dot(normal, camera_dir));
    const float nh = saturate(dot(normal, half_dir));
    const float lh = saturate(dot(light_dir, half_dir));

    const float alpha_sqr = alpha * alpha;
    const float denom = nh * nh * (alpha_sqr - 1) + 1;
    const float ggx = alpha_sqr / (PI * denom * denom);

    const float fres = fres_0 + (1 - fres_0) * pow(1 - lh, 5);

    const float k = alpha / 2;
    const float vis = visG1(nl, k) * visG1(nv, k);

    const float specular_falloff = nl * ggx * fres * vis;
    output.diffuse_falloff = diffuse_falloff;
    output.specular_falloff = specular_falloff;
    return output;
}

#endif
