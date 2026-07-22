#version 330 core
struct SnailLinearResolveParams_std140_ {
    int mode;
};
layout(std140) uniform SnailLinearResolveParams_std140_block_0Fragment { SnailLinearResolveParams_std140_ _group_0_binding_0_fs; };

vec2 input_u002e_uv_1 = vec2(0.0);

uniform sampler2D _group_0_binding_3_fs;

vec4 entryPointParam_fragmentMain = vec4(0.0);

uniform sampler2D _group_0_binding_1_fs;

smooth in vec2 _vs2fs_location0;
layout(location = 0) out vec4 _fs2p_location0;

float srgbEncode(float c) {
    float local = 0.0;
    if ((c <= 0.0031308)) {
        local = (c * 12.92);
    } else {
        local = ((1.055 * pow(c, 0.41666666)) - 0.055);
    }
    float _e28 = local;
    return _e28;
}

vec3 linearToSrgb(vec3 color) {
    float _e24 = srgbEncode(max(color.x, 0.0));
    float _e27 = srgbEncode(max(color.y, 0.0));
    float _e30 = srgbEncode(max(color.z, 0.0));
    return vec3(_e24, _e27, _e30);
}

vec4 srgbEncodePremultiplied(vec4 premul) {
    if ((premul.w <= 0.0)) {
        return vec4(0.0, 0.0, 0.0, 0.0);
    }
    vec3 _e27 = linearToSrgb((premul.xyz * (1.0 / premul.w)));
    return vec4((_e27 * premul.w), premul.w);
}

vec4 snailLinearResolveEncode(vec4 linear_premul) {
    vec4 _e22 = srgbEncodePremultiplied(linear_premul);
    return _e22;
}

float srgbDecode(float c_1) {
    float local_1 = 0.0;
    if ((c_1 <= 0.04045)) {
        local_1 = (c_1 / 12.92);
    } else {
        local_1 = pow(((c_1 + 0.055) / 1.055), 2.4);
    }
    float _e28 = local_1;
    return _e28;
}

vec3 srgbToLinear(vec3 color_1) {
    float _e23 = srgbDecode(color_1.x);
    float _e25 = srgbDecode(color_1.y);
    float _e27 = srgbDecode(color_1.z);
    return vec3(_e23, _e25, _e27);
}

vec4 snailLinearResolveSeed(vec4 dst_premul) {
    if ((dst_premul.w <= 0.0)) {
        return vec4(0.0, 0.0, 0.0, 0.0);
    }
    vec3 _e28 = srgbToLinear(clamp((dst_premul.xyz * (1.0 / dst_premul.w)), vec3(0.0, 0.0, 0.0), vec3(1.0, 1.0, 1.0)));
    return vec4((_e28 * dst_premul.w), dst_premul.w);
}

void fragmentMain() {
    int _e22 = _group_0_binding_0_fs.mode;
    if ((_e22 == 0)) {
        vec2 _e24 = input_u002e_uv_1;
        vec4 _e25 = texture(_group_0_binding_3_fs, vec2(_e24));
        vec4 _e26 = snailLinearResolveSeed(_e25);
        entryPointParam_fragmentMain = _e26;
        return;
    }
    vec2 _e27 = input_u002e_uv_1;
    vec4 _e28 = texture(_group_0_binding_1_fs, vec2(_e27));
    vec4 _e29 = snailLinearResolveEncode(_e28);
    entryPointParam_fragmentMain = _e29;
    return;
}

void main() {
    vec2 input_u002e_uv = _vs2fs_location0;
    input_u002e_uv_1 = input_u002e_uv;
    fragmentMain();
    vec4 _e3 = entryPointParam_fragmentMain;
    _fs2p_location0 = _e3;
    return;
}

