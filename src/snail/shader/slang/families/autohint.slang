// Autohint family: native-Slang single source for all four GPU targets.
// Unlike the other quad families this one owns BOTH stages: the vertex
// performs the knot fit (reading the layer-info texture) and hands the
// fragment packed targets through flat varyings.
//
// ── Stage IO contract ──
//
// Vertex inputs are the compact instance stream, locations 0..6; location 4
// is the autohint policy payload. Varyings mirror the catalog's SNAIL_WGSL variant on
// EVERY target — the two target arrays are scalarized into eight float4
// varyings (WGSL forbids array-typed entry-point IO, and one shape for all
// targets keeps the family single-source): 0 paint, 1 texcoord+layer,
// 2 info (flat), 3 policy (flat), 4..7 x targets (flat),
// 8..11 y targets (flat), 12/13 packed sources (flat).
//
// ── Vertex index ──
//
// Vulkan uses the spirv_asm raw-VertexIndex load, exactly like
// families/text.slang: SV_VertexID lowers to VertexIndex − BaseVertex and
// needs the DrawParameters device feature. Direct GL uses SV_VertexID; the
// dialect normalizer maps Slang's spelling to native gl_VertexID. WGSL's
// vertex_index is already raw.
module autohint;

import resource_types;

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
[[vk::binding(0, 0)]] SnailFloatTexture2DArray u_curve_tex;
[[vk::binding(1, 0)]] SnailUint2Texture2DArray u_band_tex;
[[vk::binding(2, 0)]] SnailFloatTexture2D u_layer_tex;
#elif defined(SNAIL_TARGET_WGSL)
[[vk::binding(0, 2)]] ConstantBuffer<SnailPushConstants> pc;
[[vk::binding(0, 0)]] SnailFloatTexture2DArray u_curve_tex;
[[vk::binding(1, 0)]] SnailUint2Texture2DArray u_band_tex;
[[vk::binding(2, 0)]] SnailFloatTexture2D u_layer_tex;
#else // GL family (desktop GLSL 330 / GLES 300 es), D3D11 HLSL (registers b0/t0..t3/s0 in declaration order), and Metal MSL ([[buffer(0)]] / [[texture(0..3)]] / [[sampler(0)]], same declaration order)
ConstantBuffer<SnailPushConstants> pc;
SnailFloatTexture2DArray u_curve_tex;
SnailUint2Texture2DArray u_band_tex;
SnailFloatTexture2D u_layer_tex;
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

#if defined(SNAIL_TARGET_GL)
[shader("vertex")]
VsOutput vertexMain(VsInput input, uint vertex_index: SV_VertexID) {
    return vertexBody(input, vertex_index);
}
#elif defined(SNAIL_TARGET_WGSL) || defined(SNAIL_TARGET_D3D11) || defined(SNAIL_TARGET_METAL)
[shader("vertex")]
VsOutput vertexMain(VsInput input, uint vertex_index: SV_VertexID) {
    VsOutput o = vertexBody(input, vertex_index);
    // WGSL/D3D11/Metal clip spaces are y-up; flip like families/text.slang.
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

    AutohintVertexResult r = snailAutohintVertex(v, vertex_index, pc.mvp, pc.viewport,
                                                 pc.subpixel_order, input.payload,
                                                 u_layer_tex);

    VsOutput o;
    o.position = r.position;
    o.paint = r.paint;
    o.texcoord_layer = r.texcoord_layer;
    o.info = r.info;
    o.policy = r.policy;
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
    return snailAutohintFragment(v, u_curve_tex, u_band_tex, u_layer_tex,
                                 pc.layer_base, pc.output_srgb,
                                 pc.coverage_exponent, pc.mask_output);
}
