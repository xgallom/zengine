float4 main(float3 TexCoord : TEXCOORD0) : SV_Target0
{
    float3 color = TexCoord / 5 + 0.5;
    return float4(color, 1.0);
}
