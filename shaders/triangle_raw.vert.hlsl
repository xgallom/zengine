cbuffer UniformBuffer : register(b0, space1)
{
    float Time : packoffset(c0);
};

struct Input
{
    uint VertexIndex : SV_VertexID;
};

struct Output
{
    float4 Color : TEXCOORD0;
    float4 Position : SV_Position;
};

static const float PI = 3.14159265358979323846264338327950288419716939937510f;

Output main(Input input)
{
    Output output;

    float4 pos = float4(0.0f, 1.0f, 0.0f, 2.0f);
    float phase = 0;
    float step_value = step(0.0f, fmod(Time, 2.0f * 2.0f * 1000.0f) - 2.0f * 1000.0f) - 0.5f;

    if (input.VertexIndex == 0)
    {
        output.Color = float4(1.0f, 0.0f, 0.0f, 1.0f);
    }
    else
    {
        if (input.VertexIndex == 1)
        {
            phase = PI * 2.0f / 3.0f;
            output.Color = float4(0.0f, 1.0f, 0.0f, 1.0f);
        }
        else
        {
            if (input.VertexIndex == 2)
            {
                phase = PI * 4.0f / 3.0f;
                output.Color = float4(0.0f, 0.0f, 1.0f, 1.0f);
            }
        }
    }

    float w = Time * 2.0f * PI / 1000;
    float t = step_value * w + phase;
    float cost = cos(t);
    float sint = sin(t);

    float4x4 transform = {
        cost, sint, 0   , 0   ,
        sint, cost, 0   , 0   ,
        0,    0   , 1   , 0   ,
        0,    0   , 0   , 1   ,
    };

    float4 position = mul(transform, pos);
    output.Position = position;
    return output;
}
