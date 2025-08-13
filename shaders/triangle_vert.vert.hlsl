cbuffer UniformBuffer : register(b0, space1)
{
    float4x4 transform_view_projection;
    float4x4 transform_model;
};

struct Input
{
    float3 position : POSITION;
    float3 normal : NORMAL;
};

struct Output
{
    float3 tex_coord : TEXCOORD0;
    float4 position : SV_Position;
};

Output main(Input input)
{
    Output output;

    const float4 position = mul(float4(input.position, 1.0), transform_model);

    output.tex_coord = input.position;
    output.position = mul(position, transform_view_projection);

    return output;
}
