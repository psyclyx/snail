// LCD-subpixel text family (dual-source blended): native-Slang single
// source. Fragment-only family — the vertex stage is the shared text
// vertex (GL hosts pair with the -O0 painted vertex).
//
// ── Dual-source outputs ──
//
// Both fragment outputs live at location 0; the blend color carries
// SPIR-V `Index 1` ([[vk::index(1)]], the dualSrcBlend contract of
// contract.zig's `.dual_source` blend state). The GL host binds the
// outputs with glBindFragDataLocationIndexed; WGSL needs the
// dual_source_blending extension (@blend_src) — checked in the generated
// artifact's test.
module text_subpixel_family;

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
[[vk::binding(0, 0)]] Texture2DArray<float4> u_curve_tex;
[[vk::binding(1, 0)]] Texture2DArray<uint2> u_band_tex;
#elif defined(SNAIL_TARGET_WGSL)
[[vk::binding(0, 2)]] ConstantBuffer<SnailPushConstants> pc;
[[vk::binding(0, 0)]] Texture2DArray<float4> u_curve_tex;
[[vk::binding(1, 0)]] Texture2DArray<uint2> u_band_tex;
#else // GL family (desktop GLSL 330; GLES 3.0 has no dual-source blending)
ConstantBuffer<SnailPushConstants> pc;
Texture2DArray<float4> u_curve_tex;
Texture2DArray<uint2> u_band_tex;
#endif

struct VsOutput {
    float4 position : SV_Position;
    [[vk::location(0)]] float4 color;
    [[vk::location(1)]] float2 texcoord;
    [[vk::location(2)]] nointerpolation float4 banding;
    [[vk::location(3)]] nointerpolation int4 glyph;
    [[vk::location(4)]] float4 tint;
};

struct FsOutput {
    [[vk::location(0)]] float4 color : SV_Target0;
    [[vk::location(0)]] [[vk::index(1)]] float4 blend : SV_Target1;
};

#if defined(SNAIL_TARGET_WGSL)
// ── WGSL dual-source interop (spike) ──
//
// slangc's WGSL backend drops [[vk::index(1)]] and renumbers the blend
// output to @location(1) (plain MRT — wrong semantics), and no Slang
// declaration syntax reaches WGSL's @blend_src attribute. The interop
// escape hatch: `__requirePrelude` (a1-04) injects raw WGSL at the very
// top of the emitted module — a position where both the `enable`
// directive and a hand-written second entry point are legal (WGSL
// module-scope declarations are order-independent, so the prelude entry
// may call functions slang emits later). `fragmentDualMain` re-declares
// the varyings itself (mangling-independent) but MUST name the slang-
// mangled body helper, bindings, and struct fields (`_0`/`_1`/`_2`
// suffixes below): those names are stable for a given module content but
// are NOT a slang API contract — any edit to this family or its imports
// can renumber them and break the artifact (gen-shaders + naga validation
// catches it). The plain `fragmentMain` entry stays in the artifact
// (valid MRT module on its own); dual-source consumers must select
// `fragmentDualMain`.
float snailWgslDualSourceInterop() {
    __target_switch {
    case wgsl:
        __requirePrelude(R"(enable dual_source_blending;

struct SnailDualSourceIn
{
    @location(0) color : vec4<f32>,
    @location(1) texcoord : vec2<f32>,
    @interpolate(flat) @location(2) banding : vec4<f32>,
    @interpolate(flat) @location(3) glyph : vec4<i32>,
    @location(4) tint : vec4<f32>,
};

struct SnailDualSourceOut
{
    @location(0) @blend_src(0) color : vec4<f32>,
    @location(0) @blend_src(1) blend : vec4<f32>,
};

@fragment
fn fragmentDualMain( input : SnailDualSourceIn, @builtin(position) position : vec4<f32>) -> SnailDualSourceOut
{
    var v : SubpixelVaryings_0;
    v.color_2 = input.color;
    v.tint_0 = input.tint;
    v.texcoord_0 = input.texcoord;
    v.banding_3 = input.banding;
    v.glyph_0 = input.glyph;
    var r : SubpixelResult_0 = snailSubpixelFragment_0(v, u_curve_tex_0, u_band_tex_0, pc_0.layer_base_0, pc_0.subpixel_order_0, pc_0.output_srgb_0, pc_0.coverage_exponent_0);
    if(r.discard_fragment_0)
    {
        discard;
    }
    var o : SnailDualSourceOut;
    o.color = r.color_1;
    o.blend = r.blend_0;
    return o;
}
)");
        __intrinsic_asm "1.0";
    default:
        return 1.0;
    }
}
#endif

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
#if defined(SNAIL_TARGET_WGSL)
    // Reachability anchor: the prelude (and with it fragmentDualMain) is
    // only emitted when the interop function is live code. Multiplies by
    // the constant 1.0 the intrinsic expands to.
    o.color *= snailWgslDualSourceInterop();
#endif
    return o;
}
