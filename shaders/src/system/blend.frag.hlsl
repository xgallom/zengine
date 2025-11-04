#include <zengine.hlsl>

Texture2D<float4> ScreenBuffer : register(t0, space2);
SamplerState ScreenSampler  : register(s0, space2);

float4 main(float2 screen_pos : TEXCOORD) : SV_Target {
    const float2 uv = screen_pos * 0.5f + 0.5f; 
    const float4 px = ScreenBuffer.Sample(ScreenSampler, uv);
    return px;
}
