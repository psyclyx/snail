#version 330 core
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
struct CoverageBandSpan_0_ {
    int first_0_;
    int last_0_;
};
struct AutohintVaryings_0_ {
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
vec4 input_paint_0_1 = vec4(0.0);

vec3 input_texcoord_layer_0_1 = vec3(0.0);

ivec2 input_info_0_1 = ivec2(0);

uvec4 input_policy0_0_1 = uvec4(0u);

uvec3 input_policy1_0_1 = uvec3(0u);

vec4 input_x_targets0_0_1 = vec4(0.0);

vec4 input_x_targets1_0_1 = vec4(0.0);

vec4 input_x_targets2_0_1 = vec4(0.0);

vec4 input_x_targets3_0_1 = vec4(0.0);

vec4 input_y_targets0_0_1 = vec4(0.0);

vec4 input_y_targets1_0_1 = vec4(0.0);

vec4 input_y_targets2_0_1 = vec4(0.0);

vec4 input_y_targets3_0_1 = vec4(0.0);

uvec4 input_x_sources_0_1 = uvec4(0u);

uvec4 input_y_sources_0_1 = uvec4(0u);

uniform sampler2DArray _group_0_binding_1_fs;

uniform usampler2DArray _group_0_binding_2_fs;

uniform sampler2D _group_0_binding_3_fs;

layout(std140) uniform block_SnailPushConstants_0_block_0Fragment { block_SnailPushConstants_0_ _group_0_binding_0_fs; };

vec4 entryPointParam_fragmentMain_0_ = vec4(0.0);

smooth in vec4 _vs2fs_location0;
smooth in vec3 _vs2fs_location1;
flat in ivec2 _vs2fs_location2;
flat in uvec4 _vs2fs_location3;
flat in uvec3 _vs2fs_location4;
flat in vec4 _vs2fs_location5;
flat in vec4 _vs2fs_location6;
flat in vec4 _vs2fs_location7;
flat in vec4 _vs2fs_location8;
flat in vec4 _vs2fs_location9;
flat in vec4 _vs2fs_location10;
flat in vec4 _vs2fs_location11;
flat in vec4 _vs2fs_location12;
flat in uvec4 _vs2fs_location13;
flat in uvec4 _vs2fs_location14;
layout(location = 0) out vec4 _fs2p_location0;

float srgbEncode_0_u0028_f1_u003b(inout float c_1_) {
    float _S109_ = 0.0;
    float _e95 = c_1_;
    if ((_e95 <= 0.0031308)) {
        float _e97 = c_1_;
        _S109_ = (_e97 * 12.92);
    } else {
        float _e99 = c_1_;
        _S109_ = ((1.055 * pow(_e99, 0.41666666)) - 0.055);
    }
    float _e103 = _S109_;
    return _e103;
}

vec3 linearToSrgb_0_u0028_vf3_u003b(inout vec3 color_1_) {
    float param = 0.0;
    float param_1 = 0.0;
    float param_2 = 0.0;
    float _e98 = color_1_[0u];
    param = max(_e98, 0.0);
    float _e100 = srgbEncode_0_u0028_f1_u003b(param);
    float _e102 = color_1_[1u];
    param_1 = max(_e102, 0.0);
    float _e104 = srgbEncode_0_u0028_f1_u003b(param_1);
    float _e106 = color_1_[2u];
    param_2 = max(_e106, 0.0);
    float _e108 = srgbEncode_0_u0028_f1_u003b(param_2);
    return vec3(_e100, _e104, _e108);
}

vec4 srgbEncodePremultiplied_0_u0028_vf4_u003b(inout vec4 premul_0_) {
    float _S110_ = 0.0;
    vec3 param_3 = vec3(0.0);
    float _e97 = premul_0_[3u];
    _S110_ = _e97;
    float _e98 = _S110_;
    if ((_e98 <= 0.0)) {
        return vec4(0.0, 0.0, 0.0, 0.0);
    }
    vec4 _e100 = premul_0_;
    float _e102 = _S110_;
    param_3 = (_e100.xyz * (1.0 / _e102));
    vec3 _e105 = linearToSrgb_0_u0028_vf3_u003b(param_3);
    float _e106 = _S110_;
    vec3 _e107 = (_e105 * _e106);
    float _e108 = _S110_;
    return vec4(_e107.x, _e107.y, _e107.z, _e108);
}

vec4 premultiplyColor_0_u0028_vf4_u003b_f1_u003b(inout vec4 color_0_, inout float cov_1_) {
    float alpha_0_ = 0.0;
    float _e97 = color_0_[3u];
    float _e98 = cov_1_;
    alpha_0_ = (_e97 * _e98);
    vec4 _e100 = color_0_;
    float _e102 = alpha_0_;
    vec3 _e103 = (_e100.xyz * _e102);
    float _e104 = alpha_0_;
    return vec4(_e103.x, _e103.y, _e103.z, _e104);
}

float applyCoverageTransfer_0_u0028_f1_u003b_f1_u003b(inout float cov_0_, inout float coverage_exponent_1_) {
    float clamped_0_ = 0.0;
    float _S93_ = 0.0;
    float _S94_ = 0.0;
    float _e98 = cov_0_;
    clamped_0_ = clamp(_e98, 0.0, 1.0);
    float _e100 = coverage_exponent_1_;
    _S93_ = max(_e100, 1.5258789e-5);
    float _e102 = _S93_;
    if ((abs((_e102 - 1.0)) <= 1e-6)) {
        float _e106 = clamped_0_;
        _S94_ = _e106;
    } else {
        float _e107 = clamped_0_;
        float _e108 = _S93_;
        _S94_ = pow(_e107, _e108);
    }
    float _e110 = _S94_;
    return _e110;
}

float applyFillRule_0_u0028_f1_u003b_i1_u003b(inout float winding_0_, inout int fill_rule_mode_0_) {
    int _e95 = fill_rule_mode_0_;
    if ((_e95 == 1)) {
        float _e97 = winding_0_;
        return (1.0 - abs(((fract((_e97 * 0.5)) * 2.0) - 1.0)));
    }
    float _e104 = winding_0_;
    return abs(_e104);
}

float snapNearTangentSqrt_0_u0028_f1_u003b_f1_u003b_f1_u003b(inout float disc_0_, inout float b_1_, inout float ac_0_) {
    float _S56_ = 0.0;
    float _e97 = disc_0_;
    float _e98 = b_1_;
    float _e99 = b_1_;
    float _e101 = ac_0_;
    if ((_e97 <= (max((_e98 * _e99), abs(_e101)) * 3e-6))) {
        _S56_ = 0.0;
    } else {
        float _e106 = disc_0_;
        _S56_ = sqrt(_e106);
    }
    float _e108 = _S56_;
    return _e108;
}

vec2 solveVertPoly_0_u0028_vf4_u003b_vf2_u003b(inout vec4 p12_2_, inout vec2 p3_2_) {
    vec2 _S75_ = vec2(0.0);
    vec2 _S76_ = vec2(0.0);
    vec2 a_1_ = vec2(0.0);
    vec2 b_3_ = vec2(0.0);
    float _S77_ = 0.0;
    float _S78_ = 0.0;
    float t1_1_ = 0.0;
    float t2_1_ = 0.0;
    float _S79_ = 0.0;
    float _S80_ = 0.0;
    float _S81_ = 0.0;
    float sq_1_ = 0.0;
    float param_4 = 0.0;
    float param_5 = 0.0;
    float param_6 = 0.0;
    float q_2_ = 0.0;
    float _S82_ = 0.0;
    float q_3_ = 0.0;
    float _S83_ = 0.0;
    float _S84_ = 0.0;
    float _S85_ = 0.0;
    float _S86_ = 0.0;
    float _S87_ = 0.0;
    vec4 _e118 = p12_2_;
    _S75_ = _e118.xy;
    vec4 _e120 = p12_2_;
    _S76_ = _e120.zw;
    vec2 _e122 = _S75_;
    vec2 _e123 = _S76_;
    vec2 _e126 = p3_2_;
    a_1_ = ((_e122 - (_e123 * 2.0)) + _e126);
    vec2 _e128 = _S75_;
    vec2 _e129 = _S76_;
    b_3_ = (_e128 - _e129);
    float _e132 = a_1_[0u];
    _S77_ = _e132;
    float _e133 = _S77_;
    if ((abs(_e133) < 1.5258789e-5)) {
        float _e137 = b_3_[0u];
        _S78_ = _e137;
        float _e138 = _S78_;
        if ((abs(_e138) < 1.5258789e-5)) {
            t1_1_ = 0.0;
        } else {
            float _e142 = p12_2_[0u];
            float _e144 = _S78_;
            t1_1_ = ((_e142 * 0.5) / _e144);
        }
        float _e146 = t1_1_;
        t2_1_ = _e146;
    } else {
        float _e148 = b_3_[0u];
        _S79_ = _e148;
        float _e150 = p12_2_[0u];
        _S80_ = _e150;
        float _e151 = _S77_;
        float _e152 = _S80_;
        _S81_ = (_e151 * _e152);
        float _e154 = _S79_;
        float _e155 = _S79_;
        float _e157 = _S81_;
        param_4 = ((_e154 * _e155) - _e157);
        float _e159 = _S79_;
        param_5 = _e159;
        float _e160 = _S81_;
        param_6 = _e160;
        float _e161 = snapNearTangentSqrt_0_u0028_f1_u003b_f1_u003b_f1_u003b(param_4, param_5, param_6);
        sq_1_ = _e161;
        float _e162 = _S79_;
        if ((_e162 >= 0.0)) {
            float _e164 = _S79_;
            float _e165 = sq_1_;
            q_2_ = (_e164 + _e165);
            float _e167 = q_2_;
            float _e168 = _S77_;
            _S82_ = (_e167 / _e168);
            float _e170 = q_2_;
            if ((abs(_e170) < 1.5258789e-5)) {
                t1_1_ = 0.0;
            } else {
                float _e173 = _S80_;
                float _e174 = q_2_;
                t1_1_ = (_e173 / _e174);
            }
            float _e176 = _S82_;
            t2_1_ = _e176;
        } else {
            float _e177 = _S79_;
            float _e178 = sq_1_;
            q_3_ = (_e177 - _e178);
            float _e180 = q_3_;
            float _e181 = _S77_;
            _S83_ = (_e180 / _e181);
            float _e183 = q_3_;
            if ((abs(_e183) < 1.5258789e-5)) {
                t1_1_ = 0.0;
            } else {
                float _e186 = _S80_;
                float _e187 = q_3_;
                t1_1_ = (_e186 / _e187);
            }
            float _e189 = t1_1_;
            _S84_ = _e189;
            float _e190 = _S83_;
            t1_1_ = _e190;
            float _e191 = _S84_;
            t2_1_ = _e191;
        }
    }
    float _e193 = a_1_[1u];
    _S85_ = _e193;
    float _e195 = b_3_[1u];
    _S86_ = (_e195 * 2.0);
    float _e198 = p12_2_[1u];
    _S87_ = _e198;
    float _e199 = _S85_;
    float _e200 = t1_1_;
    float _e202 = _S86_;
    float _e204 = t1_1_;
    float _e206 = _S87_;
    float _e208 = _S85_;
    float _e209 = t2_1_;
    float _e211 = _S86_;
    float _e213 = t2_1_;
    float _e215 = _S87_;
    return vec2(((((_e199 * _e200) - _e202) * _e204) + _e206), ((((_e208 * _e209) - _e211) * _e213) + _e215));
}

float rootCodeCoord_0_u0028_f1_u003b(inout float v_2_) {
    float _S55_ = 0.0;
    float _e95 = v_2_;
    if ((abs(_e95) <= 1.5258789e-5)) {
        _S55_ = 0.0;
    } else {
        float _e98 = v_2_;
        _S55_ = _e98;
    }
    float _e99 = _S55_;
    return _e99;
}

uint calcRootCode_0_u0028_f1_u003b_f1_u003b_f1_u003b(inout float y1_0_, inout float y2_0_, inout float y3_0_) {
    float param_7 = 0.0;
    float param_8 = 0.0;
    float param_9 = 0.0;
    float _e99 = y3_0_;
    param_7 = _e99;
    float _e100 = rootCodeCoord_0_u0028_f1_u003b(param_7);
    float _e105 = y2_0_;
    param_8 = _e105;
    float _e106 = rootCodeCoord_0_u0028_f1_u003b(param_8);
    float _e111 = y1_0_;
    param_9 = _e111;
    float _e112 = rootCodeCoord_0_u0028_f1_u003b(param_9);
    return ((11892u >> (((floatBitsToUint(_e100) >> 29u) & 4u) | ((((floatBitsToUint(_e106) >> 30u) & 2u) | ((floatBitsToUint(_e112) >> 31u) & 4294967293u)) & 4294967291u))) & 257u);
}

ivec2 offsetCurveLoc_0_u0028_vi2_u003b_i1_u003b(inout ivec2 base_1_, inout int offset_2_) {
    int _S54_ = 0;
    ivec2 loc_1_ = ivec2(0);
    int _e98 = base_1_[0u];
    int _e99 = offset_2_;
    _S54_ = (_e98 + _e99);
    int _e101 = _S54_;
    int _e103 = base_1_[1u];
    loc_1_ = ivec2(_e101, _e103);
    int _e106 = loc_1_[1u];
    int _e107 = _S54_;
    loc_1_[1u] = (_e106 + (_e107 >> uint(12)));
    int _e113 = loc_1_[0u];
    loc_1_[0u] = (_e113 & 4095);
    ivec2 _e116 = loc_1_;
    return _e116;
}

bool accumulateVertContribution_0_u0028_f1_u003b_f1_u003b_vf2_u003b_vf2_u003b_vi2_u003b_i1_u003b_tA21_u003b(inout float ycov_0_, inout float ywgt_0_, inout vec2 rc_1_, inout vec2 ppe_1_, inout ivec2 cLoc_1_, inout int texLayer_1_, sampler2DArray curve_tex_1_) {
    ivec4 _S88_ = ivec4(0);
    vec4 tex0_1_ = vec4(0.0);
    ivec4 _S89_ = ivec4(0);
    ivec2 param_10 = ivec2(0);
    int param_11 = 0;
    vec4 p12_3_ = vec4(0.0);
    vec2 p3_3_ = vec2(0.0);
    float _S90_ = 0.0;
    uint code_1_ = 0u;
    float param_12 = 0.0;
    float param_13 = 0.0;
    float param_14 = 0.0;
    vec2 r_1_ = vec2(0.0);
    vec4 param_15 = vec4(0.0);
    vec2 param_16 = vec2(0.0);
    float _S91_ = 0.0;
    float _S92_ = 0.0;
    ivec2 _e117 = cLoc_1_;
    int _e118 = texLayer_1_;
    _S88_ = ivec4(_e117.x, _e117.y, _e118, 0);
    ivec4 _e122 = _S88_;
    ivec3 _e123 = _e122.xyz;
    int _e125 = _S88_[3u];
    vec4 _e131 = texelFetch(curve_tex_1_, ivec3(ivec2(_e123.x, _e123.y), int(_e123.z)), _e125);
    tex0_1_ = _e131;
    ivec2 _e132 = cLoc_1_;
    param_10 = _e132;
    param_11 = 1;
    ivec2 _e133 = offsetCurveLoc_0_u0028_vi2_u003b_i1_u003b(param_10, param_11);
    int _e134 = texLayer_1_;
    _S89_ = ivec4(_e133.x, _e133.y, _e134, 0);
    vec4 _e138 = tex0_1_;
    vec2 _e139 = _e138.xy;
    vec4 _e140 = tex0_1_;
    vec2 _e141 = _e140.zw;
    vec2 _e147 = rc_1_;
    p12_3_ = (vec4(_e139.x, _e139.y, _e141.x, _e141.y) - vec4(_e147.x, _e147.y, _e147.x, _e147.y));
    ivec4 _e154 = _S89_;
    ivec3 _e155 = _e154.xyz;
    int _e157 = _S89_[3u];
    vec4 _e163 = texelFetch(curve_tex_1_, ivec3(ivec2(_e155.x, _e155.y), int(_e155.z)), _e157);
    vec2 _e165 = rc_1_;
    p3_3_ = (_e163.xy - _e165);
    float _e168 = ppe_1_[1u];
    _S90_ = _e168;
    float _e170 = p12_3_[1u];
    float _e172 = p12_3_[3u];
    float _e175 = p3_3_[1u];
    float _e177 = _S90_;
    if (((max(max(_e170, _e172), _e175) * _e177) < -0.5)) {
        return false;
    }
    float _e181 = p12_3_[0u];
    param_12 = _e181;
    float _e183 = p12_3_[2u];
    param_13 = _e183;
    float _e185 = p3_3_[0u];
    param_14 = _e185;
    uint _e186 = calcRootCode_0_u0028_f1_u003b_f1_u003b_f1_u003b(param_12, param_13, param_14);
    code_1_ = _e186;
    uint _e187 = code_1_;
    if ((_e187 != 0u)) {
        vec4 _e189 = p12_3_;
        param_15 = _e189;
        vec2 _e190 = p3_3_;
        param_16 = _e190;
        vec2 _e191 = solveVertPoly_0_u0028_vf4_u003b_vf2_u003b(param_15, param_16);
        float _e192 = _S90_;
        r_1_ = (_e191 * _e192);
        uint _e194 = code_1_;
        if (((_e194 & 1u) != 0u)) {
            float _e198 = r_1_[0u];
            _S91_ = _e198;
            float _e199 = ycov_0_;
            float _e200 = _S91_;
            ycov_0_ = (_e199 - clamp((_e200 + 0.5), 0.0, 1.0));
            float _e204 = ywgt_0_;
            float _e205 = _S91_;
            ywgt_0_ = max(_e204, clamp((1.0 - (abs(_e205) * 2.0)), 0.0, 1.0));
        }
        uint _e211 = code_1_;
        if ((_e211 > 1u)) {
            float _e214 = r_1_[1u];
            _S92_ = _e214;
            float _e215 = ycov_0_;
            float _e216 = _S92_;
            ycov_0_ = (_e215 + clamp((_e216 + 0.5), 0.0, 1.0));
            float _e220 = ywgt_0_;
            float _e221 = _S92_;
            ywgt_0_ = max(_e220, clamp((1.0 - (abs(_e221) * 2.0)), 0.0, 1.0));
        }
    }
    return true;
}

vec2 solveHorizPoly_0_u0028_vf4_u003b_vf2_u003b(inout vec4 p12_0_, inout vec2 p3_0_) {
    vec2 _S57_ = vec2(0.0);
    vec2 _S58_ = vec2(0.0);
    vec2 a_0_ = vec2(0.0);
    vec2 b_2_ = vec2(0.0);
    float _S59_ = 0.0;
    float _S60_ = 0.0;
    float t1_0_ = 0.0;
    float t2_0_ = 0.0;
    float _S61_ = 0.0;
    float _S62_ = 0.0;
    float _S63_ = 0.0;
    float sq_0_ = 0.0;
    float param_17 = 0.0;
    float param_18 = 0.0;
    float param_19 = 0.0;
    float q_0_ = 0.0;
    float _S64_ = 0.0;
    float q_1_ = 0.0;
    float _S65_ = 0.0;
    float _S66_ = 0.0;
    float _S67_ = 0.0;
    float _S68_ = 0.0;
    float _S69_ = 0.0;
    vec4 _e118 = p12_0_;
    _S57_ = _e118.xy;
    vec4 _e120 = p12_0_;
    _S58_ = _e120.zw;
    vec2 _e122 = _S57_;
    vec2 _e123 = _S58_;
    vec2 _e126 = p3_0_;
    a_0_ = ((_e122 - (_e123 * 2.0)) + _e126);
    vec2 _e128 = _S57_;
    vec2 _e129 = _S58_;
    b_2_ = (_e128 - _e129);
    float _e132 = a_0_[1u];
    _S59_ = _e132;
    float _e133 = _S59_;
    if ((abs(_e133) < 1.5258789e-5)) {
        float _e137 = b_2_[1u];
        _S60_ = _e137;
        float _e138 = _S60_;
        if ((abs(_e138) < 1.5258789e-5)) {
            t1_0_ = 0.0;
        } else {
            float _e142 = p12_0_[1u];
            float _e144 = _S60_;
            t1_0_ = ((_e142 * 0.5) / _e144);
        }
        float _e146 = t1_0_;
        t2_0_ = _e146;
    } else {
        float _e148 = b_2_[1u];
        _S61_ = _e148;
        float _e150 = p12_0_[1u];
        _S62_ = _e150;
        float _e151 = _S59_;
        float _e152 = _S62_;
        _S63_ = (_e151 * _e152);
        float _e154 = _S61_;
        float _e155 = _S61_;
        float _e157 = _S63_;
        param_17 = ((_e154 * _e155) - _e157);
        float _e159 = _S61_;
        param_18 = _e159;
        float _e160 = _S63_;
        param_19 = _e160;
        float _e161 = snapNearTangentSqrt_0_u0028_f1_u003b_f1_u003b_f1_u003b(param_17, param_18, param_19);
        sq_0_ = _e161;
        float _e162 = _S61_;
        if ((_e162 >= 0.0)) {
            float _e164 = _S61_;
            float _e165 = sq_0_;
            q_0_ = (_e164 + _e165);
            float _e167 = q_0_;
            float _e168 = _S59_;
            _S64_ = (_e167 / _e168);
            float _e170 = q_0_;
            if ((abs(_e170) < 1.5258789e-5)) {
                t1_0_ = 0.0;
            } else {
                float _e173 = _S62_;
                float _e174 = q_0_;
                t1_0_ = (_e173 / _e174);
            }
            float _e176 = _S64_;
            t2_0_ = _e176;
        } else {
            float _e177 = _S61_;
            float _e178 = sq_0_;
            q_1_ = (_e177 - _e178);
            float _e180 = q_1_;
            float _e181 = _S59_;
            _S65_ = (_e180 / _e181);
            float _e183 = q_1_;
            if ((abs(_e183) < 1.5258789e-5)) {
                t1_0_ = 0.0;
            } else {
                float _e186 = _S62_;
                float _e187 = q_1_;
                t1_0_ = (_e186 / _e187);
            }
            float _e189 = t1_0_;
            _S66_ = _e189;
            float _e190 = _S65_;
            t1_0_ = _e190;
            float _e191 = _S66_;
            t2_0_ = _e191;
        }
    }
    float _e193 = a_0_[0u];
    _S67_ = _e193;
    float _e195 = b_2_[0u];
    _S68_ = (_e195 * 2.0);
    float _e198 = p12_0_[0u];
    _S69_ = _e198;
    float _e199 = _S67_;
    float _e200 = t1_0_;
    float _e202 = _S68_;
    float _e204 = t1_0_;
    float _e206 = _S69_;
    float _e208 = _S67_;
    float _e209 = t2_0_;
    float _e211 = _S68_;
    float _e213 = t2_0_;
    float _e215 = _S69_;
    return vec2(((((_e199 * _e200) - _e202) * _e204) + _e206), ((((_e208 * _e209) - _e211) * _e213) + _e215));
}

bool accumulateHorizContribution_0_u0028_f1_u003b_f1_u003b_vf2_u003b_vf2_u003b_vi2_u003b_i1_u003b_tA21_u003b(inout float xcov_0_, inout float xwgt_0_, inout vec2 rc_0_, inout vec2 ppe_0_, inout ivec2 cLoc_0_, inout int texLayer_0_, sampler2DArray curve_tex_0_) {
    ivec4 _S70_ = ivec4(0);
    vec4 tex0_0_ = vec4(0.0);
    ivec4 _S71_ = ivec4(0);
    ivec2 param_20 = ivec2(0);
    int param_21 = 0;
    vec4 p12_1_ = vec4(0.0);
    vec2 p3_1_ = vec2(0.0);
    float _S72_ = 0.0;
    uint code_0_ = 0u;
    float param_22 = 0.0;
    float param_23 = 0.0;
    float param_24 = 0.0;
    vec2 r_0_ = vec2(0.0);
    vec4 param_25 = vec4(0.0);
    vec2 param_26 = vec2(0.0);
    float _S73_ = 0.0;
    float _S74_ = 0.0;
    ivec2 _e117 = cLoc_0_;
    int _e118 = texLayer_0_;
    _S70_ = ivec4(_e117.x, _e117.y, _e118, 0);
    ivec4 _e122 = _S70_;
    ivec3 _e123 = _e122.xyz;
    int _e125 = _S70_[3u];
    vec4 _e131 = texelFetch(curve_tex_0_, ivec3(ivec2(_e123.x, _e123.y), int(_e123.z)), _e125);
    tex0_0_ = _e131;
    ivec2 _e132 = cLoc_0_;
    param_20 = _e132;
    param_21 = 1;
    ivec2 _e133 = offsetCurveLoc_0_u0028_vi2_u003b_i1_u003b(param_20, param_21);
    int _e134 = texLayer_0_;
    _S71_ = ivec4(_e133.x, _e133.y, _e134, 0);
    vec4 _e138 = tex0_0_;
    vec2 _e139 = _e138.xy;
    vec4 _e140 = tex0_0_;
    vec2 _e141 = _e140.zw;
    vec2 _e147 = rc_0_;
    p12_1_ = (vec4(_e139.x, _e139.y, _e141.x, _e141.y) - vec4(_e147.x, _e147.y, _e147.x, _e147.y));
    ivec4 _e154 = _S71_;
    ivec3 _e155 = _e154.xyz;
    int _e157 = _S71_[3u];
    vec4 _e163 = texelFetch(curve_tex_0_, ivec3(ivec2(_e155.x, _e155.y), int(_e155.z)), _e157);
    vec2 _e165 = rc_0_;
    p3_1_ = (_e163.xy - _e165);
    float _e168 = ppe_0_[0u];
    _S72_ = _e168;
    float _e170 = p12_1_[0u];
    float _e172 = p12_1_[2u];
    float _e175 = p3_1_[0u];
    float _e177 = _S72_;
    if (((max(max(_e170, _e172), _e175) * _e177) < -0.5)) {
        return false;
    }
    float _e181 = p12_1_[1u];
    param_22 = _e181;
    float _e183 = p12_1_[3u];
    param_23 = _e183;
    float _e185 = p3_1_[1u];
    param_24 = _e185;
    uint _e186 = calcRootCode_0_u0028_f1_u003b_f1_u003b_f1_u003b(param_22, param_23, param_24);
    code_0_ = _e186;
    uint _e187 = code_0_;
    if ((_e187 != 0u)) {
        vec4 _e189 = p12_1_;
        param_25 = _e189;
        vec2 _e190 = p3_1_;
        param_26 = _e190;
        vec2 _e191 = solveHorizPoly_0_u0028_vf4_u003b_vf2_u003b(param_25, param_26);
        float _e192 = _S72_;
        r_0_ = (_e191 * _e192);
        uint _e194 = code_0_;
        if (((_e194 & 1u) != 0u)) {
            float _e198 = r_0_[0u];
            _S73_ = _e198;
            float _e199 = xcov_0_;
            float _e200 = _S73_;
            xcov_0_ = (_e199 + clamp((_e200 + 0.5), 0.0, 1.0));
            float _e204 = xwgt_0_;
            float _e205 = _S73_;
            xwgt_0_ = max(_e204, clamp((1.0 - (abs(_e205) * 2.0)), 0.0, 1.0));
        }
        uint _e211 = code_0_;
        if ((_e211 > 1u)) {
            float _e214 = r_0_[1u];
            _S74_ = _e214;
            float _e215 = xcov_0_;
            float _e216 = _S74_;
            xcov_0_ = (_e215 - clamp((_e216 + 0.5), 0.0, 1.0));
            float _e220 = xwgt_0_;
            float _e221 = _S74_;
            xwgt_0_ = max(_e220, clamp((1.0 - (abs(_e221) * 2.0)), 0.0, 1.0));
        }
    }
    return true;
}

ivec2 decodeBandCurveLocCommon_0_u0028_vu2_u003b(inout uvec2 ref_4_) {
    uint _e95 = ref_4_[0u];
    uint _e99 = ref_4_[1u];
    return ivec2(int((_e95 & 4095u)), int((_e99 & 16383u)));
}

ivec2 decodeBandCurveLoc_0_u0028_vu2_u003b(inout uvec2 ref_5_) {
    uvec2 param_27 = uvec2(0u);
    uvec2 _e95 = ref_5_;
    param_27 = _e95;
    ivec2 _e96 = decodeBandCurveLocCommon_0_u0028_vu2_u003b(param_27);
    return _e96;
}

int decodeBandCurveFirstMemberCommon_0_u0028_vu2_u003b(inout uvec2 ref_2_) {
    uint _e95 = ref_2_[0u];
    return int((_e95 >> 12u));
}

bool isCoverageBandSpanOwner_0_u0028_vu2_u003b_i1_u003b_i1_u003b(inout uvec2 ref_3_, inout int band_0_, inout int spanFirst_0_) {
    uvec2 param_28 = uvec2(0u);
    int _e97 = band_0_;
    uvec2 _e98 = ref_3_;
    param_28 = _e98;
    int _e99 = decodeBandCurveFirstMemberCommon_0_u0028_vu2_u003b(param_28);
    int _e100 = spanFirst_0_;
    return (_e97 == max(_e99, _e100));
}

ivec2 calcBandLoc_0_u0028_vi2_u003b_u1_u003b(inout ivec2 glyphLoc_0_, inout uint offset_1_) {
    int _S53_ = 0;
    ivec2 loc_0_ = ivec2(0);
    int _e98 = glyphLoc_0_[0u];
    uint _e99 = offset_1_;
    _S53_ = (_e98 + int(_e99));
    int _e102 = _S53_;
    int _e104 = glyphLoc_0_[1u];
    loc_0_ = ivec2(_e102, _e104);
    int _e107 = loc_0_[1u];
    int _e108 = _S53_;
    loc_0_[1u] = (_e107 + (_e108 >> uint(12)));
    int _e114 = loc_0_[0u];
    loc_0_[0u] = (_e114 & 4095);
    ivec2 _e117 = loc_0_;
    return _e117;
}

CoverageBandSpan_0_ CoverageBandSpan_x24init_0_u0028_i1_u003b_i1_u003b(inout int first_1_, inout int last_1_) {
    CoverageBandSpan_0_ _S51_ = CoverageBandSpan_0_(0, 0);
    int _e96 = first_1_;
    _S51_.first_0_ = _e96;
    int _e98 = last_1_;
    _S51_.last_0_ = _e98;
    CoverageBandSpan_0_ _e100 = _S51_;
    return _e100;
}

CoverageBandSpan_0_ computeCoverageBandSpan_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_i1_u003b(inout float coord_0_, inout float eppAxis_0_, inout float bandScale_0_, inout float bandOffset_0_, inout int bandMax_0_) {
    float center_0_ = 0.0;
    float _S52_ = 0.0;
    int first_2_ = 0;
    int param_29 = 0;
    int param_30 = 0;
    float _e103 = coord_0_;
    float _e104 = bandScale_0_;
    float _e106 = bandOffset_0_;
    center_0_ = ((_e103 * _e104) + _e106);
    float _e108 = eppAxis_0_;
    float _e109 = bandScale_0_;
    _S52_ = max((abs((_e108 * _e109)) * 0.5), 1e-5);
    float _e114 = center_0_;
    float _e115 = _S52_;
    int _e118 = bandMax_0_;
    first_2_ = min(max(int((_e114 - _e115)), 0), _e118);
    int _e120 = first_2_;
    float _e121 = center_0_;
    float _e122 = _S52_;
    int _e125 = bandMax_0_;
    int _e128 = first_2_;
    param_29 = _e128;
    param_30 = max(_e120, min(max(int((_e121 + _e122)), 0), _e125));
    CoverageBandSpan_0_ _e129 = CoverageBandSpan_x24init_0_u0028_i1_u003b_i1_u003b(param_29, param_30);
    return _e129;
}

float evalGlyphCoverage_0_u0028_vf2_u003b_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b_tA21_u003b_utA21_u003b_f1_u003b(inout vec2 rc_2_, inout vec2 epp_0_, inout vec2 ppe_2_, inout ivec2 gLoc_0_, inout ivec2 bandMax_1_, inout vec4 banding_0_, inout int texLayer_2_, sampler2DArray curve_tex_2_, usampler2DArray band_tex_0_, inout float coverage_exponent_2_) {
    int _S96_ = 0;
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
    bool _S97_ = false;
    int band_1_ = 0;
    ivec4 _S98_ = ivec4(0);
    ivec2 param_41 = ivec2(0);
    uint param_42 = 0u;
    uvec2 hbd_0_ = uvec2(0u);
    ivec2 _S99_ = ivec2(0);
    ivec2 param_43 = ivec2(0);
    uint param_44 = 0u;
    int _S100_ = 0;
    int i_6_ = 0;
    ivec4 _S101_ = ivec4(0);
    ivec2 param_45 = ivec2(0);
    uint param_46 = 0u;
    uvec2 ref_6_ = uvec2(0u);
    bool _S95_ = false;
    uvec2 param_47 = uvec2(0u);
    int param_48 = 0;
    int param_49 = 0;
    bool _S102_ = false;
    uvec2 param_50 = uvec2(0u);
    float param_51 = 0.0;
    float param_52 = 0.0;
    vec2 param_53 = vec2(0.0);
    vec2 param_54 = vec2(0.0);
    ivec2 param_55 = ivec2(0);
    int param_56 = 0;
    float ycov_1_ = 0.0;
    float ywgt_1_ = 0.0;
    bool _S103_ = false;
    ivec4 _S104_ = ivec4(0);
    ivec2 param_57 = ivec2(0);
    uint param_58 = 0u;
    uvec2 vbd_0_ = uvec2(0u);
    ivec2 _S105_ = ivec2(0);
    ivec2 param_59 = ivec2(0);
    uint param_60 = 0u;
    int _S106_ = 0;
    ivec4 _S107_ = ivec4(0);
    ivec2 param_61 = ivec2(0);
    uint param_62 = 0u;
    uvec2 ref_7_ = uvec2(0u);
    uvec2 param_63 = uvec2(0u);
    int param_64 = 0;
    int param_65 = 0;
    bool _S108_ = false;
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
    int _e180 = bandMax_1_[1u];
    _S96_ = _e180;
    float _e182 = rc_2_[1u];
    param_31 = _e182;
    float _e184 = epp_0_[1u];
    param_32 = _e184;
    float _e186 = banding_0_[1u];
    param_33 = _e186;
    float _e188 = banding_0_[3u];
    param_34 = _e188;
    int _e189 = _S96_;
    param_35 = _e189;
    CoverageBandSpan_0_ _e190 = computeCoverageBandSpan_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_i1_u003b(param_31, param_32, param_33, param_34, param_35);
    hSpan_0_ = _e190;
    float _e192 = rc_2_[0u];
    param_36 = _e192;
    float _e194 = epp_0_[0u];
    param_37 = _e194;
    float _e196 = banding_0_[0u];
    param_38 = _e196;
    float _e198 = banding_0_[2u];
    param_39 = _e198;
    int _e200 = bandMax_1_[0u];
    param_40 = _e200;
    CoverageBandSpan_0_ _e201 = computeCoverageBandSpan_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_i1_u003b(param_36, param_37, param_38, param_39, param_40);
    vSpan_0_ = _e201;
    xcov_1_ = 0.0;
    xwgt_1_ = 0.0;
    int _e203 = hSpan_0_.first_0_;
    int _e205 = hSpan_0_.last_0_;
    _S97_ = (_e203 != _e205);
    int _e208 = hSpan_0_.first_0_;
    band_1_ = _e208;
    while(true) {
        int _e209 = band_1_;
        int _e211 = hSpan_0_.last_0_;
        if ((_e209 <= _e211)) {
        } else {
            break;
        }
        int _e213 = band_1_;
        ivec2 _e215 = gLoc_0_;
        param_41 = _e215;
        param_42 = uint(_e213);
        ivec2 _e216 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_41, param_42);
        int _e217 = texLayer_2_;
        _S98_ = ivec4(_e216.x, _e216.y, _e217, 0);
        ivec4 _e221 = _S98_;
        ivec3 _e222 = _e221.xyz;
        int _e224 = _S98_[3u];
        uvec4 _e230 = texelFetch(band_tex_0_, ivec3(ivec2(_e222.x, _e222.y), int(_e222.z)), _e224);
        hbd_0_ = _e230.xy;
        ivec2 _e232 = gLoc_0_;
        param_43 = _e232;
        uint _e234 = hbd_0_[1u];
        param_44 = _e234;
        ivec2 _e235 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_43, param_44);
        _S99_ = _e235;
        uint _e237 = hbd_0_[0u];
        _S100_ = int(_e237);
        i_6_ = 0;
        while(true) {
            int _e239 = i_6_;
            int _e240 = _S100_;
            if ((_e239 < _e240)) {
            } else {
                break;
            }
            int _e242 = i_6_;
            ivec2 _e244 = _S99_;
            param_45 = _e244;
            param_46 = uint(_e242);
            ivec2 _e245 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_45, param_46);
            int _e246 = texLayer_2_;
            _S101_ = ivec4(_e245.x, _e245.y, _e246, 0);
            ivec4 _e250 = _S101_;
            ivec3 _e251 = _e250.xyz;
            int _e253 = _S101_[3u];
            uvec4 _e259 = texelFetch(band_tex_0_, ivec3(ivec2(_e251.x, _e251.y), int(_e251.z)), _e253);
            ref_6_ = _e259.xy;
            bool _e261 = _S97_;
            if (_e261) {
                uvec2 _e262 = ref_6_;
                param_47 = _e262;
                int _e263 = band_1_;
                param_48 = _e263;
                int _e265 = hSpan_0_.first_0_;
                param_49 = _e265;
                bool _e266 = isCoverageBandSpanOwner_0_u0028_vu2_u003b_i1_u003b_i1_u003b(param_47, param_48, param_49);
                _S95_ = !(_e266);
            } else {
                _S95_ = false;
            }
            bool _e268 = _S95_;
            if (_e268) {
                int _e269 = i_6_;
                i_6_ = (_e269 + 1);
                continue;
            }
            uvec2 _e271 = ref_6_;
            param_50 = _e271;
            ivec2 _e272 = decodeBandCurveLoc_0_u0028_vu2_u003b(param_50);
            float _e273 = xcov_1_;
            param_51 = _e273;
            float _e274 = xwgt_1_;
            param_52 = _e274;
            vec2 _e275 = rc_2_;
            param_53 = _e275;
            vec2 _e276 = ppe_2_;
            param_54 = _e276;
            param_55 = _e272;
            int _e277 = texLayer_2_;
            param_56 = _e277;
            bool _e278 = accumulateHorizContribution_0_u0028_f1_u003b_f1_u003b_vf2_u003b_vf2_u003b_vi2_u003b_i1_u003b_tA21_u003b(param_51, param_52, param_53, param_54, param_55, param_56, curve_tex_2_);
            float _e279 = param_51;
            xcov_1_ = _e279;
            float _e280 = param_52;
            xwgt_1_ = _e280;
            _S102_ = _e278;
            bool _e281 = _S102_;
            if (!(_e281)) {
                break;
            }
            int _e283 = i_6_;
            i_6_ = (_e283 + 1);
            continue;
        }
        int _e285 = band_1_;
        band_1_ = (_e285 + 1);
        continue;
    }
    ycov_1_ = 0.0;
    ywgt_1_ = 0.0;
    int _e288 = vSpan_0_.first_0_;
    int _e290 = vSpan_0_.last_0_;
    _S103_ = (_e288 != _e290);
    int _e293 = vSpan_0_.first_0_;
    band_1_ = _e293;
    while(true) {
        int _e294 = band_1_;
        int _e296 = vSpan_0_.last_0_;
        if ((_e294 <= _e296)) {
        } else {
            break;
        }
        int _e298 = _S96_;
        int _e300 = band_1_;
        ivec2 _e303 = gLoc_0_;
        param_57 = _e303;
        param_58 = uint(((_e298 + 1) + _e300));
        ivec2 _e304 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_57, param_58);
        int _e305 = texLayer_2_;
        _S104_ = ivec4(_e304.x, _e304.y, _e305, 0);
        ivec4 _e309 = _S104_;
        ivec3 _e310 = _e309.xyz;
        int _e312 = _S104_[3u];
        uvec4 _e318 = texelFetch(band_tex_0_, ivec3(ivec2(_e310.x, _e310.y), int(_e310.z)), _e312);
        vbd_0_ = _e318.xy;
        ivec2 _e320 = gLoc_0_;
        param_59 = _e320;
        uint _e322 = vbd_0_[1u];
        param_60 = _e322;
        ivec2 _e323 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_59, param_60);
        _S105_ = _e323;
        uint _e325 = vbd_0_[0u];
        _S106_ = int(_e325);
        i_6_ = 0;
        while(true) {
            int _e327 = i_6_;
            int _e328 = _S106_;
            if ((_e327 < _e328)) {
            } else {
                break;
            }
            int _e330 = i_6_;
            ivec2 _e332 = _S105_;
            param_61 = _e332;
            param_62 = uint(_e330);
            ivec2 _e333 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_61, param_62);
            int _e334 = texLayer_2_;
            _S107_ = ivec4(_e333.x, _e333.y, _e334, 0);
            ivec4 _e338 = _S107_;
            ivec3 _e339 = _e338.xyz;
            int _e341 = _S107_[3u];
            uvec4 _e347 = texelFetch(band_tex_0_, ivec3(ivec2(_e339.x, _e339.y), int(_e339.z)), _e341);
            ref_7_ = _e347.xy;
            bool _e349 = _S103_;
            if (_e349) {
                uvec2 _e350 = ref_7_;
                param_63 = _e350;
                int _e351 = band_1_;
                param_64 = _e351;
                int _e353 = vSpan_0_.first_0_;
                param_65 = _e353;
                bool _e354 = isCoverageBandSpanOwner_0_u0028_vu2_u003b_i1_u003b_i1_u003b(param_63, param_64, param_65);
                _S95_ = !(_e354);
            } else {
                _S95_ = false;
            }
            bool _e356 = _S95_;
            if (_e356) {
                int _e357 = i_6_;
                i_6_ = (_e357 + 1);
                continue;
            }
            uvec2 _e359 = ref_7_;
            param_66 = _e359;
            ivec2 _e360 = decodeBandCurveLoc_0_u0028_vu2_u003b(param_66);
            float _e361 = ycov_1_;
            param_67 = _e361;
            float _e362 = ywgt_1_;
            param_68 = _e362;
            vec2 _e363 = rc_2_;
            param_69 = _e363;
            vec2 _e364 = ppe_2_;
            param_70 = _e364;
            param_71 = _e360;
            int _e365 = texLayer_2_;
            param_72 = _e365;
            bool _e366 = accumulateVertContribution_0_u0028_f1_u003b_f1_u003b_vf2_u003b_vf2_u003b_vi2_u003b_i1_u003b_tA21_u003b(param_67, param_68, param_69, param_70, param_71, param_72, curve_tex_2_);
            float _e367 = param_67;
            ycov_1_ = _e367;
            float _e368 = param_68;
            ywgt_1_ = _e368;
            _S108_ = _e366;
            bool _e369 = _S108_;
            if (!(_e369)) {
                break;
            }
            int _e371 = i_6_;
            i_6_ = (_e371 + 1);
            continue;
        }
        int _e373 = band_1_;
        band_1_ = (_e373 + 1);
        continue;
    }
    float _e375 = xcov_1_;
    float _e376 = xwgt_1_;
    float _e378 = ycov_1_;
    float _e379 = ywgt_1_;
    float _e382 = xwgt_1_;
    float _e383 = ywgt_1_;
    param_73 = (((_e375 * _e376) + (_e378 * _e379)) / max((_e382 + _e383), 1.5258789e-5));
    param_74 = 0;
    float _e387 = applyFillRule_0_u0028_f1_u003b_i1_u003b(param_73, param_74);
    float _e388 = xcov_1_;
    param_75 = _e388;
    param_76 = 0;
    float _e389 = applyFillRule_0_u0028_f1_u003b_i1_u003b(param_75, param_76);
    float _e390 = ycov_1_;
    param_77 = _e390;
    param_78 = 0;
    float _e391 = applyFillRule_0_u0028_f1_u003b_i1_u003b(param_77, param_78);
    param_79 = max(_e387, min(_e389, _e391));
    float _e394 = coverage_exponent_2_;
    param_80 = _e394;
    float _e395 = applyCoverageTransfer_0_u0028_f1_u003b_f1_u003b(param_79, param_80);
    return _e395;
}

ivec2 snailAhLayerLoc_0_u0028_t21_u003b_vi2_u003b_i1_u003b(sampler2D layer_tex_0_, inout ivec2 base_0_, inout int offset_0_) {
    uint uw_0_ = 0u;
    int width_0_ = 0;
    int texel_0_ = 0;
    int _S1_ = 0;
    int _S2_ = 0;
    uw_0_ = uint(ivec2(uvec2(textureSize(layer_tex_0_, 0).xy)).x);
    uint _e105 = uw_0_;
    width_0_ = int(_e105);
    int _e108 = base_0_[1u];
    int _e109 = width_0_;
    int _e112 = base_0_[0u];
    int _e114 = offset_0_;
    texel_0_ = (((_e108 * _e109) + _e112) + _e114);
    int _e116 = texel_0_;
    int _e117 = width_0_;
    _S1_ = (_e116 - (int(floor((float(_e116) / float(_e117)))) * _e117));
    int _e125 = texel_0_;
    int _e126 = width_0_;
    _S2_ = (_e125 / _e126);
    int _e128 = _S1_;
    int _e129 = _S2_;
    return ivec2(_e128, _e129);
}

float snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(sampler2D layer_tex_1_, inout ivec2 info_base_0_, inout int block_0_, inout int i_0_) {
    int f_0_ = 0;
    ivec2 _S3_ = ivec2(0);
    ivec2 param_81 = ivec2(0);
    int param_82 = 0;
    ivec3 _S4_ = ivec3(0);
    vec4 t_0_ = vec4(0.0);
    int c_0_ = 0;
    float _S5_ = 0.0;
    int _e105 = block_0_;
    int _e106 = i_0_;
    f_0_ = (_e105 + _e106);
    int _e108 = f_0_;
    ivec2 _e111 = info_base_0_;
    param_81 = _e111;
    param_82 = (_e108 >> uint(2));
    ivec2 _e112 = snailAhLayerLoc_0_u0028_t21_u003b_vi2_u003b_i1_u003b(layer_tex_1_, param_81, param_82);
    _S3_ = _e112;
    ivec2 _e113 = _S3_;
    _S4_ = ivec3(_e113.x, _e113.y, 0);
    ivec3 _e117 = _S4_;
    int _e120 = _S4_[2u];
    vec4 _e121 = texelFetch(layer_tex_1_, _e117.xy, _e120);
    t_0_ = _e121;
    int _e122 = f_0_;
    c_0_ = (_e122 & 3);
    int _e124 = c_0_;
    if ((_e124 == 0)) {
        float _e127 = t_0_[0u];
        _S5_ = _e127;
    } else {
        int _e128 = c_0_;
        if ((_e128 == 1)) {
            float _e131 = t_0_[1u];
            _S5_ = _e131;
        } else {
            int _e132 = c_0_;
            if ((_e132 == 2)) {
                float _e135 = t_0_[2u];
                _S5_ = _e135;
            } else {
                float _e137 = t_0_[3u];
                _S5_ = _e137;
            }
        }
    }
    float _e138 = _S5_;
    return _e138;
}

uint snailAhFastSource_0_u0028_vu4_u003b_i1_u003b(inout uvec4 words_0_, inout int idx_0_) {
    int _e95 = idx_0_;
    uint _e99 = words_0_[(_e95 >> uint(2))];
    int _e100 = idx_0_;
    return ((_e99 >> uint(((_e100 & 3) * 8))) & 255u);
}

float snailAhFastBase_0_u0028_t21_u003b_vi2_u003b_i1_u003b_f1_u003b_vu4_u003b_i1_u003b(sampler2D layer_tex_3_, inout ivec2 info_base_2_, inout int run_1_, inout float left_1_, inout uvec4 sources_0_, inout int idx_2_) {
    uint source_0_ = 0u;
    uvec4 param_83 = uvec4(0u);
    int param_84 = 0;
    float _S44_ = 0.0;
    float _S45_ = 0.0;
    ivec2 param_85 = ivec2(0);
    int param_86 = 0;
    int param_87 = 0;
    uvec4 _e107 = sources_0_;
    param_83 = _e107;
    int _e108 = idx_2_;
    param_84 = _e108;
    uint _e109 = snailAhFastSource_0_u0028_vu4_u003b_i1_u003b(param_83, param_84);
    source_0_ = _e109;
    uint _e110 = source_0_;
    if ((_e110 == 32u)) {
        float _e112 = left_1_;
        _S44_ = _e112;
    } else {
        int _e113 = run_1_;
        uint _e115 = source_0_;
        ivec2 _e119 = info_base_2_;
        param_85 = _e119;
        param_86 = ((_e113 + 1) + (4 * int(_e115)));
        param_87 = 0;
        float _e120 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_3_, param_85, param_86, param_87);
        _S45_ = _e120;
        float _e121 = _S45_;
        _S44_ = _e121;
    }
    float _e122 = _S44_;
    return _e122;
}

float snailAhFastTarget_0_u0028_vf4_u005b_4_u005d_u003b_i1_u003b(inout vec4 values_0_[4], inout int idx_1_) {
    int _e95 = idx_1_;
    int _e98 = idx_1_;
    float _e102 = values_0_[(_e95 >> uint(2))][(_e98 & 3)];
    return _e102;
}

float snailInverseFastAxis_0_u0028_t21_u003b_vi2_u003b_i1_u003b_vf4_u005b_4_u005d_u003b_vu4_u003b_i1_u003b_f1_u003b_f1_u003b_f1_u003b(sampler2D layer_tex_4_, inout ivec2 info_base_3_, inout int count_4_, inout vec4 targets_2_[4], inout uvec4 sources_1_, inout int run_2_, inout float left_2_, inout float hinted_2_, inout float invSlope_1_) {
    float firstTarget_0_ = 0.0;
    vec4 param_88[4] = vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0));
    int param_89 = 0;
    float firstBase_0_ = 0.0;
    ivec2 param_90 = ivec2(0);
    int param_91 = 0;
    float param_92 = 0.0;
    uvec4 param_93 = uvec4(0u);
    int param_94 = 0;
    int _S46_ = 0;
    float lastTarget_0_ = 0.0;
    vec4 param_95[4] = vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0));
    int param_96 = 0;
    float lastBase_0_ = 0.0;
    ivec2 param_97 = ivec2(0);
    int param_98 = 0;
    float param_99 = 0.0;
    uvec4 param_100 = uvec4(0u);
    int param_101 = 0;
    int i_5_ = 0;
    int lo_1_ = 0;
    int _S47_ = 0;
    bool _S48_ = false;
    vec4 param_102[4] = vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0));
    int param_103 = 0;
    float loTarget_0_ = 0.0;
    vec4 param_104[4] = vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0));
    int param_105 = 0;
    int _S49_ = 0;
    float hiTarget_0_ = 0.0;
    vec4 param_106[4] = vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0));
    int param_107 = 0;
    float loBase_0_ = 0.0;
    ivec2 param_108 = ivec2(0);
    int param_109 = 0;
    float param_110 = 0.0;
    uvec4 param_111 = uvec4(0u);
    int param_112 = 0;
    float hiBase_0_ = 0.0;
    ivec2 param_113 = ivec2(0);
    int param_114 = 0;
    float param_115 = 0.0;
    uvec4 param_116 = uvec4(0u);
    int param_117 = 0;
    float dt_1_ = 0.0;
    float db_1_ = 0.0;
    float _S50_ = 0.0;
    invSlope_1_ = 1.0;
    int _e149 = count_4_;
    if ((_e149 == 0)) {
        float _e151 = hinted_2_;
        return _e151;
    }
    vec4 _e152[4] = targets_2_;
    param_88 = _e152;
    param_89 = 0;
    float _e153 = snailAhFastTarget_0_u0028_vf4_u005b_4_u005d_u003b_i1_u003b(param_88, param_89);
    firstTarget_0_ = _e153;
    ivec2 _e154 = info_base_3_;
    param_90 = _e154;
    int _e155 = run_2_;
    param_91 = _e155;
    float _e156 = left_2_;
    param_92 = _e156;
    uvec4 _e157 = sources_1_;
    param_93 = _e157;
    param_94 = 0;
    float _e158 = snailAhFastBase_0_u0028_t21_u003b_vi2_u003b_i1_u003b_f1_u003b_vu4_u003b_i1_u003b(layer_tex_4_, param_90, param_91, param_92, param_93, param_94);
    firstBase_0_ = _e158;
    float _e159 = hinted_2_;
    float _e160 = firstTarget_0_;
    if ((_e159 <= _e160)) {
        float _e162 = firstBase_0_;
        float _e163 = hinted_2_;
        float _e165 = firstTarget_0_;
        return ((_e162 + _e163) - _e165);
    }
    int _e167 = count_4_;
    _S46_ = (_e167 - 1);
    vec4 _e169[4] = targets_2_;
    param_95 = _e169;
    int _e170 = _S46_;
    param_96 = _e170;
    float _e171 = snailAhFastTarget_0_u0028_vf4_u005b_4_u005d_u003b_i1_u003b(param_95, param_96);
    lastTarget_0_ = _e171;
    ivec2 _e172 = info_base_3_;
    param_97 = _e172;
    int _e173 = run_2_;
    param_98 = _e173;
    float _e174 = left_2_;
    param_99 = _e174;
    uvec4 _e175 = sources_1_;
    param_100 = _e175;
    int _e176 = _S46_;
    param_101 = _e176;
    float _e177 = snailAhFastBase_0_u0028_t21_u003b_vi2_u003b_i1_u003b_f1_u003b_vu4_u003b_i1_u003b(layer_tex_4_, param_97, param_98, param_99, param_100, param_101);
    lastBase_0_ = _e177;
    float _e178 = hinted_2_;
    float _e179 = lastTarget_0_;
    if ((_e178 >= _e179)) {
        float _e181 = lastBase_0_;
        float _e182 = hinted_2_;
        float _e184 = lastTarget_0_;
        return ((_e181 + _e182) - _e184);
    }
    i_5_ = 0;
    while(true) {
        int _e186 = i_5_;
        if ((_e186 < 15)) {
        } else {
            lo_1_ = 0;
            break;
        }
        int _e188 = i_5_;
        _S47_ = (_e188 + 1);
        int _e190 = _S47_;
        int _e191 = count_4_;
        if ((_e190 >= _e191)) {
            _S48_ = true;
        } else {
            vec4 _e193[4] = targets_2_;
            param_102 = _e193;
            int _e194 = _S47_;
            param_103 = _e194;
            float _e195 = snailAhFastTarget_0_u0028_vf4_u005b_4_u005d_u003b_i1_u003b(param_102, param_103);
            float _e196 = hinted_2_;
            _S48_ = (_e195 >= _e196);
        }
        bool _e198 = _S48_;
        if (_e198) {
            int _e199 = i_5_;
            lo_1_ = _e199;
            break;
        }
        int _e200 = _S47_;
        i_5_ = _e200;
        continue;
    }
    vec4 _e201[4] = targets_2_;
    param_104 = _e201;
    int _e202 = lo_1_;
    param_105 = _e202;
    float _e203 = snailAhFastTarget_0_u0028_vf4_u005b_4_u005d_u003b_i1_u003b(param_104, param_105);
    loTarget_0_ = _e203;
    int _e204 = lo_1_;
    _S49_ = (_e204 + 1);
    vec4 _e206[4] = targets_2_;
    param_106 = _e206;
    int _e207 = _S49_;
    param_107 = _e207;
    float _e208 = snailAhFastTarget_0_u0028_vf4_u005b_4_u005d_u003b_i1_u003b(param_106, param_107);
    hiTarget_0_ = _e208;
    ivec2 _e209 = info_base_3_;
    param_108 = _e209;
    int _e210 = run_2_;
    param_109 = _e210;
    float _e211 = left_2_;
    param_110 = _e211;
    uvec4 _e212 = sources_1_;
    param_111 = _e212;
    int _e213 = lo_1_;
    param_112 = _e213;
    float _e214 = snailAhFastBase_0_u0028_t21_u003b_vi2_u003b_i1_u003b_f1_u003b_vu4_u003b_i1_u003b(layer_tex_4_, param_108, param_109, param_110, param_111, param_112);
    loBase_0_ = _e214;
    ivec2 _e215 = info_base_3_;
    param_113 = _e215;
    int _e216 = run_2_;
    param_114 = _e216;
    float _e217 = left_2_;
    param_115 = _e217;
    uvec4 _e218 = sources_1_;
    param_116 = _e218;
    int _e219 = _S49_;
    param_117 = _e219;
    float _e220 = snailAhFastBase_0_u0028_t21_u003b_vi2_u003b_i1_u003b_f1_u003b_vu4_u003b_i1_u003b(layer_tex_4_, param_113, param_114, param_115, param_116, param_117);
    hiBase_0_ = _e220;
    float _e221 = hiTarget_0_;
    float _e222 = loTarget_0_;
    dt_1_ = (_e221 - _e222);
    float _e224 = hiBase_0_;
    float _e225 = loBase_0_;
    db_1_ = (_e224 - _e225);
    float _e227 = dt_1_;
    if ((abs(_e227) > 1e-6)) {
        float _e230 = db_1_;
        float _e231 = dt_1_;
        _S50_ = (_e230 / _e231);
    } else {
        _S50_ = 1.0;
    }
    float _e233 = _S50_;
    invSlope_1_ = _e233;
    float _e234 = loBase_0_;
    float _e235 = hinted_2_;
    float _e236 = loTarget_0_;
    float _e238 = _S50_;
    return (_e234 + ((_e235 - _e236) * _e238));
}

float snailInverseWarpAxis_0_u0028_i1_u003b_f1_u005b_32_u005d_u003b_f1_u005b_32_u005d_u003b_f1_u003b_f1_u003b(inout int count_3_, inout float bases_0_[32], inout float targets_1_[32], inout float hinted_1_, inout float invSlope_0_) {
    int _S37_ = 0;
    int i_4_ = 0;
    int lo_0_ = 0;
    int _S38_ = 0;
    bool _S39_ = false;
    int _S40_ = 0;
    int _S41_ = 0;
    float dt_0_ = 0.0;
    int _S42_ = 0;
    float db_0_ = 0.0;
    float _S43_ = 0.0;
    invSlope_0_ = 1.0;
    int _e109 = count_3_;
    if ((_e109 == 0)) {
        float _e111 = hinted_1_;
        return _e111;
    }
    float _e112 = hinted_1_;
    float _e114 = targets_1_[0];
    if ((_e112 <= _e114)) {
        float _e117 = bases_0_[0];
        float _e118 = hinted_1_;
        float _e121 = targets_1_[0];
        return ((_e117 + _e118) - _e121);
    }
    int _e123 = count_3_;
    _S37_ = (_e123 - 1);
    float _e125 = hinted_1_;
    int _e126 = _S37_;
    float _e128 = targets_1_[_e126];
    if ((_e125 >= _e128)) {
        int _e130 = _S37_;
        float _e132 = bases_0_[_e130];
        float _e133 = hinted_1_;
        int _e135 = _S37_;
        float _e137 = targets_1_[_e135];
        return ((_e132 + _e133) - _e137);
    }
    i_4_ = 0;
    while(true) {
        int _e139 = i_4_;
        if ((_e139 < 31)) {
        } else {
            lo_0_ = 0;
            break;
        }
        int _e141 = i_4_;
        _S38_ = (_e141 + 1);
        int _e143 = _S38_;
        int _e144 = count_3_;
        if ((_e143 >= _e144)) {
            _S39_ = true;
        } else {
            int _e146 = _S38_;
            float _e148 = targets_1_[_e146];
            float _e149 = hinted_1_;
            _S39_ = (_e148 >= _e149);
        }
        bool _e151 = _S39_;
        if (_e151) {
            int _e152 = i_4_;
            lo_0_ = _e152;
            break;
        }
        int _e153 = _S38_;
        i_4_ = _e153;
        continue;
    }
    int _e154 = lo_0_;
    _S40_ = (_e154 + 1);
    int _e156 = lo_0_;
    _S41_ = _e156;
    int _e157 = _S40_;
    float _e159 = targets_1_[_e157];
    int _e160 = lo_0_;
    float _e162 = targets_1_[_e160];
    dt_0_ = (_e159 - _e162);
    int _e164 = lo_0_;
    _S42_ = _e164;
    int _e165 = _S40_;
    float _e167 = bases_0_[_e165];
    int _e168 = lo_0_;
    float _e170 = bases_0_[_e168];
    db_0_ = (_e167 - _e170);
    float _e172 = dt_0_;
    if ((abs(_e172) > 1e-6)) {
        float _e175 = db_0_;
        float _e176 = dt_0_;
        _S43_ = (_e175 / _e176);
    } else {
        _S43_ = 1.0;
    }
    float _e178 = _S43_;
    invSlope_0_ = _e178;
    int _e179 = _S42_;
    float _e181 = bases_0_[_e179];
    float _e182 = hinted_1_;
    int _e183 = _S41_;
    float _e185 = targets_1_[_e183];
    float _e187 = _S43_;
    return (_e181 + ((_e182 - _e185) * _e187));
}

float snailAhStandardWidth_0_u0028_f1_u003b_f1_u003b_f1_u003b(inout float raw_0_, inout float standard_0_, inout float ratio_0_) {
    bool _S10_ = false;
    float _S11_ = 0.0;
    float _e98 = standard_0_;
    if ((_e98 > 0.0)) {
        float _e100 = raw_0_;
        float _e101 = standard_0_;
        float _e104 = ratio_0_;
        float _e105 = standard_0_;
        _S10_ = (abs((_e100 - _e101)) <= (_e104 * _e105));
    } else {
        _S10_ = false;
    }
    bool _e108 = _S10_;
    if (_e108) {
        float _e109 = standard_0_;
        _S11_ = _e109;
    } else {
        float _e110 = raw_0_;
        _S11_ = _e110;
    }
    float _e111 = _S11_;
    return _e111;
}

float snailAhSnap_0_u0028_f1_u003b_f1_u003b(inout float v_1_, inout float scale_0_) {
    float _e95 = v_1_;
    float _e96 = scale_0_;
    float _e99 = scale_0_;
    return (roundEven((_e95 * _e96)) / _e99);
}

bool snailAhFinite_0_u0028_f1_u003b(inout float v_0_) {
    bool _S6_ = false;
    float _e95 = v_0_;
    if (!(isnan(_e95))) {
        float _e98 = v_0_;
        _S6_ = !(isinf(_e98));
    } else {
        _S6_ = false;
    }
    bool _e101 = _S6_;
    return _e101;
}

bool snailFitAutohintAxis_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b_i1_u003b_f1_u003b_f1_u003b_f1_u003b_struct_u002d_SnailAutohintPolicy_0_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f11_u003b_i1_u003b_f1_u005b_32_u005d_u003b_f1_u005b_32_u005d_u003b_i1_u005b_32_u005d_u003b(sampler2D layer_tex_2_, inout ivec2 info_base_1_, inout int axis_0_, inout int run_0_, inout int blueCount_0_, inout float standardWidth_0_, inout float left_0_, inout float scale_1_, inout SnailAutohintPolicy_0_ policy_0_, inout int knotCount_0_, inout float knotBase_0_[32], inout float knotTarget_0_[32], inout int knotSource_0_[32]) {
    int i_2_ = 0;
    float param_118 = 0.0;
    bool _S12_ = false;
    float param_119 = 0.0;
    bool _S13_ = false;
    float _S14_ = 0.0;
    ivec2 param_120 = ivec2(0);
    int param_121 = 0;
    int param_122 = 0;
    int n_0_ = 0;
    bool _S15_ = false;
    bool relative_0_ = false;
    float param_123 = 0.0;
    int f_1_ = 0;
    float _S17_ = 0.0;
    ivec2 param_124 = ivec2(0);
    int param_125 = 0;
    int param_126 = 0;
    float pos_0_[32] = float[32](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    float _S18_ = 0.0;
    ivec2 param_127 = ivec2(0);
    int param_128 = 0;
    int param_129 = 0;
    float width_1_[32] = float[32](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    float _S19_ = 0.0;
    ivec2 param_130 = ivec2(0);
    int param_131 = 0;
    int param_132 = 0;
    uint refs_0_ = 0u;
    int stem_0_[32] = int[32](0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    int blue_0_[32] = int[32](0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    float _S20_ = 0.0;
    ivec2 param_133 = ivec2(0);
    int param_134 = 0;
    int param_135 = 0;
    uint flags_0_ = 0u;
    bool rounded_0_[32] = bool[32](false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false);
    bool syntheticApex_0_[32] = bool[32](false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false);
    bool semanticsResolved_0_[32] = bool[32](false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false);
    bool blueDirNegative_0_[32] = bool[32](false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false);
    int gridCompanion_0_[32] = int[32](0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    int blueCompanion_0_[32] = int[32](0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    bool hinted_0_[32] = bool[32](false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false);
    float param_136 = 0.0;
    float param_137 = 0.0;
    bool anchorSet_0_ = false;
    bool bottomBlue_0_ = false;
    bool _S16_ = false;
    bool axisAligned_0_ = false;
    bool lowerBlue_0_ = false;
    int _S21_ = 0;
    float ref_0_ = 0.0;
    ivec2 param_138 = ivec2(0);
    int param_139 = 0;
    int param_140 = 0;
    float shoot_0_ = 0.0;
    ivec2 param_141 = ivec2(0);
    int param_142 = 0;
    int param_143 = 0;
    float param_144 = 0.0;
    float param_145 = 0.0;
    int j_0_ = 0;
    float param_146 = 0.0;
    float param_147 = 0.0;
    float spacing_0_ = 0.0;
    float _S24_ = 0.0;
    ivec2 param_148 = ivec2(0);
    int param_149 = 0;
    int param_150 = 0;
    float _S25_ = 0.0;
    ivec2 param_151 = ivec2(0);
    int param_152 = 0;
    int param_153 = 0;
    float maxPx_0_ = 0.0;
    int stemMode_0_ = 0;
    int clusterRight_0_ = 0;
    float gap_0_ = 0.0;
    float _S26_ = 0.0;
    ivec2 param_154 = ivec2(0);
    int param_155 = 0;
    int param_156 = 0;
    float _S27_ = 0.0;
    ivec2 param_157 = ivec2(0);
    int param_158 = 0;
    int param_159 = 0;
    int clusterStems_0_ = 0;
    bool upperBlue_0_ = false;
    bool _S23_ = false;
    int dir_0_[32] = int[32](0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    int b_0_ = 0;
    int companion_0_[32] = int[32](0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    float ref_1_ = 0.0;
    ivec2 param_160 = ivec2(0);
    int param_161 = 0;
    int param_162 = 0;
    float shoot_1_ = 0.0;
    ivec2 param_163 = ivec2(0);
    int param_164 = 0;
    int param_165 = 0;
    bool _S22_ = false;
    float targets_0_[32] = float[32](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    float param_166 = 0.0;
    float param_167 = 0.0;
    bool _S28_ = false;
    float param_168 = 0.0;
    float param_169 = 0.0;
    float grid_0_ = 0.0;
    float anchorTarget_0_ = 0.0;
    float anchorBase_0_ = 0.0;
    float clusterTarget_0_ = 0.0;
    float clusterBase_0_ = 0.0;
    float clusterDesiredRight_0_ = 0.0;
    int j_2_ = 0;
    int i_3_ = 0;
    float nominal_0_ = 0.0;
    float param_170 = 0.0;
    float param_171 = 0.0;
    float param_172 = 0.0;
    float _S29_ = 0.0;
    float bestGap_0_ = 0.0;
    float widthUnits_0_ = 0.0;
    float anchorBase_1_ = 0.0;
    float _S30_ = 0.0;
    float param_173 = 0.0;
    float param_174 = 0.0;
    float _S31_ = 0.0;
    int clusterStems_1_ = 0;
    float _S32_ = 0.0;
    float _S33_ = 0.0;
    float clusterTarget_1_ = 0.0;
    float clusterBase_1_ = 0.0;
    float clusterDesiredRight_1_ = 0.0;
    int j_1_ = 0;
    int i_3_1 = 0;
    float _S34_ = 0.0;
    bool top_0_ = false;
    int best_0_ = 0;
    bool knotBlueFixed_0_[32] = bool[32](false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false);
    bool knotNaturalSpacing_0_[32] = bool[32](false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false, false);
    int _S35_ = 0;
    float param_175 = 0.0;
    float param_176 = 0.0;
    int _S36_ = 0;
    float span_0_ = 0.0;
    float param_177 = 0.0;
    float param_178 = 0.0;
    knotCount_0_ = 0;
    i_2_ = 0;
    while(true) {
        int _e252 = i_2_;
        if ((_e252 < 32)) {
        } else {
            break;
        }
        int _e254 = i_2_;
        knotBase_0_[_e254] = 0.0;
        int _e256 = i_2_;
        knotTarget_0_[_e256] = 0.0;
        int _e258 = i_2_;
        knotSource_0_[_e258] = 0;
        int _e260 = i_2_;
        i_2_ = (_e260 + 1);
        continue;
    }
    float _e262 = scale_1_;
    param_118 = _e262;
    bool _e263 = snailAhFinite_0_u0028_f1_u003b(param_118);
    if (!(_e263)) {
        _S12_ = true;
    } else {
        float _e265 = scale_1_;
        _S12_ = (_e265 <= 0.0);
    }
    bool _e267 = _S12_;
    if (_e267) {
        _S12_ = true;
    } else {
        int _e268 = blueCount_0_;
        _S12_ = (_e268 < 0);
    }
    bool _e270 = _S12_;
    if (_e270) {
        _S12_ = true;
    } else {
        int _e271 = blueCount_0_;
        _S12_ = (_e271 > 32);
    }
    bool _e273 = _S12_;
    if (_e273) {
        _S12_ = true;
    } else {
        float _e274 = standardWidth_0_;
        param_119 = _e274;
        bool _e275 = snailAhFinite_0_u0028_f1_u003b(param_119);
        _S12_ = !(_e275);
    }
    bool _e277 = _S12_;
    if (_e277) {
        _S12_ = true;
    } else {
        float _e278 = standardWidth_0_;
        _S12_ = (_e278 < 0.0);
    }
    bool _e280 = _S12_;
    if (_e280) {
        return false;
    }
    int _e281 = axis_0_;
    _S13_ = (_e281 == 0);
    bool _e283 = _S13_;
    if (_e283) {
        int _e285 = policy_0_.xAlign_0_;
        _S12_ = (_e285 == 0);
    } else {
        _S12_ = false;
    }
    bool _e287 = _S12_;
    if (_e287) {
        int _e289 = policy_0_.xStem_0_;
        _S12_ = (_e289 == 0);
    } else {
        _S12_ = false;
    }
    bool _e291 = _S12_;
    if (_e291) {
        int _e293 = policy_0_.xPositioning_0_;
        _S12_ = (_e293 == 0);
    } else {
        _S12_ = false;
    }
    bool _e295 = _S12_;
    if (_e295) {
        int _e297 = policy_0_.xRegistration_0_;
        _S12_ = (_e297 == 0);
    } else {
        _S12_ = false;
    }
    bool _e299 = _S12_;
    if (_e299) {
        _S12_ = true;
    } else {
        int _e300 = axis_0_;
        if ((_e300 == 1)) {
            int _e303 = policy_0_.yAlign_0_;
            _S12_ = (_e303 == 0);
        } else {
            _S12_ = false;
        }
        bool _e305 = _S12_;
        if (_e305) {
            int _e307 = policy_0_.yStem_0_;
            _S12_ = (_e307 == 0);
        } else {
            _S12_ = false;
        }
        bool _e309 = _S12_;
        if (_e309) {
            int _e311 = policy_0_.yOvershoot_0_;
            _S12_ = (_e311 == 0);
        } else {
            _S12_ = false;
        }
    }
    bool _e313 = _S12_;
    if (_e313) {
        return true;
    }
    ivec2 _e314 = info_base_1_;
    param_120 = _e314;
    int _e315 = run_0_;
    param_121 = _e315;
    param_122 = 0;
    float _e316 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_120, param_121, param_122);
    _S14_ = _e316;
    float _e317 = _S14_;
    n_0_ = int(_e317);
    int _e319 = n_0_;
    if ((_e319 <= 0)) {
        _S12_ = true;
    } else {
        int _e321 = n_0_;
        _S12_ = (_e321 > 32);
    }
    bool _e323 = _S12_;
    if (_e323) {
        int _e324 = n_0_;
        return (_e324 == 0);
    }
    int _e326 = axis_0_;
    _S15_ = (_e326 == 1);
    bool _e328 = _S15_;
    if (_e328) {
        int _e330 = policy_0_.yAlign_0_;
        _S12_ = (_e330 == 2);
    } else {
        _S12_ = false;
    }
    bool _e332 = _S13_;
    if (_e332) {
        int _e334 = policy_0_.xRegistration_0_;
        relative_0_ = (_e334 == 1);
    } else {
        relative_0_ = false;
    }
    bool _e336 = relative_0_;
    if (_e336) {
        float _e337 = left_0_;
        param_123 = _e337;
        bool _e338 = snailAhFinite_0_u0028_f1_u003b(param_123);
        relative_0_ = !(_e338);
    } else {
        relative_0_ = false;
    }
    bool _e340 = relative_0_;
    if (_e340) {
        return false;
    }
    i_2_ = 0;
    while(true) {
        int _e341 = i_2_;
        if ((_e341 < 32)) {
        } else {
            break;
        }
        int _e343 = i_2_;
        int _e344 = n_0_;
        if ((_e343 >= _e344)) {
            break;
        }
        int _e346 = run_0_;
        int _e348 = i_2_;
        f_1_ = ((_e346 + 1) + (4 * _e348));
        ivec2 _e351 = info_base_1_;
        param_124 = _e351;
        int _e352 = f_1_;
        param_125 = _e352;
        param_126 = 0;
        float _e353 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_124, param_125, param_126);
        _S17_ = _e353;
        int _e354 = i_2_;
        float _e355 = _S17_;
        pos_0_[_e354] = _e355;
        ivec2 _e357 = info_base_1_;
        param_127 = _e357;
        int _e358 = f_1_;
        param_128 = _e358;
        param_129 = 1;
        float _e359 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_127, param_128, param_129);
        _S18_ = _e359;
        int _e360 = i_2_;
        float _e361 = _S18_;
        width_1_[_e360] = _e361;
        ivec2 _e363 = info_base_1_;
        param_130 = _e363;
        int _e364 = f_1_;
        param_131 = _e364;
        param_132 = 2;
        float _e365 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_130, param_131, param_132);
        _S19_ = _e365;
        float _e366 = _S19_;
        refs_0_ = floatBitsToUint(_e366);
        int _e368 = i_2_;
        uint _e369 = refs_0_;
        stem_0_[_e368] = (int((_e369 << 16u)) >> uint(16));
        int _e376 = i_2_;
        uint _e377 = refs_0_;
        blue_0_[_e376] = (int(_e377) >> uint(16));
        ivec2 _e382 = info_base_1_;
        param_133 = _e382;
        int _e383 = f_1_;
        param_134 = _e383;
        param_135 = 3;
        float _e384 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_133, param_134, param_135);
        _S20_ = _e384;
        float _e385 = _S20_;
        flags_0_ = floatBitsToUint(_e385);
        int _e387 = i_2_;
        uint _e388 = flags_0_;
        rounded_0_[_e387] = ((_e388 & 1u) != 0u);
        int _e392 = i_2_;
        uint _e393 = flags_0_;
        syntheticApex_0_[_e392] = ((_e393 & 2u) != 0u);
        int _e397 = i_2_;
        uint _e398 = flags_0_;
        semanticsResolved_0_[_e397] = ((_e398 & 4u) != 0u);
        int _e402 = i_2_;
        uint _e403 = flags_0_;
        blueDirNegative_0_[_e402] = ((_e403 & 8u) != 0u);
        int _e407 = i_2_;
        uint _e408 = flags_0_;
        gridCompanion_0_[_e407] = int(((_e408 >> 4u) & 63u));
        int _e414 = i_2_;
        uint _e415 = flags_0_;
        blueCompanion_0_[_e414] = int(((_e415 >> 10u) & 63u));
        int _e421 = i_2_;
        hinted_0_[_e421] = false;
        int _e423 = i_2_;
        float _e425 = pos_0_[_e423];
        param_136 = _e425;
        bool _e426 = snailAhFinite_0_u0028_f1_u003b(param_136);
        if (!(_e426)) {
            relative_0_ = true;
        } else {
            int _e428 = i_2_;
            float _e430 = width_1_[_e428];
            param_137 = _e430;
            bool _e431 = snailAhFinite_0_u0028_f1_u003b(param_137);
            relative_0_ = !(_e431);
        }
        bool _e433 = relative_0_;
        if (_e433) {
            anchorSet_0_ = true;
        } else {
            int _e434 = i_2_;
            float _e436 = width_1_[_e434];
            anchorSet_0_ = (_e436 < 0.0);
        }
        bool _e438 = anchorSet_0_;
        if (_e438) {
            bottomBlue_0_ = true;
        } else {
            int _e439 = i_2_;
            int _e441 = stem_0_[_e439];
            bottomBlue_0_ = (_e441 < -1);
        }
        bool _e443 = bottomBlue_0_;
        if (_e443) {
            _S16_ = true;
        } else {
            int _e444 = i_2_;
            int _e446 = stem_0_[_e444];
            int _e447 = n_0_;
            _S16_ = (_e446 >= _e447);
        }
        bool _e449 = _S16_;
        if (_e449) {
            axisAligned_0_ = true;
        } else {
            int _e450 = i_2_;
            int _e452 = blue_0_[_e450];
            axisAligned_0_ = (_e452 < -1);
        }
        bool _e454 = axisAligned_0_;
        if (_e454) {
            lowerBlue_0_ = true;
        } else {
            int _e455 = i_2_;
            int _e457 = blue_0_[_e455];
            int _e458 = blueCount_0_;
            lowerBlue_0_ = (_e457 >= _e458);
        }
        bool _e460 = lowerBlue_0_;
        if (_e460) {
            return false;
        }
        int _e461 = i_2_;
        i_2_ = (_e461 + 1);
        continue;
    }
    i_2_ = 0;
    while(true) {
        int _e463 = i_2_;
        if ((_e463 < 32)) {
        } else {
            break;
        }
        int _e465 = i_2_;
        int _e466 = blueCount_0_;
        if ((_e465 >= _e466)) {
            break;
        }
        int _e468 = i_2_;
        _S21_ = (2 * _e468);
        ivec2 _e470 = info_base_1_;
        param_138 = _e470;
        param_139 = 12;
        int _e471 = _S21_;
        param_140 = _e471;
        float _e472 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_138, param_139, param_140);
        ref_0_ = _e472;
        int _e473 = _S21_;
        ivec2 _e475 = info_base_1_;
        param_141 = _e475;
        param_142 = 12;
        param_143 = (_e473 + 1);
        float _e476 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_141, param_142, param_143);
        shoot_0_ = _e476;
        float _e477 = ref_0_;
        param_144 = _e477;
        bool _e478 = snailAhFinite_0_u0028_f1_u003b(param_144);
        if (!(_e478)) {
            relative_0_ = true;
        } else {
            float _e480 = shoot_0_;
            param_145 = _e480;
            bool _e481 = snailAhFinite_0_u0028_f1_u003b(param_145);
            relative_0_ = !(_e481);
        }
        bool _e483 = relative_0_;
        if (_e483) {
            return false;
        }
        int _e484 = i_2_;
        i_2_ = (_e484 + 1);
        continue;
    }
    i_2_ = 0;
    while(true) {
        int _e486 = i_2_;
        if ((_e486 < 32)) {
        } else {
            break;
        }
        int _e488 = i_2_;
        int _e489 = n_0_;
        if ((_e488 >= _e489)) {
            break;
        }
        int _e491 = i_2_;
        int _e493 = stem_0_[_e491];
        if ((_e493 >= 0)) {
            int _e495 = i_2_;
            int _e497 = stem_0_[_e495];
            j_0_ = _e497;
            int _e498 = i_2_;
            int _e500 = stem_0_[_e498];
            int _e501 = n_0_;
            if ((_e500 >= _e501)) {
                relative_0_ = true;
            } else {
                int _e503 = j_0_;
                int _e504 = i_2_;
                relative_0_ = (_e503 == _e504);
            }
            bool _e506 = relative_0_;
            if (_e506) {
                anchorSet_0_ = true;
            } else {
                int _e507 = j_0_;
                int _e509 = stem_0_[_e507];
                int _e510 = i_2_;
                anchorSet_0_ = (_e509 != _e510);
            }
            bool _e512 = anchorSet_0_;
            if (_e512) {
                bottomBlue_0_ = true;
            } else {
                int _e513 = j_0_;
                float _e515 = pos_0_[_e513];
                param_146 = _e515;
                bool _e516 = snailAhFinite_0_u0028_f1_u003b(param_146);
                bottomBlue_0_ = !(_e516);
            }
            bool _e518 = bottomBlue_0_;
            if (_e518) {
                _S16_ = true;
            } else {
                int _e519 = j_0_;
                float _e521 = pos_0_[_e519];
                int _e522 = i_2_;
                float _e524 = pos_0_[_e522];
                _S16_ = (_e521 == _e524);
            }
            bool _e526 = _S16_;
            if (_e526) {
                axisAligned_0_ = true;
            } else {
                int _e527 = j_0_;
                float _e529 = width_1_[_e527];
                param_147 = _e529;
                bool _e530 = snailAhFinite_0_u0028_f1_u003b(param_147);
                axisAligned_0_ = !(_e530);
            }
            bool _e532 = axisAligned_0_;
            if (_e532) {
                lowerBlue_0_ = true;
            } else {
                int _e533 = j_0_;
                float _e535 = width_1_[_e533];
                int _e536 = i_2_;
                float _e538 = width_1_[_e536];
                lowerBlue_0_ = (_e535 != _e538);
            }
            bool _e540 = lowerBlue_0_;
            if (_e540) {
                return false;
            }
        }
        int _e541 = i_2_;
        i_2_ = (_e541 + 1);
        continue;
    }
    bool _e543 = _S15_;
    if (_e543) {
        int _e545 = policy_0_.yOvershoot_0_;
        relative_0_ = (_e545 == 1);
    } else {
        relative_0_ = false;
    }
    bool _e547 = relative_0_;
    if (_e547) {
        float _e549 = policy_0_.overshootMinPx_0_;
        spacing_0_ = _e549;
    } else {
        spacing_0_ = 0.0;
    }
    i_2_ = 0;
    while(true) {
        int _e550 = i_2_;
        if ((_e550 < 32)) {
        } else {
            break;
        }
        int _e552 = i_2_;
        int _e553 = n_0_;
        if ((_e552 >= _e553)) {
            break;
        }
        int _e555 = i_2_;
        int _e557 = stem_0_[_e555];
        if ((_e557 >= 0)) {
            int _e559 = i_2_;
            int _e561 = stem_0_[_e559];
            float _e563 = pos_0_[_e561];
            int _e564 = i_2_;
            float _e566 = pos_0_[_e564];
            relative_0_ = (_e563 > _e566);
        } else {
            relative_0_ = false;
        }
        bool _e568 = _S12_;
        if (_e568) {
            int _e569 = i_2_;
            int _e571 = blue_0_[_e569];
            anchorSet_0_ = (_e571 >= 0);
        } else {
            anchorSet_0_ = false;
        }
        bool _e573 = anchorSet_0_;
        if (_e573) {
            int _e574 = i_2_;
            int _e576 = blue_0_[_e574];
            ivec2 _e579 = info_base_1_;
            param_148 = _e579;
            param_149 = 12;
            param_150 = ((2 * _e576) + 1);
            float _e580 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_148, param_149, param_150);
            _S24_ = _e580;
            int _e581 = i_2_;
            int _e583 = blue_0_[_e581];
            ivec2 _e585 = info_base_1_;
            param_151 = _e585;
            param_152 = 12;
            param_153 = (2 * _e583);
            float _e586 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_151, param_152, param_153);
            _S25_ = _e586;
            float _e587 = _S24_;
            float _e588 = _S25_;
            bottomBlue_0_ = (_e587 < _e588);
        } else {
            bottomBlue_0_ = false;
        }
        int _e590 = i_2_;
        bool _e592 = semanticsResolved_0_[_e590];
        if (!(_e592)) {
            int _e594 = i_2_;
            int _e596 = stem_0_[_e594];
            _S16_ = (_e596 < 0);
        } else {
            _S16_ = false;
        }
        bool _e598 = _S16_;
        if (_e598) {
            bool _e599 = anchorSet_0_;
            axisAligned_0_ = !(_e599);
        } else {
            axisAligned_0_ = false;
        }
        bool _e601 = axisAligned_0_;
        if (_e601) {
            bool _e602 = _S12_;
            lowerBlue_0_ = _e602;
        } else {
            lowerBlue_0_ = false;
        }
        bool _e603 = lowerBlue_0_;
        if (_e603) {
            maxPx_0_ = 3.4028235e38;
            stemMode_0_ = 1;
            clusterRight_0_ = 0;
            while(true) {
                int _e604 = clusterRight_0_;
                if ((_e604 < 32)) {
                } else {
                    break;
                }
                int _e606 = clusterRight_0_;
                int _e607 = n_0_;
                if ((_e606 >= _e607)) {
                    break;
                }
                int _e609 = clusterRight_0_;
                int _e611 = blue_0_[_e609];
                if ((_e611 < 0)) {
                    int _e613 = clusterRight_0_;
                    clusterRight_0_ = (_e613 + 1);
                    continue;
                }
                int _e615 = clusterRight_0_;
                float _e617 = pos_0_[_e615];
                int _e618 = i_2_;
                float _e620 = pos_0_[_e618];
                gap_0_ = abs((_e617 - _e620));
                float _e623 = gap_0_;
                float _e624 = maxPx_0_;
                if ((_e623 >= _e624)) {
                    int _e626 = clusterRight_0_;
                    clusterRight_0_ = (_e626 + 1);
                    continue;
                }
                int _e628 = clusterRight_0_;
                int _e630 = blue_0_[_e628];
                ivec2 _e633 = info_base_1_;
                param_154 = _e633;
                param_155 = 12;
                param_156 = ((2 * _e630) + 1);
                float _e634 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_154, param_155, param_156);
                _S26_ = _e634;
                int _e635 = clusterRight_0_;
                int _e637 = blue_0_[_e635];
                ivec2 _e639 = info_base_1_;
                param_157 = _e639;
                param_158 = 12;
                param_159 = (2 * _e637);
                float _e640 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_157, param_158, param_159);
                _S27_ = _e640;
                float _e641 = _S26_;
                float _e642 = _S27_;
                if ((_e641 < _e642)) {
                    clusterStems_0_ = 1;
                } else {
                    clusterStems_0_ = -1;
                }
                float _e644 = gap_0_;
                maxPx_0_ = _e644;
                int _e645 = clusterStems_0_;
                stemMode_0_ = _e645;
                int _e646 = clusterRight_0_;
                clusterRight_0_ = (_e646 + 1);
                continue;
            }
        } else {
            stemMode_0_ = 1;
        }
        int _e648 = i_2_;
        bool _e650 = semanticsResolved_0_[_e648];
        if (_e650) {
            bool _e651 = _S12_;
            if (_e651) {
                int _e652 = i_2_;
                bool _e654 = blueDirNegative_0_[_e652];
                upperBlue_0_ = _e654;
            } else {
                upperBlue_0_ = false;
            }
            bool _e655 = upperBlue_0_;
            if (_e655) {
                _S23_ = true;
            } else {
                bool _e656 = _S12_;
                if (!(_e656)) {
                    bool _e658 = relative_0_;
                    _S23_ = _e658;
                } else {
                    _S23_ = false;
                }
            }
            bool _e659 = _S23_;
            if (_e659) {
                clusterRight_0_ = -1;
            } else {
                clusterRight_0_ = 1;
            }
        } else {
            bool _e660 = relative_0_;
            if (_e660) {
                upperBlue_0_ = true;
            } else {
                bool _e661 = bottomBlue_0_;
                upperBlue_0_ = _e661;
            }
            bool _e662 = upperBlue_0_;
            if (_e662) {
                clusterRight_0_ = -1;
            } else {
                int _e663 = stemMode_0_;
                clusterRight_0_ = _e663;
            }
        }
        int _e664 = i_2_;
        int _e665 = clusterRight_0_;
        dir_0_[_e664] = _e665;
        bool _e667 = _S12_;
        if (_e667) {
            int _e668 = i_2_;
            int _e670 = blueCompanion_0_[_e668];
            clusterStems_0_ = _e670;
        } else {
            int _e671 = i_2_;
            int _e673 = gridCompanion_0_[_e671];
            clusterStems_0_ = _e673;
        }
        int _e674 = i_2_;
        bool _e676 = semanticsResolved_0_[_e674];
        if (!(_e676)) {
            upperBlue_0_ = true;
        } else {
            int _e678 = clusterStems_0_;
            upperBlue_0_ = (_e678 == 63);
        }
        bool _e680 = upperBlue_0_;
        if (_e680) {
            b_0_ = -2;
        } else {
            int _e681 = clusterStems_0_;
            if ((_e681 == 62)) {
                b_0_ = -1;
            } else {
                int _e683 = clusterStems_0_;
                b_0_ = _e683;
            }
        }
        int _e684 = i_2_;
        int _e685 = b_0_;
        companion_0_[_e684] = _e685;
        bool _e687 = anchorSet_0_;
        if (_e687) {
            int _e688 = i_2_;
            int _e690 = blue_0_[_e688];
            ivec2 _e692 = info_base_1_;
            param_160 = _e692;
            param_161 = 12;
            param_162 = (2 * _e690);
            float _e693 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_160, param_161, param_162);
            ref_1_ = _e693;
            int _e694 = i_2_;
            int _e696 = blue_0_[_e694];
            ivec2 _e699 = info_base_1_;
            param_163 = _e699;
            param_164 = 12;
            param_165 = ((2 * _e696) + 1);
            float _e700 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_2_, param_163, param_164, param_165);
            shoot_1_ = _e700;
            int _e701 = i_2_;
            bool _e703 = rounded_0_[_e701];
            if (_e703) {
                bool _e704 = _S15_;
                _S23_ = _e704;
            } else {
                _S23_ = false;
            }
            bool _e705 = _S23_;
            if (_e705) {
                int _e707 = policy_0_.yOvershoot_0_;
                _S22_ = (_e707 == 0);
            } else {
                _S22_ = false;
            }
            bool _e709 = _S22_;
            if (_e709) {
                int _e710 = i_2_;
                int _e711 = i_2_;
                float _e713 = pos_0_[_e711];
                targets_0_[_e710] = _e713;
            } else {
                int _e715 = i_2_;
                float _e716 = ref_1_;
                param_166 = _e716;
                float _e717 = scale_1_;
                param_167 = _e717;
                float _e718 = snailAhSnap_0_u0028_f1_u003b_f1_u003b(param_166, param_167);
                targets_0_[_e715] = _e718;
                int _e720 = i_2_;
                bool _e722 = rounded_0_[_e720];
                if (_e722) {
                    float _e723 = shoot_1_;
                    float _e724 = ref_1_;
                    float _e726 = scale_1_;
                    float _e729 = spacing_0_;
                    _S28_ = (abs(((_e723 - _e724) * _e726)) >= _e729);
                } else {
                    _S28_ = false;
                }
                bool _e731 = _S28_;
                if (_e731) {
                    int _e732 = i_2_;
                    int _e733 = i_2_;
                    float _e735 = targets_0_[_e733];
                    float _e736 = shoot_1_;
                    float _e737 = ref_1_;
                    targets_0_[_e732] = (_e735 + (_e736 - _e737));
                }
            }
        } else {
            int _e741 = i_2_;
            int _e742 = i_2_;
            float _e744 = pos_0_[_e742];
            param_168 = _e744;
            float _e745 = scale_1_;
            param_169 = _e745;
            float _e746 = snailAhSnap_0_u0028_f1_u003b_f1_u003b(param_168, param_169);
            targets_0_[_e741] = _e746;
        }
        int _e748 = i_2_;
        i_2_ = (_e748 + 1);
        continue;
    }
    float _e750 = scale_1_;
    grid_0_ = (1.0 / _e750);
    bool _e752 = _S13_;
    if (_e752) {
        int _e754 = policy_0_.xStem_0_;
        stemMode_0_ = _e754;
    } else {
        int _e756 = policy_0_.yStem_0_;
        stemMode_0_ = _e756;
    }
    bool _e757 = _S13_;
    if (_e757) {
        float _e759 = policy_0_.xRatio_0_;
        spacing_0_ = _e759;
    } else {
        float _e761 = policy_0_.yRatio_0_;
        spacing_0_ = _e761;
    }
    bool _e762 = _S13_;
    if (_e762) {
        float _e764 = policy_0_.xMaxPx_0_;
        maxPx_0_ = _e764;
    } else {
        float _e766 = policy_0_.yMaxPx_0_;
        maxPx_0_ = _e766;
    }
    bool _e767 = _S13_;
    if (_e767) {
        int _e769 = policy_0_.xAlign_0_;
        _S12_ = (_e769 == 1);
    } else {
        int _e772 = policy_0_.yAlign_0_;
        _S12_ = (_e772 != 0);
    }
    bool _e774 = _S13_;
    if (_e774) {
        int _e776 = policy_0_.xPositioning_0_;
        relative_0_ = (_e776 == 1);
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
        int _e778 = i_2_;
        if ((_e778 < 32)) {
        } else {
            break;
        }
        int _e780 = i_2_;
        int _e781 = n_0_;
        if ((_e780 >= _e781)) {
            break;
        }
        int _e783 = i_2_;
        int _e785 = stem_0_[_e783];
        j_2_ = _e785;
        int _e786 = i_2_;
        int _e788 = stem_0_[_e786];
        if ((_e788 < 0)) {
            bottomBlue_0_ = true;
        } else {
            int _e790 = j_2_;
            int _e791 = i_2_;
            bottomBlue_0_ = (_e790 <= _e791);
        }
        bool _e793 = bottomBlue_0_;
        if (_e793) {
            bool _e794 = anchorSet_0_;
            axisAligned_0_ = _e794;
            int _e795 = i_2_;
            i_3_ = (_e795 + 1);
            bool _e797 = axisAligned_0_;
            anchorSet_0_ = _e797;
            int _e798 = i_3_;
            i_2_ = _e798;
            continue;
        }
        int _e799 = i_2_;
        float _e801 = width_1_[_e799];
        param_170 = _e801;
        float _e802 = standardWidth_0_;
        param_171 = _e802;
        float _e803 = spacing_0_;
        param_172 = _e803;
        float _e804 = snailAhStandardWidth_0_u0028_f1_u003b_f1_u003b_f1_u003b(param_170, param_171, param_172);
        nominal_0_ = _e804;
        int _e805 = i_2_;
        float _e807 = width_1_[_e805];
        _S29_ = _e807;
        int _e808 = stemMode_0_;
        if ((_e808 == 2)) {
            _S16_ = true;
        } else {
            int _e810 = stemMode_0_;
            if ((_e810 == 1)) {
                float _e812 = nominal_0_;
                float _e813 = scale_1_;
                float _e815 = maxPx_0_;
                _S16_ = ((_e812 * _e813) < _e815);
            } else {
                _S16_ = false;
            }
        }
        bool _e817 = _S16_;
        if (_e817) {
            float _e818 = nominal_0_;
            float _e819 = scale_1_;
            float _e823 = grid_0_;
            bestGap_0_ = (max(roundEven((_e818 * _e819)), 1.0) * _e823);
        } else {
            float _e825 = _S29_;
            bestGap_0_ = _e825;
        }
        bool _e826 = relative_0_;
        if (_e826) {
            bool _e827 = anchorSet_0_;
            if (_e827) {
                int _e828 = i_2_;
                float _e829 = anchorTarget_0_;
                int _e830 = i_2_;
                float _e832 = pos_0_[_e830];
                float _e833 = anchorBase_0_;
                float _e835 = scale_1_;
                float _e838 = grid_0_;
                targets_0_[_e828] = (_e829 + (roundEven(((_e832 - _e833) * _e835)) * _e838));
                float _e842 = clusterTarget_0_;
                widthUnits_0_ = _e842;
                float _e843 = clusterBase_0_;
                anchorBase_1_ = _e843;
                bool _e844 = anchorSet_0_;
                axisAligned_0_ = _e844;
            } else {
                int _e845 = i_2_;
                float _e847 = pos_0_[_e845];
                param_173 = _e847;
                float _e848 = scale_1_;
                param_174 = _e848;
                float _e849 = snailAhSnap_0_u0028_f1_u003b_f1_u003b(param_173, param_174);
                _S30_ = _e849;
                int _e850 = i_2_;
                float _e851 = _S30_;
                targets_0_[_e850] = _e851;
                float _e853 = _S30_;
                widthUnits_0_ = _e853;
                int _e854 = i_2_;
                float _e856 = pos_0_[_e854];
                anchorBase_1_ = _e856;
                axisAligned_0_ = true;
            }
            int _e857 = j_2_;
            int _e858 = i_2_;
            float _e860 = targets_0_[_e858];
            float _e861 = bestGap_0_;
            targets_0_[_e857] = (_e860 + _e861);
            float _e864 = widthUnits_0_;
            int _e865 = i_2_;
            float _e867 = pos_0_[_e865];
            float _e868 = anchorBase_1_;
            float _e870 = scale_1_;
            float _e873 = grid_0_;
            float _e876 = bestGap_0_;
            _S31_ = ((_e864 + (roundEven(((_e867 - _e868) * _e870)) * _e873)) + _e876);
            int _e878 = clusterStems_0_;
            clusterStems_1_ = (_e878 + 1);
            float _e880 = widthUnits_0_;
            _S32_ = _e880;
            float _e881 = anchorBase_1_;
            _S33_ = _e881;
            int _e882 = i_2_;
            float _e884 = targets_0_[_e882];
            widthUnits_0_ = _e884;
            int _e885 = i_2_;
            float _e887 = pos_0_[_e885];
            anchorBase_1_ = _e887;
            float _e888 = _S32_;
            clusterTarget_1_ = _e888;
            float _e889 = _S33_;
            clusterBase_1_ = _e889;
            float _e890 = _S31_;
            clusterDesiredRight_1_ = _e890;
            int _e891 = j_2_;
            b_0_ = _e891;
            int _e892 = clusterStems_1_;
            j_1_ = _e892;
        } else {
            bool _e893 = _S13_;
            if (_e893) {
                int _e895 = policy_0_.xAlign_0_;
                axisAligned_0_ = (_e895 != 0);
            } else {
                int _e898 = policy_0_.yAlign_0_;
                axisAligned_0_ = (_e898 != 0);
            }
            bool _e900 = axisAligned_0_;
            if (_e900) {
                int _e901 = i_2_;
                int _e903 = blue_0_[_e901];
                lowerBlue_0_ = (_e903 >= 0);
            } else {
                lowerBlue_0_ = false;
            }
            bool _e905 = axisAligned_0_;
            if (_e905) {
                int _e906 = j_2_;
                int _e908 = blue_0_[_e906];
                upperBlue_0_ = (_e908 >= 0);
            } else {
                upperBlue_0_ = false;
            }
            bool _e910 = _S12_;
            if (!(_e910)) {
                int _e912 = i_2_;
                int _e913 = i_2_;
                float _e915 = pos_0_[_e913];
                targets_0_[_e912] = _e915;
            }
            bool _e917 = upperBlue_0_;
            if (_e917) {
                bool _e918 = lowerBlue_0_;
                _S23_ = !(_e918);
            } else {
                _S23_ = false;
            }
            bool _e920 = _S23_;
            if (_e920) {
                bool _e921 = _S12_;
                _S22_ = _e921;
            } else {
                _S22_ = false;
            }
            bool _e922 = _S22_;
            if (_e922) {
                int _e923 = i_2_;
                int _e924 = j_2_;
                float _e926 = targets_0_[_e924];
                float _e927 = bestGap_0_;
                targets_0_[_e923] = (_e926 - _e927);
            } else {
                int _e930 = j_2_;
                int _e931 = i_2_;
                float _e933 = targets_0_[_e931];
                float _e934 = bestGap_0_;
                targets_0_[_e930] = (_e933 + _e934);
            }
            bool _e937 = anchorSet_0_;
            axisAligned_0_ = _e937;
            float _e938 = anchorTarget_0_;
            widthUnits_0_ = _e938;
            float _e939 = anchorBase_0_;
            anchorBase_1_ = _e939;
            float _e940 = clusterTarget_0_;
            clusterTarget_1_ = _e940;
            float _e941 = clusterBase_0_;
            clusterBase_1_ = _e941;
            float _e942 = clusterDesiredRight_0_;
            clusterDesiredRight_1_ = _e942;
            int _e943 = clusterRight_0_;
            b_0_ = _e943;
            int _e944 = clusterStems_0_;
            j_1_ = _e944;
        }
        int _e945 = i_2_;
        hinted_0_[_e945] = true;
        int _e947 = j_2_;
        hinted_0_[_e947] = true;
        float _e949 = widthUnits_0_;
        anchorTarget_0_ = _e949;
        float _e950 = anchorBase_1_;
        anchorBase_0_ = _e950;
        float _e951 = clusterTarget_1_;
        clusterTarget_0_ = _e951;
        float _e952 = clusterBase_1_;
        clusterBase_0_ = _e952;
        float _e953 = clusterDesiredRight_1_;
        clusterDesiredRight_0_ = _e953;
        int _e954 = b_0_;
        clusterRight_0_ = _e954;
        int _e955 = j_1_;
        clusterStems_0_ = _e955;
        int _e956 = i_2_;
        i_3_1 = (_e956 + 1);
        bool _e958 = axisAligned_0_;
        anchorSet_0_ = _e958;
        int _e959 = i_3_1;
        i_2_ = _e959;
        continue;
    }
    bool _e960 = relative_0_;
    if (_e960) {
        int _e961 = clusterStems_0_;
        _S12_ = (_e961 > 1);
    } else {
        _S12_ = false;
    }
    bool _e963 = _S12_;
    if (_e963) {
        float _e964 = clusterDesiredRight_0_;
        int _e965 = clusterRight_0_;
        float _e967 = targets_0_[_e965];
        _S34_ = (_e964 - _e967);
        i_2_ = 0;
        while(true) {
            int _e969 = i_2_;
            if ((_e969 < 32)) {
            } else {
                break;
            }
            int _e971 = i_2_;
            int _e972 = n_0_;
            if ((_e971 >= _e972)) {
                break;
            }
            int _e974 = i_2_;
            bool _e976 = hinted_0_[_e974];
            if (_e976) {
                int _e977 = i_2_;
                int _e978 = i_2_;
                float _e980 = targets_0_[_e978];
                float _e981 = _S34_;
                targets_0_[_e977] = (_e980 + _e981);
            }
            int _e984 = i_2_;
            i_2_ = (_e984 + 1);
            continue;
        }
    }
    int _e986 = stemMode_0_;
    if ((_e986 == 1)) {
        float _e988 = maxPx_0_;
        spacing_0_ = _e988;
    } else {
        spacing_0_ = 1.6;
    }
    i_2_ = 0;
    while(true) {
        int _e989 = i_2_;
        if ((_e989 < 32)) {
        } else {
            break;
        }
        int _e991 = i_2_;
        int _e992 = n_0_;
        if ((_e991 >= _e992)) {
            break;
        }
        bool _e994 = _S13_;
        if (_e994) {
            int _e996 = policy_0_.xAlign_0_;
            axisAligned_0_ = (_e996 != 0);
        } else {
            int _e999 = policy_0_.yAlign_0_;
            axisAligned_0_ = (_e999 != 0);
        }
        bool _e1001 = axisAligned_0_;
        if (!(_e1001)) {
            _S12_ = true;
        } else {
            int _e1003 = i_2_;
            int _e1005 = blue_0_[_e1003];
            _S12_ = (_e1005 < 0);
        }
        bool _e1007 = _S12_;
        if (_e1007) {
            relative_0_ = true;
        } else {
            int _e1008 = i_2_;
            bool _e1010 = rounded_0_[_e1008];
            relative_0_ = !(_e1010);
        }
        bool _e1012 = relative_0_;
        if (_e1012) {
            anchorSet_0_ = true;
        } else {
            int _e1013 = i_2_;
            bool _e1015 = hinted_0_[_e1013];
            anchorSet_0_ = _e1015;
        }
        bool _e1016 = anchorSet_0_;
        if (_e1016) {
            int _e1017 = i_2_;
            i_2_ = (_e1017 + 1);
            continue;
        }
        int _e1019 = i_2_;
        int _e1021 = dir_0_[_e1019];
        top_0_ = (_e1021 > 0);
        int _e1023 = i_2_;
        int _e1025 = companion_0_[_e1023];
        best_0_ = _e1025;
        int _e1026 = i_2_;
        int _e1028 = companion_0_[_e1026];
        if ((_e1028 >= 0)) {
            bool _e1030 = top_0_;
            if (_e1030) {
                int _e1031 = i_2_;
                float _e1033 = pos_0_[_e1031];
                int _e1034 = best_0_;
                float _e1036 = pos_0_[_e1034];
                maxPx_0_ = (_e1033 - _e1036);
            } else {
                int _e1038 = best_0_;
                float _e1040 = pos_0_[_e1038];
                int _e1041 = i_2_;
                float _e1043 = pos_0_[_e1041];
                maxPx_0_ = (_e1040 - _e1043);
            }
            int _e1045 = best_0_;
            b_0_ = _e1045;
            float _e1046 = maxPx_0_;
            bestGap_0_ = _e1046;
        } else {
            int _e1047 = best_0_;
            if ((_e1047 == -2)) {
                bestGap_0_ = 3.4028235e38;
                int _e1049 = best_0_;
                b_0_ = _e1049;
                j_1_ = 0;
                while(true) {
                    int _e1050 = j_1_;
                    if ((_e1050 < 32)) {
                    } else {
                        break;
                    }
                    int _e1052 = j_1_;
                    int _e1053 = n_0_;
                    if ((_e1052 >= _e1053)) {
                        break;
                    }
                    int _e1055 = j_1_;
                    int _e1056 = i_2_;
                    if ((_e1055 == _e1056)) {
                        bottomBlue_0_ = true;
                    } else {
                        int _e1058 = j_1_;
                        int _e1060 = dir_0_[_e1058];
                        int _e1061 = i_2_;
                        int _e1063 = dir_0_[_e1061];
                        bottomBlue_0_ = (_e1060 == _e1063);
                    }
                    bool _e1065 = bottomBlue_0_;
                    if (_e1065) {
                        int _e1066 = j_1_;
                        j_1_ = (_e1066 + 1);
                        continue;
                    }
                    bool _e1068 = top_0_;
                    if (_e1068) {
                        int _e1069 = i_2_;
                        float _e1071 = pos_0_[_e1069];
                        int _e1072 = j_1_;
                        float _e1074 = pos_0_[_e1072];
                        widthUnits_0_ = (_e1071 - _e1074);
                    } else {
                        int _e1076 = j_1_;
                        float _e1078 = pos_0_[_e1076];
                        int _e1079 = i_2_;
                        float _e1081 = pos_0_[_e1079];
                        widthUnits_0_ = (_e1078 - _e1081);
                    }
                    float _e1083 = widthUnits_0_;
                    if ((_e1083 <= 0.0)) {
                        _S16_ = true;
                    } else {
                        float _e1085 = widthUnits_0_;
                        float _e1086 = bestGap_0_;
                        _S16_ = (_e1085 >= _e1086);
                    }
                    bool _e1088 = _S16_;
                    if (_e1088) {
                        int _e1089 = j_1_;
                        j_1_ = (_e1089 + 1);
                        continue;
                    }
                    float _e1091 = widthUnits_0_;
                    bestGap_0_ = _e1091;
                    int _e1092 = j_1_;
                    b_0_ = _e1092;
                    int _e1093 = j_1_;
                    j_1_ = (_e1093 + 1);
                    continue;
                }
            } else {
                int _e1095 = best_0_;
                b_0_ = _e1095;
                bestGap_0_ = 3.4028235e38;
            }
        }
        int _e1096 = b_0_;
        if ((_e1096 < 0)) {
            bottomBlue_0_ = true;
        } else {
            int _e1098 = b_0_;
            bool _e1100 = hinted_0_[_e1098];
            bottomBlue_0_ = _e1100;
        }
        bool _e1101 = bottomBlue_0_;
        if (_e1101) {
            _S16_ = true;
        } else {
            int _e1102 = b_0_;
            int _e1104 = blue_0_[_e1102];
            _S16_ = (_e1104 >= 0);
        }
        bool _e1106 = _S16_;
        if (_e1106) {
            lowerBlue_0_ = true;
        } else {
            float _e1107 = bestGap_0_;
            float _e1108 = scale_1_;
            float _e1110 = spacing_0_;
            lowerBlue_0_ = ((_e1107 * _e1108) >= _e1110);
        }
        bool _e1112 = lowerBlue_0_;
        if (_e1112) {
            int _e1113 = i_2_;
            i_2_ = (_e1113 + 1);
            continue;
        }
        int _e1115 = b_0_;
        bool _e1117 = syntheticApex_0_[_e1115];
        if (_e1117) {
            float _e1118 = bestGap_0_;
            widthUnits_0_ = _e1118;
        } else {
            float _e1119 = bestGap_0_;
            float _e1120 = scale_1_;
            float _e1124 = grid_0_;
            widthUnits_0_ = (max(roundEven((_e1119 * _e1120)), 1.0) * _e1124);
        }
        bool _e1126 = top_0_;
        if (_e1126) {
            int _e1127 = i_2_;
            float _e1129 = targets_0_[_e1127];
            float _e1130 = widthUnits_0_;
            maxPx_0_ = (_e1129 - _e1130);
        } else {
            int _e1132 = i_2_;
            float _e1134 = targets_0_[_e1132];
            float _e1135 = widthUnits_0_;
            maxPx_0_ = (_e1134 + _e1135);
        }
        int _e1137 = b_0_;
        float _e1138 = maxPx_0_;
        targets_0_[_e1137] = _e1138;
        int _e1140 = b_0_;
        hinted_0_[_e1140] = true;
        int _e1142 = i_2_;
        i_2_ = (_e1142 + 1);
        continue;
    }
    i_2_ = 0;
    while(true) {
        int _e1144 = i_2_;
        if ((_e1144 < 32)) {
        } else {
            break;
        }
        int _e1146 = i_2_;
        int _e1147 = n_0_;
        if ((_e1146 >= _e1147)) {
            break;
        }
        bool _e1149 = _S13_;
        if (_e1149) {
            int _e1151 = policy_0_.xAlign_0_;
            axisAligned_0_ = (_e1151 != 0);
        } else {
            int _e1154 = policy_0_.yAlign_0_;
            axisAligned_0_ = (_e1154 != 0);
        }
        int _e1156 = i_2_;
        bool _e1158 = hinted_0_[_e1156];
        if (!(_e1158)) {
            bool _e1160 = axisAligned_0_;
            if (_e1160) {
                int _e1161 = i_2_;
                int _e1163 = blue_0_[_e1161];
                _S12_ = (_e1163 >= 0);
            } else {
                _S12_ = false;
            }
            bool _e1165 = _S12_;
            _S12_ = !(_e1165);
        } else {
            _S12_ = false;
        }
        bool _e1167 = _S12_;
        if (_e1167) {
            int _e1168 = i_2_;
            i_2_ = (_e1168 + 1);
            continue;
        }
        int _e1170 = knotCount_0_;
        int _e1171 = i_2_;
        float _e1173 = pos_0_[_e1171];
        knotBase_0_[_e1170] = _e1173;
        int _e1175 = knotCount_0_;
        int _e1176 = i_2_;
        float _e1178 = targets_0_[_e1176];
        knotTarget_0_[_e1175] = _e1178;
        bool _e1180 = axisAligned_0_;
        if (_e1180) {
            int _e1181 = i_2_;
            int _e1183 = blue_0_[_e1181];
            relative_0_ = (_e1183 >= 0);
        } else {
            relative_0_ = false;
        }
        int _e1185 = knotCount_0_;
        bool _e1186 = relative_0_;
        knotBlueFixed_0_[_e1185] = _e1186;
        int _e1188 = knotCount_0_;
        int _e1189 = i_2_;
        bool _e1191 = syntheticApex_0_[_e1189];
        knotNaturalSpacing_0_[_e1188] = _e1191;
        int _e1193 = knotCount_0_;
        int _e1194 = i_2_;
        knotSource_0_[_e1193] = _e1194;
        int _e1196 = knotCount_0_;
        knotCount_0_ = (_e1196 + 1);
        int _e1198 = i_2_;
        i_2_ = (_e1198 + 1);
        continue;
    }
    bool _e1200 = _S13_;
    if (_e1200) {
        int _e1202 = policy_0_.xRegistration_0_;
        _S12_ = (_e1202 == 1);
    } else {
        _S12_ = false;
    }
    bool _e1204 = _S12_;
    if (_e1204) {
        int _e1205 = knotCount_0_;
        _S12_ = (_e1205 > 0);
    } else {
        _S12_ = false;
    }
    bool _e1207 = _S12_;
    if (_e1207) {
        int _e1208 = knotCount_0_;
        _S12_ = (_e1208 < 32);
    } else {
        _S12_ = false;
    }
    bool _e1210 = _S12_;
    if (_e1210) {
        float _e1211 = left_0_;
        float _e1213 = knotBase_0_[0];
        float _e1214 = grid_0_;
        _S12_ = (_e1211 < (_e1213 - (0.25 * _e1214)));
    } else {
        _S12_ = false;
    }
    bool _e1218 = _S12_;
    if (_e1218) {
        i_2_ = 31;
        while(true) {
            int _e1219 = i_2_;
            if ((_e1219 > 0)) {
            } else {
                break;
            }
            int _e1221 = i_2_;
            int _e1222 = knotCount_0_;
            if ((_e1221 <= _e1222)) {
                int _e1224 = i_2_;
                _S35_ = (_e1224 - 1);
                int _e1226 = i_2_;
                int _e1227 = _S35_;
                float _e1229 = knotBase_0_[_e1227];
                knotBase_0_[_e1226] = _e1229;
                int _e1231 = i_2_;
                int _e1232 = _S35_;
                float _e1234 = knotTarget_0_[_e1232];
                knotTarget_0_[_e1231] = _e1234;
                int _e1236 = i_2_;
                int _e1237 = _S35_;
                bool _e1239 = knotBlueFixed_0_[_e1237];
                knotBlueFixed_0_[_e1236] = _e1239;
                int _e1241 = i_2_;
                int _e1242 = _S35_;
                bool _e1244 = knotNaturalSpacing_0_[_e1242];
                knotNaturalSpacing_0_[_e1241] = _e1244;
                int _e1246 = i_2_;
                int _e1247 = _S35_;
                int _e1249 = knotSource_0_[_e1247];
                knotSource_0_[_e1246] = _e1249;
            }
            int _e1251 = i_2_;
            i_2_ = (_e1251 - 1);
            continue;
        }
        float _e1253 = left_0_;
        knotBase_0_[0] = _e1253;
        float _e1255 = left_0_;
        param_175 = _e1255;
        float _e1256 = scale_1_;
        param_176 = _e1256;
        float _e1257 = snailAhSnap_0_u0028_f1_u003b_f1_u003b(param_175, param_176);
        knotTarget_0_[0] = _e1257;
        knotBlueFixed_0_[0] = false;
        knotNaturalSpacing_0_[0] = false;
        knotSource_0_[0] = 32;
        int _e1262 = knotCount_0_;
        knotCount_0_ = (_e1262 + 1);
    }
    b_0_ = 31;
    while(true) {
        int _e1264 = b_0_;
        if ((_e1264 > 0)) {
        } else {
            break;
        }
        int _e1266 = b_0_;
        int _e1267 = knotCount_0_;
        if ((_e1266 >= _e1267)) {
            _S12_ = true;
        } else {
            int _e1269 = b_0_;
            bool _e1271 = knotBlueFixed_0_[_e1269];
            _S12_ = !(_e1271);
        }
        bool _e1273 = _S12_;
        if (_e1273) {
            int _e1274 = b_0_;
            b_0_ = (_e1274 - 1);
            continue;
        }
        j_1_ = 31;
        while(true) {
            int _e1276 = j_1_;
            if ((_e1276 > 0)) {
            } else {
                break;
            }
            int _e1278 = j_1_;
            int _e1279 = b_0_;
            if ((_e1278 > _e1279)) {
                int _e1281 = j_1_;
                j_1_ = (_e1281 - 1);
                continue;
            }
            int _e1283 = j_1_;
            _S36_ = (_e1283 - 1);
            int _e1285 = _S36_;
            bool _e1287 = knotBlueFixed_0_[_e1285];
            if (_e1287) {
                break;
            }
            int _e1288 = _S36_;
            bool _e1290 = knotNaturalSpacing_0_[_e1288];
            if (_e1290) {
                spacing_0_ = 1e-6;
            } else {
                float _e1291 = grid_0_;
                spacing_0_ = _e1291;
            }
            int _e1292 = _S36_;
            int _e1293 = _S36_;
            float _e1295 = knotTarget_0_[_e1293];
            int _e1296 = j_1_;
            float _e1298 = knotTarget_0_[_e1296];
            float _e1299 = spacing_0_;
            knotTarget_0_[_e1292] = min(_e1295, (_e1298 - _e1299));
            int _e1303 = j_1_;
            j_1_ = (_e1303 - 1);
            continue;
        }
        int _e1305 = b_0_;
        b_0_ = (_e1305 - 1);
        continue;
    }
    i_2_ = 1;
    while(true) {
        int _e1307 = i_2_;
        if ((_e1307 < 32)) {
        } else {
            break;
        }
        int _e1309 = i_2_;
        int _e1310 = knotCount_0_;
        if ((_e1309 >= _e1310)) {
            break;
        }
        int _e1312 = i_2_;
        float _e1314 = knotTarget_0_[_e1312];
        int _e1315 = i_2_;
        float _e1318 = knotTarget_0_[(_e1315 - 1)];
        if ((_e1314 <= _e1318)) {
            int _e1320 = i_2_;
            int _e1321 = i_2_;
            float _e1324 = knotTarget_0_[(_e1321 - 1)];
            float _e1325 = grid_0_;
            knotTarget_0_[_e1320] = (_e1324 + _e1325);
        }
        int _e1328 = i_2_;
        i_2_ = (_e1328 + 1);
        continue;
    }
    int _e1331 = policy_0_.fadeEnabled_0_;
    if ((_e1331 != 0)) {
        float _e1333 = scale_1_;
        float _e1335 = policy_0_.fadeStart_0_;
        _S12_ = (_e1333 > _e1335);
    } else {
        _S12_ = false;
    }
    bool _e1337 = _S12_;
    if (_e1337) {
        float _e1339 = policy_0_.fadeFull_0_;
        float _e1341 = policy_0_.fadeStart_0_;
        span_0_ = (_e1339 - _e1341);
        float _e1343 = span_0_;
        if ((_e1343 <= 0.0)) {
            _S12_ = true;
        } else {
            float _e1345 = scale_1_;
            float _e1347 = policy_0_.fadeFull_0_;
            _S12_ = (_e1345 >= _e1347);
        }
        bool _e1349 = _S12_;
        if (_e1349) {
            spacing_0_ = 1.0;
        } else {
            float _e1350 = scale_1_;
            float _e1352 = policy_0_.fadeStart_0_;
            float _e1354 = span_0_;
            spacing_0_ = ((_e1350 - _e1352) / _e1354);
        }
        i_2_ = 0;
        while(true) {
            int _e1356 = i_2_;
            if ((_e1356 < 32)) {
            } else {
                break;
            }
            int _e1358 = i_2_;
            int _e1359 = knotCount_0_;
            if ((_e1358 >= _e1359)) {
                break;
            }
            int _e1361 = i_2_;
            int _e1362 = i_2_;
            float _e1364 = knotTarget_0_[_e1362];
            int _e1365 = i_2_;
            float _e1367 = knotBase_0_[_e1365];
            int _e1368 = i_2_;
            float _e1370 = knotTarget_0_[_e1368];
            float _e1372 = spacing_0_;
            knotTarget_0_[_e1361] = (_e1364 + ((_e1367 - _e1370) * _e1372));
            int _e1376 = i_2_;
            i_2_ = (_e1376 + 1);
            continue;
        }
    }
    i_2_ = 0;
    while(true) {
        int _e1378 = i_2_;
        if ((_e1378 < 32)) {
        } else {
            break;
        }
        int _e1380 = i_2_;
        int _e1381 = knotCount_0_;
        if ((_e1380 >= _e1381)) {
            break;
        }
        int _e1383 = i_2_;
        float _e1385 = knotBase_0_[_e1383];
        param_177 = _e1385;
        bool _e1386 = snailAhFinite_0_u0028_f1_u003b(param_177);
        if (!(_e1386)) {
            _S12_ = true;
        } else {
            int _e1388 = i_2_;
            float _e1390 = knotTarget_0_[_e1388];
            param_178 = _e1390;
            bool _e1391 = snailAhFinite_0_u0028_f1_u003b(param_178);
            _S12_ = !(_e1391);
        }
        bool _e1393 = _S12_;
        if (_e1393) {
            knotCount_0_ = 0;
            return false;
        }
        int _e1394 = i_2_;
        i_2_ = (_e1394 + 1);
        continue;
    }
    return true;
}

bool snailDecodeAutohintPolicy_0_u0028_vu4_u003b_vu3_u003b_struct_u002d_SnailAutohintPolicy_0_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f11_u003b(inout uvec4 p0_0_, inout uvec3 p1_0_, inout SnailAutohintPolicy_0_ p_0_) {
    uint x_0_ = 0u;
    uint y_0_ = 0u;
    bool _S8_ = false;
    int _S9_ = 0;
    float param_179 = 0.0;
    float param_180 = 0.0;
    float param_181 = 0.0;
    float param_182 = 0.0;
    float param_183 = 0.0;
    p_0_.xAlign_0_ = 0;
    p_0_.xStem_0_ = 0;
    p_0_.xPositioning_0_ = 0;
    p_0_.xRegistration_0_ = 0;
    p_0_.yAlign_0_ = 0;
    p_0_.yStem_0_ = 0;
    p_0_.yOvershoot_0_ = 0;
    p_0_.fadeEnabled_0_ = 0;
    p_0_.fadeStart_0_ = 0.0;
    p_0_.fadeFull_0_ = 0.0;
    p_0_.xRatio_0_ = 0.0;
    p_0_.xMaxPx_0_ = 0.0;
    p_0_.yRatio_0_ = 0.0;
    p_0_.yMaxPx_0_ = 0.0;
    p_0_.overshootMinPx_0_ = 0.0;
    uint _e121 = p0_0_[0u];
    x_0_ = _e121;
    uint _e123 = p0_0_[1u];
    y_0_ = _e123;
    uint _e124 = x_0_;
    if (((_e124 & 4286578688u) != 0u)) {
        _S8_ = true;
    } else {
        uint _e127 = y_0_;
        _S8_ = ((_e127 & 4294967232u) != 0u);
    }
    bool _e130 = _S8_;
    if (_e130) {
        return false;
    }
    uint _e131 = x_0_;
    _S9_ = int((_e131 & 3u));
    int _e134 = _S9_;
    p_0_.xAlign_0_ = _e134;
    uint _e136 = x_0_;
    p_0_.xStem_0_ = int(((_e136 >> 2u) & 3u));
    uint _e142 = x_0_;
    p_0_.xPositioning_0_ = int(((_e142 >> 4u) & 3u));
    uint _e148 = x_0_;
    p_0_.xRegistration_0_ = int(((_e148 >> 6u) & 3u));
    uint _e154 = x_0_;
    p_0_.fadeEnabled_0_ = int(((_e154 >> 8u) & 1u));
    uint _e160 = x_0_;
    p_0_.fadeStart_0_ = float(((_e160 >> 9u) & 127u));
    uint _e166 = x_0_;
    p_0_.fadeFull_0_ = float(((_e166 >> 16u) & 127u));
    uint _e172 = y_0_;
    p_0_.yAlign_0_ = int((_e172 & 3u));
    uint _e176 = y_0_;
    p_0_.yStem_0_ = int(((_e176 >> 2u) & 3u));
    uint _e182 = y_0_;
    p_0_.yOvershoot_0_ = int(((_e182 >> 4u) & 3u));
    int _e188 = _S9_;
    if ((_e188 > 1)) {
        _S8_ = true;
    } else {
        int _e191 = p_0_.xStem_0_;
        _S8_ = (_e191 > 2);
    }
    bool _e193 = _S8_;
    if (_e193) {
        _S8_ = true;
    } else {
        int _e195 = p_0_.xPositioning_0_;
        _S8_ = (_e195 > 1);
    }
    bool _e197 = _S8_;
    if (_e197) {
        _S8_ = true;
    } else {
        int _e199 = p_0_.xRegistration_0_;
        _S8_ = (_e199 > 1);
    }
    bool _e201 = _S8_;
    if (_e201) {
        _S8_ = true;
    } else {
        int _e203 = p_0_.yAlign_0_;
        _S8_ = (_e203 > 2);
    }
    bool _e205 = _S8_;
    if (_e205) {
        _S8_ = true;
    } else {
        int _e207 = p_0_.yStem_0_;
        _S8_ = (_e207 > 2);
    }
    bool _e209 = _S8_;
    if (_e209) {
        _S8_ = true;
    } else {
        int _e211 = p_0_.yOvershoot_0_;
        _S8_ = (_e211 > 1);
    }
    bool _e213 = _S8_;
    if (_e213) {
        return false;
    }
    uint _e215 = p0_0_[2u];
    p_0_.xRatio_0_ = uintBitsToFloat(_e215);
    uint _e219 = p0_0_[3u];
    p_0_.xMaxPx_0_ = uintBitsToFloat(_e219);
    uint _e223 = p1_0_[0u];
    p_0_.yRatio_0_ = uintBitsToFloat(_e223);
    uint _e227 = p1_0_[1u];
    p_0_.yMaxPx_0_ = uintBitsToFloat(_e227);
    uint _e231 = p1_0_[2u];
    p_0_.overshootMinPx_0_ = uintBitsToFloat(_e231);
    int _e235 = p_0_.xStem_0_;
    if ((_e235 != 0)) {
        float _e238 = p_0_.xRatio_0_;
        param_179 = _e238;
        bool _e239 = snailAhFinite_0_u0028_f1_u003b(param_179);
        if (!(_e239)) {
            _S8_ = true;
        } else {
            float _e242 = p_0_.xRatio_0_;
            _S8_ = (_e242 < 0.0);
        }
    } else {
        _S8_ = false;
    }
    bool _e244 = _S8_;
    if (_e244) {
        _S8_ = true;
    } else {
        int _e246 = p_0_.xStem_0_;
        if ((_e246 == 1)) {
            float _e249 = p_0_.xMaxPx_0_;
            param_180 = _e249;
            bool _e250 = snailAhFinite_0_u0028_f1_u003b(param_180);
            if (!(_e250)) {
                _S8_ = true;
            } else {
                float _e253 = p_0_.xMaxPx_0_;
                _S8_ = (_e253 < 0.0);
            }
        } else {
            _S8_ = false;
        }
    }
    bool _e255 = _S8_;
    if (_e255) {
        _S8_ = true;
    } else {
        int _e257 = p_0_.yStem_0_;
        if ((_e257 != 0)) {
            float _e260 = p_0_.yRatio_0_;
            param_181 = _e260;
            bool _e261 = snailAhFinite_0_u0028_f1_u003b(param_181);
            if (!(_e261)) {
                _S8_ = true;
            } else {
                float _e264 = p_0_.yRatio_0_;
                _S8_ = (_e264 < 0.0);
            }
        } else {
            _S8_ = false;
        }
    }
    bool _e266 = _S8_;
    if (_e266) {
        _S8_ = true;
    } else {
        int _e268 = p_0_.yStem_0_;
        if ((_e268 == 1)) {
            float _e271 = p_0_.yMaxPx_0_;
            param_182 = _e271;
            bool _e272 = snailAhFinite_0_u0028_f1_u003b(param_182);
            if (!(_e272)) {
                _S8_ = true;
            } else {
                float _e275 = p_0_.yMaxPx_0_;
                _S8_ = (_e275 < 0.0);
            }
        } else {
            _S8_ = false;
        }
    }
    bool _e277 = _S8_;
    if (_e277) {
        _S8_ = true;
    } else {
        int _e279 = p_0_.yOvershoot_0_;
        if ((_e279 == 1)) {
            float _e282 = p_0_.overshootMinPx_0_;
            param_183 = _e282;
            bool _e283 = snailAhFinite_0_u0028_f1_u003b(param_183);
            if (!(_e283)) {
                _S8_ = true;
            } else {
                float _e286 = p_0_.overshootMinPx_0_;
                _S8_ = (_e286 < 0.0);
            }
        } else {
            _S8_ = false;
        }
    }
    bool _e288 = _S8_;
    if (_e288) {
        _S8_ = true;
    } else {
        int _e290 = p_0_.xPositioning_0_;
        if ((_e290 == 1)) {
            int _e293 = p_0_.xAlign_0_;
            _S8_ = (_e293 == 0);
        } else {
            _S8_ = false;
        }
    }
    bool _e295 = _S8_;
    if (_e295) {
        _S8_ = true;
    } else {
        int _e297 = p_0_.yOvershoot_0_;
        if ((_e297 == 1)) {
            int _e300 = p_0_.yAlign_0_;
            _S8_ = (_e300 != 2);
        } else {
            _S8_ = false;
        }
    }
    bool _e302 = _S8_;
    if (_e302) {
        return false;
    }
    return true;
}

int snailAhFastCount_0_u0028_vu4_u003b(inout uvec4 words_1_) {
    uvec4 param_184 = uvec4(0u);
    int param_185 = 0;
    int i_1_ = 0;
    int count_1_ = 0;
    uvec4 param_186 = uvec4(0u);
    int param_187 = 0;
    int count_2_ = 0;
    uvec4 _e101 = words_1_;
    param_184 = _e101;
    param_185 = 0;
    uint _e102 = snailAhFastSource_0_u0028_vu4_u003b_i1_u003b(param_184, param_185);
    if ((_e102 == 254u)) {
        return -1;
    }
    i_1_ = 0;
    count_1_ = 0;
    while(true) {
        int _e104 = i_1_;
        if ((_e104 < 16)) {
        } else {
            break;
        }
        uvec4 _e106 = words_1_;
        param_186 = _e106;
        int _e107 = i_1_;
        param_187 = _e107;
        uint _e108 = snailAhFastSource_0_u0028_vu4_u003b_i1_u003b(param_186, param_187);
        if ((_e108 == 255u)) {
            break;
        }
        int _e110 = count_1_;
        count_2_ = (_e110 + 1);
        int _e112 = i_1_;
        i_1_ = (_e112 + 1);
        int _e114 = count_2_;
        count_1_ = _e114;
        continue;
    }
    int _e115 = count_1_;
    return _e115;
}

bool snailAhCount_0_u0028_i1_u003b_f1_u003b_i1_u003b(inout int max_knots_0_, inout float encoded_0_, inout int count_0_) {
    float param_188 = 0.0;
    bool _S7_ = false;
    float _e98 = encoded_0_;
    param_188 = _e98;
    bool _e99 = snailAhFinite_0_u0028_f1_u003b(param_188);
    if (!(_e99)) {
        _S7_ = true;
    } else {
        float _e101 = encoded_0_;
        _S7_ = (_e101 < 0.0);
    }
    bool _e103 = _S7_;
    if (_e103) {
        _S7_ = true;
    } else {
        float _e104 = encoded_0_;
        int _e105 = max_knots_0_;
        _S7_ = (_e104 > float(_e105));
    }
    bool _e108 = _S7_;
    if (_e108) {
        _S7_ = true;
    } else {
        float _e109 = encoded_0_;
        float _e111 = encoded_0_;
        _S7_ = (floor(_e109) != _e111);
    }
    bool _e113 = _S7_;
    if (_e113) {
        count_0_ = 0;
        return false;
    }
    float _e114 = encoded_0_;
    count_0_ = int(_e114);
    return true;
}

vec4 snailAutohintFragment_0_u0028_struct_u002d_AutohintVaryings_0_u002d_vf4_u002d_vf3_u002d_vi2_u002d_vu4_u002d_vu3_u002d_vf4_u005b_4_u005d_u002d_vf4_u005b_4_u005d_u002d_vu4_u002d_vu41_u003b_tA21_u003b_utA21_u003b_t21_u003b_i1_u003b_i1_u003b_f1_u003b_i1_u003b(inout AutohintVaryings_0_ v_3_, sampler2DArray curve_tex_3_, usampler2DArray band_tex_1_, sampler2D layer_tex_5_, inout int layer_base_1_, inout int output_srgb_1_, inout float coverage_exponent_3_, inout int mask_output_1_) {
    ivec3 _S111_ = ivec3(0);
    vec4 h0_0_ = vec4(0.0);
    ivec2 _S112_ = ivec2(0);
    ivec2 param_189 = ivec2(0);
    int param_190 = 0;
    ivec3 _S113_ = ivec3(0);
    vec4 h1_0_ = vec4(0.0);
    ivec2 gLoc_1_ = ivec2(0);
    int packedBands_0_ = 0;
    int bandMaxH_0_ = 0;
    int bandMaxV_0_ = 0;
    int texLayer_3_ = 0;
    vec2 _S114_ = vec2(0.0);
    vec2 rc_3_ = vec2(0.0);
    vec2 epp_1_ = vec2(0.0);
    float _S115_ = 0.0;
    float _S116_ = 0.0;
    int blueCount_1_ = 0;
    int featureXCount_0_ = 0;
    float _S117_ = 0.0;
    ivec2 param_191 = ivec2(0);
    int param_192 = 0;
    int param_193 = 0;
    bool valid_0_ = false;
    int param_194 = 0;
    float param_195 = 0.0;
    int param_196 = 0;
    int xRun_0_ = 0;
    float _S118_ = 0.0;
    ivec2 param_197 = ivec2(0);
    int param_198 = 0;
    int param_199 = 0;
    bool _S119_ = false;
    int param_200 = 0;
    float param_201 = 0.0;
    int param_202 = 0;
    bool valid_1_ = false;
    int yRun_0_ = 0;
    float _S120_ = 0.0;
    ivec2 param_203 = ivec2(0);
    int param_204 = 0;
    int param_205 = 0;
    int param_206 = 0;
    float param_207 = 0.0;
    int param_208 = 0;
    int _S121_ = 0;
    uvec4 param_209 = uvec4(0u);
    int xCount_0_ = 0;
    uvec4 param_210 = uvec4(0u);
    int yCount_0_ = 0;
    float slopeX_0_ = 0.0;
    float slopeY_0_ = 0.0;
    bool fallbackX_0_ = false;
    bool fallbackY_0_ = false;
    float stdX_0_ = 0.0;
    ivec2 param_211 = ivec2(0);
    int param_212 = 0;
    int param_213 = 0;
    float stdY_0_ = 0.0;
    ivec2 param_214 = ivec2(0);
    int param_215 = 0;
    int param_216 = 0;
    bool _S122_ = false;
    SnailAutohintPolicy_0_ policy_1_ = SnailAutohintPolicy_0_(0, 0, 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    uvec4 param_217 = uvec4(0u);
    uvec3 param_218 = uvec3(0u);
    SnailAutohintPolicy_0_ param_219 = SnailAutohintPolicy_0_(0, 0, 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    float param_220 = 0.0;
    float param_221 = 0.0;
    bool _S123_ = false;
    float _S124_ = 0.0;
    ivec2 param_222 = ivec2(0);
    int param_223 = 0;
    int param_224 = 0;
    bool fitValid_0_ = false;
    float bases_1_[32] = float[32](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    float targets_3_[32] = float[32](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    ivec2 param_225 = ivec2(0);
    int param_226 = 0;
    int param_227 = 0;
    int param_228 = 0;
    float param_229 = 0.0;
    float param_230 = 0.0;
    float param_231 = 0.0;
    SnailAutohintPolicy_0_ param_232 = SnailAutohintPolicy_0_(0, 0, 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    int param_233 = 0;
    float param_234[32] = float[32](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    float param_235[32] = float[32](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    int param_236[32] = int[32](0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    float _S125_ = 0.0;
    int param_237 = 0;
    float param_238[32] = float[32](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    float param_239[32] = float[32](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    float param_240 = 0.0;
    float param_241 = 0.0;
    bool fitValid_1_ = false;
    float bases_2_[32] = float[32](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    float targets_4_[32] = float[32](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    ivec2 param_242 = ivec2(0);
    int param_243 = 0;
    int param_244 = 0;
    int param_245 = 0;
    float param_246 = 0.0;
    float param_247 = 0.0;
    float param_248 = 0.0;
    SnailAutohintPolicy_0_ param_249 = SnailAutohintPolicy_0_(0, 0, 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    int param_250 = 0;
    float param_251[32] = float[32](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    float param_252[32] = float[32](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    int param_253[32] = int[32](0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
    float _S126_ = 0.0;
    int param_254 = 0;
    float param_255[32] = float[32](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    float param_256[32] = float[32](0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    float param_257 = 0.0;
    float param_258 = 0.0;
    float _S127_ = 0.0;
    ivec2 param_259 = ivec2(0);
    int param_260 = 0;
    int param_261 = 0;
    float _S128_ = 0.0;
    ivec2 param_262 = ivec2(0);
    int param_263 = 0;
    vec4 param_264[4] = vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0));
    uvec4 param_265 = uvec4(0u);
    int param_266 = 0;
    float param_267 = 0.0;
    float param_268 = 0.0;
    float param_269 = 0.0;
    float _S129_ = 0.0;
    ivec2 param_270 = ivec2(0);
    int param_271 = 0;
    vec4 param_272[4] = vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0));
    uvec4 param_273 = uvec4(0u);
    int param_274 = 0;
    float param_275 = 0.0;
    float param_276 = 0.0;
    float param_277 = 0.0;
    vec2 epp_2_ = vec2(0.0);
    float cov_2_ = 0.0;
    vec2 param_278 = vec2(0.0);
    vec2 param_279 = vec2(0.0);
    vec2 param_280 = vec2(0.0);
    ivec2 param_281 = ivec2(0);
    ivec2 param_282 = ivec2(0);
    vec4 param_283 = vec4(0.0);
    int param_284 = 0;
    float param_285 = 0.0;
    vec4 premul_1_ = vec4(0.0);
    vec4 param_286 = vec4(0.0);
    float param_287 = 0.0;
    vec4 _S130_ = vec4(0.0);
    vec4 param_288 = vec4(0.0);
    ivec2 _e255 = v_3_.info_0_;
    _S111_ = ivec3(_e255.x, _e255.y, 0);
    ivec3 _e259 = _S111_;
    int _e262 = _S111_[2u];
    vec4 _e263 = texelFetch(layer_tex_5_, _e259.xy, _e262);
    h0_0_ = _e263;
    ivec2 _e265 = v_3_.info_0_;
    param_189 = _e265;
    param_190 = 1;
    ivec2 _e266 = snailAhLayerLoc_0_u0028_t21_u003b_vi2_u003b_i1_u003b(layer_tex_5_, param_189, param_190);
    _S112_ = _e266;
    ivec2 _e267 = _S112_;
    _S113_ = ivec3(_e267.x, _e267.y, 0);
    ivec3 _e271 = _S113_;
    int _e274 = _S113_[2u];
    vec4 _e275 = texelFetch(layer_tex_5_, _e271.xy, _e274);
    h1_0_ = _e275;
    float _e277 = h0_0_[0u];
    float _e281 = h0_0_[1u];
    gLoc_1_ = ivec2(int((_e277 + 0.5)), int((_e281 + 0.5)));
    float _e286 = h0_0_[2u];
    packedBands_0_ = floatBitsToInt(_e286);
    int _e288 = packedBands_0_;
    bandMaxH_0_ = (_e288 & 65535);
    int _e290 = packedBands_0_;
    bandMaxV_0_ = ((_e290 >> uint(16)) & 65535);
    int _e294 = layer_base_1_;
    float _e297 = v_3_.texcoord_layer_0_[2u];
    texLayer_3_ = (_e294 + int(_e297));
    vec3 _e301 = v_3_.texcoord_layer_0_;
    _S114_ = _e301.xy;
    vec2 _e303 = _S114_;
    rc_3_ = _e303;
    vec2 _e304 = _S114_;
    vec2 _e305 = fwidth(_e304);
    epp_1_ = _e305;
    float _e307 = epp_1_[0u];
    _S115_ = (1.0 / _e307);
    float _e310 = epp_1_[1u];
    _S116_ = (1.0 / _e310);
    blueCount_1_ = 0;
    featureXCount_0_ = 0;
    ivec2 _e313 = v_3_.info_0_;
    param_191 = _e313;
    param_192 = 0;
    param_193 = 10;
    float _e314 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_5_, param_191, param_192, param_193);
    _S117_ = _e314;
    param_194 = 32;
    float _e315 = _S117_;
    param_195 = _e315;
    bool _e316 = snailAhCount_0_u0028_i1_u003b_f1_u003b_i1_u003b(param_194, param_195, param_196);
    int _e317 = param_196;
    blueCount_1_ = _e317;
    valid_0_ = _e316;
    int _e318 = blueCount_1_;
    xRun_0_ = (12 + (2 * _e318));
    bool _e321 = valid_0_;
    if (_e321) {
        ivec2 _e323 = v_3_.info_0_;
        param_197 = _e323;
        int _e324 = xRun_0_;
        param_198 = _e324;
        param_199 = 0;
        float _e325 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_5_, param_197, param_198, param_199);
        _S118_ = _e325;
        param_200 = 32;
        float _e326 = _S118_;
        param_201 = _e326;
        bool _e327 = snailAhCount_0_u0028_i1_u003b_f1_u003b_i1_u003b(param_200, param_201, param_202);
        int _e328 = param_202;
        featureXCount_0_ = _e328;
        _S119_ = _e327;
        bool _e329 = _S119_;
        valid_1_ = _e329;
    } else {
        valid_1_ = false;
    }
    int _e330 = xRun_0_;
    int _e332 = featureXCount_0_;
    yRun_0_ = ((_e330 + 1) + (4 * _e332));
    bool _e335 = valid_1_;
    if (_e335) {
        ivec2 _e337 = v_3_.info_0_;
        param_203 = _e337;
        int _e338 = yRun_0_;
        param_204 = _e338;
        param_205 = 0;
        float _e339 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_5_, param_203, param_204, param_205);
        _S120_ = _e339;
        param_206 = 32;
        float _e340 = _S120_;
        param_207 = _e340;
        bool _e341 = snailAhCount_0_u0028_i1_u003b_f1_u003b_i1_u003b(param_206, param_207, param_208);
        valid_1_ = _e341;
    } else {
        valid_1_ = false;
    }
    bool _e342 = valid_1_;
    if (_e342) {
        uvec4 _e344 = v_3_.x_sources_0_;
        param_209 = _e344;
        int _e345 = snailAhFastCount_0_u0028_vu4_u003b(param_209);
        _S121_ = _e345;
    } else {
        _S121_ = 0;
    }
    int _e346 = _S121_;
    xCount_0_ = _e346;
    bool _e347 = valid_1_;
    if (_e347) {
        uvec4 _e349 = v_3_.y_sources_0_;
        param_210 = _e349;
        int _e350 = snailAhFastCount_0_u0028_vu4_u003b(param_210);
        _S121_ = _e350;
    } else {
        _S121_ = 0;
    }
    int _e351 = _S121_;
    yCount_0_ = _e351;
    slopeX_0_ = 1.0;
    slopeY_0_ = 1.0;
    int _e352 = xCount_0_;
    fallbackX_0_ = (_e352 < 0);
    int _e354 = _S121_;
    fallbackY_0_ = (_e354 < 0);
    bool _e356 = valid_1_;
    if (_e356) {
        bool _e357 = fallbackX_0_;
        if (_e357) {
            valid_1_ = true;
        } else {
            bool _e358 = fallbackY_0_;
            valid_1_ = _e358;
        }
    } else {
        valid_1_ = false;
    }
    bool _e359 = valid_1_;
    if (_e359) {
        ivec2 _e361 = v_3_.info_0_;
        param_211 = _e361;
        param_212 = 0;
        param_213 = 8;
        float _e362 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_5_, param_211, param_212, param_213);
        stdX_0_ = _e362;
        ivec2 _e364 = v_3_.info_0_;
        param_214 = _e364;
        param_215 = 0;
        param_216 = 9;
        float _e365 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_5_, param_214, param_215, param_216);
        stdY_0_ = _e365;
        uvec4 _e367 = v_3_.policy0_0_;
        param_217 = _e367;
        uvec3 _e369 = v_3_.policy1_0_;
        param_218 = _e369;
        bool _e370 = snailDecodeAutohintPolicy_0_u0028_vu4_u003b_vu3_u003b_struct_u002d_SnailAutohintPolicy_0_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f11_u003b(param_217, param_218, param_219);
        SnailAutohintPolicy_0_ _e371 = param_219;
        policy_1_ = _e371;
        _S122_ = _e370;
        bool _e372 = _S122_;
        if (_e372) {
            float _e373 = stdX_0_;
            param_220 = _e373;
            bool _e374 = snailAhFinite_0_u0028_f1_u003b(param_220);
            valid_1_ = _e374;
        } else {
            valid_1_ = false;
        }
        bool _e375 = valid_1_;
        if (_e375) {
            float _e376 = stdX_0_;
            valid_1_ = (_e376 >= 0.0);
        } else {
            valid_1_ = false;
        }
        bool _e378 = valid_1_;
        if (_e378) {
            float _e379 = stdY_0_;
            param_221 = _e379;
            bool _e380 = snailAhFinite_0_u0028_f1_u003b(param_221);
            valid_1_ = _e380;
        } else {
            valid_1_ = false;
        }
        bool _e381 = valid_1_;
        if (_e381) {
            float _e382 = stdY_0_;
            valid_1_ = (_e382 >= 0.0);
        } else {
            valid_1_ = false;
        }
        bool _e384 = valid_1_;
        if (_e384) {
            bool _e385 = fallbackX_0_;
            _S123_ = _e385;
        } else {
            _S123_ = false;
        }
        bool _e386 = _S123_;
        if (_e386) {
            ivec2 _e388 = v_3_.info_0_;
            param_222 = _e388;
            param_223 = 0;
            param_224 = 11;
            float _e389 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_5_, param_222, param_223, param_224);
            _S124_ = _e389;
            ivec2 _e391 = v_3_.info_0_;
            param_225 = _e391;
            param_226 = 0;
            int _e392 = xRun_0_;
            param_227 = _e392;
            int _e393 = blueCount_1_;
            param_228 = _e393;
            float _e394 = stdX_0_;
            param_229 = _e394;
            float _e395 = _S124_;
            param_230 = _e395;
            float _e396 = _S115_;
            param_231 = _e396;
            SnailAutohintPolicy_0_ _e397 = policy_1_;
            param_232 = _e397;
            bool _e398 = snailFitAutohintAxis_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b_i1_u003b_f1_u003b_f1_u003b_f1_u003b_struct_u002d_SnailAutohintPolicy_0_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f11_u003b_i1_u003b_f1_u005b_32_u005d_u003b_f1_u005b_32_u005d_u003b_i1_u005b_32_u005d_u003b(layer_tex_5_, param_225, param_226, param_227, param_228, param_229, param_230, param_231, param_232, param_233, param_234, param_235, param_236);
            int _e399 = param_233;
            xCount_0_ = _e399;
            float _e400[32] = param_234;
            bases_1_ = _e400;
            float _e401[32] = param_235;
            targets_3_ = _e401;
            fitValid_0_ = _e398;
            bool _e402 = fitValid_0_;
            if (!(_e402)) {
                xCount_0_ = 0;
            }
            int _e404 = xCount_0_;
            param_237 = _e404;
            float _e405[32] = bases_1_;
            param_238 = _e405;
            float _e406[32] = targets_3_;
            param_239 = _e406;
            float _e408 = rc_3_[0u];
            param_240 = _e408;
            float _e409 = snailInverseWarpAxis_0_u0028_i1_u003b_f1_u005b_32_u005d_u003b_f1_u005b_32_u005d_u003b_f1_u003b_f1_u003b(param_237, param_238, param_239, param_240, param_241);
            float _e410 = param_241;
            slopeX_0_ = _e410;
            _S125_ = _e409;
            float _e411 = _S125_;
            rc_3_[0u] = _e411;
        }
        bool _e413 = valid_1_;
        if (_e413) {
            bool _e414 = fallbackY_0_;
            valid_1_ = _e414;
        } else {
            valid_1_ = false;
        }
        bool _e415 = valid_1_;
        if (_e415) {
            ivec2 _e417 = v_3_.info_0_;
            param_242 = _e417;
            param_243 = 1;
            int _e418 = yRun_0_;
            param_244 = _e418;
            int _e419 = blueCount_1_;
            param_245 = _e419;
            float _e420 = stdY_0_;
            param_246 = _e420;
            param_247 = 0.0;
            float _e421 = _S116_;
            param_248 = _e421;
            SnailAutohintPolicy_0_ _e422 = policy_1_;
            param_249 = _e422;
            bool _e423 = snailFitAutohintAxis_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b_i1_u003b_f1_u003b_f1_u003b_f1_u003b_struct_u002d_SnailAutohintPolicy_0_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_i1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f1_u002d_f11_u003b_i1_u003b_f1_u005b_32_u005d_u003b_f1_u005b_32_u005d_u003b_i1_u005b_32_u005d_u003b(layer_tex_5_, param_242, param_243, param_244, param_245, param_246, param_247, param_248, param_249, param_250, param_251, param_252, param_253);
            int _e424 = param_250;
            yCount_0_ = _e424;
            float _e425[32] = param_251;
            bases_2_ = _e425;
            float _e426[32] = param_252;
            targets_4_ = _e426;
            fitValid_1_ = _e423;
            bool _e427 = fitValid_1_;
            if (!(_e427)) {
                yCount_0_ = 0;
            }
            int _e429 = yCount_0_;
            param_254 = _e429;
            float _e430[32] = bases_2_;
            param_255 = _e430;
            float _e431[32] = targets_4_;
            param_256 = _e431;
            float _e433 = rc_3_[1u];
            param_257 = _e433;
            float _e434 = snailInverseWarpAxis_0_u0028_i1_u003b_f1_u005b_32_u005d_u003b_f1_u005b_32_u005d_u003b_f1_u003b_f1_u003b(param_254, param_255, param_256, param_257, param_258);
            float _e435 = param_258;
            slopeY_0_ = _e435;
            _S126_ = _e434;
            float _e436 = _S126_;
            rc_3_[1u] = _e436;
        }
    }
    bool _e438 = fallbackX_0_;
    if (!(_e438)) {
        ivec2 _e441 = v_3_.info_0_;
        param_259 = _e441;
        param_260 = 0;
        param_261 = 11;
        float _e442 = snailWarpF_0_u0028_t21_u003b_vi2_u003b_i1_u003b_i1_u003b(layer_tex_5_, param_259, param_260, param_261);
        _S127_ = _e442;
        ivec2 _e444 = v_3_.info_0_;
        param_262 = _e444;
        int _e445 = xCount_0_;
        param_263 = _e445;
        vec4 _e447[4] = v_3_.x_targets_0_;
        param_264 = _e447;
        uvec4 _e449 = v_3_.x_sources_0_;
        param_265 = _e449;
        int _e450 = xRun_0_;
        param_266 = _e450;
        float _e451 = _S127_;
        param_267 = _e451;
        float _e453 = rc_3_[0u];
        param_268 = _e453;
        float _e454 = snailInverseFastAxis_0_u0028_t21_u003b_vi2_u003b_i1_u003b_vf4_u005b_4_u005d_u003b_vu4_u003b_i1_u003b_f1_u003b_f1_u003b_f1_u003b(layer_tex_5_, param_262, param_263, param_264, param_265, param_266, param_267, param_268, param_269);
        float _e455 = param_269;
        slopeX_0_ = _e455;
        _S128_ = _e454;
        float _e456 = _S128_;
        rc_3_[0u] = _e456;
    }
    bool _e458 = fallbackY_0_;
    if (!(_e458)) {
        ivec2 _e461 = v_3_.info_0_;
        param_270 = _e461;
        int _e462 = yCount_0_;
        param_271 = _e462;
        vec4 _e464[4] = v_3_.y_targets_0_;
        param_272 = _e464;
        uvec4 _e466 = v_3_.y_sources_0_;
        param_273 = _e466;
        int _e467 = yRun_0_;
        param_274 = _e467;
        param_275 = 0.0;
        float _e469 = rc_3_[1u];
        param_276 = _e469;
        float _e470 = snailInverseFastAxis_0_u0028_t21_u003b_vi2_u003b_i1_u003b_vf4_u005b_4_u005d_u003b_vu4_u003b_i1_u003b_f1_u003b_f1_u003b_f1_u003b(layer_tex_5_, param_270, param_271, param_272, param_273, param_274, param_275, param_276, param_277);
        float _e471 = param_277;
        slopeY_0_ = _e471;
        _S129_ = _e470;
        float _e472 = _S129_;
        rc_3_[1u] = _e472;
    }
    vec2 _e474 = epp_1_;
    float _e475 = slopeX_0_;
    float _e476 = slopeY_0_;
    epp_2_ = (_e474 * vec2(_e475, _e476));
    float _e480 = epp_2_[0u];
    float _e484 = epp_2_[1u];
    int _e488 = bandMaxV_0_;
    int _e489 = bandMaxH_0_;
    vec2 _e491 = rc_3_;
    param_278 = _e491;
    vec2 _e492 = epp_2_;
    param_279 = _e492;
    param_280 = vec2((1.0 / max(_e480, 1.5258789e-5)), (1.0 / max(_e484, 1.5258789e-5)));
    ivec2 _e493 = gLoc_1_;
    param_281 = _e493;
    param_282 = ivec2(_e488, _e489);
    vec4 _e494 = h1_0_;
    param_283 = _e494;
    int _e495 = texLayer_3_;
    param_284 = _e495;
    float _e496 = coverage_exponent_3_;
    param_285 = _e496;
    float _e497 = evalGlyphCoverage_0_u0028_vf2_u003b_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b_tA21_u003b_utA21_u003b_f1_u003b(param_278, param_279, param_280, param_281, param_282, param_283, param_284, curve_tex_3_, band_tex_1_, param_285);
    cov_2_ = _e497;
    float _e498 = cov_2_;
    if ((_e498 < 0.003921569)) {
        discard;
    }
    vec4 _e501 = v_3_.paint_0_;
    param_286 = _e501;
    float _e502 = cov_2_;
    param_287 = _e502;
    vec4 _e503 = premultiplyColor_0_u0028_vf4_u003b_f1_u003b(param_286, param_287);
    premul_1_ = _e503;
    int _e504 = mask_output_1_;
    if ((_e504 != 0)) {
        float _e507 = premul_1_[3u];
        _S130_ = vec4(_e507);
    } else {
        int _e509 = output_srgb_1_;
        if ((_e509 != 0)) {
            vec4 _e511 = premul_1_;
            param_288 = _e511;
            vec4 _e512 = srgbEncodePremultiplied_0_u0028_vf4_u003b(param_288);
            _S130_ = _e512;
        } else {
            vec4 _e513 = premul_1_;
            _S130_ = _e513;
        }
    }
    vec4 _e514 = _S130_;
    return _e514;
}

void main_1() {
    AutohintVaryings_0_ v_4_ = AutohintVaryings_0_(vec4(0.0), vec3(0.0), ivec2(0), uvec4(0u), uvec3(0u), vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0)), vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0)), uvec4(0u), uvec4(0u));
    vec4 _S131_ = vec4(0.0);
    AutohintVaryings_0_ param_289 = AutohintVaryings_0_(vec4(0.0), vec3(0.0), ivec2(0), uvec4(0u), uvec3(0u), vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0)), vec4[4](vec4(0.0), vec4(0.0), vec4(0.0), vec4(0.0)), uvec4(0u), uvec4(0u));
    int param_290 = 0;
    int param_291 = 0;
    float param_292 = 0.0;
    int param_293 = 0;
    vec4 _e100 = input_paint_0_1;
    v_4_.paint_0_ = _e100;
    vec3 _e102 = input_texcoord_layer_0_1;
    v_4_.texcoord_layer_0_ = _e102;
    ivec2 _e104 = input_info_0_1;
    v_4_.info_0_ = _e104;
    uvec4 _e106 = input_policy0_0_1;
    v_4_.policy0_0_ = _e106;
    uvec3 _e108 = input_policy1_0_1;
    v_4_.policy1_0_ = _e108;
    vec4 _e110 = input_x_targets0_0_1;
    v_4_.x_targets_0_[0] = _e110;
    vec4 _e113 = input_x_targets1_0_1;
    v_4_.x_targets_0_[1] = _e113;
    vec4 _e116 = input_x_targets2_0_1;
    v_4_.x_targets_0_[2] = _e116;
    vec4 _e119 = input_x_targets3_0_1;
    v_4_.x_targets_0_[3] = _e119;
    vec4 _e122 = input_y_targets0_0_1;
    v_4_.y_targets_0_[0] = _e122;
    vec4 _e125 = input_y_targets1_0_1;
    v_4_.y_targets_0_[1] = _e125;
    vec4 _e128 = input_y_targets2_0_1;
    v_4_.y_targets_0_[2] = _e128;
    vec4 _e131 = input_y_targets3_0_1;
    v_4_.y_targets_0_[3] = _e131;
    uvec4 _e134 = input_x_sources_0_1;
    v_4_.x_sources_0_ = _e134;
    uvec4 _e136 = input_y_sources_0_1;
    v_4_.y_sources_0_ = _e136;
    AutohintVaryings_0_ _e138 = v_4_;
    param_289 = _e138;
    int _e140 = _group_0_binding_0_fs.layer_base_0_;
    param_290 = _e140;
    int _e142 = _group_0_binding_0_fs.output_srgb_0_;
    param_291 = _e142;
    float _e144 = _group_0_binding_0_fs.coverage_exponent_0_;
    param_292 = _e144;
    int _e146 = _group_0_binding_0_fs.mask_output_0_;
    param_293 = _e146;
    vec4 _e147 = snailAutohintFragment_0_u0028_struct_u002d_AutohintVaryings_0_u002d_vf4_u002d_vf3_u002d_vi2_u002d_vu4_u002d_vu3_u002d_vf4_u005b_4_u005d_u002d_vf4_u005b_4_u005d_u002d_vu4_u002d_vu41_u003b_tA21_u003b_utA21_u003b_t21_u003b_i1_u003b_i1_u003b_f1_u003b_i1_u003b(param_289, _group_0_binding_1_fs, _group_0_binding_2_fs, _group_0_binding_3_fs, param_290, param_291, param_292, param_293);
    _S131_ = _e147;
    vec4 _e148 = _S131_;
    entryPointParam_fragmentMain_0_ = _e148;
    return;
}

void main() {
    vec4 input_paint_0_ = _vs2fs_location0;
    vec3 input_texcoord_layer_0_ = _vs2fs_location1;
    ivec2 input_info_0_ = _vs2fs_location2;
    uvec4 input_policy0_0_ = _vs2fs_location3;
    uvec3 input_policy1_0_ = _vs2fs_location4;
    vec4 input_x_targets0_0_ = _vs2fs_location5;
    vec4 input_x_targets1_0_ = _vs2fs_location6;
    vec4 input_x_targets2_0_ = _vs2fs_location7;
    vec4 input_x_targets3_0_ = _vs2fs_location8;
    vec4 input_y_targets0_0_ = _vs2fs_location9;
    vec4 input_y_targets1_0_ = _vs2fs_location10;
    vec4 input_y_targets2_0_ = _vs2fs_location11;
    vec4 input_y_targets3_0_ = _vs2fs_location12;
    uvec4 input_x_sources_0_ = _vs2fs_location13;
    uvec4 input_y_sources_0_ = _vs2fs_location14;
    input_paint_0_1 = input_paint_0_;
    input_texcoord_layer_0_1 = input_texcoord_layer_0_;
    input_info_0_1 = input_info_0_;
    input_policy0_0_1 = input_policy0_0_;
    input_policy1_0_1 = input_policy1_0_;
    input_x_targets0_0_1 = input_x_targets0_0_;
    input_x_targets1_0_1 = input_x_targets1_0_;
    input_x_targets2_0_1 = input_x_targets2_0_;
    input_x_targets3_0_1 = input_x_targets3_0_;
    input_y_targets0_0_1 = input_y_targets0_0_;
    input_y_targets1_0_1 = input_y_targets1_0_;
    input_y_targets2_0_1 = input_y_targets2_0_;
    input_y_targets3_0_1 = input_y_targets3_0_;
    input_x_sources_0_1 = input_x_sources_0_;
    input_y_sources_0_1 = input_y_sources_0_;
    main_1();
    vec4 _e31 = entryPointParam_fragmentMain_0_;
    _fs2p_location0 = _e31;
    return;
}

