// LCD-subpixel TT-hinted-text family (dual-source blended): native-Slang
// single source. Fragment-only family — the vertex stage is the shared
// text vertex, exactly like families/tt_hinted_text.slang.
//
// Dual-source output contract matches families/text_subpixel.slang: both
// outputs at location 0, blend output carries SPIR-V `Index 1`
// ([[vk::index(1)]]). No GLES artifact (ES 3.0 has no dual-source
// blending). The WGSL artifact gains a second, dual-source entry
// (`fragmentDualMain`, @blend_src 0/1) at generation time via
// build/wgsl_gen_dual_entry.zig — a mechanical clone of fragmentMain, no
// mangled names involved; naga validation is the tripwire.
module tt_hinted_text_subpixel_family;

import resource_types;

import render_abi;
import color_common;
import coverage_common;
import text_coverage;
import tt_hinted;
import tt_hinted_subpixel;
import subpixel_body;

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
[[vk::binding(0, 0)]] SnailFloatTexture2DArray u_curve_tex;
[[vk::binding(1, 0)]] SnailUint2Texture2DArray u_band_tex;
[[vk::binding(2, 0)]] SnailFloatTexture2D u_layer_tex;
#elif defined(SNAIL_TARGET_WGSL)
[[vk::binding(0, 2)]] ConstantBuffer<SnailPushConstants> pc;
[[vk::binding(0, 0)]] SnailFloatTexture2DArray u_curve_tex;
[[vk::binding(1, 0)]] SnailUint2Texture2DArray u_band_tex;
[[vk::binding(2, 0)]] SnailFloatTexture2D u_layer_tex;
#else // GL family (desktop GLSL 330; no GLES leg), D3D11 HLSL, and Metal MSL
ConstantBuffer<SnailPushConstants> pc;
SnailFloatTexture2DArray u_curve_tex;
SnailUint2Texture2DArray u_band_tex;
SnailFloatTexture2D u_layer_tex;
#endif

struct VsOutput {
    float4 position : SV_Position;
    [[vk::location(0)]] float4 color : TEXCOORD0;
    [[vk::location(1)]] float2 texcoord : TEXCOORD1;
    [[vk::location(2)]] nointerpolation float4 banding : TEXCOORD2;
    [[vk::location(3)]] nointerpolation int4 glyph : TEXCOORD3;
    [[vk::location(4)]] float4 tint : TEXCOORD4;
};

struct FsOutput {
    [[vk::location(0)]] float4 color : SV_Target0;
    [[vk::location(0)]] [[vk::index(1)]] float4 blend : SV_Target1;
};


[shader("fragment")]
FsOutput fragmentMain(VsOutput input) {
    TtHintedVaryings v;
    v.color = input.color;
    v.tint = input.tint;
    v.texcoord = input.texcoord;
    v.banding = input.banding;
    v.glyph = input.glyph;
    SubpixelResult r = snailTtHintedSubpixelFragment(v, u_curve_tex, u_band_tex, u_layer_tex,
                                                     pc.layer_base, pc.subpixel_order,
                                                     pc.output_srgb, pc.coverage_exponent);
    if (r.discard_fragment) discard;
    FsOutput o;
    o.color = r.color;
    o.blend = r.blend;
    return o;
}
