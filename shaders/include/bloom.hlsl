#ifndef _BLOOM_HLSL_
#define _BLOOM_HLSL_

cbuffer BloomParams : register(b0, space3) {
    float blm_thresh;
    float blm_int;
    float2 blm_texel_size;
};

#endif
