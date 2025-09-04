cbuffer FragUniformBuffer : register(b0, space3) {
    float time;
    float wh_ratio;
    float2 mouse_pos;
};

#include <zeng.hlsl>

struct Input {
    float2 uv : TEXCOORD0;
};

float map(float3 p) {
    // Domain repetition
    p = abs(frac(p) - 0.5);
    // Cylinder + planes SDF
    return abs(min(length(p.xy) - 0.175, min(p.x, p.y) + 1e-3)) + 1e-3;
}

float3 estimateNormal(float3 p) {
    float eps = 0.001;
    return normalize(float3(
        map(p + float3(eps, 0.0, 0.0)) - map(p - float3(eps, 0.0, 0.0)),
        map(p + float3(0.0, eps, 0.0)) - map(p - float3(0.0, eps, 0.0)),
        map(p + float3(0.0, 0.0, eps)) - map(p - float3(0.0, 0.0, eps))
    ));
}

float4 main(Input input) : SV_Target0 {
    const float2 aspect = aspectRatio(wh_ratio);

    const float2 mp = normalizeMousePos(mouse_pos);
    const float2 uv = normalizeUv(input.uv);
    const float2 uvr = normalizeUv(repeat(input.uv, 4));
    const float2 idx = indexRepeat(input.uv, 4);
    const float2 uvn = aspect * uv;
    const float2 uvnr = aspect * uvr;
    const float2 uva = abs(uv);
    const float2 uvar = abs(uvnr);
    const float t = time;

    const float3 lightDir = normalize(float3(0.3, 0.5, 1.0));
    const float3 viewDir = normalize(float3(uvn, 1.0));

    float z = frac(dot(uvn, sin(uvn))) - 0.5;
    float4 col = float4(0, 0, 0, 0);
    float4 p;

    for ( float i = 0; i < 77; ++i ) {
        p = float4( z * normalize(float3( uvn - 0.7 * aspect, aspect.y )), 0.1 * t );
        p.z += t;

        float4 q = p;

        const float2x2 r1 = float2x2( cos( 2 + q.z + float4(0, 11, 33, 0) ));
        const float2x2 r2 = float2x2( cos( q + float4(0, 11, 33, 0) ));
        p.xy = mul( rot2(q.z), p.xy );

        const float d = map(p.xyz);

        const float3 pos = p.xyz;
        const float3 n = estimateNormal(pos);
        const float3 reflectDir = reflect(viewDir, n);

        const float3 envColor = lerp( float3(0.8, 0.4, 0.8), float3(1, 1, 1), 0.5 + 0.5 * reflectDir.y );
        const float spec = pow(max(dot(reflectDir, lightDir), 0.0), 32.0);

        const float4 baseColor = (1.0 + sin(0.5 * q.z + length(p.xyz - q.xyz) + float4(0,4,3,6)))
                       / (0.5 + 2.0 * dot(q.xy, q.xy));

        const float3 finalColor = baseColor.rgb * 0.1 + envColor * 0.9 + float3(spec.xxx) * 1.2;

        col.rgb += finalColor / d;
        z += 0.6 * d;
    }
    return float4(tanh(col.rgb / 2e4), 1);

    const float3 output = saturateBlue(float2(1, 1));
    return float4(output.rbg, 1);
    // return float4(output, 1);
}
