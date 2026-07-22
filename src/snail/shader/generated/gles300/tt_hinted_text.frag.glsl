#version 300 es

precision highp float;
precision highp int;

struct CoverageBandSpan_0_ {
    int first_0_;
    int last_0_;
};
struct TtHintedVaryings_0_ {
    vec4 color_2_;
    vec4 tint_0_;
    vec2 texcoord_0_;
    vec4 banding_1_;
    ivec4 glyph_0_;
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
vec4 input_color_0_1 = vec4(0.0);

vec4 input_tint_0_1 = vec4(0.0);

vec2 input_texcoord_0_1 = vec2(0.0);

vec4 input_banding_0_1 = vec4(0.0);

ivec4 input_glyph_0_1 = ivec4(0);

uniform highp sampler2DArray _group_0_binding_1_fs;

uniform highp usampler2DArray _group_0_binding_2_fs;

uniform highp sampler2D _group_0_binding_3_fs;

layout(std140) uniform block_SnailPushConstants_0_block_0Fragment { block_SnailPushConstants_0_ _group_0_binding_0_fs; };

vec4 entryPointParam_fragmentMain_0_ = vec4(0.0);

smooth in vec4 _vs2fs_location0;
smooth in vec4 _vs2fs_location4;
smooth in vec2 _vs2fs_location1;
flat in vec4 _vs2fs_location2;
flat in ivec4 _vs2fs_location3;
layout(location = 0) out vec4 _fs2p_location0;

float srgbEncode_0_u0028_f1_u003b(inout float c_0_) {
    float _S61_ = 0.0;
    float _e58 = c_0_;
    if ((_e58 <= 0.0031308)) {
        float _e60 = c_0_;
        _S61_ = (_e60 * 12.92);
    } else {
        float _e62 = c_0_;
        _S61_ = ((1.055 * pow(_e62, 0.41666666)) - 0.055);
    }
    float _e66 = _S61_;
    return _e66;
}

vec3 linearToSrgb_0_u0028_vf3_u003b(inout vec3 color_1_) {
    float param = 0.0;
    float param_1 = 0.0;
    float param_2 = 0.0;
    float _e61 = color_1_[0u];
    param = max(_e61, 0.0);
    float _e63 = srgbEncode_0_u0028_f1_u003b(param);
    float _e65 = color_1_[1u];
    param_1 = max(_e65, 0.0);
    float _e67 = srgbEncode_0_u0028_f1_u003b(param_1);
    float _e69 = color_1_[2u];
    param_2 = max(_e69, 0.0);
    float _e71 = srgbEncode_0_u0028_f1_u003b(param_2);
    return vec3(_e63, _e67, _e71);
}

vec4 srgbEncodePremultiplied_0_u0028_vf4_u003b(inout vec4 premul_0_) {
    float _S62_ = 0.0;
    vec3 param_3 = vec3(0.0);
    float _e60 = premul_0_[3u];
    _S62_ = _e60;
    float _e61 = _S62_;
    if ((_e61 <= 0.0)) {
        return vec4(0.0, 0.0, 0.0, 0.0);
    }
    vec4 _e63 = premul_0_;
    float _e65 = _S62_;
    param_3 = (_e63.xyz * (1.0 / _e65));
    vec3 _e68 = linearToSrgb_0_u0028_vf3_u003b(param_3);
    float _e69 = _S62_;
    vec3 _e70 = (_e68 * _e69);
    float _e71 = _S62_;
    return vec4(_e70.x, _e70.y, _e70.z, _e71);
}

vec4 premultiplyColor_0_u0028_vf4_u003b_f1_u003b(inout vec4 color_0_, inout float cov_1_) {
    float alpha_0_ = 0.0;
    float _e60 = color_0_[3u];
    float _e61 = cov_1_;
    alpha_0_ = (_e60 * _e61);
    vec4 _e63 = color_0_;
    float _e65 = alpha_0_;
    vec3 _e66 = (_e63.xyz * _e65);
    float _e67 = alpha_0_;
    return vec4(_e66.x, _e66.y, _e66.z, _e67);
}

float applyCoverageTransfer_0_u0028_f1_u003b_f1_u003b(inout float cov_0_, inout float coverage_exponent_1_) {
    float clamped_0_ = 0.0;
    float _S45_ = 0.0;
    float _S46_ = 0.0;
    float _e61 = cov_0_;
    clamped_0_ = clamp(_e61, 0.0, 1.0);
    float _e63 = coverage_exponent_1_;
    _S45_ = max(_e63, 1.5258789e-5);
    float _e65 = _S45_;
    if ((abs((_e65 - 1.0)) <= 1e-6)) {
        float _e69 = clamped_0_;
        _S46_ = _e69;
    } else {
        float _e70 = clamped_0_;
        float _e71 = _S45_;
        _S46_ = pow(_e70, _e71);
    }
    float _e73 = _S46_;
    return _e73;
}

float applyFillRule_0_u0028_f1_u003b_i1_u003b(inout float winding_0_, inout int fill_rule_mode_0_) {
    int _e58 = fill_rule_mode_0_;
    if ((_e58 == 1)) {
        float _e60 = winding_0_;
        return (1.0 - abs(((fract((_e60 * 0.5)) * 2.0) - 1.0)));
    }
    float _e67 = winding_0_;
    return abs(_e67);
}

float snapNearTangentSqrt_0_u0028_f1_u003b_f1_u003b_f1_u003b(inout float disc_0_, inout float b_0_, inout float ac_0_) {
    float _S8_ = 0.0;
    float _e60 = disc_0_;
    float _e61 = b_0_;
    float _e62 = b_0_;
    float _e64 = ac_0_;
    if ((_e60 <= (max((_e61 * _e62), abs(_e64)) * 3e-6))) {
        _S8_ = 0.0;
    } else {
        float _e69 = disc_0_;
        _S8_ = sqrt(_e69);
    }
    float _e71 = _S8_;
    return _e71;
}

vec2 solveVertPoly_0_u0028_vf4_u003b_vf2_u003b(inout vec4 p12_2_, inout vec2 p3_2_) {
    vec2 _S27_ = vec2(0.0);
    vec2 _S28_ = vec2(0.0);
    vec2 a_1_ = vec2(0.0);
    vec2 b_2_ = vec2(0.0);
    float _S29_ = 0.0;
    float _S30_ = 0.0;
    float t1_1_ = 0.0;
    float t2_1_ = 0.0;
    float _S31_ = 0.0;
    float _S32_ = 0.0;
    float _S33_ = 0.0;
    float sq_1_ = 0.0;
    float param_4 = 0.0;
    float param_5 = 0.0;
    float param_6 = 0.0;
    float q_2_ = 0.0;
    float _S34_ = 0.0;
    float q_3_ = 0.0;
    float _S35_ = 0.0;
    float _S36_ = 0.0;
    float _S37_ = 0.0;
    float _S38_ = 0.0;
    float _S39_ = 0.0;
    vec4 _e81 = p12_2_;
    _S27_ = _e81.xy;
    vec4 _e83 = p12_2_;
    _S28_ = _e83.zw;
    vec2 _e85 = _S27_;
    vec2 _e86 = _S28_;
    vec2 _e89 = p3_2_;
    a_1_ = ((_e85 - (_e86 * 2.0)) + _e89);
    vec2 _e91 = _S27_;
    vec2 _e92 = _S28_;
    b_2_ = (_e91 - _e92);
    float _e95 = a_1_[0u];
    _S29_ = _e95;
    float _e96 = _S29_;
    if ((abs(_e96) < 1.5258789e-5)) {
        float _e100 = b_2_[0u];
        _S30_ = _e100;
        float _e101 = _S30_;
        if ((abs(_e101) < 1.5258789e-5)) {
            t1_1_ = 0.0;
        } else {
            float _e105 = p12_2_[0u];
            float _e107 = _S30_;
            t1_1_ = ((_e105 * 0.5) / _e107);
        }
        float _e109 = t1_1_;
        t2_1_ = _e109;
    } else {
        float _e111 = b_2_[0u];
        _S31_ = _e111;
        float _e113 = p12_2_[0u];
        _S32_ = _e113;
        float _e114 = _S29_;
        float _e115 = _S32_;
        _S33_ = (_e114 * _e115);
        float _e117 = _S31_;
        float _e118 = _S31_;
        float _e120 = _S33_;
        param_4 = ((_e117 * _e118) - _e120);
        float _e122 = _S31_;
        param_5 = _e122;
        float _e123 = _S33_;
        param_6 = _e123;
        float _e124 = snapNearTangentSqrt_0_u0028_f1_u003b_f1_u003b_f1_u003b(param_4, param_5, param_6);
        sq_1_ = _e124;
        float _e125 = _S31_;
        if ((_e125 >= 0.0)) {
            float _e127 = _S31_;
            float _e128 = sq_1_;
            q_2_ = (_e127 + _e128);
            float _e130 = q_2_;
            float _e131 = _S29_;
            _S34_ = (_e130 / _e131);
            float _e133 = q_2_;
            if ((abs(_e133) < 1.5258789e-5)) {
                t1_1_ = 0.0;
            } else {
                float _e136 = _S32_;
                float _e137 = q_2_;
                t1_1_ = (_e136 / _e137);
            }
            float _e139 = _S34_;
            t2_1_ = _e139;
        } else {
            float _e140 = _S31_;
            float _e141 = sq_1_;
            q_3_ = (_e140 - _e141);
            float _e143 = q_3_;
            float _e144 = _S29_;
            _S35_ = (_e143 / _e144);
            float _e146 = q_3_;
            if ((abs(_e146) < 1.5258789e-5)) {
                t1_1_ = 0.0;
            } else {
                float _e149 = _S32_;
                float _e150 = q_3_;
                t1_1_ = (_e149 / _e150);
            }
            float _e152 = t1_1_;
            _S36_ = _e152;
            float _e153 = _S35_;
            t1_1_ = _e153;
            float _e154 = _S36_;
            t2_1_ = _e154;
        }
    }
    float _e156 = a_1_[1u];
    _S37_ = _e156;
    float _e158 = b_2_[1u];
    _S38_ = (_e158 * 2.0);
    float _e161 = p12_2_[1u];
    _S39_ = _e161;
    float _e162 = _S37_;
    float _e163 = t1_1_;
    float _e165 = _S38_;
    float _e167 = t1_1_;
    float _e169 = _S39_;
    float _e171 = _S37_;
    float _e172 = t2_1_;
    float _e174 = _S38_;
    float _e176 = t2_1_;
    float _e178 = _S39_;
    return vec2(((((_e162 * _e163) - _e165) * _e167) + _e169), ((((_e171 * _e172) - _e174) * _e176) + _e178));
}

float rootCodeCoord_0_u0028_f1_u003b(inout float v_0_) {
    float _S7_ = 0.0;
    float _e58 = v_0_;
    if ((abs(_e58) <= 1.5258789e-5)) {
        _S7_ = 0.0;
    } else {
        float _e61 = v_0_;
        _S7_ = _e61;
    }
    float _e62 = _S7_;
    return _e62;
}

uint calcRootCode_0_u0028_f1_u003b_f1_u003b_f1_u003b(inout float y1_0_, inout float y2_0_, inout float y3_0_) {
    float param_7 = 0.0;
    float param_8 = 0.0;
    float param_9 = 0.0;
    float _e62 = y3_0_;
    param_7 = _e62;
    float _e63 = rootCodeCoord_0_u0028_f1_u003b(param_7);
    float _e68 = y2_0_;
    param_8 = _e68;
    float _e69 = rootCodeCoord_0_u0028_f1_u003b(param_8);
    float _e74 = y1_0_;
    param_9 = _e74;
    float _e75 = rootCodeCoord_0_u0028_f1_u003b(param_9);
    return ((11892u >> (((floatBitsToUint(_e63) >> 29u) & 4u) | ((((floatBitsToUint(_e69) >> 30u) & 2u) | ((floatBitsToUint(_e75) >> 31u) & 4294967293u)) & 4294967291u))) & 257u);
}

ivec2 offsetCurveLoc_0_u0028_vi2_u003b_i1_u003b(inout ivec2 base_1_, inout int offset_2_) {
    int _S6_ = 0;
    ivec2 loc_1_ = ivec2(0);
    int _e61 = base_1_[0u];
    int _e62 = offset_2_;
    _S6_ = (_e61 + _e62);
    int _e64 = _S6_;
    int _e66 = base_1_[1u];
    loc_1_ = ivec2(_e64, _e66);
    int _e69 = loc_1_[1u];
    int _e70 = _S6_;
    loc_1_[1u] = (_e69 + (_e70 >> uint(12)));
    int _e76 = loc_1_[0u];
    loc_1_[0u] = (_e76 & 4095);
    ivec2 _e79 = loc_1_;
    return _e79;
}

bool accumulateVertContribution_0_u0028_f1_u003b_f1_u003b_vf2_u003b_vf2_u003b_vi2_u003b_i1_u003b_tA21_u003b(inout float ycov_0_, inout float ywgt_0_, inout vec2 rc_1_, inout vec2 ppe_1_, inout ivec2 cLoc_1_, inout int texLayer_1_, highp sampler2DArray curve_tex_1_) {
    ivec4 _S40_ = ivec4(0);
    vec4 tex0_1_ = vec4(0.0);
    ivec4 _S41_ = ivec4(0);
    ivec2 param_10 = ivec2(0);
    int param_11 = 0;
    vec4 p12_3_ = vec4(0.0);
    vec2 p3_3_ = vec2(0.0);
    float _S42_ = 0.0;
    uint code_1_ = 0u;
    float param_12 = 0.0;
    float param_13 = 0.0;
    float param_14 = 0.0;
    vec2 r_1_ = vec2(0.0);
    vec4 param_15 = vec4(0.0);
    vec2 param_16 = vec2(0.0);
    float _S43_ = 0.0;
    float _S44_ = 0.0;
    ivec2 _e80 = cLoc_1_;
    int _e81 = texLayer_1_;
    _S40_ = ivec4(_e80.x, _e80.y, _e81, 0);
    ivec4 _e85 = _S40_;
    ivec3 _e86 = _e85.xyz;
    int _e88 = _S40_[3u];
    vec4 _e94 = texelFetch(curve_tex_1_, ivec3(ivec2(_e86.x, _e86.y), int(_e86.z)), _e88);
    tex0_1_ = _e94;
    ivec2 _e95 = cLoc_1_;
    param_10 = _e95;
    param_11 = 1;
    ivec2 _e96 = offsetCurveLoc_0_u0028_vi2_u003b_i1_u003b(param_10, param_11);
    int _e97 = texLayer_1_;
    _S41_ = ivec4(_e96.x, _e96.y, _e97, 0);
    vec4 _e101 = tex0_1_;
    vec2 _e102 = _e101.xy;
    vec4 _e103 = tex0_1_;
    vec2 _e104 = _e103.zw;
    vec2 _e110 = rc_1_;
    p12_3_ = (vec4(_e102.x, _e102.y, _e104.x, _e104.y) - vec4(_e110.x, _e110.y, _e110.x, _e110.y));
    ivec4 _e117 = _S41_;
    ivec3 _e118 = _e117.xyz;
    int _e120 = _S41_[3u];
    vec4 _e126 = texelFetch(curve_tex_1_, ivec3(ivec2(_e118.x, _e118.y), int(_e118.z)), _e120);
    vec2 _e128 = rc_1_;
    p3_3_ = (_e126.xy - _e128);
    float _e131 = ppe_1_[1u];
    _S42_ = _e131;
    float _e133 = p12_3_[1u];
    float _e135 = p12_3_[3u];
    float _e138 = p3_3_[1u];
    float _e140 = _S42_;
    if (((max(max(_e133, _e135), _e138) * _e140) < -0.5)) {
        return false;
    }
    float _e144 = p12_3_[0u];
    param_12 = _e144;
    float _e146 = p12_3_[2u];
    param_13 = _e146;
    float _e148 = p3_3_[0u];
    param_14 = _e148;
    uint _e149 = calcRootCode_0_u0028_f1_u003b_f1_u003b_f1_u003b(param_12, param_13, param_14);
    code_1_ = _e149;
    uint _e150 = code_1_;
    if ((_e150 != 0u)) {
        vec4 _e152 = p12_3_;
        param_15 = _e152;
        vec2 _e153 = p3_3_;
        param_16 = _e153;
        vec2 _e154 = solveVertPoly_0_u0028_vf4_u003b_vf2_u003b(param_15, param_16);
        float _e155 = _S42_;
        r_1_ = (_e154 * _e155);
        uint _e157 = code_1_;
        if (((_e157 & 1u) != 0u)) {
            float _e161 = r_1_[0u];
            _S43_ = _e161;
            float _e162 = ycov_0_;
            float _e163 = _S43_;
            ycov_0_ = (_e162 - clamp((_e163 + 0.5), 0.0, 1.0));
            float _e167 = ywgt_0_;
            float _e168 = _S43_;
            ywgt_0_ = max(_e167, clamp((1.0 - (abs(_e168) * 2.0)), 0.0, 1.0));
        }
        uint _e174 = code_1_;
        if ((_e174 > 1u)) {
            float _e177 = r_1_[1u];
            _S44_ = _e177;
            float _e178 = ycov_0_;
            float _e179 = _S44_;
            ycov_0_ = (_e178 + clamp((_e179 + 0.5), 0.0, 1.0));
            float _e183 = ywgt_0_;
            float _e184 = _S44_;
            ywgt_0_ = max(_e183, clamp((1.0 - (abs(_e184) * 2.0)), 0.0, 1.0));
        }
    }
    return true;
}

vec2 solveHorizPoly_0_u0028_vf4_u003b_vf2_u003b(inout vec4 p12_0_, inout vec2 p3_0_) {
    vec2 _S9_ = vec2(0.0);
    vec2 _S10_ = vec2(0.0);
    vec2 a_0_ = vec2(0.0);
    vec2 b_1_ = vec2(0.0);
    float _S11_ = 0.0;
    float _S12_ = 0.0;
    float t1_0_ = 0.0;
    float t2_0_ = 0.0;
    float _S13_ = 0.0;
    float _S14_ = 0.0;
    float _S15_ = 0.0;
    float sq_0_ = 0.0;
    float param_17 = 0.0;
    float param_18 = 0.0;
    float param_19 = 0.0;
    float q_0_ = 0.0;
    float _S16_ = 0.0;
    float q_1_ = 0.0;
    float _S17_ = 0.0;
    float _S18_ = 0.0;
    float _S19_ = 0.0;
    float _S20_ = 0.0;
    float _S21_ = 0.0;
    vec4 _e81 = p12_0_;
    _S9_ = _e81.xy;
    vec4 _e83 = p12_0_;
    _S10_ = _e83.zw;
    vec2 _e85 = _S9_;
    vec2 _e86 = _S10_;
    vec2 _e89 = p3_0_;
    a_0_ = ((_e85 - (_e86 * 2.0)) + _e89);
    vec2 _e91 = _S9_;
    vec2 _e92 = _S10_;
    b_1_ = (_e91 - _e92);
    float _e95 = a_0_[1u];
    _S11_ = _e95;
    float _e96 = _S11_;
    if ((abs(_e96) < 1.5258789e-5)) {
        float _e100 = b_1_[1u];
        _S12_ = _e100;
        float _e101 = _S12_;
        if ((abs(_e101) < 1.5258789e-5)) {
            t1_0_ = 0.0;
        } else {
            float _e105 = p12_0_[1u];
            float _e107 = _S12_;
            t1_0_ = ((_e105 * 0.5) / _e107);
        }
        float _e109 = t1_0_;
        t2_0_ = _e109;
    } else {
        float _e111 = b_1_[1u];
        _S13_ = _e111;
        float _e113 = p12_0_[1u];
        _S14_ = _e113;
        float _e114 = _S11_;
        float _e115 = _S14_;
        _S15_ = (_e114 * _e115);
        float _e117 = _S13_;
        float _e118 = _S13_;
        float _e120 = _S15_;
        param_17 = ((_e117 * _e118) - _e120);
        float _e122 = _S13_;
        param_18 = _e122;
        float _e123 = _S15_;
        param_19 = _e123;
        float _e124 = snapNearTangentSqrt_0_u0028_f1_u003b_f1_u003b_f1_u003b(param_17, param_18, param_19);
        sq_0_ = _e124;
        float _e125 = _S13_;
        if ((_e125 >= 0.0)) {
            float _e127 = _S13_;
            float _e128 = sq_0_;
            q_0_ = (_e127 + _e128);
            float _e130 = q_0_;
            float _e131 = _S11_;
            _S16_ = (_e130 / _e131);
            float _e133 = q_0_;
            if ((abs(_e133) < 1.5258789e-5)) {
                t1_0_ = 0.0;
            } else {
                float _e136 = _S14_;
                float _e137 = q_0_;
                t1_0_ = (_e136 / _e137);
            }
            float _e139 = _S16_;
            t2_0_ = _e139;
        } else {
            float _e140 = _S13_;
            float _e141 = sq_0_;
            q_1_ = (_e140 - _e141);
            float _e143 = q_1_;
            float _e144 = _S11_;
            _S17_ = (_e143 / _e144);
            float _e146 = q_1_;
            if ((abs(_e146) < 1.5258789e-5)) {
                t1_0_ = 0.0;
            } else {
                float _e149 = _S14_;
                float _e150 = q_1_;
                t1_0_ = (_e149 / _e150);
            }
            float _e152 = t1_0_;
            _S18_ = _e152;
            float _e153 = _S17_;
            t1_0_ = _e153;
            float _e154 = _S18_;
            t2_0_ = _e154;
        }
    }
    float _e156 = a_0_[0u];
    _S19_ = _e156;
    float _e158 = b_1_[0u];
    _S20_ = (_e158 * 2.0);
    float _e161 = p12_0_[0u];
    _S21_ = _e161;
    float _e162 = _S19_;
    float _e163 = t1_0_;
    float _e165 = _S20_;
    float _e167 = t1_0_;
    float _e169 = _S21_;
    float _e171 = _S19_;
    float _e172 = t2_0_;
    float _e174 = _S20_;
    float _e176 = t2_0_;
    float _e178 = _S21_;
    return vec2(((((_e162 * _e163) - _e165) * _e167) + _e169), ((((_e171 * _e172) - _e174) * _e176) + _e178));
}

bool accumulateHorizContribution_0_u0028_f1_u003b_f1_u003b_vf2_u003b_vf2_u003b_vi2_u003b_i1_u003b_tA21_u003b(inout float xcov_0_, inout float xwgt_0_, inout vec2 rc_0_, inout vec2 ppe_0_, inout ivec2 cLoc_0_, inout int texLayer_0_, highp sampler2DArray curve_tex_0_) {
    ivec4 _S22_ = ivec4(0);
    vec4 tex0_0_ = vec4(0.0);
    ivec4 _S23_ = ivec4(0);
    ivec2 param_20 = ivec2(0);
    int param_21 = 0;
    vec4 p12_1_ = vec4(0.0);
    vec2 p3_1_ = vec2(0.0);
    float _S24_ = 0.0;
    uint code_0_ = 0u;
    float param_22 = 0.0;
    float param_23 = 0.0;
    float param_24 = 0.0;
    vec2 r_0_ = vec2(0.0);
    vec4 param_25 = vec4(0.0);
    vec2 param_26 = vec2(0.0);
    float _S25_ = 0.0;
    float _S26_ = 0.0;
    ivec2 _e80 = cLoc_0_;
    int _e81 = texLayer_0_;
    _S22_ = ivec4(_e80.x, _e80.y, _e81, 0);
    ivec4 _e85 = _S22_;
    ivec3 _e86 = _e85.xyz;
    int _e88 = _S22_[3u];
    vec4 _e94 = texelFetch(curve_tex_0_, ivec3(ivec2(_e86.x, _e86.y), int(_e86.z)), _e88);
    tex0_0_ = _e94;
    ivec2 _e95 = cLoc_0_;
    param_20 = _e95;
    param_21 = 1;
    ivec2 _e96 = offsetCurveLoc_0_u0028_vi2_u003b_i1_u003b(param_20, param_21);
    int _e97 = texLayer_0_;
    _S23_ = ivec4(_e96.x, _e96.y, _e97, 0);
    vec4 _e101 = tex0_0_;
    vec2 _e102 = _e101.xy;
    vec4 _e103 = tex0_0_;
    vec2 _e104 = _e103.zw;
    vec2 _e110 = rc_0_;
    p12_1_ = (vec4(_e102.x, _e102.y, _e104.x, _e104.y) - vec4(_e110.x, _e110.y, _e110.x, _e110.y));
    ivec4 _e117 = _S23_;
    ivec3 _e118 = _e117.xyz;
    int _e120 = _S23_[3u];
    vec4 _e126 = texelFetch(curve_tex_0_, ivec3(ivec2(_e118.x, _e118.y), int(_e118.z)), _e120);
    vec2 _e128 = rc_0_;
    p3_1_ = (_e126.xy - _e128);
    float _e131 = ppe_0_[0u];
    _S24_ = _e131;
    float _e133 = p12_1_[0u];
    float _e135 = p12_1_[2u];
    float _e138 = p3_1_[0u];
    float _e140 = _S24_;
    if (((max(max(_e133, _e135), _e138) * _e140) < -0.5)) {
        return false;
    }
    float _e144 = p12_1_[1u];
    param_22 = _e144;
    float _e146 = p12_1_[3u];
    param_23 = _e146;
    float _e148 = p3_1_[1u];
    param_24 = _e148;
    uint _e149 = calcRootCode_0_u0028_f1_u003b_f1_u003b_f1_u003b(param_22, param_23, param_24);
    code_0_ = _e149;
    uint _e150 = code_0_;
    if ((_e150 != 0u)) {
        vec4 _e152 = p12_1_;
        param_25 = _e152;
        vec2 _e153 = p3_1_;
        param_26 = _e153;
        vec2 _e154 = solveHorizPoly_0_u0028_vf4_u003b_vf2_u003b(param_25, param_26);
        float _e155 = _S24_;
        r_0_ = (_e154 * _e155);
        uint _e157 = code_0_;
        if (((_e157 & 1u) != 0u)) {
            float _e161 = r_0_[0u];
            _S25_ = _e161;
            float _e162 = xcov_0_;
            float _e163 = _S25_;
            xcov_0_ = (_e162 + clamp((_e163 + 0.5), 0.0, 1.0));
            float _e167 = xwgt_0_;
            float _e168 = _S25_;
            xwgt_0_ = max(_e167, clamp((1.0 - (abs(_e168) * 2.0)), 0.0, 1.0));
        }
        uint _e174 = code_0_;
        if ((_e174 > 1u)) {
            float _e177 = r_0_[1u];
            _S26_ = _e177;
            float _e178 = xcov_0_;
            float _e179 = _S26_;
            xcov_0_ = (_e178 - clamp((_e179 + 0.5), 0.0, 1.0));
            float _e183 = xwgt_0_;
            float _e184 = _S26_;
            xwgt_0_ = max(_e183, clamp((1.0 - (abs(_e184) * 2.0)), 0.0, 1.0));
        }
    }
    return true;
}

ivec2 decodeBandCurveLocCommon_0_u0028_vu2_u003b(inout uvec2 ref_2_) {
    uint _e58 = ref_2_[0u];
    uint _e62 = ref_2_[1u];
    return ivec2(int((_e58 & 4095u)), int((_e62 & 16383u)));
}

ivec2 decodeBandCurveLoc_0_u0028_vu2_u003b(inout uvec2 ref_3_) {
    uvec2 param_27 = uvec2(0u);
    uvec2 _e58 = ref_3_;
    param_27 = _e58;
    ivec2 _e59 = decodeBandCurveLocCommon_0_u0028_vu2_u003b(param_27);
    return _e59;
}

int decodeBandCurveFirstMemberCommon_0_u0028_vu2_u003b(inout uvec2 ref_0_) {
    uint _e58 = ref_0_[0u];
    return int((_e58 >> 12u));
}

bool isCoverageBandSpanOwner_0_u0028_vu2_u003b_i1_u003b_i1_u003b(inout uvec2 ref_1_, inout int band_0_, inout int spanFirst_0_) {
    uvec2 param_28 = uvec2(0u);
    int _e60 = band_0_;
    uvec2 _e61 = ref_1_;
    param_28 = _e61;
    int _e62 = decodeBandCurveFirstMemberCommon_0_u0028_vu2_u003b(param_28);
    int _e63 = spanFirst_0_;
    return (_e60 == max(_e62, _e63));
}

ivec2 calcBandLoc_0_u0028_vi2_u003b_u1_u003b(inout ivec2 glyphLoc_0_, inout uint offset_1_) {
    int _S5_ = 0;
    ivec2 loc_0_ = ivec2(0);
    int _e61 = glyphLoc_0_[0u];
    uint _e62 = offset_1_;
    _S5_ = (_e61 + int(_e62));
    int _e65 = _S5_;
    int _e67 = glyphLoc_0_[1u];
    loc_0_ = ivec2(_e65, _e67);
    int _e70 = loc_0_[1u];
    int _e71 = _S5_;
    loc_0_[1u] = (_e70 + (_e71 >> uint(12)));
    int _e77 = loc_0_[0u];
    loc_0_[0u] = (_e77 & 4095);
    ivec2 _e80 = loc_0_;
    return _e80;
}

CoverageBandSpan_0_ CoverageBandSpan_x24init_0_u0028_i1_u003b_i1_u003b(inout int first_1_, inout int last_1_) {
    CoverageBandSpan_0_ _S3_ = CoverageBandSpan_0_(0, 0);
    int _e59 = first_1_;
    _S3_.first_0_ = _e59;
    int _e61 = last_1_;
    _S3_.last_0_ = _e61;
    CoverageBandSpan_0_ _e63 = _S3_;
    return _e63;
}

CoverageBandSpan_0_ computeCoverageBandSpan_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_i1_u003b(inout float coord_0_, inout float eppAxis_0_, inout float bandScale_0_, inout float bandOffset_0_, inout int bandMax_0_) {
    float center_0_ = 0.0;
    float _S4_ = 0.0;
    int first_2_ = 0;
    int param_29 = 0;
    int param_30 = 0;
    float _e66 = coord_0_;
    float _e67 = bandScale_0_;
    float _e69 = bandOffset_0_;
    center_0_ = ((_e66 * _e67) + _e69);
    float _e71 = eppAxis_0_;
    float _e72 = bandScale_0_;
    _S4_ = max((abs((_e71 * _e72)) * 0.5), 1e-5);
    float _e77 = center_0_;
    float _e78 = _S4_;
    int _e81 = bandMax_0_;
    first_2_ = min(max(int((_e77 - _e78)), 0), _e81);
    int _e83 = first_2_;
    float _e84 = center_0_;
    float _e85 = _S4_;
    int _e88 = bandMax_0_;
    int _e91 = first_2_;
    param_29 = _e91;
    param_30 = max(_e83, min(max(int((_e84 + _e85)), 0), _e88));
    CoverageBandSpan_0_ _e92 = CoverageBandSpan_x24init_0_u0028_i1_u003b_i1_u003b(param_29, param_30);
    return _e92;
}

float evalGlyphCoverage_0_u0028_vf2_u003b_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b_tA21_u003b_utA21_u003b_f1_u003b(inout vec2 rc_2_, inout vec2 epp_0_, inout vec2 ppe_2_, inout ivec2 gLoc_0_, inout ivec2 bandMax_1_, inout vec4 banding_0_, inout int texLayer_2_, highp sampler2DArray curve_tex_2_, highp usampler2DArray band_tex_0_, inout float coverage_exponent_2_) {
    int _S48_ = 0;
    CoverageBandSpan_0_ hSpan_0_ = CoverageBandSpan_0_(0, 0);
    float param_31 = 0.0;
    float param_32 = 0.0;
    float param_33 = 0.0;
    float param_34 = 0.0;
    int param_35 = 0;
    CoverageBandSpan_0_ vSpan_0_ = CoverageBandSpan_0_(0, 0);
    float param_36 = 0.0;
    float param_37 = 0.0;
    float param_38 = 0.0;
    float param_39 = 0.0;
    int param_40 = 0;
    float xcov_1_ = 0.0;
    float xwgt_1_ = 0.0;
    bool _S49_ = false;
    int band_1_ = 0;
    ivec4 _S50_ = ivec4(0);
    ivec2 param_41 = ivec2(0);
    uint param_42 = 0u;
    uvec2 hbd_0_ = uvec2(0u);
    ivec2 _S51_ = ivec2(0);
    ivec2 param_43 = ivec2(0);
    uint param_44 = 0u;
    int _S52_ = 0;
    int i_0_ = 0;
    ivec4 _S53_ = ivec4(0);
    ivec2 param_45 = ivec2(0);
    uint param_46 = 0u;
    uvec2 ref_4_ = uvec2(0u);
    bool _S47_ = false;
    uvec2 param_47 = uvec2(0u);
    int param_48 = 0;
    int param_49 = 0;
    bool _S54_ = false;
    uvec2 param_50 = uvec2(0u);
    float param_51 = 0.0;
    float param_52 = 0.0;
    vec2 param_53 = vec2(0.0);
    vec2 param_54 = vec2(0.0);
    ivec2 param_55 = ivec2(0);
    int param_56 = 0;
    float ycov_1_ = 0.0;
    float ywgt_1_ = 0.0;
    bool _S55_ = false;
    ivec4 _S56_ = ivec4(0);
    ivec2 param_57 = ivec2(0);
    uint param_58 = 0u;
    uvec2 vbd_0_ = uvec2(0u);
    ivec2 _S57_ = ivec2(0);
    ivec2 param_59 = ivec2(0);
    uint param_60 = 0u;
    int _S58_ = 0;
    ivec4 _S59_ = ivec4(0);
    ivec2 param_61 = ivec2(0);
    uint param_62 = 0u;
    uvec2 ref_5_ = uvec2(0u);
    uvec2 param_63 = uvec2(0u);
    int param_64 = 0;
    int param_65 = 0;
    bool _S60_ = false;
    uvec2 param_66 = uvec2(0u);
    float param_67 = 0.0;
    float param_68 = 0.0;
    vec2 param_69 = vec2(0.0);
    vec2 param_70 = vec2(0.0);
    ivec2 param_71 = ivec2(0);
    int param_72 = 0;
    float param_73 = 0.0;
    int param_74 = 0;
    float param_75 = 0.0;
    int param_76 = 0;
    float param_77 = 0.0;
    int param_78 = 0;
    float param_79 = 0.0;
    float param_80 = 0.0;
    int _e143 = bandMax_1_[1u];
    _S48_ = _e143;
    float _e145 = rc_2_[1u];
    param_31 = _e145;
    float _e147 = epp_0_[1u];
    param_32 = _e147;
    float _e149 = banding_0_[1u];
    param_33 = _e149;
    float _e151 = banding_0_[3u];
    param_34 = _e151;
    int _e152 = _S48_;
    param_35 = _e152;
    CoverageBandSpan_0_ _e153 = computeCoverageBandSpan_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_i1_u003b(param_31, param_32, param_33, param_34, param_35);
    hSpan_0_ = _e153;
    float _e155 = rc_2_[0u];
    param_36 = _e155;
    float _e157 = epp_0_[0u];
    param_37 = _e157;
    float _e159 = banding_0_[0u];
    param_38 = _e159;
    float _e161 = banding_0_[2u];
    param_39 = _e161;
    int _e163 = bandMax_1_[0u];
    param_40 = _e163;
    CoverageBandSpan_0_ _e164 = computeCoverageBandSpan_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_i1_u003b(param_36, param_37, param_38, param_39, param_40);
    vSpan_0_ = _e164;
    xcov_1_ = 0.0;
    xwgt_1_ = 0.0;
    int _e166 = hSpan_0_.first_0_;
    int _e168 = hSpan_0_.last_0_;
    _S49_ = (_e166 != _e168);
    int _e171 = hSpan_0_.first_0_;
    band_1_ = _e171;
    while(true) {
        int _e172 = band_1_;
        int _e174 = hSpan_0_.last_0_;
        if ((_e172 <= _e174)) {
        } else {
            break;
        }
        int _e176 = band_1_;
        ivec2 _e178 = gLoc_0_;
        param_41 = _e178;
        param_42 = uint(_e176);
        ivec2 _e179 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_41, param_42);
        int _e180 = texLayer_2_;
        _S50_ = ivec4(_e179.x, _e179.y, _e180, 0);
        ivec4 _e184 = _S50_;
        ivec3 _e185 = _e184.xyz;
        int _e187 = _S50_[3u];
        uvec4 _e193 = texelFetch(band_tex_0_, ivec3(ivec2(_e185.x, _e185.y), int(_e185.z)), _e187);
        hbd_0_ = _e193.xy;
        ivec2 _e195 = gLoc_0_;
        param_43 = _e195;
        uint _e197 = hbd_0_[1u];
        param_44 = _e197;
        ivec2 _e198 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_43, param_44);
        _S51_ = _e198;
        uint _e200 = hbd_0_[0u];
        _S52_ = int(_e200);
        i_0_ = 0;
        while(true) {
            int _e202 = i_0_;
            int _e203 = _S52_;
            if ((_e202 < _e203)) {
            } else {
                break;
            }
            int _e205 = i_0_;
            ivec2 _e207 = _S51_;
            param_45 = _e207;
            param_46 = uint(_e205);
            ivec2 _e208 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_45, param_46);
            int _e209 = texLayer_2_;
            _S53_ = ivec4(_e208.x, _e208.y, _e209, 0);
            ivec4 _e213 = _S53_;
            ivec3 _e214 = _e213.xyz;
            int _e216 = _S53_[3u];
            uvec4 _e222 = texelFetch(band_tex_0_, ivec3(ivec2(_e214.x, _e214.y), int(_e214.z)), _e216);
            ref_4_ = _e222.xy;
            bool _e224 = _S49_;
            if (_e224) {
                uvec2 _e225 = ref_4_;
                param_47 = _e225;
                int _e226 = band_1_;
                param_48 = _e226;
                int _e228 = hSpan_0_.first_0_;
                param_49 = _e228;
                bool _e229 = isCoverageBandSpanOwner_0_u0028_vu2_u003b_i1_u003b_i1_u003b(param_47, param_48, param_49);
                _S47_ = !(_e229);
            } else {
                _S47_ = false;
            }
            bool _e231 = _S47_;
            if (_e231) {
                int _e232 = i_0_;
                i_0_ = (_e232 + 1);
                continue;
            }
            uvec2 _e234 = ref_4_;
            param_50 = _e234;
            ivec2 _e235 = decodeBandCurveLoc_0_u0028_vu2_u003b(param_50);
            float _e236 = xcov_1_;
            param_51 = _e236;
            float _e237 = xwgt_1_;
            param_52 = _e237;
            vec2 _e238 = rc_2_;
            param_53 = _e238;
            vec2 _e239 = ppe_2_;
            param_54 = _e239;
            param_55 = _e235;
            int _e240 = texLayer_2_;
            param_56 = _e240;
            bool _e241 = accumulateHorizContribution_0_u0028_f1_u003b_f1_u003b_vf2_u003b_vf2_u003b_vi2_u003b_i1_u003b_tA21_u003b(param_51, param_52, param_53, param_54, param_55, param_56, curve_tex_2_);
            float _e242 = param_51;
            xcov_1_ = _e242;
            float _e243 = param_52;
            xwgt_1_ = _e243;
            _S54_ = _e241;
            bool _e244 = _S54_;
            if (!(_e244)) {
                break;
            }
            int _e246 = i_0_;
            i_0_ = (_e246 + 1);
            continue;
        }
        int _e248 = band_1_;
        band_1_ = (_e248 + 1);
        continue;
    }
    ycov_1_ = 0.0;
    ywgt_1_ = 0.0;
    int _e251 = vSpan_0_.first_0_;
    int _e253 = vSpan_0_.last_0_;
    _S55_ = (_e251 != _e253);
    int _e256 = vSpan_0_.first_0_;
    band_1_ = _e256;
    while(true) {
        int _e257 = band_1_;
        int _e259 = vSpan_0_.last_0_;
        if ((_e257 <= _e259)) {
        } else {
            break;
        }
        int _e261 = _S48_;
        int _e263 = band_1_;
        ivec2 _e266 = gLoc_0_;
        param_57 = _e266;
        param_58 = uint(((_e261 + 1) + _e263));
        ivec2 _e267 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_57, param_58);
        int _e268 = texLayer_2_;
        _S56_ = ivec4(_e267.x, _e267.y, _e268, 0);
        ivec4 _e272 = _S56_;
        ivec3 _e273 = _e272.xyz;
        int _e275 = _S56_[3u];
        uvec4 _e281 = texelFetch(band_tex_0_, ivec3(ivec2(_e273.x, _e273.y), int(_e273.z)), _e275);
        vbd_0_ = _e281.xy;
        ivec2 _e283 = gLoc_0_;
        param_59 = _e283;
        uint _e285 = vbd_0_[1u];
        param_60 = _e285;
        ivec2 _e286 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_59, param_60);
        _S57_ = _e286;
        uint _e288 = vbd_0_[0u];
        _S58_ = int(_e288);
        i_0_ = 0;
        while(true) {
            int _e290 = i_0_;
            int _e291 = _S58_;
            if ((_e290 < _e291)) {
            } else {
                break;
            }
            int _e293 = i_0_;
            ivec2 _e295 = _S57_;
            param_61 = _e295;
            param_62 = uint(_e293);
            ivec2 _e296 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_61, param_62);
            int _e297 = texLayer_2_;
            _S59_ = ivec4(_e296.x, _e296.y, _e297, 0);
            ivec4 _e301 = _S59_;
            ivec3 _e302 = _e301.xyz;
            int _e304 = _S59_[3u];
            uvec4 _e310 = texelFetch(band_tex_0_, ivec3(ivec2(_e302.x, _e302.y), int(_e302.z)), _e304);
            ref_5_ = _e310.xy;
            bool _e312 = _S55_;
            if (_e312) {
                uvec2 _e313 = ref_5_;
                param_63 = _e313;
                int _e314 = band_1_;
                param_64 = _e314;
                int _e316 = vSpan_0_.first_0_;
                param_65 = _e316;
                bool _e317 = isCoverageBandSpanOwner_0_u0028_vu2_u003b_i1_u003b_i1_u003b(param_63, param_64, param_65);
                _S47_ = !(_e317);
            } else {
                _S47_ = false;
            }
            bool _e319 = _S47_;
            if (_e319) {
                int _e320 = i_0_;
                i_0_ = (_e320 + 1);
                continue;
            }
            uvec2 _e322 = ref_5_;
            param_66 = _e322;
            ivec2 _e323 = decodeBandCurveLoc_0_u0028_vu2_u003b(param_66);
            float _e324 = ycov_1_;
            param_67 = _e324;
            float _e325 = ywgt_1_;
            param_68 = _e325;
            vec2 _e326 = rc_2_;
            param_69 = _e326;
            vec2 _e327 = ppe_2_;
            param_70 = _e327;
            param_71 = _e323;
            int _e328 = texLayer_2_;
            param_72 = _e328;
            bool _e329 = accumulateVertContribution_0_u0028_f1_u003b_f1_u003b_vf2_u003b_vf2_u003b_vi2_u003b_i1_u003b_tA21_u003b(param_67, param_68, param_69, param_70, param_71, param_72, curve_tex_2_);
            float _e330 = param_67;
            ycov_1_ = _e330;
            float _e331 = param_68;
            ywgt_1_ = _e331;
            _S60_ = _e329;
            bool _e332 = _S60_;
            if (!(_e332)) {
                break;
            }
            int _e334 = i_0_;
            i_0_ = (_e334 + 1);
            continue;
        }
        int _e336 = band_1_;
        band_1_ = (_e336 + 1);
        continue;
    }
    float _e338 = xcov_1_;
    float _e339 = xwgt_1_;
    float _e341 = ycov_1_;
    float _e342 = ywgt_1_;
    float _e345 = xwgt_1_;
    float _e346 = ywgt_1_;
    param_73 = (((_e338 * _e339) + (_e341 * _e342)) / max((_e345 + _e346), 1.5258789e-5));
    param_74 = 0;
    float _e350 = applyFillRule_0_u0028_f1_u003b_i1_u003b(param_73, param_74);
    float _e351 = xcov_1_;
    param_75 = _e351;
    param_76 = 0;
    float _e352 = applyFillRule_0_u0028_f1_u003b_i1_u003b(param_75, param_76);
    float _e353 = ycov_1_;
    param_77 = _e353;
    param_78 = 0;
    float _e354 = applyFillRule_0_u0028_f1_u003b_i1_u003b(param_77, param_78);
    param_79 = max(_e350, min(_e352, _e354));
    float _e357 = coverage_exponent_2_;
    param_80 = _e357;
    float _e358 = applyCoverageTransfer_0_u0028_f1_u003b_f1_u003b(param_79, param_80);
    return _e358;
}

ivec2 offsetTtHintedInfoLoc_0_u0028_t21_u003b_vi2_u003b_i1_u003b(highp sampler2D layer_tex_0_, inout ivec2 base_0_, inout int offset_0_) {
    uint uw_0_ = 0u;
    int width_0_ = 0;
    int texel_0_ = 0;
    int _S1_ = 0;
    int _S2_ = 0;
    uw_0_ = uint(ivec2(uvec2(textureSize(layer_tex_0_, 0).xy)).x);
    uint _e68 = uw_0_;
    width_0_ = int(_e68);
    int _e71 = base_0_[1u];
    int _e72 = width_0_;
    int _e75 = base_0_[0u];
    int _e77 = offset_0_;
    texel_0_ = (((_e71 * _e72) + _e75) + _e77);
    int _e79 = texel_0_;
    int _e80 = width_0_;
    _S1_ = (_e79 - (int(floor((float(_e79) / float(_e80)))) * _e80));
    int _e88 = texel_0_;
    int _e89 = width_0_;
    _S2_ = (_e88 / _e89);
    int _e91 = _S1_;
    int _e92 = _S2_;
    return ivec2(_e91, _e92);
}

vec4 snailTtHintedTextFragment_0_u0028_struct_u002d_TtHintedVaryings_0_u002d_vf4_u002d_vf4_u002d_vf2_u002d_vf4_u002d_vi41_u003b_tA21_u003b_utA21_u003b_t21_u003b_i1_u003b_i1_u003b_f1_u003b_i1_u003b(inout TtHintedVaryings_0_ v_1_, highp sampler2DArray curve_tex_3_, highp usampler2DArray band_tex_1_, highp sampler2D layer_tex_1_, inout int layer_base_1_, inout int output_srgb_1_, inout float coverage_exponent_3_, inout int mask_output_1_) {
    int _S63_ = 0;
    vec2 epp_1_ = vec2(0.0);
    vec2 ppe_3_ = vec2(0.0);
    ivec2 info_base_0_ = ivec2(0);
    ivec3 _S64_ = ivec3(0);
    vec4 header_0_ = vec4(0.0);
    ivec2 _S65_ = ivec2(0);
    ivec2 param_81 = ivec2(0);
    int param_82 = 0;
    ivec3 _S66_ = ivec3(0);
    int packed_counts_0_ = 0;
    float cov_2_ = 0.0;
    vec2 param_83 = vec2(0.0);
    vec2 param_84 = vec2(0.0);
    vec2 param_85 = vec2(0.0);
    ivec2 param_86 = ivec2(0);
    ivec2 param_87 = ivec2(0);
    vec4 param_88 = vec4(0.0);
    int param_89 = 0;
    float param_90 = 0.0;
    vec4 premul_1_ = vec4(0.0);
    vec4 param_91 = vec4(0.0);
    float param_92 = 0.0;
    vec4 _S67_ = vec4(0.0);
    vec4 param_93 = vec4(0.0);
    int _e91 = v_1_.glyph_0_[3u];
    _S63_ = _e91;
    int _e92 = _S63_;
    if ((((_e92 >> uint(8)) & 255) != 255)) {
        discard;
    }
    int _e97 = _S63_;
    if (((_e97 & 255) != 2)) {
        discard;
    }
    vec2 _e101 = v_1_.texcoord_0_;
    vec2 _e102 = fwidth(_e101);
    epp_1_ = _e102;
    float _e104 = epp_1_[0u];
    float _e108 = epp_1_[1u];
    ppe_3_ = vec2((1.0 / max(_e104, 1.5258789e-5)), (1.0 / max(_e108, 1.5258789e-5)));
    ivec4 _e113 = v_1_.glyph_0_;
    info_base_0_ = _e113.xy;
    ivec2 _e115 = info_base_0_;
    _S64_ = ivec3(_e115.x, _e115.y, 0);
    ivec3 _e119 = _S64_;
    int _e122 = _S64_[2u];
    vec4 _e123 = texelFetch(layer_tex_1_, _e119.xy, _e122);
    header_0_ = _e123;
    ivec2 _e124 = info_base_0_;
    param_81 = _e124;
    param_82 = 1;
    ivec2 _e125 = offsetTtHintedInfoLoc_0_u0028_t21_u003b_vi2_u003b_i1_u003b(layer_tex_1_, param_81, param_82);
    _S65_ = _e125;
    ivec2 _e126 = _S65_;
    _S66_ = ivec3(_e126.x, _e126.y, 0);
    float _e131 = header_0_[2u];
    packed_counts_0_ = floatBitsToInt(_e131);
    float _e134 = header_0_[0u];
    float _e137 = header_0_[1u];
    int _e140 = packed_counts_0_;
    int _e144 = packed_counts_0_;
    ivec3 _e147 = _S66_;
    int _e150 = _S66_[2u];
    vec4 _e151 = texelFetch(layer_tex_1_, _e147.xy, _e150);
    int _e152 = layer_base_1_;
    float _e155 = v_1_.banding_1_[3u];
    vec2 _e159 = v_1_.texcoord_0_;
    param_83 = _e159;
    vec2 _e160 = epp_1_;
    param_84 = _e160;
    vec2 _e161 = ppe_3_;
    param_85 = _e161;
    param_86 = ivec2(int(_e134), int(_e137));
    param_87 = ivec2(((_e140 >> uint(16)) & 65535), (_e144 & 65535));
    param_88 = _e151;
    param_89 = (_e152 + int(_e155));
    float _e162 = coverage_exponent_3_;
    param_90 = _e162;
    float _e163 = evalGlyphCoverage_0_u0028_vf2_u003b_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b_tA21_u003b_utA21_u003b_f1_u003b(param_83, param_84, param_85, param_86, param_87, param_88, param_89, curve_tex_3_, band_tex_1_, param_90);
    cov_2_ = _e163;
    float _e164 = cov_2_;
    if ((_e164 < 0.003921569)) {
        discard;
    }
    vec4 _e167 = v_1_.color_2_;
    vec4 _e169 = v_1_.tint_0_;
    param_91 = (_e167 * _e169);
    float _e171 = cov_2_;
    param_92 = _e171;
    vec4 _e172 = premultiplyColor_0_u0028_vf4_u003b_f1_u003b(param_91, param_92);
    premul_1_ = _e172;
    int _e173 = mask_output_1_;
    if ((_e173 != 0)) {
        float _e176 = premul_1_[3u];
        _S67_ = vec4(_e176);
    } else {
        int _e178 = output_srgb_1_;
        if ((_e178 != 0)) {
            vec4 _e180 = premul_1_;
            param_93 = _e180;
            vec4 _e181 = srgbEncodePremultiplied_0_u0028_vf4_u003b(param_93);
            _S67_ = _e181;
        } else {
            vec4 _e182 = premul_1_;
            _S67_ = _e182;
        }
    }
    vec4 _e183 = _S67_;
    return _e183;
}

void main_1() {
    TtHintedVaryings_0_ v_2_ = TtHintedVaryings_0_(vec4(0.0), vec4(0.0), vec2(0.0), vec4(0.0), ivec4(0));
    vec4 _S68_ = vec4(0.0);
    TtHintedVaryings_0_ param_94 = TtHintedVaryings_0_(vec4(0.0), vec4(0.0), vec2(0.0), vec4(0.0), ivec4(0));
    int param_95 = 0;
    int param_96 = 0;
    float param_97 = 0.0;
    int param_98 = 0;
    vec4 _e63 = input_color_0_1;
    v_2_.color_2_ = _e63;
    vec4 _e65 = input_tint_0_1;
    v_2_.tint_0_ = _e65;
    vec2 _e67 = input_texcoord_0_1;
    v_2_.texcoord_0_ = _e67;
    vec4 _e69 = input_banding_0_1;
    v_2_.banding_1_ = _e69;
    ivec4 _e71 = input_glyph_0_1;
    v_2_.glyph_0_ = _e71;
    TtHintedVaryings_0_ _e73 = v_2_;
    param_94 = _e73;
    int _e75 = _group_0_binding_0_fs.layer_base_0_;
    param_95 = _e75;
    int _e77 = _group_0_binding_0_fs.output_srgb_0_;
    param_96 = _e77;
    float _e79 = _group_0_binding_0_fs.coverage_exponent_0_;
    param_97 = _e79;
    int _e81 = _group_0_binding_0_fs.mask_output_0_;
    param_98 = _e81;
    vec4 _e82 = snailTtHintedTextFragment_0_u0028_struct_u002d_TtHintedVaryings_0_u002d_vf4_u002d_vf4_u002d_vf2_u002d_vf4_u002d_vi41_u003b_tA21_u003b_utA21_u003b_t21_u003b_i1_u003b_i1_u003b_f1_u003b_i1_u003b(param_94, _group_0_binding_1_fs, _group_0_binding_2_fs, _group_0_binding_3_fs, param_95, param_96, param_97, param_98);
    _S68_ = _e82;
    vec4 _e83 = _S68_;
    entryPointParam_fragmentMain_0_ = _e83;
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
    vec4 _e11 = entryPointParam_fragmentMain_0_;
    _fs2p_location0 = _e11;
    return;
}

