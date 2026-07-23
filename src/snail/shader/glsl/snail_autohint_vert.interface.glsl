layout(location = 0) in vec4 a_rect;
layout(location = 1) in vec4 a_xform;
layout(location = 2) in vec2 a_origin;
layout(location = 3) in uvec2 a_glyph;
layout(location = 4) in uvec4 a_payload;
layout(location = 5) in vec4 a_col;
layout(location = 6) in vec4 a_tint;

uniform mat4 u_mvp;
uniform vec2 u_viewport;
uniform int u_subpixel_order;
uniform sampler2D u_layer_tex;

out vec4 v_paint;
out vec3 v_texcoord_layer;
flat out ivec2 v_info;
flat out uvec4 v_policy;
flat out vec4 v_ah_x_targets[4];
flat out vec4 v_ah_y_targets[4];
flat out uvec4 v_ah_x_sources;
flat out uvec4 v_ah_y_sources;

#define SNAIL_AUTOHINT_VERTEX 1
#define SNAIL_VERTEX_INDEX gl_VertexID
#define SNAIL_MVP u_mvp
#define SNAIL_VIEWPORT u_viewport
#define SNAIL_SUBPIXEL_ORDER u_subpixel_order
