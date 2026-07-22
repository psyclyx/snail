// Native-Slang game material shader — the stage-C migration of the last
// composed-GLSL consumer. This is the worked example of the embeddable
// composition case: a CALLER-authored material (text carved into a rough,
// lit surface) that imports snail's `text_sample` module and calls
// `snailTextSamplePremulLinearWithFootprint` against its own record
// storage. The GL dialects are generated at build time and wired in as
// anonymous imports (build.zig addGameShaderGl); the demo Vulkan build
// compiles the SPIR-V leg directly (build.zig addGameShaderSpirv).
//
// Ported 1:1 from the retired composed sources (the behavioral spec — every
// literal and operation order preserved):
//   glsl/game_material.vert + gl_material.zig vertex_src   → vertexMain
//   glsl/game_material_body.glsl                            → snailGameMaterial
//   glsl/game_material.frag + gl_material.zig fragment_src → fragmentMain
//
// Per-target record storage (the ISnailTextRecords implementations):
//   Vulkan      read-only SSBO, caller-owned set 1 binding 0
//   desktop GL  R32UI texel buffer (usamplerBuffer)
//   GLES 3.0    2D R32UI texture, row-major at a fixed width (no texel
//               buffers in ES 3.0 — GL_EXT_texture_buffer needs ES 3.1);
//               selected with -DSNAIL_TARGET_GLES on the GLES leg
//
// Parameter block: Vulkan keeps the 120-byte push-constant layout of
// vk_scene.zig:MaterialPush (single premultiplied mvp — two matrices would
// blow the 128-byte push budget). The GL family instead carries view_proj
// and model separately and multiplies in the vertex stage, preserving the
// composed catalog's exact `u_view_proj * (u_model * pos)` arithmetic
// (premultiplying on the CPU would shift clip coordinates by ULPs and move
// every interpolated sample — the AE=0 gate forbids it). GL hosts bind the
// block as the std140 UBO `GameMaterialParams_std140`
// (gl_material.zig:Params mirrors the layout).
module game_material;

import text_sample;

// Record stride in u32 words. Must match snail's packed instance layout
// (snail.render.records.BYTES_PER_INSTANCE / 4; gl_material.zig
// comptime-asserts the value against the library).
static const int SNAIL_TEXT_RECORD_WORDS_PER_GLYPH = 18;

public struct GameMaterialParams {
#if defined(SNAIL_TARGET_VULKAN)
    public float4x4 mvp;
#else
    public float4x4 view_proj;
    public float4x4 model;
#endif
    public float4 base_color;
    public float4 light_dir; // xyz = fixed tangent-space light
    public float2 scene_size;
    public int glyph_count;
    public int output_srgb;
    public float relief;
    public float roughness;
};

#if defined(SNAIL_TARGET_VULKAN)
[[vk::push_constant]] ConstantBuffer<GameMaterialParams> pc;
// snail's atlas plane (set 0) — reuse the device-atlas descriptor set.
[[vk::binding(0, 0)]] Texture2DArray<float4> u_curve_tex;
[[vk::binding(1, 0)]] Texture2DArray<uint2> u_band_tex;
// Caller-owned records SSBO (set 1).
[[vk::binding(0, 1)]] StructuredBuffer<uint> u_snail_text_records;
struct Records : ISnailTextRecords {
    uint word(int linear_index) { return u_snail_text_records[linear_index]; }
};
#elif defined(SNAIL_TARGET_GLES)
ConstantBuffer<GameMaterialParams> pc;
Texture2DArray<float4> u_curve_tex;
Texture2DArray<uint2> u_band_tex;
// GLES 3.0 records storage: emit words in a 2D R32UI texture, addressed
// row-major at a fixed width (the upload side in gl_material.zig pads the
// tail row with zeros at the same width).
Texture2D<uint> u_snail_text_records;
static const int SNAIL_TEXT_RECORDS_TEX_WIDTH = 1024;
struct Records : ISnailTextRecords {
    uint word(int linear_index) {
        return u_snail_text_records.Load(int3(linear_index % SNAIL_TEXT_RECORDS_TEX_WIDTH,
                                              linear_index / SNAIL_TEXT_RECORDS_TEX_WIDTH, 0)).x;
    }
};
#else // Desktop GL: R32UI texel buffer.
ConstantBuffer<GameMaterialParams> pc;
Texture2DArray<float4> u_curve_tex;
Texture2DArray<uint2> u_band_tex;
Buffer<uint> u_snail_text_records;
struct Records : ISnailTextRecords {
    uint word(int linear_index) { return u_snail_text_records[linear_index]; }
};
#endif

float4 snailGameTextSample(float2 scene_pos, float2 scene_dx, float2 scene_dy) {
    Records records;
    return snailTextSamplePremulLinearWithFootprint(
        records, SNAIL_TEXT_RECORD_WORDS_PER_GLYPH, pc.glyph_count,
        0,   // layer_base: emit bakes the absolute atlas layer into each word
        1.0, // coverage exponent: identity transfer
        u_curve_tex, u_band_tex, scene_pos, scene_dx, scene_dy);
}

// Differentiable, material-space roughness. A small set of incommensurate
// waves reads as a hammered surface without the lattice seams hash/value
// noise can expose differently after GL and SPIR-V compilation.
float snailGameHeight(float2 uv) {
    const float tau = 6.28318530718;
    float2 p = uv * tau;
    return 0.50 * sin(dot(p, float2(1.7, 0.6))) +
           0.27 * sin(dot(p, float2(3.9, -2.7)) + 1.3) +
           0.15 * cos(dot(p, float2(7.1, 5.3)) + 0.4) +
           0.08 * sin(dot(p, float2(13.7, -9.1)) + 2.1);
}

/// `uv`        quad UV in [0,1]²
/// `scene_pos` position in snail's text authoring frame (for coverage sampling)
/// `scene_dx/dy` scene-space derivatives computed by the fragment entry point
/// `light_dir` fixed tangent-space light direction
/// `base`      surface base color (linear)
/// `relief`    text emboss strength
/// `roughness` surface bump strength
/// returns premultiplied-linear-ish opaque surface color.
float3 snailGameMaterial(float2 uv, float2 scene_pos, float2 scene_dx, float2 scene_dy,
                         float3 light_dir, float4 base, float relief, float roughness) {
    // Coverage is the text height field. Sample about 1.25 screen pixels to
    // either side so the bevel stays the same apparent width under
    // perspective instead of stretching with the authoring frame.
    float2 scene_pixel = abs(scene_dx) + abs(scene_dy);
    float2 bevel_step = max(scene_pixel * 1.25, float2(1.0 / 65536.0));
    float c   = snailGameTextSample(scene_pos, scene_dx, scene_dy).a;
    float cxp = snailGameTextSample(scene_pos + float2(bevel_step.x, 0.0), scene_dx, scene_dy).a;
    float cxn = snailGameTextSample(scene_pos - float2(bevel_step.x, 0.0), scene_dx, scene_dy).a;
    float cyp = snailGameTextSample(scene_pos + float2(0.0, bevel_step.y), scene_dx, scene_dy).a;
    float cyn = snailGameTextSample(scene_pos - float2(0.0, bevel_step.y), scene_dx, scene_dy).a;

    // A low-frequency, surface-anchored height field. Differentiate it with
    // a small material-space step; a large step turns the normal into
    // unrelated blotches rather than a coherent rough surface.
    float e = 1.0 / 1024.0;
    float h0 = snailGameHeight(uv);
    float hx = snailGameHeight(uv + float2(e, 0.0));
    float hy = snailGameHeight(uv + float2(0.0, e));
    float2 rough_grad = float2(hx - h0, hy - h0) * (roughness / e);

    // Text emboss: the strokes stand proud; their sloped sides tilt the
    // normal.
    float2 relief_grad = float2(cxp - cxn, cyp - cyn) * (0.5 * relief);

    float3 n = normalize(float3(-(rough_grad + relief_grad), 1.0));
    float3 L = normalize(light_dir);
    float diff = max(dot(n, L), 0.0);
    float3 view = float3(0.0, 0.0, 1.0);
    float3 half_v = normalize(L + view);
    float spec = pow(max(dot(n, half_v), 0.0), 40.0);

    // One carved material: dark stone, with the strokes as a slightly
    // brighter, more reflective inlay. Crucially the inlay shares the *same*
    // relief-lit normal `n`, so the letters' shading comes from their bevels
    // catching the fixed light — one side bright, the other in shadow — not
    // from a flat fill.
    float ink = clamp(c, 0.0, 1.0);
    float ao = 0.94 + 0.06 * h0;
    float3 albedo = lerp(base.rgb, float3(0.24, 0.30, 0.40), ink);
    float3 lit = albedo * (0.20 + (0.78 + 0.22 * ink) * diff) * ao
               + float3(0.80, 0.88, 1.0) * spec * (0.12 + 0.28 * ink);
    return lit;
}

float3 snailGameEncodeSrgb(float3 c) {
    c = clamp(c, 0.0, 1.0);
    float3 lo = c * 12.92;
    float3 hi = 1.055 * pow(c, float3(1.0 / 2.4)) - 0.055;
    return lerp(hi, lo, step(c, float3(0.0031308)));
}

struct VsInput {
    [[vk::location(0)]] float3 pos;
    [[vk::location(1)]] float2 uv;
};

struct Varyings {
    float4 position : SV_Position;
    [[vk::location(0)]] float2 uv;
};

[shader("vertex")]
Varyings vertexMain(VsInput input) {
    Varyings o;
    o.uv = input.uv;
#if defined(SNAIL_TARGET_VULKAN)
    o.position = mul(pc.mvp, float4(input.pos, 1.0));
#else
    // GLSL `u_view_proj * u_model * vec4(...)` is left-associative: the
    // composed catalog multiplied the MATRICES first, then the vector.
    // Preserve that exact association (see the parameter-block note in the
    // module docs).
    o.position = mul(mul(pc.view_proj, pc.model), float4(input.pos, 1.0));
#endif
    return o;
}

[shader("fragment")]
float4 fragmentMain(Varyings input) : SV_Target {
    float2 scene_pos = float2(input.uv.x * pc.scene_size.x,
                              (1.0 - input.uv.y) * pc.scene_size.y);
    // Derivatives once, at the top, outside any fragment-dependent glyph
    // control flow (the text_sample module's contract for multi-sample
    // materials).
    float2 scene_dx = ddx(scene_pos);
    float2 scene_dy = ddy(scene_pos);
    float3 lin = snailGameMaterial(input.uv, scene_pos, scene_dx, scene_dy,
                                   pc.light_dir.xyz, pc.base_color, pc.relief, pc.roughness);
    // Windowed GL surfaces want the shader to encode; the Vulkan and
    // offscreen-sRGB targets encode on store and pass output_srgb = 0.
    float3 outc = (pc.output_srgb == 1) ? snailGameEncodeSrgb(lin) : lin;
    return float4(outc, 1.0);
}
