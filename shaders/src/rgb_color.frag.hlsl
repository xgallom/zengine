cbuffer FragUniformBuffer : register(b0, space3)
{
    float4 color;
};

float4 main(float3 tex_coord : TEXCOORD0) : SV_Target0
{
    return color;
}
