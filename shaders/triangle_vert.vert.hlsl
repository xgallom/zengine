cbuffer UniformBuffer : register(b0, space1)
{
    float4x4 transform_view_projection;
    float4x4 transform_model;
};

struct SPIRV_Cross_Input
{
    float3 coords : TEXCOORD0;
};

struct Output
{
    float3 tex_coord : TEXCOORD0;
    float4 position : SV_Position;
};

Output main(float3 coords : TEXCOORD0)
{
    Output output;

    const float4 position = mul(float4(coords, 1.0), transform_model);

    output.tex_coord = coords;
    output.position = mul(position, transform_view_projection);

    return output;
}
