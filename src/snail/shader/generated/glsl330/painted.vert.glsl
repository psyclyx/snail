#version 330 core
struct VsInput {
    vec4 rect;
    vec4 xform;
    vec2 origin;
    uvec2 glyph;
    vec4 bnd;
    vec4 col;
    vec4 tint;
};
struct VsOutput {
    vec4 position;
    vec4 color;
    vec2 texcoord;
    vec4 banding;
    ivec4 glyph;
    vec4 tint;
};
struct TextVertexIn {
    vec4 rect;
    vec4 xform;
    vec2 origin;
    uvec2 glyph;
    vec4 bnd;
    vec4 col;
    vec4 tint;
};
struct SnailPushConstants_std140_ {
    mat4x4 mvp;
    vec2 viewport;
    int subpixel_order;
    int output_srgb;
    int layer_base;
    float coverage_exponent;
    float dither_scale;
    int mask_output;
};
struct TextVertexResult {
    vec4 position;
    vec4 color;
    vec4 tint;
    vec2 texcoord;
    vec4 banding;
    ivec4 glyph;
};
struct VertexOutput {
    vec4 member;
    vec4 member_1;
    vec2 member_2;
    vec4 member_3;
    ivec4 member_4;
    vec4 member_5;
};
int global = 0;

vec4 input_u002e_rect_1 = vec4(0.0);

vec4 input_u002e_xform_1 = vec4(0.0);

vec2 input_u002e_origin_1 = vec2(0.0);

uvec2 input_u002e_glyph_1 = uvec2(0u);

vec4 input_u002e_bnd_1 = vec4(0.0);

vec4 input_u002e_col_1 = vec4(0.0);

vec4 input_u002e_tint_1 = vec4(0.0);

layout(std140) uniform SnailPushConstants_std140_block_0Vertex { SnailPushConstants_std140_ _group_0_binding_0_vs; };

vec4 global_1 = vec4(0.0, 0.0, 0.0, 1.0);

vec4 entryPointParam_vertexMain_u002e_color = vec4(0.0);

vec2 entryPointParam_vertexMain_u002e_texcoord = vec2(0.0);

vec4 entryPointParam_vertexMain_u002e_banding = vec4(0.0);

ivec4 entryPointParam_vertexMain_u002e_glyph = ivec4(0);

vec4 entryPointParam_vertexMain_u002e_tint = vec4(0.0);

layout(location = 0) in vec4 _p2vs_location0;
layout(location = 1) in vec4 _p2vs_location1;
layout(location = 2) in vec2 _p2vs_location2;
layout(location = 3) in uvec2 _p2vs_location3;
layout(location = 4) in vec4 _p2vs_location4;
layout(location = 5) in vec4 _p2vs_location5;
layout(location = 6) in vec4 _p2vs_location6;
smooth out vec4 _vs2fs_location0;
smooth out vec2 _vs2fs_location1;
flat out vec4 _vs2fs_location2;
flat out ivec4 _vs2fs_location3;
smooth out vec4 _vs2fs_location4;

float snailVertexDilationScale(int subpixel_order) {
    float local = 0.0;
    if ((subpixel_order == 0)) {
        local = 1.0;
    } else {
        local = 2.3333333;
    }
    float _e43 = local;
    return (1.4142135 * _e43);
}

float srgbDecode(float c) {
    float local_1 = 0.0;
    if ((c <= 0.04045)) {
        local_1 = (c / 12.92);
    } else {
        local_1 = pow(((c + 0.055) / 1.055), 2.4);
    }
    float _e47 = local_1;
    return _e47;
}

vec3 srgbToLinear(vec3 color) {
    float _e42 = srgbDecode(color.x);
    float _e44 = srgbDecode(color.y);
    float _e46 = srgbDecode(color.z);
    return vec3(_e42, _e44, _e46);
}

TextVertexResult snailTextVertex(inout TextVertexIn input_, uint vertex_index, mat4x4 mvp, vec2 viewport, int subpixel_order_1) {
    vec2 local_2[4] = vec2[4](vec2(0.0), vec2(0.0), vec2(0.0), vec2(0.0));
    TextVertexResult r = TextVertexResult(vec4(0.0), vec4(0.0), vec4(0.0), vec2(0.0), vec4(0.0), ivec4(0));
    vec2 d = vec2(0.0);
    local_2 = vec2[4](vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(1.0, 1.0), vec2(0.0, 1.0));
    vec2 _e49 = local_2[vertex_index];
    vec4 _e51 = input_.rect;
    vec2 _e54 = mix(_e51.xy, _e51.zw, _e49);
    vec2 _e57 = ((_e49 * 2.0) - vec2(1.0));
    vec4 _e59 = input_.xform;
    vec2 _e61 = input_.origin;
    vec4 _e63 = input_.tint;
    vec2 _e80 = vec2((((_e59.x * _e54.x) + (_e59.y * _e54.y)) + _e61.x), (((_e59.z * _e54.x) + (_e59.w * _e54.y)) + _e61.y));
    float _e93 = (1.0 / ((_e59.x * _e59.w) - (_e59.y * _e59.z)));
    uvec2 _e101 = input_.glyph;
    r.glyph = ivec4(int((_e101.x & 65535u)), int((_e101.x >> 16u)), int((_e101.y & 65535u)), int((_e101.y >> 16u)));
    vec4 _e118 = input_.bnd;
    r.banding = _e118;
    vec4 _e121 = input_.col;
    vec3 _e123 = srgbToLinear(_e121.xyz);
    r.color = vec4(_e123, _e121.w);
    vec3 _e128 = srgbToLinear(_e63.xyz);
    r.tint = vec4(_e128, _e63.w);
    vec2 _e134 = normalize(vec2(((_e59.x * _e57.x) + (_e59.y * _e57.y)), ((_e59.z * _e57.x) + (_e59.w * _e57.y))));
    vec2 _e135 = mvp[3].xy;
    float _e138 = (dot(_e135, _e80) + mvp[3].w);
    float _e139 = dot(_e135, _e134);
    vec2 _e140 = mvp[0].xy;
    float _e149 = (((_e138 * dot(_e140, _e134)) - (_e139 * (dot(_e140, _e80) + mvp[0].w))) * viewport.x);
    vec2 _e150 = mvp[1].xy;
    float _e159 = (((_e138 * dot(_e150, _e134)) - (_e139 * (dot(_e150, _e80) + mvp[1].w))) * viewport.y);
    float _e161 = (_e138 * _e139);
    float _e164 = ((_e149 * _e149) + (_e159 * _e159));
    float _e166 = (_e164 - (_e161 * _e161));
    if ((abs(_e166) > 1e-10)) {
        d = (_e134 * (((_e138 * _e138) * (_e161 + sqrt(_e164))) / _e166));
    } else {
        d = ((_e134 * 2.0) / viewport);
    }
    float _e176 = snailVertexDilationScale(subpixel_order_1);
    vec2 _e177 = d;
    vec2 _e178 = (_e177 * _e176);
    r.texcoord = vec2((_e54.x + dot(_e178, vec2((_e59.w * _e93), (-(_e59.y) * _e93)))), (_e54.y + dot(_e178, vec2((-(_e59.z) * _e93), (_e59.x * _e93)))));
    r.position = (vec4((_e80 + _e178), 0.0, 1.0) * mvp);
    TextVertexResult _e191 = r;
    return _e191;
}

VsOutput vertexBody(inout VsInput input_1, uint vertex_index_1) {
    TextVertexIn v = TextVertexIn(vec4(0.0), vec4(0.0), vec2(0.0), uvec2(0u), vec4(0.0), vec4(0.0), vec4(0.0));
    TextVertexIn local_3 = TextVertexIn(vec4(0.0), vec4(0.0), vec2(0.0), uvec2(0u), vec4(0.0), vec4(0.0), vec4(0.0));
    VsOutput o = VsOutput(vec4(0.0), vec4(0.0), vec2(0.0), vec4(0.0), ivec4(0), vec4(0.0));
    vec4 _e47 = input_1.rect;
    v.rect = _e47;
    vec4 _e50 = input_1.xform;
    v.xform = _e50;
    vec2 _e53 = input_1.origin;
    v.origin = _e53;
    uvec2 _e56 = input_1.glyph;
    v.glyph = _e56;
    vec4 _e59 = input_1.bnd;
    v.bnd = _e59;
    vec4 _e62 = input_1.col;
    v.col = _e62;
    vec4 _e65 = input_1.tint;
    v.tint = _e65;
    TextVertexIn _e66 = v;
    mat4x4 _e68 = _group_0_binding_0_vs.mvp;
    vec2 _e71 = _group_0_binding_0_vs.viewport;
    int _e73 = _group_0_binding_0_vs.subpixel_order;
    local_3 = _e66;
    TextVertexResult _e74 = snailTextVertex(local_3, vertex_index_1, transpose(_e68), _e71, _e73);
    o.position = _e74.position;
    o.color = _e74.color;
    o.texcoord = _e74.texcoord;
    o.banding = _e74.banding;
    o.glyph = _e74.glyph;
    o.tint = _e74.tint;
    VsOutput _e87 = o;
    return _e87;
}

void vertexMain() {
    VsInput local_4 = VsInput(vec4(0.0), vec4(0.0), vec2(0.0), uvec2(0u), vec4(0.0), vec4(0.0), vec4(0.0));
    int _e41 = global;
    vec4 _e43 = input_u002e_rect_1;
    vec4 _e44 = input_u002e_xform_1;
    vec2 _e45 = input_u002e_origin_1;
    uvec2 _e46 = input_u002e_glyph_1;
    vec4 _e47 = input_u002e_bnd_1;
    vec4 _e48 = input_u002e_col_1;
    vec4 _e49 = input_u002e_tint_1;
    local_4 = VsInput(_e43, _e44, _e45, _e46, _e47, _e48, _e49);
    VsOutput _e51 = vertexBody(local_4, uint(_e41));
    global_1 = _e51.position;
    entryPointParam_vertexMain_u002e_color = _e51.color;
    entryPointParam_vertexMain_u002e_texcoord = _e51.texcoord;
    entryPointParam_vertexMain_u002e_banding = _e51.banding;
    entryPointParam_vertexMain_u002e_glyph = _e51.glyph;
    entryPointParam_vertexMain_u002e_tint = _e51.tint;
    return;
}

void main() {
    uint param = uint(gl_VertexID);
    vec4 input_u002e_rect = _p2vs_location0;
    vec4 input_u002e_xform = _p2vs_location1;
    vec2 input_u002e_origin = _p2vs_location2;
    uvec2 input_u002e_glyph = _p2vs_location3;
    vec4 input_u002e_bnd = _p2vs_location4;
    vec4 input_u002e_col = _p2vs_location5;
    vec4 input_u002e_tint = _p2vs_location6;
    global = int(param);
    input_u002e_rect_1 = input_u002e_rect;
    input_u002e_xform_1 = input_u002e_xform;
    input_u002e_origin_1 = input_u002e_origin;
    input_u002e_glyph_1 = input_u002e_glyph;
    input_u002e_bnd_1 = input_u002e_bnd;
    input_u002e_col_1 = input_u002e_col;
    input_u002e_tint_1 = input_u002e_tint;
    vertexMain();
    vec4 _e23 = global_1;
    vec4 _e24 = entryPointParam_vertexMain_u002e_color;
    vec2 _e25 = entryPointParam_vertexMain_u002e_texcoord;
    vec4 _e26 = entryPointParam_vertexMain_u002e_banding;
    ivec4 _e27 = entryPointParam_vertexMain_u002e_glyph;
    vec4 _e28 = entryPointParam_vertexMain_u002e_tint;
    VertexOutput _tmp_return = VertexOutput(_e23, _e24, _e25, _e26, _e27, _e28);
    gl_Position = _tmp_return.member;
    _vs2fs_location0 = _tmp_return.member_1;
    _vs2fs_location1 = _tmp_return.member_2;
    _vs2fs_location2 = _tmp_return.member_3;
    _vs2fs_location3 = _tmp_return.member_4;
    _vs2fs_location4 = _tmp_return.member_5;
    return;
}

