// Custom Vulkan material shader for the game demo: samples snail glyph coverage
// at arbitrary UVs (the "custom shader" showcase) and lights it over an opaque
// panel. This is the worked example of `snail.vulkan.embeddable`: a caller-owned
// fragment shader that #includes snail's shipped coverage + sample sources and
// binds snail's atlas plane (set 0) + a caller-owned records SSBO (set 1).
#version 450
#extension GL_GOOGLE_include_directive : require

layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 frag_color;

// snail's atlas plane (set 0) — reuse VulkanBackendCache.descriptorSet().
layout(set = 0, binding = 0) uniform sampler2DArray u_curve_tex;
layout(set = 0, binding = 1) uniform usampler2DArray u_band_tex;

layout(push_constant) uniform PC {
    mat4 mvp;
    vec4 base_color;
    vec4 light_dir;   // xyz = tangent-space light
    vec2 scene_size;
    int glyph_count;
    int output_srgb;
    float relief;
    float roughness;
} pc;

// Coverage-math configuration the snail includes expect.
#define SNAIL_FILL_RULE 1          // font convention: non-zero winding
#define SNAIL_COVERAGE_EXPONENT 1.0
#define u_layer_base 0             // emit bakes the absolute layer into each word
#define u_snail_text_glyph_count pc.glyph_count
// Record stride: must match snail's WORDS_PER_INSTANCE (asserted 23 in
// src/snail/format/vertex.zig). The GL path injects this from Zig; the Vulkan
// caller sets it at build time.
#define SNAIL_TEXT_RECORD_WORDS_PER_GLYPH 23

#include "snail_render_abi.glsl"
#include "snail_coverage_common.glsl"
#include "snail_color_common.glsl"
#include "snail_text_frag_body.glsl"                 // evalGlyphCoverage
#define SNAIL_RECORDS_SET 1
#define SNAIL_RECORDS_BINDING 0
#include "snail_text_sample.interface.vulkan.glsl"
#include "snail_text_sample_body.glsl"               // snail_text_sample_premul_linear
#include "game_material_body.glsl"                    // snailGameMaterial (rough lit surface)

void main() {
    vec2 scene_pos = vec2(v_uv.x * pc.scene_size.x, (1.0 - v_uv.y) * pc.scene_size.y);
    vec2 texel = pc.scene_size * 0.009;
    vec3 lin = snailGameMaterial(v_uv, scene_pos, texel, pc.light_dir.xyz, pc.base_color, pc.relief, pc.roughness);
    // The Vulkan swapchain/offscreen target is an sRGB format that encodes on
    // store, so emit linear.
    frag_color = vec4(lin, 1.0);
}
