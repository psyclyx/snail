#version 330 core
struct CoverageBandSpan_0_ {
    int first_0_;
    int last_0_;
};
struct SubpixelVaryings_0_ {
    vec4 color_2_;
    vec4 tint_0_;
    vec2 texcoord_0_;
    vec4 banding_3_;
    ivec4 glyph_0_;
};
struct SubpixelResult_0_ {
    vec4 color_1_;
    vec4 blend_0_;
    bool discard_fragment_0_;
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
struct FsOutput_0_ {
    vec4 color_4_;
    vec4 blend_1_;
};
struct FragmentOutput {
    vec4 member;
    vec4 member_1;
};
vec4 input_color_0_1 = vec4(0.0);

vec4 input_tint_0_1 = vec4(0.0);

vec2 input_texcoord_0_1 = vec2(0.0);

vec4 input_banding_0_1 = vec4(0.0);

ivec4 input_glyph_0_1 = ivec4(0);

uniform sampler2DArray _group_0_binding_1_fs;

uniform usampler2DArray _group_0_binding_2_fs;

layout(std140) uniform block_SnailPushConstants_0_block_0Fragment { block_SnailPushConstants_0_ _group_0_binding_0_fs; };

vec4 entryPointParam_fragmentMain_color_0_ = vec4(0.0);

vec4 entryPointParam_fragmentMain_blend_0_ = vec4(0.0);

smooth in vec4 _vs2fs_location0;
smooth in vec4 _vs2fs_location4;
smooth in vec2 _vs2fs_location1;
flat in vec4 _vs2fs_location2;
flat in ivec4 _vs2fs_location3;
layout(location = 0, index = 0) out vec4 _fs2p_location0;
layout(location = 0, index = 1) out vec4 _fs2p_location1;

vec4 premultiplyColorSubpixel_0_u0028_vf4_u003b_vf3_u003b_f1_u003b(inout vec4 color_0_, inout vec3 cov_4_, inout float alpha_cov_0_) {
    float _S66_ = 0.0;
    float _e65 = color_0_[3u];
    _S66_ = _e65;
    vec4 _e66 = color_0_;
    float _e68 = _S66_;
    vec3 _e70 = cov_4_;
    vec3 _e72 = (_e66.xyz * (vec3(_e68) * _e70));
    float _e73 = _S66_;
    float _e74 = alpha_cov_0_;
    return vec4(_e72.x, _e72.y, _e72.z, (_e73 * _e74));
}

float srgbEncode_0_u0028_f1_u003b(inout float c_0_) {
    float _S65_ = 0.0;
    float _e62 = c_0_;
    if ((_e62 <= 0.0031308)) {
        float _e64 = c_0_;
        _S65_ = (_e64 * 12.92);
    } else {
        float _e66 = c_0_;
        _S65_ = ((1.055 * pow(_e66, 0.41666666)) - 0.055);
    }
    float _e70 = _S65_;
    return _e70;
}

float applyCoverageTransfer_0_u0028_f1_u003b_f1_u003b(inout float cov_2_, inout float coverage_exponent_1_) {
    float clamped_0_ = 0.0;
    float _S59_ = 0.0;
    float _S60_ = 0.0;
    float _e65 = cov_2_;
    clamped_0_ = clamp(_e65, 0.0, 1.0);
    float _e67 = coverage_exponent_1_;
    _S59_ = max(_e67, 1.5258789e-5);
    float _e69 = _S59_;
    if ((abs((_e69 - 1.0)) <= 1e-6)) {
        float _e73 = clamped_0_;
        _S60_ = _e73;
    } else {
        float _e74 = clamped_0_;
        float _e75 = _S59_;
        _S60_ = pow(_e74, _e75);
    }
    float _e77 = _S60_;
    return _e77;
}

vec3 applyCoverageTransfer3_0_u0028_vf3_u003b_f1_u003b(inout vec3 cov_3_, inout float coverage_exponent_2_) {
    float param = 0.0;
    float param_1 = 0.0;
    float param_2 = 0.0;
    float param_3 = 0.0;
    float param_4 = 0.0;
    float param_5 = 0.0;
    float _e69 = cov_3_[0u];
    param = _e69;
    float _e70 = coverage_exponent_2_;
    param_1 = _e70;
    float _e71 = applyCoverageTransfer_0_u0028_f1_u003b_f1_u003b(param, param_1);
    float _e73 = cov_3_[1u];
    param_2 = _e73;
    float _e74 = coverage_exponent_2_;
    param_3 = _e74;
    float _e75 = applyCoverageTransfer_0_u0028_f1_u003b_f1_u003b(param_2, param_3);
    float _e77 = cov_3_[2u];
    param_4 = _e77;
    float _e78 = coverage_exponent_2_;
    param_5 = _e78;
    float _e79 = applyCoverageTransfer_0_u0028_f1_u003b_f1_u003b(param_4, param_5);
    return vec3(_e71, _e75, _e79);
}

vec4 filterSubpixelCoverage_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_b1_u003b(inout float s_m3_0_, inout float s_m2_0_, inout float s_m1_0_, inout float s_0_0_, inout float s_p1_0_, inout float s_p2_0_, inout float s_p3_0_, inout bool reverse_order_0_) {
    float _S58_ = 0.0;
    float left_0_ = 0.0;
    float center_1_ = 0.0;
    float right_0_ = 0.0;
    vec3 cov_0_ = vec3(0.0);
    vec3 cov_1_ = vec3(0.0);
    float _e74 = s_0_0_;
    _S58_ = (0.30078125 * _e74);
    float _e76 = s_m3_0_;
    float _e78 = s_m2_0_;
    float _e81 = s_m1_0_;
    float _e84 = _S58_;
    float _e86 = s_p1_0_;
    left_0_ = (((((0.03125 * _e76) + (0.30078125 * _e78)) + (0.3359375 * _e81)) + _e84) + (0.03125 * _e86));
    float _e89 = s_m2_0_;
    float _e91 = s_m1_0_;
    float _e94 = s_0_0_;
    float _e97 = s_p1_0_;
    float _e100 = s_p2_0_;
    center_1_ = (((((0.03125 * _e89) + (0.30078125 * _e91)) + (0.3359375 * _e94)) + (0.30078125 * _e97)) + (0.03125 * _e100));
    float _e103 = s_m1_0_;
    float _e105 = _S58_;
    float _e107 = s_p1_0_;
    float _e110 = s_p2_0_;
    float _e113 = s_p3_0_;
    right_0_ = (((((0.03125 * _e103) + _e105) + (0.3359375 * _e107)) + (0.30078125 * _e110)) + (0.03125 * _e113));
    bool _e116 = reverse_order_0_;
    if (_e116) {
        float _e117 = right_0_;
        float _e118 = center_1_;
        float _e119 = left_0_;
        cov_0_ = vec3(_e117, _e118, _e119);
    } else {
        float _e121 = left_0_;
        float _e122 = center_1_;
        float _e123 = right_0_;
        cov_0_ = vec3(_e121, _e122, _e123);
    }
    vec3 _e125 = cov_0_;
    cov_1_ = clamp(_e125, vec3(0.0, 0.0, 0.0), vec3(1.0, 1.0, 1.0));
    vec3 _e127 = cov_1_;
    float _e129 = cov_1_[0u];
    float _e131 = cov_1_[1u];
    float _e134 = cov_1_[2u];
    return vec4(_e127.x, _e127.y, _e127.z, clamp((((_e129 + _e131) + _e134) * 0.33333334), 0.0, 1.0));
}

float applyFillRule_0_u0028_f1_u003b_i1_u003b(inout float winding_0_, inout int fill_rule_mode_0_) {
    int _e62 = fill_rule_mode_0_;
    if ((_e62 == 1)) {
        float _e64 = winding_0_;
        return (1.0 - abs(((fract((_e64 * 0.5)) * 2.0) - 1.0)));
    }
    float _e71 = winding_0_;
    return abs(_e71);
}

float snapNearTangentSqrt_0_u0028_f1_u003b_f1_u003b_f1_u003b(inout float disc_0_, inout float b_0_, inout float ac_0_) {
    float _S7_ = 0.0;
    float _e64 = disc_0_;
    float _e65 = b_0_;
    float _e66 = b_0_;
    float _e68 = ac_0_;
    if ((_e64 <= (max((_e65 * _e66), abs(_e68)) * 3e-6))) {
        _S7_ = 0.0;
    } else {
        float _e73 = disc_0_;
        _S7_ = sqrt(_e73);
    }
    float _e75 = _S7_;
    return _e75;
}

vec2 solveVertPoly_0_u0028_vf4_u003b_vf2_u003b(inout vec4 p12_2_, inout vec2 p3_2_) {
    vec2 _S26_ = vec2(0.0);
    vec2 _S27_ = vec2(0.0);
    vec2 a_1_ = vec2(0.0);
    vec2 b_2_ = vec2(0.0);
    float _S28_ = 0.0;
    float _S29_ = 0.0;
    float t1_1_ = 0.0;
    float t2_1_ = 0.0;
    float _S30_ = 0.0;
    float _S31_ = 0.0;
    float _S32_ = 0.0;
    float sq_1_ = 0.0;
    float param_6 = 0.0;
    float param_7 = 0.0;
    float param_8 = 0.0;
    float q_2_ = 0.0;
    float _S33_ = 0.0;
    float q_3_ = 0.0;
    float _S34_ = 0.0;
    float _S35_ = 0.0;
    float _S36_ = 0.0;
    float _S37_ = 0.0;
    float _S38_ = 0.0;
    vec4 _e85 = p12_2_;
    _S26_ = _e85.xy;
    vec4 _e87 = p12_2_;
    _S27_ = _e87.zw;
    vec2 _e89 = _S26_;
    vec2 _e90 = _S27_;
    vec2 _e93 = p3_2_;
    a_1_ = ((_e89 - (_e90 * 2.0)) + _e93);
    vec2 _e95 = _S26_;
    vec2 _e96 = _S27_;
    b_2_ = (_e95 - _e96);
    float _e99 = a_1_[0u];
    _S28_ = _e99;
    float _e100 = _S28_;
    if ((abs(_e100) < 1.5258789e-5)) {
        float _e104 = b_2_[0u];
        _S29_ = _e104;
        float _e105 = _S29_;
        if ((abs(_e105) < 1.5258789e-5)) {
            t1_1_ = 0.0;
        } else {
            float _e109 = p12_2_[0u];
            float _e111 = _S29_;
            t1_1_ = ((_e109 * 0.5) / _e111);
        }
        float _e113 = t1_1_;
        t2_1_ = _e113;
    } else {
        float _e115 = b_2_[0u];
        _S30_ = _e115;
        float _e117 = p12_2_[0u];
        _S31_ = _e117;
        float _e118 = _S28_;
        float _e119 = _S31_;
        _S32_ = (_e118 * _e119);
        float _e121 = _S30_;
        float _e122 = _S30_;
        float _e124 = _S32_;
        param_6 = ((_e121 * _e122) - _e124);
        float _e126 = _S30_;
        param_7 = _e126;
        float _e127 = _S32_;
        param_8 = _e127;
        float _e128 = snapNearTangentSqrt_0_u0028_f1_u003b_f1_u003b_f1_u003b(param_6, param_7, param_8);
        sq_1_ = _e128;
        float _e129 = _S30_;
        if ((_e129 >= 0.0)) {
            float _e131 = _S30_;
            float _e132 = sq_1_;
            q_2_ = (_e131 + _e132);
            float _e134 = q_2_;
            float _e135 = _S28_;
            _S33_ = (_e134 / _e135);
            float _e137 = q_2_;
            if ((abs(_e137) < 1.5258789e-5)) {
                t1_1_ = 0.0;
            } else {
                float _e140 = _S31_;
                float _e141 = q_2_;
                t1_1_ = (_e140 / _e141);
            }
            float _e143 = _S33_;
            t2_1_ = _e143;
        } else {
            float _e144 = _S30_;
            float _e145 = sq_1_;
            q_3_ = (_e144 - _e145);
            float _e147 = q_3_;
            float _e148 = _S28_;
            _S34_ = (_e147 / _e148);
            float _e150 = q_3_;
            if ((abs(_e150) < 1.5258789e-5)) {
                t1_1_ = 0.0;
            } else {
                float _e153 = _S31_;
                float _e154 = q_3_;
                t1_1_ = (_e153 / _e154);
            }
            float _e156 = t1_1_;
            _S35_ = _e156;
            float _e157 = _S34_;
            t1_1_ = _e157;
            float _e158 = _S35_;
            t2_1_ = _e158;
        }
    }
    float _e160 = a_1_[1u];
    _S36_ = _e160;
    float _e162 = b_2_[1u];
    _S37_ = (_e162 * 2.0);
    float _e165 = p12_2_[1u];
    _S38_ = _e165;
    float _e166 = _S36_;
    float _e167 = t1_1_;
    float _e169 = _S37_;
    float _e171 = t1_1_;
    float _e173 = _S38_;
    float _e175 = _S36_;
    float _e176 = t2_1_;
    float _e178 = _S37_;
    float _e180 = t2_1_;
    float _e182 = _S38_;
    return vec2(((((_e166 * _e167) - _e169) * _e171) + _e173), ((((_e175 * _e176) - _e178) * _e180) + _e182));
}

float rootCodeCoord_0_u0028_f1_u003b(inout float v_0_) {
    float _S6_ = 0.0;
    float _e62 = v_0_;
    if ((abs(_e62) <= 1.5258789e-5)) {
        _S6_ = 0.0;
    } else {
        float _e65 = v_0_;
        _S6_ = _e65;
    }
    float _e66 = _S6_;
    return _e66;
}

uint calcRootCode_0_u0028_f1_u003b_f1_u003b_f1_u003b(inout float y1_0_, inout float y2_0_, inout float y3_0_) {
    float param_9 = 0.0;
    float param_10 = 0.0;
    float param_11 = 0.0;
    float _e66 = y3_0_;
    param_9 = _e66;
    float _e67 = rootCodeCoord_0_u0028_f1_u003b(param_9);
    float _e72 = y2_0_;
    param_10 = _e72;
    float _e73 = rootCodeCoord_0_u0028_f1_u003b(param_10);
    float _e78 = y1_0_;
    param_11 = _e78;
    float _e79 = rootCodeCoord_0_u0028_f1_u003b(param_11);
    return ((11892u >> (((floatBitsToUint(_e67) >> 29u) & 4u) | ((((floatBitsToUint(_e73) >> 30u) & 2u) | ((floatBitsToUint(_e79) >> 31u) & 4294967293u)) & 4294967291u))) & 257u);
}

ivec2 offsetCurveLoc_0_u0028_vi2_u003b_i1_u003b(inout ivec2 base_0_, inout int offset_1_) {
    int _S5_ = 0;
    ivec2 loc_1_ = ivec2(0);
    int _e65 = base_0_[0u];
    int _e66 = offset_1_;
    _S5_ = (_e65 + _e66);
    int _e68 = _S5_;
    int _e70 = base_0_[1u];
    loc_1_ = ivec2(_e68, _e70);
    int _e73 = loc_1_[1u];
    int _e74 = _S5_;
    loc_1_[1u] = (_e73 + (_e74 >> uint(12)));
    int _e80 = loc_1_[0u];
    loc_1_[0u] = (_e80 & 4095);
    ivec2 _e83 = loc_1_;
    return _e83;
}

bool accumulateVertContribution_0_u0028_f1_u003b_f1_u003b_vf2_u003b_vf2_u003b_vi2_u003b_i1_u003b_tA21_u003b(inout float ycov_0_, inout float ywgt_0_, inout vec2 rc_1_, inout vec2 ppe_1_, inout ivec2 cLoc_1_, inout int texLayer_1_, sampler2DArray curve_tex_1_) {
    ivec4 _S39_ = ivec4(0);
    vec4 tex0_1_ = vec4(0.0);
    ivec4 _S40_ = ivec4(0);
    ivec2 param_12 = ivec2(0);
    int param_13 = 0;
    vec4 p12_3_ = vec4(0.0);
    vec2 p3_3_ = vec2(0.0);
    float _S41_ = 0.0;
    uint code_1_ = 0u;
    float param_14 = 0.0;
    float param_15 = 0.0;
    float param_16 = 0.0;
    vec2 r_1_ = vec2(0.0);
    vec4 param_17 = vec4(0.0);
    vec2 param_18 = vec2(0.0);
    float _S42_ = 0.0;
    float _S43_ = 0.0;
    ivec2 _e84 = cLoc_1_;
    int _e85 = texLayer_1_;
    _S39_ = ivec4(_e84.x, _e84.y, _e85, 0);
    ivec4 _e89 = _S39_;
    ivec3 _e90 = _e89.xyz;
    int _e92 = _S39_[3u];
    vec4 _e98 = texelFetch(curve_tex_1_, ivec3(ivec2(_e90.x, _e90.y), int(_e90.z)), _e92);
    tex0_1_ = _e98;
    ivec2 _e99 = cLoc_1_;
    param_12 = _e99;
    param_13 = 1;
    ivec2 _e100 = offsetCurveLoc_0_u0028_vi2_u003b_i1_u003b(param_12, param_13);
    int _e101 = texLayer_1_;
    _S40_ = ivec4(_e100.x, _e100.y, _e101, 0);
    vec4 _e105 = tex0_1_;
    vec2 _e106 = _e105.xy;
    vec4 _e107 = tex0_1_;
    vec2 _e108 = _e107.zw;
    vec2 _e114 = rc_1_;
    p12_3_ = (vec4(_e106.x, _e106.y, _e108.x, _e108.y) - vec4(_e114.x, _e114.y, _e114.x, _e114.y));
    ivec4 _e121 = _S40_;
    ivec3 _e122 = _e121.xyz;
    int _e124 = _S40_[3u];
    vec4 _e130 = texelFetch(curve_tex_1_, ivec3(ivec2(_e122.x, _e122.y), int(_e122.z)), _e124);
    vec2 _e132 = rc_1_;
    p3_3_ = (_e130.xy - _e132);
    float _e135 = ppe_1_[1u];
    _S41_ = _e135;
    float _e137 = p12_3_[1u];
    float _e139 = p12_3_[3u];
    float _e142 = p3_3_[1u];
    float _e144 = _S41_;
    if (((max(max(_e137, _e139), _e142) * _e144) < -0.5)) {
        return false;
    }
    float _e148 = p12_3_[0u];
    param_14 = _e148;
    float _e150 = p12_3_[2u];
    param_15 = _e150;
    float _e152 = p3_3_[0u];
    param_16 = _e152;
    uint _e153 = calcRootCode_0_u0028_f1_u003b_f1_u003b_f1_u003b(param_14, param_15, param_16);
    code_1_ = _e153;
    uint _e154 = code_1_;
    if ((_e154 != 0u)) {
        vec4 _e156 = p12_3_;
        param_17 = _e156;
        vec2 _e157 = p3_3_;
        param_18 = _e157;
        vec2 _e158 = solveVertPoly_0_u0028_vf4_u003b_vf2_u003b(param_17, param_18);
        float _e159 = _S41_;
        r_1_ = (_e158 * _e159);
        uint _e161 = code_1_;
        if (((_e161 & 1u) != 0u)) {
            float _e165 = r_1_[0u];
            _S42_ = _e165;
            float _e166 = ycov_0_;
            float _e167 = _S42_;
            ycov_0_ = (_e166 - clamp((_e167 + 0.5), 0.0, 1.0));
            float _e171 = ywgt_0_;
            float _e172 = _S42_;
            ywgt_0_ = max(_e171, clamp((1.0 - (abs(_e172) * 2.0)), 0.0, 1.0));
        }
        uint _e178 = code_1_;
        if ((_e178 > 1u)) {
            float _e181 = r_1_[1u];
            _S43_ = _e181;
            float _e182 = ycov_0_;
            float _e183 = _S43_;
            ycov_0_ = (_e182 + clamp((_e183 + 0.5), 0.0, 1.0));
            float _e187 = ywgt_0_;
            float _e188 = _S43_;
            ywgt_0_ = max(_e187, clamp((1.0 - (abs(_e188) * 2.0)), 0.0, 1.0));
        }
    }
    return true;
}

vec2 solveHorizPoly_0_u0028_vf4_u003b_vf2_u003b(inout vec4 p12_0_, inout vec2 p3_0_) {
    vec2 _S8_ = vec2(0.0);
    vec2 _S9_ = vec2(0.0);
    vec2 a_0_ = vec2(0.0);
    vec2 b_1_ = vec2(0.0);
    float _S10_ = 0.0;
    float _S11_ = 0.0;
    float t1_0_ = 0.0;
    float t2_0_ = 0.0;
    float _S12_ = 0.0;
    float _S13_ = 0.0;
    float _S14_ = 0.0;
    float sq_0_ = 0.0;
    float param_19 = 0.0;
    float param_20 = 0.0;
    float param_21 = 0.0;
    float q_0_ = 0.0;
    float _S15_ = 0.0;
    float q_1_ = 0.0;
    float _S16_ = 0.0;
    float _S17_ = 0.0;
    float _S18_ = 0.0;
    float _S19_ = 0.0;
    float _S20_ = 0.0;
    vec4 _e85 = p12_0_;
    _S8_ = _e85.xy;
    vec4 _e87 = p12_0_;
    _S9_ = _e87.zw;
    vec2 _e89 = _S8_;
    vec2 _e90 = _S9_;
    vec2 _e93 = p3_0_;
    a_0_ = ((_e89 - (_e90 * 2.0)) + _e93);
    vec2 _e95 = _S8_;
    vec2 _e96 = _S9_;
    b_1_ = (_e95 - _e96);
    float _e99 = a_0_[1u];
    _S10_ = _e99;
    float _e100 = _S10_;
    if ((abs(_e100) < 1.5258789e-5)) {
        float _e104 = b_1_[1u];
        _S11_ = _e104;
        float _e105 = _S11_;
        if ((abs(_e105) < 1.5258789e-5)) {
            t1_0_ = 0.0;
        } else {
            float _e109 = p12_0_[1u];
            float _e111 = _S11_;
            t1_0_ = ((_e109 * 0.5) / _e111);
        }
        float _e113 = t1_0_;
        t2_0_ = _e113;
    } else {
        float _e115 = b_1_[1u];
        _S12_ = _e115;
        float _e117 = p12_0_[1u];
        _S13_ = _e117;
        float _e118 = _S10_;
        float _e119 = _S13_;
        _S14_ = (_e118 * _e119);
        float _e121 = _S12_;
        float _e122 = _S12_;
        float _e124 = _S14_;
        param_19 = ((_e121 * _e122) - _e124);
        float _e126 = _S12_;
        param_20 = _e126;
        float _e127 = _S14_;
        param_21 = _e127;
        float _e128 = snapNearTangentSqrt_0_u0028_f1_u003b_f1_u003b_f1_u003b(param_19, param_20, param_21);
        sq_0_ = _e128;
        float _e129 = _S12_;
        if ((_e129 >= 0.0)) {
            float _e131 = _S12_;
            float _e132 = sq_0_;
            q_0_ = (_e131 + _e132);
            float _e134 = q_0_;
            float _e135 = _S10_;
            _S15_ = (_e134 / _e135);
            float _e137 = q_0_;
            if ((abs(_e137) < 1.5258789e-5)) {
                t1_0_ = 0.0;
            } else {
                float _e140 = _S13_;
                float _e141 = q_0_;
                t1_0_ = (_e140 / _e141);
            }
            float _e143 = _S15_;
            t2_0_ = _e143;
        } else {
            float _e144 = _S12_;
            float _e145 = sq_0_;
            q_1_ = (_e144 - _e145);
            float _e147 = q_1_;
            float _e148 = _S10_;
            _S16_ = (_e147 / _e148);
            float _e150 = q_1_;
            if ((abs(_e150) < 1.5258789e-5)) {
                t1_0_ = 0.0;
            } else {
                float _e153 = _S13_;
                float _e154 = q_1_;
                t1_0_ = (_e153 / _e154);
            }
            float _e156 = t1_0_;
            _S17_ = _e156;
            float _e157 = _S16_;
            t1_0_ = _e157;
            float _e158 = _S17_;
            t2_0_ = _e158;
        }
    }
    float _e160 = a_0_[0u];
    _S18_ = _e160;
    float _e162 = b_1_[0u];
    _S19_ = (_e162 * 2.0);
    float _e165 = p12_0_[0u];
    _S20_ = _e165;
    float _e166 = _S18_;
    float _e167 = t1_0_;
    float _e169 = _S19_;
    float _e171 = t1_0_;
    float _e173 = _S20_;
    float _e175 = _S18_;
    float _e176 = t2_0_;
    float _e178 = _S19_;
    float _e180 = t2_0_;
    float _e182 = _S20_;
    return vec2(((((_e166 * _e167) - _e169) * _e171) + _e173), ((((_e175 * _e176) - _e178) * _e180) + _e182));
}

bool accumulateHorizContribution_0_u0028_f1_u003b_f1_u003b_vf2_u003b_vf2_u003b_vi2_u003b_i1_u003b_tA21_u003b(inout float xcov_0_, inout float xwgt_0_, inout vec2 rc_0_, inout vec2 ppe_0_, inout ivec2 cLoc_0_, inout int texLayer_0_, sampler2DArray curve_tex_0_) {
    ivec4 _S21_ = ivec4(0);
    vec4 tex0_0_ = vec4(0.0);
    ivec4 _S22_ = ivec4(0);
    ivec2 param_22 = ivec2(0);
    int param_23 = 0;
    vec4 p12_1_ = vec4(0.0);
    vec2 p3_1_ = vec2(0.0);
    float _S23_ = 0.0;
    uint code_0_ = 0u;
    float param_24 = 0.0;
    float param_25 = 0.0;
    float param_26 = 0.0;
    vec2 r_0_ = vec2(0.0);
    vec4 param_27 = vec4(0.0);
    vec2 param_28 = vec2(0.0);
    float _S24_ = 0.0;
    float _S25_ = 0.0;
    ivec2 _e84 = cLoc_0_;
    int _e85 = texLayer_0_;
    _S21_ = ivec4(_e84.x, _e84.y, _e85, 0);
    ivec4 _e89 = _S21_;
    ivec3 _e90 = _e89.xyz;
    int _e92 = _S21_[3u];
    vec4 _e98 = texelFetch(curve_tex_0_, ivec3(ivec2(_e90.x, _e90.y), int(_e90.z)), _e92);
    tex0_0_ = _e98;
    ivec2 _e99 = cLoc_0_;
    param_22 = _e99;
    param_23 = 1;
    ivec2 _e100 = offsetCurveLoc_0_u0028_vi2_u003b_i1_u003b(param_22, param_23);
    int _e101 = texLayer_0_;
    _S22_ = ivec4(_e100.x, _e100.y, _e101, 0);
    vec4 _e105 = tex0_0_;
    vec2 _e106 = _e105.xy;
    vec4 _e107 = tex0_0_;
    vec2 _e108 = _e107.zw;
    vec2 _e114 = rc_0_;
    p12_1_ = (vec4(_e106.x, _e106.y, _e108.x, _e108.y) - vec4(_e114.x, _e114.y, _e114.x, _e114.y));
    ivec4 _e121 = _S22_;
    ivec3 _e122 = _e121.xyz;
    int _e124 = _S22_[3u];
    vec4 _e130 = texelFetch(curve_tex_0_, ivec3(ivec2(_e122.x, _e122.y), int(_e122.z)), _e124);
    vec2 _e132 = rc_0_;
    p3_1_ = (_e130.xy - _e132);
    float _e135 = ppe_0_[0u];
    _S23_ = _e135;
    float _e137 = p12_1_[0u];
    float _e139 = p12_1_[2u];
    float _e142 = p3_1_[0u];
    float _e144 = _S23_;
    if (((max(max(_e137, _e139), _e142) * _e144) < -0.5)) {
        return false;
    }
    float _e148 = p12_1_[1u];
    param_24 = _e148;
    float _e150 = p12_1_[3u];
    param_25 = _e150;
    float _e152 = p3_1_[1u];
    param_26 = _e152;
    uint _e153 = calcRootCode_0_u0028_f1_u003b_f1_u003b_f1_u003b(param_24, param_25, param_26);
    code_0_ = _e153;
    uint _e154 = code_0_;
    if ((_e154 != 0u)) {
        vec4 _e156 = p12_1_;
        param_27 = _e156;
        vec2 _e157 = p3_1_;
        param_28 = _e157;
        vec2 _e158 = solveHorizPoly_0_u0028_vf4_u003b_vf2_u003b(param_27, param_28);
        float _e159 = _S23_;
        r_0_ = (_e158 * _e159);
        uint _e161 = code_0_;
        if (((_e161 & 1u) != 0u)) {
            float _e165 = r_0_[0u];
            _S24_ = _e165;
            float _e166 = xcov_0_;
            float _e167 = _S24_;
            xcov_0_ = (_e166 + clamp((_e167 + 0.5), 0.0, 1.0));
            float _e171 = xwgt_0_;
            float _e172 = _S24_;
            xwgt_0_ = max(_e171, clamp((1.0 - (abs(_e172) * 2.0)), 0.0, 1.0));
        }
        uint _e178 = code_0_;
        if ((_e178 > 1u)) {
            float _e181 = r_0_[1u];
            _S25_ = _e181;
            float _e182 = xcov_0_;
            float _e183 = _S25_;
            xcov_0_ = (_e182 - clamp((_e183 + 0.5), 0.0, 1.0));
            float _e187 = xwgt_0_;
            float _e188 = _S25_;
            xwgt_0_ = max(_e187, clamp((1.0 - (abs(_e188) * 2.0)), 0.0, 1.0));
        }
    }
    return true;
}

ivec2 decodeBandCurveLocCommon_0_u0028_vu2_u003b(inout uvec2 ref_2_) {
    uint _e62 = ref_2_[0u];
    uint _e66 = ref_2_[1u];
    return ivec2(int((_e62 & 4095u)), int((_e66 & 16383u)));
}

ivec2 decodeBandCurveLoc_0_u0028_vu2_u003b(inout uvec2 ref_3_) {
    uvec2 param_29 = uvec2(0u);
    uvec2 _e62 = ref_3_;
    param_29 = _e62;
    ivec2 _e63 = decodeBandCurveLocCommon_0_u0028_vu2_u003b(param_29);
    return _e63;
}

int decodeBandCurveFirstMemberCommon_0_u0028_vu2_u003b(inout uvec2 ref_0_) {
    uint _e62 = ref_0_[0u];
    return int((_e62 >> 12u));
}

bool isCoverageBandSpanOwner_0_u0028_vu2_u003b_i1_u003b_i1_u003b(inout uvec2 ref_1_, inout int band_0_, inout int spanFirst_0_) {
    uvec2 param_30 = uvec2(0u);
    int _e64 = band_0_;
    uvec2 _e65 = ref_1_;
    param_30 = _e65;
    int _e66 = decodeBandCurveFirstMemberCommon_0_u0028_vu2_u003b(param_30);
    int _e67 = spanFirst_0_;
    return (_e64 == max(_e66, _e67));
}

ivec2 calcBandLoc_0_u0028_vi2_u003b_u1_u003b(inout ivec2 glyphLoc_0_, inout uint offset_0_) {
    int _S4_ = 0;
    ivec2 loc_0_ = ivec2(0);
    int _e65 = glyphLoc_0_[0u];
    uint _e66 = offset_0_;
    _S4_ = (_e65 + int(_e66));
    int _e69 = _S4_;
    int _e71 = glyphLoc_0_[1u];
    loc_0_ = ivec2(_e69, _e71);
    int _e74 = loc_0_[1u];
    int _e75 = _S4_;
    loc_0_[1u] = (_e74 + (_e75 >> uint(12)));
    int _e81 = loc_0_[0u];
    loc_0_[0u] = (_e81 & 4095);
    ivec2 _e84 = loc_0_;
    return _e84;
}

CoverageBandSpan_0_ CoverageBandSpan_x24init_0_u0028_i1_u003b_i1_u003b(inout int first_1_, inout int last_1_) {
    CoverageBandSpan_0_ _S2_ = CoverageBandSpan_0_(0, 0);
    int _e63 = first_1_;
    _S2_.first_0_ = _e63;
    int _e65 = last_1_;
    _S2_.last_0_ = _e65;
    CoverageBandSpan_0_ _e67 = _S2_;
    return _e67;
}

CoverageBandSpan_0_ computeCoverageBandSpan_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_i1_u003b(inout float coord_0_, inout float eppAxis_0_, inout float bandScale_0_, inout float bandOffset_0_, inout int bandMax_0_) {
    float center_0_ = 0.0;
    float _S3_ = 0.0;
    int first_2_ = 0;
    int param_31 = 0;
    int param_32 = 0;
    float _e70 = coord_0_;
    float _e71 = bandScale_0_;
    float _e73 = bandOffset_0_;
    center_0_ = ((_e70 * _e71) + _e73);
    float _e75 = eppAxis_0_;
    float _e76 = bandScale_0_;
    _S3_ = max((abs((_e75 * _e76)) * 0.5), 1e-5);
    float _e81 = center_0_;
    float _e82 = _S3_;
    int _e85 = bandMax_0_;
    first_2_ = min(max(int((_e81 - _e82)), 0), _e85);
    int _e87 = first_2_;
    float _e88 = center_0_;
    float _e89 = _S3_;
    int _e92 = bandMax_0_;
    int _e95 = first_2_;
    param_31 = _e95;
    param_32 = max(_e87, min(max(int((_e88 + _e89)), 0), _e92));
    CoverageBandSpan_0_ _e96 = CoverageBandSpan_x24init_0_u0028_i1_u003b_i1_u003b(param_31, param_32);
    return _e96;
}

float evalGlyphCoverageRaw_0_u0028_vf2_u003b_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b_tA21_u003b_utA21_u003b(inout vec2 rc_2_, inout vec2 epp_0_, inout vec2 ppe_2_, inout ivec2 glyph_loc_0_, inout ivec2 band_max_0_, inout vec4 banding_0_, inout int layer_0_, sampler2DArray curve_tex_2_, usampler2DArray band_tex_0_) {
    int _S45_ = 0;
    CoverageBandSpan_0_ hSpan_0_ = CoverageBandSpan_0_(0, 0);
    float param_33 = 0.0;
    float param_34 = 0.0;
    float param_35 = 0.0;
    float param_36 = 0.0;
    int param_37 = 0;
    CoverageBandSpan_0_ vSpan_0_ = CoverageBandSpan_0_(0, 0);
    float param_38 = 0.0;
    float param_39 = 0.0;
    float param_40 = 0.0;
    float param_41 = 0.0;
    int param_42 = 0;
    float xcov_1_ = 0.0;
    float xwgt_1_ = 0.0;
    bool _S46_ = false;
    int band_1_ = 0;
    ivec4 _S47_ = ivec4(0);
    ivec2 param_43 = ivec2(0);
    uint param_44 = 0u;
    uvec2 hbd_0_ = uvec2(0u);
    ivec2 _S48_ = ivec2(0);
    ivec2 param_45 = ivec2(0);
    uint param_46 = 0u;
    int _S49_ = 0;
    int i_0_ = 0;
    ivec4 _S50_ = ivec4(0);
    ivec2 param_47 = ivec2(0);
    uint param_48 = 0u;
    uvec2 ref_4_ = uvec2(0u);
    bool _S44_ = false;
    uvec2 param_49 = uvec2(0u);
    int param_50 = 0;
    int param_51 = 0;
    bool _S51_ = false;
    uvec2 param_52 = uvec2(0u);
    float param_53 = 0.0;
    float param_54 = 0.0;
    vec2 param_55 = vec2(0.0);
    vec2 param_56 = vec2(0.0);
    ivec2 param_57 = ivec2(0);
    int param_58 = 0;
    float ycov_1_ = 0.0;
    float ywgt_1_ = 0.0;
    bool _S52_ = false;
    ivec4 _S53_ = ivec4(0);
    ivec2 param_59 = ivec2(0);
    uint param_60 = 0u;
    uvec2 vbd_0_ = uvec2(0u);
    ivec2 _S54_ = ivec2(0);
    ivec2 param_61 = ivec2(0);
    uint param_62 = 0u;
    int _S55_ = 0;
    ivec4 _S56_ = ivec4(0);
    ivec2 param_63 = ivec2(0);
    uint param_64 = 0u;
    uvec2 ref_5_ = uvec2(0u);
    uvec2 param_65 = uvec2(0u);
    int param_66 = 0;
    int param_67 = 0;
    bool _S57_ = false;
    uvec2 param_68 = uvec2(0u);
    float param_69 = 0.0;
    float param_70 = 0.0;
    vec2 param_71 = vec2(0.0);
    vec2 param_72 = vec2(0.0);
    ivec2 param_73 = ivec2(0);
    int param_74 = 0;
    float param_75 = 0.0;
    int param_76 = 0;
    float param_77 = 0.0;
    int param_78 = 0;
    float param_79 = 0.0;
    int param_80 = 0;
    int _e144 = band_max_0_[1u];
    _S45_ = _e144;
    float _e146 = rc_2_[1u];
    param_33 = _e146;
    float _e148 = epp_0_[1u];
    param_34 = _e148;
    float _e150 = banding_0_[1u];
    param_35 = _e150;
    float _e152 = banding_0_[3u];
    param_36 = _e152;
    int _e153 = _S45_;
    param_37 = _e153;
    CoverageBandSpan_0_ _e154 = computeCoverageBandSpan_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_i1_u003b(param_33, param_34, param_35, param_36, param_37);
    hSpan_0_ = _e154;
    float _e156 = rc_2_[0u];
    param_38 = _e156;
    float _e158 = epp_0_[0u];
    param_39 = _e158;
    float _e160 = banding_0_[0u];
    param_40 = _e160;
    float _e162 = banding_0_[2u];
    param_41 = _e162;
    int _e164 = band_max_0_[0u];
    param_42 = _e164;
    CoverageBandSpan_0_ _e165 = computeCoverageBandSpan_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_i1_u003b(param_38, param_39, param_40, param_41, param_42);
    vSpan_0_ = _e165;
    xcov_1_ = 0.0;
    xwgt_1_ = 0.0;
    int _e167 = hSpan_0_.first_0_;
    int _e169 = hSpan_0_.last_0_;
    _S46_ = (_e167 != _e169);
    int _e172 = hSpan_0_.first_0_;
    band_1_ = _e172;
    while(true) {
        int _e173 = band_1_;
        int _e175 = hSpan_0_.last_0_;
        if ((_e173 <= _e175)) {
        } else {
            break;
        }
        int _e177 = band_1_;
        ivec2 _e179 = glyph_loc_0_;
        param_43 = _e179;
        param_44 = uint(_e177);
        ivec2 _e180 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_43, param_44);
        int _e181 = layer_0_;
        _S47_ = ivec4(_e180.x, _e180.y, _e181, 0);
        ivec4 _e185 = _S47_;
        ivec3 _e186 = _e185.xyz;
        int _e188 = _S47_[3u];
        uvec4 _e194 = texelFetch(band_tex_0_, ivec3(ivec2(_e186.x, _e186.y), int(_e186.z)), _e188);
        hbd_0_ = _e194.xy;
        ivec2 _e196 = glyph_loc_0_;
        param_45 = _e196;
        uint _e198 = hbd_0_[1u];
        param_46 = _e198;
        ivec2 _e199 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_45, param_46);
        _S48_ = _e199;
        uint _e201 = hbd_0_[0u];
        _S49_ = int(_e201);
        i_0_ = 0;
        while(true) {
            int _e203 = i_0_;
            int _e204 = _S49_;
            if ((_e203 < _e204)) {
            } else {
                break;
            }
            int _e206 = i_0_;
            ivec2 _e208 = _S48_;
            param_47 = _e208;
            param_48 = uint(_e206);
            ivec2 _e209 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_47, param_48);
            int _e210 = layer_0_;
            _S50_ = ivec4(_e209.x, _e209.y, _e210, 0);
            ivec4 _e214 = _S50_;
            ivec3 _e215 = _e214.xyz;
            int _e217 = _S50_[3u];
            uvec4 _e223 = texelFetch(band_tex_0_, ivec3(ivec2(_e215.x, _e215.y), int(_e215.z)), _e217);
            ref_4_ = _e223.xy;
            bool _e225 = _S46_;
            if (_e225) {
                uvec2 _e226 = ref_4_;
                param_49 = _e226;
                int _e227 = band_1_;
                param_50 = _e227;
                int _e229 = hSpan_0_.first_0_;
                param_51 = _e229;
                bool _e230 = isCoverageBandSpanOwner_0_u0028_vu2_u003b_i1_u003b_i1_u003b(param_49, param_50, param_51);
                _S44_ = !(_e230);
            } else {
                _S44_ = false;
            }
            bool _e232 = _S44_;
            if (_e232) {
                int _e233 = i_0_;
                i_0_ = (_e233 + 1);
                continue;
            }
            uvec2 _e235 = ref_4_;
            param_52 = _e235;
            ivec2 _e236 = decodeBandCurveLoc_0_u0028_vu2_u003b(param_52);
            float _e237 = xcov_1_;
            param_53 = _e237;
            float _e238 = xwgt_1_;
            param_54 = _e238;
            vec2 _e239 = rc_2_;
            param_55 = _e239;
            vec2 _e240 = ppe_2_;
            param_56 = _e240;
            param_57 = _e236;
            int _e241 = layer_0_;
            param_58 = _e241;
            bool _e242 = accumulateHorizContribution_0_u0028_f1_u003b_f1_u003b_vf2_u003b_vf2_u003b_vi2_u003b_i1_u003b_tA21_u003b(param_53, param_54, param_55, param_56, param_57, param_58, curve_tex_2_);
            float _e243 = param_53;
            xcov_1_ = _e243;
            float _e244 = param_54;
            xwgt_1_ = _e244;
            _S51_ = _e242;
            bool _e245 = _S51_;
            if (!(_e245)) {
                break;
            }
            int _e247 = i_0_;
            i_0_ = (_e247 + 1);
            continue;
        }
        int _e249 = band_1_;
        band_1_ = (_e249 + 1);
        continue;
    }
    ycov_1_ = 0.0;
    ywgt_1_ = 0.0;
    int _e252 = vSpan_0_.first_0_;
    int _e254 = vSpan_0_.last_0_;
    _S52_ = (_e252 != _e254);
    int _e257 = vSpan_0_.first_0_;
    band_1_ = _e257;
    while(true) {
        int _e258 = band_1_;
        int _e260 = vSpan_0_.last_0_;
        if ((_e258 <= _e260)) {
        } else {
            break;
        }
        int _e262 = _S45_;
        int _e264 = band_1_;
        ivec2 _e267 = glyph_loc_0_;
        param_59 = _e267;
        param_60 = uint(((_e262 + 1) + _e264));
        ivec2 _e268 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_59, param_60);
        int _e269 = layer_0_;
        _S53_ = ivec4(_e268.x, _e268.y, _e269, 0);
        ivec4 _e273 = _S53_;
        ivec3 _e274 = _e273.xyz;
        int _e276 = _S53_[3u];
        uvec4 _e282 = texelFetch(band_tex_0_, ivec3(ivec2(_e274.x, _e274.y), int(_e274.z)), _e276);
        vbd_0_ = _e282.xy;
        ivec2 _e284 = glyph_loc_0_;
        param_61 = _e284;
        uint _e286 = vbd_0_[1u];
        param_62 = _e286;
        ivec2 _e287 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_61, param_62);
        _S54_ = _e287;
        uint _e289 = vbd_0_[0u];
        _S55_ = int(_e289);
        i_0_ = 0;
        while(true) {
            int _e291 = i_0_;
            int _e292 = _S55_;
            if ((_e291 < _e292)) {
            } else {
                break;
            }
            int _e294 = i_0_;
            ivec2 _e296 = _S54_;
            param_63 = _e296;
            param_64 = uint(_e294);
            ivec2 _e297 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_63, param_64);
            int _e298 = layer_0_;
            _S56_ = ivec4(_e297.x, _e297.y, _e298, 0);
            ivec4 _e302 = _S56_;
            ivec3 _e303 = _e302.xyz;
            int _e305 = _S56_[3u];
            uvec4 _e311 = texelFetch(band_tex_0_, ivec3(ivec2(_e303.x, _e303.y), int(_e303.z)), _e305);
            ref_5_ = _e311.xy;
            bool _e313 = _S52_;
            if (_e313) {
                uvec2 _e314 = ref_5_;
                param_65 = _e314;
                int _e315 = band_1_;
                param_66 = _e315;
                int _e317 = vSpan_0_.first_0_;
                param_67 = _e317;
                bool _e318 = isCoverageBandSpanOwner_0_u0028_vu2_u003b_i1_u003b_i1_u003b(param_65, param_66, param_67);
                _S44_ = !(_e318);
            } else {
                _S44_ = false;
            }
            bool _e320 = _S44_;
            if (_e320) {
                int _e321 = i_0_;
                i_0_ = (_e321 + 1);
                continue;
            }
            uvec2 _e323 = ref_5_;
            param_68 = _e323;
            ivec2 _e324 = decodeBandCurveLoc_0_u0028_vu2_u003b(param_68);
            float _e325 = ycov_1_;
            param_69 = _e325;
            float _e326 = ywgt_1_;
            param_70 = _e326;
            vec2 _e327 = rc_2_;
            param_71 = _e327;
            vec2 _e328 = ppe_2_;
            param_72 = _e328;
            param_73 = _e324;
            int _e329 = layer_0_;
            param_74 = _e329;
            bool _e330 = accumulateVertContribution_0_u0028_f1_u003b_f1_u003b_vf2_u003b_vf2_u003b_vi2_u003b_i1_u003b_tA21_u003b(param_69, param_70, param_71, param_72, param_73, param_74, curve_tex_2_);
            float _e331 = param_69;
            ycov_1_ = _e331;
            float _e332 = param_70;
            ywgt_1_ = _e332;
            _S57_ = _e330;
            bool _e333 = _S57_;
            if (!(_e333)) {
                break;
            }
            int _e335 = i_0_;
            i_0_ = (_e335 + 1);
            continue;
        }
        int _e337 = band_1_;
        band_1_ = (_e337 + 1);
        continue;
    }
    float _e339 = xcov_1_;
    float _e340 = xwgt_1_;
    float _e342 = ycov_1_;
    float _e343 = ywgt_1_;
    float _e346 = xwgt_1_;
    float _e347 = ywgt_1_;
    param_75 = (((_e339 * _e340) + (_e342 * _e343)) / max((_e346 + _e347), 1.5258789e-5));
    param_76 = 0;
    float _e351 = applyFillRule_0_u0028_f1_u003b_i1_u003b(param_75, param_76);
    float _e352 = xcov_1_;
    param_77 = _e352;
    param_78 = 0;
    float _e353 = applyFillRule_0_u0028_f1_u003b_i1_u003b(param_77, param_78);
    float _e354 = ycov_1_;
    param_79 = _e354;
    param_80 = 0;
    float _e355 = applyFillRule_0_u0028_f1_u003b_i1_u003b(param_79, param_80);
    return clamp(max(_e351, min(_e353, _e355)), 0.0, 1.0);
}

float evalGlyphSample_0_u0028_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b_tA21_u003b_utA21_u003b(inout vec2 rc_3_, inout vec2 display_epp_0_, inout ivec2 glyph_loc_1_, inout ivec2 band_max_1_, inout vec4 banding_1_, inout int layer_1_, sampler2DArray curve_tex_3_, usampler2DArray band_tex_1_) {
    vec2 param_81 = vec2(0.0);
    vec2 param_82 = vec2(0.0);
    vec2 param_83 = vec2(0.0);
    ivec2 param_84 = ivec2(0);
    ivec2 param_85 = ivec2(0);
    vec4 param_86 = vec4(0.0);
    int param_87 = 0;
    float _e76 = display_epp_0_[0u];
    float _e80 = display_epp_0_[1u];
    vec2 _e84 = rc_3_;
    param_81 = _e84;
    vec2 _e85 = display_epp_0_;
    param_82 = _e85;
    param_83 = vec2((1.0 / max(_e76, 1.5258789e-5)), (1.0 / max(_e80, 1.5258789e-5)));
    ivec2 _e86 = glyph_loc_1_;
    param_84 = _e86;
    ivec2 _e87 = band_max_1_;
    param_85 = _e87;
    vec4 _e88 = banding_1_;
    param_86 = _e88;
    int _e89 = layer_1_;
    param_87 = _e89;
    float _e90 = evalGlyphCoverageRaw_0_u0028_vf2_u003b_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b_tA21_u003b_utA21_u003b(param_81, param_82, param_83, param_84, param_85, param_86, param_87, curve_tex_3_, band_tex_1_);
    return _e90;
}

vec2 subpixelCoverageEdgePixels_0_u0028_vf2_u003b_vf2_u003b_i1_u003b(inout vec2 display_dx_0_, inout vec2 display_dy_0_, inout int subpixel_order_1_) {
    vec2 dx_0_ = vec2(0.0);
    vec2 dy_0_ = vec2(0.0);
    vec2 _S1_ = vec2(0.0);
    vec2 _e66 = display_dx_0_;
    dx_0_ = abs(_e66);
    vec2 _e68 = display_dy_0_;
    dy_0_ = abs(_e68);
    int _e70 = subpixel_order_1_;
    if ((_e70 <= 2)) {
        vec2 _e72 = dx_0_;
        vec2 _e74 = dy_0_;
        _S1_ = ((_e72 * 0.33333334) + _e74);
    } else {
        vec2 _e76 = dx_0_;
        vec2 _e77 = dy_0_;
        _S1_ = (_e76 + (_e77 * 0.33333334));
    }
    vec2 _e80 = _S1_;
    return _e80;
}

vec4 evalGlyphCoverageSubpixel_0_u0028_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b_i1_u003b_f1_u003b_tA21_u003b_utA21_u003b(inout vec2 rc_4_, inout ivec2 glyph_loc_2_, inout ivec2 band_max_2_, inout vec4 banding_2_, inout int layer_2_, inout int subpixel_order_2_, inout float coverage_exponent_3_, sampler2DArray curve_tex_4_, usampler2DArray band_tex_2_) {
    vec2 display_dx_1_ = vec2(0.0);
    vec2 display_dy_1_ = vec2(0.0);
    vec2 _S61_ = vec2(0.0);
    vec2 sample_step_0_ = vec2(0.0);
    vec2 display_epp_1_ = vec2(0.0);
    vec2 param_88 = vec2(0.0);
    vec2 param_89 = vec2(0.0);
    int param_90 = 0;
    vec2 _S62_ = vec2(0.0);
    vec2 _S63_ = vec2(0.0);
    float s_m3_1_ = 0.0;
    vec2 param_91 = vec2(0.0);
    vec2 param_92 = vec2(0.0);
    ivec2 param_93 = ivec2(0);
    ivec2 param_94 = ivec2(0);
    vec4 param_95 = vec4(0.0);
    int param_96 = 0;
    float s_m2_1_ = 0.0;
    vec2 param_97 = vec2(0.0);
    vec2 param_98 = vec2(0.0);
    ivec2 param_99 = ivec2(0);
    ivec2 param_100 = ivec2(0);
    vec4 param_101 = vec4(0.0);
    int param_102 = 0;
    float s_m1_1_ = 0.0;
    vec2 param_103 = vec2(0.0);
    vec2 param_104 = vec2(0.0);
    ivec2 param_105 = ivec2(0);
    ivec2 param_106 = ivec2(0);
    vec4 param_107 = vec4(0.0);
    int param_108 = 0;
    float s_0_1_ = 0.0;
    vec2 param_109 = vec2(0.0);
    vec2 param_110 = vec2(0.0);
    ivec2 param_111 = ivec2(0);
    ivec2 param_112 = ivec2(0);
    vec4 param_113 = vec4(0.0);
    int param_114 = 0;
    float s_p1_1_ = 0.0;
    vec2 param_115 = vec2(0.0);
    vec2 param_116 = vec2(0.0);
    ivec2 param_117 = ivec2(0);
    ivec2 param_118 = ivec2(0);
    vec4 param_119 = vec4(0.0);
    int param_120 = 0;
    float s_p2_1_ = 0.0;
    vec2 param_121 = vec2(0.0);
    vec2 param_122 = vec2(0.0);
    ivec2 param_123 = ivec2(0);
    ivec2 param_124 = ivec2(0);
    vec4 param_125 = vec4(0.0);
    int param_126 = 0;
    float s_p3_1_ = 0.0;
    vec2 param_127 = vec2(0.0);
    vec2 param_128 = vec2(0.0);
    ivec2 param_129 = ivec2(0);
    ivec2 param_130 = ivec2(0);
    vec4 param_131 = vec4(0.0);
    int param_132 = 0;
    bool _S64_ = false;
    vec4 coverage_0_ = vec4(0.0);
    float param_133 = 0.0;
    float param_134 = 0.0;
    float param_135 = 0.0;
    float param_136 = 0.0;
    float param_137 = 0.0;
    float param_138 = 0.0;
    float param_139 = 0.0;
    bool param_140 = false;
    vec3 param_141 = vec3(0.0);
    float param_142 = 0.0;
    float param_143 = 0.0;
    float param_144 = 0.0;
    vec2 _e142 = rc_4_;
    vec2 _e143 = dFdx(_e142);
    display_dx_1_ = _e143;
    vec2 _e144 = rc_4_;
    vec2 _e145 = dFdy(_e144);
    display_dy_1_ = _e145;
    int _e146 = subpixel_order_2_;
    if ((_e146 <= 2)) {
        vec2 _e148 = display_dx_1_;
        _S61_ = _e148;
    } else {
        vec2 _e149 = display_dy_1_;
        _S61_ = _e149;
    }
    vec2 _e150 = _S61_;
    sample_step_0_ = (_e150 * 0.33333334);
    vec2 _e152 = display_dx_1_;
    param_88 = _e152;
    vec2 _e153 = display_dy_1_;
    param_89 = _e153;
    int _e154 = subpixel_order_2_;
    param_90 = _e154;
    vec2 _e155 = subpixelCoverageEdgePixels_0_u0028_vf2_u003b_vf2_u003b_i1_u003b(param_88, param_89, param_90);
    display_epp_1_ = _e155;
    vec2 _e156 = sample_step_0_;
    _S62_ = (_e156 * 3.0);
    vec2 _e158 = sample_step_0_;
    _S63_ = (_e158 * 2.0);
    vec2 _e160 = rc_4_;
    vec2 _e161 = _S62_;
    param_91 = (_e160 - _e161);
    vec2 _e163 = display_epp_1_;
    param_92 = _e163;
    ivec2 _e164 = glyph_loc_2_;
    param_93 = _e164;
    ivec2 _e165 = band_max_2_;
    param_94 = _e165;
    vec4 _e166 = banding_2_;
    param_95 = _e166;
    int _e167 = layer_2_;
    param_96 = _e167;
    float _e168 = evalGlyphSample_0_u0028_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b_tA21_u003b_utA21_u003b(param_91, param_92, param_93, param_94, param_95, param_96, curve_tex_4_, band_tex_2_);
    s_m3_1_ = _e168;
    vec2 _e169 = rc_4_;
    vec2 _e170 = _S63_;
    param_97 = (_e169 - _e170);
    vec2 _e172 = display_epp_1_;
    param_98 = _e172;
    ivec2 _e173 = glyph_loc_2_;
    param_99 = _e173;
    ivec2 _e174 = band_max_2_;
    param_100 = _e174;
    vec4 _e175 = banding_2_;
    param_101 = _e175;
    int _e176 = layer_2_;
    param_102 = _e176;
    float _e177 = evalGlyphSample_0_u0028_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b_tA21_u003b_utA21_u003b(param_97, param_98, param_99, param_100, param_101, param_102, curve_tex_4_, band_tex_2_);
    s_m2_1_ = _e177;
    vec2 _e178 = rc_4_;
    vec2 _e179 = sample_step_0_;
    param_103 = (_e178 - _e179);
    vec2 _e181 = display_epp_1_;
    param_104 = _e181;
    ivec2 _e182 = glyph_loc_2_;
    param_105 = _e182;
    ivec2 _e183 = band_max_2_;
    param_106 = _e183;
    vec4 _e184 = banding_2_;
    param_107 = _e184;
    int _e185 = layer_2_;
    param_108 = _e185;
    float _e186 = evalGlyphSample_0_u0028_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b_tA21_u003b_utA21_u003b(param_103, param_104, param_105, param_106, param_107, param_108, curve_tex_4_, band_tex_2_);
    s_m1_1_ = _e186;
    vec2 _e187 = rc_4_;
    param_109 = _e187;
    vec2 _e188 = display_epp_1_;
    param_110 = _e188;
    ivec2 _e189 = glyph_loc_2_;
    param_111 = _e189;
    ivec2 _e190 = band_max_2_;
    param_112 = _e190;
    vec4 _e191 = banding_2_;
    param_113 = _e191;
    int _e192 = layer_2_;
    param_114 = _e192;
    float _e193 = evalGlyphSample_0_u0028_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b_tA21_u003b_utA21_u003b(param_109, param_110, param_111, param_112, param_113, param_114, curve_tex_4_, band_tex_2_);
    s_0_1_ = _e193;
    vec2 _e194 = rc_4_;
    vec2 _e195 = sample_step_0_;
    param_115 = (_e194 + _e195);
    vec2 _e197 = display_epp_1_;
    param_116 = _e197;
    ivec2 _e198 = glyph_loc_2_;
    param_117 = _e198;
    ivec2 _e199 = band_max_2_;
    param_118 = _e199;
    vec4 _e200 = banding_2_;
    param_119 = _e200;
    int _e201 = layer_2_;
    param_120 = _e201;
    float _e202 = evalGlyphSample_0_u0028_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b_tA21_u003b_utA21_u003b(param_115, param_116, param_117, param_118, param_119, param_120, curve_tex_4_, band_tex_2_);
    s_p1_1_ = _e202;
    vec2 _e203 = rc_4_;
    vec2 _e204 = _S63_;
    param_121 = (_e203 + _e204);
    vec2 _e206 = display_epp_1_;
    param_122 = _e206;
    ivec2 _e207 = glyph_loc_2_;
    param_123 = _e207;
    ivec2 _e208 = band_max_2_;
    param_124 = _e208;
    vec4 _e209 = banding_2_;
    param_125 = _e209;
    int _e210 = layer_2_;
    param_126 = _e210;
    float _e211 = evalGlyphSample_0_u0028_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b_tA21_u003b_utA21_u003b(param_121, param_122, param_123, param_124, param_125, param_126, curve_tex_4_, band_tex_2_);
    s_p2_1_ = _e211;
    vec2 _e212 = rc_4_;
    vec2 _e213 = _S62_;
    param_127 = (_e212 + _e213);
    vec2 _e215 = display_epp_1_;
    param_128 = _e215;
    ivec2 _e216 = glyph_loc_2_;
    param_129 = _e216;
    ivec2 _e217 = band_max_2_;
    param_130 = _e217;
    vec4 _e218 = banding_2_;
    param_131 = _e218;
    int _e219 = layer_2_;
    param_132 = _e219;
    float _e220 = evalGlyphSample_0_u0028_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b_tA21_u003b_utA21_u003b(param_127, param_128, param_129, param_130, param_131, param_132, curve_tex_4_, band_tex_2_);
    s_p3_1_ = _e220;
    int _e221 = subpixel_order_2_;
    if ((_e221 == 2)) {
        _S64_ = true;
    } else {
        int _e223 = subpixel_order_2_;
        _S64_ = (_e223 == 4);
    }
    float _e225 = s_m3_1_;
    param_133 = _e225;
    float _e226 = s_m2_1_;
    param_134 = _e226;
    float _e227 = s_m1_1_;
    param_135 = _e227;
    float _e228 = s_0_1_;
    param_136 = _e228;
    float _e229 = s_p1_1_;
    param_137 = _e229;
    float _e230 = s_p2_1_;
    param_138 = _e230;
    float _e231 = s_p3_1_;
    param_139 = _e231;
    bool _e232 = _S64_;
    param_140 = _e232;
    vec4 _e233 = filterSubpixelCoverage_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_b1_u003b(param_133, param_134, param_135, param_136, param_137, param_138, param_139, param_140);
    coverage_0_ = _e233;
    vec4 _e234 = coverage_0_;
    param_141 = _e234.xyz;
    float _e236 = coverage_exponent_3_;
    param_142 = _e236;
    vec3 _e237 = applyCoverageTransfer3_0_u0028_vf3_u003b_f1_u003b(param_141, param_142);
    float _e239 = coverage_0_[3u];
    param_143 = _e239;
    float _e240 = coverage_exponent_3_;
    param_144 = _e240;
    float _e241 = applyCoverageTransfer_0_u0028_f1_u003b_f1_u003b(param_143, param_144);
    return vec4(_e237.x, _e237.y, _e237.z, _e241);
}

SubpixelResult_0_ snailSubpixelFragment_0_u0028_struct_u002d_SubpixelVaryings_0_u002d_vf4_u002d_vf4_u002d_vf2_u002d_vf4_u002d_vi41_u003b_tA21_u003b_utA21_u003b_i1_u003b_i1_u003b_i1_u003b_f1_u003b(inout SubpixelVaryings_0_ v_1_, sampler2DArray curve_tex_5_, usampler2DArray band_tex_3_, inout int layer_base_1_, inout int subpixel_order_3_, inout int output_srgb_1_, inout float coverage_exponent_4_) {
    SubpixelResult_0_ r_2_ = SubpixelResult_0_(vec4(0.0), vec4(0.0), false);
    int _S68_ = 0;
    int layer_byte_0_ = 0;
    vec4 cov_alpha_0_ = vec4(0.0);
    vec2 param_145 = vec2(0.0);
    ivec2 param_146 = ivec2(0);
    ivec2 param_147 = ivec2(0);
    vec4 param_148 = vec4(0.0);
    int param_149 = 0;
    int param_150 = 0;
    float param_151 = 0.0;
    vec3 cov_5_ = vec3(0.0);
    vec4 color_3_ = vec4(0.0);
    vec4 effective_0_ = vec4(0.0);
    float param_152 = 0.0;
    float param_153 = 0.0;
    float param_154 = 0.0;
    vec4 param_155 = vec4(0.0);
    vec3 param_156 = vec3(0.0);
    float param_157 = 0.0;
    r_2_.color_1_ = vec4(0.0, 0.0, 0.0, 0.0);
    r_2_.blend_0_ = vec4(0.0, 0.0, 0.0, 0.0);
    r_2_.discard_fragment_0_ = false;
    int _e92 = v_1_.glyph_0_[3u];
    _S68_ = _e92;
    int _e93 = _S68_;
    layer_byte_0_ = ((_e93 >> uint(8)) & 255);
    int _e97 = layer_byte_0_;
    if ((_e97 == 255)) {
        r_2_.discard_fragment_0_ = true;
        SubpixelResult_0_ _e100 = r_2_;
        return _e100;
    }
    int _e101 = _S68_;
    int _e105 = v_1_.glyph_0_[2u];
    int _e107 = layer_base_1_;
    int _e108 = layer_byte_0_;
    vec2 _e111 = v_1_.texcoord_0_;
    param_145 = _e111;
    ivec4 _e113 = v_1_.glyph_0_;
    param_146 = _e113.xy;
    param_147 = ivec2((_e101 & 255), _e105);
    vec4 _e116 = v_1_.banding_3_;
    param_148 = _e116;
    param_149 = (_e107 + _e108);
    int _e117 = subpixel_order_3_;
    param_150 = _e117;
    float _e118 = coverage_exponent_4_;
    param_151 = _e118;
    vec4 _e119 = evalGlyphCoverageSubpixel_0_u0028_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b_i1_u003b_f1_u003b_tA21_u003b_utA21_u003b(param_145, param_146, param_147, param_148, param_149, param_150, param_151, curve_tex_5_, band_tex_3_);
    cov_alpha_0_ = _e119;
    vec4 _e120 = cov_alpha_0_;
    cov_5_ = _e120.xyz;
    float _e123 = cov_5_[0u];
    float _e125 = cov_5_[1u];
    float _e128 = cov_5_[2u];
    if ((max(max(_e123, _e125), _e128) < 0.003921569)) {
        r_2_.discard_fragment_0_ = true;
        SubpixelResult_0_ _e132 = r_2_;
        return _e132;
    }
    vec4 _e134 = v_1_.color_2_;
    vec4 _e136 = v_1_.tint_0_;
    color_3_ = (_e134 * _e136);
    int _e138 = output_srgb_1_;
    if ((_e138 != 0)) {
        float _e141 = color_3_[0u];
        param_152 = max(_e141, 0.0);
        float _e143 = srgbEncode_0_u0028_f1_u003b(param_152);
        float _e145 = color_3_[1u];
        param_153 = max(_e145, 0.0);
        float _e147 = srgbEncode_0_u0028_f1_u003b(param_153);
        float _e149 = color_3_[2u];
        param_154 = max(_e149, 0.0);
        float _e151 = srgbEncode_0_u0028_f1_u003b(param_154);
        float _e153 = color_3_[3u];
        effective_0_ = vec4(_e143, _e147, _e151, _e153);
    } else {
        vec4 _e155 = color_3_;
        effective_0_ = _e155;
    }
    vec4 _e156 = effective_0_;
    param_155 = _e156;
    vec3 _e157 = cov_5_;
    param_156 = _e157;
    float _e159 = cov_alpha_0_[3u];
    param_157 = _e159;
    vec4 _e160 = premultiplyColorSubpixel_0_u0028_vf4_u003b_vf3_u003b_f1_u003b(param_155, param_156, param_157);
    r_2_.color_1_ = _e160;
    float _e163 = color_3_[3u];
    vec3 _e165 = cov_5_;
    vec3 _e166 = (vec3(_e163) * _e165);
    r_2_.blend_0_ = vec4(_e166.x, _e166.y, _e166.z, 0.0);
    SubpixelResult_0_ _e172 = r_2_;
    return _e172;
}

void main_1() {
    SubpixelVaryings_0_ v_2_ = SubpixelVaryings_0_(vec4(0.0), vec4(0.0), vec2(0.0), vec4(0.0), ivec4(0));
    SubpixelResult_0_ r_3_ = SubpixelResult_0_(vec4(0.0), vec4(0.0), false);
    SubpixelVaryings_0_ param_158 = SubpixelVaryings_0_(vec4(0.0), vec4(0.0), vec2(0.0), vec4(0.0), ivec4(0));
    int param_159 = 0;
    int param_160 = 0;
    int param_161 = 0;
    float param_162 = 0.0;
    FsOutput_0_ o_0_ = FsOutput_0_(vec4(0.0), vec4(0.0));
    FsOutput_0_ _S69_ = FsOutput_0_(vec4(0.0), vec4(0.0));
    vec4 _e69 = input_color_0_1;
    v_2_.color_2_ = _e69;
    vec4 _e71 = input_tint_0_1;
    v_2_.tint_0_ = _e71;
    vec2 _e73 = input_texcoord_0_1;
    v_2_.texcoord_0_ = _e73;
    vec4 _e75 = input_banding_0_1;
    v_2_.banding_3_ = _e75;
    ivec4 _e77 = input_glyph_0_1;
    v_2_.glyph_0_ = _e77;
    SubpixelVaryings_0_ _e79 = v_2_;
    param_158 = _e79;
    int _e81 = _group_0_binding_0_fs.layer_base_0_;
    param_159 = _e81;
    int _e83 = _group_0_binding_0_fs.subpixel_order_0_;
    param_160 = _e83;
    int _e85 = _group_0_binding_0_fs.output_srgb_0_;
    param_161 = _e85;
    float _e87 = _group_0_binding_0_fs.coverage_exponent_0_;
    param_162 = _e87;
    SubpixelResult_0_ _e88 = snailSubpixelFragment_0_u0028_struct_u002d_SubpixelVaryings_0_u002d_vf4_u002d_vf4_u002d_vf2_u002d_vf4_u002d_vi41_u003b_tA21_u003b_utA21_u003b_i1_u003b_i1_u003b_i1_u003b_f1_u003b(param_158, _group_0_binding_1_fs, _group_0_binding_2_fs, param_159, param_160, param_161, param_162);
    r_3_ = _e88;
    bool _e90 = r_3_.discard_fragment_0_;
    if (_e90) {
        discard;
    }
    vec4 _e92 = r_3_.color_1_;
    o_0_.color_4_ = _e92;
    vec4 _e95 = r_3_.blend_0_;
    o_0_.blend_1_ = _e95;
    FsOutput_0_ _e97 = o_0_;
    _S69_ = _e97;
    vec4 _e99 = o_0_.color_4_;
    entryPointParam_fragmentMain_color_0_ = _e99;
    vec4 _e101 = _S69_.blend_1_;
    entryPointParam_fragmentMain_blend_0_ = _e101;
    return;
}

void main() {
    vec4 input_color_0_ = _vs2fs_location0;
    vec4 input_tint_0_ = _vs2fs_location4;
    vec2 input_texcoord_0_ = _vs2fs_location1;
    vec4 input_banding_0_ = _vs2fs_location2;
    ivec4 input_glyph_0_ = _vs2fs_location3;
    input_color_0_1 = input_color_0_;
    input_tint_0_1 = input_tint_0_;
    input_texcoord_0_1 = input_texcoord_0_;
    input_banding_0_1 = input_banding_0_;
    input_glyph_0_1 = input_glyph_0_;
    main_1();
    vec4 _e12 = entryPointParam_fragmentMain_color_0_;
    vec4 _e13 = entryPointParam_fragmentMain_blend_0_;
    FragmentOutput _tmp_return = FragmentOutput(_e12, _e13);
    _fs2p_location0 = _tmp_return.member;
    _fs2p_location1 = _tmp_return.member_1;
    return;
}

