layout(location = 0) in vec4 a_rect;    // source bbox: min_x, min_y, max_x, max_y (em-space, f16 storage)
layout(location = 1) in vec4 a_xform;   // linear transform: xx, xy, yx, yy
layout(location = 2) in vec2 a_origin;  // tx, ty
layout(location = 3) in uvec2 a_glyph;  // gz, gw packed glyph data
layout(location = 4) in vec4 a_bnd;     // band scale x, scale y, offset x, offset y
layout(location = 5) in vec4 a_col;     // vertex color RGBA

uniform mat4 u_mvp;
uniform vec2 u_viewport;
uniform int u_subpixel_order;

out vec4 v_color;
out vec2 v_texcoord;
flat out vec4 v_banding;
flat out ivec4 v_glyph;

#define SNAIL_VERTEX_INDEX gl_VertexID
#define SNAIL_MVP u_mvp
#define SNAIL_VIEWPORT u_viewport
#define SNAIL_SUBPIXEL_ORDER u_subpixel_order
