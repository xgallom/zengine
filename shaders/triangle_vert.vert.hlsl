cbuffer UniformBuffer : register(b0, space1)
{
    float4x4 TransformMatrix;
    float Time;
};

struct SPIRV_Cross_Input
{
    float3 Coords : TEXCOORD0;
};

struct Output
{
    float3 TexCoord : TEXCOORD0;
    float4 Position : SV_Position;
};

Output main(float3 Coords : TEXCOORD0)
{
    Output output;

    output.TexCoord = Coords;
    output.Position = mul(TransformMatrix, float4(Coords, 1.0));

    return output;
}
