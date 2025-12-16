#include <zengine.hlsl>

Texture2D<float4> SrcBuffer : register(t0, space2);
SamplerState SrcSampler  : register(s0, space2);

float4 main(float2 screen_pos : TEXCOORD) : SV_Target {
    const float2 uv = screen_pos * 0.5f + 0.5f; 
    return SrcBuffer.Sample(SrcSampler, uv);
}
