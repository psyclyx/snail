#version 450
#extension GL_GOOGLE_include_directive : require

layout(location = 0) in vec4 a_rect;   // source bbox: min_x, min_y, max_x, max_y (em-space)
layout(location = 1) in vec4 a_xform;  // linear transform: xx, xy, yx, yy
layout(location = 2) in vec2 a_origin; // tx, ty
layout(location = 3) in uvec2 a_glyph; // gz, gw packed
layout(location = 4) in vec4 a_bnd;    // band scale x, scale y, offset x, offset y
layout(location = 5) in vec4 a_col;    // vertex color RGBA

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    vec2 viewport;
    int fill_rule;
    int subpixel_order;
};

layout(location = 0) out vec4 v_color;
layout(location = 1) out vec2 v_texcoord;
layout(location = 2) flat out vec4 v_banding;
layout(location = 3) flat out ivec4 v_glyph;

#define SNAIL_VERTEX_INDEX gl_VertexIndex
#define SNAIL_MVP mvp
#define SNAIL_VIEWPORT viewport
#define SNAIL_SUBPIXEL_ORDER subpixel_order

#include "snail_vert_body.glsl"
