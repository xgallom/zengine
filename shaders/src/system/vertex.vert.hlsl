#include <zengine.hlsl>

cbuffer UniformBuffer : register(b0, space1) {
    float4x4 tr_view_projection;
    float4x4 tr_model;
};

struct VertexInput {
    float3 position  : POSITION;
    float3 tex_coord : TEXCOORD;
    float3 normal    : NORMAL;
    float3 tangent   : TANGENT;
    float3 binormal  : BINORMAL;
};

struct VertexOutput {
    float4 position  : SV_Position;
    float3 world_pos : POSITION1;
    float2 tex_coord : TEXCOORD1;
    float3 normal    : NORMAL1;
    float3 tangent   : TANGENT1;
    float3 binormal  : BINORMAL1;
};

VertexOutput main(VertexInput input)
{
    VertexOutput output;

    const float4 position = mul(float4(input.position, 1), tr_model);
    const float4 normal = mul(float4(input.normal, 0), tr_model);
    const float4 tangent = mul(float4(input.tangent, 0), tr_model);
    const float4 binormal = mul(float4(input.binormal, 0), tr_model);

    output.position = mul(position, tr_view_projection);
    output.world_pos = position.xyz;
    output.tex_coord = input.tex_coord.xy;
    output.normal = normal.xyz;
    output.tangent = tangent.xyz;
    output.binormal = binormal.xyz;

    return output;
}
