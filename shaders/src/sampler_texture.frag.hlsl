#include <zeng.hlsl>

#define MTL_HAS_TEXTURE     (1 << 0)
#define MTL_HAS_DIFFUSE_MAP (1 << 1)
#define MTL_HAS_BUMP_MAP    (1 << 2)
#define MTL_HAS_FILTER      (1 << 3)

cbuffer UniformBuffer : register(b0, space3) {
    float3 mtl_clr_ambient  : packoffset(c0) ;
    float3 mtl_clr_diffuse  : packoffset(c1);
    float3 mtl_clr_specular : packoffset(c2);
    float3 mtl_clr_emissive : packoffset(c3);
    float3 mtl_clr_filter   : packoffset(c4);
    float mtl_specular_exp  : packoffset(c5.x);
    float mtl_ior           : packoffset(c5.y);
    float mtl_alpha         : packoffset(c5.z);
    uint32_t mtl_config     : packoffset(c5.w);
    float3 camera_pos       : packoffset(c6);
};

struct Input {
    float2 tex_coord : TEXCOORD0;
    float3 normal    : TEXCOORD1;
    float3 world_pos : TEXCOORD2;
};

Texture2D<float4> TextureMap : register(t0, space2);
SamplerState SamplerTexture  : register(s0, space2);

Texture2D<float4> DiffuseMap : register(t1, space2);
SamplerState SamplerDiffuse  : register(s1, space2);

Texture2D<float4> BumpMap    : register(t2, space2);
SamplerState SamplerBump     : register(s2, space2);

float3 bumpMap(Input input);

float4 main(Input input) : SV_Target0 
{
    const float2 tex_uv = textureUV(input.tex_coord);
    const float3 normal = bumpMap(input);
    const float3 world_pos = input.world_pos;

    const float3 ambient_light_clr = float3(1, 1, 1);
    const float ambient_light_pwr = 0.1;
    const float3 ambient_light = ambient_light_clr * ambient_light_pwr;

    const float3 diffuse_light_clr = float3(1, 1, 1);
    const float diffuse_light_pwr = 1;
    const float3 diffuse_light = diffuse_light_clr * diffuse_light_pwr;

    const float3 light_pos = float3(10, 8, 4) * 15;

    const float3 light_dir = normalize(light_pos - world_pos);
    const float3 camera_dir = normalize(camera_pos - world_pos);
    const float3 camera_refl = reflect(-camera_dir, normal);

    const float diffuse_falloff = max(0, dot(light_dir, normal));
    const float specular_falloff = pow( max(0, dot(light_dir, camera_refl)), mtl_specular_exp );

    float3 ambient_tex = float3(1, 1, 1);
    float3 diffuse_tex = float3(1, 1, 1);
    if (mtl_config & MTL_HAS_TEXTURE) ambient_tex = TextureMap.Sample(SamplerTexture, tex_uv).xyz;
    if (mtl_config & MTL_HAS_DIFFUSE_MAP) diffuse_tex = DiffuseMap.Sample(SamplerDiffuse, tex_uv).xyz;

    const float3 ambient_clr = ambient_light * mtl_clr_ambient * ambient_tex;
    const float3 diffuse_clr = diffuse_light * mtl_clr_diffuse * diffuse_tex;
    const float3 specular_clr = diffuse_light * mtl_clr_specular;
    const float3 emissive_clr = mtl_clr_emissive;

    const float3 ambient = ambient_clr;
    const float3 diffuse = diffuse_falloff * diffuse_clr;
    const float3 specular = specular_falloff * specular_clr;
    const float3 emissive = emissive_clr;

    float3 color = ambient + diffuse + specular + emissive;
    if (mtl_config & MTL_HAS_FILTER) color *= mtl_clr_filter;
    return float4(color, mtl_alpha);
}

float3 bumpMap(Input input)
{
    const float3 vn = normalize(input.normal);
    if (!(mtl_config & MTL_HAS_BUMP_MAP)) return vn;

    const float2 tex_uv = textureUV(input.tex_coord);
    const float3 wp = input.world_pos;

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
