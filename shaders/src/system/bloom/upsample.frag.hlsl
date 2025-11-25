#include <zengine.hlsl>
#include <bloom.hlsl>

Texture2D<float4> ScreenBuffer : register(t0, space2);
SamplerState ScreenSampler  : register(s0, space2);

float4 main(float2 screen_pos : TEXCOORD) : SV_Target {
    const float2 uv = screen_pos * 0.5f + 0.5f; 
    const float3 src = ScreenBuffer.Sample(ScreenSampler, uv).rgb;

    float3 clr = src * 4;
    clr += ScreenBuffer.Sample(ScreenSampler, uv + float2(-1, -1) * blm_texel_size).rgb;
    clr += ScreenBuffer.Sample(ScreenSampler, uv + float2(0, -1) * blm_texel_size).rgb * 2;
    clr += ScreenBuffer.Sample(ScreenSampler, uv + float2(1, -1) * blm_texel_size).rgb;

    clr += ScreenBuffer.Sample(ScreenSampler, uv + float2(-1, 0) * blm_texel_size).rgb * 2;
    clr += src * 4;
    clr += ScreenBuffer.Sample(ScreenSampler, uv + float2(1, 0) * blm_texel_size).rgb * 2;

    clr += ScreenBuffer.Sample(ScreenSampler, uv + float2(-1, 1) * blm_texel_size).rgb;
    clr += ScreenBuffer.Sample(ScreenSampler, uv + float2(0, 1) * blm_texel_size).rgb * 2;
    clr += ScreenBuffer.Sample(ScreenSampler, uv + float2(1, 1) * blm_texel_size).rgb;
    return float4(clr / 16, 1);
}
