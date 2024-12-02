float4 main(float3 TexCoord : TEXCOORD0) : SV_Target0
{
    float3 normalTexCoord = TexCoord / 20 + 0.5;
    float3 originalColors = step(1, normalTexCoord) * 2 / 3;
    float3 inverseColors = (1 - step(0, normalTexCoord)) * 2 / 3;
    float3 colors = float3(
        originalColors.x + inverseColors.y + inverseColors.z,
        originalColors.y + inverseColors.x + inverseColors.z,
        originalColors.z + inverseColors.x + inverseColors.y
    );
    return float4(colors, 1.0);
}
