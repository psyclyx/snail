#version 330 core
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

void vertexMain() {
    ivec4 local = ivec4(0);
    vec4 local_1 = vec4(0.0);
    vec4 local_2 = vec4(0.0);
    vec4 local_3 = vec4(0.0);
    float local_4 = 0.0;
    float local_5 = 0.0;
    float local_6 = 0.0;
    float local_7 = 0.0;
    float local_8 = 0.0;
    float local_9 = 0.0;
    float local_10 = 0.0;
    vec2 local_11[4] = vec2[4](vec2(0.0), vec2(0.0), vec2(0.0), vec2(0.0));
    vec2 local_12 = vec2(0.0);
    int _e50 = global;
    vec4 _e52 = input_u002e_rect_1;
    vec4 _e53 = input_u002e_xform_1;
    vec2 _e54 = input_u002e_origin_1;
    uvec2 _e55 = input_u002e_glyph_1;
    vec4 _e56 = input_u002e_bnd_1;
    vec4 _e57 = input_u002e_col_1;
    vec4 _e58 = input_u002e_tint_1;
    mat4x4 _e60 = _group_0_binding_0_vs.mvp;
    mat4x4 _e61 = transpose(_e60);
    vec2 _e63 = _group_0_binding_0_vs.viewport;
    int _e65 = _group_0_binding_0_vs.subpixel_order;
    local_11 = vec2[4](vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(1.0, 1.0), vec2(0.0, 1.0));
    vec2 _e67 = local_11[uint(_e50)];
    vec2 _e70 = mix(_e52.xy, _e52.zw, _e67);
    vec2 _e72 = ((_e67 * 2.0) - vec2(1.0, 1.0));
    vec2 _e89 = vec2((((_e53.x * _e70.x) + (_e53.y * _e70.y)) + _e54.x), (((_e53.z * _e70.x) + (_e53.w * _e70.y)) + _e54.y));
    float _e102 = (1.0 / ((_e53.x * _e53.w) - (_e53.y * _e53.z)));
    local = ivec4(int((_e55.x & 65535u)), int((_e55.x >> 16u)), int((_e55.y & 65535u)), int((_e55.y >> 16u)));
    local_1 = _e56;
    if ((_e57.x <= 0.04045)) {
        local_10 = (_e57.x * 0.07739938);
    } else {
        local_10 = pow(((_e57.x + 0.055) * 0.94786733), 2.4);
    }
    float _e128 = local_10;
    if ((_e57.y <= 0.04045)) {
        local_9 = (_e57.y * 0.07739938);
    } else {
        local_9 = pow(((_e57.y + 0.055) * 0.94786733), 2.4);
    }
    float _e135 = local_9;
    if ((_e57.z <= 0.04045)) {
        local_8 = (_e57.z * 0.07739938);
    } else {
        local_8 = pow(((_e57.z + 0.055) * 0.94786733), 2.4);
    }
    float _e142 = local_8;
    local_3 = vec4(vec3(_e128, _e135, _e142), _e57.w);
    if ((_e58.x <= 0.04045)) {
        local_7 = (_e58.x * 0.07739938);
    } else {
        local_7 = pow(((_e58.x + 0.055) * 0.94786733), 2.4);
    }
    float _e152 = local_7;
    if ((_e58.y <= 0.04045)) {
        local_6 = (_e58.y * 0.07739938);
    } else {
        local_6 = pow(((_e58.y + 0.055) * 0.94786733), 2.4);
    }
    float _e159 = local_6;
    if ((_e58.z <= 0.04045)) {
        local_5 = (_e58.z * 0.07739938);
    } else {
        local_5 = pow(((_e58.z + 0.055) * 0.94786733), 2.4);
    }
    float _e166 = local_5;
    local_2 = vec4(vec3(_e152, _e159, _e166), _e58.w);
    vec2 _e173 = normalize(vec2(((_e53.x * _e72.x) + (_e53.y * _e72.y)), ((_e53.z * _e72.x) + (_e53.w * _e72.y))));
    vec2 _e174 = _e61[3].xy;
    float _e177 = (dot(_e174, _e89) + _e61[3].w);
    float _e178 = dot(_e174, _e173);
    vec2 _e179 = _e61[0].xy;
    float _e188 = (((_e177 * dot(_e179, _e173)) - (_e178 * (dot(_e179, _e89) + _e61[0].w))) * _e63.x);
    vec2 _e189 = _e61[1].xy;
    float _e198 = (((_e177 * dot(_e189, _e173)) - (_e178 * (dot(_e189, _e89) + _e61[1].w))) * _e63.y);
    float _e200 = (_e177 * _e178);
    float _e203 = ((_e188 * _e188) + (_e198 * _e198));
    float _e205 = (_e203 - (_e200 * _e200));
    if ((abs(_e205) > 1e-10)) {
        local_12 = (_e173 * (((_e177 * _e177) * (_e200 + sqrt(_e203))) / _e205));
    } else {
        local_12 = ((_e173 * 2.0) / _e63);
    }
    if ((_e65 == 0)) {
        local_4 = 1.0;
    } else {
        local_4 = 2.3333333;
    }
    float _e216 = local_4;
    vec2 _e218 = local_12;
    vec2 _e219 = (_e218 * (1.4142135 * _e216));
    ivec4 _e230 = local;
    vec4 _e231 = local_1;
    vec4 _e232 = local_2;
    vec4 _e233 = local_3;
    global_1 = (vec4((_e89 + _e219), 0.0, 1.0) * _e61);
    entryPointParam_vertexMain_u002e_color = _e233;
    entryPointParam_vertexMain_u002e_texcoord = vec2((_e70.x + dot(_e219, vec2((_e53.w * _e102), (-(_e53.y) * _e102)))), (_e70.y + dot(_e219, vec2((-(_e53.z) * _e102), (_e53.x * _e102)))));
    entryPointParam_vertexMain_u002e_banding = _e231;
    entryPointParam_vertexMain_u002e_glyph = _e230;
    entryPointParam_vertexMain_u002e_tint = _e232;
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

