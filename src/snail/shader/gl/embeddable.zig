//! Embeddable coverage surface for the GL family (GL 3.3 / 4.4 / GLES 3.0).
//!
//! This module contains only renderer-independent constants and reusable GLSL
//! fragments. It creates no GL objects and makes no GL calls.

const std = @import("std");
const WORDS_PER_INSTANCE: usize = @import("../../format/vertex.zig").WORDS_PER_INSTANCE;

const gl_shaders = @import("shaders.zig");
const gles30_shaders = gl_shaders;

// ── Shader sources ──

const text_color_funcs =
    \\vec4 snail_text_color_srgb() {
    \\    return v_color;
    \\}
    \\
    \\vec4 snail_text_color_linear() {
    \\    return vec4(srgbDecode(v_color.r), srgbDecode(v_color.g), srgbDecode(v_color.b), v_color.a);
    \\}
    \\
    \\float snail_text_coverage() {
    \\    int layer_byte = (v_glyph.w >> 8) & 0xFF;
    \\    if (layer_byte == SNAIL_SPECIAL_LAYER_SENTINEL) return 0.0;
    \\    int atlas_layer = u_layer_base + layer_byte;
    \\    vec2 rc = v_texcoord;
    \\    vec2 epp = fwidth(rc);
    \\    vec2 ppe = 1.0 / max(epp, vec2(1.0 / 65536.0));
    \\    return evalGlyphCoverage(rc, epp, ppe, v_glyph.xy,
    \\                             ivec2(v_glyph.w & 0xFF, v_glyph.z),
    \\                             v_banding, atlas_layer);
    \\}
    \\
;

const resource_interface_glsl =
    \\uniform sampler2DArray u_curve_tex;
    \\uniform usampler2DArray u_band_tex;
    \\uniform int u_fill_rule;
    \\uniform int u_layer_base;
    \\
    \\#define SNAIL_FILL_RULE u_fill_rule
    \\
;

const TEXT_WORDS_PER_GLYPH_PRELUDE = std.fmt.comptimePrint(
    "#define SNAIL_TEXT_RECORD_WORDS_PER_GLYPH {d}\n",
    .{WORDS_PER_INSTANCE},
);

/// GLSL source fragments callers concatenate into their own GL 3.3 / 4.4
/// shaders.
pub const GlShaderSources = struct {
    /// Paste into a vertex shader that wants the standard snail per-
    /// instance attributes (the same `vertex.Instance` layout the snail
    /// draw path uses).
    pub const vertex_interface = gl_shaders.text_vertex_interface;
    /// Standard vertex implementation. Defines `snailVertex()` but no entry
    /// point; call it (or wrap it) from the application's vertex `main()`.
    pub const vertex_functions = gl_shaders.vertex_functions;
    /// Paste into a fragment shader that draws the prepared coverage
    /// geometry directly (per-fragment varyings from the vertex stage).
    pub const fragment_interface = gl_shaders.text_coverage_fragment_interface;
    /// Full fragment interface used by paths and the two special text record
    /// kinds. Applications can use one interface across all Snail programs.
    pub const render_fragment_interface = gl_shaders.render_fragment_interface;
    /// Paste into a fragment shader that does NOT use snail varyings —
    /// just samples coverage from arbitrary positions (typically when
    /// snail text is "painted onto" some other geometry).
    pub const resource_interface = resource_interface_glsl;
    /// Shared coverage helpers (`evalGlyphCoverage`, fill-rule, sRGB).
    pub const coverage_functions = gl_shaders.text_coverage_fragment_body;
    /// Sample-buffer interface: declares `u_snail_text_records` and
    /// `u_snail_text_glyph_count`.
    pub const sample_interface = gl_shaders.text_sample_interface;
    /// Function bodies for `snail_text_sample_premul_linear(vec2)` and
    /// friends — random-access sampling of the records buffer.
    pub const sample_functions = TEXT_WORDS_PER_GLYPH_PRELUDE ++ gl_shaders.text_sample_body;
    /// Full fragment body: coverage helpers + snail_text_coverage() +
    /// snail_text_color_*(). Paste after `fragment_interface`.
    pub const fragment_body = coverage_functions ++ "\n" ++ text_color_funcs;
    /// Each fragment defines a named Snail function and deliberately omits
    /// `main()`, leaving stage ownership with the application.
    pub const regular_text_functions = gl_shaders.regular_text_functions;
    pub const path_functions = gl_shaders.path_functions;
    pub const hinted_text_functions = gl_shaders.hinted_text_functions;
    pub const autohint_functions = gl_shaders.autohint_functions;
};

/// GLSL source fragments for GLES 3.0.
pub const Gles30ShaderSources = struct {
    pub const vertex_interface = gles30_shaders.text_vertex_interface;
    pub const vertex_functions = gles30_shaders.vertex_functions;
    pub const fragment_interface = gles30_shaders.text_coverage_fragment_interface;
    pub const render_fragment_interface = gles30_shaders.render_fragment_interface;
    pub const resource_interface = resource_interface_glsl;
    pub const coverage_functions = gles30_shaders.text_coverage_fragment_body;
    pub const sample_interface = gles30_shaders.gles30_text_sample_interface;
    pub const sample_functions = TEXT_WORDS_PER_GLYPH_PRELUDE ++ gles30_shaders.text_sample_body;
    pub const fragment_body = coverage_functions ++ "\n" ++ text_color_funcs;
    pub const regular_text_functions = gles30_shaders.regular_text_functions;
    pub const path_functions = gles30_shaders.path_functions;
    pub const hinted_text_functions = gles30_shaders.hinted_text_functions;
    pub const autohint_functions = gles30_shaders.autohint_functions;
};

/// Width (in texels) of the 2D `GL_R32UI` texture the GLES 3.0 records plane
/// expects. GLES 3.0 has no buffer textures, so the emit words are uploaded
/// row-major into a 2D texture of this width (height = ceil(word_count / width)).
/// Must match `SNAIL_TEXT_RECORDS_TEX_WIDTH` in
/// `glsl/snail_text_sample.interface.gles30.glsl`.
pub const gles30_records_tex_width: u32 = 1024;

test {
    _ = WORDS_PER_INSTANCE;
}

test "exported fragment helper uses the Slug pixel footprint" {
    try std.testing.expect(std.mem.indexOf(u8, GlShaderSources.fragment_body, "vec2 epp = fwidth(rc);") != null);
    try std.testing.expect(std.mem.indexOf(u8, GlShaderSources.fragment_body, "evalGlyphCoverage(rc, epp, ppe") != null);
    try std.testing.expect(std.mem.indexOf(u8, GlShaderSources.fragment_body, "length(dx)") == null);
}
