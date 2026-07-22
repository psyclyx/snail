// Painted family (path + COLR): native-Slang single source for all four GPU
// targets. The two families share one body (snail_path_frag_body.glsl is the
// spec); the expected special-instance kind — COLR (0) vs PATH (1) — is
// selected at compile time with -DSNAIL_FAMILY_COLR (path is the default),
// mirroring how the GLSL catalog composes snail_colr_frag_body.glsl on top
// of the path body.
//
// Per-target compile flags match families/text.slang (see
// build/slang_shaders.zig). The vertex is the same raw-VertexIndex
// spirv_asm body as the text family's — both families pair with the text
// vertex artifacts on every target.
//
// ── Resource bindings ──
//
// Same descriptor contract as the composed catalog (contract.zig):
// binding 0 curve tex, 1 band tex, 2 layer-info tex, 3 image array. The
// image paint SAMPLES binding 3 (linear filter), so:
//  - Vulkan: `u_image_tex` (sampled image) and `u_image_sampler` share
//    binding 3 — spec-legal aliasing of one COMBINED_IMAGE_SAMPLER
//    descriptor by an image-only and a sampler-only variable.
//  - WGSL: the sampler lives at @group(1) @binding(3), the catalog's
//    split-sampler contract (filtering sampler slot).
//  - GL: no explicit bindings; slangc fuses Texture+SamplerState back into
//    a combined sampler and the generated names are recorded in
//    snail.shader.generated.
module painted;

import render_abi;
import color_common;
import coverage_common;
import path_body;
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
[[vk::binding(2, 0)]] Texture2D<float4> u_layer_tex;
[[vk::binding(3, 0)]] Texture2DArray<float4> u_image_tex;
[[vk::binding(3, 0)]] SamplerState u_image_sampler;
#elif defined(SNAIL_TARGET_WGSL)
[[vk::binding(0, 2)]] ConstantBuffer<SnailPushConstants> pc;
[[vk::binding(0, 0)]] Texture2DArray<float4> u_curve_tex;
[[vk::binding(1, 0)]] Texture2DArray<uint2> u_band_tex;
[[vk::binding(2, 0)]] Texture2D<float4> u_layer_tex;
[[vk::binding(3, 0)]] Texture2DArray<float4> u_image_tex;
[[vk::binding(3, 1)]] SamplerState u_image_sampler;
#else // GL family (desktop GLSL 330 / GLES 300 es)
ConstantBuffer<SnailPushConstants> pc;
Texture2DArray<float4> u_curve_tex;
Texture2DArray<uint2> u_band_tex;
Texture2D<float4> u_layer_tex;
Texture2DArray<float4> u_image_tex;
SamplerState u_image_sampler;
#endif

struct VsInput {
    [[vk::location(0)]] float4 rect;
    [[vk::location(1)]] float4 xform;
    [[vk::location(2)]] float2 origin;
    [[vk::location(3)]] uint2 glyph;
    [[vk::location(4)]] float4 bnd;
    [[vk::location(5)]] float4 col;
    [[vk::location(6)]] float4 tint;
};

struct VsOutput {
    float4 position : SV_Position;
    [[vk::location(0)]] float4 color;
    [[vk::location(1)]] float2 texcoord;
    [[vk::location(2)]] nointerpolation float4 banding;
    [[vk::location(3)]] nointerpolation int4 glyph;
    [[vk::location(4)]] float4 tint;
};

// Raw-VertexIndex loading: same trap and same workaround as
// families/text.slang (SV_VertexID is D3D-semantics on SPIR-V targets).
#if defined(SNAIL_TARGET_WGSL)
[shader("vertex")]
VsOutput vertexMain(VsInput input, uint vertex_index: SV_VertexID) {
    VsOutput o = vertexBody(input, vertex_index);
    // WGSL clip space is y-up; flip like families/text.slang.
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
    v.bnd = input.bnd;
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

#if defined(SNAIL_FAMILY_COLR)
static const int kExpectedSpecialKind = SNAIL_SPECIAL_KIND_COLR;
#else
static const int kExpectedSpecialKind = SNAIL_SPECIAL_KIND_PATH;
#endif

[shader("fragment")]
float4 fragmentMain(VsOutput input) : SV_Target {
    PaintedVaryings v;
    v.tint = input.tint;
    v.texcoord = input.texcoord;
    v.banding = input.banding;
    v.glyph = input.glyph;
    PaintedParams p;
    p.layer_base = pc.layer_base;
    p.output_srgb = pc.output_srgb;
    p.coverage_exponent = pc.coverage_exponent;
    p.dither_scale = pc.dither_scale;
    p.mask_output = pc.mask_output;
    return snailPaintedFragment(kExpectedSpecialKind, v, input.position.xy,
                                u_curve_tex, u_band_tex, u_layer_tex,
                                u_image_tex, u_image_sampler, p);
}
