cbuffer UniformBuffer : register(b0, space3) {
    float3 color;
};

float4 main() : SV_Target
{
    return float4(color, 1);
}
