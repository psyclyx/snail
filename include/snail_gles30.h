#ifndef SNAIL_GLES30_H
#define SNAIL_GLES30_H

#include "snail.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int curve_tex_loc;
    int band_tex_loc;
    int layer_tex_loc;
    int image_tex_loc;
    int fill_rule_loc;
    int subpixel_order_loc;
    int output_srgb_loc;
    int coverage_exponent_loc;
    int layer_base_loc;
    int curve_tex_unit;
    int band_tex_unit;
    int layer_tex_unit;
    int image_tex_unit;
} SnailGles30TextCoverageProgram;

int snail_gles30_renderer_init(SnailRenderer **out);
SnailString snail_gles30_coverage_shader_vertex_interface(void);
SnailString snail_gles30_coverage_shader_fragment_interface(void);
SnailString snail_gles30_coverage_shader_resource_interface(void);
SnailString snail_gles30_coverage_shader_coverage_functions(void);
SnailString snail_gles30_coverage_shader_sample_interface(void);
SnailString snail_gles30_coverage_shader_sample_functions(void);
SnailString snail_gles30_coverage_shader_fragment_body(void);
int snail_gles30_coverage_backend_bind_program(SnailCoverageBackend *backend,
                                               SnailGles30TextCoverageProgram program);
int snail_gles30_coverage_backend_bind_draw_state(SnailCoverageBackend *backend,
                                                  SnailGles30TextCoverageProgram program,
                                                  SnailCoverageDrawState state);

#ifdef __cplusplus
}
#endif

#endif /* SNAIL_GLES30_H */
