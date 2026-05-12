#version 450
#extension GL_GOOGLE_include_directive : require

layout(location = 0) in vec4 v_color;
layout(location = 1) in vec2 v_texcoord;
layout(location = 2) flat in vec4 v_banding;
layout(location = 3) flat in ivec4 v_glyph;
layout(location = 4) in vec4 v_tint;

layout(set = 0, binding = 0) uniform sampler2DArray u_curve_tex;
layout(set = 0, binding = 1) uniform usampler2DArray u_band_tex;

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    vec2 viewport;
    int fill_rule;
    int subpixel_order;
    int output_srgb;
    int layer_base;
};

layout(location = 0) out vec4 frag_color;

#define SNAIL_FILL_RULE fill_rule
#define SNAIL_OUTPUT_SRGB output_srgb
#define u_layer_base layer_base

#include "snail_text_frag_body.glsl"

void main() {
    int layer_byte = (v_glyph.w >> 8) & 0xFF;
    if (layer_byte == 0xFF) discard;
    int atlas_layer = u_layer_base + layer_byte;
    vec2 rc = v_texcoord;
    vec2 dx = vec2(dFdx(rc.x), dFdy(rc.x));
    vec2 dy = vec2(dFdx(rc.y), dFdy(rc.y));
    vec2 ppe = vec2(1.0 / max(length(dx), 1.0 / 65536.0), 1.0 / max(length(dy), 1.0 / 65536.0));
    float cov = evalGlyphCoverage(rc, ppe, v_glyph.xy,
                                  ivec2(v_glyph.w & 0xFF, v_glyph.z),
                                  v_banding, atlas_layer);
    if (cov < 1.0 / 255.0) discard;
    vec4 linear_color = vec4(srgbDecode(v_color.r), srgbDecode(v_color.g), srgbDecode(v_color.b), v_color.a);
    vec4 linear_tint = vec4(srgbDecode(v_tint.r), srgbDecode(v_tint.g), srgbDecode(v_tint.b), v_tint.a);
    linear_color *= linear_tint;
    vec4 premul = premultiplyColor(linear_color, cov);
    frag_color = (SNAIL_OUTPUT_SRGB != 0) ? srgbEncodePremultiplied(premul) : premul;
}
