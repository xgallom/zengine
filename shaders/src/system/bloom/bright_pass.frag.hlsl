#include <zengine.hlsl>
#include <bloom.hlsl>

#define COLOR_WEIGHTS float3(0.299, 0.587, 0.114)

Texture2D<float4> ScreenBuffer : register(t0, space2);
SamplerState ScreenSampler  : register(s0, space2);

float4 main(float2 screen_pos : TEXCOORD) : SV_Target {
    const float2 uv = screen_pos * 0.5f + 0.5f; 
    const float3 src = ScreenBuffer.Sample(ScreenSampler, uv).rgb;
    
    return float4(clamp(src, 0, 2), 1);
    const float3 a = ScreenBuffer.Sample(ScreenSampler, uv + float2(-1, -1) * blm_texel_size).rgb;
    const float3 b = ScreenBuffer.Sample(ScreenSampler, uv + float2(1, -1) * blm_texel_size).rgb;
    const float3 c = ScreenBuffer.Sample(ScreenSampler, uv + float2(-1, 1) * blm_texel_size).rgb;
    const float3 d = ScreenBuffer.Sample(ScreenSampler, uv + float2(1, 1) * blm_texel_size).rgb;
    const float3 m = (a + b + c + d) * 0.25;

    const float wa = 1 / (1 + dot(a, COLOR_WEIGHTS));
    const float wb = 1 / (1 + dot(b, COLOR_WEIGHTS));
    const float wc = 1 / (1 + dot(c, COLOR_WEIGHTS));
    const float wd = 1 / (1 + dot(d, COLOR_WEIGHTS));
    const float3 filt = (a * wa + b * wb + c * wc + d * wd) / (wa + wb + wc + wd);
    
    const float br = max(filt.r, max(filt.g, filt.b));
    float soft = br - blm_thresh + 0.5;
    soft = saturate(soft);
    soft = soft * soft * (3 - 2 * soft);
    const float cont = max(soft, br - blm_thresh) / max(br, 0.00001);

    return float4(filt * cont, 1);
}
