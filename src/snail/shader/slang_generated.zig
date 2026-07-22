//! Generated, complete per-target shaders from the native-Slang source
//! (`src/snail/shader/slang/`). Stage A covers the regular-text family only;
//! the GLSL fragment catalog (`shader.glsl`) remains the source for the
//! other families.
//!
//! These are checked-in artifacts; regenerate with
//!
//!     zig build gen-shaders
//!
//! inside `nix-shell` (needs `slangc` + `naga`; see build/slang_shaders.zig
//! for the per-target flag sets and the semantic traps they avoid).
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
//!  - `glsl330` / `gles300` (naga-translated): std140 uniform blocks named
//!    `SnailPushConstants_std140_block_0Vertex` (vertex stage) and
//!    `SnailPushConstants_std140_block_0Fragment` (fragment stage) — bind
//!    both block indices to one binding point backed by a single 96-byte
//!    UBO. Combined samplers `_group_0_binding_1_fs` (curve, rgba16f) and
//!    `_group_0_binding_2_fs` (band, rg16ui). Vertex inputs keep locations
//!    0..6 of the instance stream; entry point is `main`.

pub const Stage = enum { vertex, fragment };

/// GLSL uniform-block names the GL hosts resolve with
/// `glGetUniformBlockIndex` (one per stage; both wrap the same 96 bytes).
/// The names differ because the two stages take different SPIR-V legs
/// (vertex: slang-direct; fragment: -emit-spirv-via-glsl — see
/// build/slang_shaders.zig for why).
pub const glsl_vertex_block_name = "SnailPushConstants_std140_block_0Vertex";
pub const glsl_fragment_block_name = "block_SnailPushConstants_0_block_0Fragment";

/// Vertex-stage block name for via-glsl vertex legs (autohint: its fitter
/// loops force the vertex through -emit-spirv-via-glsl, and the glslang leg
/// names the struct differently from the slang-direct leg above). GL hosts
/// resolve whichever of the two the program declares.
pub const glsl_via_vertex_block_name = "block_SnailPushConstants_0_block_0Vertex";

/// GLSL combined-sampler uniform names. The fragment leg's binding numbers
/// are assigned sequentially after the parameter block (binding 0), so
/// curve/band land on 1/2 in every family; the paint-record families
/// additionally get layer-info at 3 and the image array at 4 (slangc fuses
/// the image Texture+SamplerState pair back into one combined sampler).
pub const glsl_curve_tex_name = "_group_0_binding_1_fs";
pub const glsl_band_tex_name = "_group_0_binding_2_fs";
pub const glsl_layer_tex_name = "_group_0_binding_3_fs";
pub const glsl_image_tex_name = "_group_0_binding_4_fs";
/// The autohint VERTEX stage also samples the layer-info texture; its
/// combined sampler gets the vertex-stage suffix.
pub const glsl_vert_layer_tex_name = "_group_0_binding_3_vs";

/// WGSL entry-point names (native Slang keeps the source names).
pub const wgsl_vertex_entry = "vertexMain";
pub const wgsl_fragment_entry = "fragmentMain";

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

// ── Fragment-only families (stage B) ──
//
// colr/path (and the other quad families) share the text family's vertex
// stage — identical source, identical stage IO. On Vulkan/WGSL hosts pair
// their fragments with `textSpv(.vertex)` / `textWgsl(.vertex)`. The GL
// dialects instead pair them with `paintedVertGlsl330/Gles300` — the same
// vertex compiled at -O0 so the sRGB-decode divisions survive verbatim
// (the GL baseline is the raw-GLSL catalog; see build/slang_shaders.zig
// `gl_o0`).

pub fn paintedVertGlsl330() [:0]const u8 {
    return @embedFile("generated/glsl330/painted.vert.glsl");
}

pub fn paintedVertGles300() [:0]const u8 {
    return @embedFile("generated/gles300/painted.vert.glsl");
}

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
// No WGSL artifact: slangc's WGSL backend drops [[vk::index(1)]] (no
// @blend_src), so the wgpu path keeps the old catalog. No GLES artifact:
// ES 3.0 has no dual-source blending.

pub fn subpixelFragGlsl330() [:0]const u8 {
    return @embedFile("generated/glsl330/text_subpixel.frag.glsl");
}

// ── Linear resolve (GL hosts only: fullscreen seed/encode pass) ──

/// Fragment parameter block: one std140 int (`mode`).
pub const glsl_linear_resolve_block_name = "SnailLinearResolveParams_std140_block_0Fragment";
/// Combined samplers (naga names them by the TEXTURE's binding slot; each
/// texture is followed by its SamplerState in the family file).
pub const glsl_linear_resolve_linear_tex_name = "_group_0_binding_1_fs";
pub const glsl_linear_resolve_dst_tex_name = "_group_0_binding_3_fs";

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

// ── Text-as-material sampler (canonical artifacts; consumer migration is
// stage C — the game keeps composing the GLSL catalog) ──
//
// No GL artifacts: naga's SPIR-V front end rejects texel buffers, and the
// GL consumer composes GLSL directly anyway.

pub fn textSampleFragWgsl() [:0]const u8 {
    return @embedFile("generated/wgsl/text_sample.frag.wgsl");
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
    inline for (.{ textGlsl330(.vertex), textGles300(.vertex), paintedVertGlsl330(), paintedVertGles300() }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_vertex_block_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "void main") != null);
    }
    // The painted vertex exists for exact division semantics on GL; the
    // strength-reduced reciprocal constants must not reappear.
    inline for (.{ paintedVertGlsl330(), paintedVertGles300() }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, "0.94786") == null);
        try std.testing.expect(std.mem.indexOf(u8, src, "0.077399") == null);
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
    // Autohint GL vertex: via-glsl block name, vertex-stage layer sampler,
    // and the base-vertex patch (no GL 4.6 builtin may survive).
    inline for (.{ autohintGlsl330(.vertex), autohintGles300(.vertex) }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_via_vertex_block_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_vert_layer_tex_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, "uint(gl_BaseVertex)") == null);
    }
    inline for (.{ autohintGlsl330(.fragment), autohintGles300(.fragment) }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_fragment_block_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_layer_tex_name) != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, autohintWgsl(.vertex), "fn " ++ wgsl_vertex_entry) != null);
    // Subpixel: dual-source output qualifiers must survive to the GL 3.3
    // artifact, and the SPIR-V must exist.
    try std.testing.expect(std.mem.indexOf(u8, subpixelFragGlsl330(), "layout(location = 0, index = 0) out") != null);
    try std.testing.expect(std.mem.indexOf(u8, subpixelFragGlsl330(), "layout(location = 0, index = 1) out") != null);
    try std.testing.expect(std.mem.readInt(u32, subpixelFragSpv()[0..4], .little) == 0x0723_0203);
    // Text-sample canonical artifacts (consumer migration is stage C).
    try std.testing.expect(std.mem.readInt(u32, textSampleFragSpv()[0..4], .little) == 0x0723_0203);
    try std.testing.expect(std.mem.indexOf(u8, textSampleFragWgsl(), "fn " ++ wgsl_fragment_entry) != null);
    // Linear resolve: block + sampler names must survive.
    inline for (.{ linearResolveGlsl330(.fragment), linearResolveGles300(.fragment) }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_linear_resolve_block_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_linear_resolve_linear_tex_name) != null);
        try std.testing.expect(std.mem.indexOf(u8, src, glsl_linear_resolve_dst_tex_name) != null);
    }
    inline for (.{ linearResolveGlsl330(.vertex), linearResolveGles300(.vertex) }) |src| {
        try std.testing.expect(std.mem.indexOf(u8, src, "void main") != null);
    }
    try std.testing.expect(std.mem.startsWith(u8, textGles300(.fragment), "#version 300 es"));
    try std.testing.expect(std.mem.startsWith(u8, textGlsl330(.fragment), "#version 330 core"));
    try std.testing.expect(std.mem.indexOf(u8, textWgsl(.vertex), "fn " ++ wgsl_vertex_entry) != null);
    try std.testing.expect(std.mem.indexOf(u8, textWgsl(.fragment), "fn " ++ wgsl_fragment_entry) != null);
    try std.testing.expect(std.mem.indexOf(u8, textWgsl(.fragment), "@group(2) var<uniform>") != null);
    // SPIR-V magic.
    inline for (.{ textSpv(.vertex), textSpv(.fragment) }) |spv| {
        try std.testing.expect(std.mem.readInt(u32, spv[0..4], .little) == 0x0723_0203);
    }
}
