in vec4 v_color;
in vec4 v_tint;
in vec2 v_texcoord;
flat in vec4 v_banding;
flat in ivec4 v_glyph;

uniform sampler2DArray u_curve_tex;
uniform usampler2DArray u_band_tex;
uniform sampler2D u_layer_tex;
uniform sampler2DArray u_image_tex;
uniform int u_output_srgb; // 0 = emit linear, 1 = sRGB-encode before write
uniform float u_coverage_exponent; // 1 = identity; <1 strengthens edges
uniform int u_layer_base;

out vec4 frag_color;

// Fill rule is now encoded per paint record (bit 15 of texel 0.x); text /
// COLR / hinted shaders default to non-zero via the no-arg applyFillRule
// overload.
#define SNAIL_OUTPUT_SRGB u_output_srgb
#define SNAIL_COVERAGE_EXPONENT u_coverage_exponent
