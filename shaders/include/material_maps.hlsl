#ifndef _MATERIAL_MAPS_HLSL_
#define _MATERIAL_MAPS_HLSL_

Texture2D<float4> TextureMap : register(t0, space2);
SamplerState SamplerTexture  : register(s0, space2);

Texture2D<float4> DiffuseMap : register(t1, space2);
SamplerState SamplerDiffuse  : register(s1, space2);

Texture2D<float4> BumpMap    : register(t2, space2);
SamplerState SamplerBump     : register(s2, space2);

float3 bumpMap(in float3 world_pos, in float2 tex_uv, in float3 normal) {
    const float3 vn = normal;
    const float3 wp = world_pos;

    const float3 dx_wp = ddx(wp);
    const float3 dy_wp = ddy(wp);
    const float3 r1 = cross(dy_wp, vn);
    const float3 r2 = cross(vn, dx_wp);

    const float det = dot(dx_wp, r1);
    const float h_0 = BumpMap.Sample(SamplerBump, tex_uv).x * 2 - 1;
    const float h_dx = BumpMap.Sample(SamplerBump, tex_uv + ddx(tex_uv)).x * 2 - 1;
    const float h_dy = BumpMap.Sample(SamplerBump, tex_uv + ddy(tex_uv)).x * 2 - 1;

    const float3 surf_grad = sign(det) * ( (h_dx - h_0) * r1 + (h_dy - h_0) * r2 );
    const float bump_amt = 0.7;

    return vn * (1 - bump_amt) + bump_amt * normalize( abs(det) * vn - surf_grad );
}

float3 normalMap(in float2 tex_uv, in float3 normal, in float3 tangent, in float3 binormal) {
    const float4 normal_sample = BumpMap.Sample(SamplerBump, tex_uv);
    const float3 normal_offset = normalize(normal_sample.xyz * 2 - 1);
    const float3x3 tan_bin_norm = float3x3(
        normalize(tangent), 
        normalize(binormal),
        normalize(normal)
    );
    return normalize(mul(normal_offset, tan_bin_norm));
}
#endif
