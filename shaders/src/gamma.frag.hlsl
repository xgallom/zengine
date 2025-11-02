#include <zengine.hlsl>

cbuffer FragUniformBuffer : register(b0, space3) {
    float gamma;
};

Texture2D<float4> ScreenBuffer : register(t0, space2);
SamplerState ScreenSampler  : register(s0, space2);

float4 main(float2 screen_pos : TEXCOORD) : SV_Target {
    const float2 uv = screen_pos * 0.5f + 0.5f; 
    const float3 px = ScreenBuffer.Sample(ScreenSampler, uv).rgb;
    const float3 color = max(0, pow(px, gamma));
    return float4(color, 1);
}
