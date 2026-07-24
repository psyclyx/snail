// LCD-subpixel text family (dual-source blended): native-Slang single
// source. Fragment-only family — the vertex stage is the shared text
// vertex (GL hosts pair with the -O0 painted vertex).
//
// ── Dual-source outputs ──
//
// Both fragment outputs live at location 0; the blend color carries
// SPIR-V `Index 1` ([[vk::index(1)]], the dualSrcBlend contract of
// contract.zig's `.dual_source` blend state). The WGSL artifact gains a
// second, dual-source entry (`fragmentDualMain`, @blend_src 0/1) at
// generation time via build/wgsl_gen_dual_entry.zig — a mechanical clone
// of fragmentMain, no mangled names involved; naga validation is the
// tripwire. The Metal backend drops [[vk::index(1)]] like WGSL's
// and emits plain MRT ([[color(0)]]/[[color(1)]]): a Metal dual-source
// consumer must textually rewrite the blend output to
// [[color(0), index(1)]] before compiling (see README-notes, Metal stage).
module text_subpixel_family;

import resource_types;

import render_abi;
import color_common;
import coverage_common;
import text_coverage;
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
#elif defined(SNAIL_TARGET_WGSL)
[[vk::binding(0, 2)]] ConstantBuffer<SnailPushConstants> pc;
[[vk::binding(0, 0)]] SnailFloatTexture2DArray u_curve_tex;
[[vk::binding(1, 0)]] SnailUint2Texture2DArray u_band_tex;
#else // GL family (desktop GLSL 330; GLES 3.0 has no dual-source blending), D3D11 HLSL, and Metal MSL
ConstantBuffer<SnailPushConstants> pc;
SnailFloatTexture2DArray u_curve_tex;
SnailUint2Texture2DArray u_band_tex;
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
    SubpixelVaryings v;
    v.color = input.color;
    v.tint = input.tint;
    v.texcoord = input.texcoord;
    v.banding = input.banding;
    v.glyph = input.glyph;
    SubpixelResult r = snailSubpixelFragment(v, u_curve_tex, u_band_tex,
                                             pc.layer_base, pc.subpixel_order,
                                             pc.output_srgb, pc.coverage_exponent);
    if (r.discard_fragment) discard;
    FsOutput o;
    o.color = r.color;
    o.blend = r.blend;
    return o;
}
