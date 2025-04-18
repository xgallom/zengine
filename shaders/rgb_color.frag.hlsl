cbuffer FragUniformBuffer : register(b0, space1)
{
    float4 Color;
};

float4 main(float3 TexCoord : TEXCOORD0) : SV_Target0
{
    return Color;
}
