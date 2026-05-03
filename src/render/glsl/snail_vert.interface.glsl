layout(location = 0) in vec4 a_rect;   // bbox: min_x, min_y, max_x, max_y (em-space)
layout(location = 1) in vec4 a_xform;  // linear transform: xx, xy, yx, yy
layout(location = 2) in vec4 a_meta;   // tx, ty, gz (packed), gw (packed)
layout(location = 3) in vec4 a_bnd;    // band scale x, scale y, offset x, offset y
layout(location = 4) in vec4 a_col;    // vertex color RGBA
layout(location = 5) in vec4 a_hint_src; // source stem anchors
layout(location = 6) in vec4 a_hint_dst; // resolved display anchors

uniform mat4 u_mvp;
uniform vec2 u_viewport;

out vec4 v_color;
out vec2 v_texcoord;
flat out vec4 v_banding;
flat out ivec4 v_glyph;
flat out vec4 v_hint_src;
flat out vec4 v_hint_dst;
flat out vec2 v_hint_bounds;

#define SNAIL_VERTEX_INDEX gl_VertexID
#define SNAIL_MVP u_mvp
#define SNAIL_VIEWPORT u_viewport
