#include <zengine.hlsl>

float3 deathly_grayscale(float3 hdr_color)
{
    float lum = dot(hdr_color, float3(0.299, 0.587, 0.114));
    
    float gray = lum / (1.0 + lum);
    gray = gray * 0.75;
    
    float overflow = max(0.0, lum - 1);
    float red_blend = 1.0 - exp(-overflow * 0.5);
    
    float3 cold_gray = float3(gray * 0.95, gray * 0.97, gray);
    float3 blood_red = float3(0.4 + gray * 0.5, gray * 0.2, gray * 0.15);
    
    return lerp(cold_gray, blood_red, red_blend);
}

float3 deathly_harsh(float3 hdr_color)
{
    float lum = dot(hdr_color, float3(0.299, 0.587, 0.114));
    
    float gray = lum / (1.0 + lum);
    gray = 0.08 + gray * 0.65;
    
    /* Sharp cutoff into red */
    float overflow = smoothstep(0.9, 1.5, lum);
    
    float3 corpse = float3(gray * 0.9, gray * 0.95, gray);
    float3 blood = float3(0.6, 0.08, 0.05) + gray * float3(0.3, 0.1, 0.1);
    
    return lerp(corpse, blood, overflow);
}

float3 deathly_bleed(float3 hdr_color)
{
    float lum = dot(hdr_color, float3(0.299, 0.587, 0.114));
    
    float compressed = lum / (1.0 + lum);
    
    /* Red channel resists compression slightly */
    float r = hdr_color.r / (1.0 + hdr_color.r * 0.8);
    float bleed = max(0.0, r - compressed) * 0.5;
    
    float gray = 0.05 + compressed * 0.7;
    
    return float3(gray + bleed, gray * 0.95, gray * 0.9);
}

float3 deathly_veins(float3 hdr_color)
{
    float lum = dot(hdr_color, float3(0.299, 0.587, 0.114));
    
    float gray = lum / (1.0 + lum);
    gray = 0.06 + gray * 0.7;
    
    /* Red overflow weighted by original red channel */
    float overflow = max(0.0, lum - 0.8);
    float red_weight = hdr_color.r / (lum + 0.001);  /* How red was the source */
    float red_amount = overflow * red_weight * 0.8;
    
    return float3(
        gray + red_amount,
        gray * (1.0 - red_amount * 0.5),
        gray * (1.0 - red_amount * 0.6)
    );
}

float3 deathly_metal(float3 hdr_color)
{
    float lum = dot(hdr_color, float3(0.299, 0.587, 0.114));
    
    /* Hard compression, crushed blacks */
    float gray = lum / (0.5 + lum);
    gray = pow(gray, 1.4);  /* Crush it */
    gray = smoothstep(0.02, 0.95, gray);  /* Clip shadows and highlights */
    
    /* Aggressive red overflow */
    float overflow = max(0.0, lum - 0.7);
    float red_blend = 1.0 - 1.0 / (1.0 + overflow * 2.0);
    
    float3 cold = gray.xxx;  /* Pure gray, no tint */
    float3 blood = float3(0.8, 0.05, 0.02) * (0.5 + gray);
    
    return lerp(cold, blood, red_blend);
}

/* Full music video aggression */
float3 deathly_brutal(float3 hdr_color)
{
    float lum = dot(hdr_color, float3(0.299, 0.587, 0.114));
    
    /* Harsh S-curve - crush blacks, blow highlights */
    float gray = lum / (0.3 + lum);
    gray = gray * gray * (3.0 - 2.0 * gray);  /* S-curve */
    gray = clamp((gray - 0.1) * 1.3, 0.0, 1.0);  /* Clip hard */
    
    /* Red kicks in fast and mean */
    float overflow = max(0.0, lum - 0.5);
    float red_blend = smoothstep(0.0, 0.8, overflow);
    
    float3 ash = gray.xxx;
    float3 rage = float3(1.0, 0.1, 0.05) * (0.3 + gray * 0.9);
    
    return lerp(ash, rage, red_blend);
}

/* Variant with near-black shadows */
float3 deathly_void(float3 hdr_color)
{
    float lum = dot(hdr_color, float3(0.299, 0.587, 0.114));
    
    /* Extreme contrast */
    float gray = lum / (0.2 + lum);
    gray = pow(max(gray - 0.15, 0.0) * 1.2, 1.5);
    
    /* Red bloom on overflow */
    float overflow = max(0.0, lum - 0.6);
    float red = overflow * 1.5;
    
    return float3(
        clamp(gray + red, 0.0, 1.0),
        gray * (1.0 - red * 0.8),
        gray * (1.0 - red * 0.9)
    );
}

/* Gritty with slight grain effect */
float3 deathly_grit(float3 hdr_color, float2 uv, float time)
{
    float lum = dot(hdr_color, float3(0.299, 0.587, 0.114));
    
    /* Crushed */
    float gray = lum / (0.4 + lum);
    gray = pow(gray, 1.3);
    gray = clamp((gray - 0.08) * 1.2, 0.0, 1.0);
    
    /* Subtle noise */
    float noise = frac(sin(dot(uv + time, float2(12.9898, 78.233))) * 43758.5453);
    gray += (noise - 0.5) * 0.06;
    
    /* Blood */
    float overflow = max(0.0, lum - 0.6);
    float red_blend = smoothstep(0.0, 1.0, overflow * 1.5);
    
    float3 dead = gray.xxx;
    float3 blood = float3(0.9, 0.08, 0.03) * (0.4 + gray * 0.8);
    
    return lerp(dead, blood, red_blend);
}

Texture2D<float4> ScreenBuffer : register(t0, space2);
SamplerState ScreenSampler  : register(s0, space2);

float4 main(float2 screen_pos : TEXCOORD) : SV_Target {
    const float2 uv = screen_pos * 0.5f + 0.5f; 
    const float3 src = ScreenBuffer.Sample(ScreenSampler, uv).rgb;
    return float4(deathly_void(src), 1);
}
