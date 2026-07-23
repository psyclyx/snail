// LCD-subpixel autohint family (dual-source blended): native-Slang single
// source. Fragment-only family — the vertex stage is the autohint
// family's own vertex (families/autohint.slang vertexMain; identical
// varying interface, locations 0..13), so hosts pair autohint.vert with
// this fragment.
//
// Dual-source output contract matches families/text_subpixel.slang: both
// outputs at location 0, blend output carries SPIR-V `Index 1`
// ([[vk::index(1)]]). No GLES artifact (ES 3.0 has no dual-source
// blending). The WGSL artifact gains a second, dual-source entry
// (`fragmentDualMain`, @blend_src 0/1) at generation time via
// build/wgsl_gen_dual_entry.zig — a mechanical clone of fragmentMain, no
// mangled names involved; naga validation is the tripwire.
module autohint_subpixel_family;

import render_abi;
import color_common;
import coverage_common;
import text_coverage;
import autohint_warp;
import autohint_frag;
import autohint_subpixel_frag;
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
[[vk::binding(0, 0)]] Texture2DArray<float4> u_curve_tex;
[[vk::binding(1, 0)]] Texture2DArray<uint2> u_band_tex;
[[vk::binding(2, 0)]] Texture2D<float4> u_layer_tex;
#elif defined(SNAIL_TARGET_WGSL)
[[vk::binding(0, 2)]] ConstantBuffer<SnailPushConstants> pc;
[[vk::binding(0, 0)]] Texture2DArray<float4> u_curve_tex;
[[vk::binding(1, 0)]] Texture2DArray<uint2> u_band_tex;
[[vk::binding(2, 0)]] Texture2D<float4> u_layer_tex;
#else // GL family (desktop GLSL 330; no GLES leg), D3D11 HLSL, and Metal MSL
ConstantBuffer<SnailPushConstants> pc;
Texture2DArray<float4> u_curve_tex;
Texture2DArray<uint2> u_band_tex;
Texture2D<float4> u_layer_tex;
#endif

struct VsOutput {
    float4 position : SV_Position;
    [[vk::location(0)]] float4 paint : TEXCOORD0;
    [[vk::location(1)]] float3 texcoord_layer : TEXCOORD1;
    [[vk::location(2)]] nointerpolation int2 info : TEXCOORD2;
    [[vk::location(3)]] nointerpolation uint4 policy : TEXCOORD3;
    [[vk::location(4)]] nointerpolation float4 x_targets0 : TEXCOORD4;
    [[vk::location(5)]] nointerpolation float4 x_targets1 : TEXCOORD5;
    [[vk::location(6)]] nointerpolation float4 x_targets2 : TEXCOORD6;
    [[vk::location(7)]] nointerpolation float4 x_targets3 : TEXCOORD7;
    [[vk::location(8)]] nointerpolation float4 y_targets0 : TEXCOORD8;
    [[vk::location(9)]] nointerpolation float4 y_targets1 : TEXCOORD9;
    [[vk::location(10)]] nointerpolation float4 y_targets2 : TEXCOORD10;
    [[vk::location(11)]] nointerpolation float4 y_targets3 : TEXCOORD11;
    [[vk::location(12)]] nointerpolation uint4 x_sources : TEXCOORD12;
    [[vk::location(13)]] nointerpolation uint4 y_sources : TEXCOORD13;
};

struct FsOutput {
    [[vk::location(0)]] float4 color : SV_Target0;
    [[vk::location(0)]] [[vk::index(1)]] float4 blend : SV_Target1;
};


[shader("fragment")]
FsOutput fragmentMain(VsOutput input) {
    AutohintVaryings v;
    v.paint = input.paint;
    v.texcoord_layer = input.texcoord_layer;
    v.info = input.info;
    v.policy = input.policy;
    v.x_targets[0] = input.x_targets0;
    v.x_targets[1] = input.x_targets1;
    v.x_targets[2] = input.x_targets2;
    v.x_targets[3] = input.x_targets3;
    v.y_targets[0] = input.y_targets0;
    v.y_targets[1] = input.y_targets1;
    v.y_targets[2] = input.y_targets2;
    v.y_targets[3] = input.y_targets3;
    v.x_sources = input.x_sources;
    v.y_sources = input.y_sources;
    SubpixelResult r = snailAutohintSubpixelFragment(v, u_curve_tex, u_band_tex, u_layer_tex,
                                                     pc.layer_base, pc.subpixel_order,
                                                     pc.output_srgb, pc.coverage_exponent);
    if (r.discard_fragment) discard;
    FsOutput o;
    o.color = r.color;
    o.blend = r.blend;
    return o;
}
