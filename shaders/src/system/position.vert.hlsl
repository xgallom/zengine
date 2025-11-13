#include <zengine.hlsl>

cbuffer UniformBuffer : register(b0, space1) {
    float4x4 tr_view_projection;
    float4x4 tr_model;
};

struct VertexInput {
    float3 position  : POSITION;
};

struct VertexOutput {
    float4 position  : SV_Position;
    float3 world_pos : POSITION1;
};

VertexOutput main(VertexInput input)
{
    VertexOutput output;
    const float4 position = mul(float4(input.position, 1), tr_model);

    output.position = mul(position, tr_view_projection);
    output.world_pos = position.xyz;
    return output;
}
