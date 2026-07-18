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
//!   2. Declares the caller-owned **atlas plane** at bindings of its choice:
//!        layout(set=..., binding=...) uniform sampler2DArray  u_curve_tex;
//!        layout(set=..., binding=...) uniform usampler2DArray u_band_tex;
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
//!   5. Defines `SNAIL_RECORDS_SET` and `SNAIL_RECORDS_BINDING`, then
//!      `#include`s the records-plane interface from the vulkan_glsl dir:
//!        #include "snail_text_sample.interface.vulkan.glsl"
//!      then the storage-agnostic sampler body:
//!        #include "snail_text_sample_body.glsl"
//!   6. In `main()`, call `snail_text_sample_premul_linear(scene_pos)` and
//!      composite/light the returned premultiplied-linear paint however you like.
//!
//! The caller uploads the emit words (`snail.emit.emit` output) into the set-1
//! SSBO and pushes `u_snail_text_glyph_count = words.len / WORDS_PER_INSTANCE`.

/// Include-file names a caller `#include`s from Snail's source tree.
pub const records_interface_include = "snail_text_sample.interface.vulkan.glsl";
pub const sample_body_include = "snail_text_sample_body.glsl";
pub const coverage_body_include = "snail_text_frag_body.glsl";
