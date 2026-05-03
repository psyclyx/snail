in vec4 v_color;
in vec2 v_texcoord;
flat in vec4 v_banding;
flat in ivec4 v_glyph;
flat in vec4 v_hint_src;
flat in vec4 v_hint_dst;
flat in vec2 v_hint_bounds;

uniform sampler2DArray u_curve_tex;
uniform usampler2DArray u_band_tex;
uniform int u_fill_rule;
uniform int u_subpixel_order; // 1=RGB, 2=BGR, 3=VRGB, 4=VBGR
uniform int u_layer_base;

out vec4 frag_color;
#ifdef SNAIL_DUAL_SOURCE
out vec4 frag_blend;
#endif

#define SNAIL_FILL_RULE u_fill_rule
#define SNAIL_SUBPIXEL_ORDER u_subpixel_order
