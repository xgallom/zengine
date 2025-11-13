#ifndef _LIGHT_HLSL_
#define _LIGHT_HLSL_

#include <zengine.hlsl>
#include <shading.hlsl>

#ifndef LGH_REG_CBUF_OFFSET
#error "LGH_REG_CBUF_OFFSET must be defined"
#endif
#ifndef LGH_REG_SB_OFFSET
#error "LGH_REG_SB_OFFSET muse be defined"
#endif

#define LGH_REG_CBUF_LEN 1
#define LGH_REG_SB_LEN 1

#define LGH_MIN_DIST_SQR  0.01
#define LGH_MIN_INTENSITY 0.01

float lightDistanceFalloff(in float3 light_ray, in float light_pwr) {
    const float light_dist_sqr = dot(light_ray, light_ray);
    const float light_dist = sqrt(light_dist_sqr);

    const float light_dist_falloff = light_pwr / (LGH_MIN_DIST_SQR + light_dist_sqr);
    const float light_max_radius = sqrt(light_pwr / LGH_MIN_INTENSITY - LGH_MIN_DIST_SQR);
    return max(0, light_dist_falloff - light_dist / light_max_radius * LGH_MIN_INTENSITY);
}

struct LightAmbient {
    float3 clr;
    float int_ambient;
};

struct LightDirectional {
    float3 dir;
    float3 clr;
    float int_diffuse;
    float int_specular;
};

struct LightPoint {
    float3 pos;
    float3 dir;
    float3 clr;
    float int_diffuse;
    float int_specular;
};

struct Light {
    float3 ambient;
    float3 diffuse;
    float3 specular;
};

cbuffer LightsBufferMeta : register(b2, space3) {
    uint lgh_cnt_ambient;
    uint lgh_cnt_directional;
    uint lgh_cnt_point;
}

StructuredBuffer<float4> LightsBuffer  : register(t3, space2);
static uint lgh_idx = 0;

LightAmbient lightAmbient() {
    LightAmbient output;
    const float4 light_clr = LightsBuffer.Load(lgh_idx++);

    output.clr = light_clr.xyz;
    output.int_ambient = light_clr.w;
    return output;
}

LightDirectional lightDirectional(in float3 world_pos, in float3 normal, in float3 camera_dir, in float specular_exp) {
    LightDirectional output;

    const float3 light_ray = LightsBuffer.Load(lgh_idx++).xyz;
    const float4 light_clr = LightsBuffer.Load(lgh_idx++);
    const float3 light_dir = normalize(light_ray);

    const Highlights highlights = shadingBlinnPhong(normal, light_dir, camera_dir, specular_exp);
    const float light_int = light_clr.w;

    output.dir = light_dir;
    output.clr = light_clr.rgb;
    output.int_diffuse = light_int * highlights.diffuse_falloff;
    output.int_specular = light_int * highlights.specular_falloff;
    return output;
}

LightPoint lightPoint(in float3 world_pos, in float3 normal, in float3 camera_dir, in float specular_exp) {
    LightPoint output;

    const float3 light_pos = LightsBuffer.Load(lgh_idx++).xyz;
    const float4 light_clr = LightsBuffer.Load(lgh_idx++);
    const float3 light_ray = light_pos - world_pos;
    const float3 light_dir = normalize(light_ray);

    const Highlights highlights = shadingBlinnPhong(normal, light_dir, camera_dir, specular_exp);
    const float light_int = lightDistanceFalloff(light_ray, light_clr.w);

    output.pos = light_pos;
    output.dir = light_dir;
    output.clr = light_clr.rgb;
    output.int_diffuse = light_int * highlights.diffuse_falloff;
    output.int_specular = light_int * highlights.specular_falloff;
    return output;
}

Light processLights(in float3 world_pos, in float3 normal, in float3 camera_dir, in float specular_exp) {
    Light output;
    float3 ambient_light = float3(0, 0, 0);
    float3 diffuse_light = float3(0, 0, 0);
    float3 specular_light = float3(0, 0, 0);

    for (uint n = 0; n < lgh_cnt_ambient; ++n) {
        const LightAmbient light = lightAmbient();
        ambient_light += light.int_ambient * light.clr;
    }

    for (uint n = 0; n < lgh_cnt_directional; ++n) {
        const LightDirectional light = lightDirectional(world_pos, normal, camera_dir, specular_exp);
        diffuse_light += light.int_diffuse * light.clr;
        specular_light += light.int_specular * light.clr;
    }

    for (uint n = 0; n < lgh_cnt_point; ++n) {
        const LightPoint light = lightPoint(world_pos, normal, camera_dir, specular_exp);
        diffuse_light += light.int_diffuse * light.clr;
        specular_light += light.int_specular * light.clr;
    }

    output.ambient = ambient_light;
    output.diffuse = diffuse_light;
    output.specular = specular_light;
    return output;
}

#endif
