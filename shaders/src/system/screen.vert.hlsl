//
// * [-1,3]
// |\
// +-+ screen [[-1,-1],[1,1]]
// | |\
// *-+-* [3,-1]
// [-1,-1]
//

struct Output {
    float4 position   : SV_Position;
    float2 screen_pos : TEXCOORD;
};

Output main(uint idx : SV_VertexID) {
    Output output;
    const float2 verts[] = {
        float2(-1, 3),
        float2(-1, -1),
        float2(3, -1),
    };
    const float2 screen_pos = verts[idx];

    output.position = float4(screen_pos, 0, 1);
    output.screen_pos = screen_pos * float2(1, -1);
    return output;
}
