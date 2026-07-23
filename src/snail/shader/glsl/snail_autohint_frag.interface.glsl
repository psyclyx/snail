in vec4 v_paint;
in vec3 v_texcoord_layer;
flat in ivec2 v_info;
flat in uvec4 v_policy;
flat in vec4 v_ah_x_targets[4];
flat in vec4 v_ah_y_targets[4];
flat in uvec4 v_ah_x_sources;
flat in uvec4 v_ah_y_sources;

uniform sampler2DArray u_curve_tex;
uniform usampler2DArray u_band_tex;
uniform sampler2D u_layer_tex;
uniform int u_output_srgb;
uniform float u_coverage_exponent;
uniform int u_mask_output;
uniform int u_layer_base;

out vec4 frag_color;

#define SNAIL_OUTPUT_SRGB u_output_srgb
#define SNAIL_COVERAGE_EXPONENT u_coverage_exponent
#define SNAIL_MASK_OUTPUT u_mask_output
