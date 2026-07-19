#version 450
#extension GL_GOOGLE_include_directive : require

layout(location = 0) in vec4 v_paint;
layout(location = 1) in vec3 v_texcoord_layer;
layout(location = 2) flat in ivec2 v_info;
layout(location = 3) flat in uvec4 v_policy0;
layout(location = 4) flat in uvec3 v_policy1;
layout(location = 5) flat in vec4 v_ah_x_targets[4];
layout(location = 9) flat in vec4 v_ah_y_targets[4];
layout(location = 13) flat in uvec4 v_ah_x_sources;
layout(location = 14) flat in uvec4 v_ah_y_sources;

layout(set = 0, binding = 0) uniform sampler2DArray u_curve_tex;
layout(set = 0, binding = 1) uniform usampler2DArray u_band_tex;
layout(set = 0, binding = 2) uniform sampler2D u_layer_tex;

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    vec2 viewport;
    int subpixel_order;
    int output_srgb;
    int layer_base;
    float coverage_exponent;
    float dither_scale;
    int mask_output;
};

layout(location = 0) out vec4 frag_color;

#define SNAIL_OUTPUT_SRGB output_srgb
#define SNAIL_COVERAGE_EXPONENT coverage_exponent
#define SNAIL_MASK_OUTPUT mask_output
#define u_layer_base layer_base

#include "snail_render_abi.glsl"
#include "snail_coverage_common.glsl"
#include "snail_color_common.glsl"
#include "snail_text_frag_body.glsl"
#include "snail_autohint_warp.glsl"
#include "snail_autohint_fast_main.glsl"

void main() { snailAutohintFragment(); }
