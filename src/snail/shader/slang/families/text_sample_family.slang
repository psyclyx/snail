// Text-as-material sampler family: canonical native-Slang artifacts for the
// `text_sample` module. The real consumer is a CALLER-authored material
// shader (the game composes the GLSL body into its own fragment program
// with its own record storage and uniforms — see
// src/snail/shader/glsl/snail_text_sample.interface.*.glsl). Migrating that
// consumer is stage C; this family exists so gen-shaders continuously
// compiles the module for every target and records the canonical binding
// flavors:
//
//  - Vulkan/WGSL: the emit words in a read-only SSBO (StructuredBuffer) —
//    set 0 binding 4 here (beyond the four atlas textures; a real caller
//    picks its own set/binding, the module does not care).
//  - Desktop GL: a R32UI texel buffer (Buffer<uint> → usamplerBuffer).
//  - GLES 3.0: skipped — no texel buffers in ES 3.0; the composed catalog's
//    R32UI-2D-texture interface remains the GLES story until stage C.
//
// The entry samples at an interpolated scene position and returns the
// premultiplied linear paint — the module's contract, nothing more.
module text_sample_family;

import render_abi;
import color_common;
import coverage_common;
import text_coverage;
import text_sample;

public struct SnailTextSampleParams {
    public int glyph_count;
    public int words_per_glyph;
    public int layer_base;
    public float coverage_exponent;
};

#if defined(SNAIL_TARGET_VULKAN)
[[vk::push_constant]] ConstantBuffer<SnailTextSampleParams> pc;
[[vk::binding(0, 0)]] Texture2DArray<float4> u_curve_tex;
[[vk::binding(1, 0)]] Texture2DArray<uint2> u_band_tex;
[[vk::binding(4, 0)]] StructuredBuffer<uint> u_snail_text_records;
struct Records : ISnailTextRecords {
    uint word(int linear_index) { return u_snail_text_records[linear_index]; }
};
#elif defined(SNAIL_TARGET_WGSL)
[[vk::binding(0, 2)]] ConstantBuffer<SnailTextSampleParams> pc;
[[vk::binding(0, 0)]] Texture2DArray<float4> u_curve_tex;
[[vk::binding(1, 0)]] Texture2DArray<uint2> u_band_tex;
[[vk::binding(4, 0)]] StructuredBuffer<uint> u_snail_text_records;
struct Records : ISnailTextRecords {
    uint word(int linear_index) { return u_snail_text_records[linear_index]; }
};
#else // Desktop GL: R32UI texel buffer.
ConstantBuffer<SnailTextSampleParams> pc;
Texture2DArray<float4> u_curve_tex;
Texture2DArray<uint2> u_band_tex;
Buffer<uint> u_snail_text_records;
struct Records : ISnailTextRecords {
    uint word(int linear_index) { return u_snail_text_records[linear_index]; }
};
#endif

struct FsInput {
    float4 position : SV_Position;
    [[vk::location(0)]] float2 scene_pos;
};

[shader("fragment")]
float4 fragmentMain(FsInput input) : SV_Target {
    Records records;
    return snailTextSamplePremulLinear(records, pc.words_per_glyph, pc.glyph_count,
                                       pc.layer_base, pc.coverage_exponent,
                                       u_curve_tex, u_band_tex, input.scene_pos);
}
