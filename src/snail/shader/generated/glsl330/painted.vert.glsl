#version 330

struct VsInput
{
    vec4 rect;
    vec4 xform;
    vec2 origin;
    uvec2 glyph;
    vec4 bnd;
    vec4 col;
    vec4 tint;
};

struct VsOutput
{
    vec4 position;
    vec4 color;
    vec2 texcoord;
    vec4 banding;
    ivec4 glyph;
    vec4 tint;
};

struct TextVertexIn
{
    vec4 rect;
    vec4 xform;
    vec2 origin;
    uvec2 glyph;
    vec4 bnd;
    vec4 col;
    vec4 tint;
};

struct TextVertexResult
{
    vec4 position;
    vec4 color;
    vec4 tint;
    vec2 texcoord;
    vec4 banding;
    ivec4 glyph;
};

const vec2 _123[4] = vec2[](vec2(0.0), vec2(1.0, 0.0), vec2(1.0), vec2(0.0, 1.0));

layout(std140) uniform SnailPushConstants_std140
{
    layout(row_major) mat4 mvp;
    vec2 viewport;
    int subpixel_order;
    int output_srgb;
    int layer_base;
    float coverage_exponent;
    float dither_scale;
    int mask_output;
} pc;

layout(location = 0) in vec4 input_rect;
layout(location = 1) in vec4 input_xform;
layout(location = 2) in vec2 input_origin;
layout(location = 3) in uvec2 input_glyph;
layout(location = 4) in vec4 input_bnd;
layout(location = 5) in vec4 input_col;
layout(location = 6) in vec4 input_tint;
out vec4 snail_io0;
out vec2 snail_io1;
flat out vec4 snail_io2;
flat out ivec4 snail_io3;
out vec4 snail_io4;

mat4 spvWorkaroundRowMajor(mat4 wrap) { return wrap; }

float srgbDecode(float c)
{
    float _224;
    if (c <= 0.040449999272823333740234375)
    {
        _224 = c / 12.9200000762939453125;
    }
    else
    {
        _224 = pow((c + 0.054999999701976776123046875) / 1.05499994754791259765625, 2.400000095367431640625);
    }
    return _224;
}

vec3 srgbToLinear(vec3 color)
{
    return vec3(srgbDecode(color.x), srgbDecode(color.y), srgbDecode(color.z));
}

float snailVertexDilationScale(int subpixel_order)
{
    float _317;
    if (subpixel_order == 0)
    {
        _317 = 1.0;
    }
    else
    {
        _317 = 2.3333332538604736328125;
    }
    return 1.41421353816986083984375 * _317;
}

TextVertexResult snailTextVertex(TextVertexIn _input, uint vertex_index, mat4 mvp, vec2 viewport, int subpixel_order)
{
    vec2 _137 = mix(_input.rect.xy, _input.rect.zw, _123[vertex_index]);
    vec2 nd = (_123[vertex_index] * 2.0) - vec2(1.0);
    float _150 = _137.x;
    float _153 = _137.y;
    vec2 pos = vec2(((_input.xform.x * _150) + (_input.xform.y * _153)) + _input.origin.x, ((_input.xform.z * _150) + (_input.xform.w * _153)) + _input.origin.y);
    float _166 = nd.x;
    float _168 = nd.y;
    float inv_det = 1.0 / ((_input.xform.x * _input.xform.w) - (_input.xform.y * _input.xform.z));
    TextVertexResult r;
    r.glyph = ivec4(int(_input.glyph.x & 65535u), int(_input.glyph.x >> 16u), int(_input.glyph.y & 65535u), int(_input.glyph.y >> 16u));
    r.banding = _input.bnd;
    r.color = vec4(srgbToLinear(_input.col.xyz), _input.col.w);
    r.tint = vec4(srgbToLinear(_input.tint.xyz), _input.tint.w);
    vec2 _264 = normalize(vec2((_input.xform.x * _166) + (_input.xform.y * _168), (_input.xform.z * _166) + (_input.xform.w * _168)));
    float s = dot(mvp[3].xy, pos) + mvp[3].w;
    float _269 = dot(mvp[3].xy, _264);
    float u_val = ((s * dot(mvp[0].xy, _264)) - (_269 * (dot(mvp[0].xy, pos) + mvp[0].w))) * viewport.x;
    float v_val = ((s * dot(mvp[1].xy, _264)) - (_269 * (dot(mvp[1].xy, pos) + mvp[1].w))) * viewport.y;
    float st = s * _269;
    float uv = (u_val * u_val) + (v_val * v_val);
    float denom = uv - (st * st);
    vec2 d;
    if (abs(denom) > 1.0000000133514319600180897396058e-10)
    {
        d = _264 * (((s * s) * (st + sqrt(uv))) / denom);
    }
    else
    {
        d = (_264 * 2.0) / viewport;
    }
    vec2 d_1 = d * snailVertexDilationScale(subpixel_order);
    r.texcoord = vec2(_150 + dot(d_1, vec2(_input.xform.w * inv_det, (-_input.xform.y) * inv_det)), _153 + dot(d_1, vec2((-_input.xform.z) * inv_det, _input.xform.x * inv_det)));
    r.position = vec4(pos + d_1, 0.0, 1.0) * mvp;
    return r;
}

VsOutput vertexBody(VsInput _input, uint vertex_index)
{
    TextVertexIn v;
    v.rect = _input.rect;
    v.xform = _input.xform;
    v.origin = _input.origin;
    v.glyph = _input.glyph;
    v.bnd = _input.bnd;
    v.col = _input.col;
    v.tint = _input.tint;
    TextVertexIn _48 = v;
    TextVertexResult _105 = snailTextVertex(_48, vertex_index, spvWorkaroundRowMajor(pc.mvp), pc.viewport, pc.subpixel_order);
    VsOutput o;
    o.position = _105.position;
    o.color = _105.color;
    o.texcoord = _105.texcoord;
    o.banding = _105.banding;
    o.glyph = _105.glyph;
    o.tint = _105.tint;
    return o;
}

void main()
{
    VsInput _12 = VsInput(input_rect, input_xform, input_origin, input_glyph, input_bnd, input_col, input_tint);
    VsOutput _39 = vertexBody(_12, uint(gl_VertexID));
    gl_Position = _39.position;
    snail_io0 = _39.color;
    snail_io1 = _39.texcoord;
    snail_io2 = _39.banding;
    snail_io3 = _39.glyph;
    snail_io4 = _39.tint;
}

