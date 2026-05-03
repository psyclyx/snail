#version 450
#extension GL_GOOGLE_include_directive : require

layout(location = 0) in vec4 v_color;
layout(location = 1) in vec2 v_texcoord;
layout(location = 2) flat in vec4 v_banding;
layout(location = 3) flat in ivec4 v_glyph;

layout(set = 0, binding = 0) uniform sampler2DArray u_curve_tex;
layout(set = 0, binding = 1) uniform usampler2DArray u_band_tex;

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    vec2 viewport;
    int fill_rule;
    int subpixel_order;
    int layer_base;
};

layout(location = 0) out vec4 frag_color;
#ifdef SNAIL_DUAL_SOURCE
layout(location = 0, index = 1) out vec4 frag_blend;
#endif

#define SNAIL_FILL_RULE fill_rule
#define SNAIL_SUBPIXEL_ORDER subpixel_order
#define u_layer_base layer_base

#include "snail_text_subpixel_body.glsl"
