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

/// GLSL combined-sampler uniform names.
pub const glsl_curve_tex_name = "_group_0_binding_1_fs";
pub const glsl_band_tex_name = "_group_0_binding_2_fs";

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

const raw_text_vert_spv = @embedFile("generated/spirv/text.vert.spv");
const raw_text_frag_spv = @embedFile("generated/spirv/text.frag.spv");
const aligned_text_vert_spv: [raw_text_vert_spv.len]u8 align(4) = raw_text_vert_spv.*;
const aligned_text_frag_spv: [raw_text_frag_spv.len]u8 align(4) = raw_text_frag_spv.*;

/// Vulkan SPIR-V, 4-byte aligned for VkShaderModuleCreateInfo.pCode.
pub fn textSpv(comptime stage: Stage) []align(4) const u8 {
    return switch (stage) {
        .vertex => &aligned_text_vert_spv,
        .fragment => &aligned_text_frag_spv,
    };
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
