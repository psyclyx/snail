#version 300 es

struct VsOutput
{
    vec4 position;
    vec2 uv;
};

out vec2 snail_io0;

void main()
{
    float _7;
    if (gl_VertexID == 1)
    {
        _7 = 3.0;
    }
    else
    {
        _7 = -1.0;
    }
    float _8;
    if (gl_VertexID == 2)
    {
        _8 = 3.0;
    }
    else
    {
        _8 = -1.0;
    }
    vec2 pos = vec2(_7, _8);
    VsOutput o;
    o.uv = (pos * 0.5) + vec2(0.5);
    o.position = vec4(pos, 0.0, 1.0);
    gl_Position = o.position;
    snail_io0 = o.uv;
}

