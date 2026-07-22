//! Generated, complete per-target shaders from the native-Slang source
//! (`src/snail/shader/slang/`) — every family, six targets: Vulkan SPIR-V
//! (`spirv`), WGSL (`wgsl`), GLSL 330 (`glsl330`), GLES 300 (`gles300`),
//! D3D11 HLSL SM 5.0 (`hlsl`), and Metal MSL (`msl`; BEST-EFFORT — no
//! Metal compiler exists on the Linux dev/CI hosts, so the MSL artifacts
//! are textually validated only and real validation is deferred to a Mac,
//! see slang/README-notes "Metal stage").
//! The hand-written GLSL fragment catalog (`snail.shader.glsl`) remains
//! available as the behavioral spec and the composition surface for GL hosts.
//!
//! This file is the root of the public `snail-shaders` module. The
//! artifacts are NOT checked in: the build lays this file out next to a
//! `generated/` tree of build-time compiler outputs (one WriteFiles
//! directory in the zig cache; see build/slang_shaders.zig for the
//! per-target flag sets and the semantic traps they avoid), and the
//! `@embedFile`s below read from that tree. Only builds that import the
//! `snail-shaders` module need `slangc` + `spirv-cross` on PATH (the nix
//! shell provides both); `zig build gen-shaders` optionally materializes
//! the artifacts into zig-out/shaders/ for inspection.
//!
//! ## Interface contracts
//!
//! All targets share the 96-byte parameter block of
//! `src/demo/render/vulkan/contract.zig:PushConstants` (mvp @ 0, viewport
//! @ 64, subpixel_order @ 72, output_srgb @ 76, layer_base @ 80,
//! coverage_exponent @ 84, dither_scale @ 88, mask_output @ 92):
//!
//!  - `spirv`: bound as the push-constant range; curve/band textures are
//!    sampled images at set 0, bindings 0/1 (compatible with the existing
//!    COMBINED_IMAGE_SAMPLER descriptor set layout). Entry points are
//!    named `main`.
//!  - `wgsl`: uniform buffer at `@group(2) @binding(0)`; textures at
//!    `@group(0)` bindings 0/1 (the WGSL catalog's binding contract; no
//!    samplers — the text family only `Load`s). Entry points keep their
//!    Slang names: `vertexMain` / `fragmentMain`.
//!  - `glsl330` / `gles300` (SPIRV-Cross-translated): every stage of every
//!    family declares ONE std140 uniform block named
//!    `SnailPushConstants_std140` (identical definition in both stages, so
//!    the linker merges them — bind the single block index to one binding
//!    point backed by a single 96-byte UBO). Texture access goes through
//!    SPIRV-Cross's combined samplers: Load-only textures pair with the
//!    generated dummy sampler (`SPIRV_Cross_Combined<tex>SPIRV_Cross_
//!    DummySampler`), Sample sites with the real one
//!    (`SPIRV_Cross_Combined<tex><sampler>`). Varyings are renamed to the
//!    location-keyed `snail_io<N>` table at generation time (GLSL <4.10
//!    links varyings by name). Vertex inputs keep locations 0..8 of the
//!    instance stream; entry point is `main`.
//!  - `hlsl` (D3D11, SM 5.0 / FXC class — compiles with d3dcompiler_47 and
//!    dxc alike): the parameter block is `cbuffer` register b0; textures
//!    sit on the Vulkan binding numbers as registers t0 curve, t1 band,
//!    t2 layer-info, t3 image array, s0 image sampler (t2 = the records
//!    buffer for text_sample). Vertex-input semantics are `ATTRIB0..8`
//!    (instance-stream locations); entry points keep their Slang names
//!    (`vertexMain` / `fragmentMain`). The subpixel fragment emits
//!    SV_Target0/SV_Target1 — D3D11 dual-source (SRC1 blend factors).
//!  - `msl` (Metal, runtime-compile with `newLibraryWithSource:`): the
//!    parameter block is `constant SnailPushConstants_natural*` at
//!    [[buffer(0)]] — NATURAL (C) layout, byte-identical to the 96-byte
//!    extern struct. Textures land on the Vulkan binding numbers as
//!    [[texture(0)]] curve, [[texture(1)]] band, [[texture(2)]]
//!    layer-info (= the records `texture_buffer<uint>` for text_sample,
//!    which needs MSL 2.1+), [[texture(3)]] image array, [[sampler(0)]]
//!    image sampler. Vertex data arrives via [[stage_in]] with
//!    [[attribute(0..8)]] — the host's MTLVertexDescriptor chooses the
//!    instance buffer index; it must not collide with [[buffer(0)]].
//!    Entry points keep their Slang names ([[vertex]] `vertexMain` /
//!    [[fragment]] `fragmentMain`). Metal clip space is y-up (z [0,1])
//!    and the artifacts flip y in the vertex like the WGSL/HLSL ones:
//!    mvp = ortho(0, w, 0, h). CAVEAT: the subpixel fragment's outputs
//!    are plain MRT [[color(0)]]/[[color(1)]] — slangc's Metal backend
//!    drops [[vk::index(1)]]; rewrite the blend output to
//!    `[[color(0), index(1)]]` before compiling for dual-source use.

pub const Stage = enum { vertex, fragment };

/// GLSL uniform-block name the GL hosts resolve with
/// `glGetUniformBlockIndex`. Both stages of every family declare the same
/// block (SPIRV-Cross names it after the Slang struct + layout suffix), so
/// one lookup covers the program.
pub const glsl_vertex_block_name = "SnailPushConstants_std140";
pub const glsl_fragment_block_name = "SnailPushConstants_std140";

/// GLSL combined-sampler uniform names. SPIRV-Cross fuses each texture
/// with the sampler it is used with: Load-only textures get the generated
/// dummy sampler, Sample sites the real `u_image_sampler`. u_image_tex is
/// both Loaded (GetDimensions/texelFetch) and Sampled, so TWO combined
/// uniforms exist for it — bind both to the image texture unit.
pub const glsl_curve_tex_name = "SPIRV_Cross_Combinedu_curve_texSPIRV_Cross_DummySampler";
pub const glsl_band_tex_name = "SPIRV_Cross_Combinedu_band_texSPIRV_Cross_DummySampler";
pub const glsl_layer_tex_name = "SPIRV_Cross_Combinedu_layer_texSPIRV_Cross_DummySampler";
pub const glsl_image_tex_name = "SPIRV_Cross_Combinedu_image_texSPIRV_Cross_DummySampler";
pub const glsl_image_tex_sampled_name = "SPIRV_Cross_Combinedu_image_texu_image_sampler";
/// The autohint VERTEX stage also reads the layer-info texture; its
/// Load-only combined sampler carries the same name as the fragment's, so
/// the linker merges them (one uniform, one unit).
pub const glsl_vert_layer_tex_name = glsl_layer_tex_name;

/// WGSL entry-point names (native Slang keeps the source names).
pub const wgsl_vertex_entry = "vertexMain";
pub const wgsl_fragment_entry = "fragmentMain";

/// HLSL entry-point names (like WGSL, the Slang function names survive) and
/// the vertex-input semantic prefix: input-layout elements are
/// `ATTRIB0..ATTRIB8`, one per instance-stream location of
/// contract.zig:vertexInputAttributes.
pub const hlsl_vertex_entry = "vertexMain";
pub const hlsl_fragment_entry = "fragmentMain";
pub const hlsl_attrib_semantic = "ATTRIB";

pub fn textGlsl330(comptime stage: Stage) [:0]const u8 {
    return switch (stage) {
        .vertex => @embedFile("generated/glsl330/text.vert.glsl"),
        .fragment => @embedFile("generated/glsl330/text.frag.glsl"),
    };
}

pub fn textGles300(comptime stage: Stage) [:0]const u8 {
    return switch (stage) {
        .vertex => @embedFile("generated/gles300/text.vert.glsl"),
        .fragment => @embedFile("generated/gles300/text.frag.glsl"),
    };
}

pub fn textWgsl(comptime stage: Stage) [:0]const u8 {
    return switch (stage) {
        .vertex => @embedFile("generated/wgsl/text.vert.wgsl"),
        .fragment => @embedFile("generated/wgsl/text.frag.wgsl"),
    };
}

// ── Fragment-only families ──
//
// colr/path (and the other quad families) share the text family's vertex
// stage — identical source, identical stage IO. Pair their fragments with
// `textSpv(.vertex)` / `textWgsl(.vertex)` / `textGlsl330(.vertex)` /
// `textGles300(.vertex)`.

pub fn colrFragGlsl330() [:0]const u8 {
    return @embedFile("generated/glsl330/colr.frag.glsl");
}

pub fn colrFragGles300() [:0]const u8 {
    return @embedFile("generated/gles300/colr.frag.glsl");
}

pub fn colrFragWgsl() [:0]const u8 {
    return @embedFile("generated/wgsl/colr.frag.wgsl");
}

pub fn pathFragGlsl330() [:0]const u8 {
    return @embedFile("generated/glsl330/path.frag.glsl");
}

pub fn pathFragGles300() [:0]const u8 {
    return @embedFile("generated/gles300/path.frag.glsl");
}

pub fn pathFragWgsl() [:0]const u8 {
    return @embedFile("generated/wgsl/path.frag.wgsl");
}

pub fn ttHintedFragGlsl330() [:0]const u8 {
    return @embedFile("generated/glsl330/tt_hinted_text.frag.glsl");
}

pub fn ttHintedFragGles300() [:0]const u8 {
    return @embedFile("generated/gles300/tt_hinted_text.frag.glsl");
}

pub fn ttHintedFragWgsl() [:0]const u8 {
    return @embedFile("generated/wgsl/tt_hinted_text.frag.wgsl");
}

// ── LCD subpixel (dual-source; desktop GL + Vulkan only) ──
//
// No GLES artifact: ES 3.0 has no dual-source blending. A WGSL artifact
// is generated (generated/wgsl/text_subpixel.frag.wgsl; its dual-source
// entry is `fragmentDualMain`, injected via the __requirePrelude interop
// in the family source) but not exposed here: it depends on slang's name
// mangling, so it stays a regeneration-time artifact until slang lowers
// [[vk::index(1)]] to @blend_src natively. See slang/README-notes.

pub fn subpixelFragGlsl330() [:0]const u8 {
    return @embedFile("generated/glsl330/text_subpixel.frag.glsl");
}

// ── Linear resolve (GL hosts only: fullscreen seed/encode pass) ──

/// Fragment parameter block: one std140 int (`mode`).
pub const glsl_linear_resolve_block_name = "SnailLinearResolveParams_std140";
/// Combined samplers (SPIRV-Cross fuses each texture with the
/// SamplerState it is sampled through).
pub const glsl_linear_resolve_linear_tex_name = "SPIRV_Cross_Combinedu_linear_texu_linear_sampler";
pub const glsl_linear_resolve_dst_tex_name = "SPIRV_Cross_Combinedu_dst_texu_dst_sampler";

pub fn linearResolveGlsl330(comptime stage: Stage) [:0]const u8 {
    return switch (stage) {
        .vertex => @embedFile("generated/glsl330/linear_resolve.vert.glsl"),
        .fragment => @embedFile("generated/glsl330/linear_resolve.frag.glsl"),
    };
}

pub fn linearResolveGles300(comptime stage: Stage) [:0]const u8 {
    return switch (stage) {
        .vertex => @embedFile("generated/gles300/linear_resolve.vert.glsl"),
        .fragment => @embedFile("generated/gles300/linear_resolve.frag.glsl"),
    };
}

// ── Text-as-material sampler (canonical artifacts for every target; the
// game's material shader — the one shipped consumer — is its own Slang
// family importing the same text_sample module, see
// src/demo/game/slang/game_material.slang) ──
//
// The desktop GL dialect exists since the SPIRV-Cross leg (naga's SPIR-V
// front end rejected the texel buffer): the record buffer stays a plain
// `usamplerBuffer u_snail_text_records`, the parameter block is
// `SnailTextSampleParams_std140`. The GLES 3.0 dialect compiles with
// -DSNAIL_TARGET_GLES: texel buffers are ES 3.1+ (GL_EXT_texture_buffer
// itself requires ES 3.1), so the emit words bind as a 2D R32UI texture
// addressed row-major at a fixed width of 1024 texels (the combined
// sampler carries the SPIRV-Cross dummy-sampler name).

pub const glsl_text_sample_block_name = "SnailTextSampleParams_std140";
pub const glsl_text_sample_records_name = "u_snail_text_records";
pub const gles_text_sample_records_name = "SPIRV_Cross_Combinedu_snail_text_recordsSPIRV_Cross_DummySampler";
/// Row width (in u32 texels) of the GLES R32UI records texture; must match
/// SNAIL_TEXT_RECORDS_TEX_WIDTH in the Slang source.
pub const gles_text_sample_records_width = 1024;

pub fn textSampleFragWgsl() [:0]const u8 {
    return @embedFile("generated/wgsl/text_sample.frag.wgsl");
}

pub fn textSampleFragGlsl330() [:0]const u8 {
    return @embedFile("generated/glsl330/text_sample.frag.glsl");
}

pub fn textSampleFragGles300() [:0]const u8 {
    return @embedFile("generated/gles300/text_sample.frag.glsl");
}

// ── Autohint (own vertex stage: the knot fit runs per provoking vertex) ──

pub fn autohintGlsl330(comptime stage: Stage) [:0]const u8 {
    return switch (stage) {
        .vertex => @embedFile("generated/glsl330/autohint.vert.glsl"),
        .fragment => @embedFile("generated/glsl330/autohint.frag.glsl"),
    };
}

pub fn autohintGles300(comptime stage: Stage) [:0]const u8 {
    return switch (stage) {
        .vertex => @embedFile("generated/gles300/autohint.vert.glsl"),
        .fragment => @embedFile("generated/gles300/autohint.frag.glsl"),
    };
}

pub fn autohintWgsl(comptime stage: Stage) [:0]const u8 {
    return switch (stage) {
        .vertex => @embedFile("generated/wgsl/autohint.vert.wgsl"),
        .fragment => @embedFile("generated/wgsl/autohint.frag.wgsl"),
    };
}

// ── D3D11 HLSL (SM 5.0; runtime-compile with d3dcompiler_47 or offline
// with dxc/fxc). Fragment-only families pair with `textHlsl(.vertex)`;
// autohint uses its own vertex stage. ──

pub fn textHlsl(comptime stage: Stage) [:0]const u8 {
    return switch (stage) {
        .vertex => @embedFile("generated/hlsl/text.vert.hlsl"),
        .fragment => @embedFile("generated/hlsl/text.frag.hlsl"),
    };
}

pub fn autohintHlsl(comptime stage: Stage) [:0]const u8 {
    return switch (stage) {
        .vertex => @embedFile("generated/hlsl/autohint.vert.hlsl"),
        .fragment => @embedFile("generated/hlsl/autohint.frag.hlsl"),
    };
}

pub fn colrFragHlsl() [:0]const u8 {
    return @embedFile("generated/hlsl/colr.frag.hlsl");
}

pub fn pathFragHlsl() [:0]const u8 {
    return @embedFile("generated/hlsl/path.frag.hlsl");
}

pub fn ttHintedFragHlsl() [:0]const u8 {
    return @embedFile("generated/hlsl/tt_hinted_text.frag.hlsl");
}

pub fn subpixelFragHlsl() [:0]const u8 {
    return @embedFile("generated/hlsl/text_subpixel.frag.hlsl");
}

pub fn textSampleFragHlsl() [:0]const u8 {
    return @embedFile("generated/hlsl/text_sample.frag.hlsl");
}

// ── Metal MSL (best-effort: generated + textually checked on Linux;
// compile validation deferred to a Mac — see slang/README-notes "Metal
// stage"). Runtime-compile with `newLibraryWithSource:`; fragment-only
// families pair with `textMsl(.vertex)`; autohint uses its own vertex. ──

/// Metal entry-point names (like WGSL/HLSL, the Slang function names
/// survive) — pass to `newFunctionWithName:`.
pub const msl_vertex_entry = "vertexMain";
pub const msl_fragment_entry = "fragmentMain";

pub fn textMsl(comptime stage: Stage) [:0]const u8 {
    return switch (stage) {
        .vertex => @embedFile("generated/msl/text.vert.metal"),
        .fragment => @embedFile("generated/msl/text.frag.metal"),
    };
}

pub fn autohintMsl(comptime stage: Stage) [:0]const u8 {
    return switch (stage) {
        .vertex => @embedFile("generated/msl/autohint.vert.metal"),
        .fragment => @embedFile("generated/msl/autohint.frag.metal"),
    };
}

pub fn colrFragMsl() [:0]const u8 {
    return @embedFile("generated/msl/colr.frag.metal");
}

pub fn pathFragMsl() [:0]const u8 {
    return @embedFile("generated/msl/path.frag.metal");
}

pub fn ttHintedFragMsl() [:0]const u8 {
    return @embedFile("generated/msl/tt_hinted_text.frag.metal");
}

/// Plain-MRT outputs [[color(0)]]/[[color(1)]] — NOT dual-source as
/// emitted; see the module doc's `msl` caveat.
pub fn subpixelFragMsl() [:0]const u8 {
    return @embedFile("generated/msl/text_subpixel.frag.metal");
}

pub fn textSampleFragMsl() [:0]const u8 {
    return @embedFile("generated/msl/text_sample.frag.metal");
}

const raw_text_vert_spv = @embedFile("generated/spirv/text.vert.spv");
const raw_text_frag_spv = @embedFile("generated/spirv/text.frag.spv");
const aligned_text_vert_spv: [raw_text_vert_spv.len]u8 align(4) = raw_text_vert_spv.*;
const aligned_text_frag_spv: [raw_text_frag_spv.len]u8 align(4) = raw_text_frag_spv.*;
const raw_colr_frag_spv = @embedFile("generated/spirv/colr.frag.spv");
const aligned_colr_frag_spv: [raw_colr_frag_spv.len]u8 align(4) = raw_colr_frag_spv.*;
const raw_path_frag_spv = @embedFile("generated/spirv/path.frag.spv");
const aligned_path_frag_spv: [raw_path_frag_spv.len]u8 align(4) = raw_path_frag_spv.*;
const raw_tt_hinted_frag_spv = @embedFile("generated/spirv/tt_hinted_text.frag.spv");
const aligned_tt_hinted_frag_spv: [raw_tt_hinted_frag_spv.len]u8 align(4) = raw_tt_hinted_frag_spv.*;
const raw_autohint_vert_spv = @embedFile("generated/spirv/autohint.vert.spv");
const aligned_autohint_vert_spv: [raw_autohint_vert_spv.len]u8 align(4) = raw_autohint_vert_spv.*;
const raw_autohint_frag_spv = @embedFile("generated/spirv/autohint.frag.spv");
const aligned_autohint_frag_spv: [raw_autohint_frag_spv.len]u8 align(4) = raw_autohint_frag_spv.*;
const raw_subpixel_frag_spv = @embedFile("generated/spirv/text_subpixel.frag.spv");
const aligned_subpixel_frag_spv: [raw_subpixel_frag_spv.len]u8 align(4) = raw_subpixel_frag_spv.*;
const raw_text_sample_frag_spv = @embedFile("generated/spirv/text_sample.frag.spv");
const aligned_text_sample_frag_spv: [raw_text_sample_frag_spv.len]u8 align(4) = raw_text_sample_frag_spv.*;

/// Vulkan SPIR-V, 4-byte aligned for VkShaderModuleCreateInfo.pCode.
pub fn textSpv(comptime stage: Stage) []align(4) const u8 {
    return switch (stage) {
        .vertex => &aligned_text_vert_spv,
        .fragment => &aligned_text_frag_spv,
    };
}

pub fn colrFragSpv() []align(4) const u8 {
    return &aligned_colr_frag_spv;
}

pub fn pathFragSpv() []align(4) const u8 {
    return &aligned_path_frag_spv;
}

pub fn ttHintedFragSpv() []align(4) const u8 {
    return &aligned_tt_hinted_frag_spv;
}

pub fn autohintSpv(comptime stage: Stage) []align(4) const u8 {
    return switch (stage) {
        .vertex => &aligned_autohint_vert_spv,
        .fragment => &aligned_autohint_frag_spv,
    };
}

pub fn subpixelFragSpv() []align(4) const u8 {
    return &aligned_subpixel_frag_spv;
}

pub fn textSampleFragSpv() []align(4) const u8 {
    return &aligned_text_sample_frag_spv;
}

test "generated artifacts carry the documented interface names" {
    const std = @import("std");
    inline for (.{ textGlsl330(.vertex), textGles300(.vertex) }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_vertex_block_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "void main") != null);
    }
    inline for (.{ textGlsl330(.fragment), textGles300(.fragment) }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_fragment_block_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_curve_tex_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_band_tex_name) != null);
    }
    inline for (.{ colrFragGlsl330(), colrFragGles300(), pathFragGlsl330(), pathFragGles300() }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_fragment_block_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_curve_tex_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_band_tex_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_layer_tex_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_image_tex_name) != null);
    }
    inline for (.{ ttHintedFragGlsl330(), ttHintedFragGles300() }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_fragment_block_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_curve_tex_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_band_tex_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_layer_tex_name) != null);
    }
    inline for (.{ colrFragWgsl(), pathFragWgsl(), ttHintedFragWgsl(), autohintWgsl(.fragment) }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, "fn " ++ wgsl_fragment_entry) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "@group(2) var<uniform>") != null);
    }
    inline for (.{ colrFragSpv(), pathFragSpv(), ttHintedFragSpv(), autohintSpv(.vertex), autohintSpv(.fragment) }) |spv| {
        try std.testing.expect(std.mem.readInt(u32, spv[0..4], .little) == 0x0723_0203);
    }
    // Autohint GL vertex: shared block name, vertex-stage layer sampler,
    // and the raw-VertexIndex load (no BaseVertex/DrawParameters path may
    // survive — GL 4.6-only on desktop, a hard error in ES).
    inline for (.{ autohintGlsl330(.vertex), autohintGles300(.vertex) }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_vertex_block_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_vert_layer_tex_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "BaseVertex") == null);
        try std.testing.expect(std.mem.indexOf(u8, src, "gl_VertexID") != null);
    }
    inline for (.{ autohintGlsl330(.fragment), autohintGles300(.fragment) }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_fragment_block_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_layer_tex_name) != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, autohintWgsl(.vertex), "fn " ++ wgsl_vertex_entry) != null);
    // Subpixel: dual-source output qualifiers must survive to the GL 3.3
    // artifact (SPIRV-Cross leaves the index-0 output implicit — the GL
    // default — and qualifies only the blend output), and the SPIR-V must
    // exist.
    try std.testing.expect(std.mem.indexOf(u8, subpixelFragGlsl330(), "layout(location = 0) out") != null);
    try std.testing.expect(std.mem.indexOf(u8, subpixelFragGlsl330(), "layout(location = 0, index = 1) out") != null);
    try std.testing.expect(std.mem.readInt(u32, subpixelFragSpv()[0..4], .little) == 0x0723_0203);
    // Text-sample canonical artifacts (consumer migration is stage C).
    try std.testing.expect(std.mem.readInt(u32, textSampleFragSpv()[0..4], .little) == 0x0723_0203);
    try std.testing.expect(std.mem.indexOf(u8, textSampleFragWgsl(), "fn " ++ wgsl_fragment_entry) != null);
    // Text-sample desktop GL dialect: the texel buffer must stay a plain
    // named usamplerBuffer (a loader would bind it by name).
    try std.testing.expect(std.mem.indexOf(u8, textSampleFragGlsl330(), "usamplerBuffer " ++ glsl_text_sample_records_name) != null);
    try std.testing.expect(std.mem.indexOf(u8, textSampleFragGlsl330(), glsl_text_sample_block_name) != null);
    // Text-sample GLES dialect: no texel buffer exists in ES 3.0 — the
    // records bind as a 2D R32UI texture through the combined dummy
    // sampler, and the default float precision must be highp.
    try std.testing.expect(std.mem.indexOf(u8, textSampleFragGles300(), "usampler2D " ++ gles_text_sample_records_name) != null);
    try std.testing.expect(std.mem.indexOf(u8, textSampleFragGles300(), glsl_text_sample_block_name) != null);
    try std.testing.expect(std.mem.indexOf(u8, textSampleFragGles300(), "usamplerBuffer") == null);
    try std.testing.expect(std.mem.indexOf(u8, textSampleFragGles300(), "precision highp float;") != null);
    // Linear resolve: block + sampler names must survive.
    inline for (.{ linearResolveGlsl330(.fragment), linearResolveGles300(.fragment) }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_linear_resolve_block_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_linear_resolve_linear_tex_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_linear_resolve_dst_tex_name) != null);
    }
    inline for (.{ linearResolveGlsl330(.vertex), linearResolveGles300(.vertex) }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, "void main") != null);
    }
    // HLSL artifacts: register contract (b0 cbuffer + Vulkan-numbered
    // t registers), entry names, and the ATTRIB vertex-input semantics.
    inline for (.{ textHlsl(.vertex), autohintHlsl(.vertex) }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, "register(b0)") != null);
        try std.testing.expect(std.mem.indexOf(u8, src, hlsl_vertex_entry) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, hlsl_attrib_semantic ++ "0") != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "SV_VertexID") != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "pack_matrix(column_major)") != null);
    }
    // Autohint's vertex-stage layer read keeps the contract register even
    // with curve/band stripped as unused.
    try std.testing.expect(std.mem.indexOf(u8, autohintHlsl(.vertex), "register(t2)") != null);
    inline for (.{ textHlsl(.fragment), autohintHlsl(.fragment), colrFragHlsl(), pathFragHlsl(), ttHintedFragHlsl(), subpixelFragHlsl(), textSampleFragHlsl() }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, "register(b0)") != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "register(t0)") != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "register(t1)") != null);
        try std.testing.expect(std.mem.indexOf(u8, src, hlsl_fragment_entry) != null);
    }
    inline for (.{ colrFragHlsl(), pathFragHlsl() }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, "register(t2)") != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "register(t3)") != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "register(s0)") != null);
    }
    // Subpixel: true D3D11 dual source (SV_Target0/1, SRC1 blend factors).
    try std.testing.expect(std.mem.indexOf(u8, subpixelFragHlsl(), "SV_Target0") != null);
    try std.testing.expect(std.mem.indexOf(u8, subpixelFragHlsl(), "SV_Target1") != null);
    // Text-sample: the records texel buffer is Buffer<uint> at t2.
    try std.testing.expect(std.mem.indexOf(u8, textSampleFragHlsl(), "register(t2)") != null);
    // No absolute build paths may leak into the artifacts
    // (-line-directive-mode none).
    inline for (.{ textHlsl(.vertex), textHlsl(.fragment) }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, "#line") == null);
    }
    // MSL artifacts (best-effort; textual contract only — no Metal
    // compiler on this platform): the b0-analog parameter block at
    // [[buffer(0)]], Vulkan-numbered [[texture(n)]] slots, [[vertex_id]]
    // entries with the ATTRIB-analog [[attribute(n)]] stage_in, Slang
    // entry names, and no #line leakage.
    inline for (.{ textMsl(.vertex), autohintMsl(.vertex) }) |src| {
        try std.testing.expect(std.mem.startsWith(u8, src, "#include <metal_stdlib>"));
        try std.testing.expect(std.mem.indexOf(u8, src, "[[buffer(0)]]") != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "[[vertex]]") != null);
        try std.testing.expect(std.mem.indexOf(u8, src, msl_vertex_entry) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "[[vertex_id]]") != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "[[attribute(0)]]") != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "#line") == null);
    }
    // Autohint's vertex-stage layer read keeps the contract slot even with
    // curve/band stripped as unused.
    try std.testing.expect(std.mem.indexOf(u8, autohintMsl(.vertex), "[[texture(2)]]") != null);
    inline for (.{ textMsl(.fragment), autohintMsl(.fragment), colrFragMsl(), pathFragMsl(), ttHintedFragMsl(), subpixelFragMsl(), textSampleFragMsl() }) |src| {
        try std.testing.expect(std.mem.startsWith(u8, src, "#include <metal_stdlib>"));
        try std.testing.expect(std.mem.indexOf(u8, src, "[[buffer(0)]]") != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "[[fragment]]") != null);
        try std.testing.expect(std.mem.indexOf(u8, src, msl_fragment_entry) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "[[texture(0)]]") != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "[[texture(1)]]") != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "#line") == null);
    }
    inline for (.{ colrFragMsl(), pathFragMsl() }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, "[[texture(2)]]") != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "[[texture(3)]]") != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "[[sampler(0)]]") != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, ttHintedFragMsl(), "[[texture(2)]]") != null);
    // Subpixel: slangc's Metal backend drops [[vk::index(1)]] — the
    // artifact is plain MRT (documented caveat; a dual-source consumer
    // rewrites [[color(1)]] to [[color(0), index(1)]]). This assertion is
    // the tripwire for slang gaining native support.
    try std.testing.expect(std.mem.indexOf(u8, subpixelFragMsl(), "[[color(0)]]") != null);
    try std.testing.expect(std.mem.indexOf(u8, subpixelFragMsl(), "[[color(1)]]") != null);
    try std.testing.expect(std.mem.indexOf(u8, subpixelFragMsl(), "index(1)") == null);
    // Text-sample: the records texel buffer is texture_buffer<uint> on the
    // t2-analog slot (MSL 2.1+).
    try std.testing.expect(std.mem.indexOf(u8, textSampleFragMsl(), "texture_buffer<uint") != null);
    try std.testing.expect(std.mem.indexOf(u8, textSampleFragMsl(), "[[texture(2)]]") != null);
    try std.testing.expect(std.mem.startsWith(u8, textGles300(.fragment), "#version 300 es"));
    // The GLES default float precision must be highp (the es-highp patch;
    // SPIRV-Cross emits mediump and locals inherit the default).
    try std.testing.expect(std.mem.indexOf(u8, textGles300(.fragment), "precision highp float;") != null);
    try std.testing.expect(std.mem.indexOf(u8, textGles300(.fragment), "precision mediump float;") == null);
    try std.testing.expect(std.mem.startsWith(u8, textGlsl330(.fragment), "#version 330"));
    try std.testing.expect(std.mem.indexOf(u8, textWgsl(.vertex), "fn " ++ wgsl_vertex_entry) != null);
    try std.testing.expect(std.mem.indexOf(u8, textWgsl(.fragment), "fn " ++ wgsl_fragment_entry) != null);
    try std.testing.expect(std.mem.indexOf(u8, textWgsl(.fragment), "@group(2) var<uniform>") != null);
    // SPIR-V magic.
    inline for (.{ textSpv(.vertex), textSpv(.fragment) }) |spv| {
        try std.testing.expect(std.mem.readInt(u32, spv[0..4], .little) == 0x0723_0203);
    }
}
