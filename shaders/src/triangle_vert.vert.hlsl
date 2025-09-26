cbuffer UniformBuffer : register(b0, space1) {
    float4x4 transform_view_projection;
    float4x4 transform_model;
};

struct Input {
    float3 position : POSITION;
    float3 tex_coord : TEXCOORD0;
    float3 normal : NORMAL;
};

struct Output {
    float4 position : SV_Position;
    float3 tex_coord : TEXCOORD0;
    float3 normal : NORMAL;
};

Output main(Input input)
{
    Output output;

    const float4 position = mul(float4(input.position, 1.0), transform_model);

    output.position = mul(position, transform_view_projection);
    output.normal = input.normal;
    output.tex_coord = input.tex_coord;

    return output;
}
