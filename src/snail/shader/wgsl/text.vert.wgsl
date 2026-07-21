struct block_SLANG_ParameterGroup_PushConstants_0_ {
    mvp_0_: mat4x4<f32>,
    viewport_0_: vec2<f32>,
    subpixel_order_0_: i32,
}

struct gl_PerVertex {
    @builtin(position) gl_Position: vec4<f32>,
    gl_PointSize: f32,
    gl_ClipDistance: array<f32, 1>,
    gl_CullDistance: array<f32, 1>,
}

struct VertexOutput {
    @location(3) @interpolate(flat) member: vec4<i32>,
    @location(5) @interpolate(flat) member_1: vec4<u32>,
    @location(6) @interpolate(flat) member_2: vec3<u32>,
    @location(2) @interpolate(flat) member_3: vec4<f32>,
    @location(0) member_4: vec4<f32>,
    @location(4) member_5: vec4<f32>,
    @location(1) member_6: vec2<f32>,
    @builtin(position) gl_Position: vec4<f32>,
}

var<private> gl_VertexIndex_1: i32;
@group(2) @binding(0) 
var<uniform> PushConstants_0_: block_SLANG_ParameterGroup_PushConstants_0_;
var<private> a_rect_0_1: vec4<f32>;
var<private> a_xform_0_1: vec4<f32>;
var<private> a_origin_0_1: vec2<f32>;
var<private> a_glyph_0_1: vec2<u32>;
var<private> a_policy0_0_1: vec4<u32>;
var<private> a_policy1_0_1: vec3<u32>;
var<private> a_bnd_0_1: vec4<f32>;
var<private> a_col_0_1: vec4<f32>;
var<private> a_tint_0_1: vec4<f32>;
var<private> entryPointParam_main_v_glyph_0_: vec4<i32>;
var<private> entryPointParam_main_v_policy0_0_: vec4<u32>;
var<private> entryPointParam_main_v_policy1_0_: vec3<u32>;
var<private> entryPointParam_main_v_banding_0_: vec4<f32>;
var<private> entryPointParam_main_v_color_0_: vec4<f32>;
var<private> entryPointParam_main_v_tint_0_: vec4<f32>;
var<private> entryPointParam_main_v_texcoord_0_: vec2<f32>;
var<private> unnamed: gl_PerVertex = gl_PerVertex(vec4<f32>(0f, 0f, 0f, 1f), 1f, array<f32, 1>(), array<f32, 1>());

fn main_1() {
    var _S7_: vec4<f32>;
    var _S6_: vec4<f32>;
    var _S4_: vec4<f32>;
    var _S3_: vec3<u32>;
    var _S2_: vec4<u32>;
    var _S1_: vec4<i32>;
    var local: f32;
    var local_1: f32;
    var local_2: f32;
    var local_3: f32;
    var local_4: f32;
    var local_5: f32;
    var local_6: f32;
    var local_7: f32;
    var local_8: f32;
    var local_9: f32;
    var local_10: f32;
    var local_11: f32;
    var local_12: f32;
    var local_13: array<vec2<f32>, 4>;
    var local_14: array<vec2<f32>, 4>;
    var local_15: f32;
    var local_16: f32;
    var local_17: vec2<f32>;
    var local_18: vec2<f32>;
    var local_19: f32;
    var local_20: f32;
    var local_21: f32;
    var local_22: f32;
    var local_23: vec3<f32>;
    var local_24: vec3<f32>;
    var local_25: vec2<f32>;
    var local_26: f32;
    var local_27: f32;
    var local_28: f32;
    var local_29: f32;
    var local_30: vec2<f32>;

    let _e83 = gl_VertexIndex_1;
    let _e84 = a_rect_0_1;
    let _e86 = a_rect_0_1;
    local_13 = array<vec2<f32>, 4>(vec2<f32>(0f, 0f), vec2<f32>(1f, 0f), vec2<f32>(1f, 1f), vec2<f32>(0f, 1f));
    let _e89 = local_13[_e83];
    let _e90 = mix(_e84.xy, _e86.zw, _e89);
    local_14 = array<vec2<f32>, 4>(vec2<f32>(0f, 0f), vec2<f32>(1f, 0f), vec2<f32>(1f, 1f), vec2<f32>(0f, 1f));
    let _e92 = local_14[_e83];
    let _e94 = ((_e92 * 2f) - vec2<f32>(1f, 1f));
    let _e96 = a_xform_0_1[0u];
    local_15 = _e90.x;
    let _e99 = a_xform_0_1[1u];
    local_16 = _e90.y;
    let _e102 = a_xform_0_1[2u];
    let _e104 = a_xform_0_1[3u];
    let _e109 = a_origin_0_1[0u];
    let _e115 = a_origin_0_1[1u];
    local_17 = vec2<f32>((((_e96 * _e90.x) + (_e99 * _e90.y)) + _e109), (((_e102 * _e90.x) + (_e104 * _e90.y)) + _e115));
    local_18 = vec2<f32>(((_e96 * _e94.x) + (_e99 * _e94.y)), ((_e102 * _e94.x) + (_e104 * _e94.y)));
    let _e130 = (1f / ((_e96 * _e104) - (_e99 * _e102)));
    local_19 = (_e104 * _e130);
    local_20 = (-(_e99) * _e130);
    local_21 = (-(_e102) * _e130);
    local_22 = (_e96 * _e130);
    let _e138 = a_glyph_0_1[0u];
    let _e140 = a_glyph_0_1[1u];
    _S1_ = vec4<i32>(bitcast<i32>((_e138 & 65535u)), bitcast<i32>((_e138 >> bitcast<u32>(16u))), bitcast<i32>((_e140 & 65535u)), bitcast<i32>((_e140 >> bitcast<u32>(16u))));
    let _e152 = a_policy0_0_1;
    _S2_ = _e152;
    let _e153 = a_policy1_0_1;
    _S3_ = _e153;
    let _e154 = a_bnd_0_1;
    _S4_ = _e154;
    let _e155 = a_col_0_1;
    let _e156 = _e155.xyz;
    local_23 = _e156;
    local_10 = _e156.x;
    if (_e156.x <= 0.04045f) {
        let _e159 = local_10;
        local_9 = (_e159 * 0.07739938f);
    } else {
        let _e161 = local_10;
        local_9 = pow(((_e161 + 0.055f) * 0.94786733f), 2.4f);
    }
    let _e165 = local_9;
    let _e166 = local_23;
    local_11 = _e166.y;
    if (_e166.y <= 0.04045f) {
        let _e169 = local_11;
        local_8 = (_e169 * 0.07739938f);
    } else {
        let _e171 = local_11;
        local_8 = pow(((_e171 + 0.055f) * 0.94786733f), 2.4f);
    }
    let _e175 = local_8;
    let _e176 = local_23;
    local_12 = _e176.z;
    if (_e176.z <= 0.04045f) {
        let _e179 = local_12;
        local_7 = (_e179 * 0.07739938f);
    } else {
        let _e181 = local_12;
        local_7 = pow(((_e181 + 0.055f) * 0.94786733f), 2.4f);
    }
    let _e185 = local_7;
    let _e186 = vec3<f32>(_e165, _e175, _e185);
    let _e188 = a_col_0_1[3u];
    _S6_ = vec4<f32>(_e186.x, _e186.y, _e186.z, _e188);
    let _e193 = a_tint_0_1;
    let _e194 = _e193.xyz;
    local_24 = _e194;
    local_4 = _e194.x;
    if (_e194.x <= 0.04045f) {
        let _e197 = local_4;
        local_3 = (_e197 * 0.07739938f);
    } else {
        let _e199 = local_4;
        local_3 = pow(((_e199 + 0.055f) * 0.94786733f), 2.4f);
    }
    let _e203 = local_3;
    let _e204 = local_24;
    local_5 = _e204.y;
    if (_e204.y <= 0.04045f) {
        let _e207 = local_5;
        local_2 = (_e207 * 0.07739938f);
    } else {
        let _e209 = local_5;
        local_2 = pow(((_e209 + 0.055f) * 0.94786733f), 2.4f);
    }
    let _e213 = local_2;
    let _e214 = local_24;
    local_6 = _e214.z;
    if (_e214.z <= 0.04045f) {
        let _e217 = local_6;
        local_1 = (_e217 * 0.07739938f);
    } else {
        let _e219 = local_6;
        local_1 = pow(((_e219 + 0.055f) * 0.94786733f), 2.4f);
    }
    let _e223 = local_1;
    let _e224 = vec3<f32>(_e203, _e213, _e223);
    let _e226 = a_tint_0_1[3u];
    _S7_ = vec4<f32>(_e224.x, _e224.y, _e224.z, _e226);
    let _e231 = local_18;
    let _e232 = normalize(_e231);
    local_25 = _e232;
    let _e236 = PushConstants_0_.mvp_0_[0][3u];
    let _e240 = PushConstants_0_.mvp_0_[1][3u];
    let _e241 = vec2<f32>(_e236, _e240);
    let _e242 = local_17;
    let _e247 = PushConstants_0_.mvp_0_[3][3u];
    let _e248 = (dot(_e241, _e242) + _e247);
    let _e249 = dot(_e241, _e232);
    let _e253 = PushConstants_0_.mvp_0_[0][0u];
    let _e257 = PushConstants_0_.mvp_0_[1][0u];
    let _e258 = vec2<f32>(_e253, _e257);
    let _e265 = PushConstants_0_.mvp_0_[3][0u];
    let _e271 = PushConstants_0_.viewport_0_[0u];
    let _e272 = (((_e248 * dot(_e258, _e232)) - (_e249 * (dot(_e258, _e242) + _e265))) * _e271);
    let _e276 = PushConstants_0_.mvp_0_[0][1u];
    let _e280 = PushConstants_0_.mvp_0_[1][1u];
    let _e281 = vec2<f32>(_e276, _e280);
    let _e288 = PushConstants_0_.mvp_0_[3][1u];
    let _e294 = PushConstants_0_.viewport_0_[1u];
    let _e295 = (((_e248 * dot(_e281, _e232)) - (_e249 * (dot(_e281, _e242) + _e288))) * _e294);
    local_26 = (_e248 * _e248);
    let _e297 = (_e248 * _e249);
    local_27 = _e297;
    let _e300 = ((_e272 * _e272) + (_e295 * _e295));
    local_28 = _e300;
    let _e302 = (_e300 - (_e297 * _e297));
    local_29 = _e302;
    if (abs(_e302) > 0.0000000001f) {
        let _e305 = local_25;
        let _e306 = local_26;
        let _e307 = local_27;
        let _e308 = local_28;
        let _e312 = local_29;
        local_30 = (_e305 * ((_e306 * (_e307 + sqrt(_e308))) / _e312));
    } else {
        let _e315 = local_25;
        let _e318 = PushConstants_0_.viewport_0_;
        local_30 = ((_e315 * 2f) / _e318);
    }
    let _e320 = local_30;
    let _e322 = PushConstants_0_.subpixel_order_0_;
    if (_e322 == 0i) {
        local = 1f;
    } else {
        local = 2.3333333f;
    }
    let _e324 = local;
    let _e326 = (_e320 * (1.4142135f * _e324));
    let _e327 = local_17;
    let _e328 = (_e327 + _e326);
    let _e329 = local_15;
    let _e330 = local_19;
    let _e331 = local_20;
    let _e335 = local_16;
    let _e336 = local_21;
    let _e337 = local_22;
    let _e343 = PushConstants_0_.mvp_0_;
    let _e348 = _S2_;
    let _e349 = _S3_;
    let _e350 = _S4_;
    let _e351 = _S6_;
    let _e352 = _S7_;
    let _e353 = _S1_;
    entryPointParam_main_v_glyph_0_ = _e353;
    entryPointParam_main_v_policy0_0_ = _e348;
    entryPointParam_main_v_policy1_0_ = _e349;
    entryPointParam_main_v_banding_0_ = _e350;
    entryPointParam_main_v_color_0_ = _e351;
    entryPointParam_main_v_tint_0_ = _e352;
    entryPointParam_main_v_texcoord_0_ = vec2<f32>((_e329 + dot(_e326, vec2<f32>(_e330, _e331))), (_e335 + dot(_e326, vec2<f32>(_e336, _e337))));
    unnamed.gl_Position = (_e343 * vec4<f32>(_e328.x, _e328.y, 0f, 1f));
    return;
}

@vertex 
fn main(@builtin(vertex_index) gl_VertexIndex: u32, @location(0) a_rect_0_: vec4<f32>, @location(1) a_xform_0_: vec4<f32>, @location(2) a_origin_0_: vec2<f32>, @location(3) a_glyph_0_: vec2<u32>, @location(7) a_policy0_0_: vec4<u32>, @location(8) a_policy1_0_: vec3<u32>, @location(4) a_bnd_0_: vec4<f32>, @location(5) a_col_0_: vec4<f32>, @location(6) a_tint_0_: vec4<f32>) -> VertexOutput {
    gl_VertexIndex_1 = i32(gl_VertexIndex);
    a_rect_0_1 = a_rect_0_;
    a_xform_0_1 = a_xform_0_;
    a_origin_0_1 = a_origin_0_;
    a_glyph_0_1 = a_glyph_0_;
    a_policy0_0_1 = a_policy0_0_;
    a_policy1_0_1 = a_policy1_0_;
    a_bnd_0_1 = a_bnd_0_;
    a_col_0_1 = a_col_0_;
    a_tint_0_1 = a_tint_0_;
    main_1();
    let _e31 = unnamed.gl_Position.y;
    unnamed.gl_Position.y = -(_e31);
    let _e33 = entryPointParam_main_v_glyph_0_;
    let _e34 = entryPointParam_main_v_policy0_0_;
    let _e35 = entryPointParam_main_v_policy1_0_;
    let _e36 = entryPointParam_main_v_banding_0_;
    let _e37 = entryPointParam_main_v_color_0_;
    let _e38 = entryPointParam_main_v_tint_0_;
    let _e39 = entryPointParam_main_v_texcoord_0_;
    let _e40 = unnamed.gl_Position;
    return VertexOutput(_e33, _e34, _e35, _e36, _e37, _e38, _e39, _e40);
}
