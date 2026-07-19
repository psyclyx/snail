#version 450
#extension GL_GOOGLE_include_directive : require

layout(location = 0) in vec4 a_rect;
layout(location = 1) in vec4 a_xform;
layout(location = 2) in vec2 a_origin;
layout(location = 3) in uvec2 a_glyph;
layout(location = 4) in vec4 a_bnd;
layout(location = 5) in vec4 a_col;
layout(location = 6) in vec4 a_tint;
layout(location = 7) in uvec4 a_policy0;
layout(location = 8) in uvec3 a_policy1;

layout(set = 0, binding = 2) uniform sampler2D u_layer_tex;

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    vec2 viewport;
    int subpixel_order;
};

layout(location = 0) out vec4 v_paint;
layout(location = 1) out vec3 v_texcoord_layer;
layout(location = 2) flat out ivec2 v_info;
layout(location = 3) flat out uvec4 v_policy0;
layout(location = 4) flat out uvec3 v_policy1;
layout(location = 5) flat out vec4 v_ah_x_targets[4];
layout(location = 9) flat out vec4 v_ah_y_targets[4];
layout(location = 13) flat out uvec4 v_ah_x_sources;
layout(location = 14) flat out uvec4 v_ah_y_sources;

#define SNAIL_AUTOHINT_VERTEX 1
#define SNAIL_VERTEX_INDEX gl_VertexIndex
#define SNAIL_MVP mvp
#define SNAIL_VIEWPORT viewport
#define SNAIL_SUBPIXEL_ORDER subpixel_order

#include "snail_color_common.glsl"
#include "snail_autohint_warp.glsl"
#include "snail_vert_body.glsl"
#include "snail_autohint_vert_body.glsl"

void main() { snailAutohintVertex(); }
