in vec4 v_color;
in vec2 v_texcoord;
flat in vec4 v_banding;
flat in ivec4 v_glyph;

uniform sampler2DArray u_curve_tex;
uniform usampler2DArray u_band_tex;
uniform int u_fill_rule;
uniform float u_coverage_exponent;
uniform int u_layer_base;

#define SNAIL_FILL_RULE u_fill_rule
#define SNAIL_COVERAGE_EXPONENT u_coverage_exponent
