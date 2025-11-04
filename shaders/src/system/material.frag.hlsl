#include <zengine.hlsl>
#include <lights.hlsl>
#include <material_maps.hlsl>

#define MTL_CONFIG_HAS_TEXTURE     (1 << 0)
#define MTL_CONFIG_HAS_DIFFUSE_MAP (1 << 1)
#define MTL_CONFIG_HAS_BUMP_MAP    (1 << 2)
#define MTL_CONFIG_HAS_NORMAL_MAP  (1 << 3)
#define MTL_CONFIG_HAS_FILTER      (1 << 4)

cbuffer Material : register(b0, space3) {
    float3 mtl_clr_ambient;
    float3 mtl_clr_diffuse;
    float3 mtl_clr_specular;
    float3 mtl_clr_emissive;
    float3 mtl_clr_filter;
    uint   mtl_illum;

    float mtl_specular_exp;
    float mtl_ior;
    float mtl_alpha;
    uint  mtl_config;
};

cbuffer Camera : register(b1, space3) {
    float3 camera_pos;
}

struct MeshVertex {
    float3 position  : POSITION;
    float2 tex_coord : TEXCOORD;
    float3 normal    : NORMAL;
    float3 tangent   : TANGENT;
    float3 binormal  : BINORMAL;
};

struct WorldVertex {
    float3 position  : POSITION1;
    float2 tex_coord : TEXCOORD1;
    float3 normal    : NORMAL1;
    float3 tangent   : TANGENT1;
    float3 binormal  : BINORMAL1;
};

float4 main(WorldVertex world) : SV_Target {
    const float2 tex_uv = world.tex_coord;
    const float3 camera_dir = cameraDir(world.position, camera_pos);

    float3 normal = normalize(world.normal);
    [branch] if (mtl_config & MTL_CONFIG_HAS_BUMP_MAP)
        normal = bumpMap(world.position, tex_uv, normal);
    [branch] if (mtl_config & MTL_CONFIG_HAS_NORMAL_MAP) 
        normal = normalMap(tex_uv, world.normal, world.tangent, world.binormal);

    const Light light = processLights(world.position, normal, camera_dir, mtl_specular_exp);

    float3 ambient_tex = float3(1, 1, 1);
    float3 diffuse_tex = float3(1, 1, 1);
    [branch] if (mtl_config & MTL_CONFIG_HAS_TEXTURE) ambient_tex = TextureMap.Sample(SamplerTexture, tex_uv).xyz;
    [branch] if (mtl_config & MTL_CONFIG_HAS_DIFFUSE_MAP) diffuse_tex = DiffuseMap.Sample(SamplerDiffuse, tex_uv).xyz;

    const float3 ambient = light.ambient * mtl_clr_ambient * ambient_tex;
    const float3 diffuse = light.diffuse * mtl_clr_diffuse * diffuse_tex;
    const float3 specular = light.specular * mtl_clr_specular;
    const float3 emissive = mtl_clr_emissive;

    float3 color = ambient + diffuse + specular + emissive;
    [branch] if (mtl_config & MTL_CONFIG_HAS_FILTER) color *= mtl_clr_filter;
    return float4(color, mtl_alpha);
}
