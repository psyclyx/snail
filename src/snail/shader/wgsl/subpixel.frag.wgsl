enable dual_source_blending;

struct CoverageBandSpan_0_ {
    first_0_: i32,
    last_0_: i32,
}

struct block_SLANG_ParameterGroup_PushConstants_0_ {
    mvp_0_: mat4x4<f32>,
    viewport_0_: vec2<f32>,
    subpixel_order_0_: i32,
    output_srgb_0_: i32,
    layer_base_0_: i32,
    coverage_exponent_0_: f32,
}

struct FragmentOutput {
    @location(0) @blend_src(1) member: vec4<f32>,
    @location(0) @blend_src(0) member_1: vec4<f32>,
}

@group(2) @binding(0) 
var<uniform> PushConstants_0_: block_SLANG_ParameterGroup_PushConstants_0_;
@group(1) @binding(0) 
var u_curve_tex_0_sampler: sampler;
@group(0) @binding(0) 
var u_curve_tex_0_image: texture_2d_array<f32>;
@group(1) @binding(1) 
var u_band_tex_0_sampler: sampler;
@group(0) @binding(1) 
var u_band_tex_0_image: texture_2d_array<u32>;
var<private> _S72_: vec4<f32>;
var<private> _S1_: vec4<f32>;
var<private> v_glyph_0_1: vec4<i32>;
var<private> v_texcoord_0_1: vec2<f32>;
var<private> v_banding_0_1: vec4<f32>;
var<private> v_color_0_1: vec4<f32>;
var<private> v_tint_0_1: vec4<f32>;
var<private> entryPointParam_main_frag_blend_0_: vec4<f32>;
var<private> entryPointParam_main_frag_color_0_: vec4<f32>;

fn premultiplyColorSubpixel_0_u0028_vf4_u003b_vf3_u003b_f1_u003b(color_0_: ptr<function, vec4<f32>>, cov_6_: ptr<function, vec3<f32>>, alpha_cov_0_: ptr<function, f32>) -> vec4<f32> {
    var _S71_: f32;

    let _e67 = (*color_0_)[3u];
    _S71_ = _e67;
    let _e68 = (*color_0_);
    let _e70 = _S71_;
    let _e72 = (*cov_6_);
    let _e74 = (_e68.xyz * (vec3(_e70) * _e72));
    let _e75 = _S71_;
    let _e76 = (*alpha_cov_0_);
    return vec4<f32>(_e74.x, _e74.y, _e74.z, (_e75 * _e76));
}

fn srgbEncode_0_u0028_f1_u003b(c_0_: ptr<function, f32>) -> f32 {
    var _S70_: f32;

    let _e64 = (*c_0_);
    if (_e64 <= 0.0031308f) {
        let _e66 = (*c_0_);
        _S70_ = (_e66 * 12.92f);
    } else {
        let _e68 = (*c_0_);
        _S70_ = ((1.055f * pow(_e68, 0.41666666f)) - 0.055f);
    }
    let _e72 = _S70_;
    return _e72;
}

fn emitSubpixelColor_0_u0028_vf4_u003b_vf3_u003b_f1_u003b(color_1_: ptr<function, vec4<f32>>, cov_7_: ptr<function, vec3<f32>>, alpha_cov_1_: ptr<function, f32>) {
    var effective_0_: vec4<f32>;
    var param: f32;
    var param_1: f32;
    var param_2: f32;
    var param_3: vec4<f32>;
    var param_4: vec3<f32>;
    var param_5: f32;

    let _e73 = PushConstants_0_.output_srgb_0_;
    if (_e73 != 0i) {
        let _e76 = (*color_1_)[0u];
        param = max(_e76, 0f);
        let _e78 = srgbEncode_0_u0028_f1_u003b((&param));
        let _e80 = (*color_1_)[1u];
        param_1 = max(_e80, 0f);
        let _e82 = srgbEncode_0_u0028_f1_u003b((&param_1));
        let _e84 = (*color_1_)[2u];
        param_2 = max(_e84, 0f);
        let _e86 = srgbEncode_0_u0028_f1_u003b((&param_2));
        let _e88 = (*color_1_)[3u];
        effective_0_ = vec4<f32>(_e78, _e82, _e86, _e88);
    } else {
        let _e90 = (*color_1_);
        effective_0_ = _e90;
    }
    let _e91 = effective_0_;
    param_3 = _e91;
    let _e92 = (*cov_7_);
    param_4 = _e92;
    let _e93 = (*alpha_cov_1_);
    param_5 = _e93;
    let _e94 = premultiplyColorSubpixel_0_u0028_vf4_u003b_vf3_u003b_f1_u003b((&param_3), (&param_4), (&param_5));
    _S72_ = _e94;
    let _e96 = (*color_1_)[3u];
    let _e98 = (*cov_7_);
    let _e99 = (vec3(_e96) * _e98);
    _S1_ = vec4<f32>(_e99.x, _e99.y, _e99.z, 0f);
    return;
}

fn applyCoverageTransfer_0_u0028_f1_u003b(cov_4_: ptr<function, f32>) -> f32 {
    var clamped_0_: f32;
    var _S62_: f32;
    var _S63_: f32;

    let _e66 = (*cov_4_);
    clamped_0_ = clamp(_e66, 0f, 1f);
    let _e69 = PushConstants_0_.coverage_exponent_0_;
    _S62_ = max(_e69, 0.000015258789f);
    let _e71 = _S62_;
    if (abs((_e71 - 1f)) <= 0.000001f) {
        let _e75 = clamped_0_;
        _S63_ = _e75;
    } else {
        let _e76 = clamped_0_;
        let _e77 = _S62_;
        _S63_ = pow(_e76, _e77);
    }
    let _e79 = _S63_;
    return _e79;
}

fn applyCoverageTransfer_1_u0028_vf3_u003b(cov_5_: ptr<function, vec3<f32>>) -> vec3<f32> {
    var param_6: f32;
    var param_7: f32;
    var param_8: f32;

    let _e67 = (*cov_5_)[0u];
    param_6 = _e67;
    let _e68 = applyCoverageTransfer_0_u0028_f1_u003b((&param_6));
    let _e70 = (*cov_5_)[1u];
    param_7 = _e70;
    let _e71 = applyCoverageTransfer_0_u0028_f1_u003b((&param_7));
    let _e73 = (*cov_5_)[2u];
    param_8 = _e73;
    let _e74 = applyCoverageTransfer_0_u0028_f1_u003b((&param_8));
    return vec3<f32>(_e68, _e71, _e74);
}

fn filterSubpixelCoverage_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_b1_u003b(s_m3_0_: ptr<function, f32>, s_m2_0_: ptr<function, f32>, s_m1_0_: ptr<function, f32>, s_0_0_: ptr<function, f32>, s_p1_0_: ptr<function, f32>, s_p2_0_: ptr<function, f32>, s_p3_0_: ptr<function, f32>, reverse_order_0_: ptr<function, bool>) -> vec4<f32> {
    var _S61_: f32;
    var left_0_: f32;
    var center_1_: f32;
    var right_0_: f32;
    var cov_2_: vec3<f32>;
    var cov_3_: vec3<f32>;

    let _e76 = (*s_0_0_);
    _S61_ = (0.30078125f * _e76);
    let _e78 = (*s_m3_0_);
    let _e80 = (*s_m2_0_);
    let _e83 = (*s_m1_0_);
    let _e86 = _S61_;
    let _e88 = (*s_p1_0_);
    left_0_ = (((((0.03125f * _e78) + (0.30078125f * _e80)) + (0.3359375f * _e83)) + _e86) + (0.03125f * _e88));
    let _e91 = (*s_m2_0_);
    let _e93 = (*s_m1_0_);
    let _e96 = (*s_0_0_);
    let _e99 = (*s_p1_0_);
    let _e102 = (*s_p2_0_);
    center_1_ = (((((0.03125f * _e91) + (0.30078125f * _e93)) + (0.3359375f * _e96)) + (0.30078125f * _e99)) + (0.03125f * _e102));
    let _e105 = (*s_m1_0_);
    let _e107 = _S61_;
    let _e109 = (*s_p1_0_);
    let _e112 = (*s_p2_0_);
    let _e115 = (*s_p3_0_);
    right_0_ = (((((0.03125f * _e105) + _e107) + (0.3359375f * _e109)) + (0.30078125f * _e112)) + (0.03125f * _e115));
    let _e118 = (*reverse_order_0_);
    if _e118 {
        let _e119 = right_0_;
        let _e120 = center_1_;
        let _e121 = left_0_;
        cov_2_ = vec3<f32>(_e119, _e120, _e121);
    } else {
        let _e123 = left_0_;
        let _e124 = center_1_;
        let _e125 = right_0_;
        cov_2_ = vec3<f32>(_e123, _e124, _e125);
    }
    let _e127 = cov_2_;
    cov_3_ = clamp(_e127, vec3(0f), vec3(1f));
    let _e131 = cov_3_;
    let _e133 = cov_3_[0u];
    let _e135 = cov_3_[1u];
    let _e138 = cov_3_[2u];
    return vec4<f32>(_e131.x, _e131.y, _e131.z, clamp((((_e133 + _e135) + _e138) * 0.33333334f), 0f, 1f));
}

fn applyFillRule_0_u0028_f1_u003b_i1_u003b(winding_0_: ptr<function, f32>, fill_rule_mode_0_: ptr<function, i32>) -> f32 {
    let _e64 = (*fill_rule_mode_0_);
    if (_e64 == 1i) {
        let _e66 = (*winding_0_);
        return (1f - abs(((fract((_e66 * 0.5f)) * 2f) - 1f)));
    }
    let _e73 = (*winding_0_);
    return abs(_e73);
}

fn snapNearTangentSqrt_0_u0028_f1_u003b_f1_u003b_f1_u003b(disc_0_: ptr<function, f32>, b_0_: ptr<function, f32>, ac_0_: ptr<function, f32>) -> f32 {
    var _S8_: f32;

    let _e66 = (*disc_0_);
    let _e67 = (*b_0_);
    let _e68 = (*b_0_);
    let _e70 = (*ac_0_);
    if (_e66 <= (max((_e67 * _e68), abs(_e70)) * 0.000003f)) {
        _S8_ = 0f;
    } else {
        let _e75 = (*disc_0_);
        _S8_ = sqrt(_e75);
    }
    let _e77 = _S8_;
    return _e77;
}

fn solveVertPoly_0_u0028_vf4_u003b_vf2_u003b(p12_2_: ptr<function, vec4<f32>>, p3_2_: ptr<function, vec2<f32>>) -> vec2<f32> {
    var _S28_: vec2<f32>;
    var _S29_: vec2<f32>;
    var a_1_: vec2<f32>;
    var b_2_: vec2<f32>;
    var _S30_: f32;
    var _S31_: f32;
    var t1_1_: f32;
    var t2_1_: f32;
    var _S32_: f32;
    var _S33_: f32;
    var _S34_: f32;
    var sq_1_: f32;
    var param_9: f32;
    var param_10: f32;
    var param_11: f32;
    var q_2_: f32;
    var _S35_: f32;
    var q_3_: f32;
    var _S36_: f32;
    var _S37_: f32;
    var _S38_: f32;
    var _S39_: f32;
    var _S40_: f32;

    let _e87 = (*p12_2_);
    _S28_ = _e87.xy;
    let _e89 = (*p12_2_);
    _S29_ = _e89.zw;
    let _e91 = _S28_;
    let _e92 = _S29_;
    let _e95 = (*p3_2_);
    a_1_ = ((_e91 - (_e92 * 2f)) + _e95);
    let _e97 = _S28_;
    let _e98 = _S29_;
    b_2_ = (_e97 - _e98);
    let _e101 = a_1_[0u];
    _S30_ = _e101;
    let _e102 = _S30_;
    if (abs(_e102) < 0.000015258789f) {
        let _e106 = b_2_[0u];
        _S31_ = _e106;
        let _e107 = _S31_;
        if (abs(_e107) < 0.000015258789f) {
            t1_1_ = 0f;
        } else {
            let _e111 = (*p12_2_)[0u];
            let _e113 = _S31_;
            t1_1_ = ((_e111 * 0.5f) / _e113);
        }
        let _e115 = t1_1_;
        t2_1_ = _e115;
    } else {
        let _e117 = b_2_[0u];
        _S32_ = _e117;
        let _e119 = (*p12_2_)[0u];
        _S33_ = _e119;
        let _e120 = _S30_;
        let _e121 = _S33_;
        _S34_ = (_e120 * _e121);
        let _e123 = _S32_;
        let _e124 = _S32_;
        let _e126 = _S34_;
        param_9 = ((_e123 * _e124) - _e126);
        let _e128 = _S32_;
        param_10 = _e128;
        let _e129 = _S34_;
        param_11 = _e129;
        let _e130 = snapNearTangentSqrt_0_u0028_f1_u003b_f1_u003b_f1_u003b((&param_9), (&param_10), (&param_11));
        sq_1_ = _e130;
        let _e131 = _S32_;
        if (_e131 >= 0f) {
            let _e133 = _S32_;
            let _e134 = sq_1_;
            q_2_ = (_e133 + _e134);
            let _e136 = q_2_;
            let _e137 = _S30_;
            _S35_ = (_e136 / _e137);
            let _e139 = q_2_;
            if (abs(_e139) < 0.000015258789f) {
                t1_1_ = 0f;
            } else {
                let _e142 = _S33_;
                let _e143 = q_2_;
                t1_1_ = (_e142 / _e143);
            }
            let _e145 = _S35_;
            t2_1_ = _e145;
        } else {
            let _e146 = _S32_;
            let _e147 = sq_1_;
            q_3_ = (_e146 - _e147);
            let _e149 = q_3_;
            let _e150 = _S30_;
            _S36_ = (_e149 / _e150);
            let _e152 = q_3_;
            if (abs(_e152) < 0.000015258789f) {
                t1_1_ = 0f;
            } else {
                let _e155 = _S33_;
                let _e156 = q_3_;
                t1_1_ = (_e155 / _e156);
            }
            let _e158 = t1_1_;
            _S37_ = _e158;
            let _e159 = _S36_;
            t1_1_ = _e159;
            let _e160 = _S37_;
            t2_1_ = _e160;
        }
    }
    let _e162 = a_1_[1u];
    _S38_ = _e162;
    let _e164 = b_2_[1u];
    _S39_ = (_e164 * 2f);
    let _e167 = (*p12_2_)[1u];
    _S40_ = _e167;
    let _e168 = _S38_;
    let _e169 = t1_1_;
    let _e171 = _S39_;
    let _e173 = t1_1_;
    let _e175 = _S40_;
    let _e177 = _S38_;
    let _e178 = t2_1_;
    let _e180 = _S39_;
    let _e182 = t2_1_;
    let _e184 = _S40_;
    return vec2<f32>(((((_e168 * _e169) - _e171) * _e173) + _e175), ((((_e177 * _e178) - _e180) * _e182) + _e184));
}

fn rootCodeCoord_0_u0028_f1_u003b(v_0_: ptr<function, f32>) -> f32 {
    var _S7_: f32;

    let _e64 = (*v_0_);
    if (abs(_e64) <= 0.000015258789f) {
        _S7_ = 0f;
    } else {
        let _e67 = (*v_0_);
        _S7_ = _e67;
    }
    let _e68 = _S7_;
    return _e68;
}

fn calcRootCode_0_u0028_f1_u003b_f1_u003b_f1_u003b(y1_0_: ptr<function, f32>, y2_0_: ptr<function, f32>, y3_0_: ptr<function, f32>) -> u32 {
    var param_12: f32;
    var param_13: f32;
    var param_14: f32;

    let _e68 = (*y3_0_);
    param_12 = _e68;
    let _e69 = rootCodeCoord_0_u0028_f1_u003b((&param_12));
    let _e74 = (*y2_0_);
    param_13 = _e74;
    let _e75 = rootCodeCoord_0_u0028_f1_u003b((&param_13));
    let _e80 = (*y1_0_);
    param_14 = _e80;
    let _e81 = rootCodeCoord_0_u0028_f1_u003b((&param_14));
    return ((11892u >> bitcast<u32>((((bitcast<u32>(_e69) >> bitcast<u32>(29u)) & 4u) | ((((bitcast<u32>(_e75) >> bitcast<u32>(30u)) & 2u) | ((bitcast<u32>(_e81) >> bitcast<u32>(31u)) & 4294967293u)) & 4294967291u)))) & 257u);
}

fn offsetCurveLoc_0_u0028_vi2_u003b_i1_u003b(base_0_: ptr<function, vec2<i32>>, offset_1_: ptr<function, i32>) -> vec2<i32> {
    var _S6_: i32;
    var loc_1_: vec2<i32>;

    let _e67 = (*base_0_)[0u];
    let _e68 = (*offset_1_);
    _S6_ = (_e67 + _e68);
    let _e70 = _S6_;
    let _e72 = (*base_0_)[1u];
    loc_1_ = vec2<i32>(_e70, _e72);
    let _e75 = loc_1_[1u];
    let _e76 = _S6_;
    loc_1_[1u] = (_e75 + (_e76 >> bitcast<u32>(12i)));
    let _e82 = loc_1_[0u];
    loc_1_[0u] = (_e82 & 4095i);
    let _e85 = loc_1_;
    return _e85;
}

fn accumulateSubpixelVert_0_u0028_f1_u003b_f1_u003b_vf2_u003b_vf2_u003b_vi2_u003b_i1_u003b(cov_1_: ptr<function, f32>, wgt_1_: ptr<function, f32>, rc_1_: ptr<function, vec2<f32>>, ppe_1_: ptr<function, vec2<f32>>, c_loc_1_: ptr<function, vec2<i32>>, layer_1_: ptr<function, i32>) -> bool {
    var _S41_: vec4<i32>;
    var _S42_: vec4<f32>;
    var _S43_: vec4<i32>;
    var param_15: vec2<i32>;
    var param_16: i32;
    var p12_3_: vec4<f32>;
    var p3_3_: vec2<f32>;
    var _S44_: f32;
    var code_1_: u32;
    var param_17: f32;
    var param_18: f32;
    var param_19: f32;
    var roots_1_: vec2<f32>;
    var param_20: vec4<f32>;
    var param_21: vec2<f32>;
    var _S45_: f32;
    var _S46_: f32;

    let _e85 = (*c_loc_1_);
    let _e86 = (*layer_1_);
    let _e89 = vec3<i32>(_e85.x, _e85.y, _e86);
    _S41_ = vec4<i32>(_e89.x, _e89.y, _e89.z, 0i);
    let _e94 = _S41_;
    let _e95 = _e94.xyz;
    let _e97 = _S41_[3u];
    let _e103 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e95.x, _e95.y), i32(_e95.z), _e97);
    _S42_ = _e103;
    let _e104 = (*c_loc_1_);
    param_15 = _e104;
    param_16 = 1i;
    let _e105 = offsetCurveLoc_0_u0028_vi2_u003b_i1_u003b((&param_15), (&param_16));
    let _e106 = (*layer_1_);
    let _e109 = vec3<i32>(_e105.x, _e105.y, _e106);
    _S43_ = vec4<i32>(_e109.x, _e109.y, _e109.z, 0i);
    let _e114 = _S42_;
    let _e115 = _e114.xy;
    let _e116 = _S42_;
    let _e117 = _e116.zw;
    let _e123 = (*rc_1_);
    p12_3_ = (vec4<f32>(_e115.x, _e115.y, _e117.x, _e117.y) - vec4<f32>(_e123.x, _e123.y, _e123.x, _e123.y));
    let _e130 = _S43_;
    let _e131 = _e130.xyz;
    let _e133 = _S43_[3u];
    let _e139 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e131.x, _e131.y), i32(_e131.z), _e133);
    let _e141 = (*rc_1_);
    p3_3_ = (_e139.xy - _e141);
    let _e144 = (*ppe_1_)[1u];
    _S44_ = _e144;
    let _e146 = p12_3_[1u];
    let _e148 = p12_3_[3u];
    let _e151 = p3_3_[1u];
    let _e153 = _S44_;
    if ((max(max(_e146, _e148), _e151) * _e153) < -0.5f) {
        return false;
    }
    let _e157 = p12_3_[0u];
    param_17 = _e157;
    let _e159 = p12_3_[2u];
    param_18 = _e159;
    let _e161 = p3_3_[0u];
    param_19 = _e161;
    let _e162 = calcRootCode_0_u0028_f1_u003b_f1_u003b_f1_u003b((&param_17), (&param_18), (&param_19));
    code_1_ = _e162;
    let _e163 = code_1_;
    if (_e163 != 0u) {
        let _e165 = p12_3_;
        param_20 = _e165;
        let _e166 = p3_3_;
        param_21 = _e166;
        let _e167 = solveVertPoly_0_u0028_vf4_u003b_vf2_u003b((&param_20), (&param_21));
        let _e168 = _S44_;
        roots_1_ = (_e167 * _e168);
        let _e170 = code_1_;
        if ((_e170 & 1u) != 0u) {
            let _e174 = roots_1_[0u];
            _S45_ = _e174;
            let _e175 = (*cov_1_);
            let _e176 = _S45_;
            (*cov_1_) = (_e175 - clamp((_e176 + 0.5f), 0f, 1f));
            let _e180 = (*wgt_1_);
            let _e181 = _S45_;
            (*wgt_1_) = max(_e180, clamp((1f - (abs(_e181) * 2f)), 0f, 1f));
        }
        let _e187 = code_1_;
        if (_e187 > 1u) {
            let _e190 = roots_1_[1u];
            _S46_ = _e190;
            let _e191 = (*cov_1_);
            let _e192 = _S46_;
            (*cov_1_) = (_e191 + clamp((_e192 + 0.5f), 0f, 1f));
            let _e196 = (*wgt_1_);
            let _e197 = _S46_;
            (*wgt_1_) = max(_e196, clamp((1f - (abs(_e197) * 2f)), 0f, 1f));
        }
    }
    return true;
}

fn solveHorizPoly_0_u0028_vf4_u003b_vf2_u003b(p12_0_: ptr<function, vec4<f32>>, p3_0_: ptr<function, vec2<f32>>) -> vec2<f32> {
    var _S9_: vec2<f32>;
    var _S10_: vec2<f32>;
    var a_0_: vec2<f32>;
    var b_1_: vec2<f32>;
    var _S11_: f32;
    var _S12_: f32;
    var t1_0_: f32;
    var t2_0_: f32;
    var _S13_: f32;
    var _S14_: f32;
    var _S15_: f32;
    var sq_0_: f32;
    var param_22: f32;
    var param_23: f32;
    var param_24: f32;
    var q_0_: f32;
    var _S16_: f32;
    var q_1_: f32;
    var _S17_: f32;
    var _S18_: f32;
    var _S19_: f32;
    var _S20_: f32;
    var _S21_: f32;

    let _e87 = (*p12_0_);
    _S9_ = _e87.xy;
    let _e89 = (*p12_0_);
    _S10_ = _e89.zw;
    let _e91 = _S9_;
    let _e92 = _S10_;
    let _e95 = (*p3_0_);
    a_0_ = ((_e91 - (_e92 * 2f)) + _e95);
    let _e97 = _S9_;
    let _e98 = _S10_;
    b_1_ = (_e97 - _e98);
    let _e101 = a_0_[1u];
    _S11_ = _e101;
    let _e102 = _S11_;
    if (abs(_e102) < 0.000015258789f) {
        let _e106 = b_1_[1u];
        _S12_ = _e106;
        let _e107 = _S12_;
        if (abs(_e107) < 0.000015258789f) {
            t1_0_ = 0f;
        } else {
            let _e111 = (*p12_0_)[1u];
            let _e113 = _S12_;
            t1_0_ = ((_e111 * 0.5f) / _e113);
        }
        let _e115 = t1_0_;
        t2_0_ = _e115;
    } else {
        let _e117 = b_1_[1u];
        _S13_ = _e117;
        let _e119 = (*p12_0_)[1u];
        _S14_ = _e119;
        let _e120 = _S11_;
        let _e121 = _S14_;
        _S15_ = (_e120 * _e121);
        let _e123 = _S13_;
        let _e124 = _S13_;
        let _e126 = _S15_;
        param_22 = ((_e123 * _e124) - _e126);
        let _e128 = _S13_;
        param_23 = _e128;
        let _e129 = _S15_;
        param_24 = _e129;
        let _e130 = snapNearTangentSqrt_0_u0028_f1_u003b_f1_u003b_f1_u003b((&param_22), (&param_23), (&param_24));
        sq_0_ = _e130;
        let _e131 = _S13_;
        if (_e131 >= 0f) {
            let _e133 = _S13_;
            let _e134 = sq_0_;
            q_0_ = (_e133 + _e134);
            let _e136 = q_0_;
            let _e137 = _S11_;
            _S16_ = (_e136 / _e137);
            let _e139 = q_0_;
            if (abs(_e139) < 0.000015258789f) {
                t1_0_ = 0f;
            } else {
                let _e142 = _S14_;
                let _e143 = q_0_;
                t1_0_ = (_e142 / _e143);
            }
            let _e145 = _S16_;
            t2_0_ = _e145;
        } else {
            let _e146 = _S13_;
            let _e147 = sq_0_;
            q_1_ = (_e146 - _e147);
            let _e149 = q_1_;
            let _e150 = _S11_;
            _S17_ = (_e149 / _e150);
            let _e152 = q_1_;
            if (abs(_e152) < 0.000015258789f) {
                t1_0_ = 0f;
            } else {
                let _e155 = _S14_;
                let _e156 = q_1_;
                t1_0_ = (_e155 / _e156);
            }
            let _e158 = t1_0_;
            _S18_ = _e158;
            let _e159 = _S17_;
            t1_0_ = _e159;
            let _e160 = _S18_;
            t2_0_ = _e160;
        }
    }
    let _e162 = a_0_[0u];
    _S19_ = _e162;
    let _e164 = b_1_[0u];
    _S20_ = (_e164 * 2f);
    let _e167 = (*p12_0_)[0u];
    _S21_ = _e167;
    let _e168 = _S19_;
    let _e169 = t1_0_;
    let _e171 = _S20_;
    let _e173 = t1_0_;
    let _e175 = _S21_;
    let _e177 = _S19_;
    let _e178 = t2_0_;
    let _e180 = _S20_;
    let _e182 = t2_0_;
    let _e184 = _S21_;
    return vec2<f32>(((((_e168 * _e169) - _e171) * _e173) + _e175), ((((_e177 * _e178) - _e180) * _e182) + _e184));
}

fn accumulateSubpixelHoriz_0_u0028_f1_u003b_f1_u003b_vf2_u003b_vf2_u003b_vi2_u003b_i1_u003b(cov_0_: ptr<function, f32>, wgt_0_: ptr<function, f32>, rc_0_: ptr<function, vec2<f32>>, ppe_0_: ptr<function, vec2<f32>>, c_loc_0_: ptr<function, vec2<i32>>, layer_0_: ptr<function, i32>) -> bool {
    var _S22_: vec4<i32>;
    var _S23_: vec4<f32>;
    var _S24_: vec4<i32>;
    var param_25: vec2<i32>;
    var param_26: i32;
    var p12_1_: vec4<f32>;
    var p3_1_: vec2<f32>;
    var _S25_: f32;
    var code_0_: u32;
    var param_27: f32;
    var param_28: f32;
    var param_29: f32;
    var roots_0_: vec2<f32>;
    var param_30: vec4<f32>;
    var param_31: vec2<f32>;
    var _S26_: f32;
    var _S27_: f32;

    let _e85 = (*c_loc_0_);
    let _e86 = (*layer_0_);
    let _e89 = vec3<i32>(_e85.x, _e85.y, _e86);
    _S22_ = vec4<i32>(_e89.x, _e89.y, _e89.z, 0i);
    let _e94 = _S22_;
    let _e95 = _e94.xyz;
    let _e97 = _S22_[3u];
    let _e103 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e95.x, _e95.y), i32(_e95.z), _e97);
    _S23_ = _e103;
    let _e104 = (*c_loc_0_);
    param_25 = _e104;
    param_26 = 1i;
    let _e105 = offsetCurveLoc_0_u0028_vi2_u003b_i1_u003b((&param_25), (&param_26));
    let _e106 = (*layer_0_);
    let _e109 = vec3<i32>(_e105.x, _e105.y, _e106);
    _S24_ = vec4<i32>(_e109.x, _e109.y, _e109.z, 0i);
    let _e114 = _S23_;
    let _e115 = _e114.xy;
    let _e116 = _S23_;
    let _e117 = _e116.zw;
    let _e123 = (*rc_0_);
    p12_1_ = (vec4<f32>(_e115.x, _e115.y, _e117.x, _e117.y) - vec4<f32>(_e123.x, _e123.y, _e123.x, _e123.y));
    let _e130 = _S24_;
    let _e131 = _e130.xyz;
    let _e133 = _S24_[3u];
    let _e139 = textureLoad(u_curve_tex_0_image, vec2<i32>(_e131.x, _e131.y), i32(_e131.z), _e133);
    let _e141 = (*rc_0_);
    p3_1_ = (_e139.xy - _e141);
    let _e144 = (*ppe_0_)[0u];
    _S25_ = _e144;
    let _e146 = p12_1_[0u];
    let _e148 = p12_1_[2u];
    let _e151 = p3_1_[0u];
    let _e153 = _S25_;
    if ((max(max(_e146, _e148), _e151) * _e153) < -0.5f) {
        return false;
    }
    let _e157 = p12_1_[1u];
    param_27 = _e157;
    let _e159 = p12_1_[3u];
    param_28 = _e159;
    let _e161 = p3_1_[1u];
    param_29 = _e161;
    let _e162 = calcRootCode_0_u0028_f1_u003b_f1_u003b_f1_u003b((&param_27), (&param_28), (&param_29));
    code_0_ = _e162;
    let _e163 = code_0_;
    if (_e163 != 0u) {
        let _e165 = p12_1_;
        param_30 = _e165;
        let _e166 = p3_1_;
        param_31 = _e166;
        let _e167 = solveHorizPoly_0_u0028_vf4_u003b_vf2_u003b((&param_30), (&param_31));
        let _e168 = _S25_;
        roots_0_ = (_e167 * _e168);
        let _e170 = code_0_;
        if ((_e170 & 1u) != 0u) {
            let _e174 = roots_0_[0u];
            _S26_ = _e174;
            let _e175 = (*cov_0_);
            let _e176 = _S26_;
            (*cov_0_) = (_e175 + clamp((_e176 + 0.5f), 0f, 1f));
            let _e180 = (*wgt_0_);
            let _e181 = _S26_;
            (*wgt_0_) = max(_e180, clamp((1f - (abs(_e181) * 2f)), 0f, 1f));
        }
        let _e187 = code_0_;
        if (_e187 > 1u) {
            let _e190 = roots_0_[1u];
            _S27_ = _e190;
            let _e191 = (*cov_0_);
            let _e192 = _S27_;
            (*cov_0_) = (_e191 - clamp((_e192 + 0.5f), 0f, 1f));
            let _e196 = (*wgt_0_);
            let _e197 = _S27_;
            (*wgt_0_) = max(_e196, clamp((1f - (abs(_e197) * 2f)), 0f, 1f));
        }
    }
    return true;
}

fn decodeBandCurveLocCommon_0_u0028_vu2_u003b(ref_2_: ptr<function, vec2<u32>>) -> vec2<i32> {
    let _e64 = (*ref_2_)[0u];
    let _e68 = (*ref_2_)[1u];
    return vec2<i32>(bitcast<i32>((_e64 & 4095u)), bitcast<i32>((_e68 & 16383u)));
}

fn decodeBandCurveLoc_0_u0028_vu2_u003b(ref_3_: ptr<function, vec2<u32>>) -> vec2<i32> {
    var param_32: vec2<u32>;

    let _e64 = (*ref_3_);
    param_32 = _e64;
    let _e65 = decodeBandCurveLocCommon_0_u0028_vu2_u003b((&param_32));
    return _e65;
}

fn decodeBandCurveFirstMemberCommon_0_u0028_vu2_u003b(ref_0_: ptr<function, vec2<u32>>) -> i32 {
    let _e64 = (*ref_0_)[0u];
    return bitcast<i32>((_e64 >> bitcast<u32>(12u)));
}

fn isCoverageBandSpanOwner_0_u0028_vu2_u003b_i1_u003b_i1_u003b(ref_1_: ptr<function, vec2<u32>>, band_0_: ptr<function, i32>, spanFirst_0_: ptr<function, i32>) -> bool {
    var param_33: vec2<u32>;

    let _e66 = (*band_0_);
    let _e67 = (*ref_1_);
    param_33 = _e67;
    let _e68 = decodeBandCurveFirstMemberCommon_0_u0028_vu2_u003b((&param_33));
    let _e69 = (*spanFirst_0_);
    return (_e66 == max(_e68, _e69));
}

fn calcBandLoc_0_u0028_vi2_u003b_u1_u003b(glyphLoc_0_: ptr<function, vec2<i32>>, offset_0_: ptr<function, u32>) -> vec2<i32> {
    var _S5_: i32;
    var loc_0_: vec2<i32>;

    let _e67 = (*glyphLoc_0_)[0u];
    let _e68 = (*offset_0_);
    _S5_ = (_e67 + bitcast<i32>(_e68));
    let _e71 = _S5_;
    let _e73 = (*glyphLoc_0_)[1u];
    loc_0_ = vec2<i32>(_e71, _e73);
    let _e76 = loc_0_[1u];
    let _e77 = _S5_;
    loc_0_[1u] = (_e76 + (_e77 >> bitcast<u32>(12i)));
    let _e83 = loc_0_[0u];
    loc_0_[0u] = (_e83 & 4095i);
    let _e86 = loc_0_;
    return _e86;
}

fn CoverageBandSpan_x24init_0_u0028_i1_u003b_i1_u003b(first_1_: ptr<function, i32>, last_1_: ptr<function, i32>) -> CoverageBandSpan_0_ {
    var _S3_: CoverageBandSpan_0_;

    let _e65 = (*first_1_);
    _S3_.first_0_ = _e65;
    let _e67 = (*last_1_);
    _S3_.last_0_ = _e67;
    let _e69 = _S3_;
    return _e69;
}

fn computeCoverageBandSpan_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_i1_u003b(coord_0_: ptr<function, f32>, eppAxis_0_: ptr<function, f32>, bandScale_0_: ptr<function, f32>, bandOffset_0_: ptr<function, f32>, bandMax_0_: ptr<function, i32>) -> CoverageBandSpan_0_ {
    var center_0_: f32;
    var _S4_: f32;
    var first_2_: i32;
    var param_34: i32;
    var param_35: i32;

    let _e72 = (*coord_0_);
    let _e73 = (*bandScale_0_);
    let _e75 = (*bandOffset_0_);
    center_0_ = ((_e72 * _e73) + _e75);
    let _e77 = (*eppAxis_0_);
    let _e78 = (*bandScale_0_);
    _S4_ = max((abs((_e77 * _e78)) * 0.5f), 0.00001f);
    let _e83 = center_0_;
    let _e84 = _S4_;
    let _e87 = (*bandMax_0_);
    first_2_ = clamp(i32((_e83 - _e84)), 0i, _e87);
    let _e89 = first_2_;
    let _e90 = center_0_;
    let _e91 = _S4_;
    let _e94 = (*bandMax_0_);
    let _e97 = first_2_;
    param_34 = _e97;
    param_35 = max(_e89, clamp(i32((_e90 + _e91)), 0i, _e94));
    let _e98 = CoverageBandSpan_x24init_0_u0028_i1_u003b_i1_u003b((&param_34), (&param_35));
    return _e98;
}

fn evalGlyphCoverage_0_u0028_vf2_u003b_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b(rc_2_: ptr<function, vec2<f32>>, epp_0_: ptr<function, vec2<f32>>, ppe_2_: ptr<function, vec2<f32>>, glyph_loc_0_: ptr<function, vec2<i32>>, band_max_0_: ptr<function, vec2<i32>>, banding_0_: ptr<function, vec4<f32>>, layer_2_: ptr<function, i32>) -> f32 {
    var _S48_: i32;
    var hSpan_0_: CoverageBandSpan_0_;
    var param_36: f32;
    var param_37: f32;
    var param_38: f32;
    var param_39: f32;
    var param_40: i32;
    var vSpan_0_: CoverageBandSpan_0_;
    var param_41: f32;
    var param_42: f32;
    var param_43: f32;
    var param_44: f32;
    var param_45: i32;
    var xcov_0_: f32;
    var xwgt_0_: f32;
    var _S49_: bool;
    var band_1_: i32;
    var _S50_: vec4<i32>;
    var param_46: vec2<i32>;
    var param_47: u32;
    var hbd_0_: vec2<u32>;
    var _S51_: vec2<i32>;
    var param_48: vec2<i32>;
    var param_49: u32;
    var _S52_: i32;
    var i_0_: i32;
    var _S53_: vec4<i32>;
    var param_50: vec2<i32>;
    var param_51: u32;
    var ref_4_: vec2<u32>;
    var _S47_: bool;
    var param_52: vec2<u32>;
    var param_53: i32;
    var param_54: i32;
    var _S54_: bool;
    var param_55: vec2<u32>;
    var param_56: f32;
    var param_57: f32;
    var param_58: vec2<f32>;
    var param_59: vec2<f32>;
    var param_60: vec2<i32>;
    var param_61: i32;
    var ycov_0_: f32;
    var ywgt_0_: f32;
    var _S55_: bool;
    var _S56_: vec4<i32>;
    var param_62: vec2<i32>;
    var param_63: u32;
    var vbd_0_: vec2<u32>;
    var _S57_: vec2<i32>;
    var param_64: vec2<i32>;
    var param_65: u32;
    var _S58_: i32;
    var _S59_: vec4<i32>;
    var param_66: vec2<i32>;
    var param_67: u32;
    var ref_5_: vec2<u32>;
    var param_68: vec2<u32>;
    var param_69: i32;
    var param_70: i32;
    var _S60_: bool;
    var param_71: vec2<u32>;
    var param_72: f32;
    var param_73: f32;
    var param_74: vec2<f32>;
    var param_75: vec2<f32>;
    var param_76: vec2<i32>;
    var param_77: i32;
    var param_78: f32;
    var param_79: i32;
    var param_80: f32;
    var param_81: i32;
    var param_82: f32;
    var param_83: i32;

    let _e144 = (*band_max_0_)[1u];
    _S48_ = _e144;
    let _e146 = (*rc_2_)[1u];
    param_36 = _e146;
    let _e148 = (*epp_0_)[1u];
    param_37 = _e148;
    let _e150 = (*banding_0_)[1u];
    param_38 = _e150;
    let _e152 = (*banding_0_)[3u];
    param_39 = _e152;
    let _e153 = _S48_;
    param_40 = _e153;
    let _e154 = computeCoverageBandSpan_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_i1_u003b((&param_36), (&param_37), (&param_38), (&param_39), (&param_40));
    hSpan_0_ = _e154;
    let _e156 = (*rc_2_)[0u];
    param_41 = _e156;
    let _e158 = (*epp_0_)[0u];
    param_42 = _e158;
    let _e160 = (*banding_0_)[0u];
    param_43 = _e160;
    let _e162 = (*banding_0_)[2u];
    param_44 = _e162;
    let _e164 = (*band_max_0_)[0u];
    param_45 = _e164;
    let _e165 = computeCoverageBandSpan_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_i1_u003b((&param_41), (&param_42), (&param_43), (&param_44), (&param_45));
    vSpan_0_ = _e165;
    xcov_0_ = 0f;
    xwgt_0_ = 0f;
    let _e167 = hSpan_0_.first_0_;
    let _e169 = hSpan_0_.last_0_;
    _S49_ = (_e167 != _e169);
    let _e172 = hSpan_0_.first_0_;
    band_1_ = _e172;
    loop {
        let _e173 = band_1_;
        let _e175 = hSpan_0_.last_0_;
        if (_e173 <= _e175) {
        } else {
            break;
        }
        let _e177 = band_1_;
        let _e179 = (*glyph_loc_0_);
        param_46 = _e179;
        param_47 = bitcast<u32>(_e177);
        let _e180 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b((&param_46), (&param_47));
        let _e181 = (*layer_2_);
        let _e184 = vec3<i32>(_e180.x, _e180.y, _e181);
        _S50_ = vec4<i32>(_e184.x, _e184.y, _e184.z, 0i);
        let _e189 = _S50_;
        let _e190 = _e189.xyz;
        let _e192 = _S50_[3u];
        let _e198 = textureLoad(u_band_tex_0_image, vec2<i32>(_e190.x, _e190.y), i32(_e190.z), _e192);
        hbd_0_ = _e198.xy;
        let _e200 = (*glyph_loc_0_);
        param_48 = _e200;
        let _e202 = hbd_0_[1u];
        param_49 = _e202;
        let _e203 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b((&param_48), (&param_49));
        _S51_ = _e203;
        let _e205 = hbd_0_[0u];
        _S52_ = bitcast<i32>(_e205);
        i_0_ = 0i;
        loop {
            let _e207 = i_0_;
            let _e208 = _S52_;
            if (_e207 < _e208) {
            } else {
                break;
            }
            let _e210 = i_0_;
            let _e212 = _S51_;
            param_50 = _e212;
            param_51 = bitcast<u32>(_e210);
            let _e213 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b((&param_50), (&param_51));
            let _e214 = (*layer_2_);
            let _e217 = vec3<i32>(_e213.x, _e213.y, _e214);
            _S53_ = vec4<i32>(_e217.x, _e217.y, _e217.z, 0i);
            let _e222 = _S53_;
            let _e223 = _e222.xyz;
            let _e225 = _S53_[3u];
            let _e231 = textureLoad(u_band_tex_0_image, vec2<i32>(_e223.x, _e223.y), i32(_e223.z), _e225);
            ref_4_ = _e231.xy;
            let _e233 = _S49_;
            if _e233 {
                let _e234 = ref_4_;
                param_52 = _e234;
                let _e235 = band_1_;
                param_53 = _e235;
                let _e237 = hSpan_0_.first_0_;
                param_54 = _e237;
                let _e238 = isCoverageBandSpanOwner_0_u0028_vu2_u003b_i1_u003b_i1_u003b((&param_52), (&param_53), (&param_54));
                _S47_ = !(_e238);
            } else {
                _S47_ = false;
            }
            let _e240 = _S47_;
            if _e240 {
                let _e241 = i_0_;
                i_0_ = (_e241 + 1i);
                continue;
            }
            let _e243 = ref_4_;
            param_55 = _e243;
            let _e244 = decodeBandCurveLoc_0_u0028_vu2_u003b((&param_55));
            let _e245 = xcov_0_;
            param_56 = _e245;
            let _e246 = xwgt_0_;
            param_57 = _e246;
            let _e247 = (*rc_2_);
            param_58 = _e247;
            let _e248 = (*ppe_2_);
            param_59 = _e248;
            param_60 = _e244;
            let _e249 = (*layer_2_);
            param_61 = _e249;
            let _e250 = accumulateSubpixelHoriz_0_u0028_f1_u003b_f1_u003b_vf2_u003b_vf2_u003b_vi2_u003b_i1_u003b((&param_56), (&param_57), (&param_58), (&param_59), (&param_60), (&param_61));
            let _e251 = param_56;
            xcov_0_ = _e251;
            let _e252 = param_57;
            xwgt_0_ = _e252;
            _S54_ = _e250;
            let _e253 = _S54_;
            if !(_e253) {
                break;
            }
            let _e255 = i_0_;
            i_0_ = (_e255 + 1i);
            continue;
        }
        let _e257 = band_1_;
        band_1_ = (_e257 + 1i);
        continue;
    }
    ycov_0_ = 0f;
    ywgt_0_ = 0f;
    let _e260 = vSpan_0_.first_0_;
    let _e262 = vSpan_0_.last_0_;
    _S55_ = (_e260 != _e262);
    let _e265 = vSpan_0_.first_0_;
    band_1_ = _e265;
    loop {
        let _e266 = band_1_;
        let _e268 = vSpan_0_.last_0_;
        if (_e266 <= _e268) {
        } else {
            break;
        }
        let _e270 = _S48_;
        let _e272 = band_1_;
        let _e275 = (*glyph_loc_0_);
        param_62 = _e275;
        param_63 = bitcast<u32>(((_e270 + 1i) + _e272));
        let _e276 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b((&param_62), (&param_63));
        let _e277 = (*layer_2_);
        let _e280 = vec3<i32>(_e276.x, _e276.y, _e277);
        _S56_ = vec4<i32>(_e280.x, _e280.y, _e280.z, 0i);
        let _e285 = _S56_;
        let _e286 = _e285.xyz;
        let _e288 = _S56_[3u];
        let _e294 = textureLoad(u_band_tex_0_image, vec2<i32>(_e286.x, _e286.y), i32(_e286.z), _e288);
        vbd_0_ = _e294.xy;
        let _e296 = (*glyph_loc_0_);
        param_64 = _e296;
        let _e298 = vbd_0_[1u];
        param_65 = _e298;
        let _e299 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b((&param_64), (&param_65));
        _S57_ = _e299;
        let _e301 = vbd_0_[0u];
        _S58_ = bitcast<i32>(_e301);
        i_0_ = 0i;
        loop {
            let _e303 = i_0_;
            let _e304 = _S58_;
            if (_e303 < _e304) {
            } else {
                break;
            }
            let _e306 = i_0_;
            let _e308 = _S57_;
            param_66 = _e308;
            param_67 = bitcast<u32>(_e306);
            let _e309 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b((&param_66), (&param_67));
            let _e310 = (*layer_2_);
            let _e313 = vec3<i32>(_e309.x, _e309.y, _e310);
            _S59_ = vec4<i32>(_e313.x, _e313.y, _e313.z, 0i);
            let _e318 = _S59_;
            let _e319 = _e318.xyz;
            let _e321 = _S59_[3u];
            let _e327 = textureLoad(u_band_tex_0_image, vec2<i32>(_e319.x, _e319.y), i32(_e319.z), _e321);
            ref_5_ = _e327.xy;
            let _e329 = _S55_;
            if _e329 {
                let _e330 = ref_5_;
                param_68 = _e330;
                let _e331 = band_1_;
                param_69 = _e331;
                let _e333 = vSpan_0_.first_0_;
                param_70 = _e333;
                let _e334 = isCoverageBandSpanOwner_0_u0028_vu2_u003b_i1_u003b_i1_u003b((&param_68), (&param_69), (&param_70));
                _S47_ = !(_e334);
            } else {
                _S47_ = false;
            }
            let _e336 = _S47_;
            if _e336 {
                let _e337 = i_0_;
                i_0_ = (_e337 + 1i);
                continue;
            }
            let _e339 = ref_5_;
            param_71 = _e339;
            let _e340 = decodeBandCurveLoc_0_u0028_vu2_u003b((&param_71));
            let _e341 = ycov_0_;
            param_72 = _e341;
            let _e342 = ywgt_0_;
            param_73 = _e342;
            let _e343 = (*rc_2_);
            param_74 = _e343;
            let _e344 = (*ppe_2_);
            param_75 = _e344;
            param_76 = _e340;
            let _e345 = (*layer_2_);
            param_77 = _e345;
            let _e346 = accumulateSubpixelVert_0_u0028_f1_u003b_f1_u003b_vf2_u003b_vf2_u003b_vi2_u003b_i1_u003b((&param_72), (&param_73), (&param_74), (&param_75), (&param_76), (&param_77));
            let _e347 = param_72;
            ycov_0_ = _e347;
            let _e348 = param_73;
            ywgt_0_ = _e348;
            _S60_ = _e346;
            let _e349 = _S60_;
            if !(_e349) {
                break;
            }
            let _e351 = i_0_;
            i_0_ = (_e351 + 1i);
            continue;
        }
        let _e353 = band_1_;
        band_1_ = (_e353 + 1i);
        continue;
    }
    let _e355 = xcov_0_;
    let _e356 = xwgt_0_;
    let _e358 = ycov_0_;
    let _e359 = ywgt_0_;
    let _e362 = xwgt_0_;
    let _e363 = ywgt_0_;
    param_78 = (((_e355 * _e356) + (_e358 * _e359)) / max((_e362 + _e363), 0.000015258789f));
    param_79 = 0i;
    let _e367 = applyFillRule_0_u0028_f1_u003b_i1_u003b((&param_78), (&param_79));
    let _e368 = xcov_0_;
    param_80 = _e368;
    param_81 = 0i;
    let _e369 = applyFillRule_0_u0028_f1_u003b_i1_u003b((&param_80), (&param_81));
    let _e370 = ycov_0_;
    param_82 = _e370;
    param_83 = 0i;
    let _e371 = applyFillRule_0_u0028_f1_u003b_i1_u003b((&param_82), (&param_83));
    return clamp(max(_e367, min(_e369, _e371)), 0f, 1f);
}

fn evalGlyphSample_0_u0028_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b(rc_3_: ptr<function, vec2<f32>>, display_epp_0_: ptr<function, vec2<f32>>, glyph_loc_1_: ptr<function, vec2<i32>>, band_max_1_: ptr<function, vec2<i32>>, banding_1_: ptr<function, vec4<f32>>, layer_3_: ptr<function, i32>) -> f32 {
    var param_84: vec2<f32>;
    var param_85: vec2<f32>;
    var param_86: vec2<f32>;
    var param_87: vec2<i32>;
    var param_88: vec2<i32>;
    var param_89: vec4<f32>;
    var param_90: i32;

    let _e76 = (*display_epp_0_)[0u];
    let _e80 = (*display_epp_0_)[1u];
    let _e84 = (*rc_3_);
    param_84 = _e84;
    let _e85 = (*display_epp_0_);
    param_85 = _e85;
    param_86 = vec2<f32>((1f / max(_e76, 0.000015258789f)), (1f / max(_e80, 0.000015258789f)));
    let _e86 = (*glyph_loc_1_);
    param_87 = _e86;
    let _e87 = (*band_max_1_);
    param_88 = _e87;
    let _e88 = (*banding_1_);
    param_89 = _e88;
    let _e89 = (*layer_3_);
    param_90 = _e89;
    let _e90 = evalGlyphCoverage_0_u0028_vf2_u003b_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b((&param_84), (&param_85), (&param_86), (&param_87), (&param_88), (&param_89), (&param_90));
    return _e90;
}

fn subpixelCoverageEdgePixels_0_u0028_vf2_u003b_vf2_u003b(display_dx_0_: ptr<function, vec2<f32>>, display_dy_0_: ptr<function, vec2<f32>>) -> vec2<f32> {
    var dx_0_: vec2<f32>;
    var dy_0_: vec2<f32>;
    var _S2_: vec2<f32>;

    let _e67 = (*display_dx_0_);
    dx_0_ = abs(_e67);
    let _e69 = (*display_dy_0_);
    dy_0_ = abs(_e69);
    let _e72 = PushConstants_0_.subpixel_order_0_;
    if (_e72 <= 2i) {
        let _e74 = dx_0_;
        let _e76 = dy_0_;
        _S2_ = ((_e74 * 0.33333334f) + _e76);
    } else {
        let _e78 = dx_0_;
        let _e79 = dy_0_;
        _S2_ = (_e78 + (_e79 * 0.33333334f));
    }
    let _e82 = _S2_;
    return _e82;
}

fn evalGlyphCoverageSubpixel_0_u0028_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b(rc_4_: ptr<function, vec2<f32>>, glyph_loc_2_: ptr<function, vec2<i32>>, band_max_2_: ptr<function, vec2<i32>>, banding_2_: ptr<function, vec4<f32>>, layer_4_: ptr<function, i32>) -> vec4<f32> {
    var _S64_: vec2<f32>;
    var _S65_: vec2<f32>;
    var _S66_: vec2<f32>;
    var sample_step_0_: vec2<f32>;
    var display_epp_1_: vec2<f32>;
    var param_91: vec2<f32>;
    var param_92: vec2<f32>;
    var _S67_: vec2<f32>;
    var _S68_: vec2<f32>;
    var s_m3_1_: f32;
    var param_93: vec2<f32>;
    var param_94: vec2<f32>;
    var param_95: vec2<i32>;
    var param_96: vec2<i32>;
    var param_97: vec4<f32>;
    var param_98: i32;
    var s_m2_1_: f32;
    var param_99: vec2<f32>;
    var param_100: vec2<f32>;
    var param_101: vec2<i32>;
    var param_102: vec2<i32>;
    var param_103: vec4<f32>;
    var param_104: i32;
    var s_m1_1_: f32;
    var param_105: vec2<f32>;
    var param_106: vec2<f32>;
    var param_107: vec2<i32>;
    var param_108: vec2<i32>;
    var param_109: vec4<f32>;
    var param_110: i32;
    var s_0_1_: f32;
    var param_111: vec2<f32>;
    var param_112: vec2<f32>;
    var param_113: vec2<i32>;
    var param_114: vec2<i32>;
    var param_115: vec4<f32>;
    var param_116: i32;
    var s_p1_1_: f32;
    var param_117: vec2<f32>;
    var param_118: vec2<f32>;
    var param_119: vec2<i32>;
    var param_120: vec2<i32>;
    var param_121: vec4<f32>;
    var param_122: i32;
    var s_p2_1_: f32;
    var param_123: vec2<f32>;
    var param_124: vec2<f32>;
    var param_125: vec2<i32>;
    var param_126: vec2<i32>;
    var param_127: vec4<f32>;
    var param_128: i32;
    var s_p3_1_: f32;
    var param_129: vec2<f32>;
    var param_130: vec2<f32>;
    var param_131: vec2<i32>;
    var param_132: vec2<i32>;
    var param_133: vec4<f32>;
    var param_134: i32;
    var _S69_: bool;
    var coverage_0_: vec4<f32>;
    var param_135: f32;
    var param_136: f32;
    var param_137: f32;
    var param_138: f32;
    var param_139: f32;
    var param_140: f32;
    var param_141: f32;
    var param_142: bool;
    var param_143: vec3<f32>;
    var param_144: f32;

    let _e137 = (*rc_4_);
    let _e138 = dpdx(_e137);
    _S64_ = _e138;
    let _e139 = (*rc_4_);
    let _e140 = dpdy(_e139);
    _S65_ = _e140;
    let _e142 = PushConstants_0_.subpixel_order_0_;
    if (_e142 <= 2i) {
        let _e144 = _S64_;
        _S66_ = _e144;
    } else {
        let _e145 = _S65_;
        _S66_ = _e145;
    }
    let _e146 = _S66_;
    sample_step_0_ = (_e146 * 0.33333334f);
    let _e148 = _S64_;
    param_91 = _e148;
    let _e149 = _S65_;
    param_92 = _e149;
    let _e150 = subpixelCoverageEdgePixels_0_u0028_vf2_u003b_vf2_u003b((&param_91), (&param_92));
    display_epp_1_ = _e150;
    let _e151 = sample_step_0_;
    _S67_ = (_e151 * 3f);
    let _e153 = sample_step_0_;
    _S68_ = (_e153 * 2f);
    let _e155 = (*rc_4_);
    let _e156 = _S67_;
    param_93 = (_e155 - _e156);
    let _e158 = display_epp_1_;
    param_94 = _e158;
    let _e159 = (*glyph_loc_2_);
    param_95 = _e159;
    let _e160 = (*band_max_2_);
    param_96 = _e160;
    let _e161 = (*banding_2_);
    param_97 = _e161;
    let _e162 = (*layer_4_);
    param_98 = _e162;
    let _e163 = evalGlyphSample_0_u0028_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b((&param_93), (&param_94), (&param_95), (&param_96), (&param_97), (&param_98));
    s_m3_1_ = _e163;
    let _e164 = (*rc_4_);
    let _e165 = _S68_;
    param_99 = (_e164 - _e165);
    let _e167 = display_epp_1_;
    param_100 = _e167;
    let _e168 = (*glyph_loc_2_);
    param_101 = _e168;
    let _e169 = (*band_max_2_);
    param_102 = _e169;
    let _e170 = (*banding_2_);
    param_103 = _e170;
    let _e171 = (*layer_4_);
    param_104 = _e171;
    let _e172 = evalGlyphSample_0_u0028_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b((&param_99), (&param_100), (&param_101), (&param_102), (&param_103), (&param_104));
    s_m2_1_ = _e172;
    let _e173 = (*rc_4_);
    let _e174 = sample_step_0_;
    param_105 = (_e173 - _e174);
    let _e176 = display_epp_1_;
    param_106 = _e176;
    let _e177 = (*glyph_loc_2_);
    param_107 = _e177;
    let _e178 = (*band_max_2_);
    param_108 = _e178;
    let _e179 = (*banding_2_);
    param_109 = _e179;
    let _e180 = (*layer_4_);
    param_110 = _e180;
    let _e181 = evalGlyphSample_0_u0028_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b((&param_105), (&param_106), (&param_107), (&param_108), (&param_109), (&param_110));
    s_m1_1_ = _e181;
    let _e182 = (*rc_4_);
    param_111 = _e182;
    let _e183 = display_epp_1_;
    param_112 = _e183;
    let _e184 = (*glyph_loc_2_);
    param_113 = _e184;
    let _e185 = (*band_max_2_);
    param_114 = _e185;
    let _e186 = (*banding_2_);
    param_115 = _e186;
    let _e187 = (*layer_4_);
    param_116 = _e187;
    let _e188 = evalGlyphSample_0_u0028_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b((&param_111), (&param_112), (&param_113), (&param_114), (&param_115), (&param_116));
    s_0_1_ = _e188;
    let _e189 = (*rc_4_);
    let _e190 = sample_step_0_;
    param_117 = (_e189 + _e190);
    let _e192 = display_epp_1_;
    param_118 = _e192;
    let _e193 = (*glyph_loc_2_);
    param_119 = _e193;
    let _e194 = (*band_max_2_);
    param_120 = _e194;
    let _e195 = (*banding_2_);
    param_121 = _e195;
    let _e196 = (*layer_4_);
    param_122 = _e196;
    let _e197 = evalGlyphSample_0_u0028_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b((&param_117), (&param_118), (&param_119), (&param_120), (&param_121), (&param_122));
    s_p1_1_ = _e197;
    let _e198 = (*rc_4_);
    let _e199 = _S68_;
    param_123 = (_e198 + _e199);
    let _e201 = display_epp_1_;
    param_124 = _e201;
    let _e202 = (*glyph_loc_2_);
    param_125 = _e202;
    let _e203 = (*band_max_2_);
    param_126 = _e203;
    let _e204 = (*banding_2_);
    param_127 = _e204;
    let _e205 = (*layer_4_);
    param_128 = _e205;
    let _e206 = evalGlyphSample_0_u0028_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b((&param_123), (&param_124), (&param_125), (&param_126), (&param_127), (&param_128));
    s_p2_1_ = _e206;
    let _e207 = (*rc_4_);
    let _e208 = _S67_;
    param_129 = (_e207 + _e208);
    let _e210 = display_epp_1_;
    param_130 = _e210;
    let _e211 = (*glyph_loc_2_);
    param_131 = _e211;
    let _e212 = (*band_max_2_);
    param_132 = _e212;
    let _e213 = (*banding_2_);
    param_133 = _e213;
    let _e214 = (*layer_4_);
    param_134 = _e214;
    let _e215 = evalGlyphSample_0_u0028_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b((&param_129), (&param_130), (&param_131), (&param_132), (&param_133), (&param_134));
    s_p3_1_ = _e215;
    let _e217 = PushConstants_0_.subpixel_order_0_;
    if (_e217 == 2i) {
        _S69_ = true;
    } else {
        let _e220 = PushConstants_0_.subpixel_order_0_;
        _S69_ = (_e220 == 4i);
    }
    let _e222 = s_m3_1_;
    param_135 = _e222;
    let _e223 = s_m2_1_;
    param_136 = _e223;
    let _e224 = s_m1_1_;
    param_137 = _e224;
    let _e225 = s_0_1_;
    param_138 = _e225;
    let _e226 = s_p1_1_;
    param_139 = _e226;
    let _e227 = s_p2_1_;
    param_140 = _e227;
    let _e228 = s_p3_1_;
    param_141 = _e228;
    let _e229 = _S69_;
    param_142 = _e229;
    let _e230 = filterSubpixelCoverage_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_b1_u003b((&param_135), (&param_136), (&param_137), (&param_138), (&param_139), (&param_140), (&param_141), (&param_142));
    coverage_0_ = _e230;
    let _e231 = coverage_0_;
    param_143 = _e231.xyz;
    let _e233 = applyCoverageTransfer_1_u0028_vf3_u003b((&param_143));
    let _e235 = coverage_0_[3u];
    param_144 = _e235;
    let _e236 = applyCoverageTransfer_0_u0028_f1_u003b((&param_144));
    return vec4<f32>(_e233.x, _e233.y, _e233.z, _e236);
}

fn snailSubpixelFragment_0_u0028_() {
    var layer_byte_0_: i32;
    var cov_alpha_0_: vec4<f32>;
    var param_145: vec2<f32>;
    var param_146: vec2<i32>;
    var param_147: vec2<i32>;
    var param_148: vec4<f32>;
    var param_149: i32;
    var cov_8_: vec3<f32>;
    var param_150: vec4<f32>;
    var param_151: vec3<f32>;
    var param_152: f32;

    _S1_ = vec4<f32>(0f, 0f, 0f, 0f);
    let _e74 = v_glyph_0_1[3u];
    layer_byte_0_ = ((_e74 >> bitcast<u32>(8i)) & 255i);
    let _e78 = layer_byte_0_;
    if (_e78 == 255i) {
        discard;
    }
    let _e81 = v_glyph_0_1[3u];
    let _e84 = v_glyph_0_1[2u];
    let _e87 = PushConstants_0_.layer_base_0_;
    let _e88 = layer_byte_0_;
    let _e90 = v_texcoord_0_1;
    param_145 = _e90;
    let _e91 = v_glyph_0_1;
    param_146 = _e91.xy;
    param_147 = vec2<i32>((_e81 & 255i), _e84);
    let _e93 = v_banding_0_1;
    param_148 = _e93;
    param_149 = (_e87 + _e88);
    let _e94 = evalGlyphCoverageSubpixel_0_u0028_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b((&param_145), (&param_146), (&param_147), (&param_148), (&param_149));
    cov_alpha_0_ = _e94;
    let _e95 = cov_alpha_0_;
    cov_8_ = _e95.xyz;
    let _e98 = cov_8_[0u];
    let _e100 = cov_8_[1u];
    let _e103 = cov_8_[2u];
    if (max(max(_e98, _e100), _e103) < 0.003921569f) {
        discard;
    }
    let _e106 = v_color_0_1;
    let _e107 = v_tint_0_1;
    param_150 = (_e106 * _e107);
    let _e109 = cov_8_;
    param_151 = _e109;
    let _e111 = cov_alpha_0_[3u];
    param_152 = _e111;
    emitSubpixelColor_0_u0028_vf4_u003b_vf3_u003b_f1_u003b((&param_150), (&param_151), (&param_152));
    return;
}

fn main_1() {
    var _S73_: vec4<f32>;

    snailSubpixelFragment_0_u0028_();
    let _e63 = _S72_;
    _S73_ = _e63;
    let _e64 = _S1_;
    entryPointParam_main_frag_blend_0_ = _e64;
    let _e65 = _S73_;
    entryPointParam_main_frag_color_0_ = _e65;
    return;
}

@fragment 
fn main(@location(3) @interpolate(flat) v_glyph_0_: vec4<i32>, @location(1) v_texcoord_0_: vec2<f32>, @location(2) @interpolate(flat) v_banding_0_: vec4<f32>, @location(0) v_color_0_: vec4<f32>, @location(4) v_tint_0_: vec4<f32>) -> FragmentOutput {
    v_glyph_0_1 = v_glyph_0_;
    v_texcoord_0_1 = v_texcoord_0_;
    v_banding_0_1 = v_banding_0_;
    v_color_0_1 = v_color_0_;
    v_tint_0_1 = v_tint_0_;
    main_1();
    let _e12 = entryPointParam_main_frag_blend_0_;
    let _e13 = entryPointParam_main_frag_color_0_;
    return FragmentOutput(_e12, _e13);
}
