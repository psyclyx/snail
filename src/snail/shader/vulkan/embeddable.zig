//! Embeddable custom-shader surface for the Vulkan backend.
//!
//! The GL family exposes injectable GLSL *strings* (`snail.shader.glsl.embeddable`)
//! because a GL caller compiles at runtime. On Vulkan a caller compiles GLSL to
//! SPIR-V at *build* time with `glslc`, so the injectable unit is a set of
//! shipped `.glsl` files a caller `#include`s, plus the resource *contract* they
//! must satisfy. This module documents that contract and names the include
//! files. The caller's build compiles its shader against the corresponding
//! include directories.
//!
//! ## Recipe: sample glyph coverage in your own material fragment shader
//!
//! To call `snail_text_sample_premul_linear(vec2 scene_pos)` from your own lit
//! material shader, author a `.frag` that:
//!
//!   1. `#version 450` + `#extension GL_GOOGLE_include_directive : require`.
//!   2. Declares the caller-owned **atlas plane** in set 0:
//!        layout(set=0, binding=0) uniform sampler2DArray  u_curve_tex;
//!        layout(set=0, binding=1) uniform usampler2DArray u_band_tex;
//!      and binds the descriptor set it populated from `AtlasUploadPlanner`.
//!   3. Provides the coverage macros the math expects, e.g.
//!        #define SNAIL_FILL_RULE 1            // font convention: non-zero
//!        #define SNAIL_COVERAGE_EXPONENT 1.0
//!        #define u_layer_base 0               // absolute layer baked into words
//!        #define u_snail_text_glyph_count  <your push/spec constant>
//!        #define SNAIL_TEXT_RECORD_WORDS_PER_GLYPH <words_per_instance>
//!   4. `#include` the shared coverage math (from the gl/glsl include dir):
//!        #include "snail_render_abi.glsl"
//!        #include "snail_coverage_common.glsl"
//!        #include "snail_color_common.glsl"
//!        #include "snail_text_frag_body.glsl"   // evalGlyphCoverage
//!   5. `#include` the **records plane** interface (from the vulkan_glsl dir) —
//!      a caller-owned SSBO in set `RECORDS_SET`, binding `RECORDS_BINDING`:
//!        #include "snail_text_sample.interface.vulkan.glsl"
//!      then the storage-agnostic sampler body:
//!        #include "snail_text_sample_body.glsl"
//!   6. In `main()`, call `snail_text_sample_premul_linear(scene_pos)` and
//!      composite/light the returned premultiplied-linear paint however you like.
//!
//! The caller uploads the emit words (`snail.emit.emit` output) into the set-1
//! SSBO and pushes `u_snail_text_glyph_count = words.len / WORDS_PER_INSTANCE`.

/// Conventional descriptor set for the caller-owned atlas textures.
pub const ATLAS_SET: u32 = 0;
pub const CURVE_BINDING: u32 = 0;
pub const BAND_BINDING: u32 = 1;
pub const LAYER_INFO_BINDING: u32 = 2;
pub const IMAGE_BINDING: u32 = 3;

/// Records plane (caller-owned) — the per-glyph emit words, as a read-only
/// SSBO. Kept in a separate set so the atlas set stays reusable verbatim.
pub const RECORDS_SET: u32 = 1;
pub const RECORDS_BINDING: u32 = 0;

/// Include-file names a caller `#include`s from Snail's source tree.
pub const records_interface_include = "snail_text_sample.interface.vulkan.glsl";
pub const sample_body_include = "snail_text_sample_body.glsl";
pub const coverage_body_include = "snail_text_frag_body.glsl";
