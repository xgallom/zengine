cbuffer UniformBuffer : register(b0, space1)
{
    float4x4 transform_view_projection;
    float4x4 transform_model;
};

struct Input {
    uint vertex_index : SV_VertexID;
};

struct Output {
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

Output main(Input input) {
    Output output;

    const float2 verts[] = {
        float2(0, 0),
        float2(0, 1),
        float2(1, 1),
        float2(0, 0),
        float2(1, 1),
        float2(1, 0),
    };

    output.uv = verts[input.vertex_index];
    output.position = float4(verts[input.vertex_index] * 2 - 1, 0, 1);

    return output;
}
