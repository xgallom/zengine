cbuffer UniformBuffer : register(b0, space3) {
    float3 mtl_clr_ambient  : packoffset(c0) ;
    float3 mtl_clr_diffuse  : packoffset(c1);
    float3 mtl_clr_specular : packoffset(c2);
    float3 mtl_clr_emissive : packoffset(c3);
    float3 mtl_clr_filter   : packoffset(c4);
    float mtl_specular_exp  : packoffset(c5.x);
    float mtl_ior           : packoffset(c5.y);
    float mtl_alpha         : packoffset(c5.z);
    float3 camera_pos       : packoffset(c6);
};

struct Input {
    float2 tex_coord : TEXCOORD0;
    float3 normal    : TEXCOORD1;
    float3 world_pos : TEXCOORD2;
};

float4 main(Input input) : SV_Target0
{
    return float4(mtl_clr_ambient, 1);
}
