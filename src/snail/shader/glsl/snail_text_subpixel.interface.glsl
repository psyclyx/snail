in vec4 v_color;
in vec4 v_tint;
in vec2 v_texcoord;
flat in vec4 v_banding;
flat in ivec4 v_glyph;

uniform sampler2DArray u_curve_tex;
uniform usampler2DArray u_band_tex;
uniform int u_subpixel_order; // 1=RGB, 2=BGR, 3=VRGB, 4=VBGR
uniform int u_output_srgb; // 0 = emit linear, 1 = sRGB-encode before write
uniform float u_coverage_exponent; // 1 = identity; <1 strengthens edges
uniform int u_mask_output; // 1 = single-channel mask target: emit painted alpha
uniform int u_layer_base;

out vec4 frag_color;
#ifdef SNAIL_DUAL_SOURCE
out vec4 frag_blend;
#endif

// Text glyphs from fonts are non-zero winding by convention; the
// no-arg applyFillRule overload defaults to that. No fill_rule uniform.
#define SNAIL_SUBPIXEL_ORDER u_subpixel_order
#define SNAIL_OUTPUT_SRGB u_output_srgb
#define SNAIL_COVERAGE_EXPONENT u_coverage_exponent
#define SNAIL_MASK_OUTPUT u_mask_output
