// Regular-text family: native-Slang single source for all four GPU targets.
//
// Entry points: vertexMain / fragmentMain ([shader(...)] attributes).
// The math lives in the imported modules; this file owns only the
// per-target resource bindings and the stage IO contract.
//
// ── Per-target compile (see build/slang_shaders.zig for the maintainer
//    step `gen-shaders`; flags recorded there are the source of truth) ──
//
//  - Vulkan SPIR-V:  -DSNAIL_TARGET_VULKAN -target spirv -profile spirv_1_3
//                    -default-image-format-unknown
//  - WGSL (direct):  -DSNAIL_TARGET_WGSL -target wgsl
//  - GLSL 330 / GLES 300 es: -DSNAIL_TARGET_GL -target spirv (vertex:
//    direct; fragment: -emit-spirv-via-glsl — loop-structure trap), then
//    naga --keep-coordinate-space --profile {core330,es300}. slangc's own
//    `-target glsl` emits Vulkan-flavor GLSL only and cannot feed a real
//    OpenGL context.
//
// ── Stage IO contract ──
//
// Vertex inputs mirror contract.zig:vertexInputAttributes locations 0..6.
// The text family bitcasts the shared payload into its band transform. Varyings keep the
// Vulkan GLSL wrapper's locations: 0 color, 1 texcoord, 2 banding (flat),
// 3 glyph (flat), 4 tint.
//
// ── Uniform block ──
//
// `SnailPushConstants` matches the 96-byte layout of
// src/demo/render/vulkan/contract.zig:PushConstants exactly (mvp @ 0,
// viewport @ 64, subpixel_order @ 72, output_srgb @ 76, layer_base @ 80,
// coverage_exponent @ 84, dither_scale @ 88, mask_output @ 92; std140 and
// std430 agree on all of them). Vulkan binds it as the push-constant
// range; WGSL as a uniform buffer at @group(2) @binding(0) (the catalog's
// binding contract); GL as a named uniform block.
module text;

import render_abi;
import color_common;
import coverage_common;
import text_coverage;
import text_main;
import vertex;

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
#else // GL family (desktop GLSL 330 / GLES 300 es), D3D11 HLSL (registers b0/t0..t3/s0 in declaration order), and Metal MSL ([[buffer(0)]] / [[texture(0..3)]] / [[sampler(0)]], same declaration order)
ConstantBuffer<SnailPushConstants> pc;
Texture2DArray<float4> u_curve_tex;
Texture2DArray<uint2> u_band_tex;
#endif

struct VsInput {
    [[vk::location(0)]] float4 rect : ATTRIB0;
    [[vk::location(1)]] float4 xform : ATTRIB1;
    [[vk::location(2)]] float2 origin : ATTRIB2;
    [[vk::location(3)]] uint2 glyph : ATTRIB3;
    [[vk::location(4)]] uint4 payload : ATTRIB4;
    [[vk::location(5)]] float4 col : ATTRIB5;
    [[vk::location(6)]] float4 tint : ATTRIB6;
};

struct VsOutput {
    float4 position : SV_Position;
    [[vk::location(0)]] float4 color : TEXCOORD0;
    [[vk::location(1)]] float2 texcoord : TEXCOORD1;
    [[vk::location(2)]] nointerpolation float4 banding : TEXCOORD2;
    [[vk::location(3)]] nointerpolation int4 glyph : TEXCOORD3;
    [[vk::location(4)]] float4 tint : TEXCOORD4;
};

// ── Vertex index ──
//
// `SV_VertexID` is a semantic trap on SPIR-V targets: Slang lowers it to
// `VertexIndex - BaseVertex` (D3D semantics), which drags in the
// DrawParameters capability — a Vulkan device *feature* the demo devices do
// not enable — and translates to `gl_BaseVertex` in naga's GLSL backends,
// which does not exist in GLSL 330 / GLES 300. The raw SPIR-V VertexIndex
// builtin (identical for our base-vertex-0 quad draws) is loaded through
// inline SPIR-V instead. WGSL's @builtin(vertex_index) is already raw, so
// the WGSL target keeps SV_VertexID — and on the D3D11 HLSL and Metal MSL
// targets SV_VertexID is simply the native semantic ([[vertex_id]] in MSL;
// spirv_asm cannot compile on either: "unexpected IR opcode during code
// emit").
#if defined(SNAIL_TARGET_WGSL) || defined(SNAIL_TARGET_D3D11) || defined(SNAIL_TARGET_METAL)
[shader("vertex")]
VsOutput vertexMain(VsInput input, uint vertex_index: SV_VertexID) {
    VsOutput o = vertexBody(input, vertex_index);
    // WebGPU, D3D11, and Metal clip spaces are y-up while the CPU-side mvp
    // follows the Vulkan y-down convention (shared with every other
    // target). The old WGSL catalog got this flip injected by naga's
    // SPIR-V front end; slangc's direct WGSL/HLSL/MSL backends perform no
    // coordinate-space conversion (and `-fvk-invert-y` is a no-op for
    // them), so flip here.
    o.position.y = -o.position.y;
    return o;
}
#else
int snailRawVertexIndex() {
    return spirv_asm {
        result:$$int = OpLoad builtin(VertexIndex:int);
    };
}

[shader("vertex")]
VsOutput vertexMain(VsInput input) {
    return vertexBody(input, uint(snailRawVertexIndex()));
}
#endif

VsOutput vertexBody(VsInput input, uint vertex_index) {
    TextVertexIn v;
    v.rect = input.rect;
    v.xform = input.xform;
    v.origin = input.origin;
    v.glyph = input.glyph;
    v.payload = input.payload;
    v.col = input.col;
    v.tint = input.tint;

    TextVertexResult r = snailTextVertex(v, vertex_index, pc.mvp, pc.viewport, pc.subpixel_order);

    VsOutput o;
    o.position = r.position;
    o.color = r.color;
    o.texcoord = r.texcoord;
    o.banding = r.banding;
    o.glyph = r.glyph;
    o.tint = r.tint;
    return o;
}

[shader("fragment")]
float4 fragmentMain(VsOutput input) : SV_Target {
    TextVaryings v;
    v.color = input.color;
    v.tint = input.tint;
    v.texcoord = input.texcoord;
    v.banding = input.banding;
    v.glyph = input.glyph;
    return snailTextFragment(v, u_curve_tex, u_band_tex,
                             pc.layer_base, pc.output_srgb,
                             pc.coverage_exponent, pc.mask_output);
}
