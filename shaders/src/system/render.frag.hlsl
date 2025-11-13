#include <zengine.hlsl>

#define RENDER_CONFIG_HAS_AGX (1 << 0)
#define RENDER_CONFIG_HAS_LUT (1 << 1)

cbuffer FragUniformBuffer : register(b0, space3) {
    float exposure;
    float exposure_bias;
    float gamma;
    uint  config;
};

Texture2D<float4> ScreenBuffer : register(t0, space2);
SamplerState ScreenSampler  : register(s0, space2);

Texture3D<float4> LUTMap : register(t1, space2);
SamplerState LUTSampler  : register(s1, space2);
#define LUT_SIZE 33
#define LUT_SCALE (LUT_SIZE - 1) / LUT_SIZE
#define LUT_OFFSET 1 / (2 * LUT_SIZE)

float3 agxDefaultContrastApprox( float3 x );
float3 AgXToneMapping(float3 color);

float4 main(float2 screen_pos : TEXCOORD) : SV_Target {
    const float2 uv = screen_pos * 0.5f + 0.5f; 
    const float4 src = ScreenBuffer.Sample(ScreenSampler, uv);

    float3 ldr = src.rgb * exposure + exposure_bias;
    [branch] if (config & RENDER_CONFIG_HAS_AGX)
        ldr = AgXToneMapping(ldr);
    [branch] if (config & RENDER_CONFIG_HAS_LUT) {
        ldr = LUTMap.Sample(LUTSampler, ldr * LUT_SCALE + LUT_OFFSET).rgb;
        // const float3 black3 = LUTMap.Sample(LUTSampler, float1(LUT_OFFSET).xxx).rgb;
        // const float3 white3 = LUTMap.Sample(LUTSampler, float1(1 - LUT_OFFSET).xxx).rgb;
        // const float3 black = min(black3.r, min(black3.g, black3.b)).xxx;
        // const float3 white = min(white3.r, min(white3.g, white3.b)).xxx;
        // ldr = (ldr - black) / (white - black);
        // ldr = pow(max(0, ldr), 2.2);
    }

    const float3 color = saturate(pow(ldr, 1 / gamma));
    return float4(color, src.a);
}

// AgX Tone Mapping implementation based on Three.js, which in turn is based
// Filament, which in turn is based on Blender's implementation using rec 2020 primaries
// https://github.com/google/filament/pull/7236
// Inputs and outputs are encoded as Linear-sRGB.
float3 AgXToneMapping(float3 color) {
    const float3x3 LINEAR_REC2020_TO_LINEAR_SRGB = float3x3(
        float3( 1.6605, -0.1246, -0.0182 ),
        float3( -0.5876, 1.1329, - 0.1006 ),
        float3( -0.0728, -0.0083, 1.1187 )
    );

    const float3x3 LINEAR_SRGB_TO_LINEAR_REC2020 = float3x3(
        float3( 0.6274, 0.0691, 0.0164 ),
        float3( 0.3293, 0.9195, 0.0880 ),
        float3( 0.0433, 0.0113, 0.8956 )
    );

    const float3x3 AgXInsetMatrix = float3x3(
        float3( 0.856627153315983, 0.137318972929847, 0.11189821299995 ),
        float3( 0.0951212405381588, 0.761241990602591, 0.0767994186031903 ),
        float3( 0.0482516061458583, 0.101439036467562, 0.811302368396859 )
    );

    const float3x3 AgXOutsetMatrix = float3x3(
        float3( 1.1271005818144368, -0.1413297634984383, -0.14132976349843826 ),
        float3( -0.11060664309660323, 1.157823702216272, -0.11060664309660294 ),
        float3( -0.016493938717834573, -0.016493938717834257, 1.2519364065950405 )
    );

    // LOG2_MIN      = -10.0
    // LOG2_MAX      =  +6.5
    // MIDDLE_GRAY   =  0.18
    const float AgxMinEv = -12.47393;  // log2( pow( 2, LOG2_MIN ) * MIDDLE_GRAY )
    const float AgxMaxEv = 4.026069;    // log2( pow( 2, LOG2_MAX ) * MIDDLE_GRAY )

    color = mul(color, LINEAR_SRGB_TO_LINEAR_REC2020);
    color = mul(color, AgXInsetMatrix);

    // Log2 encoding
    color = max(color, 1e-10); // avoid 0 or negative numbers for log2
    color = log2(color);
    color = (color - AgxMinEv) / (AgxMaxEv - AgxMinEv);

    color = saturate(color);

    // Apply sigmoid
    color = agxDefaultContrastApprox(color);
    color = mul(color, AgXOutsetMatrix);

    // Linearize
    color = pow(max(0, color), 2.2);
    color = mul(color, LINEAR_REC2020_TO_LINEAR_SRGB);
    color = saturate(color);

    return color;
}

// https://iolite-engine.com/blog_posts/minimal_agx_implementation
// Mean error^2: 3.6705141e-06
float3 agxDefaultContrastApprox( float3 x ) {
    float3 x2 = x * x;
    float3 x4 = x2 * x2;
    return + 15.5 * x4 * x2
        - 40.14 * x4 * x
        + 31.96 * x4
        - 6.868 * x2 * x
        + 0.4298 * x2
        + 0.1191 * x
        - 0.00232;
}

