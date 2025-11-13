cbuffer UniformBuffer : register(b0, space3) {
    float4 color;
};

float4 main(float3 world_pos : POSITION) : SV_Target
{
    return color;
}
