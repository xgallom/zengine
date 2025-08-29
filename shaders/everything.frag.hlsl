#include <zeng.hlsl>

cbuffer FragUniformBuffer : register(b0, space3) {
    float time;
    float wh_ratio;
    float2 mouse_pos;
};

struct Input {
    float2 uv : TEXCOORD0;
};

float4 main(Input input) : SV_Target0 {
    const float2 aspect = float2(wh_ratio, 1);

    const float2 mp = float2(1, -1) * ( mouse_pos - 0.5 ) * 40;
    const float2 uv = ( input.uv - 0.5 ) * 2;
    const float2 uvn = aspect * (uv);
    const float2 uva = abs(uvn);
    float t = time;
    t *= lerp(-1, 1, (floor(t / 2) % 4) / 3);

    const float rnd = random(floor(uv * 50) * t).x;
    const float2 phase_shake = cos( float2(0.5 / 11, 0.5 / 9) + float2(50 / 13, 50 / 7) * PI * 0.4 + t * PI / 4 + t * PI / 12 );
    const float dist = length( uva );
    const float sdf = smoothstep(0.8 * (0.7 + cos(t) * 0.3), 1.2 * (0.7 + cos(t) * 0.3), 2 * dist);
    const float nsdf = 1 - sdf;

    const float2 circ = mul( rot2(t * PI * 0.25), uva + phase_shake * (sin(t) + 1) / 2 );
    const float plen = frac( length( circ * 3 ) + t );
    const float nlen = frac( length( circ * 3 ) - t );
    //const float len = sdf * (cos(t) * cos(t) * plen + sin(t) * sin(t) * nlen) + nsdf * (cos(t) * cos(t) * nlen + sin(t) * sin(t) * plen) ;
    const float len = avg(nlen, plen) + 0.1 * plen * rnd;

    const float ring = 1 - len;
    const float sat_ring = ring * ring * ring;
    const float inv_ring = 1 - abs( len - 1 );
    const float sat_inv_ring = inv_ring * inv_ring * inv_ring;
    const float2 osc = cos( circ * len * PI + t * 8 * PI ) / 2 + 0.5;
    const float2 osc2 = cos( circ * 2.1 * PI + t * 7.5 * PI ) / 2 + 0.5;
    const float2 clr = avg( avg(sat_ring, sat_inv_ring), bleed( avg( osc, osc2 ), 0.5 ) );
    // const float2 clr = ( sat_ring + sat_inv_ring ) / 2;
    const float2 inv_web = sum2( saturate( bleed( clr, 0.5 ) ) );

    const float2 nuv = mul( rot2(t * PI / 10), uvn );
    const float nis = saturate(noise(nuv * ( 1 + 10 * frac(t / 2) ) * 250)) * 0.5 + 0.5;
    const float2 result = nis * bleed( clr * clr, 0.3 );
    const float3 output = saturate( float3( result, ( result.x + result.y - 1 ) / 4 ) );
    return float4(output.rbg, 1);
}
