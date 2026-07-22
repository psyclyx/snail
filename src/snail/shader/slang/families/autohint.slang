// Autohint family: native-Slang single source for all four GPU targets.
// Unlike the other quad families this one owns BOTH stages: the vertex
// performs the knot fit (reading the layer-info texture) and hands the
// fragment packed targets through flat varyings.
//
// ── Stage IO contract ──
//
// Vertex inputs are the full instance stream, locations 0..8 (policy words
// 7/8 feed the fit). Varyings mirror the catalog's SNAIL_WGSL variant on
// EVERY target — the two target arrays are scalarized into eight float4
// varyings (WGSL forbids array-typed entry-point IO, and one shape for all
// targets keeps the family single-source): 0 paint, 1 texcoord+layer,
// 2 info (flat), 3/4 policy words (flat), 5..8 x targets (flat),
// 9..12 y targets (flat), 13/14 packed sources (flat).
//
// ── Vertex index ──
//
// Every SPIR-V leg (Vulkan AND the SPIRV-Cross GL dialects) uses the
// spirv_asm raw-VertexIndex load, exactly like families/text.slang:
// SV_VertexID lowers to VertexIndex − BaseVertex (D3D semantics), which
// needs the DrawParameters device feature on Vulkan and is a hard error in
// SPIRV-Cross's ES backend ("BaseVertex not supported in ES profile").
// The naga era compiled this stage -emit-spirv-via-glsl (its fitter loops
// hit naga's structurizer trap, and spirv_asm cannot compile via glsl) and
// patched gl_BaseVertex to 0 in the output; SPIRV-Cross structurizes
// slang's direct loops correctly, so the whole detour is gone. WGSL's
// vertex_index is already raw and keeps SV_VertexID.
module autohint;

import render_abi;
import color_common;
import coverage_common;
import text_coverage;
import vertex;
import autohint_warp;
import autohint_vertex;
import autohint_frag;

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
#else // GL family (desktop GLSL 330 / GLES 300 es)
ConstantBuffer<SnailPushConstants> pc;
Texture2DArray<float4> u_curve_tex;
Texture2DArray<uint2> u_band_tex;
Texture2D<float4> u_layer_tex;
#endif

struct VsInput {
    [[vk::location(0)]] float4 rect;
    [[vk::location(1)]] float4 xform;
    [[vk::location(2)]] float2 origin;
    [[vk::location(3)]] uint2 glyph;
    [[vk::location(4)]] float4 bnd;
    [[vk::location(5)]] float4 col;
    [[vk::location(6)]] float4 tint;
    [[vk::location(7)]] uint4 policy0;
    [[vk::location(8)]] uint3 policy1;
};

struct VsOutput {
    float4 position : SV_Position;
    [[vk::location(0)]] float4 paint;
    [[vk::location(1)]] float3 texcoord_layer;
    [[vk::location(2)]] nointerpolation int2 info;
    [[vk::location(3)]] nointerpolation uint4 policy0;
    [[vk::location(4)]] nointerpolation uint3 policy1;
    [[vk::location(5)]] nointerpolation float4 x_targets0;
    [[vk::location(6)]] nointerpolation float4 x_targets1;
    [[vk::location(7)]] nointerpolation float4 x_targets2;
    [[vk::location(8)]] nointerpolation float4 x_targets3;
    [[vk::location(9)]] nointerpolation float4 y_targets0;
    [[vk::location(10)]] nointerpolation float4 y_targets1;
    [[vk::location(11)]] nointerpolation float4 y_targets2;
    [[vk::location(12)]] nointerpolation float4 y_targets3;
    [[vk::location(13)]] nointerpolation uint4 x_sources;
    [[vk::location(14)]] nointerpolation uint4 y_sources;
};

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

    AutohintVertexResult r = snailAutohintVertex(v, vertex_index, pc.mvp, pc.viewport,
                                                 pc.subpixel_order, input.policy0,
                                                 input.policy1, u_layer_tex);

    VsOutput o;
    o.position = r.position;
    o.paint = r.paint;
    o.texcoord_layer = r.texcoord_layer;
    o.info = r.info;
    o.policy0 = r.policy0;
    o.policy1 = r.policy1;
    o.x_targets0 = r.x_targets[0];
    o.x_targets1 = r.x_targets[1];
    o.x_targets2 = r.x_targets[2];
    o.x_targets3 = r.x_targets[3];
    o.y_targets0 = r.y_targets[0];
    o.y_targets1 = r.y_targets[1];
    o.y_targets2 = r.y_targets[2];
    o.y_targets3 = r.y_targets[3];
    o.x_sources = r.x_sources;
    o.y_sources = r.y_sources;
    return o;
}

[shader("fragment")]
float4 fragmentMain(VsOutput input) : SV_Target {
    AutohintVaryings v;
    v.paint = input.paint;
    v.texcoord_layer = input.texcoord_layer;
    v.info = input.info;
    v.policy0 = input.policy0;
    v.policy1 = input.policy1;
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
    return snailAutohintFragment(v, u_curve_tex, u_band_tex, u_layer_tex,
                                 pc.layer_base, pc.output_srgb,
                                 pc.coverage_exponent, pc.mask_output);
}
