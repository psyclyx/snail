// TT-hinted-text family: native-Slang single source for all four GPU
// targets. Fragment-only family — the vertex stage is the shared text
// vertex (families/text.slang; GL hosts pair with the -O0 painted vertex,
// see README-notes trap 9).
//
// Per-target compile flags and the naga legs match families/painted.slang
// (see build/slang_shaders.zig). The fragment has loops (text-family
// coverage evaluator), so its GL leg goes -emit-spirv-via-glsl -O0 + ADCE.
module tt_hinted_text;

import render_abi;
import color_common;
import coverage_common;
import text_coverage;
import tt_hinted;

public struct SnailPushConstants {
    public float4x4 mvp;
    public float2 viewport;
    public int subpixel_order;
    public int output_srgb;
    public int layer_base;
    public float coverage_exponent;
    public float dither_scale;
    public int mask_output;
};

#if defined(SNAIL_TARGET_VULKAN)
[[vk::push_constant]] ConstantBuffer<SnailPushConstants> pc;
[[vk::binding(0, 0)]] Texture2DArray<float4> u_curve_tex;
[[vk::binding(1, 0)]] Texture2DArray<uint2> u_band_tex;
[[vk::binding(2, 0)]] Texture2D<float4> u_layer_tex;
#elif defined(SNAIL_TARGET_WGSL)
[[vk::binding(0, 2)]] ConstantBuffer<SnailPushConstants> pc;
[[vk::binding(0, 0)]] Texture2DArray<float4> u_curve_tex;
[[vk::binding(1, 0)]] Texture2DArray<uint2> u_band_tex;
[[vk::binding(2, 0)]] Texture2D<float4> u_layer_tex;
#else // GL family (desktop GLSL 330 / GLES 300 es), D3D11 HLSL (registers b0/t0..t3/s0 in declaration order), and Metal MSL ([[buffer(0)]] / [[texture(0..3)]] / [[sampler(0)]], same declaration order)
ConstantBuffer<SnailPushConstants> pc;
Texture2DArray<float4> u_curve_tex;
Texture2DArray<uint2> u_band_tex;
Texture2D<float4> u_layer_tex;
#endif

struct VsOutput {
    float4 position : SV_Position;
    [[vk::location(0)]] float4 color : TEXCOORD0;
    [[vk::location(1)]] float2 texcoord : TEXCOORD1;
    [[vk::location(2)]] nointerpolation float4 banding : TEXCOORD2;
    [[vk::location(3)]] nointerpolation int4 glyph : TEXCOORD3;
    [[vk::location(4)]] float4 tint : TEXCOORD4;
};

[shader("fragment")]
float4 fragmentMain(VsOutput input) : SV_Target {
    TtHintedVaryings v;
    v.color = input.color;
    v.tint = input.tint;
    v.texcoord = input.texcoord;
    v.banding = input.banding;
    v.glyph = input.glyph;
    return snailTtHintedTextFragment(v, u_curve_tex, u_band_tex, u_layer_tex,
                                     pc.layer_base, pc.output_srgb,
                                     pc.coverage_exponent, pc.mask_output);
}
