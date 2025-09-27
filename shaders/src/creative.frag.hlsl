cbuffer FragUniformBuffer : register(b0, space3) {
    float time;
};

struct Input {
    float2 tex_coord : TEXCOORD0;
    float3 normal    : TEXCOORD1;
    float3 world_pos : TEXCOORD2;
};

float get_max(float3 vector) {
    if (vector.x < vector.y) {
        if (vector.y < vector.z) {
            return vector.z;
        } else {
            return vector.y;
        }
    } else {
        if (vector.x < vector.z) {
            return vector.z;
        } else {
            return vector.x;
        }
    }
}

float4 main(Input input) : SV_Target0
{
    //const float3 positive = abs(tex_coord);
    //const float3 rotated = positive.yzx * positive.zxy;
    //const float3 mapped = positive / get_max(positive);
    //const float3 inv_mapped = rotated / get_max(positive);

    //float distance = abs(length(mapped) + abs(fmod(time, 2) - 1) - 2);
    //distance = step(0.1, distance);
    //const float inv_distance = 1 - distance;

    //const float3 result = ((mapped * distance) + (inv_mapped * inv_distance)) / (get_max(mapped) * distance + get_max(inv_mapped) * inv_distance);
    //return float4(result, 1);
    return float4(input.tex_coord.xy, 0, 1);
}

