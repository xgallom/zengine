#include <zengine.hlsl>
#include <bloom.hlsl>

Texture2D<float4> ScreenBuffer : register(t0, space2);
SamplerState ScreenSampler  : register(s0, space2);

Texture2D<float4> BloomBuffer : register(t1, space2);
SamplerState BloomSampler  : register(s1, space2);

float4 main(float2 screen_pos : TEXCOORD) : SV_Target {
    const float2 uv = screen_pos * 0.5f + 0.5f; 
    const float3 src = ScreenBuffer.Sample(ScreenSampler, uv).rgb;
    const float3 blm = BloomBuffer.Sample(BloomSampler, uv).rgb;
    return float4(lerp(src, blm, blm_int), 1);
}
