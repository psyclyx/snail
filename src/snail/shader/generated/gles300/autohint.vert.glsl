#version 300 es

precision highp float;
precision highp int;

struct TextVertexIn_0_ {
    vec4 rect_0_;
    vec4 xform_0_;
    vec2 origin_0_;
    uvec2 glyph_1_;
    vec4 bnd_0_;
    vec4 col_0_;
    vec4 tint_1_;
};
struct TextVertexResult_0_ {
    vec4 position_0_;
    vec4 color_1_;
    vec4 tint_0_;
    vec2 texcoord_0_;
    vec4 banding_0_;
    ivec4 glyph_0_;
};
struct SnailAutohintPolicy_0_ {
    int xAlign_0_;
    int xStem_0_;
    int xPositioning_0_;
    int xRegistration_0_;
    int yAlign_0_;
    int yStem_0_;
    int yOvershoot_0_;
    int fadeEnabled_0_;
    float fadeStart_0_;
    float fadeFull_0_;
    float xRatio_0_;
    float xMaxPx_0_;
    float yRatio_0_;
    float yMaxPx_0_;
    float overshootMinPx_0_;
};
struct AutohintVertexResult_0_ {
    vec4 position_1_;
    vec4 paint_0_;
    vec3 texcoord_layer_0_;
    ivec2 info_0_;
    uvec4 policy0_0_;
    uvec3 policy1_0_;
    vec4 x_targets_0_[4];
    vec4 y_targets_0_[4];
    uvec4 x_sources_0_;
    uvec4 y_sources_0_;
};
struct VsInput_0_ {
    vec4 rect_1_;
    vec4 xform_2_;
    vec2 origin_1_;
    uvec2 glyph_2_;
    vec4 bnd_1_;
    vec4 col_1_;
    vec4 tint_2_;
    uvec4 policy0_3_;
    uvec3 policy1_3_;
};
struct VsOutput_0_ {
    vec4 position_2_;
    vec4 paint_1_;
    vec3 texcoord_layer_1_;
    ivec2 info_1_;
    uvec4 policy0_2_;
    uvec3 policy1_2_;
    vec4 x_targets0_0_;
    vec4 x_targets1_0_;
    vec4 x_targets2_0_;
    vec4 x_targets3_0_;
    vec4 y_targets0_0_;
    vec4 y_targets1_0_;
    vec4 y_targets2_0_;
    vec4 y_targets3_0_;
    uvec4 x_sources_1_;
    uvec4 y_sources_1_;
};
struct block_SnailPushConstants_0_ {
    mat4x4 mvp_0_;
    vec2 viewport_0_;
    int subpixel_order_0_;
    int output_srgb_0_;
    int layer_base_0_;
    float coverage_exponent_0_;
    float dither_scale_0_;
    int mask_output_0_;
};
struct gen_gl_PerVertex {
    vec4 gen_gl_Position;
    float gen_gl_PointSize;
    float gen_gl_ClipDistance[1];
    float gen_gl_CullDistance[1];
};
struct VertexOutput {
    vec4 gen_gl_Position;
    vec4 member;
    vec3 member_1;
    ivec2 member_2;
    uvec4 member_3;
    uvec3 member_4;
    vec4 member_5;
    vec4 member_6;
    vec4 member_7;
    vec4 member_8;
    vec4 member_9;
    vec4 member_10;
    vec4 member_11;
    vec4 member_12;
    uvec4 member_13;
    uvec4 member_14;
};
layout(std140) uniform block_SnailPushConstants_0_block_0Vertex { block_SnailPushConstants_0_ _group_0_binding_0_vs; };

uniform highp sampler2D _group_0_binding_3_vs;

vec4 input_rect_0_1 = vec4(0.0);

vec4 input_xform_0_1 = vec4(0.0);

vec2 input_origin_0_1 = vec2(0.0);

uvec2 input_glyph_0_1 = uvec2(0u);

vec4 input_bnd_0_1 = vec4(0.0);

vec4 input_col_0_1 = vec4(0.0);

vec4 input_tint_0_1 = vec4(0.0);

uvec4 input_policy0_0_1 = uvec4(0u);

uvec3 input_policy1_0_1 = uvec3(0u);

int gen_gl_VertexIndex_1 = 0;

int gen_gl_BaseVertex_1 = 0;

gen_gl_PerVertex unnamed = gen_gl_PerVertex(vec4(0.0, 0.0, 0.0, 1.0), 1.0, float[1](0.0), float[1](0.0));

vec4 entryPointParam_vertexMain_paint_0_ = vec4(0.0);

vec3 entryPointParam_vertexMain_texcoord_layer_0_ = vec3(0.0);

ivec2 entryPointParam_vertexMain_info_0_ = ivec2(0);

uvec4 entryPointParam_vertexMain_policy0_0_ = uvec4(0u);

uvec3 entryPointParam_vertexMain_policy1_0_ = uvec3(0u);

vec4 entryPointParam_vertexMain_x_targets0_0_ = vec4(0.0);

vec4 entryPointParam_vertexMain_x_targets1_0_ = vec4(0.0);

vec4 entryPointParam_vertexMain_x_targets2_0_ = vec4(0.0);

vec4 entryPointParam_vertexMain_x_targets3_0_ = vec4(0.0);

vec4 entryPointParam_vertexMain_y_targets0_0_ = vec4(0.0);

vec4 entryPointParam_vertexMain_y_targets1_0_ = vec4(0.0);

vec4 entryPointParam_vertexMain_y_targets2_0_ = vec4(0.0);

vec4 entryPointParam_vertexMain_y_targets3_0_ = vec4(0.0);

uvec4 entryPointParam_vertexMain_x_sources_0_ = uvec4(0u);

uvec4 entryPointParam_vertexMain_y_sources_0_ = uvec4(0u);

layout(location = 0) in vec4 _p2vs_location0;
layout(location = 1) in vec4 _p2vs_location1;
layout(location = 2) in vec2 _p2vs_location2;
layout(location = 3) in uvec2 _p2vs_location3;
layout(location = 4) in vec4 _p2vs_location4;
layout(location = 5) in vec4 _p2vs_location5;
layout(location = 6) in vec4 _p2vs_location6;
layout(location = 7) in uvec4 _p2vs_location7;
layout(location = 8) in uvec3 _p2vs_location8;
smooth out vec4 _vs2fs_location0;
smooth out vec3 _vs2fs_location1;
flat out ivec2 _vs2fs_location2;
flat out uvec4 _vs2fs_location3;
flat out uvec3 _vs2fs_location4;
flat out vec4 _vs2fs_location5;
flat out vec4 _vs2fs_location6;
flat out vec4 _vs2fs_location7;
flat out vec4 _vs2fs_location8;
flat out vec4 _vs2fs_location9;
flat out vec4 _vs2fs_location10;
flat out vec4 _vs2fs_location11;
flat out vec4 _vs2fs_location12;
flat out uvec4 _vs2fs_location13;
flat out uvec4 _vs2fs_location14;

void snailAhPackAxis_0_u0028_i1_u003b_f1_u005b_16_u005d_u003b_i1_u005b_16_u005d_u003b_vf4_u005b_4_u005d_u003b_vu4_u003b(inout int count_1_, inout float targets_1_[16], inout int sources_0_[16], inout vec4 packedTargets_1_[4], inout uvec4 packedSources_1_) {
    int i_4_ = 0;
    int _S63_ = 0;
    int _S64_ = 0;
    uint _S65_ = 0u;
    i_4_ = 0;
    while(true) {
        int _e106 = i_4_;
        if ((_e106 < 4)) {
        } else {
            break;
        }
        int _e108 = i_4_;
        packedTargets_1_[_e108] = vec4(0.0, 0.0, 0.0, 0.0);
        int _e110 = i_4_;
        i_4_ = (_e110 + 1);
        continue;
    }
    packedSources_1_ = uvec4(4294967295u, 4294967295u, 4294967295u, 4294967295u);
    int _e112 = count_1_;
    if ((_e112 > 16)) {
        uint _e115 = packedSources_1_[0u];
        packedSources_1_[0u] = ((_e115 & 4294967040u) | 254u);
        return;
    }
    i_4_ = 0;
    while(true) {
        int _e119 = i_4_;
        if ((_e119 < 16)) {
        } else {
            break;
        }
        int _e121 = i_4_;
        int _e122 = count_1_;
        if ((_e121 >= _e122)) {
            break;
        }
        int _e124 = i_4_;
        _S63_ = (_e124 >> uint(2));
        int _e127 = i_4_;
        _S64_ = (_e127 & 3);
        int _e129 = _S63_;
        int _e130 = _S64_;
        int _e131 = i_4_;
        float _e133 = targets_1_[_e131];
        packedTargets_1_[_e129][_e130] = _e133;
        int _e136 = _S64_;
        _S65_ = uint((_e136 * 8));
        int _e139 = _S63_;
        int _e140 = _S63_;
        uint _e142 = packedSources_1_[_e140];
        uint _e143 = _S65_;
        int _e148 = i_4_;
        int _e150 = sources_0_[_e148];
        uint _e153 = _S65_;
        packedSources_1_[_e139] = ((_e142 & ~((255u << _e143))) | ((uint(_e150) & 255u) << _e153));
        int _e158 = i_4_;
        i_4_ = (_e158 + 1);
        continue;
    }
    return;
}

float snailAhStandardWidth_0_u0028_f1_u003b_f1_u003b_f1_u003b(inout float raw_0_, inout float standard_0_, inout float ratio_0_) {
    bool _S39_ = false;
    float _S40_ = 0.0;
    float _e102 = standard_0_;
    if ((_e102 > 0.0)) {
        float _e104 = raw_0_;
        float _e105 = standard_0_;
        float _e108 = ratio_0_;
        float _e109 = standard_0_;
        _S39_ = (abs((_e104 - _e105)) <= (_e108 * _e109));
    } else {
        _S39_ = false;
    }
    bool _e112 = _S39_;
    if (_e112) {
        float _e113 = standard_0_;
        _S40_ = _e113;
    } else {
        float _e114 = raw_0_;
        _S40_ = _e114;
    }
    float _e115 = _S40_;
    return _e115;
}

float snailAhSnap_0_u0028_f1_u003b_f1_u003b(inout float v_1_, inout float scale_1_) {
    float _e99 = v_1_;
    float _e100 = scale_1_;
    float _e103 = scale_1_;
    return (roundEven((_e99 * _e100)) / _e103);
}

ivec2 snailAhLayerLoc_0_u0028_t21_u003b_vi2_u003b_i1_u003b(highp sampler2D layer_tex_0_, inout ivec2 base_0_, inout int offset_0_) {
    uint uw_0_ = 0u;
    int width_0_ = 0;
    int texel_0_ = 0;
    int _S31_ = 0;
    int _S32_ = 0;
    uw_0_ = uint(ivec2(uvec2(textureSize(layer_tex_0_, 0).xy)).x);
    uint _e109 = uw_0_;
    width_0_ = int(_e109);
    int _e112 = base_0_[1u];
    int _e113 = width_0_;
    int _e116 = base_0_[0u];
    int _e118 = offset_0_;
    texel_0_ = (((_e112 * _e113) + _e116) + _e118);
    int _e120 = texel_0_;
    int _e121 = width_0_;
    _S31_ = (_e120 - (int(floor((float(_e120) / float(_e121)))) * _e121));
    int _e129 = texel_0_;
    int _e130 = width_0_;
    _S32_ = (_e129 / _e130);
    int _e132 = _S31_;
    int _e133 = _S32_;
    return ivec2(_e132, _e133);
}

float snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(highp sampler2D layer_tex_1_, inout ivec2 info_base_0_, inout int block_0_, inout int i_1_) {
    int f_0_ = 0;
    ivec2 _S33_ = ivec2(0);
    ivec2 param = ivec2(0);
    int param_1 = 0;
    ivec3 _S34_ = ivec3(0);
    vec4 t_0_ = vec4(0.0);
    int c_1_ = 0;
    float _S35_ = 0.0;
    int _e109 = block_0_;
    int _e110 = i_1_;
    f_0_ = (_e109 + _e110);
    int _e112 = f_0_;
    ivec2 _e115 = info_base_0_;
    param = _e115;
    param_1 = (_e112 >> uint(2));
    ivec2 _e116 = snailAhLayerLoc_0_u0028_t21_u003b_vi2_u003b_i1_u003b(layer_tex_1_, param, param_1);
    _S33_ = _e116;
    ivec2 _e117 = _S33_;
    _S34_ = ivec3(_e117.x, _e117.y, 0);
    ivec3 _e121 = _S34_;
    int _e124 = _S34_[2u];
    vec4 _e125 = texelFetch(layer_tex_1_, _e121.xy, _e124);
    t_0_ = _e125;
    int _e126 = f_0_;
    c_1_ = (_e126 & 3);
    int _e128 = c_1_;
    if ((_e128 == 0)) {
        float _e131 = t_0_[0u];
        _S35_ = _e131;
    } else {
        int _e132 = c_1_;
        if ((_e132 == 1)) {
            float _e135 = t_0_[1u];
            _S35_ = _e135;
        } else {
            int _e136 = c_1_;
            if ((_e136 == 2)) {
                float _e139 = t_0_[2u];
                _S35_ = _e139;
            } else {
                float _e141 = t_0_[3u];
                _S35_ = _e141;
            }
        }
    }
    float _e142 = _S35_;
    return _e142;
}

bool snailAhFinite_0_u0028_f1_u003b(inout float v_0_) {
    bool _S18_ = false;
    float _e99 = v_0_;
    if (!(isnan(_e99))) {
        float _e102 = v_0_;
        _S18_ = !(isinf(_e102));
    } else {
        _S18_ = false;
    }
    bool _e105 = _S18_;
    return _e105;
}

bool snailFitAutohintAxis_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b_i1_u003b_f1_u003b_f1_u003b_f1_u003b_struct_u002d_SnailAutohintPolicy_0_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f11_u003b_i1_u003b_f1_u005b_16_u005d_u003b_f1_u005b_16_u005d_u003b_i1_u005b_16_u005d_u003b(highp sampler2D layer_tex_2_, inout ivec2 info_base_1_, inout int axis_0_, inout int run_0_, inout int blueCount_0_, inout float standardWidth_0_, inout float left_0_, inout float scale_2_, inout SnailAutohintPolicy_0_ policy_0_, inout int knotCount_0_, inout float knotBase_0_[16], inout float knotTarget_0_[16], inout int knotSource_0_[16]) {
    int i_2_ = 0;
    float param_2 = 0.0;
    bool _S41_ = false;
    float param_3 = 0.0;
    bool _S42_ = false;
    float _S43_ = 0.0;
    ivec2 param_4 = ivec2(0);
    int param_5 = 0;
    int param_6 = 0;
    int n_1_ = 0;
    bool _S44_ = false;
    bool relative_0_ = false;
    float param_7 = 0.0;
    int f_1_ = 0;
    float _S48_ = 0.0;
    ivec2 param_8 = ivec2(0);
    int param_9 = 0;
    int param_10 = 0;
    float pos_1_[16] = float[16](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    float _S49_ = 0.0;
    ivec2 param_11 = ivec2(0);
    int param_12 = 0;
    int param_13 = 0;
    float width_1_[16] = float[16](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    float _S50_ = 0.0;
    ivec2 param_14 = ivec2(0);
    int param_15 = 0;
    int param_16 = 0;
    uint refs_0_ = 0u;
    int stem_0_[16] = int[16](0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    int blue_0_[16] = int[16](0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    float _S51_ = 0.0;
    ivec2 param_17 = ivec2(0);
    int param_18 = 0;
    int param_19 = 0;
    uint flags_0_ = 0u;
    bool rounded_0_[16] = bool[16](false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false);
    bool syntheticApex_0_[16] = bool[16](false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false);
    int stemMode_0_ = 0;
    int dir_0_[16] = int[16](0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    uint _S52_ = 0u;
    int encodedCompanion_0_ = 0;
    int clusterRight_0_ = 0;
    int companion_0_[16] = int[16](0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    bool anchorSet_0_ = false;
    bool hinted_0_[16] = bool[16](false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false);
    float param_20 = 0.0;
    bool _S47_ = false;
    float param_21 = 0.0;
    bool _S46_ = false;
    bool axisAligned_0_ = false;
    bool lowerBlue_0_ = false;
    bool upperBlue_0_ = false;
    bool _S45_ = false;
    int _S53_ = 0;
    float ref_0_ = 0.0;
    ivec2 param_22 = ivec2(0);
    int param_23 = 0;
    int param_24 = 0;
    float shoot_0_ = 0.0;
    ivec2 param_25 = ivec2(0);
    int param_26 = 0;
    int param_27 = 0;
    float param_28 = 0.0;
    float param_29 = 0.0;
    float spacing_0_ = 0.0;
    float ref_1_ = 0.0;
    ivec2 param_30 = ivec2(0);
    int param_31 = 0;
    int param_32 = 0;
    float shoot_1_ = 0.0;
    ivec2 param_33 = ivec2(0);
    int param_34 = 0;
    int param_35 = 0;
    float targets_0_[16] = float[16](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    float param_36 = 0.0;
    float param_37 = 0.0;
    float param_38 = 0.0;
    float param_39 = 0.0;
    float grid_0_ = 0.0;
    float maxPx_0_ = 0.0;
    float anchorTarget_0_ = 0.0;
    float anchorBase_0_ = 0.0;
    float clusterTarget_0_ = 0.0;
    float clusterBase_0_ = 0.0;
    float clusterDesiredRight_0_ = 0.0;
    int clusterStems_0_ = 0;
    int j_1_ = 0;
    int i_3_ = 0;
    float nominal_0_ = 0.0;
    float param_40 = 0.0;
    float param_41 = 0.0;
    float param_42 = 0.0;
    float _S54_ = 0.0;
    float bestGap_0_ = 0.0;
    float widthUnits_0_ = 0.0;
    float anchorBase_1_ = 0.0;
    float _S55_ = 0.0;
    float param_43 = 0.0;
    float param_44 = 0.0;
    float _S56_ = 0.0;
    int clusterStems_1_ = 0;
    float _S57_ = 0.0;
    float _S58_ = 0.0;
    float clusterTarget_1_ = 0.0;
    float clusterBase_1_ = 0.0;
    float clusterDesiredRight_1_ = 0.0;
    int b_0_ = 0;
    int j_0_ = 0;
    bool _S59_ = false;
    int i_3_1 = 0;
    float _S60_ = 0.0;
    bool top_0_ = false;
    int best_0_ = 0;
    bool knotBlueFixed_0_[16] = bool[16](false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false);
    bool knotNaturalSpacing_0_[16] = bool[16](false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false);
    int _S61_ = 0;
    float param_45 = 0.0;
    float param_46 = 0.0;
    int _S62_ = 0;
    float span_0_ = 0.0;
    float param_47 = 0.0;
    float param_48 = 0.0;
    knotCount_0_ = 0;
    i_2_ = 0;
    while(true) {
        int _e233 = i_2_;
        if ((_e233 < 16)) {
        } else {
            break;
        }
        int _e235 = i_2_;
        knotBase_0_[_e235] = 0.0;
        int _e237 = i_2_;
        knotTarget_0_[_e237] = 0.0;
        int _e239 = i_2_;
        knotSource_0_[_e239] = 0;
        int _e241 = i_2_;
        i_2_ = (_e241 + 1);
        continue;
    }
    float _e243 = scale_2_;
    param_2 = _e243;
    bool _e244 = snailAhFinite_0_u0028_f1_u003b(param_2);
    if (!(_e244)) {
        _S41_ = true;
    } else {
        float _e246 = scale_2_;
        _S41_ = (_e246 <= 0.0);
    }
    bool _e248 = _S41_;
    if (_e248) {
        _S41_ = true;
    } else {
        int _e249 = blueCount_0_;
        _S41_ = (_e249 < 0);
    }
    bool _e251 = _S41_;
    if (_e251) {
        _S41_ = true;
    } else {
        int _e252 = blueCount_0_;
        _S41_ = (_e252 > 16);
    }
    bool _e254 = _S41_;
    if (_e254) {
        _S41_ = true;
    } else {
        float _e255 = standardWidth_0_;
        param_3 = _e255;
        bool _e256 = snailAhFinite_0_u0028_f1_u003b(param_3);
        _S41_ = !(_e256);
    }
    bool _e258 = _S41_;
    if (_e258) {
        _S41_ = true;
    } else {
        float _e259 = standardWidth_0_;
        _S41_ = (_e259 < 0.0);
    }
    bool _e261 = _S41_;
    if (_e261) {
        return false;
    }
    int _e262 = axis_0_;
    _S42_ = (_e262 == 0);
    bool _e264 = _S42_;
    if (_e264) {
        int _e266 = policy_0_.xAlign_0_;
        _S41_ = (_e266 == 0);
    } else {
        _S41_ = false;
    }
    bool _e268 = _S41_;
    if (_e268) {
        int _e270 = policy_0_.xStem_0_;
        _S41_ = (_e270 == 0);
    } else {
        _S41_ = false;
    }
    bool _e272 = _S41_;
    if (_e272) {
        int _e274 = policy_0_.xPositioning_0_;
        _S41_ = (_e274 == 0);
    } else {
        _S41_ = false;
    }
    bool _e276 = _S41_;
    if (_e276) {
        int _e278 = policy_0_.xRegistration_0_;
        _S41_ = (_e278 == 0);
    } else {
        _S41_ = false;
    }
    bool _e280 = _S41_;
    if (_e280) {
        _S41_ = true;
    } else {
        int _e281 = axis_0_;
        if ((_e281 == 1)) {
            int _e284 = policy_0_.yAlign_0_;
            _S41_ = (_e284 == 0);
        } else {
            _S41_ = false;
        }
        bool _e286 = _S41_;
        if (_e286) {
            int _e288 = policy_0_.yStem_0_;
            _S41_ = (_e288 == 0);
        } else {
            _S41_ = false;
        }
        bool _e290 = _S41_;
        if (_e290) {
            int _e292 = policy_0_.yOvershoot_0_;
            _S41_ = (_e292 == 0);
        } else {
            _S41_ = false;
        }
    }
    bool _e294 = _S41_;
    if (_e294) {
        return true;
    }
    ivec2 _e295 = info_base_1_;
    param_4 = _e295;
    int _e296 = run_0_;
    param_5 = _e296;
    param_6 = 0;
    float _e297 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_4, param_5, param_6);
    _S43_ = _e297;
    float _e298 = _S43_;
    n_1_ = int(_e298);
    int _e300 = n_1_;
    if ((_e300 <= 0)) {
        _S41_ = true;
    } else {
        int _e302 = n_1_;
        _S41_ = (_e302 > 16);
    }
    bool _e304 = _S41_;
    if (_e304) {
        int _e305 = n_1_;
        return (_e305 == 0);
    }
    int _e307 = axis_0_;
    _S44_ = (_e307 == 1);
    bool _e309 = _S44_;
    if (_e309) {
        int _e311 = policy_0_.yAlign_0_;
        _S41_ = (_e311 == 2);
    } else {
        _S41_ = false;
    }
    bool _e313 = _S42_;
    if (_e313) {
        int _e315 = policy_0_.xRegistration_0_;
        relative_0_ = (_e315 == 1);
    } else {
        relative_0_ = false;
    }
    bool _e317 = relative_0_;
    if (_e317) {
        float _e318 = left_0_;
        param_7 = _e318;
        bool _e319 = snailAhFinite_0_u0028_f1_u003b(param_7);
        relative_0_ = !(_e319);
    } else {
        relative_0_ = false;
    }
    bool _e321 = relative_0_;
    if (_e321) {
        return false;
    }
    i_2_ = 0;
    while(true) {
        int _e322 = i_2_;
        if ((_e322 < 16)) {
        } else {
            break;
        }
        int _e324 = i_2_;
        int _e325 = n_1_;
        if ((_e324 >= _e325)) {
            break;
        }
        int _e327 = run_0_;
        int _e329 = i_2_;
        f_1_ = ((_e327 + 1) + (4 * _e329));
        ivec2 _e332 = info_base_1_;
        param_8 = _e332;
        int _e333 = f_1_;
        param_9 = _e333;
        param_10 = 0;
        float _e334 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_8, param_9, param_10);
        _S48_ = _e334;
        int _e335 = i_2_;
        float _e336 = _S48_;
        pos_1_[_e335] = _e336;
        ivec2 _e338 = info_base_1_;
        param_11 = _e338;
        int _e339 = f_1_;
        param_12 = _e339;
        param_13 = 1;
        float _e340 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_11, param_12, param_13);
        _S49_ = _e340;
        int _e341 = i_2_;
        float _e342 = _S49_;
        width_1_[_e341] = _e342;
        ivec2 _e344 = info_base_1_;
        param_14 = _e344;
        int _e345 = f_1_;
        param_15 = _e345;
        param_16 = 2;
        float _e346 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_14, param_15, param_16);
        _S50_ = _e346;
        float _e347 = _S50_;
        refs_0_ = floatBitsToUint(_e347);
        int _e349 = i_2_;
        uint _e350 = refs_0_;
        stem_0_[_e349] = (int((_e350 << 16u)) >> uint(16));
        int _e357 = i_2_;
        uint _e358 = refs_0_;
        blue_0_[_e357] = (int(_e358) >> uint(16));
        ivec2 _e363 = info_base_1_;
        param_17 = _e363;
        int _e364 = f_1_;
        param_18 = _e364;
        param_19 = 3;
        float _e365 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_17, param_18, param_19);
        _S51_ = _e365;
        float _e366 = _S51_;
        flags_0_ = floatBitsToUint(_e366);
        int _e368 = i_2_;
        uint _e369 = flags_0_;
        rounded_0_[_e368] = ((_e369 & 1u) != 0u);
        int _e373 = i_2_;
        uint _e374 = flags_0_;
        syntheticApex_0_[_e373] = ((_e374 & 2u) != 0u);
        uint _e378 = flags_0_;
        if (((_e378 & 4u) == 0u)) {
            return false;
        }
        uint _e381 = flags_0_;
        if (((_e381 & 8u) != 0u)) {
            stemMode_0_ = -1;
        } else {
            stemMode_0_ = 1;
        }
        int _e384 = i_2_;
        int _e385 = stemMode_0_;
        dir_0_[_e384] = _e385;
        bool _e387 = _S41_;
        if (_e387) {
            _S52_ = 10u;
        } else {
            _S52_ = 4u;
        }
        uint _e388 = flags_0_;
        uint _e389 = _S52_;
        encodedCompanion_0_ = int(((_e388 >> _e389) & 63u));
        int _e394 = encodedCompanion_0_;
        if ((_e394 >= 62)) {
            clusterRight_0_ = -1;
        } else {
            int _e396 = encodedCompanion_0_;
            clusterRight_0_ = _e396;
        }
        int _e397 = i_2_;
        int _e398 = clusterRight_0_;
        companion_0_[_e397] = _e398;
        int _e400 = encodedCompanion_0_;
        if ((_e400 >= 63)) {
            int _e402 = i_2_;
            bool _e404 = rounded_0_[_e402];
            relative_0_ = _e404;
        } else {
            relative_0_ = false;
        }
        bool _e405 = relative_0_;
        if (_e405) {
            int _e406 = i_2_;
            int _e408 = blue_0_[_e406];
            anchorSet_0_ = (_e408 >= 0);
        } else {
            anchorSet_0_ = false;
        }
        bool _e410 = anchorSet_0_;
        if (_e410) {
            return false;
        }
        int _e411 = i_2_;
        hinted_0_[_e411] = false;
        int _e413 = i_2_;
        float _e415 = pos_1_[_e413];
        param_20 = _e415;
        bool _e416 = snailAhFinite_0_u0028_f1_u003b(param_20);
        if (!(_e416)) {
            _S47_ = true;
        } else {
            int _e418 = i_2_;
            float _e420 = width_1_[_e418];
            param_21 = _e420;
            bool _e421 = snailAhFinite_0_u0028_f1_u003b(param_21);
            _S47_ = !(_e421);
        }
        bool _e423 = _S47_;
        if (_e423) {
            _S46_ = true;
        } else {
            int _e424 = i_2_;
            float _e426 = width_1_[_e424];
            _S46_ = (_e426 < 0.0);
        }
        bool _e428 = _S46_;
        if (_e428) {
            axisAligned_0_ = true;
        } else {
            int _e429 = i_2_;
            int _e431 = stem_0_[_e429];
            axisAligned_0_ = (_e431 < -1);
        }
        bool _e433 = axisAligned_0_;
        if (_e433) {
            lowerBlue_0_ = true;
        } else {
            int _e434 = i_2_;
            int _e436 = stem_0_[_e434];
            int _e437 = n_1_;
            lowerBlue_0_ = (_e436 >= _e437);
        }
        bool _e439 = lowerBlue_0_;
        if (_e439) {
            upperBlue_0_ = true;
        } else {
            int _e440 = i_2_;
            int _e442 = blue_0_[_e440];
            upperBlue_0_ = (_e442 < -1);
        }
        bool _e444 = upperBlue_0_;
        if (_e444) {
            _S45_ = true;
        } else {
            int _e445 = i_2_;
            int _e447 = blue_0_[_e445];
            int _e448 = blueCount_0_;
            _S45_ = (_e447 >= _e448);
        }
        bool _e450 = _S45_;
        if (_e450) {
            return false;
        }
        int _e451 = i_2_;
        i_2_ = (_e451 + 1);
        continue;
    }
    i_2_ = 0;
    while(true) {
        int _e453 = i_2_;
        if ((_e453 < 16)) {
        } else {
            break;
        }
        int _e455 = i_2_;
        int _e456 = blueCount_0_;
        if ((_e455 >= _e456)) {
            break;
        }
        int _e458 = i_2_;
        _S53_ = (2 * _e458);
        ivec2 _e460 = info_base_1_;
        param_22 = _e460;
        param_23 = 12;
        int _e461 = _S53_;
        param_24 = _e461;
        float _e462 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_22, param_23, param_24);
        ref_0_ = _e462;
        int _e463 = _S53_;
        ivec2 _e465 = info_base_1_;
        param_25 = _e465;
        param_26 = 12;
        param_27 = (_e463 + 1);
        float _e466 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_25, param_26, param_27);
        shoot_0_ = _e466;
        float _e467 = ref_0_;
        param_28 = _e467;
        bool _e468 = snailAhFinite_0_u0028_f1_u003b(param_28);
        if (!(_e468)) {
            relative_0_ = true;
        } else {
            float _e470 = shoot_0_;
            param_29 = _e470;
            bool _e471 = snailAhFinite_0_u0028_f1_u003b(param_29);
            relative_0_ = !(_e471);
        }
        bool _e473 = relative_0_;
        if (_e473) {
            return false;
        }
        int _e474 = i_2_;
        i_2_ = (_e474 + 1);
        continue;
    }
    bool _e476 = _S44_;
    if (_e476) {
        int _e478 = policy_0_.yOvershoot_0_;
        relative_0_ = (_e478 == 1);
    } else {
        relative_0_ = false;
    }
    bool _e480 = relative_0_;
    if (_e480) {
        float _e482 = policy_0_.overshootMinPx_0_;
        spacing_0_ = _e482;
    } else {
        spacing_0_ = 0.0;
    }
    i_2_ = 0;
    while(true) {
        int _e483 = i_2_;
        if ((_e483 < 16)) {
        } else {
            break;
        }
        int _e485 = i_2_;
        int _e486 = n_1_;
        if ((_e485 >= _e486)) {
            break;
        }
        int _e488 = i_2_;
        int _e490 = stem_0_[_e488];
        if ((_e490 >= 0)) {
            int _e492 = i_2_;
            int _e494 = stem_0_[_e492];
            float _e496 = pos_1_[_e494];
            int _e497 = i_2_;
            float _e499 = pos_1_[_e497];
            relative_0_ = (_e496 > _e499);
        } else {
            relative_0_ = false;
        }
        bool _e501 = _S41_;
        if (_e501) {
            int _e502 = i_2_;
            int _e504 = blue_0_[_e502];
            anchorSet_0_ = (_e504 >= 0);
        } else {
            anchorSet_0_ = false;
        }
        bool _e506 = _S41_;
        if (!(_e506)) {
            bool _e508 = relative_0_;
            if (_e508) {
                stemMode_0_ = -1;
            } else {
                stemMode_0_ = 1;
            }
            int _e509 = i_2_;
            int _e510 = stemMode_0_;
            dir_0_[_e509] = _e510;
        }
        bool _e512 = anchorSet_0_;
        if (_e512) {
            int _e513 = i_2_;
            int _e515 = blue_0_[_e513];
            ivec2 _e517 = info_base_1_;
            param_30 = _e517;
            param_31 = 12;
            param_32 = (2 * _e515);
            float _e518 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_30, param_31, param_32);
            ref_1_ = _e518;
            int _e519 = i_2_;
            int _e521 = blue_0_[_e519];
            ivec2 _e524 = info_base_1_;
            param_33 = _e524;
            param_34 = 12;
            param_35 = ((2 * _e521) + 1);
            float _e525 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_33, param_34, param_35);
            shoot_1_ = _e525;
            int _e526 = i_2_;
            bool _e528 = rounded_0_[_e526];
            if (_e528) {
                bool _e529 = _S44_;
                _S47_ = _e529;
            } else {
                _S47_ = false;
            }
            bool _e530 = _S47_;
            if (_e530) {
                int _e532 = policy_0_.yOvershoot_0_;
                _S46_ = (_e532 == 0);
            } else {
                _S46_ = false;
            }
            bool _e534 = _S46_;
            if (_e534) {
                int _e535 = i_2_;
                int _e536 = i_2_;
                float _e538 = pos_1_[_e536];
                targets_0_[_e535] = _e538;
            } else {
                int _e540 = i_2_;
                float _e541 = ref_1_;
                param_36 = _e541;
                float _e542 = scale_2_;
                param_37 = _e542;
                float _e543 = snailAhSnap_0_u0028_f1_u003b_f1_u003b(param_36, param_37);
                targets_0_[_e540] = _e543;
                int _e545 = i_2_;
                bool _e547 = rounded_0_[_e545];
                if (_e547) {
                    float _e548 = shoot_1_;
                    float _e549 = ref_1_;
                    float _e551 = scale_2_;
                    float _e554 = spacing_0_;
                    axisAligned_0_ = (abs(((_e548 - _e549) * _e551)) >= _e554);
                } else {
                    axisAligned_0_ = false;
                }
                bool _e556 = axisAligned_0_;
                if (_e556) {
                    int _e557 = i_2_;
                    int _e558 = i_2_;
                    float _e560 = targets_0_[_e558];
                    float _e561 = shoot_1_;
                    float _e562 = ref_1_;
                    targets_0_[_e557] = (_e560 + (_e561 - _e562));
                }
            }
        } else {
            int _e566 = i_2_;
            int _e567 = i_2_;
            float _e569 = pos_1_[_e567];
            param_38 = _e569;
            float _e570 = scale_2_;
            param_39 = _e570;
            float _e571 = snailAhSnap_0_u0028_f1_u003b_f1_u003b(param_38, param_39);
            targets_0_[_e566] = _e571;
        }
        int _e573 = i_2_;
        i_2_ = (_e573 + 1);
        continue;
    }
    float _e575 = scale_2_;
    grid_0_ = (1.0 / _e575);
    bool _e577 = _S42_;
    if (_e577) {
        int _e579 = policy_0_.xStem_0_;
        stemMode_0_ = _e579;
    } else {
        int _e581 = policy_0_.yStem_0_;
        stemMode_0_ = _e581;
    }
    bool _e582 = _S42_;
    if (_e582) {
        float _e584 = policy_0_.xRatio_0_;
        spacing_0_ = _e584;
    } else {
        float _e586 = policy_0_.yRatio_0_;
        spacing_0_ = _e586;
    }
    bool _e587 = _S42_;
    if (_e587) {
        float _e589 = policy_0_.xMaxPx_0_;
        maxPx_0_ = _e589;
    } else {
        float _e591 = policy_0_.yMaxPx_0_;
        maxPx_0_ = _e591;
    }
    bool _e592 = _S42_;
    if (_e592) {
        int _e594 = policy_0_.xAlign_0_;
        _S41_ = (_e594 == 1);
    } else {
        int _e597 = policy_0_.yAlign_0_;
        _S41_ = (_e597 != 0);
    }
    bool _e599 = _S42_;
    if (_e599) {
        int _e601 = policy_0_.xPositioning_0_;
        relative_0_ = (_e601 == 1);
    } else {
        relative_0_ = false;
    }
    anchorSet_0_ = false;
    anchorTarget_0_ = 0.0;
    anchorBase_0_ = 0.0;
    clusterTarget_0_ = 0.0;
    clusterBase_0_ = 0.0;
    clusterDesiredRight_0_ = 0.0;
    clusterRight_0_ = 0;
    i_2_ = 0;
    clusterStems_0_ = 0;
    while(true) {
        int _e603 = i_2_;
        if ((_e603 < 16)) {
        } else {
            break;
        }
        int _e605 = i_2_;
        int _e606 = n_1_;
        if ((_e605 >= _e606)) {
            break;
        }
        int _e608 = i_2_;
        int _e610 = stem_0_[_e608];
        j_1_ = _e610;
        int _e611 = i_2_;
        int _e613 = stem_0_[_e611];
        if ((_e613 < 0)) {
            _S47_ = true;
        } else {
            int _e615 = j_1_;
            int _e616 = i_2_;
            _S47_ = (_e615 <= _e616);
        }
        bool _e618 = _S47_;
        if (_e618) {
            bool _e619 = anchorSet_0_;
            axisAligned_0_ = _e619;
            int _e620 = i_2_;
            i_3_ = (_e620 + 1);
            bool _e622 = axisAligned_0_;
            anchorSet_0_ = _e622;
            int _e623 = i_3_;
            i_2_ = _e623;
            continue;
        }
        int _e624 = i_2_;
        float _e626 = width_1_[_e624];
        param_40 = _e626;
        float _e627 = standardWidth_0_;
        param_41 = _e627;
        float _e628 = spacing_0_;
        param_42 = _e628;
        float _e629 = snailAhStandardWidth_0_u0028_f1_u003b_f1_u003b_f1_u003b(param_40, param_41, param_42);
        nominal_0_ = _e629;
        int _e630 = i_2_;
        float _e632 = width_1_[_e630];
        _S54_ = _e632;
        int _e633 = stemMode_0_;
        if ((_e633 == 2)) {
            _S46_ = true;
        } else {
            int _e635 = stemMode_0_;
            if ((_e635 == 1)) {
                float _e637 = nominal_0_;
                float _e638 = scale_2_;
                float _e640 = maxPx_0_;
                _S46_ = ((_e637 * _e638) < _e640);
            } else {
                _S46_ = false;
            }
        }
        bool _e642 = _S46_;
        if (_e642) {
            float _e643 = nominal_0_;
            float _e644 = scale_2_;
            float _e648 = grid_0_;
            bestGap_0_ = (max(roundEven((_e643 * _e644)), 1.0) * _e648);
        } else {
            float _e650 = _S54_;
            bestGap_0_ = _e650;
        }
        bool _e651 = relative_0_;
        if (_e651) {
            bool _e652 = anchorSet_0_;
            if (_e652) {
                int _e653 = i_2_;
                float _e654 = anchorTarget_0_;
                int _e655 = i_2_;
                float _e657 = pos_1_[_e655];
                float _e658 = anchorBase_0_;
                float _e660 = scale_2_;
                float _e663 = grid_0_;
                targets_0_[_e653] = (_e654 + (roundEven(((_e657 - _e658) * _e660)) * _e663));
                float _e667 = clusterTarget_0_;
                widthUnits_0_ = _e667;
                float _e668 = clusterBase_0_;
                anchorBase_1_ = _e668;
                bool _e669 = anchorSet_0_;
                axisAligned_0_ = _e669;
            } else {
                int _e670 = i_2_;
                float _e672 = pos_1_[_e670];
                param_43 = _e672;
                float _e673 = scale_2_;
                param_44 = _e673;
                float _e674 = snailAhSnap_0_u0028_f1_u003b_f1_u003b(param_43, param_44);
                _S55_ = _e674;
                int _e675 = i_2_;
                float _e676 = _S55_;
                targets_0_[_e675] = _e676;
                float _e678 = _S55_;
                widthUnits_0_ = _e678;
                int _e679 = i_2_;
                float _e681 = pos_1_[_e679];
                anchorBase_1_ = _e681;
                axisAligned_0_ = true;
            }
            int _e682 = j_1_;
            int _e683 = i_2_;
            float _e685 = targets_0_[_e683];
            float _e686 = bestGap_0_;
            targets_0_[_e682] = (_e685 + _e686);
            float _e689 = widthUnits_0_;
            int _e690 = i_2_;
            float _e692 = pos_1_[_e690];
            float _e693 = anchorBase_1_;
            float _e695 = scale_2_;
            float _e698 = grid_0_;
            float _e701 = bestGap_0_;
            _S56_ = ((_e689 + (roundEven(((_e692 - _e693) * _e695)) * _e698)) + _e701);
            int _e703 = clusterStems_0_;
            clusterStems_1_ = (_e703 + 1);
            float _e705 = widthUnits_0_;
            _S57_ = _e705;
            float _e706 = anchorBase_1_;
            _S58_ = _e706;
            int _e707 = i_2_;
            float _e709 = targets_0_[_e707];
            widthUnits_0_ = _e709;
            int _e710 = i_2_;
            float _e712 = pos_1_[_e710];
            anchorBase_1_ = _e712;
            float _e713 = _S57_;
            clusterTarget_1_ = _e713;
            float _e714 = _S58_;
            clusterBase_1_ = _e714;
            float _e715 = _S56_;
            clusterDesiredRight_1_ = _e715;
            int _e716 = j_1_;
            b_0_ = _e716;
            int _e717 = clusterStems_1_;
            j_0_ = _e717;
        } else {
            bool _e718 = _S42_;
            if (_e718) {
                int _e720 = policy_0_.xAlign_0_;
                axisAligned_0_ = (_e720 != 0);
            } else {
                int _e723 = policy_0_.yAlign_0_;
                axisAligned_0_ = (_e723 != 0);
            }
            bool _e725 = axisAligned_0_;
            if (_e725) {
                int _e726 = i_2_;
                int _e728 = blue_0_[_e726];
                lowerBlue_0_ = (_e728 >= 0);
            } else {
                lowerBlue_0_ = false;
            }
            bool _e730 = axisAligned_0_;
            if (_e730) {
                int _e731 = j_1_;
                int _e733 = blue_0_[_e731];
                upperBlue_0_ = (_e733 >= 0);
            } else {
                upperBlue_0_ = false;
            }
            bool _e735 = _S41_;
            if (!(_e735)) {
                int _e737 = i_2_;
                int _e738 = i_2_;
                float _e740 = pos_1_[_e738];
                targets_0_[_e737] = _e740;
            }
            bool _e742 = upperBlue_0_;
            if (_e742) {
                bool _e743 = lowerBlue_0_;
                _S45_ = !(_e743);
            } else {
                _S45_ = false;
            }
            bool _e745 = _S45_;
            if (_e745) {
                bool _e746 = _S41_;
                _S59_ = _e746;
            } else {
                _S59_ = false;
            }
            bool _e747 = _S59_;
            if (_e747) {
                int _e748 = i_2_;
                int _e749 = j_1_;
                float _e751 = targets_0_[_e749];
                float _e752 = bestGap_0_;
                targets_0_[_e748] = (_e751 - _e752);
            } else {
                int _e755 = j_1_;
                int _e756 = i_2_;
                float _e758 = targets_0_[_e756];
                float _e759 = bestGap_0_;
                targets_0_[_e755] = (_e758 + _e759);
            }
            bool _e762 = anchorSet_0_;
            axisAligned_0_ = _e762;
            float _e763 = anchorTarget_0_;
            widthUnits_0_ = _e763;
            float _e764 = anchorBase_0_;
            anchorBase_1_ = _e764;
            float _e765 = clusterTarget_0_;
            clusterTarget_1_ = _e765;
            float _e766 = clusterBase_0_;
            clusterBase_1_ = _e766;
            float _e767 = clusterDesiredRight_0_;
            clusterDesiredRight_1_ = _e767;
            int _e768 = clusterRight_0_;
            b_0_ = _e768;
            int _e769 = clusterStems_0_;
            j_0_ = _e769;
        }
        int _e770 = i_2_;
        hinted_0_[_e770] = true;
        int _e772 = j_1_;
        hinted_0_[_e772] = true;
        float _e774 = widthUnits_0_;
        anchorTarget_0_ = _e774;
        float _e775 = anchorBase_1_;
        anchorBase_0_ = _e775;
        float _e776 = clusterTarget_1_;
        clusterTarget_0_ = _e776;
        float _e777 = clusterBase_1_;
        clusterBase_0_ = _e777;
        float _e778 = clusterDesiredRight_1_;
        clusterDesiredRight_0_ = _e778;
        int _e779 = b_0_;
        clusterRight_0_ = _e779;
        int _e780 = j_0_;
        clusterStems_0_ = _e780;
        int _e781 = i_2_;
        i_3_1 = (_e781 + 1);
        bool _e783 = axisAligned_0_;
        anchorSet_0_ = _e783;
        int _e784 = i_3_1;
        i_2_ = _e784;
        continue;
    }
    bool _e785 = relative_0_;
    if (_e785) {
        int _e786 = clusterStems_0_;
        _S41_ = (_e786 > 1);
    } else {
        _S41_ = false;
    }
    bool _e788 = _S41_;
    if (_e788) {
        float _e789 = clusterDesiredRight_0_;
        int _e790 = clusterRight_0_;
        float _e792 = targets_0_[_e790];
        _S60_ = (_e789 - _e792);
        i_2_ = 0;
        while(true) {
            int _e794 = i_2_;
            if ((_e794 < 16)) {
            } else {
                break;
            }
            int _e796 = i_2_;
            int _e797 = n_1_;
            if ((_e796 >= _e797)) {
                break;
            }
            int _e799 = i_2_;
            bool _e801 = hinted_0_[_e799];
            if (_e801) {
                int _e802 = i_2_;
                int _e803 = i_2_;
                float _e805 = targets_0_[_e803];
                float _e806 = _S60_;
                targets_0_[_e802] = (_e805 + _e806);
            }
            int _e809 = i_2_;
            i_2_ = (_e809 + 1);
            continue;
        }
    }
    int _e811 = stemMode_0_;
    if ((_e811 == 1)) {
        float _e813 = maxPx_0_;
        spacing_0_ = _e813;
    } else {
        spacing_0_ = 1.6;
    }
    i_2_ = 0;
    while(true) {
        int _e814 = i_2_;
        if ((_e814 < 16)) {
        } else {
            break;
        }
        int _e816 = i_2_;
        int _e817 = n_1_;
        if ((_e816 >= _e817)) {
            break;
        }
        bool _e819 = _S42_;
        if (_e819) {
            int _e821 = policy_0_.xAlign_0_;
            axisAligned_0_ = (_e821 != 0);
        } else {
            int _e824 = policy_0_.yAlign_0_;
            axisAligned_0_ = (_e824 != 0);
        }
        bool _e826 = axisAligned_0_;
        if (!(_e826)) {
            _S41_ = true;
        } else {
            int _e828 = i_2_;
            int _e830 = blue_0_[_e828];
            _S41_ = (_e830 < 0);
        }
        bool _e832 = _S41_;
        if (_e832) {
            relative_0_ = true;
        } else {
            int _e833 = i_2_;
            bool _e835 = rounded_0_[_e833];
            relative_0_ = !(_e835);
        }
        bool _e837 = relative_0_;
        if (_e837) {
            anchorSet_0_ = true;
        } else {
            int _e838 = i_2_;
            bool _e840 = hinted_0_[_e838];
            anchorSet_0_ = _e840;
        }
        bool _e841 = anchorSet_0_;
        if (_e841) {
            int _e842 = i_2_;
            i_2_ = (_e842 + 1);
            continue;
        }
        int _e844 = i_2_;
        int _e846 = dir_0_[_e844];
        top_0_ = (_e846 > 0);
        int _e848 = i_2_;
        int _e850 = companion_0_[_e848];
        best_0_ = _e850;
        int _e851 = i_2_;
        int _e853 = companion_0_[_e851];
        if ((_e853 >= 0)) {
            bool _e855 = top_0_;
            if (_e855) {
                int _e856 = i_2_;
                float _e858 = pos_1_[_e856];
                int _e859 = best_0_;
                float _e861 = pos_1_[_e859];
                maxPx_0_ = (_e858 - _e861);
            } else {
                int _e863 = best_0_;
                float _e865 = pos_1_[_e863];
                int _e866 = i_2_;
                float _e868 = pos_1_[_e866];
                maxPx_0_ = (_e865 - _e868);
            }
            int _e870 = best_0_;
            b_0_ = _e870;
            float _e871 = maxPx_0_;
            bestGap_0_ = _e871;
        } else {
            int _e872 = best_0_;
            if ((_e872 == -2)) {
                bestGap_0_ = 3.4028235e38;
                int _e874 = best_0_;
                b_0_ = _e874;
                j_0_ = 0;
                while(true) {
                    int _e875 = j_0_;
                    if ((_e875 < 16)) {
                    } else {
                        break;
                    }
                    int _e877 = j_0_;
                    int _e878 = n_1_;
                    if ((_e877 >= _e878)) {
                        break;
                    }
                    int _e880 = j_0_;
                    int _e881 = i_2_;
                    if ((_e880 == _e881)) {
                        _S47_ = true;
                    } else {
                        int _e883 = j_0_;
                        int _e885 = dir_0_[_e883];
                        int _e886 = i_2_;
                        int _e888 = dir_0_[_e886];
                        _S47_ = (_e885 == _e888);
                    }
                    bool _e890 = _S47_;
                    if (_e890) {
                        int _e891 = j_0_;
                        j_0_ = (_e891 + 1);
                        continue;
                    }
                    bool _e893 = top_0_;
                    if (_e893) {
                        int _e894 = i_2_;
                        float _e896 = pos_1_[_e894];
                        int _e897 = j_0_;
                        float _e899 = pos_1_[_e897];
                        widthUnits_0_ = (_e896 - _e899);
                    } else {
                        int _e901 = j_0_;
                        float _e903 = pos_1_[_e901];
                        int _e904 = i_2_;
                        float _e906 = pos_1_[_e904];
                        widthUnits_0_ = (_e903 - _e906);
                    }
                    float _e908 = widthUnits_0_;
                    if ((_e908 <= 0.0)) {
                        _S46_ = true;
                    } else {
                        float _e910 = widthUnits_0_;
                        float _e911 = bestGap_0_;
                        _S46_ = (_e910 >= _e911);
                    }
                    bool _e913 = _S46_;
                    if (_e913) {
                        int _e914 = j_0_;
                        j_0_ = (_e914 + 1);
                        continue;
                    }
                    float _e916 = widthUnits_0_;
                    bestGap_0_ = _e916;
                    int _e917 = j_0_;
                    b_0_ = _e917;
                    int _e918 = j_0_;
                    j_0_ = (_e918 + 1);
                    continue;
                }
            } else {
                int _e920 = best_0_;
                b_0_ = _e920;
                bestGap_0_ = 3.4028235e38;
            }
        }
        int _e921 = b_0_;
        if ((_e921 < 0)) {
            _S47_ = true;
        } else {
            int _e923 = b_0_;
            bool _e925 = hinted_0_[_e923];
            _S47_ = _e925;
        }
        bool _e926 = _S47_;
        if (_e926) {
            _S46_ = true;
        } else {
            int _e927 = b_0_;
            int _e929 = blue_0_[_e927];
            _S46_ = (_e929 >= 0);
        }
        bool _e931 = _S46_;
        if (_e931) {
            lowerBlue_0_ = true;
        } else {
            float _e932 = bestGap_0_;
            float _e933 = scale_2_;
            float _e935 = spacing_0_;
            lowerBlue_0_ = ((_e932 * _e933) >= _e935);
        }
        bool _e937 = lowerBlue_0_;
        if (_e937) {
            int _e938 = i_2_;
            i_2_ = (_e938 + 1);
            continue;
        }
        int _e940 = b_0_;
        bool _e942 = syntheticApex_0_[_e940];
        if (_e942) {
            float _e943 = bestGap_0_;
            widthUnits_0_ = _e943;
        } else {
            float _e944 = bestGap_0_;
            float _e945 = scale_2_;
            float _e949 = grid_0_;
            widthUnits_0_ = (max(roundEven((_e944 * _e945)), 1.0) * _e949);
        }
        bool _e951 = top_0_;
        if (_e951) {
            int _e952 = i_2_;
            float _e954 = targets_0_[_e952];
            float _e955 = widthUnits_0_;
            maxPx_0_ = (_e954 - _e955);
        } else {
            int _e957 = i_2_;
            float _e959 = targets_0_[_e957];
            float _e960 = widthUnits_0_;
            maxPx_0_ = (_e959 + _e960);
        }
        int _e962 = b_0_;
        float _e963 = maxPx_0_;
        targets_0_[_e962] = _e963;
        int _e965 = b_0_;
        hinted_0_[_e965] = true;
        int _e967 = i_2_;
        i_2_ = (_e967 + 1);
        continue;
    }
    i_2_ = 0;
    while(true) {
        int _e969 = i_2_;
        if ((_e969 < 16)) {
        } else {
            break;
        }
        int _e971 = i_2_;
        int _e972 = n_1_;
        if ((_e971 >= _e972)) {
            break;
        }
        bool _e974 = _S42_;
        if (_e974) {
            int _e976 = policy_0_.xAlign_0_;
            axisAligned_0_ = (_e976 != 0);
        } else {
            int _e979 = policy_0_.yAlign_0_;
            axisAligned_0_ = (_e979 != 0);
        }
        int _e981 = i_2_;
        bool _e983 = hinted_0_[_e981];
        if (!(_e983)) {
            bool _e985 = axisAligned_0_;
            if (_e985) {
                int _e986 = i_2_;
                int _e988 = blue_0_[_e986];
                _S41_ = (_e988 >= 0);
            } else {
                _S41_ = false;
            }
            bool _e990 = _S41_;
            _S41_ = !(_e990);
        } else {
            _S41_ = false;
        }
        bool _e992 = _S41_;
        if (_e992) {
            int _e993 = i_2_;
            i_2_ = (_e993 + 1);
            continue;
        }
        int _e995 = knotCount_0_;
        int _e996 = i_2_;
        float _e998 = pos_1_[_e996];
        knotBase_0_[_e995] = _e998;
        int _e1000 = knotCount_0_;
        int _e1001 = i_2_;
        float _e1003 = targets_0_[_e1001];
        knotTarget_0_[_e1000] = _e1003;
        bool _e1005 = axisAligned_0_;
        if (_e1005) {
            int _e1006 = i_2_;
            int _e1008 = blue_0_[_e1006];
            relative_0_ = (_e1008 >= 0);
        } else {
            relative_0_ = false;
        }
        int _e1010 = knotCount_0_;
        bool _e1011 = relative_0_;
        knotBlueFixed_0_[_e1010] = _e1011;
        int _e1013 = knotCount_0_;
        int _e1014 = i_2_;
        bool _e1016 = syntheticApex_0_[_e1014];
        knotNaturalSpacing_0_[_e1013] = _e1016;
        int _e1018 = knotCount_0_;
        int _e1019 = i_2_;
        knotSource_0_[_e1018] = _e1019;
        int _e1021 = knotCount_0_;
        knotCount_0_ = (_e1021 + 1);
        int _e1023 = i_2_;
        i_2_ = (_e1023 + 1);
        continue;
    }
    bool _e1025 = _S42_;
    if (_e1025) {
        int _e1027 = policy_0_.xRegistration_0_;
        _S41_ = (_e1027 == 1);
    } else {
        _S41_ = false;
    }
    bool _e1029 = _S41_;
    if (_e1029) {
        int _e1030 = knotCount_0_;
        _S41_ = (_e1030 > 0);
    } else {
        _S41_ = false;
    }
    bool _e1032 = _S41_;
    if (_e1032) {
        int _e1033 = knotCount_0_;
        _S41_ = (_e1033 < 16);
    } else {
        _S41_ = false;
    }
    bool _e1035 = _S41_;
    if (_e1035) {
        float _e1036 = left_0_;
        float _e1038 = knotBase_0_[0];
        float _e1039 = grid_0_;
        _S41_ = (_e1036 < (_e1038 - (0.25 * _e1039)));
    } else {
        _S41_ = false;
    }
    bool _e1043 = _S41_;
    if (_e1043) {
        i_2_ = 15;
        while(true) {
            int _e1044 = i_2_;
            if ((_e1044 > 0)) {
            } else {
                break;
            }
            int _e1046 = i_2_;
            int _e1047 = knotCount_0_;
            if ((_e1046 <= _e1047)) {
                int _e1049 = i_2_;
                _S61_ = (_e1049 - 1);
                int _e1051 = i_2_;
                int _e1052 = _S61_;
                float _e1054 = knotBase_0_[_e1052];
                knotBase_0_[_e1051] = _e1054;
                int _e1056 = i_2_;
                int _e1057 = _S61_;
                float _e1059 = knotTarget_0_[_e1057];
                knotTarget_0_[_e1056] = _e1059;
                int _e1061 = i_2_;
                int _e1062 = _S61_;
                bool _e1064 = knotBlueFixed_0_[_e1062];
                knotBlueFixed_0_[_e1061] = _e1064;
                int _e1066 = i_2_;
                int _e1067 = _S61_;
                bool _e1069 = knotNaturalSpacing_0_[_e1067];
                knotNaturalSpacing_0_[_e1066] = _e1069;
                int _e1071 = i_2_;
                int _e1072 = _S61_;
                int _e1074 = knotSource_0_[_e1072];
                knotSource_0_[_e1071] = _e1074;
            }
            int _e1076 = i_2_;
            i_2_ = (_e1076 - 1);
            continue;
        }
        float _e1078 = left_0_;
        knotBase_0_[0] = _e1078;
        float _e1080 = left_0_;
        param_45 = _e1080;
        float _e1081 = scale_2_;
        param_46 = _e1081;
        float _e1082 = snailAhSnap_0_u0028_f1_u003b_f1_u003b(param_45, param_46);
        knotTarget_0_[0] = _e1082;
        knotBlueFixed_0_[0] = false;
        knotNaturalSpacing_0_[0] = false;
        knotSource_0_[0] = 32;
        int _e1087 = knotCount_0_;
        knotCount_0_ = (_e1087 + 1);
    }
    b_0_ = 15;
    while(true) {
        int _e1089 = b_0_;
        if ((_e1089 > 0)) {
        } else {
            break;
        }
        int _e1091 = b_0_;
        int _e1092 = knotCount_0_;
        if ((_e1091 >= _e1092)) {
            _S41_ = true;
        } else {
            int _e1094 = b_0_;
            bool _e1096 = knotBlueFixed_0_[_e1094];
            _S41_ = !(_e1096);
        }
        bool _e1098 = _S41_;
        if (_e1098) {
            int _e1099 = b_0_;
            b_0_ = (_e1099 - 1);
            continue;
        }
        j_0_ = 15;
        while(true) {
            int _e1101 = j_0_;
            if ((_e1101 > 0)) {
            } else {
                break;
            }
            int _e1103 = j_0_;
            int _e1104 = b_0_;
            if ((_e1103 > _e1104)) {
                int _e1106 = j_0_;
                j_0_ = (_e1106 - 1);
                continue;
            }
            int _e1108 = j_0_;
            _S62_ = (_e1108 - 1);
            int _e1110 = _S62_;
            bool _e1112 = knotBlueFixed_0_[_e1110];
            if (_e1112) {
                break;
            }
            int _e1113 = _S62_;
            bool _e1115 = knotNaturalSpacing_0_[_e1113];
            if (_e1115) {
                spacing_0_ = 1e-6;
            } else {
                float _e1116 = grid_0_;
                spacing_0_ = _e1116;
            }
            int _e1117 = _S62_;
            int _e1118 = _S62_;
            float _e1120 = knotTarget_0_[_e1118];
            int _e1121 = j_0_;
            float _e1123 = knotTarget_0_[_e1121];
            float _e1124 = spacing_0_;
            knotTarget_0_[_e1117] = min(_e1120, (_e1123 - _e1124));
            int _e1128 = j_0_;
            j_0_ = (_e1128 - 1);
            continue;
        }
        int _e1130 = b_0_;
        b_0_ = (_e1130 - 1);
        continue;
    }
    i_2_ = 1;
    while(true) {
        int _e1132 = i_2_;
        if ((_e1132 < 16)) {
        } else {
            break;
        }
        int _e1134 = i_2_;
        int _e1135 = knotCount_0_;
        if ((_e1134 >= _e1135)) {
            break;
        }
        int _e1137 = i_2_;
        float _e1139 = knotTarget_0_[_e1137];
        int _e1140 = i_2_;
        float _e1143 = knotTarget_0_[(_e1140 - 1)];
        if ((_e1139 <= _e1143)) {
            int _e1145 = i_2_;
            int _e1146 = i_2_;
            float _e1149 = knotTarget_0_[(_e1146 - 1)];
            float _e1150 = grid_0_;
            knotTarget_0_[_e1145] = (_e1149 + _e1150);
        }
        int _e1153 = i_2_;
        i_2_ = (_e1153 + 1);
        continue;
    }
    int _e1156 = policy_0_.fadeEnabled_0_;
    if ((_e1156 != 0)) {
        float _e1158 = scale_2_;
        float _e1160 = policy_0_.fadeStart_0_;
        _S41_ = (_e1158 > _e1160);
    } else {
        _S41_ = false;
    }
    bool _e1162 = _S41_;
    if (_e1162) {
        float _e1164 = policy_0_.fadeFull_0_;
        float _e1166 = policy_0_.fadeStart_0_;
        span_0_ = (_e1164 - _e1166);
        float _e1168 = span_0_;
        if ((_e1168 <= 0.0)) {
            _S41_ = true;
        } else {
            float _e1170 = scale_2_;
            float _e1172 = policy_0_.fadeFull_0_;
            _S41_ = (_e1170 >= _e1172);
        }
        bool _e1174 = _S41_;
        if (_e1174) {
            spacing_0_ = 1.0;
        } else {
            float _e1175 = scale_2_;
            float _e1177 = policy_0_.fadeStart_0_;
            float _e1179 = span_0_;
            spacing_0_ = ((_e1175 - _e1177) / _e1179);
        }
        i_2_ = 0;
        while(true) {
            int _e1181 = i_2_;
            if ((_e1181 < 16)) {
            } else {
                break;
            }
            int _e1183 = i_2_;
            int _e1184 = knotCount_0_;
            if ((_e1183 >= _e1184)) {
                break;
            }
            int _e1186 = i_2_;
            int _e1187 = i_2_;
            float _e1189 = knotTarget_0_[_e1187];
            int _e1190 = i_2_;
            float _e1192 = knotBase_0_[_e1190];
            int _e1193 = i_2_;
            float _e1195 = knotTarget_0_[_e1193];
            float _e1197 = spacing_0_;
            knotTarget_0_[_e1186] = (_e1189 + ((_e1192 - _e1195) * _e1197));
            int _e1201 = i_2_;
            i_2_ = (_e1201 + 1);
            continue;
        }
    }
    i_2_ = 0;
    while(true) {
        int _e1203 = i_2_;
        if ((_e1203 < 16)) {
        } else {
            break;
        }
        int _e1205 = i_2_;
        int _e1206 = knotCount_0_;
        if ((_e1205 >= _e1206)) {
            break;
        }
        int _e1208 = i_2_;
        float _e1210 = knotBase_0_[_e1208];
        param_47 = _e1210;
        bool _e1211 = snailAhFinite_0_u0028_f1_u003b(param_47);
        if (!(_e1211)) {
            _S41_ = true;
        } else {
            int _e1213 = i_2_;
            float _e1215 = knotTarget_0_[_e1213];
            param_48 = _e1215;
            bool _e1216 = snailAhFinite_0_u0028_f1_u003b(param_48);
            _S41_ = !(_e1216);
        }
        bool _e1218 = _S41_;
        if (_e1218) {
            knotCount_0_ = 0;
            return false;
        }
        int _e1219 = i_2_;
        i_2_ = (_e1219 + 1);
        continue;
    }
    return true;
}

bool snailAhCount_0_u0028_i1_u003b_f1_u003b_i1_u003b(inout int max_knots_0_, inout float encoded_0_, inout int count_0_) {
    float param_49 = 0.0;
    bool _S38_ = false;
    float _e102 = encoded_0_;
    param_49 = _e102;
    bool _e103 = snailAhFinite_0_u0028_f1_u003b(param_49);
    if (!(_e103)) {
        _S38_ = true;
    } else {
        float _e105 = encoded_0_;
        _S38_ = (_e105 < 0.0);
    }
    bool _e107 = _S38_;
    if (_e107) {
        _S38_ = true;
    } else {
        float _e108 = encoded_0_;
        int _e109 = max_knots_0_;
        _S38_ = (_e108 > float(_e109));
    }
    bool _e112 = _S38_;
    if (_e112) {
        _S38_ = true;
    } else {
        float _e113 = encoded_0_;
        float _e115 = encoded_0_;
        _S38_ = (floor(_e113) != _e115);
    }
    bool _e117 = _S38_;
    if (_e117) {
        count_0_ = 0;
        return false;
    }
    float _e118 = encoded_0_;
    count_0_ = int(_e118);
    return true;
}

bool snailDecodeAutohintPolicy_0_u0028_vu4_u003b_vu3_u003b_struct_u002d_SnailAutohintPolicy_0_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f11_u003b(inout uvec4 p0_0_, inout uvec3 p1_0_, inout SnailAutohintPolicy_0_ p_1_) {
    uint x_0_ = 0u;
    uint y_0_ = 0u;
    bool _S36_ = false;
    int _S37_ = 0;
    float param_50 = 0.0;
    float param_51 = 0.0;
    float param_52 = 0.0;
    float param_53 = 0.0;
    float param_54 = 0.0;
    p_1_.xAlign_0_ = 0;
    p_1_.xStem_0_ = 0;
    p_1_.xPositioning_0_ = 0;
    p_1_.xRegistration_0_ = 0;
    p_1_.yAlign_0_ = 0;
    p_1_.yStem_0_ = 0;
    p_1_.yOvershoot_0_ = 0;
    p_1_.fadeEnabled_0_ = 0;
    p_1_.fadeStart_0_ = 0.0;
    p_1_.fadeFull_0_ = 0.0;
    p_1_.xRatio_0_ = 0.0;
    p_1_.xMaxPx_0_ = 0.0;
    p_1_.yRatio_0_ = 0.0;
    p_1_.yMaxPx_0_ = 0.0;
    p_1_.overshootMinPx_0_ = 0.0;
    uint _e125 = p0_0_[0u];
    x_0_ = _e125;
    uint _e127 = p0_0_[1u];
    y_0_ = _e127;
    uint _e128 = x_0_;
    if (((_e128 & 4286578688u) != 0u)) {
        _S36_ = true;
    } else {
        uint _e131 = y_0_;
        _S36_ = ((_e131 & 4294967232u) != 0u);
    }
    bool _e134 = _S36_;
    if (_e134) {
        return false;
    }
    uint _e135 = x_0_;
    _S37_ = int((_e135 & 3u));
    int _e138 = _S37_;
    p_1_.xAlign_0_ = _e138;
    uint _e140 = x_0_;
    p_1_.xStem_0_ = int(((_e140 >> 2u) & 3u));
    uint _e146 = x_0_;
    p_1_.xPositioning_0_ = int(((_e146 >> 4u) & 3u));
    uint _e152 = x_0_;
    p_1_.xRegistration_0_ = int(((_e152 >> 6u) & 3u));
    uint _e158 = x_0_;
    p_1_.fadeEnabled_0_ = int(((_e158 >> 8u) & 1u));
    uint _e164 = x_0_;
    p_1_.fadeStart_0_ = float(((_e164 >> 9u) & 127u));
    uint _e170 = x_0_;
    p_1_.fadeFull_0_ = float(((_e170 >> 16u) & 127u));
    uint _e176 = y_0_;
    p_1_.yAlign_0_ = int((_e176 & 3u));
    uint _e180 = y_0_;
    p_1_.yStem_0_ = int(((_e180 >> 2u) & 3u));
    uint _e186 = y_0_;
    p_1_.yOvershoot_0_ = int(((_e186 >> 4u) & 3u));
    int _e192 = _S37_;
    if ((_e192 > 1)) {
        _S36_ = true;
    } else {
        int _e195 = p_1_.xStem_0_;
        _S36_ = (_e195 > 2);
    }
    bool _e197 = _S36_;
    if (_e197) {
        _S36_ = true;
    } else {
        int _e199 = p_1_.xPositioning_0_;
        _S36_ = (_e199 > 1);
    }
    bool _e201 = _S36_;
    if (_e201) {
        _S36_ = true;
    } else {
        int _e203 = p_1_.xRegistration_0_;
        _S36_ = (_e203 > 1);
    }
    bool _e205 = _S36_;
    if (_e205) {
        _S36_ = true;
    } else {
        int _e207 = p_1_.yAlign_0_;
        _S36_ = (_e207 > 2);
    }
    bool _e209 = _S36_;
    if (_e209) {
        _S36_ = true;
    } else {
        int _e211 = p_1_.yStem_0_;
        _S36_ = (_e211 > 2);
    }
    bool _e213 = _S36_;
    if (_e213) {
        _S36_ = true;
    } else {
        int _e215 = p_1_.yOvershoot_0_;
        _S36_ = (_e215 > 1);
    }
    bool _e217 = _S36_;
    if (_e217) {
        return false;
    }
    uint _e219 = p0_0_[2u];
    p_1_.xRatio_0_ = uintBitsToFloat(_e219);
    uint _e223 = p0_0_[3u];
    p_1_.xMaxPx_0_ = uintBitsToFloat(_e223);
    uint _e227 = p1_0_[0u];
    p_1_.yRatio_0_ = uintBitsToFloat(_e227);
    uint _e231 = p1_0_[1u];
    p_1_.yMaxPx_0_ = uintBitsToFloat(_e231);
    uint _e235 = p1_0_[2u];
    p_1_.overshootMinPx_0_ = uintBitsToFloat(_e235);
    int _e239 = p_1_.xStem_0_;
    if ((_e239 != 0)) {
        float _e242 = p_1_.xRatio_0_;
        param_50 = _e242;
        bool _e243 = snailAhFinite_0_u0028_f1_u003b(param_50);
        if (!(_e243)) {
            _S36_ = true;
        } else {
            float _e246 = p_1_.xRatio_0_;
            _S36_ = (_e246 < 0.0);
        }
    } else {
        _S36_ = false;
    }
    bool _e248 = _S36_;
    if (_e248) {
        _S36_ = true;
    } else {
        int _e250 = p_1_.xStem_0_;
        if ((_e250 == 1)) {
            float _e253 = p_1_.xMaxPx_0_;
            param_51 = _e253;
            bool _e254 = snailAhFinite_0_u0028_f1_u003b(param_51);
            if (!(_e254)) {
                _S36_ = true;
            } else {
                float _e257 = p_1_.xMaxPx_0_;
                _S36_ = (_e257 < 0.0);
            }
        } else {
            _S36_ = false;
        }
    }
    bool _e259 = _S36_;
    if (_e259) {
        _S36_ = true;
    } else {
        int _e261 = p_1_.yStem_0_;
        if ((_e261 != 0)) {
            float _e264 = p_1_.yRatio_0_;
            param_52 = _e264;
            bool _e265 = snailAhFinite_0_u0028_f1_u003b(param_52);
            if (!(_e265)) {
                _S36_ = true;
            } else {
                float _e268 = p_1_.yRatio_0_;
                _S36_ = (_e268 < 0.0);
            }
        } else {
            _S36_ = false;
        }
    }
    bool _e270 = _S36_;
    if (_e270) {
        _S36_ = true;
    } else {
        int _e272 = p_1_.yStem_0_;
        if ((_e272 == 1)) {
            float _e275 = p_1_.yMaxPx_0_;
            param_53 = _e275;
            bool _e276 = snailAhFinite_0_u0028_f1_u003b(param_53);
            if (!(_e276)) {
                _S36_ = true;
            } else {
                float _e279 = p_1_.yMaxPx_0_;
                _S36_ = (_e279 < 0.0);
            }
        } else {
            _S36_ = false;
        }
    }
    bool _e281 = _S36_;
    if (_e281) {
        _S36_ = true;
    } else {
        int _e283 = p_1_.yOvershoot_0_;
        if ((_e283 == 1)) {
            float _e286 = p_1_.overshootMinPx_0_;
            param_54 = _e286;
            bool _e287 = snailAhFinite_0_u0028_f1_u003b(param_54);
            if (!(_e287)) {
                _S36_ = true;
            } else {
                float _e290 = p_1_.overshootMinPx_0_;
                _S36_ = (_e290 < 0.0);
            }
        } else {
            _S36_ = false;
        }
    }
    bool _e292 = _S36_;
    if (_e292) {
        _S36_ = true;
    } else {
        int _e294 = p_1_.xPositioning_0_;
        if ((_e294 == 1)) {
            int _e297 = p_1_.xAlign_0_;
            _S36_ = (_e297 == 0);
        } else {
            _S36_ = false;
        }
    }
    bool _e299 = _S36_;
    if (_e299) {
        _S36_ = true;
    } else {
        int _e301 = p_1_.yOvershoot_0_;
        if ((_e301 == 1)) {
            int _e304 = p_1_.yAlign_0_;
            _S36_ = (_e304 != 2);
        } else {
            _S36_ = false;
        }
    }
    bool _e306 = _S36_;
    if (_e306) {
        return false;
    }
    return true;
}

void snailAhMarkFallback_0_u0028_vf4_u005b_4_u005d_u003b_vu4_u003b(inout vec4 packedTargets_0_[4], inout uvec4 packedSources_0_) {
    int i_0_ = 0;
    i_0_ = 0;
    while(true) {
        int _e100 = i_0_;
        if ((_e100 < 4)) {
        } else {
            break;
        }
        int _e102 = i_0_;
        packedTargets_0_[_e102] = vec4(0.0, 0.0, 0.0, 0.0);
        int _e104 = i_0_;
        i_0_ = (_e104 + 1);
        continue;
    }
    packedSources_0_ = uvec4(4294967295u, 4294967295u, 4294967295u, 4294967295u);
    packedSources_0_[0u] = 4294967294u;
    return;
}

bool snailAhAffineScale_0_u0028_mf44_u003b_vf2_u003b_vf4_u003b_vf2_u003b(inout mat4x4 mvp_2_, inout vec2 viewport_2_, inout vec4 xform_1_, inout vec2 scale_0_) {
    bool _S19_ = false;
    float param_55 = 0.0;
    vec2 localX_0_ = vec2(0.0);
    vec2 localY_0_ = vec2(0.0);
    vec2 _S20_ = vec2(0.0);
    vec2 _S21_ = vec2(0.0);
    vec2 _S22_ = vec2(0.0);
    float _S23_ = 0.0;
    vec2 screenX_0_ = vec2(0.0);
    vec2 screenY_0_ = vec2(0.0);
    float _S24_ = 0.0;
    float _S25_ = 0.0;
    float _S26_ = 0.0;
    float _S27_ = 0.0;
    float det_0_ = 0.0;
    float param_56 = 0.0;
    float _S28_ = 0.0;
    vec2 _S29_ = vec2(0.0);
    float param_57 = 0.0;
    float param_58 = 0.0;
    scale_0_ = vec2(0.0, 0.0);
    float _e123 = mvp_2_[3][0u];
    if ((abs(_e123) > 1e-7)) {
        _S19_ = true;
    } else {
        float _e128 = mvp_2_[3][1u];
        _S19_ = (abs(_e128) > 1e-7);
    }
    bool _e131 = _S19_;
    if (_e131) {
        _S19_ = true;
    } else {
        float _e134 = mvp_2_[3][3u];
        param_55 = _e134;
        bool _e135 = snailAhFinite_0_u0028_f1_u003b(param_55);
        _S19_ = !(_e135);
    }
    bool _e137 = _S19_;
    if (_e137) {
        _S19_ = true;
    } else {
        float _e140 = mvp_2_[3][3u];
        _S19_ = (abs(_e140) < 1e-10);
    }
    bool _e143 = _S19_;
    if (_e143) {
        return false;
    }
    float _e145 = xform_1_[0u];
    float _e147 = xform_1_[2u];
    localX_0_ = vec2(_e145, _e147);
    float _e150 = xform_1_[1u];
    float _e152 = xform_1_[3u];
    localY_0_ = vec2(_e150, _e152);
    vec2 _e154 = viewport_2_;
    _S20_ = (_e154 * 0.5);
    vec4 _e157 = mvp_2_[0];
    _S21_ = _e157.xy;
    vec4 _e160 = mvp_2_[1];
    _S22_ = _e160.xy;
    float _e164 = mvp_2_[3][3u];
    _S23_ = _e164;
    vec2 _e165 = _S20_;
    vec2 _e166 = _S21_;
    vec2 _e167 = localX_0_;
    vec2 _e169 = _S22_;
    vec2 _e170 = localX_0_;
    float _e174 = _S23_;
    screenX_0_ = ((_e165 * vec2(dot(_e166, _e167), dot(_e169, _e170))) / vec2(_e174));
    vec2 _e177 = _S20_;
    vec2 _e178 = _S21_;
    vec2 _e179 = localY_0_;
    vec2 _e181 = _S22_;
    vec2 _e182 = localY_0_;
    float _e186 = _S23_;
    screenY_0_ = ((_e177 * vec2(dot(_e178, _e179), dot(_e181, _e182))) / vec2(_e186));
    float _e190 = screenX_0_[0u];
    _S24_ = _e190;
    float _e192 = screenY_0_[1u];
    _S25_ = _e192;
    float _e194 = screenY_0_[0u];
    _S26_ = _e194;
    float _e196 = screenX_0_[1u];
    _S27_ = _e196;
    float _e197 = _S24_;
    float _e198 = _S25_;
    float _e200 = _S26_;
    float _e201 = _S27_;
    det_0_ = ((_e197 * _e198) - (_e200 * _e201));
    float _e204 = det_0_;
    param_56 = _e204;
    bool _e205 = snailAhFinite_0_u0028_f1_u003b(param_56);
    if (!(_e205)) {
        _S19_ = true;
    } else {
        float _e207 = det_0_;
        _S19_ = (abs(_e207) < 1e-10);
    }
    bool _e210 = _S19_;
    if (_e210) {
        return false;
    }
    float _e211 = det_0_;
    _S28_ = abs(_e211);
    float _e213 = _S25_;
    float _e215 = _S26_;
    float _e218 = _S28_;
    float _e220 = _S27_;
    float _e222 = _S24_;
    float _e225 = _S28_;
    _S29_ = (vec2(1.0) / vec2(((abs(_e213) + abs(_e215)) / _e218), ((abs(_e220) + abs(_e222)) / _e225)));
    vec2 _e230 = _S29_;
    scale_0_ = _e230;
    float _e232 = _S29_[0u];
    param_57 = _e232;
    bool _e233 = snailAhFinite_0_u0028_f1_u003b(param_57);
    if (_e233) {
        float _e235 = scale_0_[1u];
        param_58 = _e235;
        bool _e236 = snailAhFinite_0_u0028_f1_u003b(param_58);
        _S19_ = _e236;
    } else {
        _S19_ = false;
    }
    bool _e237 = _S19_;
    if (_e237) {
        float _e239 = scale_0_[0u];
        _S19_ = (_e239 > 0.0);
    } else {
        _S19_ = false;
    }
    bool _e241 = _S19_;
    if (_e241) {
        float _e243 = scale_0_[1u];
        _S19_ = (_e243 > 0.0);
    } else {
        _S19_ = false;
    }
    bool _e245 = _S19_;
    return _e245;
}

float snailVertexDilationScale_0_u0028_i1_u003b(inout int subpixel_order_1_) {
    float _S2_ = 0.0;
    int _e99 = subpixel_order_1_;
    if ((_e99 == 0)) {
        _S2_ = 1.0;
    } else {
        _S2_ = 2.3333333;
    }
    float _e101 = _S2_;
    return (1.4142135 * _e101);
}

float srgbDecode_0_u0028_f1_u003b(inout float c_0_) {
    float _S1_ = 0.0;
    float _e99 = c_0_;
    if ((_e99 <= 0.04045)) {
        float _e101 = c_0_;
        _S1_ = (_e101 / 12.92);
    } else {
        float _e103 = c_0_;
        _S1_ = pow(((_e103 + 0.055) / 1.055), 2.4);
    }
    float _e107 = _S1_;
    return _e107;
}

vec3 srgbToLinear_0_u0028_vf3_u003b(inout vec3 color_0_) {
    float param_59 = 0.0;
    float param_60 = 0.0;
    float param_61 = 0.0;
    float _e102 = color_0_[0u];
    param_59 = _e102;
    float _e103 = srgbDecode_0_u0028_f1_u003b(param_59);
    float _e105 = color_0_[1u];
    param_60 = _e105;
    float _e106 = srgbDecode_0_u0028_f1_u003b(param_60);
    float _e108 = color_0_[2u];
    param_61 = _e108;
    float _e109 = srgbDecode_0_u0028_f1_u003b(param_61);
    return vec3(_e103, _e106, _e109);
}

TextVertexResult_0_ snailTextVertex_0_u0028_struct_u002d_TextVertexIn_0_u002d_vf4_u002d_vf4_u002d_vf2_u002d_vu2_u002d_vf4_u002d_vf4_u002d_vf41_u003b_u1_u003b_mf44_u003b_vf2_u003b_i1_u003b(inout TextVertexIn_0_ input_0_, inout uint vertex_index_0_, inout mat4x4 mvp_1_, inout vec2 viewport_1_, inout int subpixel_order_2_) {
    vec2 em_0_ = vec2(0.0);
    vec2 indexable[4] = vec2[4](vec2(0.0), vec2(0.0), vec2(0.0), vec2(0.0));
    vec2 nd_0_ = vec2(0.0);
    vec2 indexable_1[4] = vec2[4](vec2(0.0), vec2(0.0), vec2(0.0), vec2(0.0));
    float _S3_ = 0.0;
    float _S4_ = 0.0;
    float _S5_ = 0.0;
    float _S6_ = 0.0;
    float _S7_ = 0.0;
    float _S8_ = 0.0;
    vec2 pos_0_ = vec2(0.0);
    float _S9_ = 0.0;
    float _S10_ = 0.0;
    vec2 wn_0_ = vec2(0.0);
    float inv_det_0_ = 0.0;
    float _S11_ = 0.0;
    float _S12_ = 0.0;
    float _S13_ = 0.0;
    float _S14_ = 0.0;
    uint gz_0_ = 0u;
    uint gw_0_ = 0u;
    TextVertexResult_0_ r_0_ = TextVertexResult_0_(vec4(0.0), vec4(0.0), vec4(0.0), vec2(0.0), vec4(0.0), ivec4(0));
    vec3 param_62 = vec3(0.0);
    vec3 param_63 = vec3(0.0);
    vec2 n_0_ = vec2(0.0);
    vec2 _S15_ = vec2(0.0);
    float s_0_ = 0.0;
    float t_val_0_ = 0.0;
    vec2 _S16_ = vec2(0.0);
    float u_val_0_ = 0.0;
    vec2 _S17_ = vec2(0.0);
    float v_val_0_ = 0.0;
    float s2_0_ = 0.0;
    float st_0_ = 0.0;
    float uv_0_ = 0.0;
    float denom_0_ = 0.0;
    vec2 d_0_ = vec2(0.0);
    vec2 d_1_ = vec2(0.0);
    int param_64 = 0;
    vec2 p_0_ = vec2(0.0);
    vec4 _e143 = input_0_.rect_0_;
    vec4 _e146 = input_0_.rect_0_;
    uint _e148 = vertex_index_0_;
    indexable = vec2[4](vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(1.0, 1.0), vec2(0.0, 1.0));
    vec2 _e150 = indexable[_e148];
    em_0_ = mix(_e143.xy, _e146.zw, _e150);
    uint _e152 = vertex_index_0_;
    indexable_1 = vec2[4](vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(1.0, 1.0), vec2(0.0, 1.0));
    vec2 _e154 = indexable_1[_e152];
    nd_0_ = ((_e154 * 2.0) - vec2(1.0));
    float _e160 = input_0_.xform_0_[0u];
    _S3_ = _e160;
    float _e162 = em_0_[0u];
    _S4_ = _e162;
    float _e165 = input_0_.xform_0_[1u];
    _S5_ = _e165;
    float _e167 = em_0_[1u];
    _S6_ = _e167;
    float _e170 = input_0_.xform_0_[2u];
    _S7_ = _e170;
    float _e173 = input_0_.xform_0_[3u];
    _S8_ = _e173;
    float _e174 = _S3_;
    float _e175 = _S4_;
    float _e177 = _S5_;
    float _e178 = _S6_;
    float _e183 = input_0_.origin_0_[0u];
    float _e185 = _S7_;
    float _e186 = _S4_;
    float _e188 = _S8_;
    float _e189 = _S6_;
    float _e194 = input_0_.origin_0_[1u];
    pos_0_ = vec2((((_e174 * _e175) + (_e177 * _e178)) + _e183), (((_e185 * _e186) + (_e188 * _e189)) + _e194));
    float _e198 = nd_0_[0u];
    _S9_ = _e198;
    float _e200 = nd_0_[1u];
    _S10_ = _e200;
    float _e201 = _S3_;
    float _e202 = _S9_;
    float _e204 = _S5_;
    float _e205 = _S10_;
    float _e208 = _S7_;
    float _e209 = _S9_;
    float _e211 = _S8_;
    float _e212 = _S10_;
    wn_0_ = vec2(((_e201 * _e202) + (_e204 * _e205)), ((_e208 * _e209) + (_e211 * _e212)));
    float _e216 = _S3_;
    float _e217 = _S8_;
    float _e219 = _S5_;
    float _e220 = _S7_;
    inv_det_0_ = (1.0 / ((_e216 * _e217) - (_e219 * _e220)));
    float _e224 = _S8_;
    float _e225 = inv_det_0_;
    _S11_ = (_e224 * _e225);
    float _e227 = _S5_;
    float _e229 = inv_det_0_;
    _S12_ = (-(_e227) * _e229);
    float _e231 = _S7_;
    float _e233 = inv_det_0_;
    _S13_ = (-(_e231) * _e233);
    float _e235 = _S3_;
    float _e236 = inv_det_0_;
    _S14_ = (_e235 * _e236);
    uint _e240 = input_0_.glyph_1_[0u];
    gz_0_ = _e240;
    uint _e243 = input_0_.glyph_1_[1u];
    gw_0_ = _e243;
    uint _e244 = gz_0_;
    uint _e247 = gz_0_;
    uint _e251 = gw_0_;
    uint _e254 = gw_0_;
    r_0_.glyph_0_ = ivec4(int((_e244 & 65535u)), int((_e247 >> 16u)), int((_e251 & 65535u)), int((_e254 >> 16u)));
    vec4 _e261 = input_0_.bnd_0_;
    r_0_.banding_0_ = _e261;
    vec4 _e264 = input_0_.col_0_;
    param_62 = _e264.xyz;
    vec3 _e266 = srgbToLinear_0_u0028_vf3_u003b(param_62);
    float _e269 = input_0_.col_0_[3u];
    r_0_.color_1_ = vec4(_e266.x, _e266.y, _e266.z, _e269);
    vec4 _e276 = input_0_.tint_1_;
    param_63 = _e276.xyz;
    vec3 _e278 = srgbToLinear_0_u0028_vf3_u003b(param_63);
    float _e281 = input_0_.tint_1_[3u];
    r_0_.tint_0_ = vec4(_e278.x, _e278.y, _e278.z, _e281);
    vec2 _e287 = wn_0_;
    n_0_ = normalize(_e287);
    vec4 _e290 = mvp_1_[3];
    _S15_ = _e290.xy;
    vec2 _e292 = _S15_;
    vec2 _e293 = pos_0_;
    float _e297 = mvp_1_[3][3u];
    s_0_ = (dot(_e292, _e293) + _e297);
    vec2 _e299 = _S15_;
    vec2 _e300 = n_0_;
    t_val_0_ = dot(_e299, _e300);
    vec4 _e303 = mvp_1_[0];
    _S16_ = _e303.xy;
    float _e305 = s_0_;
    vec2 _e306 = _S16_;
    vec2 _e307 = n_0_;
    float _e310 = t_val_0_;
    vec2 _e311 = _S16_;
    vec2 _e312 = pos_0_;
    float _e316 = mvp_1_[0][3u];
    float _e321 = viewport_1_[0u];
    u_val_0_ = (((_e305 * dot(_e306, _e307)) - (_e310 * (dot(_e311, _e312) + _e316))) * _e321);
    vec4 _e324 = mvp_1_[1];
    _S17_ = _e324.xy;
    float _e326 = s_0_;
    vec2 _e327 = _S17_;
    vec2 _e328 = n_0_;
    float _e331 = t_val_0_;
    vec2 _e332 = _S17_;
    vec2 _e333 = pos_0_;
    float _e337 = mvp_1_[1][3u];
    float _e342 = viewport_1_[1u];
    v_val_0_ = (((_e326 * dot(_e327, _e328)) - (_e331 * (dot(_e332, _e333) + _e337))) * _e342);
    float _e344 = s_0_;
    float _e345 = s_0_;
    s2_0_ = (_e344 * _e345);
    float _e347 = s_0_;
    float _e348 = t_val_0_;
    st_0_ = (_e347 * _e348);
    float _e350 = u_val_0_;
    float _e351 = u_val_0_;
    float _e353 = v_val_0_;
    float _e354 = v_val_0_;
    uv_0_ = ((_e350 * _e351) + (_e353 * _e354));
    float _e357 = uv_0_;
    float _e358 = st_0_;
    float _e359 = st_0_;
    denom_0_ = (_e357 - (_e358 * _e359));
    float _e362 = denom_0_;
    if ((abs(_e362) > 1e-10)) {
        vec2 _e365 = n_0_;
        float _e366 = s2_0_;
        float _e367 = st_0_;
        float _e368 = uv_0_;
        float _e372 = denom_0_;
        d_0_ = (_e365 * ((_e366 * (_e367 + sqrt(_e368))) / _e372));
    } else {
        vec2 _e375 = n_0_;
        vec2 _e377 = viewport_1_;
        d_0_ = ((_e375 * 2.0) / _e377);
    }
    vec2 _e379 = d_0_;
    int _e380 = subpixel_order_2_;
    param_64 = _e380;
    float _e381 = snailVertexDilationScale_0_u0028_i1_u003b(param_64);
    d_1_ = (_e379 * _e381);
    vec2 _e383 = pos_0_;
    vec2 _e384 = d_1_;
    p_0_ = (_e383 + _e384);
    float _e386 = _S4_;
    vec2 _e387 = d_1_;
    float _e388 = _S11_;
    float _e389 = _S12_;
    float _e393 = _S6_;
    vec2 _e394 = d_1_;
    float _e395 = _S13_;
    float _e396 = _S14_;
    r_0_.texcoord_0_ = vec2((_e386 + dot(_e387, vec2(_e388, _e389))), (_e393 + dot(_e394, vec2(_e395, _e396))));
    vec2 _e402 = p_0_;
    mat4x4 _e406 = mvp_1_;
    r_0_.position_0_ = (vec4(_e402.x, _e402.y, 0.0, 1.0) * _e406);
    TextVertexResult_0_ _e409 = r_0_;
    return _e409;
}

AutohintVertexResult_0_ snailAutohintVertex_0_u0028_struct_u002d_TextVertexIn_0_u002d_vf4_u002d_vf4_u002d_vf2_u002d_vu2_u002d_vf4_u002d_vf4_u002d_vf41_u003b_u1_u003b_mf44_u003b_vf2_u003b_i1_u003b_vu4_u003b_vu3_u003b_t21_u003b(inout TextVertexIn_0_ input_1_, inout uint vertex_index_1_, inout mat4x4 mvp_3_, inout vec2 viewport_3_, inout int subpixel_order_3_, inout uvec4 policy0_1_, inout uvec3 policy1_1_, highp sampler2D layer_tex_3_) {
    TextVertexResult_0_ base_1_ = TextVertexResult_0_(vec4(0.0), vec4(0.0), vec4(0.0), vec2(0.0), vec4(0.0), ivec4(0));
    TextVertexIn_0_ param_65 = TextVertexIn_0_(vec4(0.0), vec4(0.0), vec2(0.0), uvec2(0u), vec4(0.0), vec4(0.0), vec4(0.0));
    uint param_66 = 0u;
    mat4x4 param_67 = mat4x4(0.0);
    vec2 param_68 = vec2(0.0);
    int param_69 = 0;
    AutohintVertexResult_0_ r_1_ = AutohintVertexResult_0_(vec4(0.0), vec4(0.0), vec3(0.0), ivec2(0), uvec4(0u), uvec3(0u), vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0)), vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0)), uvec4(0u), uvec4(0u));
    uint gz_1_ = 0u;
    int i_5_ = 0;
    ivec2 info_base_2_ = ivec2(0);
    bool _S68_ = false;
    vec2 scale_3_ = vec2(0.0);
    mat4x4 param_70 = mat4x4(0.0);
    vec2 param_71 = vec2(0.0);
    vec4 param_72 = vec4(0.0);
    vec2 param_73 = vec2(0.0);
    vec4 param_74[4] = vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0));
    uvec4 param_75 = uvec4(0u);
    vec4 param_76[4] = vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0));
    uvec4 param_77 = uvec4(0u);
    int blueCount_1_ = 0;
    int featureXCount_0_ = 0;
    float stdX_0_ = 0.0;
    ivec2 param_78 = ivec2(0);
    int param_79 = 0;
    int param_80 = 0;
    float stdY_0_ = 0.0;
    ivec2 param_81 = ivec2(0);
    int param_82 = 0;
    int param_83 = 0;
    bool _S69_ = false;
    SnailAutohintPolicy_0_ policy_1_ = SnailAutohintPolicy_0_(0, 0, 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    uvec4 param_84 = uvec4(0u);
    uvec3 param_85 = uvec3(0u);
    SnailAutohintPolicy_0_ param_86 = SnailAutohintPolicy_0_(0, 0, 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    bool valid_0_ = false;
    float param_87 = 0.0;
    float param_88 = 0.0;
    float _S70_ = 0.0;
    ivec2 param_89 = ivec2(0);
    int param_90 = 0;
    int param_91 = 0;
    bool _S71_ = false;
    int param_92 = 0;
    float param_93 = 0.0;
    int param_94 = 0;
    int xRun_0_ = 0;
    float _S72_ = 0.0;
    ivec2 param_95 = ivec2(0);
    int param_96 = 0;
    int param_97 = 0;
    bool _S73_ = false;
    int param_98 = 0;
    float param_99 = 0.0;
    int param_100 = 0;
    int yRun_0_ = 0;
    float _S74_ = 0.0;
    ivec2 param_101 = ivec2(0);
    int param_102 = 0;
    int param_103 = 0;
    int param_104 = 0;
    float param_105 = 0.0;
    int param_106 = 0;
    vec4 param_107[4] = vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0));
    uvec4 param_108 = uvec4(0u);
    vec4 param_109[4] = vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0));
    uvec4 param_110 = uvec4(0u);
    int xCount_0_ = 0;
    int yCount_0_ = 0;
    float _S75_ = 0.0;
    ivec2 param_111 = ivec2(0);
    int param_112 = 0;
    int param_113 = 0;
    bool xValid_0_ = false;
    float xTarget_0_[16] = float[16](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    int xSource_0_[16] = int[16](0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    ivec2 param_114 = ivec2(0);
    int param_115 = 0;
    int param_116 = 0;
    int param_117 = 0;
    float param_118 = 0.0;
    float param_119 = 0.0;
    float param_120 = 0.0;
    SnailAutohintPolicy_0_ param_121 = SnailAutohintPolicy_0_(0, 0, 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    int param_122 = 0;
    float param_123[16] = float[16](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    float param_124[16] = float[16](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    int param_125[16] = int[16](0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    bool yValid_0_ = false;
    float yTarget_0_[16] = float[16](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    int ySource_0_[16] = int[16](0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    ivec2 param_126 = ivec2(0);
    int param_127 = 0;
    int param_128 = 0;
    int param_129 = 0;
    float param_130 = 0.0;
    float param_131 = 0.0;
    float param_132 = 0.0;
    SnailAutohintPolicy_0_ param_133 = SnailAutohintPolicy_0_(0, 0, 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    int param_134 = 0;
    float param_135[16] = float[16](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    float param_136[16] = float[16](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    int param_137[16] = int[16](0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    int param_138 = 0;
    float param_139[16] = float[16](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    int param_140[16] = int[16](0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    vec4 param_141[4] = vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0));
    uvec4 param_142 = uvec4(0u);
    vec4 param_143[4] = vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0));
    uvec4 param_144 = uvec4(0u);
    int param_145 = 0;
    float param_146[16] = float[16](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    int param_147[16] = int[16](0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    vec4 param_148[4] = vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0));
    uvec4 param_149 = uvec4(0u);
    vec4 param_150[4] = vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0));
    uvec4 param_151 = uvec4(0u);
    TextVertexIn_0_ _e222 = input_1_;
    param_65 = _e222;
    uint _e223 = vertex_index_1_;
    param_66 = _e223;
    mat4x4 _e224 = mvp_3_;
    param_67 = _e224;
    vec2 _e225 = viewport_3_;
    param_68 = _e225;
    int _e226 = subpixel_order_3_;
    param_69 = _e226;
    TextVertexResult_0_ _e227 = snailTextVertex_0_u0028_struct_u002d_TextVertexIn_0_u002d_vf4_u002d_vf4_u002d_vf2_u002d_vu2_u002d_vf4_u002d_vf4_u002d_vf41_u003b_u1_u003b_mf44_u003b_vf2_u003b_i1_u003b(param_65, param_66, param_67, param_68, param_69);
    base_1_ = _e227;
    vec4 _e229 = base_1_.position_0_;
    r_1_.position_1_ = _e229;
    vec4 _e232 = base_1_.color_1_;
    vec4 _e234 = base_1_.tint_0_;
    r_1_.paint_0_ = (_e232 * _e234);
    vec2 _e238 = base_1_.texcoord_0_;
    float _e241 = input_1_.bnd_0_[3u];
    r_1_.texcoord_layer_0_ = vec3(_e238.x, _e238.y, _e241);
    uint _e248 = input_1_.glyph_1_[0u];
    gz_1_ = _e248;
    uint _e249 = gz_1_;
    uint _e252 = gz_1_;
    r_1_.info_0_ = ivec2(int((_e249 & 65535u)), int((_e252 >> 16u)));
    uvec4 _e258 = policy0_1_;
    r_1_.policy0_0_ = _e258;
    uvec3 _e260 = policy1_1_;
    r_1_.policy1_0_ = _e260;
    uint _e262 = vertex_index_1_;
    if ((_e262 != 0u)) {
        i_5_ = 0;
        while(true) {
            int _e264 = i_5_;
            if ((_e264 < 4)) {
            } else {
                break;
            }
            int _e266 = i_5_;
            r_1_.x_targets_0_[_e266] = vec4(0.0, 0.0, 0.0, 0.0);
            int _e269 = i_5_;
            r_1_.y_targets_0_[_e269] = vec4(0.0, 0.0, 0.0, 0.0);
            int _e272 = i_5_;
            i_5_ = (_e272 + 1);
            continue;
        }
        r_1_.x_sources_0_ = uvec4(4294967295u, 4294967295u, 4294967295u, 4294967295u);
        r_1_.y_sources_0_ = uvec4(4294967295u, 4294967295u, 4294967295u, 4294967295u);
        AutohintVertexResult_0_ _e276 = r_1_;
        return _e276;
    }
    ivec2 _e278 = r_1_.info_0_;
    info_base_2_ = _e278;
    mat4x4 _e279 = mvp_3_;
    param_70 = _e279;
    vec2 _e280 = viewport_3_;
    param_71 = _e280;
    vec4 _e282 = input_1_.xform_0_;
    param_72 = _e282;
    bool _e283 = snailAhAffineScale_0_u0028_mf44_u003b_vf2_u003b_vf4_u003b_vf2_u003b(param_70, param_71, param_72, param_73);
    vec2 _e284 = param_73;
    scale_3_ = _e284;
    _S68_ = _e283;
    bool _e285 = _S68_;
    if (!(_e285)) {
        snailAhMarkFallback_0_u0028_vf4_u005b_4_u005d_u003b_vu4_u003b(param_74, param_75);
        vec4 _e287[4] = param_74;
        r_1_.x_targets_0_ = _e287;
        uvec4 _e289 = param_75;
        r_1_.x_sources_0_ = _e289;
        snailAhMarkFallback_0_u0028_vf4_u005b_4_u005d_u003b_vu4_u003b(param_76, param_77);
        vec4 _e291[4] = param_76;
        r_1_.y_targets_0_ = _e291;
        uvec4 _e293 = param_77;
        r_1_.y_sources_0_ = _e293;
        AutohintVertexResult_0_ _e295 = r_1_;
        return _e295;
    }
    blueCount_1_ = 0;
    featureXCount_0_ = 0;
    ivec2 _e296 = info_base_2_;
    param_78 = _e296;
    param_79 = 0;
    param_80 = 8;
    float _e297 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_3_, param_78, param_79, param_80);
    stdX_0_ = _e297;
    ivec2 _e298 = info_base_2_;
    param_81 = _e298;
    param_82 = 0;
    param_83 = 9;
    float _e299 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_3_, param_81, param_82, param_83);
    stdY_0_ = _e299;
    uvec4 _e300 = policy0_1_;
    param_84 = _e300;
    uvec3 _e301 = policy1_1_;
    param_85 = _e301;
    bool _e302 = snailDecodeAutohintPolicy_0_u0028_vu4_u003b_vu3_u003b_struct_u002d_SnailAutohintPolicy_0_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f11_u003b(param_84, param_85, param_86);
    SnailAutohintPolicy_0_ _e303 = param_86;
    policy_1_ = _e303;
    _S69_ = _e302;
    bool _e304 = _S69_;
    if (_e304) {
        float _e305 = stdX_0_;
        param_87 = _e305;
        bool _e306 = snailAhFinite_0_u0028_f1_u003b(param_87);
        valid_0_ = _e306;
    } else {
        valid_0_ = false;
    }
    bool _e307 = valid_0_;
    if (_e307) {
        float _e308 = stdX_0_;
        valid_0_ = (_e308 >= 0.0);
    } else {
        valid_0_ = false;
    }
    bool _e310 = valid_0_;
    if (_e310) {
        float _e311 = stdY_0_;
        param_88 = _e311;
        bool _e312 = snailAhFinite_0_u0028_f1_u003b(param_88);
        valid_0_ = _e312;
    } else {
        valid_0_ = false;
    }
    bool _e313 = valid_0_;
    if (_e313) {
        float _e314 = stdY_0_;
        valid_0_ = (_e314 >= 0.0);
    } else {
        valid_0_ = false;
    }
    bool _e316 = valid_0_;
    if (_e316) {
        ivec2 _e317 = info_base_2_;
        param_89 = _e317;
        param_90 = 0;
        param_91 = 10;
        float _e318 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_3_, param_89, param_90, param_91);
        _S70_ = _e318;
        param_92 = 16;
        float _e319 = _S70_;
        param_93 = _e319;
        bool _e320 = snailAhCount_0_u0028_i1_u003b_f1_u003b_i1_u003b(param_92, param_93, param_94);
        int _e321 = param_94;
        blueCount_1_ = _e321;
        _S71_ = _e320;
        bool _e322 = _S71_;
        valid_0_ = _e322;
    } else {
        valid_0_ = false;
    }
    int _e323 = blueCount_1_;
    xRun_0_ = (12 + (2 * _e323));
    bool _e326 = valid_0_;
    if (_e326) {
        ivec2 _e327 = info_base_2_;
        param_95 = _e327;
        int _e328 = xRun_0_;
        param_96 = _e328;
        param_97 = 0;
        float _e329 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_3_, param_95, param_96, param_97);
        _S72_ = _e329;
        param_98 = 16;
        float _e330 = _S72_;
        param_99 = _e330;
        bool _e331 = snailAhCount_0_u0028_i1_u003b_f1_u003b_i1_u003b(param_98, param_99, param_100);
        int _e332 = param_100;
        featureXCount_0_ = _e332;
        _S73_ = _e331;
        bool _e333 = _S73_;
        valid_0_ = _e333;
    } else {
        valid_0_ = false;
    }
    int _e334 = xRun_0_;
    int _e336 = featureXCount_0_;
    yRun_0_ = ((_e334 + 1) + (4 * _e336));
    bool _e339 = valid_0_;
    if (_e339) {
        ivec2 _e340 = info_base_2_;
        param_101 = _e340;
        int _e341 = yRun_0_;
        param_102 = _e341;
        param_103 = 0;
        float _e342 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_3_, param_101, param_102, param_103);
        _S74_ = _e342;
        param_104 = 16;
        float _e343 = _S74_;
        param_105 = _e343;
        bool _e344 = snailAhCount_0_u0028_i1_u003b_f1_u003b_i1_u003b(param_104, param_105, param_106);
        valid_0_ = _e344;
    } else {
        valid_0_ = false;
    }
    bool _e345 = valid_0_;
    if (!(_e345)) {
        snailAhMarkFallback_0_u0028_vf4_u005b_4_u005d_u003b_vu4_u003b(param_107, param_108);
        vec4 _e347[4] = param_107;
        r_1_.x_targets_0_ = _e347;
        uvec4 _e349 = param_108;
        r_1_.x_sources_0_ = _e349;
        snailAhMarkFallback_0_u0028_vf4_u005b_4_u005d_u003b_vu4_u003b(param_109, param_110);
        vec4 _e351[4] = param_109;
        r_1_.y_targets_0_ = _e351;
        uvec4 _e353 = param_110;
        r_1_.y_sources_0_ = _e353;
        AutohintVertexResult_0_ _e355 = r_1_;
        return _e355;
    }
    xCount_0_ = 0;
    yCount_0_ = 0;
    ivec2 _e356 = info_base_2_;
    param_111 = _e356;
    param_112 = 0;
    param_113 = 11;
    float _e357 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_3_, param_111, param_112, param_113);
    _S75_ = _e357;
    ivec2 _e358 = info_base_2_;
    param_114 = _e358;
    param_115 = 0;
    int _e359 = xRun_0_;
    param_116 = _e359;
    int _e360 = blueCount_1_;
    param_117 = _e360;
    float _e361 = stdX_0_;
    param_118 = _e361;
    float _e362 = _S75_;
    param_119 = _e362;
    float _e364 = scale_3_[0u];
    param_120 = _e364;
    SnailAutohintPolicy_0_ _e365 = policy_1_;
    param_121 = _e365;
    bool _e366 = snailFitAutohintAxis_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b_i1_u003b_f1_u003b_f1_u003b_f1_u003b_struct_u002d_SnailAutohintPolicy_0_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f11_u003b_i1_u003b_f1_u005b_16_u005d_u003b_f1_u005b_16_u005d_u003b_i1_u005b_16_u005d_u003b(layer_tex_3_, param_114, param_115, param_116, param_117, param_118, param_119, param_120, param_121, param_122, param_123, param_124, param_125);
    int _e367 = param_122;
    xCount_0_ = _e367;
    float _e368[16] = param_124;
    xTarget_0_ = _e368;
    int _e369[16] = param_125;
    xSource_0_ = _e369;
    xValid_0_ = _e366;
    ivec2 _e370 = info_base_2_;
    param_126 = _e370;
    param_127 = 1;
    int _e371 = yRun_0_;
    param_128 = _e371;
    int _e372 = blueCount_1_;
    param_129 = _e372;
    float _e373 = stdY_0_;
    param_130 = _e373;
    param_131 = 0.0;
    float _e375 = scale_3_[1u];
    param_132 = _e375;
    SnailAutohintPolicy_0_ _e376 = policy_1_;
    param_133 = _e376;
    bool _e377 = snailFitAutohintAxis_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b_i1_u003b_f1_u003b_f1_u003b_f1_u003b_struct_u002d_SnailAutohintPolicy_0_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f11_u003b_i1_u003b_f1_u005b_16_u005d_u003b_f1_u005b_16_u005d_u003b_i1_u005b_16_u005d_u003b(layer_tex_3_, param_126, param_127, param_128, param_129, param_130, param_131, param_132, param_133, param_134, param_135, param_136, param_137);
    int _e378 = param_134;
    yCount_0_ = _e378;
    float _e379[16] = param_136;
    yTarget_0_ = _e379;
    int _e380[16] = param_137;
    ySource_0_ = _e380;
    yValid_0_ = _e377;
    bool _e381 = xValid_0_;
    if (_e381) {
        int _e382 = xCount_0_;
        param_138 = _e382;
        float _e383[16] = xTarget_0_;
        param_139 = _e383;
        int _e384[16] = xSource_0_;
        param_140 = _e384;
        snailAhPackAxis_0_u0028_i1_u003b_f1_u005b_16_u005d_u003b_i1_u005b_16_u005d_u003b_vf4_u005b_4_u005d_u003b_vu4_u003b(param_138, param_139, param_140, param_141, param_142);
        vec4 _e385[4] = param_141;
        r_1_.x_targets_0_ = _e385;
        uvec4 _e387 = param_142;
        r_1_.x_sources_0_ = _e387;
    } else {
        snailAhMarkFallback_0_u0028_vf4_u005b_4_u005d_u003b_vu4_u003b(param_143, param_144);
        vec4 _e389[4] = param_143;
        r_1_.x_targets_0_ = _e389;
        uvec4 _e391 = param_144;
        r_1_.x_sources_0_ = _e391;
    }
    bool _e393 = yValid_0_;
    if (_e393) {
        int _e394 = yCount_0_;
        param_145 = _e394;
        float _e395[16] = yTarget_0_;
        param_146 = _e395;
        int _e396[16] = ySource_0_;
        param_147 = _e396;
        snailAhPackAxis_0_u0028_i1_u003b_f1_u005b_16_u005d_u003b_i1_u005b_16_u005d_u003b_vf4_u005b_4_u005d_u003b_vu4_u003b(param_145, param_146, param_147, param_148, param_149);
        vec4 _e397[4] = param_148;
        r_1_.y_targets_0_ = _e397;
        uvec4 _e399 = param_149;
        r_1_.y_sources_0_ = _e399;
    } else {
        snailAhMarkFallback_0_u0028_vf4_u005b_4_u005d_u003b_vu4_u003b(param_150, param_151);
        vec4 _e401[4] = param_150;
        r_1_.y_targets_0_ = _e401;
        uvec4 _e403 = param_151;
        r_1_.y_sources_0_ = _e403;
    }
    AutohintVertexResult_0_ _e405 = r_1_;
    return _e405;
}

VsOutput_0_ vertexBody_0_u0028_struct_u002d_VsInput_0_u002d_vf4_u002d_vf4_u002d_vf2_u002d_vu2_u002d_vf4_u002d_vf4_u002d_vf4_u002d_vu4_u002d_vu31_u003b_u1_u003b(inout VsInput_0_ input_2_, inout uint vertex_index_2_) {
    TextVertexIn_0_ v_2_ = TextVertexIn_0_(vec4(0.0), vec4(0.0), vec2(0.0), uvec2(0u), vec4(0.0), vec4(0.0), vec4(0.0));
    AutohintVertexResult_0_ r_2_ = AutohintVertexResult_0_(vec4(0.0), vec4(0.0), vec3(0.0), ivec2(0), uvec4(0u), uvec3(0u), vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0)), vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0)), uvec4(0u), uvec4(0u));
    TextVertexIn_0_ param_152 = TextVertexIn_0_(vec4(0.0), vec4(0.0), vec2(0.0), uvec2(0u), vec4(0.0), vec4(0.0), vec4(0.0));
    uint param_153 = 0u;
    mat4x4 param_154 = mat4x4(0.0);
    vec2 param_155 = vec2(0.0);
    int param_156 = 0;
    uvec4 param_157 = uvec4(0u);
    uvec3 param_158 = uvec3(0u);
    VsOutput_0_ o_0_ = VsOutput_0_(vec4(0.0), vec4(0.0), vec3(0.0), ivec2(0), uvec4(0u), uvec3(0u), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), uvec4(0u), uvec4(0u));
    vec4 _e110 = input_2_.rect_1_;
    v_2_.rect_0_ = _e110;
    vec4 _e113 = input_2_.xform_2_;
    v_2_.xform_0_ = _e113;
    vec2 _e116 = input_2_.origin_1_;
    v_2_.origin_0_ = _e116;
    uvec2 _e119 = input_2_.glyph_2_;
    v_2_.glyph_1_ = _e119;
    vec4 _e122 = input_2_.bnd_1_;
    v_2_.bnd_0_ = _e122;
    vec4 _e125 = input_2_.col_1_;
    v_2_.col_0_ = _e125;
    vec4 _e128 = input_2_.tint_2_;
    v_2_.tint_1_ = _e128;
    TextVertexIn_0_ _e130 = v_2_;
    param_152 = _e130;
    uint _e131 = vertex_index_2_;
    param_153 = _e131;
    mat4x4 _e133 = _group_0_binding_0_vs.mvp_0_;
    param_154 = transpose(_e133);
    vec2 _e136 = _group_0_binding_0_vs.viewport_0_;
    param_155 = _e136;
    int _e138 = _group_0_binding_0_vs.subpixel_order_0_;
    param_156 = _e138;
    uvec4 _e140 = input_2_.policy0_3_;
    param_157 = _e140;
    uvec3 _e142 = input_2_.policy1_3_;
    param_158 = _e142;
    AutohintVertexResult_0_ _e143 = snailAutohintVertex_0_u0028_struct_u002d_TextVertexIn_0_u002d_vf4_u002d_vf4_u002d_vf2_u002d_vu2_u002d_vf4_u002d_vf4_u002d_vf41_u003b_u1_u003b_mf44_u003b_vf2_u003b_i1_u003b_vu4_u003b_vu3_u003b_t21_u003b(param_152, param_153, param_154, param_155, param_156, param_157, param_158, _group_0_binding_3_vs);
    r_2_ = _e143;
    vec4 _e145 = r_2_.position_1_;
    o_0_.position_2_ = _e145;
    vec4 _e148 = r_2_.paint_0_;
    o_0_.paint_1_ = _e148;
    vec3 _e151 = r_2_.texcoord_layer_0_;
    o_0_.texcoord_layer_1_ = _e151;
    ivec2 _e154 = r_2_.info_0_;
    o_0_.info_1_ = _e154;
    uvec4 _e157 = r_2_.policy0_0_;
    o_0_.policy0_2_ = _e157;
    uvec3 _e160 = r_2_.policy1_0_;
    o_0_.policy1_2_ = _e160;
    vec4 _e164 = r_2_.x_targets_0_[0];
    o_0_.x_targets0_0_ = _e164;
    vec4 _e168 = r_2_.x_targets_0_[1];
    o_0_.x_targets1_0_ = _e168;
    vec4 _e172 = r_2_.x_targets_0_[2];
    o_0_.x_targets2_0_ = _e172;
    vec4 _e176 = r_2_.x_targets_0_[3];
    o_0_.x_targets3_0_ = _e176;
    vec4 _e180 = r_2_.y_targets_0_[0];
    o_0_.y_targets0_0_ = _e180;
    vec4 _e184 = r_2_.y_targets_0_[1];
    o_0_.y_targets1_0_ = _e184;
    vec4 _e188 = r_2_.y_targets_0_[2];
    o_0_.y_targets2_0_ = _e188;
    vec4 _e192 = r_2_.y_targets_0_[3];
    o_0_.y_targets3_0_ = _e192;
    uvec4 _e195 = r_2_.x_sources_0_;
    o_0_.x_sources_1_ = _e195;
    uvec4 _e198 = r_2_.y_sources_0_;
    o_0_.y_sources_1_ = _e198;
    VsOutput_0_ _e200 = o_0_;
    return _e200;
}

void main_1() {
    VsInput_0_ _S76_ = VsInput_0_(vec4(0.0), vec4(0.0), vec2(0.0), uvec2(0u), vec4(0.0), vec4(0.0), vec4(0.0), uvec4(0u), uvec3(0u));
    VsOutput_0_ _S77_ = VsOutput_0_(vec4(0.0), vec4(0.0), vec3(0.0), ivec2(0), uvec4(0u), uvec3(0u), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0), uvec4(0u), uvec4(0u));
    VsInput_0_ param_159 = VsInput_0_(vec4(0.0), vec4(0.0), vec2(0.0), uvec2(0u), vec4(0.0), vec4(0.0), vec4(0.0), uvec4(0u), uvec3(0u));
    uint param_160 = 0u;
    vec4 _e101 = input_rect_0_1;
    vec4 _e102 = input_xform_0_1;
    vec2 _e103 = input_origin_0_1;
    uvec2 _e104 = input_glyph_0_1;
    vec4 _e105 = input_bnd_0_1;
    vec4 _e106 = input_col_0_1;
    vec4 _e107 = input_tint_0_1;
    uvec4 _e108 = input_policy0_0_1;
    uvec3 _e109 = input_policy1_0_1;
    _S76_ = VsInput_0_(_e101, _e102, _e103, _e104, _e105, _e106, _e107, _e108, _e109);
    int _e111 = gen_gl_VertexIndex_1;
    int _e112 = gen_gl_BaseVertex_1;
    VsInput_0_ _e115 = _S76_;
    param_159 = _e115;
    param_160 = uint((_e111 - _e112));
    VsOutput_0_ _e116 = vertexBody_0_u0028_struct_u002d_VsInput_0_u002d_vf4_u002d_vf4_u002d_vf2_u002d_vu2_u002d_vf4_u002d_vf4_u002d_vf4_u002d_vu4_u002d_vu31_u003b_u1_u003b(param_159, param_160);
    _S77_ = _e116;
    vec4 _e118 = _S77_.position_2_;
    unnamed.gen_gl_Position = _e118;
    vec4 _e121 = _S77_.paint_1_;
    entryPointParam_vertexMain_paint_0_ = _e121;
    vec3 _e123 = _S77_.texcoord_layer_1_;
    entryPointParam_vertexMain_texcoord_layer_0_ = _e123;
    ivec2 _e125 = _S77_.info_1_;
    entryPointParam_vertexMain_info_0_ = _e125;
    uvec4 _e127 = _S77_.policy0_2_;
    entryPointParam_vertexMain_policy0_0_ = _e127;
    uvec3 _e129 = _S77_.policy1_2_;
    entryPointParam_vertexMain_policy1_0_ = _e129;
    vec4 _e131 = _S77_.x_targets0_0_;
    entryPointParam_vertexMain_x_targets0_0_ = _e131;
    vec4 _e133 = _S77_.x_targets1_0_;
    entryPointParam_vertexMain_x_targets1_0_ = _e133;
    vec4 _e135 = _S77_.x_targets2_0_;
    entryPointParam_vertexMain_x_targets2_0_ = _e135;
    vec4 _e137 = _S77_.x_targets3_0_;
    entryPointParam_vertexMain_x_targets3_0_ = _e137;
    vec4 _e139 = _S77_.y_targets0_0_;
    entryPointParam_vertexMain_y_targets0_0_ = _e139;
    vec4 _e141 = _S77_.y_targets1_0_;
    entryPointParam_vertexMain_y_targets1_0_ = _e141;
    vec4 _e143 = _S77_.y_targets2_0_;
    entryPointParam_vertexMain_y_targets2_0_ = _e143;
    vec4 _e145 = _S77_.y_targets3_0_;
    entryPointParam_vertexMain_y_targets3_0_ = _e145;
    uvec4 _e147 = _S77_.x_sources_1_;
    entryPointParam_vertexMain_x_sources_0_ = _e147;
    uvec4 _e149 = _S77_.y_sources_1_;
    entryPointParam_vertexMain_y_sources_0_ = _e149;
    return;
}

void main() {
    vec4 input_rect_0_ = _p2vs_location0;
    vec4 input_xform_0_ = _p2vs_location1;
    vec2 input_origin_0_ = _p2vs_location2;
    uvec2 input_glyph_0_ = _p2vs_location3;
    vec4 input_bnd_0_ = _p2vs_location4;
    vec4 input_col_0_ = _p2vs_location5;
    vec4 input_tint_0_ = _p2vs_location6;
    uvec4 input_policy0_0_ = _p2vs_location7;
    uvec3 input_policy1_0_ = _p2vs_location8;
    uint gen_gl_VertexIndex = uint(gl_VertexID);
    uint gen_gl_BaseVertex = 0u;
    input_rect_0_1 = input_rect_0_;
    input_xform_0_1 = input_xform_0_;
    input_origin_0_1 = input_origin_0_;
    input_glyph_0_1 = input_glyph_0_;
    input_bnd_0_1 = input_bnd_0_;
    input_col_0_1 = input_col_0_;
    input_tint_0_1 = input_tint_0_;
    input_policy0_0_1 = input_policy0_0_;
    input_policy1_0_1 = input_policy1_0_;
    gen_gl_VertexIndex_1 = int(gen_gl_VertexIndex);
    gen_gl_BaseVertex_1 = int(gen_gl_BaseVertex);
    main_1();
    vec4 _e41 = unnamed.gen_gl_Position;
    vec4 _e42 = entryPointParam_vertexMain_paint_0_;
    vec3 _e43 = entryPointParam_vertexMain_texcoord_layer_0_;
    ivec2 _e44 = entryPointParam_vertexMain_info_0_;
    uvec4 _e45 = entryPointParam_vertexMain_policy0_0_;
    uvec3 _e46 = entryPointParam_vertexMain_policy1_0_;
    vec4 _e47 = entryPointParam_vertexMain_x_targets0_0_;
    vec4 _e48 = entryPointParam_vertexMain_x_targets1_0_;
    vec4 _e49 = entryPointParam_vertexMain_x_targets2_0_;
    vec4 _e50 = entryPointParam_vertexMain_x_targets3_0_;
    vec4 _e51 = entryPointParam_vertexMain_y_targets0_0_;
    vec4 _e52 = entryPointParam_vertexMain_y_targets1_0_;
    vec4 _e53 = entryPointParam_vertexMain_y_targets2_0_;
    vec4 _e54 = entryPointParam_vertexMain_y_targets3_0_;
    uvec4 _e55 = entryPointParam_vertexMain_x_sources_0_;
    uvec4 _e56 = entryPointParam_vertexMain_y_sources_0_;
    VertexOutput _tmp_return = VertexOutput(_e41, _e42, _e43, _e44, _e45, _e46, _e47, _e48, _e49, _e50, _e51, _e52, _e53, _e54, _e55, _e56);
    gl_Position = _tmp_return.gen_gl_Position;
    _vs2fs_location0 = _tmp_return.member;
    _vs2fs_location1 = _tmp_return.member_1;
    _vs2fs_location2 = _tmp_return.member_2;
    _vs2fs_location3 = _tmp_return.member_3;
    _vs2fs_location4 = _tmp_return.member_4;
    _vs2fs_location5 = _tmp_return.member_5;
    _vs2fs_location6 = _tmp_return.member_6;
    _vs2fs_location7 = _tmp_return.member_7;
    _vs2fs_location8 = _tmp_return.member_8;
    _vs2fs_location9 = _tmp_return.member_9;
    _vs2fs_location10 = _tmp_return.member_10;
    _vs2fs_location11 = _tmp_return.member_11;
    _vs2fs_location12 = _tmp_return.member_12;
    _vs2fs_location13 = _tmp_return.member_13;
    _vs2fs_location14 = _tmp_return.member_14;
    return;
}

