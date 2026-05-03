in vec4 v_color;
in vec2 v_texcoord;
flat in vec4 v_banding;
flat in ivec4 v_glyph;

uniform sampler2DArray u_curve_tex;
uniform usampler2DArray u_band_tex;
uniform sampler2D u_layer_tex;
uniform sampler2DArray u_image_tex;
uniform int u_fill_rule; // 0 = non-zero winding (default), 1 = even-odd
uniform int u_layer_base;

out vec4 frag_color;

#define SNAIL_FILL_RULE u_fill_rule
