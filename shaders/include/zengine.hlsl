#ifndef _ZENGINE_HLSL_
#define _ZENGINE_HLSL_

#define PI 3.1415926538

float random(float2 uv) {
    return frac(sin(dot(uv, float2(12.9898, 4.1414))) * 43758.5453);
}

float noise(float2 uv) {
    float2 i = floor(uv);
    float2 f = frac(uv);

    // Four corners in 2D of a tile
    float a = random(i);
    float b = random(i + float2(1.0, 0.0));
    float c = random(i + float2(0.0, 1.0));
    float d = random(i + float2(1.0, 1.0));

    // Smooth Interpolation

    // Cubic Hermine Curve.  Same as SmoothStep()
    float2 u = f * f * (3 - 2 * f);
    // u = smoothstep(0.,1.,f);

    // Mix 4 coorners percentages
    return lerp(a, b, u.x) +
            (c - a) * u.y * (1 - u.x) +
            (d - b) * u.x * u.y;
}

float2 cross2(float2 l, float2 r) {
    return float2( l.x * r.y, l.y * r.x );
}

float2 bleed(float2 uv, float mag) {
    const float2 c = uv * mag;
    return float2( uv.x + c.y, c.x + uv.y );
}

float3 bleed(float3 uv, float2 mag) {
    const float3 c1 = uv * mag.x;
    const float3 c2 = uv * mag.y;
    return float3( uv.x + c1.y + c2.z, c2.x + uv.y + c1.z, c1.x + c2.y + uv.z );
}

float avg(float a, float b) {
    return ( a + b ) / 2;
}

float2 avg(float2 a, float2 b) {
    return ( a + b ) / 2;
}

float3 avg(float3 a, float3 b) {
    return ( a + b ) / 2;
}

float4 avg(float4 a, float4 b) {
    return ( a + b ) / 2;
}

float2 sum2(float2 uv) {
    return avg( uv.xx, uv.yy );
}

float2x2 rot2(float angle) {
    const float c = cos(angle), s = sin(angle);
    return float2x2(
        c, -s,
        s, c
    );
}

float3x3 rot3(float angle, float3 axis) {
    const float3 u = normalize( axis );
    const float c = cos(angle), s = sin(angle);
    const float3x3 proj = float3x3(
        u.x * u.x, u.x * u.y, u.x * u.z,
        u.y * u.x, u.y * u.y, u.y * u.z,
        u.z * u.x, u.z * u.y, u.z * u.z
    );
    const float3x3 rest = float3x3(
        c, -u.z * s, u.y * s,
        u.z * s, c, -u.x * s,
        u.y * s, u.x * s, c
    );
    return proj * (1 - c) + rest;
}

float3 saturateBlue(float2 uv) {
    return saturate( float3( uv, ( uv.x + uv.y - 1 ) / 4 ) );
}

float2 repeat(float2 uv, float times) {
    return frac(uv * times);
}

float2 repeatIndex(float2 uv, float times) {
    return floor(uv * times);
}

float linearIndex(float2 idx, float times, int offset) {
    return idx.x + idx.y * times + offset;
}

float2 normalizeUV(float2 uv) {
    return (uv - 0.5) * 2;
}

float2 normalizeMousePos(float2 mouse_pos) {
    return float2(2, 2) * (mouse_pos - 0.5);
}

float2 aspectRatio(float wh_ratio) {
     return float2(wh_ratio, 1);
}

float2 mixOscillate(float2 a, float2 b, float t) {
    const float c = cos(t), s = sin(t);
    return c * c * a + s * s * b;
}

#endif
