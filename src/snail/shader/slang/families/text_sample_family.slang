// Text-as-material sampler family: canonical native-Slang artifacts for the
// `text_sample` module. The real consumer is a CALLER-authored Slang
// family that imports the module into its own material shader (the game's
// dev/demo/game/slang/game_material.slang is the worked example); this
// family exists so gen-shaders continuously compiles the module for every
// target and records the canonical binding flavors:
//
//  - Vulkan/WGSL: the emit words in a read-only SSBO (StructuredBuffer) —
//    set 0 binding 4 here (beyond the four atlas textures; a real caller
//    picks its own set/binding, the module does not care).
//  - Desktop GL: a R32UI texel buffer (Buffer<uint> → usamplerBuffer).
//  - GLES 3.0 (-DSNAIL_TARGET_GLES on the ES leg): a 2D R32UI texture
//    addressed row-major at a fixed width — texel buffers do not exist in
//    ES 3.0 at any extension level (GL_EXT_texture_buffer requires ES 3.1).
//
// The entry samples at an interpolated scene position and returns the
// premultiplied linear paint — the module's contract, nothing more.
module text_sample_family;

import resource_types;

import render_abi;
import color_common;
import coverage_common;
import text_coverage;
import text_sample;

public struct SnailTextSampleParams {
    public int glyph_count;
    public int words_per_glyph;
    public int page_base;
    public float coverage_exponent;
    public int2 atlas_page_texels;
};

#if defined(SNAIL_TARGET_VULKAN)
[[vk::push_constant]] ConstantBuffer<SnailTextSampleParams> pc;
[[vk::binding(0, 0)]] SnailCurveStorage u_curve_tex;
[[vk::binding(1, 0)]] SnailBandStorage u_band_tex;
[[vk::binding(4, 0)]] StructuredBuffer<uint> u_snail_text_records;
struct Records : ISnailTextSource {
    uint word(int linear_index) { return u_snail_text_records[linear_index]; }
    uint pageBase(int glyph_index) { return uint(pc.page_base); }
    SnailAtlasLayout atlasLayout() { return snailAtlasLayout(pc.atlas_page_texels); }
};
#elif defined(SNAIL_TARGET_WGSL)
[[vk::binding(0, 2)]] ConstantBuffer<SnailTextSampleParams> pc;
[[vk::binding(0, 0)]] SnailCurveStorage u_curve_tex;
[[vk::binding(1, 0)]] SnailBandStorage u_band_tex;
[[vk::binding(4, 0)]] StructuredBuffer<uint> u_snail_text_records;
struct Records : ISnailTextSource {
    uint word(int linear_index) { return u_snail_text_records[linear_index]; }
    uint pageBase(int glyph_index) { return uint(pc.page_base); }
    SnailAtlasLayout atlasLayout() { return snailAtlasLayout(pc.atlas_page_texels); }
};
#elif defined(SNAIL_TARGET_GLES)
ConstantBuffer<SnailTextSampleParams> pc;
SnailCurveStorage u_curve_tex;
SnailBandStorage u_band_tex;
// GLES 3.0: 2D R32UI texture, row-major at a fixed width (the upload side
// pads the tail row with zeros; the composed catalog's
// SNAIL_TEXT_RECORDS_TEX_WIDTH contract).
SnailUintTexture2D u_snail_text_records;
static const int SNAIL_TEXT_RECORDS_TEX_WIDTH = 1024;
struct Records : ISnailTextSource {
    uint word(int linear_index) {
        return u_snail_text_records.Load(int3(linear_index % SNAIL_TEXT_RECORDS_TEX_WIDTH,
                                              linear_index / SNAIL_TEXT_RECORDS_TEX_WIDTH, 0)).x;
    }
    uint pageBase(int glyph_index) { return uint(pc.page_base); }
    SnailAtlasLayout atlasLayout() { return snailAtlasLayout(pc.atlas_page_texels); }
};
#else // Desktop GL, D3D11, and Metal: R32UI texel buffer (Buffer<uint> →
      // usamplerBuffer / t2 / MSL texture_buffer<uint> at [[texture(2)]],
      // which needs MSL 2.1+ at pipeline compile time).
ConstantBuffer<SnailTextSampleParams> pc;
SnailCurveStorage u_curve_tex;
SnailBandStorage u_band_tex;
Buffer<uint> u_snail_text_records;
struct Records : ISnailTextSource {
    uint word(int linear_index) { return u_snail_text_records[linear_index]; }
    uint pageBase(int glyph_index) { return uint(pc.page_base); }
    SnailAtlasLayout atlasLayout() { return snailAtlasLayout(pc.atlas_page_texels); }
};
#endif

struct FsInput {
    float4 position : SV_Position;
    [[vk::location(0)]] float2 scene_pos : TEXCOORD0;
};

[shader("fragment")]
float4 fragmentMain(FsInput input) : SV_Target {
    Records records;
    return snailTextSamplePremulLinear(records, pc.words_per_glyph, pc.glyph_count,
                                       pc.coverage_exponent,
                                       u_curve_tex, u_band_tex, input.scene_pos);
}
