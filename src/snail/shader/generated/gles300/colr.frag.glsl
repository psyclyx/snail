#version 300 es

precision highp float;
precision highp int;

struct PathPaintSample_0_ {
    vec4 color_0_;
    float gradient_0_;
};
struct CoverageBandSpan_0_ {
    int first_0_;
    int last_0_;
};
struct SegmentData_0_ {
    int kind_0_;
    vec2 p0_0_;
    vec2 p1_0_;
    vec2 p2_0_;
    vec2 p3_0_;
    vec3 weights_0_;
};
struct PathCompositeSample_0_ {
    vec4 color_3_;
    float gradient_2_;
};
struct PaintedVaryings_0_ {
    vec4 tint_1_;
    vec2 texcoord_0_;
    vec4 banding_1_;
    ivec4 glyph_0_;
};
struct PaintedParams_0_ {
    int layer_base_1_;
    int output_srgb_1_;
    float coverage_exponent_4_;
    float dither_scale_2_;
    int mask_output_1_;
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
vec4 input_tint_0_1 = vec4(0.0);

vec2 input_texcoord_0_1 = vec2(0.0);

vec4 input_banding_0_1 = vec4(0.0);

ivec4 input_glyph_0_1 = ivec4(0);

layout(std140) uniform block_SnailPushConstants_0_block_0Fragment { block_SnailPushConstants_0_ _group_0_binding_0_fs; };

vec4 gen_gl_FragCoord_1 = vec4(0.0);

uniform highp sampler2DArray _group_0_binding_1_fs;

uniform highp usampler2DArray _group_0_binding_2_fs;

uniform highp sampler2D _group_0_binding_3_fs;

uniform highp sampler2DArray _group_0_binding_4_fs;

vec4 entryPointParam_fragmentMain_0_ = vec4(0.0);

smooth in vec4 _vs2fs_location4;
smooth in vec2 _vs2fs_location1;
flat in vec4 _vs2fs_location2;
flat in ivec4 _vs2fs_location3;
layout(location = 0) out vec4 _fs2p_location0;

vec4 premultiplyColor_0_u0028_vf4_u003b_f1_u003b(inout vec4 color_2_, inout float cov_8_) {
    float alpha_0_ = 0.0;
    float _e86 = color_2_[3u];
    float _e87 = cov_8_;
    alpha_0_ = (_e86 * _e87);
    vec4 _e89 = color_2_;
    float _e91 = alpha_0_;
    vec3 _e92 = (_e89.xyz * _e91);
    float _e93 = alpha_0_;
    return vec4(_e92.x, _e92.y, _e92.z, _e93);
}

vec4 sampleImagePaintTex_0_u0028_tA21_u003b_p1_u003b_vf2_u003b_i1_u003b_i1_u003b(highp sampler2DArray image_tex_0_, inout vec2 uv_0_, inout int layer_2_, inout int filterMode_0_) {
    uint uw_1_ = 0u;
    uint uh_1_ = 0u;
    ivec2 size_0_ = ivec2(0);
    ivec4 _S75_ = ivec4(0);
    int _e91 = filterMode_0_;
    if ((_e91 == 1)) {
        uw_1_ = uint(ivec2(uvec2(textureSize(image_tex_0_, 0).xy)).x);
        uh_1_ = uint(ivec2(uvec2(textureSize(image_tex_0_, 0).xy)).y);
        uint _e101 = uw_1_;
        uint _e103 = uh_1_;
        size_0_ = ivec2(int(_e101), int(_e103));
        vec2 _e106 = uv_0_;
        ivec2 _e107 = size_0_;
        ivec2 _e111 = size_0_;
        ivec2 _e113 = min(max(ivec2((_e106 * vec2(_e107))), ivec2(0, 0)), (_e111 - ivec2(1, 1)));
        int _e114 = layer_2_;
        _S75_ = ivec4(_e113.x, _e113.y, _e114, 0);
        ivec4 _e118 = _S75_;
        ivec3 _e119 = _e118.xyz;
        int _e121 = _S75_[3u];
        vec4 _e127 = texelFetch(image_tex_0_, ivec3(ivec2(_e119.x, _e119.y), int(_e119.z)), _e121);
        return _e127;
    }
    vec2 _e128 = uv_0_;
    int _e129 = layer_2_;
    vec3 _e133 = vec3(_e128.x, _e128.y, float(_e129));
    vec4 _e139 = texture(image_tex_0_, vec3(vec2(_e133.x, _e133.y), int(_e133.z)));
    return _e139;
}

vec4 mixGradient_0_u0028_vf4_u003b_vf4_u003b_f1_u003b(inout vec4 c0_1_, inout vec4 c1_1_, inout float t_6_) {
    vec4 _e85 = c0_1_;
    vec4 _e86 = c1_1_;
    float _e87 = t_6_;
    return mix(_e85, _e86, vec4(_e87));
}

float wrapPaintT_0_u0028_f1_u003b_f1_u003b(inout float t_5_, inout float extendMode_0_) {
    int mode_0_ = 0;
    float reflected_0_ = 0.0;
    float reflected_1_ = 0.0;
    float _e87 = extendMode_0_;
    mode_0_ = int((_e87 + 0.5));
    int _e90 = mode_0_;
    if ((_e90 == 1)) {
        float _e92 = t_5_;
        return fract(_e92);
    }
    int _e94 = mode_0_;
    if ((_e94 == 2)) {
        float _e96 = t_5_;
        float _e97 = t_5_;
        reflected_0_ = (_e96 - (2.0 * floor((_e97 / 2.0))));
        float _e102 = reflected_0_;
        if ((_e102 < 0.0)) {
            float _e104 = reflected_0_;
            reflected_1_ = (_e104 + 2.0);
        } else {
            float _e106 = reflected_0_;
            reflected_1_ = _e106;
        }
        float _e107 = reflected_1_;
        return (1.0 - abs((_e107 - 1.0)));
    }
    float _e111 = t_5_;
    return clamp(_e111, 0.0, 1.0);
}

PathPaintSample_0_ PathPaintSample_x24init_0_u0028_vf4_u003b_f1_u003b(inout vec4 color_1_, inout float gradient_1_) {
    PathPaintSample_0_ _S1_ = PathPaintSample_0_(vec4(0.0), 0.0);
    vec4 _e85 = color_1_;
    _S1_.color_0_ = _e85;
    float _e87 = gradient_1_;
    _S1_.gradient_0_ = _e87;
    PathPaintSample_0_ _e89 = _S1_;
    return _e89;
}

ivec2 offsetLayerLoc_0_u0028_t21_u003b_vi2_u003b_i1_u003b(highp sampler2D layer_tex_0_, inout ivec2 base_0_, inout int offset_0_) {
    uint uw_0_ = 0u;
    int width_0_ = 0;
    int texel_0_ = 0;
    int _S2_ = 0;
    int _S3_ = 0;
    uw_0_ = uint(ivec2(uvec2(textureSize(layer_tex_0_, 0).xy)).x);
    uint _e94 = uw_0_;
    width_0_ = int(_e94);
    int _e97 = base_0_[1u];
    int _e98 = width_0_;
    int _e101 = base_0_[0u];
    int _e103 = offset_0_;
    texel_0_ = (((_e97 * _e98) + _e101) + _e103);
    int _e105 = texel_0_;
    int _e106 = width_0_;
    _S2_ = (_e105 - (int(floor((float(_e105) / float(_e106)))) * _e106));
    int _e114 = texel_0_;
    int _e115 = width_0_;
    _S3_ = (_e114 / _e115);
    int _e117 = _S2_;
    int _e118 = _S3_;
    return ivec2(_e117, _e118);
}

PathPaintSample_0_ samplePathPaint_0_u0028_t21_u003b_tA21_u003b_p1_u003b_vf2_u003b_vi2_u003b_vf4_u003b(highp sampler2D layer_tex_1_, highp sampler2DArray image_tex_1_, inout vec2 rc_1_, inout ivec2 infoBase_0_, inout vec4 info_0_) {
    int paintKind_0_ = 0;
    ivec2 _S76_ = ivec2(0);
    ivec2 param = ivec2(0);
    int param_1 = 0;
    ivec3 _S77_ = ivec3(0);
    vec4 data0_0_ = vec4(0.0);
    vec4 param_2 = vec4(0.0);
    float param_3 = 0.0;
    ivec2 _S78_ = ivec2(0);
    ivec2 param_4 = ivec2(0);
    int param_5 = 0;
    ivec3 _S79_ = ivec3(0);
    vec4 color0_0_ = vec4(0.0);
    ivec2 _S80_ = ivec2(0);
    ivec2 param_6 = ivec2(0);
    int param_7 = 0;
    ivec3 _S81_ = ivec3(0);
    vec4 color1_0_ = vec4(0.0);
    vec2 _S82_ = vec2(0.0);
    vec2 delta_0_ = vec2(0.0);
    float lenSq_0_ = 0.0;
    float t_7_ = 0.0;
    ivec2 _S83_ = ivec2(0);
    ivec2 param_8 = ivec2(0);
    int param_9 = 0;
    ivec3 _S84_ = ivec3(0);
    float param_10 = 0.0;
    float param_11 = 0.0;
    vec4 param_12 = vec4(0.0);
    vec4 param_13 = vec4(0.0);
    float param_14 = 0.0;
    vec4 param_15 = vec4(0.0);
    float param_16 = 0.0;
    float param_17 = 0.0;
    float param_18 = 0.0;
    vec4 param_19 = vec4(0.0);
    vec4 param_20 = vec4(0.0);
    float param_21 = 0.0;
    vec4 param_22 = vec4(0.0);
    float param_23 = 0.0;
    vec2 d_1_ = vec2(0.0);
    float param_24 = 0.0;
    float param_25 = 0.0;
    vec4 param_26 = vec4(0.0);
    vec4 param_27 = vec4(0.0);
    float param_28 = 0.0;
    vec4 param_29 = vec4(0.0);
    float param_30 = 0.0;
    ivec2 _S85_ = ivec2(0);
    ivec2 param_31 = ivec2(0);
    int param_32 = 0;
    ivec3 _S86_ = ivec3(0);
    vec4 data1_0_ = vec4(0.0);
    ivec2 _S87_ = ivec2(0);
    ivec2 param_33 = ivec2(0);
    int param_34 = 0;
    ivec3 _S88_ = ivec3(0);
    vec4 extra_0_ = vec4(0.0);
    vec3 _S89_ = vec3(0.0);
    float param_35 = 0.0;
    float param_36 = 0.0;
    float param_37 = 0.0;
    float param_38 = 0.0;
    vec2 param_39 = vec2(0.0);
    int param_40 = 0;
    int param_41 = 0;
    vec4 param_42 = vec4(0.0);
    float param_43 = 0.0;
    vec4 param_44 = vec4(0.0);
    float param_45 = 0.0;
    float _e159 = info_0_[3u];
    paintKind_0_ = int((-(_e159) + 0.5));
    ivec2 _e163 = infoBase_0_;
    param = _e163;
    param_1 = 2;
    ivec2 _e164 = offsetLayerLoc_0_u0028_t21_u003b_vi2_u003b_i1_u003b(layer_tex_1_, param, param_1);
    _S76_ = _e164;
    ivec2 _e165 = _S76_;
    _S77_ = ivec3(_e165.x, _e165.y, 0);
    ivec3 _e169 = _S77_;
    int _e172 = _S77_[2u];
    vec4 _e173 = texelFetch(layer_tex_1_, _e169.xy, _e172);
    data0_0_ = _e173;
    int _e174 = paintKind_0_;
    if ((_e174 == 1)) {
        vec4 _e176 = data0_0_;
        param_2 = _e176;
        param_3 = 0.0;
        PathPaintSample_0_ _e177 = PathPaintSample_x24init_0_u0028_vf4_u003b_f1_u003b(param_2, param_3);
        return _e177;
    }
    ivec2 _e178 = infoBase_0_;
    param_4 = _e178;
    param_5 = 3;
    ivec2 _e179 = offsetLayerLoc_0_u0028_t21_u003b_vi2_u003b_i1_u003b(layer_tex_1_, param_4, param_5);
    _S78_ = _e179;
    ivec2 _e180 = _S78_;
    _S79_ = ivec3(_e180.x, _e180.y, 0);
    ivec3 _e184 = _S79_;
    int _e187 = _S79_[2u];
    vec4 _e188 = texelFetch(layer_tex_1_, _e184.xy, _e187);
    color0_0_ = _e188;
    ivec2 _e189 = infoBase_0_;
    param_6 = _e189;
    param_7 = 4;
    ivec2 _e190 = offsetLayerLoc_0_u0028_t21_u003b_vi2_u003b_i1_u003b(layer_tex_1_, param_6, param_7);
    _S80_ = _e190;
    ivec2 _e191 = _S80_;
    _S81_ = ivec3(_e191.x, _e191.y, 0);
    ivec3 _e195 = _S81_;
    int _e198 = _S81_[2u];
    vec4 _e199 = texelFetch(layer_tex_1_, _e195.xy, _e198);
    color1_0_ = _e199;
    int _e200 = paintKind_0_;
    if ((_e200 == 2)) {
        vec4 _e202 = data0_0_;
        _S82_ = _e202.xy;
        vec4 _e204 = data0_0_;
        vec2 _e206 = _S82_;
        delta_0_ = (_e204.zw - _e206);
        vec2 _e208 = delta_0_;
        vec2 _e209 = delta_0_;
        lenSq_0_ = dot(_e208, _e209);
        float _e211 = lenSq_0_;
        if ((_e211 > 1e-10)) {
            vec2 _e213 = rc_1_;
            vec2 _e214 = _S82_;
            vec2 _e216 = delta_0_;
            float _e218 = lenSq_0_;
            t_7_ = (dot((_e213 - _e214), _e216) / _e218);
        } else {
            t_7_ = 0.0;
        }
        ivec2 _e220 = infoBase_0_;
        param_8 = _e220;
        param_9 = 5;
        ivec2 _e221 = offsetLayerLoc_0_u0028_t21_u003b_vi2_u003b_i1_u003b(layer_tex_1_, param_8, param_9);
        _S83_ = _e221;
        ivec2 _e222 = _S83_;
        _S84_ = ivec3(_e222.x, _e222.y, 0);
        ivec3 _e226 = _S84_;
        int _e229 = _S84_[2u];
        vec4 _e230 = texelFetch(layer_tex_1_, _e226.xy, _e229);
        float _e231 = t_7_;
        param_10 = _e231;
        param_11 = _e230.x;
        float _e233 = wrapPaintT_0_u0028_f1_u003b_f1_u003b(param_10, param_11);
        vec4 _e234 = color0_0_;
        param_12 = _e234;
        vec4 _e235 = color1_0_;
        param_13 = _e235;
        param_14 = _e233;
        vec4 _e236 = mixGradient_0_u0028_vf4_u003b_vf4_u003b_f1_u003b(param_12, param_13, param_14);
        param_15 = _e236;
        param_16 = 1.0;
        PathPaintSample_0_ _e237 = PathPaintSample_x24init_0_u0028_vf4_u003b_f1_u003b(param_15, param_16);
        return _e237;
    }
    int _e238 = paintKind_0_;
    if ((_e238 == 3)) {
        vec2 _e240 = rc_1_;
        vec4 _e241 = data0_0_;
        float _e246 = data0_0_[2u];
        param_17 = (length((_e240 - _e241.xy)) / max(abs(_e246), 1.5258789e-5));
        float _e251 = data0_0_[3u];
        param_18 = _e251;
        float _e252 = wrapPaintT_0_u0028_f1_u003b_f1_u003b(param_17, param_18);
        vec4 _e253 = color0_0_;
        param_19 = _e253;
        vec4 _e254 = color1_0_;
        param_20 = _e254;
        param_21 = _e252;
        vec4 _e255 = mixGradient_0_u0028_vf4_u003b_vf4_u003b_f1_u003b(param_19, param_20, param_21);
        param_22 = _e255;
        param_23 = 1.0;
        PathPaintSample_0_ _e256 = PathPaintSample_x24init_0_u0028_vf4_u003b_f1_u003b(param_22, param_23);
        return _e256;
    }
    int _e257 = paintKind_0_;
    if ((_e257 == 6)) {
        vec2 _e259 = rc_1_;
        vec4 _e260 = data0_0_;
        d_1_ = (_e259 - _e260.xy);
        float _e264 = d_1_[1u];
        float _e266 = d_1_[0u];
        float _e269 = data0_0_[2u];
        param_24 = ((atan(_e264, _e266) - _e269) * 0.15915494);
        float _e273 = data0_0_[3u];
        param_25 = _e273;
        float _e274 = wrapPaintT_0_u0028_f1_u003b_f1_u003b(param_24, param_25);
        vec4 _e275 = color0_0_;
        param_26 = _e275;
        vec4 _e276 = color1_0_;
        param_27 = _e276;
        param_28 = _e274;
        vec4 _e277 = mixGradient_0_u0028_vf4_u003b_vf4_u003b_f1_u003b(param_26, param_27, param_28);
        param_29 = _e277;
        param_30 = 1.0;
        PathPaintSample_0_ _e278 = PathPaintSample_x24init_0_u0028_vf4_u003b_f1_u003b(param_29, param_30);
        return _e278;
    }
    int _e279 = paintKind_0_;
    if ((_e279 == 4)) {
        ivec2 _e281 = infoBase_0_;
        param_31 = _e281;
        param_32 = 3;
        ivec2 _e282 = offsetLayerLoc_0_u0028_t21_u003b_vi2_u003b_i1_u003b(layer_tex_1_, param_31, param_32);
        _S85_ = _e282;
        ivec2 _e283 = _S85_;
        _S86_ = ivec3(_e283.x, _e283.y, 0);
        ivec3 _e287 = _S86_;
        int _e290 = _S86_[2u];
        vec4 _e291 = texelFetch(layer_tex_1_, _e287.xy, _e290);
        data1_0_ = _e291;
        ivec2 _e292 = infoBase_0_;
        param_33 = _e292;
        param_34 = 5;
        ivec2 _e293 = offsetLayerLoc_0_u0028_t21_u003b_vi2_u003b_i1_u003b(layer_tex_1_, param_33, param_34);
        _S87_ = _e293;
        ivec2 _e294 = _S87_;
        _S88_ = ivec3(_e294.x, _e294.y, 0);
        ivec3 _e298 = _S88_;
        int _e301 = _S88_[2u];
        vec4 _e302 = texelFetch(layer_tex_1_, _e298.xy, _e301);
        extra_0_ = _e302;
        vec2 _e303 = rc_1_;
        _S89_ = vec3(_e303.x, _e303.y, 1.0);
        vec3 _e307 = _S89_;
        float _e309 = data0_0_[0u];
        float _e311 = data0_0_[1u];
        float _e313 = data0_0_[2u];
        param_35 = dot(_e307, vec3(_e309, _e311, _e313));
        float _e317 = extra_0_[2u];
        param_36 = _e317;
        float _e318 = wrapPaintT_0_u0028_f1_u003b_f1_u003b(param_35, param_36);
        float _e320 = extra_0_[0u];
        vec3 _e322 = _S89_;
        float _e324 = data1_0_[0u];
        float _e326 = data1_0_[1u];
        float _e328 = data1_0_[2u];
        param_37 = dot(_e322, vec3(_e324, _e326, _e328));
        float _e332 = extra_0_[3u];
        param_38 = _e332;
        float _e333 = wrapPaintT_0_u0028_f1_u003b_f1_u003b(param_37, param_38);
        float _e335 = extra_0_[1u];
        float _e339 = data0_0_[3u];
        float _e343 = data1_0_[3u];
        param_39 = vec2((_e318 * _e320), (_e333 * _e335));
        param_40 = int((_e339 + 0.5));
        param_41 = int((_e343 + 0.5));
        vec4 _e346 = sampleImagePaintTex_0_u0028_tA21_u003b_p1_u003b_vf2_u003b_i1_u003b_i1_u003b(image_tex_1_, param_39, param_40, param_41);
        param_42 = _e346;
        param_43 = 0.0;
        PathPaintSample_0_ _e347 = PathPaintSample_x24init_0_u0028_vf4_u003b_f1_u003b(param_42, param_43);
        return _e347;
    }
    param_44 = vec4(1.0, 0.0, 1.0, 1.0);
    param_45 = 0.0;
    PathPaintSample_0_ _e348 = PathPaintSample_x24init_0_u0028_vf4_u003b_f1_u003b(param_44, param_45);
    return _e348;
}

float applyCoverageTransfer_0_u0028_f1_u003b_f1_u003b(inout float cov_7_, inout float coverage_exponent_1_) {
    float clamped_0_ = 0.0;
    float _S68_ = 0.0;
    float _S69_ = 0.0;
    float _e87 = cov_7_;
    clamped_0_ = clamp(_e87, 0.0, 1.0);
    float _e89 = coverage_exponent_1_;
    _S68_ = max(_e89, 1.5258789e-5);
    float _e91 = _S68_;
    if ((abs((_e91 - 1.0)) <= 1e-6)) {
        float _e95 = clamped_0_;
        _S69_ = _e95;
    } else {
        float _e96 = clamped_0_;
        float _e97 = _S68_;
        _S69_ = pow(_e96, _e97);
    }
    float _e99 = _S69_;
    return _e99;
}

float applyFillRule_0_u0028_f1_u003b_i1_u003b(inout float winding_0_, inout int fill_rule_mode_0_) {
    int _e84 = fill_rule_mode_0_;
    if ((_e84 == 1)) {
        float _e86 = winding_0_;
        return (1.0 - abs(((fract((_e86 * 0.5)) * 2.0) - 1.0)));
    }
    float _e93 = winding_0_;
    return abs(_e93);
}

void appendCoverageContribution_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b(inout float cov_0_, inout float wgt_0_, inout float distance_0_, inout float sign_0_) {
    float _e86 = cov_0_;
    float _e87 = sign_0_;
    float _e88 = distance_0_;
    cov_0_ = (_e86 + (_e87 * clamp((_e88 + 0.5), 0.0, 1.0)));
    float _e93 = wgt_0_;
    float _e94 = distance_0_;
    wgt_0_ = max(_e93, clamp((1.0 - (abs(_e94) * 2.0)), 0.0, 1.0));
    return;
}

// Composed-catalog solver text, injected by build/glsl_patch_cubic_solver.zig
// (see that file for why the naga emission cannot be used verbatim).
bool snailSpecSolveMonotonicCubicRoot(float a, float b, float cVal, float d, float endDelta, out float tOut) {
    // Path preparation splits cubics at x/y extrema, so each uploaded cubic is
    // monotonic along both sampling axes and can contribute at most one root.
    float f0 = d;
    // Use the uploaded p3 directly. Reconstructing f(1) through a+b+c+d
    // loses enough precision near shallow extrema to corrupt the bracket.
    float f1 = endDelta;
    if ((f0 < -(1.0 / 65536.0) && f1 < -(1.0 / 65536.0)) || (f0 > (1.0 / 65536.0) && f1 > (1.0 / 65536.0))) return false;

    float lo = 0.0;
    float hi = 1.0;
    float t = 0.5;
    bool increasing = f1 >= f0;
    for (int i = 0; i < 16; i++) {
        float f = ((a * t + b) * t + cVal) * t + d;
        if ((increasing && f < 0.0) || (!increasing && f > 0.0)) {
            lo = t;
        } else {
            hi = t;
        }
        float deriv = (3.0 * a * t + 2.0 * b) * t + cVal;
        float next = (lo + hi) * 0.5;
        if (abs(deriv) >= 1e-6) {
            float newton = t - f / deriv;
            if (newton > lo && newton < hi) next = newton;
        }
        t = next;
    }
    tOut = t;
    return true;
}

bool solveMonotonicCubicRoot_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b(inout float a_0_, inout float b_1_, inout float cVal_0_, inout float d_0_, inout float endDelta_0_, inout float tOut_0_) {
    return snailSpecSolveMonotonicCubicRoot(a_0_, b_1_, cVal_0_, d_0_, endDelta_0_, tOut_0_);
}

float rootCodeCoord_0_u0028_f1_u003b(inout float v_0_) {
    float _S11_ = 0.0;
    float _e84 = v_0_;
    if ((abs(_e84) <= 1.5258789e-5)) {
        _S11_ = 0.0;
    } else {
        float _e87 = v_0_;
        _S11_ = _e87;
    }
    float _e88 = _S11_;
    return _e88;
}

bool rootHullCanCross3_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b(inout float p0_2_, inout float p1_2_, inout float p2_2_, inout float sampleRoot_1_) {
    float _S25_ = 0.0;
    bool _S26_ = false;
    float _e88 = p0_2_;
    float _e89 = p1_2_;
    float _e91 = p2_2_;
    _S25_ = max(max(_e88, _e89), _e91);
    float _e93 = p0_2_;
    float _e94 = p1_2_;
    float _e96 = p2_2_;
    float _e98 = sampleRoot_1_;
    if (((min(min(_e93, _e94), _e96) - _e98) <= 1.5258789e-5)) {
        float _e101 = _S25_;
        float _e102 = sampleRoot_1_;
        _S26_ = ((_e101 - _e102) >= -1.5258789e-5);
    } else {
        _S26_ = false;
    }
    bool _e105 = _S26_;
    return _e105;
}

bool rootHullCanCross4_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b(inout float p0_1_, inout float p1_1_, inout float p2_1_, inout float p3_1_, inout float sampleRoot_0_) {
    float _S23_ = 0.0;
    bool _S24_ = false;
    float _e89 = p0_1_;
    float _e90 = p1_1_;
    float _e92 = p2_1_;
    float _e93 = p3_1_;
    _S23_ = max(max(_e89, _e90), max(_e92, _e93));
    float _e96 = p0_1_;
    float _e97 = p1_1_;
    float _e99 = p2_1_;
    float _e100 = p3_1_;
    float _e103 = sampleRoot_0_;
    if (((min(min(_e96, _e97), min(_e99, _e100)) - _e103) <= 1.5258789e-5)) {
        float _e106 = _S23_;
        float _e107 = sampleRoot_0_;
        _S24_ = ((_e106 - _e107) >= -1.5258789e-5);
    } else {
        _S24_ = false;
    }
    bool _e110 = _S24_;
    return _e110;
}

bool segmentRootHullCanCross_0_u0028_struct_u002d_SegmentData_0_u002d_i1_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf31_u003b_vf2_u003b_b1_u003b(inout SegmentData_0_ seg_3_, inout vec2 sampleRc_0_, inout bool horizontal_1_) {
    float sampleRoot_2_ = 0.0;
    float _S27_ = 0.0;
    float _S28_ = 0.0;
    float _S29_ = 0.0;
    float _S30_ = 0.0;
    float param_46 = 0.0;
    float param_47 = 0.0;
    float param_48 = 0.0;
    float param_49 = 0.0;
    float param_50 = 0.0;
    float param_51 = 0.0;
    float param_52 = 0.0;
    float param_53 = 0.0;
    float param_54 = 0.0;
    bool _e99 = horizontal_1_;
    if (_e99) {
        float _e101 = sampleRc_0_[1u];
        sampleRoot_2_ = _e101;
    } else {
        float _e103 = sampleRc_0_[0u];
        sampleRoot_2_ = _e103;
    }
    int _e105 = seg_3_.kind_0_;
    if ((_e105 == 2)) {
        bool _e107 = horizontal_1_;
        if (_e107) {
            float _e110 = seg_3_.p0_0_[1u];
            _S27_ = _e110;
        } else {
            float _e113 = seg_3_.p0_0_[0u];
            _S27_ = _e113;
        }
        bool _e114 = horizontal_1_;
        if (_e114) {
            float _e117 = seg_3_.p1_0_[1u];
            _S28_ = _e117;
        } else {
            float _e120 = seg_3_.p1_0_[0u];
            _S28_ = _e120;
        }
        bool _e121 = horizontal_1_;
        if (_e121) {
            float _e124 = seg_3_.p2_0_[1u];
            _S29_ = _e124;
        } else {
            float _e127 = seg_3_.p2_0_[0u];
            _S29_ = _e127;
        }
        bool _e128 = horizontal_1_;
        if (_e128) {
            float _e131 = seg_3_.p3_0_[1u];
            _S30_ = _e131;
        } else {
            float _e134 = seg_3_.p3_0_[0u];
            _S30_ = _e134;
        }
        float _e135 = _S27_;
        param_46 = _e135;
        float _e136 = _S28_;
        param_47 = _e136;
        float _e137 = _S29_;
        param_48 = _e137;
        float _e138 = _S30_;
        param_49 = _e138;
        float _e139 = sampleRoot_2_;
        param_50 = _e139;
        bool _e140 = rootHullCanCross4_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b(param_46, param_47, param_48, param_49, param_50);
        return _e140;
    }
    bool _e141 = horizontal_1_;
    if (_e141) {
        float _e144 = seg_3_.p0_0_[1u];
        _S27_ = _e144;
    } else {
        float _e147 = seg_3_.p0_0_[0u];
        _S27_ = _e147;
    }
    bool _e148 = horizontal_1_;
    if (_e148) {
        float _e151 = seg_3_.p1_0_[1u];
        _S28_ = _e151;
    } else {
        float _e154 = seg_3_.p1_0_[0u];
        _S28_ = _e154;
    }
    bool _e155 = horizontal_1_;
    if (_e155) {
        float _e158 = seg_3_.p2_0_[1u];
        _S29_ = _e158;
    } else {
        float _e161 = seg_3_.p2_0_[0u];
        _S29_ = _e161;
    }
    float _e162 = _S27_;
    param_51 = _e162;
    float _e163 = _S28_;
    param_52 = _e163;
    float _e164 = _S29_;
    param_53 = _e164;
    float _e165 = sampleRoot_2_;
    param_54 = _e165;
    bool _e166 = rootHullCanCross3_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b(param_51, param_52, param_53, param_54);
    return _e166;
}

void accumulateCubicCoverage_0_u0028_f1_u003b_f1_u003b_struct_u002d_SegmentData_0_u002d_i1_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf31_u003b_vf2_u003b_f1_u003b_b1_u003b(inout float cov_4_, inout float wgt_4_, inout SegmentData_0_ seg_6_, inout vec2 sampleRc_3_, inout float ppe_3_, inout bool horizontal_5_) {
    SegmentData_0_ param_55 = SegmentData_0_(0, vec2(0.0), vec2(0.0), vec2(0.0), vec2(0.0), vec3(0.0));
    vec2 param_56 = vec2(0.0);
    bool param_57 = false;
    float sampleRoot_4_ = 0.0;
    float sampleAlong_2_ = 0.0;
    float p0Root_1_ = 0.0;
    float p1Root_1_ = 0.0;
    float p2Root_1_ = 0.0;
    float p3Root_0_ = 0.0;
    float p0Along_1_ = 0.0;
    float p1Along_1_ = 0.0;
    float p2Along_1_ = 0.0;
    float p3Along_0_ = 0.0;
    float _S51_ = 0.0;
    float _S52_ = 0.0;
    float rootA_2_ = 0.0;
    float rootB_2_ = 0.0;
    float rootC_1_ = 0.0;
    float startDelta_0_ = 0.0;
    float endDelta_1_ = 0.0;
    float param_58 = 0.0;
    float param_59 = 0.0;
    float t_4_ = 0.0;
    bool _S53_ = false;
    float param_60 = 0.0;
    float param_61 = 0.0;
    float param_62 = 0.0;
    float param_63 = 0.0;
    float param_64 = 0.0;
    float param_65 = 0.0;
    float _S54_ = 0.0;
    float _S55_ = 0.0;
    float alongA_2_ = 0.0;
    float alongB_2_ = 0.0;
    float alongC_1_ = 0.0;
    float along_1_ = 0.0;
    float derivAxis_2_ = 0.0;
    float dist_1_ = 0.0;
    float param_66 = 0.0;
    float param_67 = 0.0;
    float param_68 = 0.0;
    float param_69 = 0.0;
    SegmentData_0_ _e130 = seg_6_;
    param_55 = _e130;
    vec2 _e131 = sampleRc_3_;
    param_56 = _e131;
    bool _e132 = horizontal_5_;
    param_57 = _e132;
    bool _e133 = segmentRootHullCanCross_0_u0028_struct_u002d_SegmentData_0_u002d_i1_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf31_u003b_vf2_u003b_b1_u003b(param_55, param_56, param_57);
    if (!(_e133)) {
        return;
    }
    bool _e135 = horizontal_5_;
    if (_e135) {
        float _e137 = sampleRc_3_[1u];
        sampleRoot_4_ = _e137;
    } else {
        float _e139 = sampleRc_3_[0u];
        sampleRoot_4_ = _e139;
    }
    bool _e140 = horizontal_5_;
    if (_e140) {
        float _e142 = sampleRc_3_[0u];
        sampleAlong_2_ = _e142;
    } else {
        float _e144 = sampleRc_3_[1u];
        sampleAlong_2_ = _e144;
    }
    bool _e145 = horizontal_5_;
    if (_e145) {
        float _e148 = seg_6_.p0_0_[1u];
        p0Root_1_ = _e148;
    } else {
        float _e151 = seg_6_.p0_0_[0u];
        p0Root_1_ = _e151;
    }
    bool _e152 = horizontal_5_;
    if (_e152) {
        float _e155 = seg_6_.p1_0_[1u];
        p1Root_1_ = _e155;
    } else {
        float _e158 = seg_6_.p1_0_[0u];
        p1Root_1_ = _e158;
    }
    bool _e159 = horizontal_5_;
    if (_e159) {
        float _e162 = seg_6_.p2_0_[1u];
        p2Root_1_ = _e162;
    } else {
        float _e165 = seg_6_.p2_0_[0u];
        p2Root_1_ = _e165;
    }
    bool _e166 = horizontal_5_;
    if (_e166) {
        float _e169 = seg_6_.p3_0_[1u];
        p3Root_0_ = _e169;
    } else {
        float _e172 = seg_6_.p3_0_[0u];
        p3Root_0_ = _e172;
    }
    bool _e173 = horizontal_5_;
    if (_e173) {
        float _e176 = seg_6_.p0_0_[0u];
        p0Along_1_ = _e176;
    } else {
        float _e179 = seg_6_.p0_0_[1u];
        p0Along_1_ = _e179;
    }
    bool _e180 = horizontal_5_;
    if (_e180) {
        float _e183 = seg_6_.p1_0_[0u];
        p1Along_1_ = _e183;
    } else {
        float _e186 = seg_6_.p1_0_[1u];
        p1Along_1_ = _e186;
    }
    bool _e187 = horizontal_5_;
    if (_e187) {
        float _e190 = seg_6_.p2_0_[0u];
        p2Along_1_ = _e190;
    } else {
        float _e193 = seg_6_.p2_0_[1u];
        p2Along_1_ = _e193;
    }
    bool _e194 = horizontal_5_;
    if (_e194) {
        float _e197 = seg_6_.p3_0_[0u];
        p3Along_0_ = _e197;
    } else {
        float _e200 = seg_6_.p3_0_[1u];
        p3Along_0_ = _e200;
    }
    float _e201 = p1Root_1_;
    _S51_ = (3.0 * _e201);
    float _e203 = p2Root_1_;
    _S52_ = (3.0 * _e203);
    float _e205 = p0Root_1_;
    float _e207 = _S51_;
    float _e209 = _S52_;
    float _e211 = p3Root_0_;
    rootA_2_ = (((-(_e205) + _e207) - _e209) + _e211);
    float _e213 = p0Root_1_;
    float _e215 = p1Root_1_;
    float _e218 = _S52_;
    rootB_2_ = (((3.0 * _e213) - (6.0 * _e215)) + _e218);
    float _e220 = p0Root_1_;
    float _e222 = _S51_;
    rootC_1_ = ((-3.0 * _e220) + _e222);
    float _e224 = p0Root_1_;
    float _e225 = sampleRoot_4_;
    startDelta_0_ = (_e224 - _e225);
    float _e227 = p3Root_0_;
    float _e228 = sampleRoot_4_;
    endDelta_1_ = (_e227 - _e228);
    float _e230 = startDelta_0_;
    param_58 = _e230;
    float _e231 = rootCodeCoord_0_u0028_f1_u003b(param_58);
    float _e233 = endDelta_1_;
    param_59 = _e233;
    float _e234 = rootCodeCoord_0_u0028_f1_u003b(param_59);
    if (((_e231 < 0.0) == (_e234 < 0.0))) {
        return;
    }
    t_4_ = 0.0;
    float _e237 = startDelta_0_;
    if ((abs(_e237) <= 1.5258789e-5)) {
        t_4_ = 0.0;
    } else {
        float _e240 = endDelta_1_;
        if ((abs(_e240) <= 1.5258789e-5)) {
            t_4_ = 1.0;
        } else {
            float _e243 = rootA_2_;
            param_60 = _e243;
            float _e244 = rootB_2_;
            param_61 = _e244;
            float _e245 = rootC_1_;
            param_62 = _e245;
            float _e246 = startDelta_0_;
            param_63 = _e246;
            float _e247 = endDelta_1_;
            param_64 = _e247;
            bool _e248 = solveMonotonicCubicRoot_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b(param_60, param_61, param_62, param_63, param_64, param_65);
            float _e249 = param_65;
            t_4_ = _e249;
            _S53_ = _e248;
            bool _e250 = _S53_;
            if (!(_e250)) {
                return;
            }
        }
    }
    float _e252 = p1Along_1_;
    _S54_ = (3.0 * _e252);
    float _e254 = p2Along_1_;
    _S55_ = (3.0 * _e254);
    float _e256 = p0Along_1_;
    float _e258 = _S54_;
    float _e260 = _S55_;
    float _e262 = p3Along_0_;
    alongA_2_ = (((-(_e256) + _e258) - _e260) + _e262);
    float _e264 = p0Along_1_;
    float _e266 = p1Along_1_;
    float _e269 = _S55_;
    alongB_2_ = (((3.0 * _e264) - (6.0 * _e266)) + _e269);
    float _e271 = p0Along_1_;
    float _e273 = _S54_;
    alongC_1_ = ((-3.0 * _e271) + _e273);
    float _e275 = t_4_;
    if ((_e275 == 1.0)) {
        float _e277 = p3Along_0_;
        along_1_ = _e277;
    } else {
        float _e278 = alongA_2_;
        float _e279 = t_4_;
        float _e281 = alongB_2_;
        float _e283 = t_4_;
        float _e285 = alongC_1_;
        float _e287 = t_4_;
        float _e289 = p0Along_1_;
        along_1_ = ((((((_e278 * _e279) + _e281) * _e283) + _e285) * _e287) + _e289);
    }
    bool _e291 = horizontal_5_;
    if (_e291) {
        float _e292 = p3Root_0_;
        float _e293 = p0Root_1_;
        derivAxis_2_ = (_e292 - _e293);
    } else {
        float _e295 = p0Root_1_;
        float _e296 = p3Root_0_;
        derivAxis_2_ = (_e295 - _e296);
    }
    float _e298 = along_1_;
    float _e299 = sampleAlong_2_;
    float _e301 = ppe_3_;
    dist_1_ = ((_e298 - _e299) * _e301);
    float _e303 = derivAxis_2_;
    if ((_e303 > 0.0)) {
        sampleRoot_4_ = 1.0;
    } else {
        sampleRoot_4_ = -1.0;
    }
    float _e305 = cov_4_;
    param_66 = _e305;
    float _e306 = wgt_4_;
    param_67 = _e306;
    float _e307 = dist_1_;
    param_68 = _e307;
    float _e308 = sampleRoot_4_;
    param_69 = _e308;
    appendCoverageContribution_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b(param_66, param_67, param_68, param_69);
    float _e309 = param_66;
    cov_4_ = _e309;
    float _e310 = param_67;
    wgt_4_ = _e310;
    return;
}

void accumulateConicRoot_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_b1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b(inout float cov_2_, inout float wgt_2_, inout float t_2_, inout float endRootDelta_0_, inout float sampleAlong_0_, inout float ppe_1_, inout bool horizontal_3_, inout float rootA_0_, inout float rootB_0_, inout float rootC_0_, inout float alongA_0_, inout float alongB_0_, inout float alongC_0_, inout float denA_0_, inout float denB_0_, inout float denC_0_) {
    float _S32_ = 0.0;
    float along_0_ = 0.0;
    float derivAxis_0_ = 0.0;
    float derivAxis_1_ = 0.0;
    float dist_0_ = 0.0;
    float param_70 = 0.0;
    float param_71 = 0.0;
    float param_72 = 0.0;
    float param_73 = 0.0;
    float _e107 = denA_0_;
    float _e108 = t_2_;
    float _e110 = denB_0_;
    float _e112 = t_2_;
    float _e114 = denC_0_;
    _S32_ = max(((((_e107 * _e108) + _e110) * _e112) + _e114), 1.5258789e-5);
    float _e117 = alongA_0_;
    float _e118 = t_2_;
    float _e120 = alongB_0_;
    float _e122 = t_2_;
    float _e124 = alongC_0_;
    float _e126 = _S32_;
    along_0_ = (((((_e117 * _e118) + _e120) * _e122) + _e124) / _e126);
    float _e128 = rootA_0_;
    float _e130 = t_2_;
    float _e132 = rootB_0_;
    float _e134 = _S32_;
    float _e136 = rootA_0_;
    float _e137 = t_2_;
    float _e139 = rootB_0_;
    float _e141 = t_2_;
    float _e143 = rootC_0_;
    float _e145 = denA_0_;
    float _e147 = t_2_;
    float _e149 = denB_0_;
    float _e153 = _S32_;
    float _e154 = _S32_;
    derivAxis_0_ = ((((((2.0 * _e128) * _e130) + _e132) * _e134) - (((((_e136 * _e137) + _e139) * _e141) + _e143) * (((2.0 * _e145) * _e147) + _e149))) / (_e153 * _e154));
    bool _e157 = horizontal_3_;
    if (!(_e157)) {
        float _e159 = derivAxis_0_;
        derivAxis_1_ = -(_e159);
    } else {
        float _e161 = derivAxis_0_;
        derivAxis_1_ = _e161;
    }
    float _e162 = derivAxis_1_;
    if ((abs(_e162) <= 1e-5)) {
        return;
    }
    float _e165 = along_0_;
    float _e166 = sampleAlong_0_;
    float _e168 = ppe_1_;
    dist_0_ = ((_e165 - _e166) * _e168);
    float _e170 = derivAxis_1_;
    if ((_e170 > 0.0)) {
        derivAxis_1_ = 1.0;
    } else {
        derivAxis_1_ = -1.0;
    }
    float _e172 = cov_2_;
    param_70 = _e172;
    float _e173 = wgt_2_;
    param_71 = _e173;
    float _e174 = dist_0_;
    param_72 = _e174;
    float _e175 = derivAxis_1_;
    param_73 = _e175;
    appendCoverageContribution_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b(param_70, param_71, param_72, param_73);
    float _e176 = param_70;
    cov_2_ = _e176;
    float _e177 = param_71;
    wgt_2_ = _e177;
    return;
}

float segmentEndRootDelta_0_u0028_struct_u002d_SegmentData_0_u002d_i1_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf31_u003b_vf2_u003b_b1_u003b(inout SegmentData_0_ seg_4_, inout vec2 sampleRc_1_, inout bool horizontal_2_) {
    float _S31_ = 0.0;
    int _e87 = seg_4_.kind_0_;
    if ((_e87 == 2)) {
        bool _e89 = horizontal_2_;
        if (_e89) {
            float _e92 = seg_4_.p3_0_[1u];
            float _e94 = sampleRc_1_[1u];
            _S31_ = (_e92 - _e94);
        } else {
            float _e98 = seg_4_.p3_0_[0u];
            float _e100 = sampleRc_1_[0u];
            _S31_ = (_e98 - _e100);
        }
        float _e102 = _S31_;
        return _e102;
    }
    bool _e103 = horizontal_2_;
    if (_e103) {
        float _e106 = seg_4_.p2_0_[1u];
        float _e108 = sampleRc_1_[1u];
        _S31_ = (_e106 - _e108);
    } else {
        float _e112 = seg_4_.p2_0_[0u];
        float _e114 = sampleRc_1_[0u];
        _S31_ = (_e112 - _e114);
    }
    float _e116 = _S31_;
    return _e116;
}

float distToUnitInterval_0_u0028_f1_u003b(inout float t_1_) {
    float _e83 = t_1_;
    float _e86 = t_1_;
    return max(max(0.0, -(_e83)), (_e86 - 1.0));
}

uint calcRootCode_0_u0028_f1_u003b_f1_u003b_f1_u003b(inout float y1_0_, inout float y2_0_, inout float y3_0_) {
    float param_74 = 0.0;
    float param_75 = 0.0;
    float param_76 = 0.0;
    float _e88 = y3_0_;
    param_74 = _e88;
    float _e89 = rootCodeCoord_0_u0028_f1_u003b(param_74);
    float _e94 = y2_0_;
    param_75 = _e94;
    float _e95 = rootCodeCoord_0_u0028_f1_u003b(param_75);
    float _e100 = y1_0_;
    param_76 = _e100;
    float _e101 = rootCodeCoord_0_u0028_f1_u003b(param_76);
    return ((11892u >> (((floatBitsToUint(_e89) >> 29u) & 4u) | ((((floatBitsToUint(_e95) >> 30u) & 2u) | ((floatBitsToUint(_e101) >> 31u) & 4294967293u)) & 4294967291u))) & 257u);
}

void accumulateConicCoverage_0_u0028_f1_u003b_f1_u003b_struct_u002d_SegmentData_0_u002d_i1_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf31_u003b_vf2_u003b_f1_u003b_b1_u003b(inout float cov_3_, inout float wgt_3_, inout SegmentData_0_ seg_5_, inout vec2 sampleRc_2_, inout float ppe_2_, inout bool horizontal_4_) {
    SegmentData_0_ param_77 = SegmentData_0_(0, vec2(0.0), vec2(0.0), vec2(0.0), vec2(0.0), vec3(0.0));
    vec2 param_78 = vec2(0.0);
    bool param_79 = false;
    float sampleRoot_3_ = 0.0;
    float sampleAlong_1_ = 0.0;
    float p0Root_0_ = 0.0;
    float p1Root_0_ = 0.0;
    float p2Root_0_ = 0.0;
    float p0Along_0_ = 0.0;
    float p1Along_0_ = 0.0;
    float p2Along_0_ = 0.0;
    float _S33_ = 0.0;
    float c0_0_ = 0.0;
    float _S34_ = 0.0;
    float c1_0_ = 0.0;
    float _S35_ = 0.0;
    float c2_0_ = 0.0;
    uint code_0_ = 0u;
    float param_80 = 0.0;
    float param_81 = 0.0;
    float param_82 = 0.0;
    int want_0_ = 0;
    float quadA_0_ = 0.0;
    float quadB_0_ = 0.0;
    float _S36_ = 0.0;
    int ncand_0_ = 0;
    float cand1_0_ = 0.0;
    float _S37_ = 0.0;
    float cand0_0_ = 0.0;
    float sqrtDisc_0_ = 0.0;
    float inv2a_0_ = 0.0;
    float _S38_ = 0.0;
    float _S39_ = 0.0;
    float _S40_ = 0.0;
    bool _S41_ = false;
    float param_83 = 0.0;
    float param_84 = 0.0;
    float root0_0_ = 0.0;
    int rootCount_0_ = 0;
    float root1_0_ = 0.0;
    float _S42_ = 0.0;
    float _S43_ = 0.0;
    float rootA_1_ = 0.0;
    float rootB_1_ = 0.0;
    float _S44_ = 0.0;
    float alongA_1_ = 0.0;
    float alongB_1_ = 0.0;
    float denA_1_ = 0.0;
    float denB_1_ = 0.0;
    float endRootDelta_1_ = 0.0;
    SegmentData_0_ param_85 = SegmentData_0_(0, vec2(0.0), vec2(0.0), vec2(0.0), vec2(0.0), vec3(0.0));
    vec2 param_86 = vec2(0.0);
    bool param_87 = false;
    float param_88 = 0.0;
    float param_89 = 0.0;
    float param_90 = 0.0;
    float param_91 = 0.0;
    float param_92 = 0.0;
    float param_93 = 0.0;
    bool param_94 = false;
    float param_95 = 0.0;
    float param_96 = 0.0;
    float param_97 = 0.0;
    float param_98 = 0.0;
    float param_99 = 0.0;
    float param_100 = 0.0;
    float param_101 = 0.0;
    float param_102 = 0.0;
    float param_103 = 0.0;
    float param_104 = 0.0;
    float param_105 = 0.0;
    float param_106 = 0.0;
    float param_107 = 0.0;
    float param_108 = 0.0;
    float param_109 = 0.0;
    bool param_110 = false;
    float param_111 = 0.0;
    float param_112 = 0.0;
    float param_113 = 0.0;
    float param_114 = 0.0;
    float param_115 = 0.0;
    float param_116 = 0.0;
    float param_117 = 0.0;
    float param_118 = 0.0;
    float param_119 = 0.0;
    SegmentData_0_ _e173 = seg_5_;
    param_77 = _e173;
    vec2 _e174 = sampleRc_2_;
    param_78 = _e174;
    bool _e175 = horizontal_4_;
    param_79 = _e175;
    bool _e176 = segmentRootHullCanCross_0_u0028_struct_u002d_SegmentData_0_u002d_i1_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf31_u003b_vf2_u003b_b1_u003b(param_77, param_78, param_79);
    if (!(_e176)) {
        return;
    }
    bool _e178 = horizontal_4_;
    if (_e178) {
        float _e180 = sampleRc_2_[1u];
        sampleRoot_3_ = _e180;
    } else {
        float _e182 = sampleRc_2_[0u];
        sampleRoot_3_ = _e182;
    }
    bool _e183 = horizontal_4_;
    if (_e183) {
        float _e185 = sampleRc_2_[0u];
        sampleAlong_1_ = _e185;
    } else {
        float _e187 = sampleRc_2_[1u];
        sampleAlong_1_ = _e187;
    }
    bool _e188 = horizontal_4_;
    if (_e188) {
        float _e191 = seg_5_.p0_0_[1u];
        p0Root_0_ = _e191;
    } else {
        float _e194 = seg_5_.p0_0_[0u];
        p0Root_0_ = _e194;
    }
    bool _e195 = horizontal_4_;
    if (_e195) {
        float _e198 = seg_5_.p1_0_[1u];
        p1Root_0_ = _e198;
    } else {
        float _e201 = seg_5_.p1_0_[0u];
        p1Root_0_ = _e201;
    }
    bool _e202 = horizontal_4_;
    if (_e202) {
        float _e205 = seg_5_.p2_0_[1u];
        p2Root_0_ = _e205;
    } else {
        float _e208 = seg_5_.p2_0_[0u];
        p2Root_0_ = _e208;
    }
    bool _e209 = horizontal_4_;
    if (_e209) {
        float _e212 = seg_5_.p0_0_[0u];
        p0Along_0_ = _e212;
    } else {
        float _e215 = seg_5_.p0_0_[1u];
        p0Along_0_ = _e215;
    }
    bool _e216 = horizontal_4_;
    if (_e216) {
        float _e219 = seg_5_.p1_0_[0u];
        p1Along_0_ = _e219;
    } else {
        float _e222 = seg_5_.p1_0_[1u];
        p1Along_0_ = _e222;
    }
    bool _e223 = horizontal_4_;
    if (_e223) {
        float _e226 = seg_5_.p2_0_[0u];
        p2Along_0_ = _e226;
    } else {
        float _e229 = seg_5_.p2_0_[1u];
        p2Along_0_ = _e229;
    }
    float _e232 = seg_5_.weights_0_[0u];
    _S33_ = _e232;
    float _e233 = _S33_;
    float _e234 = p0Root_0_;
    float _e235 = sampleRoot_3_;
    c0_0_ = (_e233 * (_e234 - _e235));
    float _e240 = seg_5_.weights_0_[1u];
    _S34_ = _e240;
    float _e241 = _S34_;
    float _e242 = p1Root_0_;
    float _e243 = sampleRoot_3_;
    c1_0_ = (_e241 * (_e242 - _e243));
    float _e248 = seg_5_.weights_0_[2u];
    _S35_ = _e248;
    float _e249 = _S35_;
    float _e250 = p2Root_0_;
    float _e251 = sampleRoot_3_;
    c2_0_ = (_e249 * (_e250 - _e251));
    float _e254 = c0_0_;
    param_80 = _e254;
    float _e255 = c1_0_;
    param_81 = _e255;
    float _e256 = c2_0_;
    param_82 = _e256;
    uint _e257 = calcRootCode_0_u0028_f1_u003b_f1_u003b_f1_u003b(param_80, param_81, param_82);
    code_0_ = _e257;
    uint _e258 = code_0_;
    if ((_e258 == 0u)) {
        return;
    }
    uint _e260 = code_0_;
    if ((_e260 == 257u)) {
        want_0_ = 2;
    } else {
        want_0_ = 1;
    }
    float _e262 = c0_0_;
    float _e263 = c1_0_;
    float _e266 = c2_0_;
    quadA_0_ = ((_e262 - (2.0 * _e263)) + _e266);
    float _e268 = c1_0_;
    float _e269 = c0_0_;
    quadB_0_ = (2.0 * (_e268 - _e269));
    float _e272 = quadA_0_;
    if ((abs(_e272) < 1.5258789e-5)) {
        float _e275 = quadB_0_;
        if ((abs(_e275) >= 1.5258789e-5)) {
            float _e278 = c0_0_;
            float _e280 = quadB_0_;
            _S36_ = (-(_e278) / _e280);
            ncand_0_ = 1;
            float _e282 = _S36_;
            cand1_0_ = _e282;
        } else {
            ncand_0_ = 0;
            cand1_0_ = 0.0;
        }
        float _e283 = cand1_0_;
        _S37_ = _e283;
        cand1_0_ = 0.0;
        float _e284 = _S37_;
        cand0_0_ = _e284;
    } else {
        float _e285 = quadB_0_;
        float _e286 = quadB_0_;
        float _e288 = quadA_0_;
        float _e290 = c0_0_;
        sqrtDisc_0_ = sqrt(max(((_e285 * _e286) - ((4.0 * _e288) * _e290)), 0.0));
        float _e295 = quadA_0_;
        inv2a_0_ = (0.5 / _e295);
        float _e297 = quadB_0_;
        _S38_ = -(_e297);
        float _e299 = _S38_;
        float _e300 = sqrtDisc_0_;
        float _e302 = inv2a_0_;
        _S39_ = ((_e299 - _e300) * _e302);
        float _e304 = _S38_;
        float _e305 = sqrtDisc_0_;
        float _e307 = inv2a_0_;
        _S40_ = ((_e304 + _e305) * _e307);
        ncand_0_ = 2;
        float _e309 = _S40_;
        cand1_0_ = _e309;
        float _e310 = _S39_;
        cand0_0_ = _e310;
    }
    int _e311 = ncand_0_;
    if ((_e311 == 0)) {
        return;
    }
    int _e313 = want_0_;
    if ((_e313 == 1)) {
        int _e315 = ncand_0_;
        if ((_e315 == 2)) {
            float _e317 = cand1_0_;
            param_83 = _e317;
            float _e318 = distToUnitInterval_0_u0028_f1_u003b(param_83);
            float _e319 = cand0_0_;
            param_84 = _e319;
            float _e320 = distToUnitInterval_0_u0028_f1_u003b(param_84);
            _S41_ = (_e318 < _e320);
        } else {
            _S41_ = false;
        }
        bool _e322 = _S41_;
        if (_e322) {
            float _e323 = cand1_0_;
            root0_0_ = _e323;
        } else {
            float _e324 = cand0_0_;
            root0_0_ = _e324;
        }
        float _e325 = root0_0_;
        root0_0_ = clamp(_e325, 0.0, 1.0);
        rootCount_0_ = 1;
        root1_0_ = 0.0;
    } else {
        float _e327 = cand1_0_;
        _S42_ = clamp(_e327, 0.0, 1.0);
        float _e329 = cand0_0_;
        root0_0_ = clamp(_e329, 0.0, 1.0);
        rootCount_0_ = 2;
        float _e331 = _S42_;
        root1_0_ = _e331;
    }
    float _e332 = p0Root_0_;
    float _e333 = _S33_;
    _S43_ = (_e332 * _e333);
    float _e335 = _S43_;
    float _e336 = p1Root_0_;
    float _e338 = _S34_;
    float _e341 = p2Root_0_;
    float _e342 = _S35_;
    rootA_1_ = ((_e335 - ((2.0 * _e336) * _e338)) + (_e341 * _e342));
    float _e345 = p1Root_0_;
    float _e346 = _S34_;
    float _e348 = _S43_;
    rootB_1_ = (2.0 * ((_e345 * _e346) - _e348));
    float _e351 = p0Along_0_;
    float _e352 = _S33_;
    _S44_ = (_e351 * _e352);
    float _e354 = _S44_;
    float _e355 = p1Along_0_;
    float _e357 = _S34_;
    float _e360 = p2Along_0_;
    float _e361 = _S35_;
    alongA_1_ = ((_e354 - ((2.0 * _e355) * _e357)) + (_e360 * _e361));
    float _e364 = p1Along_0_;
    float _e365 = _S34_;
    float _e367 = _S44_;
    alongB_1_ = (2.0 * ((_e364 * _e365) - _e367));
    float _e370 = _S33_;
    float _e371 = _S34_;
    float _e374 = _S35_;
    denA_1_ = ((_e370 - (2.0 * _e371)) + _e374);
    float _e376 = _S34_;
    float _e377 = _S33_;
    denB_1_ = (2.0 * (_e376 - _e377));
    SegmentData_0_ _e380 = seg_5_;
    param_85 = _e380;
    vec2 _e381 = sampleRc_2_;
    param_86 = _e381;
    bool _e382 = horizontal_4_;
    param_87 = _e382;
    float _e383 = segmentEndRootDelta_0_u0028_struct_u002d_SegmentData_0_u002d_i1_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf31_u003b_vf2_u003b_b1_u003b(param_85, param_86, param_87);
    endRootDelta_1_ = _e383;
    float _e384 = cov_3_;
    param_88 = _e384;
    float _e385 = wgt_3_;
    param_89 = _e385;
    float _e386 = root0_0_;
    param_90 = _e386;
    float _e387 = endRootDelta_1_;
    param_91 = _e387;
    float _e388 = sampleAlong_1_;
    param_92 = _e388;
    float _e389 = ppe_2_;
    param_93 = _e389;
    bool _e390 = horizontal_4_;
    param_94 = _e390;
    float _e391 = rootA_1_;
    param_95 = _e391;
    float _e392 = rootB_1_;
    param_96 = _e392;
    float _e393 = _S43_;
    param_97 = _e393;
    float _e394 = alongA_1_;
    param_98 = _e394;
    float _e395 = alongB_1_;
    param_99 = _e395;
    float _e396 = _S44_;
    param_100 = _e396;
    float _e397 = denA_1_;
    param_101 = _e397;
    float _e398 = denB_1_;
    param_102 = _e398;
    float _e399 = _S33_;
    param_103 = _e399;
    accumulateConicRoot_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_b1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b(param_88, param_89, param_90, param_91, param_92, param_93, param_94, param_95, param_96, param_97, param_98, param_99, param_100, param_101, param_102, param_103);
    float _e400 = param_88;
    cov_3_ = _e400;
    float _e401 = param_89;
    wgt_3_ = _e401;
    int _e402 = rootCount_0_;
    if ((_e402 == 2)) {
        float _e404 = cov_3_;
        param_104 = _e404;
        float _e405 = wgt_3_;
        param_105 = _e405;
        float _e406 = root1_0_;
        param_106 = _e406;
        float _e407 = endRootDelta_1_;
        param_107 = _e407;
        float _e408 = sampleAlong_1_;
        param_108 = _e408;
        float _e409 = ppe_2_;
        param_109 = _e409;
        bool _e410 = horizontal_4_;
        param_110 = _e410;
        float _e411 = rootA_1_;
        param_111 = _e411;
        float _e412 = rootB_1_;
        param_112 = _e412;
        float _e413 = _S43_;
        param_113 = _e413;
        float _e414 = alongA_1_;
        param_114 = _e414;
        float _e415 = alongB_1_;
        param_115 = _e415;
        float _e416 = _S44_;
        param_116 = _e416;
        float _e417 = denA_1_;
        param_117 = _e417;
        float _e418 = denB_1_;
        param_118 = _e418;
        float _e419 = _S33_;
        param_119 = _e419;
        accumulateConicRoot_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_b1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b(param_104, param_105, param_106, param_107, param_108, param_109, param_110, param_111, param_112, param_113, param_114, param_115, param_116, param_117, param_118, param_119);
        float _e420 = param_104;
        cov_3_ = _e420;
        float _e421 = param_105;
        wgt_3_ = _e421;
    }
    return;
}

void accumulateLineCoverage_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_b1_u003b(inout float cov_1_, inout float wgt_1_, inout float p0x_2_, inout float p0y_2_, inout float p2x_2_, inout float p2y_2_, inout float ppe_0_, inout bool horizontal_0_) {
    float rootAxis0_0_ = 0.0;
    float rootAxis2_0_ = 0.0;
    float param_120 = 0.0;
    float param_121 = 0.0;
    float denom_0_ = 0.0;
    float t_0_ = 0.0;
    float derivativeAxis_0_ = 0.0;
    float distance_1_ = 0.0;
    float param_122 = 0.0;
    float param_123 = 0.0;
    float param_124 = 0.0;
    float param_125 = 0.0;
    bool _e102 = horizontal_0_;
    if (_e102) {
        float _e103 = p0y_2_;
        rootAxis0_0_ = _e103;
    } else {
        float _e104 = p0x_2_;
        rootAxis0_0_ = _e104;
    }
    bool _e105 = horizontal_0_;
    if (_e105) {
        float _e106 = p2y_2_;
        rootAxis2_0_ = _e106;
    } else {
        float _e107 = p2x_2_;
        rootAxis2_0_ = _e107;
    }
    float _e108 = rootAxis0_0_;
    param_120 = _e108;
    float _e109 = rootCodeCoord_0_u0028_f1_u003b(param_120);
    float _e111 = rootAxis2_0_;
    param_121 = _e111;
    float _e112 = rootCodeCoord_0_u0028_f1_u003b(param_121);
    if (((_e109 < 0.0) == (_e112 < 0.0))) {
        return;
    }
    float _e115 = rootAxis2_0_;
    float _e116 = rootAxis0_0_;
    denom_0_ = (_e115 - _e116);
    float _e118 = denom_0_;
    if ((abs(_e118) < 1e-10)) {
        return;
    }
    float _e121 = rootAxis0_0_;
    float _e123 = denom_0_;
    t_0_ = clamp((-(_e121) / _e123), 0.0, 1.0);
    bool _e126 = horizontal_0_;
    if (_e126) {
        float _e127 = p2y_2_;
        float _e128 = p0y_2_;
        derivativeAxis_0_ = (_e127 - _e128);
    } else {
        float _e130 = p0x_2_;
        float _e131 = p2x_2_;
        derivativeAxis_0_ = (_e130 - _e131);
    }
    float _e133 = derivativeAxis_0_;
    if ((abs(_e133) <= 1e-5)) {
        return;
    }
    bool _e136 = horizontal_0_;
    if (_e136) {
        float _e137 = p0x_2_;
        float _e138 = p2x_2_;
        float _e139 = p0x_2_;
        float _e141 = t_0_;
        rootAxis0_0_ = (_e137 + ((_e138 - _e139) * _e141));
    } else {
        float _e144 = p0y_2_;
        float _e145 = p2y_2_;
        float _e146 = p0y_2_;
        float _e148 = t_0_;
        rootAxis0_0_ = (_e144 + ((_e145 - _e146) * _e148));
    }
    float _e151 = rootAxis0_0_;
    float _e152 = ppe_0_;
    distance_1_ = (_e151 * _e152);
    float _e154 = derivativeAxis_0_;
    if ((_e154 > 0.0)) {
        rootAxis0_0_ = 1.0;
    } else {
        rootAxis0_0_ = -1.0;
    }
    float _e156 = cov_1_;
    param_122 = _e156;
    float _e157 = wgt_1_;
    param_123 = _e157;
    float _e158 = distance_1_;
    param_124 = _e158;
    float _e159 = rootAxis0_0_;
    param_125 = _e159;
    appendCoverageContribution_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b(param_122, param_123, param_124, param_125);
    float _e160 = param_122;
    cov_1_ = _e160;
    float _e161 = param_123;
    wgt_1_ = _e161;
    return;
}

float snapNearTangentSqrt_0_u0028_f1_u003b_f1_u003b_f1_u003b(inout float disc_0_, inout float b_0_, inout float ac_0_) {
    float _S12_ = 0.0;
    float _e86 = disc_0_;
    float _e87 = b_0_;
    float _e88 = b_0_;
    float _e90 = ac_0_;
    if ((_e86 <= (max((_e87 * _e88), abs(_e90)) * 3e-6))) {
        _S12_ = 0.0;
    } else {
        float _e95 = disc_0_;
        _S12_ = sqrt(_e95);
    }
    float _e97 = _S12_;
    return _e97;
}

vec2 solveQuadraticVertDistances_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b(inout float p0x_1_, inout float p0y_1_, inout float p1x_1_, inout float p1y_1_, inout float p2x_1_, inout float p2y_1_, inout float ppeY_0_) {
    float ax_1_ = 0.0;
    float ay_1_ = 0.0;
    float bx_1_ = 0.0;
    float by_1_ = 0.0;
    float t1_1_ = 0.0;
    float t2_1_ = 0.0;
    float _S18_ = 0.0;
    float sq_1_ = 0.0;
    float param_126 = 0.0;
    float param_127 = 0.0;
    float param_128 = 0.0;
    float q_2_ = 0.0;
    float _S19_ = 0.0;
    float q_3_ = 0.0;
    float _S20_ = 0.0;
    float _S21_ = 0.0;
    float _S22_ = 0.0;
    float _e106 = p0x_1_;
    float _e107 = p1x_1_;
    float _e110 = p2x_1_;
    ax_1_ = ((_e106 - (_e107 * 2.0)) + _e110);
    float _e112 = p0y_1_;
    float _e113 = p1y_1_;
    float _e116 = p2y_1_;
    ay_1_ = ((_e112 - (_e113 * 2.0)) + _e116);
    float _e118 = p0x_1_;
    float _e119 = p1x_1_;
    bx_1_ = (_e118 - _e119);
    float _e121 = p0y_1_;
    float _e122 = p1y_1_;
    by_1_ = (_e121 - _e122);
    float _e124 = ax_1_;
    if ((abs(_e124) < 1.5258789e-5)) {
        float _e127 = bx_1_;
        if ((abs(_e127) < 1.5258789e-5)) {
            t1_1_ = 0.0;
        } else {
            float _e130 = p0x_1_;
            float _e132 = bx_1_;
            t1_1_ = ((_e130 * 0.5) / _e132);
        }
        float _e134 = t1_1_;
        t2_1_ = _e134;
    } else {
        float _e135 = ax_1_;
        float _e136 = p0x_1_;
        _S18_ = (_e135 * _e136);
        float _e138 = bx_1_;
        float _e139 = bx_1_;
        float _e141 = _S18_;
        param_126 = ((_e138 * _e139) - _e141);
        float _e143 = bx_1_;
        param_127 = _e143;
        float _e144 = _S18_;
        param_128 = _e144;
        float _e145 = snapNearTangentSqrt_0_u0028_f1_u003b_f1_u003b_f1_u003b(param_126, param_127, param_128);
        sq_1_ = _e145;
        float _e146 = bx_1_;
        if ((_e146 >= 0.0)) {
            float _e148 = bx_1_;
            float _e149 = sq_1_;
            q_2_ = (_e148 + _e149);
            float _e151 = q_2_;
            float _e152 = ax_1_;
            _S19_ = (_e151 / _e152);
            float _e154 = q_2_;
            if ((abs(_e154) < 1.5258789e-5)) {
                t1_1_ = 0.0;
            } else {
                float _e157 = p0x_1_;
                float _e158 = q_2_;
                t1_1_ = (_e157 / _e158);
            }
            float _e160 = _S19_;
            t2_1_ = _e160;
        } else {
            float _e161 = bx_1_;
            float _e162 = sq_1_;
            q_3_ = (_e161 - _e162);
            float _e164 = q_3_;
            float _e165 = ax_1_;
            _S20_ = (_e164 / _e165);
            float _e167 = q_3_;
            if ((abs(_e167) < 1.5258789e-5)) {
                t1_1_ = 0.0;
            } else {
                float _e170 = p0x_1_;
                float _e171 = q_3_;
                t1_1_ = (_e170 / _e171);
            }
            float _e173 = t1_1_;
            _S21_ = _e173;
            float _e174 = _S20_;
            t1_1_ = _e174;
            float _e175 = _S21_;
            t2_1_ = _e175;
        }
    }
    float _e176 = by_1_;
    _S22_ = (_e176 * 2.0);
    float _e178 = ay_1_;
    float _e179 = t1_1_;
    float _e181 = _S22_;
    float _e183 = t1_1_;
    float _e185 = p0y_1_;
    float _e187 = ppeY_0_;
    float _e189 = ay_1_;
    float _e190 = t2_1_;
    float _e192 = _S22_;
    float _e194 = t2_1_;
    float _e196 = p0y_1_;
    float _e198 = ppeY_0_;
    return vec2((((((_e178 * _e179) - _e181) * _e183) + _e185) * _e187), (((((_e189 * _e190) - _e192) * _e194) + _e196) * _e198));
}

vec2 solveQuadraticHorizDistances_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b(inout float p0x_0_, inout float p0y_0_, inout float p1x_0_, inout float p1y_0_, inout float p2x_0_, inout float p2y_0_, inout float ppeX_0_) {
    float ax_0_ = 0.0;
    float ay_0_ = 0.0;
    float bx_0_ = 0.0;
    float by_0_ = 0.0;
    float t1_0_ = 0.0;
    float t2_0_ = 0.0;
    float _S13_ = 0.0;
    float sq_0_ = 0.0;
    float param_129 = 0.0;
    float param_130 = 0.0;
    float param_131 = 0.0;
    float q_0_ = 0.0;
    float _S14_ = 0.0;
    float q_1_ = 0.0;
    float _S15_ = 0.0;
    float _S16_ = 0.0;
    float _S17_ = 0.0;
    float _e106 = p0x_0_;
    float _e107 = p1x_0_;
    float _e110 = p2x_0_;
    ax_0_ = ((_e106 - (_e107 * 2.0)) + _e110);
    float _e112 = p0y_0_;
    float _e113 = p1y_0_;
    float _e116 = p2y_0_;
    ay_0_ = ((_e112 - (_e113 * 2.0)) + _e116);
    float _e118 = p0x_0_;
    float _e119 = p1x_0_;
    bx_0_ = (_e118 - _e119);
    float _e121 = p0y_0_;
    float _e122 = p1y_0_;
    by_0_ = (_e121 - _e122);
    float _e124 = ay_0_;
    if ((abs(_e124) < 1.5258789e-5)) {
        float _e127 = by_0_;
        if ((abs(_e127) < 1.5258789e-5)) {
            t1_0_ = 0.0;
        } else {
            float _e130 = p0y_0_;
            float _e132 = by_0_;
            t1_0_ = ((_e130 * 0.5) / _e132);
        }
        float _e134 = t1_0_;
        t2_0_ = _e134;
    } else {
        float _e135 = ay_0_;
        float _e136 = p0y_0_;
        _S13_ = (_e135 * _e136);
        float _e138 = by_0_;
        float _e139 = by_0_;
        float _e141 = _S13_;
        param_129 = ((_e138 * _e139) - _e141);
        float _e143 = by_0_;
        param_130 = _e143;
        float _e144 = _S13_;
        param_131 = _e144;
        float _e145 = snapNearTangentSqrt_0_u0028_f1_u003b_f1_u003b_f1_u003b(param_129, param_130, param_131);
        sq_0_ = _e145;
        float _e146 = by_0_;
        if ((_e146 >= 0.0)) {
            float _e148 = by_0_;
            float _e149 = sq_0_;
            q_0_ = (_e148 + _e149);
            float _e151 = q_0_;
            float _e152 = ay_0_;
            _S14_ = (_e151 / _e152);
            float _e154 = q_0_;
            if ((abs(_e154) < 1.5258789e-5)) {
                t1_0_ = 0.0;
            } else {
                float _e157 = p0y_0_;
                float _e158 = q_0_;
                t1_0_ = (_e157 / _e158);
            }
            float _e160 = _S14_;
            t2_0_ = _e160;
        } else {
            float _e161 = by_0_;
            float _e162 = sq_0_;
            q_1_ = (_e161 - _e162);
            float _e164 = q_1_;
            float _e165 = ay_0_;
            _S15_ = (_e164 / _e165);
            float _e167 = q_1_;
            if ((abs(_e167) < 1.5258789e-5)) {
                t1_0_ = 0.0;
            } else {
                float _e170 = p0y_0_;
                float _e171 = q_1_;
                t1_0_ = (_e170 / _e171);
            }
            float _e173 = t1_0_;
            _S16_ = _e173;
            float _e174 = _S15_;
            t1_0_ = _e174;
            float _e175 = _S16_;
            t2_0_ = _e175;
        }
    }
    float _e176 = bx_0_;
    _S17_ = (_e176 * 2.0);
    float _e178 = ax_0_;
    float _e179 = t1_0_;
    float _e181 = _S17_;
    float _e183 = t1_0_;
    float _e185 = p0x_0_;
    float _e187 = ppeX_0_;
    float _e189 = ax_0_;
    float _e190 = t2_0_;
    float _e192 = _S17_;
    float _e194 = t2_0_;
    float _e196 = p0x_0_;
    float _e198 = ppeX_0_;
    return vec2((((((_e178 * _e179) - _e181) * _e183) + _e185) * _e187), (((((_e189 * _e190) - _e192) * _e194) + _e196) * _e198));
}

float segmentMaxY_0_u0028_struct_u002d_SegmentData_0_u002d_i1_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf31_u003b(inout SegmentData_0_ seg_2_) {
    int _e84 = seg_2_.kind_0_;
    if ((_e84 == 3)) {
        float _e88 = seg_2_.p0_0_[1u];
        float _e91 = seg_2_.p2_0_[1u];
        return max(_e88, _e91);
    }
    int _e94 = seg_2_.kind_0_;
    if ((_e94 == 2)) {
        float _e98 = seg_2_.p0_0_[1u];
        float _e101 = seg_2_.p1_0_[1u];
        float _e105 = seg_2_.p2_0_[1u];
        float _e108 = seg_2_.p3_0_[1u];
        return max(max(_e98, _e101), max(_e105, _e108));
    }
    float _e113 = seg_2_.p0_0_[1u];
    float _e116 = seg_2_.p1_0_[1u];
    float _e120 = seg_2_.p2_0_[1u];
    return max(max(_e113, _e116), _e120);
}

float segmentMaxX_0_u0028_struct_u002d_SegmentData_0_u002d_i1_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf31_u003b(inout SegmentData_0_ seg_1_) {
    int _e84 = seg_1_.kind_0_;
    if ((_e84 == 3)) {
        float _e88 = seg_1_.p0_0_[0u];
        float _e91 = seg_1_.p2_0_[0u];
        return max(_e88, _e91);
    }
    int _e94 = seg_1_.kind_0_;
    if ((_e94 == 2)) {
        float _e98 = seg_1_.p0_0_[0u];
        float _e101 = seg_1_.p1_0_[0u];
        float _e105 = seg_1_.p2_0_[0u];
        float _e108 = seg_1_.p3_0_[0u];
        return max(max(_e98, _e101), max(_e105, _e108));
    }
    float _e113 = seg_1_.p0_0_[0u];
    float _e116 = seg_1_.p1_0_[0u];
    float _e120 = seg_1_.p2_0_[0u];
    return max(max(_e113, _e116), _e120);
}

bool accumulateAxisCoverageSegment_0_u0028_f1_u003b_f1_u003b_vf2_u003b_f1_u003b_struct_u002d_SegmentData_0_u002d_i1_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf31_u003b_b1_u003b(inout float cov_5_, inout float wgt_5_, inout vec2 sampleRc_4_, inout float ppe_4_, inout SegmentData_0_ seg_7_, inout bool horizontal_6_) {
    float maxCoord_0_ = 0.0;
    SegmentData_0_ param_132 = SegmentData_0_(0, vec2(0.0), vec2(0.0), vec2(0.0), vec2(0.0), vec3(0.0));
    SegmentData_0_ param_133 = SegmentData_0_(0, vec2(0.0), vec2(0.0), vec2(0.0), vec2(0.0), vec3(0.0));
    float _S56_ = 0.0;
    float p0x_3_ = 0.0;
    float _S57_ = 0.0;
    float p0y_3_ = 0.0;
    float p1x_2_ = 0.0;
    float p1y_2_ = 0.0;
    float p2x_3_ = 0.0;
    float p2y_3_ = 0.0;
    uint code_1_ = 0u;
    float param_134 = 0.0;
    float param_135 = 0.0;
    float param_136 = 0.0;
    float param_137 = 0.0;
    float param_138 = 0.0;
    float param_139 = 0.0;
    vec2 roots_0_ = vec2(0.0);
    float param_140 = 0.0;
    float param_141 = 0.0;
    float param_142 = 0.0;
    float param_143 = 0.0;
    float param_144 = 0.0;
    float param_145 = 0.0;
    float param_146 = 0.0;
    float param_147 = 0.0;
    float param_148 = 0.0;
    float param_149 = 0.0;
    float param_150 = 0.0;
    float param_151 = 0.0;
    float param_152 = 0.0;
    float param_153 = 0.0;
    float _S58_ = 0.0;
    float param_154 = 0.0;
    float param_155 = 0.0;
    float param_156 = 0.0;
    float param_157 = 0.0;
    float _S59_ = 0.0;
    float param_158 = 0.0;
    float param_159 = 0.0;
    float param_160 = 0.0;
    float param_161 = 0.0;
    float _S60_ = 0.0;
    float _S61_ = 0.0;
    float param_162 = 0.0;
    float param_163 = 0.0;
    float param_164 = 0.0;
    float param_165 = 0.0;
    float param_166 = 0.0;
    float param_167 = 0.0;
    float param_168 = 0.0;
    bool param_169 = false;
    float param_170 = 0.0;
    float param_171 = 0.0;
    SegmentData_0_ param_172 = SegmentData_0_(0, vec2(0.0), vec2(0.0), vec2(0.0), vec2(0.0), vec3(0.0));
    vec2 param_173 = vec2(0.0);
    float param_174 = 0.0;
    bool param_175 = false;
    float param_176 = 0.0;
    float param_177 = 0.0;
    SegmentData_0_ param_178 = SegmentData_0_(0, vec2(0.0), vec2(0.0), vec2(0.0), vec2(0.0), vec3(0.0));
    vec2 param_179 = vec2(0.0);
    float param_180 = 0.0;
    bool param_181 = false;
    bool _e153 = horizontal_6_;
    if (_e153) {
        SegmentData_0_ _e154 = seg_7_;
        param_132 = _e154;
        float _e155 = segmentMaxX_0_u0028_struct_u002d_SegmentData_0_u002d_i1_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf31_u003b(param_132);
        float _e157 = sampleRc_4_[0u];
        maxCoord_0_ = (_e155 - _e157);
    } else {
        SegmentData_0_ _e159 = seg_7_;
        param_133 = _e159;
        float _e160 = segmentMaxY_0_u0028_struct_u002d_SegmentData_0_u002d_i1_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf31_u003b(param_133);
        float _e162 = sampleRc_4_[1u];
        maxCoord_0_ = (_e160 - _e162);
    }
    float _e164 = maxCoord_0_;
    float _e165 = ppe_4_;
    if (((_e164 * _e165) < -0.5)) {
        return false;
    }
    int _e169 = seg_7_.kind_0_;
    if ((_e169 == 0)) {
        float _e172 = sampleRc_4_[0u];
        _S56_ = _e172;
        float _e175 = seg_7_.p0_0_[0u];
        float _e176 = _S56_;
        p0x_3_ = (_e175 - _e176);
        float _e179 = sampleRc_4_[1u];
        _S57_ = _e179;
        float _e182 = seg_7_.p0_0_[1u];
        float _e183 = _S57_;
        p0y_3_ = (_e182 - _e183);
        float _e187 = seg_7_.p1_0_[0u];
        float _e188 = _S56_;
        p1x_2_ = (_e187 - _e188);
        float _e192 = seg_7_.p1_0_[1u];
        float _e193 = _S57_;
        p1y_2_ = (_e192 - _e193);
        float _e197 = seg_7_.p2_0_[0u];
        float _e198 = _S56_;
        p2x_3_ = (_e197 - _e198);
        float _e202 = seg_7_.p2_0_[1u];
        float _e203 = _S57_;
        p2y_3_ = (_e202 - _e203);
        bool _e205 = horizontal_6_;
        if (_e205) {
            float _e206 = p0y_3_;
            param_134 = _e206;
            float _e207 = p1y_2_;
            param_135 = _e207;
            float _e208 = p2y_3_;
            param_136 = _e208;
            uint _e209 = calcRootCode_0_u0028_f1_u003b_f1_u003b_f1_u003b(param_134, param_135, param_136);
            code_1_ = _e209;
        } else {
            float _e210 = p0x_3_;
            param_137 = _e210;
            float _e211 = p1x_2_;
            param_138 = _e211;
            float _e212 = p2x_3_;
            param_139 = _e212;
            uint _e213 = calcRootCode_0_u0028_f1_u003b_f1_u003b_f1_u003b(param_137, param_138, param_139);
            code_1_ = _e213;
        }
        uint _e214 = code_1_;
        if ((_e214 == 0u)) {
            return true;
        }
        bool _e216 = horizontal_6_;
        if (_e216) {
            float _e217 = p0x_3_;
            param_140 = _e217;
            float _e218 = p0y_3_;
            param_141 = _e218;
            float _e219 = p1x_2_;
            param_142 = _e219;
            float _e220 = p1y_2_;
            param_143 = _e220;
            float _e221 = p2x_3_;
            param_144 = _e221;
            float _e222 = p2y_3_;
            param_145 = _e222;
            float _e223 = ppe_4_;
            param_146 = _e223;
            vec2 _e224 = solveQuadraticHorizDistances_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b(param_140, param_141, param_142, param_143, param_144, param_145, param_146);
            roots_0_ = _e224;
        } else {
            float _e225 = p0x_3_;
            param_147 = _e225;
            float _e226 = p0y_3_;
            param_148 = _e226;
            float _e227 = p1x_2_;
            param_149 = _e227;
            float _e228 = p1y_2_;
            param_150 = _e228;
            float _e229 = p2x_3_;
            param_151 = _e229;
            float _e230 = p2y_3_;
            param_152 = _e230;
            float _e231 = ppe_4_;
            param_153 = _e231;
            vec2 _e232 = solveQuadraticVertDistances_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b(param_147, param_148, param_149, param_150, param_151, param_152, param_153);
            roots_0_ = _e232;
        }
        uint _e233 = code_1_;
        if (((_e233 & 1u) != 0u)) {
            float _e237 = roots_0_[0u];
            _S58_ = _e237;
            bool _e238 = horizontal_6_;
            if (_e238) {
                maxCoord_0_ = 1.0;
            } else {
                maxCoord_0_ = -1.0;
            }
            float _e239 = cov_5_;
            param_154 = _e239;
            float _e240 = wgt_5_;
            param_155 = _e240;
            float _e241 = _S58_;
            param_156 = _e241;
            float _e242 = maxCoord_0_;
            param_157 = _e242;
            appendCoverageContribution_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b(param_154, param_155, param_156, param_157);
            float _e243 = param_154;
            cov_5_ = _e243;
            float _e244 = param_155;
            wgt_5_ = _e244;
        }
        uint _e245 = code_1_;
        if ((_e245 > 1u)) {
            float _e248 = roots_0_[1u];
            _S59_ = _e248;
            bool _e249 = horizontal_6_;
            if (_e249) {
                maxCoord_0_ = -1.0;
            } else {
                maxCoord_0_ = 1.0;
            }
            float _e250 = cov_5_;
            param_158 = _e250;
            float _e251 = wgt_5_;
            param_159 = _e251;
            float _e252 = _S59_;
            param_160 = _e252;
            float _e253 = maxCoord_0_;
            param_161 = _e253;
            appendCoverageContribution_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b(param_158, param_159, param_160, param_161);
            float _e254 = param_158;
            cov_5_ = _e254;
            float _e255 = param_159;
            wgt_5_ = _e255;
        }
        return true;
    }
    int _e257 = seg_7_.kind_0_;
    if ((_e257 == 3)) {
        float _e260 = sampleRc_4_[0u];
        _S60_ = _e260;
        float _e262 = sampleRc_4_[1u];
        _S61_ = _e262;
        float _e265 = seg_7_.p0_0_[0u];
        float _e266 = _S60_;
        float _e270 = seg_7_.p0_0_[1u];
        float _e271 = _S61_;
        float _e275 = seg_7_.p2_0_[0u];
        float _e276 = _S60_;
        float _e280 = seg_7_.p2_0_[1u];
        float _e281 = _S61_;
        float _e283 = cov_5_;
        param_162 = _e283;
        float _e284 = wgt_5_;
        param_163 = _e284;
        param_164 = (_e265 - _e266);
        param_165 = (_e270 - _e271);
        param_166 = (_e275 - _e276);
        param_167 = (_e280 - _e281);
        float _e285 = ppe_4_;
        param_168 = _e285;
        bool _e286 = horizontal_6_;
        param_169 = _e286;
        accumulateLineCoverage_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_f1_u003b_b1_u003b(param_162, param_163, param_164, param_165, param_166, param_167, param_168, param_169);
        float _e287 = param_162;
        cov_5_ = _e287;
        float _e288 = param_163;
        wgt_5_ = _e288;
        return true;
    }
    int _e290 = seg_7_.kind_0_;
    if ((_e290 == 1)) {
        float _e292 = cov_5_;
        param_170 = _e292;
        float _e293 = wgt_5_;
        param_171 = _e293;
        SegmentData_0_ _e294 = seg_7_;
        param_172 = _e294;
        vec2 _e295 = sampleRc_4_;
        param_173 = _e295;
        float _e296 = ppe_4_;
        param_174 = _e296;
        bool _e297 = horizontal_6_;
        param_175 = _e297;
        accumulateConicCoverage_0_u0028_f1_u003b_f1_u003b_struct_u002d_SegmentData_0_u002d_i1_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf31_u003b_vf2_u003b_f1_u003b_b1_u003b(param_170, param_171, param_172, param_173, param_174, param_175);
        float _e298 = param_170;
        cov_5_ = _e298;
        float _e299 = param_171;
        wgt_5_ = _e299;
        return true;
    }
    float _e300 = cov_5_;
    param_176 = _e300;
    float _e301 = wgt_5_;
    param_177 = _e301;
    SegmentData_0_ _e302 = seg_7_;
    param_178 = _e302;
    vec2 _e303 = sampleRc_4_;
    param_179 = _e303;
    float _e304 = ppe_4_;
    param_180 = _e304;
    bool _e305 = horizontal_6_;
    param_181 = _e305;
    accumulateCubicCoverage_0_u0028_f1_u003b_f1_u003b_struct_u002d_SegmentData_0_u002d_i1_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf31_u003b_vf2_u003b_f1_u003b_b1_u003b(param_176, param_177, param_178, param_179, param_180, param_181);
    float _e306 = param_176;
    cov_5_ = _e306;
    float _e307 = param_177;
    wgt_5_ = _e307;
    return true;
}

ivec2 offsetCurveLoc_0_u0028_vi2_u003b_i1_u003b(inout ivec2 base_1_, inout int offset_2_) {
    int _S7_ = 0;
    ivec2 loc_1_ = ivec2(0);
    int _e87 = base_1_[0u];
    int _e88 = offset_2_;
    _S7_ = (_e87 + _e88);
    int _e90 = _S7_;
    int _e92 = base_1_[1u];
    loc_1_ = ivec2(_e90, _e92);
    int _e95 = loc_1_[1u];
    int _e96 = _S7_;
    loc_1_[1u] = (_e95 + (_e96 >> uint(12)));
    int _e102 = loc_1_[0u];
    loc_1_[0u] = (_e102 & 4095);
    ivec2 _e105 = loc_1_;
    return _e105;
}

SegmentData_0_ fetchSegment_0_u0028_tA21_u003b_vi2_u003b_i1_u003b_i1_u003b(highp sampler2DArray curve_tex_0_, inout ivec2 loc_2_, inout int layer_0_, inout int kind_1_) {
    ivec4 _S8_ = ivec4(0);
    vec4 tex0_0_ = vec4(0.0);
    ivec4 _S9_ = ivec4(0);
    ivec2 param_182 = ivec2(0);
    int param_183 = 0;
    vec4 tex1_0_ = vec4(0.0);
    SegmentData_0_ seg_0_ = SegmentData_0_(0, vec2(0.0), vec2(0.0), vec2(0.0), vec2(0.0), vec3(0.0));
    ivec4 _S10_ = ivec4(0);
    ivec2 param_184 = ivec2(0);
    int param_185 = 0;
    vec4 tex2_0_ = vec4(0.0);
    ivec2 _e97 = loc_2_;
    int _e98 = layer_0_;
    _S8_ = ivec4(_e97.x, _e97.y, _e98, 0);
    ivec4 _e102 = _S8_;
    ivec3 _e103 = _e102.xyz;
    int _e105 = _S8_[3u];
    vec4 _e111 = texelFetch(curve_tex_0_, ivec3(ivec2(_e103.x, _e103.y), int(_e103.z)), _e105);
    tex0_0_ = _e111;
    ivec2 _e112 = loc_2_;
    param_182 = _e112;
    param_183 = 1;
    ivec2 _e113 = offsetCurveLoc_0_u0028_vi2_u003b_i1_u003b(param_182, param_183);
    int _e114 = layer_0_;
    _S9_ = ivec4(_e113.x, _e113.y, _e114, 0);
    ivec4 _e118 = _S9_;
    ivec3 _e119 = _e118.xyz;
    int _e121 = _S9_[3u];
    vec4 _e127 = texelFetch(curve_tex_0_, ivec3(ivec2(_e119.x, _e119.y), int(_e119.z)), _e121);
    tex1_0_ = _e127;
    int _e128 = kind_1_;
    seg_0_.kind_0_ = _e128;
    vec4 _e130 = tex0_0_;
    seg_0_.p0_0_ = _e130.xy;
    vec4 _e133 = tex0_0_;
    seg_0_.p1_0_ = _e133.zw;
    vec4 _e136 = tex1_0_;
    seg_0_.p2_0_ = _e136.xy;
    vec4 _e139 = tex1_0_;
    seg_0_.p3_0_ = _e139.zw;
    int _e142 = kind_1_;
    if ((_e142 == 1)) {
        ivec2 _e144 = loc_2_;
        param_184 = _e144;
        param_185 = 2;
        ivec2 _e145 = offsetCurveLoc_0_u0028_vi2_u003b_i1_u003b(param_184, param_185);
        int _e146 = layer_0_;
        _S10_ = ivec4(_e145.x, _e145.y, _e146, 0);
        ivec4 _e150 = _S10_;
        ivec3 _e151 = _e150.xyz;
        int _e153 = _S10_[3u];
        vec4 _e159 = texelFetch(curve_tex_0_, ivec3(ivec2(_e151.x, _e151.y), int(_e151.z)), _e153);
        tex2_0_ = _e159;
        float _e161 = tex2_0_[3u];
        float _e163 = tex2_0_[0u];
        float _e165 = tex2_0_[1u];
        seg_0_.weights_0_ = vec3(_e161, _e163, _e165);
    } else {
        seg_0_.weights_0_ = vec3(1.0, 1.0, 1.0);
    }
    SegmentData_0_ _e169 = seg_0_;
    return _e169;
}

int decodeBandCurveKindCommon_0_u0028_vu2_u003b(inout uvec2 ref_2_) {
    uint _e84 = ref_2_[1u];
    return int((_e84 >> 14u));
}

ivec2 decodeBandCurveLocCommon_0_u0028_vu2_u003b(inout uvec2 ref_1_) {
    uint _e84 = ref_1_[0u];
    uint _e88 = ref_1_[1u];
    return ivec2(int((_e84 & 4095u)), int((_e88 & 16383u)));
}

int decodeBandCurveFirstMemberCommon_0_u0028_vu2_u003b(inout uvec2 ref_0_) {
    uint _e84 = ref_0_[0u];
    return int((_e84 >> 12u));
}

ivec2 calcBandLoc_0_u0028_vi2_u003b_u1_u003b(inout ivec2 glyphLoc_0_, inout uint offset_1_) {
    int _S6_ = 0;
    ivec2 loc_0_ = ivec2(0);
    int _e87 = glyphLoc_0_[0u];
    uint _e88 = offset_1_;
    _S6_ = (_e87 + int(_e88));
    int _e91 = _S6_;
    int _e93 = glyphLoc_0_[1u];
    loc_0_ = ivec2(_e91, _e93);
    int _e96 = loc_0_[1u];
    int _e97 = _S6_;
    loc_0_[1u] = (_e96 + (_e97 >> uint(12)));
    int _e103 = loc_0_[0u];
    loc_0_[0u] = (_e103 & 4095);
    ivec2 _e106 = loc_0_;
    return _e106;
}

vec2 evalAxisCoverageBands_0_u0028_tA21_u003b_utA21_u003b_vf2_u003b_f1_u003b_vi2_u003b_i1_u003b_i1_u003b_i1_u003b_i1_u003b_b1_u003b(highp sampler2DArray curve_tex_1_, highp usampler2DArray band_tex_0_, inout vec2 sampleRc_5_, inout float ppe_5_, inout ivec2 gLoc_0_, inout int headerBase_0_, inout int firstBand_0_, inout int lastBand_0_, inout int layer_1_, inout bool horizontal_7_) {
    float cov_6_ = 0.0;
    float wgt_6_ = 0.0;
    bool _S62_ = false;
    int band_0_ = 0;
    ivec4 _S63_ = ivec4(0);
    ivec2 param_186 = ivec2(0);
    uint param_187 = 0u;
    uvec2 bd_0_ = uvec2(0u);
    ivec2 _S64_ = ivec2(0);
    ivec2 param_188 = ivec2(0);
    uint param_189 = 0u;
    int _S65_ = 0;
    int i_1_ = 0;
    ivec4 _S66_ = ivec4(0);
    ivec2 param_190 = ivec2(0);
    uint param_191 = 0u;
    uvec2 ref_3_ = uvec2(0u);
    uvec2 param_192 = uvec2(0u);
    bool _S67_ = false;
    uvec2 param_193 = uvec2(0u);
    uvec2 param_194 = uvec2(0u);
    ivec2 param_195 = ivec2(0);
    int param_196 = 0;
    int param_197 = 0;
    float param_198 = 0.0;
    float param_199 = 0.0;
    vec2 param_200 = vec2(0.0);
    float param_201 = 0.0;
    SegmentData_0_ param_202 = SegmentData_0_(0, vec2(0.0), vec2(0.0), vec2(0.0), vec2(0.0), vec3(0.0));
    bool param_203 = false;
    cov_6_ = 0.0;
    wgt_6_ = 0.0;
    int _e122 = firstBand_0_;
    int _e123 = lastBand_0_;
    _S62_ = (_e122 != _e123);
    int _e125 = firstBand_0_;
    band_0_ = _e125;
    while(true) {
        int _e126 = band_0_;
        int _e127 = lastBand_0_;
        if ((_e126 <= _e127)) {
        } else {
            break;
        }
        int _e129 = headerBase_0_;
        int _e130 = band_0_;
        ivec2 _e133 = gLoc_0_;
        param_186 = _e133;
        param_187 = uint((_e129 + _e130));
        ivec2 _e134 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_186, param_187);
        int _e135 = layer_1_;
        _S63_ = ivec4(_e134.x, _e134.y, _e135, 0);
        ivec4 _e139 = _S63_;
        ivec3 _e140 = _e139.xyz;
        int _e142 = _S63_[3u];
        uvec4 _e148 = texelFetch(band_tex_0_, ivec3(ivec2(_e140.x, _e140.y), int(_e140.z)), _e142);
        bd_0_ = _e148.xy;
        ivec2 _e150 = gLoc_0_;
        param_188 = _e150;
        uint _e152 = bd_0_[1u];
        param_189 = _e152;
        ivec2 _e153 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_188, param_189);
        _S64_ = _e153;
        uint _e155 = bd_0_[0u];
        _S65_ = int(_e155);
        i_1_ = 0;
        while(true) {
            int _e157 = i_1_;
            int _e158 = _S65_;
            if ((_e157 < _e158)) {
            } else {
                break;
            }
            int _e160 = i_1_;
            ivec2 _e162 = _S64_;
            param_190 = _e162;
            param_191 = uint(_e160);
            ivec2 _e163 = calcBandLoc_0_u0028_vi2_u003b_u1_u003b(param_190, param_191);
            int _e164 = layer_1_;
            _S66_ = ivec4(_e163.x, _e163.y, _e164, 0);
            ivec4 _e168 = _S66_;
            ivec3 _e169 = _e168.xyz;
            int _e171 = _S66_[3u];
            uvec4 _e177 = texelFetch(band_tex_0_, ivec3(ivec2(_e169.x, _e169.y), int(_e169.z)), _e171);
            ref_3_ = _e177.xy;
            bool _e179 = _S62_;
            if (_e179) {
                int _e180 = band_0_;
                uvec2 _e181 = ref_3_;
                param_192 = _e181;
                int _e182 = decodeBandCurveFirstMemberCommon_0_u0028_vu2_u003b(param_192);
                int _e183 = firstBand_0_;
                if ((_e180 != max(_e182, _e183))) {
                    int _e186 = i_1_;
                    i_1_ = (_e186 + 1);
                    continue;
                }
            }
            uvec2 _e188 = ref_3_;
            param_193 = _e188;
            ivec2 _e189 = decodeBandCurveLocCommon_0_u0028_vu2_u003b(param_193);
            uvec2 _e190 = ref_3_;
            param_194 = _e190;
            int _e191 = decodeBandCurveKindCommon_0_u0028_vu2_u003b(param_194);
            param_195 = _e189;
            int _e192 = layer_1_;
            param_196 = _e192;
            param_197 = _e191;
            SegmentData_0_ _e193 = fetchSegment_0_u0028_tA21_u003b_vi2_u003b_i1_u003b_i1_u003b(curve_tex_1_, param_195, param_196, param_197);
            float _e194 = cov_6_;
            param_198 = _e194;
            float _e195 = wgt_6_;
            param_199 = _e195;
            vec2 _e196 = sampleRc_5_;
            param_200 = _e196;
            float _e197 = ppe_5_;
            param_201 = _e197;
            param_202 = _e193;
            bool _e198 = horizontal_7_;
            param_203 = _e198;
            bool _e199 = accumulateAxisCoverageSegment_0_u0028_f1_u003b_f1_u003b_vf2_u003b_f1_u003b_struct_u002d_SegmentData_0_u002d_i1_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf2_u002d_vf31_u003b_b1_u003b(param_198, param_199, param_200, param_201, param_202, param_203);
            float _e200 = param_198;
            cov_6_ = _e200;
            float _e201 = param_199;
            wgt_6_ = _e201;
            _S67_ = _e199;
            bool _e202 = _S67_;
            if (!(_e202)) {
                break;
            }
            int _e204 = i_1_;
            i_1_ = (_e204 + 1);
            continue;
        }
        int _e206 = band_0_;
        band_0_ = (_e206 + 1);
        continue;
    }
    float _e208 = cov_6_;
    float _e209 = wgt_6_;
    return vec2(_e208, _e209);
}

CoverageBandSpan_0_ CoverageBandSpan_x24init_0_u0028_i1_u003b_i1_u003b(inout int first_1_, inout int last_1_) {
    CoverageBandSpan_0_ _S4_ = CoverageBandSpan_0_(0, 0);
    int _e85 = first_1_;
    _S4_.first_0_ = _e85;
    int _e87 = last_1_;
    _S4_.last_0_ = _e87;
    CoverageBandSpan_0_ _e89 = _S4_;
    return _e89;
}

CoverageBandSpan_0_ computeCoverageBandSpan_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_i1_u003b(inout float coord_0_, inout float eppAxis_0_, inout float bandScale_0_, inout float bandOffset_0_, inout int bandMax_0_) {
    float center_0_ = 0.0;
    float _S5_ = 0.0;
    int first_2_ = 0;
    int param_204 = 0;
    int param_205 = 0;
    float _e92 = coord_0_;
    float _e93 = bandScale_0_;
    float _e95 = bandOffset_0_;
    center_0_ = ((_e92 * _e93) + _e95);
    float _e97 = eppAxis_0_;
    float _e98 = bandScale_0_;
    _S5_ = max((abs((_e97 * _e98)) * 0.5), 1e-5);
    float _e103 = center_0_;
    float _e104 = _S5_;
    int _e107 = bandMax_0_;
    first_2_ = min(max(int((_e103 - _e104)), 0), _e107);
    int _e109 = first_2_;
    float _e110 = center_0_;
    float _e111 = _S5_;
    int _e114 = bandMax_0_;
    int _e117 = first_2_;
    param_204 = _e117;
    param_205 = max(_e109, min(max(int((_e110 + _e111)), 0), _e114));
    CoverageBandSpan_0_ _e118 = CoverageBandSpan_x24init_0_u0028_i1_u003b_i1_u003b(param_204, param_205);
    return _e118;
}

float evalPathGlyphCoverage_0_u0028_tA21_u003b_utA21_u003b_vf2_u003b_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b_i1_u003b_f1_u003b(highp sampler2DArray curve_tex_2_, highp usampler2DArray band_tex_1_, inout vec2 rc_0_, inout vec2 epp_0_, inout vec2 ppe_6_, inout ivec2 gLoc_1_, inout ivec2 bandMax_1_, inout vec4 banding_0_, inout int texLayer_0_, inout int fill_rule_0_, inout float coverage_exponent_2_) {
    int _S70_ = 0;
    CoverageBandSpan_0_ hSpan_0_ = CoverageBandSpan_0_(0, 0);
    float param_206 = 0.0;
    float param_207 = 0.0;
    float param_208 = 0.0;
    float param_209 = 0.0;
    int param_210 = 0;
    CoverageBandSpan_0_ vSpan_0_ = CoverageBandSpan_0_(0, 0);
    float param_211 = 0.0;
    float param_212 = 0.0;
    float param_213 = 0.0;
    float param_214 = 0.0;
    int param_215 = 0;
    vec2 horiz_0_ = vec2(0.0);
    vec2 param_216 = vec2(0.0);
    float param_217 = 0.0;
    ivec2 param_218 = ivec2(0);
    int param_219 = 0;
    int param_220 = 0;
    int param_221 = 0;
    int param_222 = 0;
    bool param_223 = false;
    vec2 vert_0_ = vec2(0.0);
    vec2 param_224 = vec2(0.0);
    float param_225 = 0.0;
    ivec2 param_226 = ivec2(0);
    int param_227 = 0;
    int param_228 = 0;
    int param_229 = 0;
    int param_230 = 0;
    bool param_231 = false;
    float _S71_ = 0.0;
    float _S72_ = 0.0;
    float _S73_ = 0.0;
    float _S74_ = 0.0;
    float param_232 = 0.0;
    int param_233 = 0;
    float param_234 = 0.0;
    int param_235 = 0;
    float param_236 = 0.0;
    int param_237 = 0;
    float param_238 = 0.0;
    float param_239 = 0.0;
    int _e137 = bandMax_1_[1u];
    _S70_ = _e137;
    float _e139 = rc_0_[1u];
    param_206 = _e139;
    float _e141 = epp_0_[1u];
    param_207 = _e141;
    float _e143 = banding_0_[1u];
    param_208 = _e143;
    float _e145 = banding_0_[3u];
    param_209 = _e145;
    int _e146 = _S70_;
    param_210 = _e146;
    CoverageBandSpan_0_ _e147 = computeCoverageBandSpan_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_i1_u003b(param_206, param_207, param_208, param_209, param_210);
    hSpan_0_ = _e147;
    float _e149 = rc_0_[0u];
    param_211 = _e149;
    float _e151 = epp_0_[0u];
    param_212 = _e151;
    float _e153 = banding_0_[0u];
    param_213 = _e153;
    float _e155 = banding_0_[2u];
    param_214 = _e155;
    int _e157 = bandMax_1_[0u];
    param_215 = _e157;
    CoverageBandSpan_0_ _e158 = computeCoverageBandSpan_0_u0028_f1_u003b_f1_u003b_f1_u003b_f1_u003b_i1_u003b(param_211, param_212, param_213, param_214, param_215);
    vSpan_0_ = _e158;
    vec2 _e159 = rc_0_;
    param_216 = _e159;
    float _e161 = ppe_6_[0u];
    param_217 = _e161;
    ivec2 _e162 = gLoc_1_;
    param_218 = _e162;
    param_219 = 0;
    int _e164 = hSpan_0_.first_0_;
    param_220 = _e164;
    int _e166 = hSpan_0_.last_0_;
    param_221 = _e166;
    int _e167 = texLayer_0_;
    param_222 = _e167;
    param_223 = true;
    vec2 _e168 = evalAxisCoverageBands_0_u0028_tA21_u003b_utA21_u003b_vf2_u003b_f1_u003b_vi2_u003b_i1_u003b_i1_u003b_i1_u003b_i1_u003b_b1_u003b(curve_tex_2_, band_tex_1_, param_216, param_217, param_218, param_219, param_220, param_221, param_222, param_223);
    horiz_0_ = _e168;
    int _e169 = _S70_;
    vec2 _e171 = rc_0_;
    param_224 = _e171;
    float _e173 = ppe_6_[1u];
    param_225 = _e173;
    ivec2 _e174 = gLoc_1_;
    param_226 = _e174;
    param_227 = (_e169 + 1);
    int _e176 = vSpan_0_.first_0_;
    param_228 = _e176;
    int _e178 = vSpan_0_.last_0_;
    param_229 = _e178;
    int _e179 = texLayer_0_;
    param_230 = _e179;
    param_231 = false;
    vec2 _e180 = evalAxisCoverageBands_0_u0028_tA21_u003b_utA21_u003b_vf2_u003b_f1_u003b_vi2_u003b_i1_u003b_i1_u003b_i1_u003b_i1_u003b_b1_u003b(curve_tex_2_, band_tex_1_, param_224, param_225, param_226, param_227, param_228, param_229, param_230, param_231);
    vert_0_ = _e180;
    float _e182 = horiz_0_[1u];
    _S71_ = _e182;
    float _e184 = vert_0_[1u];
    _S72_ = _e184;
    float _e186 = horiz_0_[0u];
    _S73_ = _e186;
    float _e188 = vert_0_[0u];
    _S74_ = _e188;
    float _e189 = _S73_;
    float _e190 = _S71_;
    float _e192 = _S74_;
    float _e193 = _S72_;
    float _e196 = _S71_;
    float _e197 = _S72_;
    param_232 = (((_e189 * _e190) + (_e192 * _e193)) / max((_e196 + _e197), 1.5258789e-5));
    int _e201 = fill_rule_0_;
    param_233 = _e201;
    float _e202 = applyFillRule_0_u0028_f1_u003b_i1_u003b(param_232, param_233);
    float _e203 = _S73_;
    param_234 = _e203;
    int _e204 = fill_rule_0_;
    param_235 = _e204;
    float _e205 = applyFillRule_0_u0028_f1_u003b_i1_u003b(param_234, param_235);
    float _e206 = _S74_;
    param_236 = _e206;
    int _e207 = fill_rule_0_;
    param_237 = _e207;
    float _e208 = applyFillRule_0_u0028_f1_u003b_i1_u003b(param_236, param_237);
    param_238 = max(_e202, min(_e205, _e208));
    float _e211 = coverage_exponent_2_;
    param_239 = _e211;
    float _e212 = applyCoverageTransfer_0_u0028_f1_u003b_f1_u003b(param_238, param_239);
    return _e212;
}

float srgbEncode_0_u0028_f1_u003b(inout float c_0_) {
    float _S103_ = 0.0;
    float _e84 = c_0_;
    if ((_e84 <= 0.0031308)) {
        float _e86 = c_0_;
        _S103_ = (_e86 * 12.92);
    } else {
        float _e88 = c_0_;
        _S103_ = ((1.055 * pow(_e88, 0.41666666)) - 0.055);
    }
    float _e92 = _S103_;
    return _e92;
}

vec3 linearToSrgb_0_u0028_vf3_u003b(inout vec3 color_5_) {
    float param_240 = 0.0;
    float param_241 = 0.0;
    float param_242 = 0.0;
    float _e87 = color_5_[0u];
    param_240 = max(_e87, 0.0);
    float _e89 = srgbEncode_0_u0028_f1_u003b(param_240);
    float _e91 = color_5_[1u];
    param_241 = max(_e91, 0.0);
    float _e93 = srgbEncode_0_u0028_f1_u003b(param_241);
    float _e95 = color_5_[2u];
    param_242 = max(_e95, 0.0);
    float _e97 = srgbEncode_0_u0028_f1_u003b(param_242);
    return vec3(_e89, _e93, _e97);
}

vec4 srgbEncodePremultiplied_0_u0028_vf4_u003b(inout vec4 premul_1_) {
    float _S107_ = 0.0;
    vec3 param_243 = vec3(0.0);
    float _e86 = premul_1_[3u];
    _S107_ = _e86;
    float _e87 = _S107_;
    if ((_e87 <= 0.0)) {
        return vec4(0.0, 0.0, 0.0, 0.0);
    }
    vec4 _e89 = premul_1_;
    float _e91 = _S107_;
    param_243 = (_e89.xyz * (1.0 / _e91));
    vec3 _e94 = linearToSrgb_0_u0028_vf3_u003b(param_243);
    float _e95 = _S107_;
    vec3 _e96 = (_e94 * _e95);
    float _e97 = _S107_;
    return vec4(_e96.x, _e96.y, _e96.z, _e97);
}

float srgbDecode_0_u0028_f1_u003b(inout float c_1_) {
    float _S104_ = 0.0;
    float _e84 = c_1_;
    if ((_e84 <= 0.04045)) {
        float _e86 = c_1_;
        _S104_ = (_e86 / 12.92);
    } else {
        float _e88 = c_1_;
        _S104_ = pow(((_e88 + 0.055) / 1.055), 2.4);
    }
    float _e92 = _S104_;
    return _e92;
}

vec3 srgbToLinear_0_u0028_vf3_u003b(inout vec3 color_6_) {
    float param_244 = 0.0;
    float param_245 = 0.0;
    float param_246 = 0.0;
    float _e87 = color_6_[0u];
    param_244 = _e87;
    float _e88 = srgbDecode_0_u0028_f1_u003b(param_244);
    float _e90 = color_6_[1u];
    param_245 = _e90;
    float _e91 = srgbDecode_0_u0028_f1_u003b(param_245);
    float _e93 = color_6_[2u];
    param_246 = _e93;
    float _e94 = srgbDecode_0_u0028_f1_u003b(param_246);
    return vec3(_e88, _e91, _e94);
}

float interleavedGradientNoise_0_u0028_vf2_u003b(inout vec2 pixel_0_) {
    vec2 _e83 = pixel_0_;
    return fract((52.982918 * fract(dot(_e83, vec2(0.06711056, 0.00583715)))));
}

vec4 ditherPremultipliedColor_0_u0028_vf4_u003b_vf2_u003b_f1_u003b(inout vec4 color_7_, inout vec2 frag_coord_0_, inout float dither_scale_1_) {
    float _S105_ = 0.0;
    bool _S106_ = false;
    vec3 param_247 = vec3(0.0);
    vec2 param_248 = vec2(0.0);
    vec3 param_249 = vec3(0.0);
    float _e91 = color_7_[3u];
    _S105_ = _e91;
    float _e92 = _S105_;
    if ((_e92 <= 0.0)) {
        _S106_ = true;
    } else {
        float _e94 = dither_scale_1_;
        _S106_ = (_e94 <= 0.0);
    }
    bool _e96 = _S106_;
    if (_e96) {
        vec4 _e97 = color_7_;
        return _e97;
    }
    vec4 _e98 = color_7_;
    param_247 = _e98.xyz;
    vec3 _e100 = linearToSrgb_0_u0028_vf3_u003b(param_247);
    vec2 _e101 = frag_coord_0_;
    param_248 = _e101;
    float _e102 = interleavedGradientNoise_0_u0028_vf2_u003b(param_248);
    float _e104 = _S105_;
    float _e106 = dither_scale_1_;
    param_249 = clamp((_e100 + vec3(((_e102 - 0.5) * (clamp(_e104, 0.0, 1.0) * _e106)))), vec3(0.0, 0.0, 0.0), vec3(1.0, 1.0, 1.0));
    vec3 _e112 = srgbToLinear_0_u0028_vf3_u003b(param_249);
    float _e113 = _S105_;
    return vec4(_e112.x, _e112.y, _e112.z, _e113);
}

PathCompositeSample_0_ PathCompositeSample_x24init_0_u0028_vf4_u003b_f1_u003b(inout vec4 color_4_, inout float gradient_3_) {
    PathCompositeSample_0_ _S90_ = PathCompositeSample_0_(vec4(0.0), 0.0);
    vec4 _e85 = color_4_;
    _S90_.color_3_ = _e85;
    float _e87 = gradient_3_;
    _S90_.gradient_2_ = _e87;
    PathCompositeSample_0_ _e89 = _S90_;
    return _e89;
}

PathCompositeSample_0_ compositePathGroup_0_u0028_tA21_u003b_utA21_u003b_t21_u003b_tA21_u003b_p1_u003b_vf2_u003b_vf2_u003b_vf2_u003b_vi2_u003b_vf4_u003b_i1_u003b_vf4_u003b_f1_u003b(highp sampler2DArray curve_tex_3_, highp usampler2DArray band_tex_2_, highp sampler2D layer_tex_2_, highp sampler2DArray image_tex_2_, inout vec2 rc_2_, inout vec2 epp_1_, inout vec2 ppe_7_, inout ivec2 infoBase_1_, inout vec4 header_0_, inout int texLayer_1_, inout vec4 tint_0_, inout float coverage_exponent_3_) {
    int layer_count_0_ = 0;
    int composite_mode_0_ = 0;
    PathPaintSample_0_ _S93_ = PathPaintSample_0_(vec4(0.0), 0.0);
    vec4 param_250 = vec4(0.0);
    float param_251 = 0.0;
    vec4 result_0_ = vec4(0.0);
    float fill_cov_0_ = 0.0;
    float stroke_cov_0_ = 0.0;
    PathPaintSample_0_ fill_paint_0_ = PathPaintSample_0_(vec4(0.0), 0.0);
    PathPaintSample_0_ stroke_paint_0_ = PathPaintSample_0_(vec4(0.0), 0.0);
    float has_gradient_0_ = 0.0;
    int l_0_ = 0;
    ivec2 loc_3_ = ivec2(0);
    ivec2 param_252 = ivec2(0);
    int param_253 = 0;
    ivec3 _S94_ = ivec3(0);
    vec4 info_1_ = vec4(0.0);
    ivec2 _S95_ = ivec2(0);
    ivec2 param_254 = ivec2(0);
    int param_255 = 0;
    ivec3 _S96_ = ivec3(0);
    int packed_gx_0_ = 0;
    int _S97_ = 0;
    float cov_9_ = 0.0;
    vec2 param_256 = vec2(0.0);
    vec2 param_257 = vec2(0.0);
    vec2 param_258 = vec2(0.0);
    ivec2 param_259 = ivec2(0);
    ivec2 param_260 = ivec2(0);
    vec4 param_261 = vec4(0.0);
    int param_262 = 0;
    int param_263 = 0;
    float param_264 = 0.0;
    PathPaintSample_0_ _S98_ = PathPaintSample_0_(vec4(0.0), 0.0);
    vec2 param_265 = vec2(0.0);
    ivec2 param_266 = ivec2(0);
    vec4 param_267 = vec4(0.0);
    PathPaintSample_0_ paint_0_ = PathPaintSample_0_(vec4(0.0), 0.0);
    bool _S91_ = false;
    bool _S99_ = false;
    float fill_cov_1_ = 0.0;
    float stroke_cov_1_ = 0.0;
    PathPaintSample_0_ fill_paint_1_ = PathPaintSample_0_(vec4(0.0), 0.0);
    PathPaintSample_0_ stroke_paint_1_ = PathPaintSample_0_(vec4(0.0), 0.0);
    bool _S100_ = false;
    vec4 premul_0_ = vec4(0.0);
    vec4 param_268 = vec4(0.0);
    float param_269 = 0.0;
    float _S101_ = 0.0;
    float _S102_ = 0.0;
    vec4 param_270 = vec4(0.0);
    float param_271 = 0.0;
    vec4 param_272 = vec4(0.0);
    float param_273 = 0.0;
    vec4 param_274 = vec4(0.0);
    float param_275 = 0.0;
    float _e152 = header_0_[0u];
    layer_count_0_ = int((_e152 + 0.5));
    float _e156 = header_0_[1u];
    composite_mode_0_ = int((_e156 + 0.5));
    param_250 = vec4(0.0, 0.0, 0.0, 0.0);
    param_251 = 0.0;
    PathPaintSample_0_ _e159 = PathPaintSample_x24init_0_u0028_vf4_u003b_f1_u003b(param_250, param_251);
    _S93_ = _e159;
    result_0_ = vec4(0.0, 0.0, 0.0, 0.0);
    fill_cov_0_ = 0.0;
    stroke_cov_0_ = 0.0;
    PathPaintSample_0_ _e160 = _S93_;
    fill_paint_0_ = _e160;
    PathPaintSample_0_ _e161 = _S93_;
    stroke_paint_0_ = _e161;
    has_gradient_0_ = 0.0;
    l_0_ = 0;
    while(true) {
        int _e162 = l_0_;
        int _e163 = layer_count_0_;
        if ((_e162 < _e163)) {
        } else {
            break;
        }
        int _e165 = l_0_;
        ivec2 _e168 = infoBase_1_;
        param_252 = _e168;
        param_253 = (1 + (_e165 * 6));
        ivec2 _e169 = offsetLayerLoc_0_u0028_t21_u003b_vi2_u003b_i1_u003b(layer_tex_2_, param_252, param_253);
        loc_3_ = _e169;
        ivec2 _e170 = loc_3_;
        _S94_ = ivec3(_e170.x, _e170.y, 0);
        ivec3 _e174 = _S94_;
        int _e177 = _S94_[2u];
        vec4 _e178 = texelFetch(layer_tex_2_, _e174.xy, _e177);
        info_1_ = _e178;
        ivec2 _e179 = loc_3_;
        param_254 = _e179;
        param_255 = 1;
        ivec2 _e180 = offsetLayerLoc_0_u0028_t21_u003b_vi2_u003b_i1_u003b(layer_tex_2_, param_254, param_255);
        _S95_ = _e180;
        ivec2 _e181 = _S95_;
        _S96_ = ivec3(_e181.x, _e181.y, 0);
        float _e186 = info_1_[0u];
        packed_gx_0_ = int(_e186);
        float _e189 = info_1_[2u];
        _S97_ = floatBitsToInt(_e189);
        int _e191 = packed_gx_0_;
        float _e194 = info_1_[1u];
        int _e197 = _S97_;
        int _e201 = _S97_;
        ivec3 _e204 = _S96_;
        int _e207 = _S96_[2u];
        vec4 _e208 = texelFetch(layer_tex_2_, _e204.xy, _e207);
        int _e209 = packed_gx_0_;
        vec2 _e213 = rc_2_;
        param_256 = _e213;
        vec2 _e214 = epp_1_;
        param_257 = _e214;
        vec2 _e215 = ppe_7_;
        param_258 = _e215;
        param_259 = ivec2((_e191 & 32767), int(_e194));
        param_260 = ivec2(((_e197 >> uint(16)) & 65535), (_e201 & 65535));
        param_261 = _e208;
        int _e216 = texLayer_1_;
        param_262 = _e216;
        param_263 = ((_e209 >> uint(15)) & 1);
        float _e217 = coverage_exponent_3_;
        param_264 = _e217;
        float _e218 = evalPathGlyphCoverage_0_u0028_tA21_u003b_utA21_u003b_vf2_u003b_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b_i1_u003b_f1_u003b(curve_tex_3_, band_tex_2_, param_256, param_257, param_258, param_259, param_260, param_261, param_262, param_263, param_264);
        cov_9_ = _e218;
        vec2 _e219 = rc_2_;
        param_265 = _e219;
        ivec2 _e220 = loc_3_;
        param_266 = _e220;
        vec4 _e221 = info_1_;
        param_267 = _e221;
        PathPaintSample_0_ _e222 = samplePathPaint_0_u0028_t21_u003b_tA21_u003b_p1_u003b_vf2_u003b_vi2_u003b_vf4_u003b(layer_tex_2_, image_tex_2_, param_265, param_266, param_267);
        _S98_ = _e222;
        PathPaintSample_0_ _e223 = _S98_;
        paint_0_ = _e223;
        vec4 _e225 = paint_0_.color_0_;
        vec4 _e226 = tint_0_;
        paint_0_.color_0_ = (_e225 * _e226);
        int _e229 = composite_mode_0_;
        if ((_e229 == 1)) {
            int _e231 = layer_count_0_;
            _S91_ = (_e231 >= 2);
        } else {
            _S91_ = false;
        }
        bool _e233 = _S91_;
        if (_e233) {
            int _e234 = l_0_;
            _S99_ = (_e234 < 2);
        } else {
            _S99_ = false;
        }
        bool _e236 = _S99_;
        if (_e236) {
            int _e237 = l_0_;
            if ((_e237 == 0)) {
                float _e239 = cov_9_;
                fill_cov_1_ = _e239;
                float _e240 = stroke_cov_0_;
                stroke_cov_1_ = _e240;
                PathPaintSample_0_ _e241 = paint_0_;
                fill_paint_1_ = _e241;
                PathPaintSample_0_ _e242 = stroke_paint_0_;
                stroke_paint_1_ = _e242;
            } else {
                float _e243 = fill_cov_0_;
                fill_cov_1_ = _e243;
                float _e244 = cov_9_;
                stroke_cov_1_ = _e244;
                PathPaintSample_0_ _e245 = fill_paint_0_;
                fill_paint_1_ = _e245;
                PathPaintSample_0_ _e246 = paint_0_;
                stroke_paint_1_ = _e246;
            }
            float _e247 = fill_cov_1_;
            fill_cov_0_ = _e247;
            float _e248 = stroke_cov_1_;
            stroke_cov_0_ = _e248;
            PathPaintSample_0_ _e249 = fill_paint_1_;
            fill_paint_0_ = _e249;
            PathPaintSample_0_ _e250 = stroke_paint_1_;
            stroke_paint_0_ = _e250;
            int _e251 = l_0_;
            l_0_ = (_e251 + 1);
            continue;
        }
        float _e254 = paint_0_.gradient_0_;
        if ((_e254 > 0.5)) {
            float _e256 = cov_9_;
            _S100_ = (_e256 > 1e-6);
        } else {
            _S100_ = false;
        }
        bool _e258 = _S100_;
        if (_e258) {
            fill_cov_1_ = 1.0;
        } else {
            float _e259 = has_gradient_0_;
            fill_cov_1_ = _e259;
        }
        vec4 _e261 = paint_0_.color_0_;
        param_268 = _e261;
        float _e262 = cov_9_;
        param_269 = _e262;
        vec4 _e263 = premultiplyColor_0_u0028_vf4_u003b_f1_u003b(param_268, param_269);
        premul_0_ = _e263;
        vec4 _e264 = premul_0_;
        vec4 _e265 = result_0_;
        float _e267 = premul_0_[3u];
        result_0_ = (_e264 + (_e265 * (1.0 - _e267)));
        float _e271 = fill_cov_1_;
        has_gradient_0_ = _e271;
        int _e272 = l_0_;
        l_0_ = (_e272 + 1);
        continue;
    }
    int _e274 = composite_mode_0_;
    if ((_e274 == 1)) {
        int _e276 = layer_count_0_;
        _S91_ = (_e276 >= 2);
    } else {
        _S91_ = false;
    }
    bool _e278 = _S91_;
    if (_e278) {
        float _e279 = fill_cov_0_;
        float _e280 = stroke_cov_0_;
        _S101_ = min(_e279, _e280);
        float _e282 = fill_cov_0_;
        float _e283 = _S101_;
        _S102_ = max((_e282 - _e283), 0.0);
        float _e287 = fill_paint_0_.gradient_0_;
        if ((_e287 > 0.5)) {
            float _e289 = _S102_;
            _S91_ = (_e289 > 1e-6);
        } else {
            _S91_ = false;
        }
        bool _e291 = _S91_;
        if (_e291) {
            has_gradient_0_ = 1.0;
        }
        float _e293 = stroke_paint_0_.gradient_0_;
        if ((_e293 > 0.5)) {
            float _e295 = _S101_;
            _S91_ = (_e295 > 1e-6);
        } else {
            _S91_ = false;
        }
        bool _e297 = _S91_;
        if (_e297) {
            has_gradient_0_ = 1.0;
        }
        vec4 _e298 = result_0_;
        vec4 _e300 = fill_paint_0_.color_0_;
        param_270 = _e300;
        float _e301 = _S102_;
        param_271 = _e301;
        vec4 _e302 = premultiplyColor_0_u0028_vf4_u003b_f1_u003b(param_270, param_271);
        vec4 _e304 = stroke_paint_0_.color_0_;
        param_272 = _e304;
        float _e305 = _S101_;
        param_273 = _e305;
        vec4 _e306 = premultiplyColor_0_u0028_vf4_u003b_f1_u003b(param_272, param_273);
        float _e309 = result_0_[3u];
        result_0_ = (_e298 + ((_e302 + _e306) * (1.0 - _e309)));
    }
    vec4 _e313 = result_0_;
    param_274 = _e313;
    float _e314 = has_gradient_0_;
    param_275 = _e314;
    PathCompositeSample_0_ _e315 = PathCompositeSample_x24init_0_u0028_vf4_u003b_f1_u003b(param_274, param_275);
    return _e315;
}

vec4 snailPaintedFragment_0_u0028_i1_u003b_struct_u002d_PaintedVaryings_0_u002d_vf4_u002d_vf2_u002d_vf4_u002d_vi41_u003b_vf2_u003b_tA21_u003b_utA21_u003b_t21_u003b_tA21_u003b_p1_u003b_struct_u002d_PaintedParams_0_u002d_i1_u002d_i1_u002d_f1_u002d_f1_u002d_i11_u003b(inout int expected_special_kind_0_, inout PaintedVaryings_0_ v_1_, inout vec2 frag_coord_1_, highp sampler2DArray curve_tex_4_, highp usampler2DArray band_tex_3_, highp sampler2D layer_tex_3_, highp sampler2DArray image_tex_3_, inout PaintedParams_0_ p_0_) {
    vec2 epp_2_ = vec2(0.0);
    vec2 ppe_8_ = vec2(0.0);
    int _S108_ = 0;
    int special_kind_0_ = 0;
    ivec2 infoBase_2_ = ivec2(0);
    ivec3 _S109_ = ivec3(0);
    vec4 firstInfo_0_ = vec4(0.0);
    float _S110_ = 0.0;
    int texLayer_2_ = 0;
    PathCompositeSample_0_ result_1_ = PathCompositeSample_0_(vec4(0.0), 0.0);
    vec2 param_276 = vec2(0.0);
    vec2 param_277 = vec2(0.0);
    vec2 param_278 = vec2(0.0);
    ivec2 param_279 = ivec2(0);
    vec4 param_280 = vec4(0.0);
    int param_281 = 0;
    vec4 param_282 = vec4(0.0);
    float param_283 = 0.0;
    vec4 emit_0_ = vec4(0.0);
    vec4 param_284 = vec4(0.0);
    vec2 param_285 = vec2(0.0);
    float param_286 = 0.0;
    vec4 param_287 = vec4(0.0);
    ivec2 _S111_ = ivec2(0);
    ivec2 param_288 = ivec2(0);
    int param_289 = 0;
    ivec3 _S112_ = ivec3(0);
    int packed_gx_1_ = 0;
    int _S113_ = 0;
    float cov_10_ = 0.0;
    vec2 param_290 = vec2(0.0);
    vec2 param_291 = vec2(0.0);
    vec2 param_292 = vec2(0.0);
    ivec2 param_293 = ivec2(0);
    ivec2 param_294 = ivec2(0);
    vec4 param_295 = vec4(0.0);
    int param_296 = 0;
    int param_297 = 0;
    float param_298 = 0.0;
    PathPaintSample_0_ _S114_ = PathPaintSample_0_(vec4(0.0), 0.0);
    vec2 param_299 = vec2(0.0);
    ivec2 param_300 = ivec2(0);
    vec4 param_301 = vec4(0.0);
    PathPaintSample_0_ paint_1_ = PathPaintSample_0_(vec4(0.0), 0.0);
    vec4 _S115_ = vec4(0.0);
    vec4 result_2_ = vec4(0.0);
    vec4 param_302 = vec4(0.0);
    float param_303 = 0.0;
    vec4 param_304 = vec4(0.0);
    vec2 param_305 = vec2(0.0);
    float param_306 = 0.0;
    vec4 param_307 = vec4(0.0);
    vec2 _e144 = v_1_.texcoord_0_;
    vec2 _e145 = fwidth(_e144);
    epp_2_ = _e145;
    vec2 _e146 = epp_2_;
    ppe_8_ = (vec2(1.0) / max(_e146, vec2(1.5258789e-5, 1.5258789e-5)));
    int _e152 = v_1_.glyph_0_[3u];
    _S108_ = _e152;
    int _e153 = _S108_;
    special_kind_0_ = (_e153 & 255);
    int _e155 = _S108_;
    if ((((_e155 >> uint(8)) & 255) != 255)) {
        discard;
    }
    int _e160 = special_kind_0_;
    int _e161 = expected_special_kind_0_;
    if ((_e160 != _e161)) {
        discard;
    }
    ivec4 _e164 = v_1_.glyph_0_;
    infoBase_2_ = _e164.xy;
    ivec2 _e166 = infoBase_2_;
    _S109_ = ivec3(_e166.x, _e166.y, 0);
    ivec3 _e170 = _S109_;
    int _e173 = _S109_[2u];
    vec4 _e174 = texelFetch(layer_tex_3_, _e170.xy, _e173);
    firstInfo_0_ = _e174;
    float _e176 = firstInfo_0_[3u];
    _S110_ = _e176;
    float _e177 = _S110_;
    if ((_e177 >= 0.0)) {
        discard;
    }
    int _e180 = p_0_.layer_base_1_;
    float _e183 = v_1_.banding_1_[3u];
    texLayer_2_ = (_e180 + int(_e183));
    float _e186 = _S110_;
    if ((int((-(_e186) + 0.5)) == 5)) {
        vec2 _e192 = v_1_.texcoord_0_;
        param_276 = _e192;
        vec2 _e193 = epp_2_;
        param_277 = _e193;
        vec2 _e194 = ppe_8_;
        param_278 = _e194;
        ivec2 _e195 = infoBase_2_;
        param_279 = _e195;
        vec4 _e196 = firstInfo_0_;
        param_280 = _e196;
        int _e197 = texLayer_2_;
        param_281 = _e197;
        vec4 _e199 = v_1_.tint_1_;
        param_282 = _e199;
        float _e201 = p_0_.coverage_exponent_4_;
        param_283 = _e201;
        PathCompositeSample_0_ _e202 = compositePathGroup_0_u0028_tA21_u003b_utA21_u003b_t21_u003b_tA21_u003b_p1_u003b_vf2_u003b_vf2_u003b_vf2_u003b_vi2_u003b_vf4_u003b_i1_u003b_vf4_u003b_f1_u003b(curve_tex_4_, band_tex_3_, layer_tex_3_, image_tex_3_, param_276, param_277, param_278, param_279, param_280, param_281, param_282, param_283);
        result_1_ = _e202;
        float _e205 = result_1_.color_3_[3u];
        if ((_e205 < 0.003921569)) {
            discard;
        }
        float _e208 = result_1_.gradient_2_;
        if ((_e208 > 0.5)) {
            vec4 _e211 = result_1_.color_3_;
            param_284 = _e211;
            vec2 _e212 = frag_coord_1_;
            param_285 = _e212;
            float _e214 = p_0_.dither_scale_2_;
            param_286 = _e214;
            vec4 _e215 = ditherPremultipliedColor_0_u0028_vf4_u003b_vf2_u003b_f1_u003b(param_284, param_285, param_286);
            emit_0_ = _e215;
        } else {
            vec4 _e217 = result_1_.color_3_;
            emit_0_ = _e217;
        }
        int _e219 = p_0_.mask_output_1_;
        if ((_e219 != 0)) {
            float _e222 = emit_0_[3u];
            emit_0_ = vec4(_e222);
        } else {
            int _e225 = p_0_.output_srgb_1_;
            if ((_e225 != 0)) {
                vec4 _e227 = emit_0_;
                param_287 = _e227;
                vec4 _e228 = srgbEncodePremultiplied_0_u0028_vf4_u003b(param_287);
                emit_0_ = _e228;
            }
        }
        vec4 _e229 = emit_0_;
        return _e229;
    }
    ivec2 _e230 = infoBase_2_;
    param_288 = _e230;
    param_289 = 1;
    ivec2 _e231 = offsetLayerLoc_0_u0028_t21_u003b_vi2_u003b_i1_u003b(layer_tex_3_, param_288, param_289);
    _S111_ = _e231;
    ivec2 _e232 = _S111_;
    _S112_ = ivec3(_e232.x, _e232.y, 0);
    float _e237 = firstInfo_0_[0u];
    packed_gx_1_ = int(_e237);
    float _e240 = firstInfo_0_[2u];
    _S113_ = floatBitsToInt(_e240);
    int _e242 = packed_gx_1_;
    float _e245 = firstInfo_0_[1u];
    int _e248 = _S113_;
    int _e252 = _S113_;
    ivec3 _e255 = _S112_;
    int _e258 = _S112_[2u];
    vec4 _e259 = texelFetch(layer_tex_3_, _e255.xy, _e258);
    int _e260 = packed_gx_1_;
    vec2 _e265 = v_1_.texcoord_0_;
    param_290 = _e265;
    vec2 _e266 = epp_2_;
    param_291 = _e266;
    vec2 _e267 = ppe_8_;
    param_292 = _e267;
    param_293 = ivec2((_e242 & 32767), int(_e245));
    param_294 = ivec2(((_e248 >> uint(16)) & 65535), (_e252 & 65535));
    param_295 = _e259;
    int _e268 = texLayer_2_;
    param_296 = _e268;
    param_297 = ((_e260 >> uint(15)) & 1);
    float _e270 = p_0_.coverage_exponent_4_;
    param_298 = _e270;
    float _e271 = evalPathGlyphCoverage_0_u0028_tA21_u003b_utA21_u003b_vf2_u003b_vf2_u003b_vf2_u003b_vi2_u003b_vi2_u003b_vf4_u003b_i1_u003b_i1_u003b_f1_u003b(curve_tex_4_, band_tex_3_, param_290, param_291, param_292, param_293, param_294, param_295, param_296, param_297, param_298);
    cov_10_ = _e271;
    float _e272 = cov_10_;
    if ((_e272 < 0.003921569)) {
        discard;
    }
    vec2 _e275 = v_1_.texcoord_0_;
    param_299 = _e275;
    ivec2 _e276 = infoBase_2_;
    param_300 = _e276;
    vec4 _e277 = firstInfo_0_;
    param_301 = _e277;
    PathPaintSample_0_ _e278 = samplePathPaint_0_u0028_t21_u003b_tA21_u003b_p1_u003b_vf2_u003b_vi2_u003b_vf4_u003b(layer_tex_3_, image_tex_3_, param_299, param_300, param_301);
    _S114_ = _e278;
    PathPaintSample_0_ _e279 = _S114_;
    paint_1_ = _e279;
    vec4 _e281 = paint_1_.color_0_;
    vec4 _e283 = v_1_.tint_1_;
    _S115_ = (_e281 * _e283);
    vec4 _e285 = _S115_;
    paint_1_.color_0_ = _e285;
    vec4 _e287 = _S115_;
    param_302 = _e287;
    float _e288 = cov_10_;
    param_303 = _e288;
    vec4 _e289 = premultiplyColor_0_u0028_vf4_u003b_f1_u003b(param_302, param_303);
    result_2_ = _e289;
    float _e291 = paint_1_.gradient_0_;
    if ((_e291 > 0.5)) {
        vec4 _e293 = result_2_;
        param_304 = _e293;
        vec2 _e294 = frag_coord_1_;
        param_305 = _e294;
        float _e296 = p_0_.dither_scale_2_;
        param_306 = _e296;
        vec4 _e297 = ditherPremultipliedColor_0_u0028_vf4_u003b_vf2_u003b_f1_u003b(param_304, param_305, param_306);
        emit_0_ = _e297;
    } else {
        vec4 _e298 = result_2_;
        emit_0_ = _e298;
    }
    int _e300 = p_0_.mask_output_1_;
    if ((_e300 != 0)) {
        float _e303 = emit_0_[3u];
        emit_0_ = vec4(_e303);
    } else {
        int _e306 = p_0_.output_srgb_1_;
        if ((_e306 != 0)) {
            vec4 _e308 = emit_0_;
            param_307 = _e308;
            vec4 _e309 = srgbEncodePremultiplied_0_u0028_vf4_u003b(param_307);
            emit_0_ = _e309;
        }
    }
    vec4 _e310 = emit_0_;
    return _e310;
}

void main_1() {
    PaintedVaryings_0_ v_2_ = PaintedVaryings_0_(vec4(0.0), vec2(0.0), vec4(0.0), ivec4(0));
    PaintedParams_0_ p_1_ = PaintedParams_0_(0, 0, 0.0, 0.0, 0);
    vec4 _S116_ = vec4(0.0);
    int param_308 = 0;
    PaintedVaryings_0_ param_309 = PaintedVaryings_0_(vec4(0.0), vec2(0.0), vec4(0.0), ivec4(0));
    vec2 param_310 = vec2(0.0);
    PaintedParams_0_ param_311 = PaintedParams_0_(0, 0, 0.0, 0.0, 0);
    vec4 _e89 = input_tint_0_1;
    v_2_.tint_1_ = _e89;
    vec2 _e91 = input_texcoord_0_1;
    v_2_.texcoord_0_ = _e91;
    vec4 _e93 = input_banding_0_1;
    v_2_.banding_1_ = _e93;
    ivec4 _e95 = input_glyph_0_1;
    v_2_.glyph_0_ = _e95;
    int _e98 = _group_0_binding_0_fs.layer_base_0_;
    p_1_.layer_base_1_ = _e98;
    int _e101 = _group_0_binding_0_fs.output_srgb_0_;
    p_1_.output_srgb_1_ = _e101;
    float _e104 = _group_0_binding_0_fs.coverage_exponent_0_;
    p_1_.coverage_exponent_4_ = _e104;
    float _e107 = _group_0_binding_0_fs.dither_scale_0_;
    p_1_.dither_scale_2_ = _e107;
    int _e110 = _group_0_binding_0_fs.mask_output_0_;
    p_1_.mask_output_1_ = _e110;
    param_308 = 0;
    PaintedVaryings_0_ _e112 = v_2_;
    param_309 = _e112;
    vec4 _e113 = gen_gl_FragCoord_1;
    param_310 = _e113.xy;
    PaintedParams_0_ _e115 = p_1_;
    param_311 = _e115;
    vec4 _e116 = snailPaintedFragment_0_u0028_i1_u003b_struct_u002d_PaintedVaryings_0_u002d_vf4_u002d_vf2_u002d_vf4_u002d_vi41_u003b_vf2_u003b_tA21_u003b_utA21_u003b_t21_u003b_tA21_u003b_p1_u003b_struct_u002d_PaintedParams_0_u002d_i1_u002d_i1_u002d_f1_u002d_f1_u002d_i11_u003b(param_308, param_309, param_310, _group_0_binding_1_fs, _group_0_binding_2_fs, _group_0_binding_3_fs, _group_0_binding_4_fs, param_311);
    _S116_ = _e116;
    vec4 _e117 = _S116_;
    entryPointParam_fragmentMain_0_ = _e117;
    return;
}

void main() {
    vec4 input_tint_0_ = _vs2fs_location4;
    vec2 input_texcoord_0_ = _vs2fs_location1;
    vec4 input_banding_0_ = _vs2fs_location2;
    ivec4 input_glyph_0_ = _vs2fs_location3;
    vec4 gen_gl_FragCoord = gl_FragCoord;
    input_tint_0_1 = input_tint_0_;
    input_texcoord_0_1 = input_texcoord_0_;
    input_banding_0_1 = input_banding_0_;
    input_glyph_0_1 = input_glyph_0_;
    gen_gl_FragCoord_1 = gen_gl_FragCoord;
    main_1();
    vec4 _e11 = entryPointParam_fragmentMain_0_;
    _fs2p_location0 = _e11;
    return;
}

