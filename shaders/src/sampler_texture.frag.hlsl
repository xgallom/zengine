#include <zeng.hlsl>

#define MTL_HAS_TEXTURE     (1 << 0)
#define MTL_HAS_DIFFUSE_MAP (1 << 1)
#define MTL_HAS_BUMP_MAP    (1 << 2)
#define MTL_HAS_FILTER      (1 << 3)

cbuffer Material : register(b0, space3) {
    float3 mtl_clr_ambient;
    float3 mtl_clr_diffuse;
    float3 mtl_clr_specular;
    float3 mtl_clr_emissive;
    float3 mtl_clr_filter;
    float _padding0;

    float mtl_specular_exp;
    float mtl_ior;
    float mtl_alpha;
    uint  mtl_config;

    float3 camera_pos;
};

cbuffer LightsBufferMeta : register(b1, space3) {
    uint  lgh_cnt_ambient;
    uint lgh_cnt_directional;
    uint lgh_cnt_point;
}

struct LightAmbient {
    float3 clr;
    float pwr;
};

struct LightDirectional {
    float3 dir;
    float3 clr;
    float pwr_diffuse;
    float pwr_specular;
};

struct LightPoint {
    float3 pos;
    float3 dir;
    float3 clr;
    float pwr_diffuse;
    float pwr_specular;
};

struct Input {
    float2 tex_coord : TEXCOORD0;
    float3 normal    : TEXCOORD2;
    float3 world_pos : TEXCOORD3;
};

Texture2D<float4> TextureMap : register(t0, space2);
SamplerState SamplerTexture  : register(s0, space2);

Texture2D<float4> DiffuseMap : register(t1, space2);
SamplerState SamplerDiffuse  : register(s1, space2);

Texture2D<float4> BumpMap    : register(t2, space2);
SamplerState SamplerBump     : register(s2, space2);

StructuredBuffer<float4> LightsBuffer  : register(t3, space2);
static uint lgh_idx = 0;

float3 bumpMap(in float3 normal, in float2 tex_coord, in float3 world_pos);
LightAmbient lightAmbient();
LightDirectional lightDirectional(in float3 normal, in float3 world_pos, in float3 camera_refl);
LightPoint lightPoint( in float3 normal, in float3 world_pos, in float3 camera_refl);

float4 main(Input input) : SV_Target0 {
    const float2 tex_uv = textureUV(input.tex_coord);
    const float3 world_pos = input.world_pos;
    const float3 normal = bumpMap(input.normal, tex_uv, world_pos);
    const float3 camera_dir = normalize(camera_pos - world_pos);
    const float3 camera_refl = reflect(-camera_dir, normal);

    float3 ambient_light = float3(0, 0, 0);
    float3 diffuse_light = float3(0, 0, 0);
    float3 specular_light = float3(0, 0, 0);

    for (uint n = 0; n < lgh_cnt_ambient; ++n) {
        const LightAmbient light = lightAmbient();
        ambient_light += light.clr * light.pwr;
    }

    for (uint n = 0; n < lgh_cnt_directional; ++n) {
        const LightDirectional light = lightDirectional(normal, world_pos, camera_refl);
        diffuse_light += light.pwr_diffuse * light.clr;
        specular_light += light.pwr_specular * light.clr;
    }

    for (uint n = 0; n < lgh_cnt_point; ++n) {
        const LightPoint light = lightPoint(normal, world_pos, camera_refl);
        diffuse_light += light.pwr_diffuse * light.clr;
        specular_light += light.pwr_specular * light.clr;
    }

    float3 ambient_tex = float3(1, 1, 1);
    float3 diffuse_tex = float3(1, 1, 1);
    [branch] if (mtl_config & MTL_HAS_TEXTURE) ambient_tex = TextureMap.Sample(SamplerTexture, tex_uv).xyz;
    [branch] if (mtl_config & MTL_HAS_DIFFUSE_MAP) diffuse_tex = DiffuseMap.Sample(SamplerDiffuse, tex_uv).xyz;

    const float3 ambient = ambient_light * mtl_clr_ambient * ambient_tex;
    const float3 diffuse = diffuse_light * mtl_clr_diffuse * diffuse_tex;
    const float3 specular = specular_light * mtl_clr_specular;
    const float3 emissive = mtl_clr_emissive;

    float3 color = ambient + diffuse + specular + emissive;
    [branch] if (mtl_config & MTL_HAS_FILTER) color *= mtl_clr_filter;
    return float4(color, mtl_alpha);
}

float3 bumpMap(
    in float3 normal, 
    in float2 tex_coord, 
    in float3 world_pos
) {
    const float3 vn = normalize(normal);
    [branch] if (!(mtl_config & MTL_HAS_BUMP_MAP)) return vn;

    const float2 tex_uv = tex_coord;
    const float3 wp = world_pos;

    const float3 dx_wp = ddx(wp);
    const float3 dy_wp = ddy(wp);
    const float3 r1 = cross(dy_wp, vn);
    const float3 r2 = cross(vn, dx_wp);
    const float det = dot(dx_wp, r1);
    const float h_0 = BumpMap.Sample(SamplerBump, tex_uv).x;
    const float h_dx = BumpMap.Sample(SamplerBump, tex_uv + ddx(tex_uv)).x;
    const float h_dy = BumpMap.Sample(SamplerBump, tex_uv + ddy(tex_uv)).x;

    const float3 surf_grad = sign(det) * ( (h_dx - h_0) * r1 + (h_dy - h_0) * r2 );
    const float bump_amt = 0.7;

    return vn * (1 - bump_amt) + bump_amt * normalize( abs(det) * vn - surf_grad );
}

LightAmbient lightAmbient() {
    LightAmbient output;
    const float4 light_clr = LightsBuffer.Load(lgh_idx++);

    output.clr = light_clr.xyz;
    output.pwr = light_clr.w;
    return output;
}

LightDirectional lightDirectional(in float3 normal, in float3 world_pos, in float3 camera_refl) {
    LightDirectional output;
    const float3 light_ray = LightsBuffer.Load(lgh_idx++).xyz;
    const float4 light_clr = LightsBuffer.Load(lgh_idx++);
    const float3 light_dir = normalize(light_ray);
    const float diffuse_falloff = max(0, dot(light_dir, normal));
    const float specular_falloff = pow( max(0, dot(light_dir, camera_refl)), mtl_specular_exp );

    output.dir = light_dir;
    output.clr = light_clr.xyz;
    output.pwr_diffuse = light_clr.w * diffuse_falloff;
    output.pwr_specular = light_clr.w * specular_falloff;
    return output;
}

LightPoint lightPoint(in float3 normal, in float3 world_pos, in float3 camera_refl) {
    LightPoint output;
    const float3 light_pos = LightsBuffer.Load(lgh_idx++).xyz;
    const float4 light_clr = LightsBuffer.Load(lgh_idx++);
    const float3 light_ray = light_pos - world_pos;
    const float3 light_dir = normalize(light_ray);
    const float diffuse_falloff = max(0, dot(light_dir, normal));
    const float specular_falloff = pow( max(0, dot(light_dir, camera_refl)), mtl_specular_exp );
    const float light_dist_sqr = dot(light_ray, light_ray);
    const float light_dist = sqrt(light_dist_sqr);
    //const float dist_falloff = max(0, 1 / (0.01 + light_dist_sqr) - light_dist / 1e9);
    const float dist_falloff = max(0, 1 / (0.01 + light_dist_sqr));

    output.pos = light_pos;
    output.dir = light_dir;
    output.clr = light_clr.xyz;
    output.pwr_diffuse = light_clr.w * diffuse_falloff * dist_falloff;
    output.pwr_specular = light_clr.w * specular_falloff * dist_falloff;
    return output;
}
