#version 450
#extension GL_GOOGLE_include_directive : require

layout(location = 0) in vec4 v_color;
layout(location = 1) in vec2 v_texcoord;
layout(location = 2) flat in vec4 v_banding;
layout(location = 3) flat in ivec4 v_glyph;
layout(location = 4) flat in vec4 v_hint_src;
layout(location = 5) flat in vec4 v_hint_dst;
layout(location = 6) flat in vec2 v_hint_bounds;

layout(set = 0, binding = 0) uniform sampler2DArray u_curve_tex;
layout(set = 0, binding = 1) uniform usampler2DArray u_band_tex;

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    vec2 viewport;
    int fill_rule;
    int subpixel_order;
};

layout(location = 0) out vec4 frag_color;

#define SNAIL_FILL_RULE fill_rule

#include "snail_text_frag_body.glsl"

void main() {
    int atlas_layer = (v_glyph.w >> 8) & 0xFF;
    if (atlas_layer == 0xFF) discard;
    vec2 rc = hintedLocalCoord(v_texcoord);
    vec2 ppe = 1.0 / max(fwidth(rc), vec2(1.0 / 65536.0));
    float cov = evalGlyphCoverage(rc, ppe, v_glyph.xy,
                                  ivec2(v_glyph.z, v_glyph.w & 0xFF),
                                  v_banding, atlas_layer);
    if (cov < 1.0 / 255.0) discard;
    vec4 linear_color = vec4(srgbDecode(v_color.r), srgbDecode(v_color.g), srgbDecode(v_color.b), v_color.a);
    frag_color = premultiplyColor(linear_color, cov);
}
