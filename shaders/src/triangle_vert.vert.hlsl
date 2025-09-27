cbuffer UniformBuffer : register(b0, space1) {
    float4x4 tr_view_projection;
    float4x4 tr_model;
};

struct Input {
    float3 position  : POSITION;
    float3 tex_coord : TEXCOORD0;
    float3 normal    : NORMAL;
};

struct Output {
    float4 position  : SV_Position;
    float2 tex_coord : TEXCOORD0;
    float3 normal    : TEXCOORD1;
    float3 world_pos : TEXCOORD2;
};

Output main(Input input)
{
    Output output;

    const float4 position = mul(float4(input.position, 1), tr_model);
    const float4 normal = mul(float4(input.normal, 0), tr_model);

    output.position = mul(position, tr_view_projection);
    output.tex_coord = input.tex_coord.xy;
    output.normal = normal.xyz;
    output.world_pos = position.xyz;

    return output;
}
