cbuffer UniformBuffer : register(b0, space1)
{
    float4x4 TransformViewProjection;
    float4x4 TransformModel;
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

    const float4x4 Transform = mul(TransformModel, TransformViewProjection);

    output.TexCoord = Coords;
    output.Position = mul(float4(Coords, 1.0), Transform);

    return output;
}
