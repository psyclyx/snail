//! Complete GL/GLES stages used by the reference renderer. The structured
//! shipping programs come from `snail.shader.glsl.programs`; native-Slang
//! translations remain here as a portability/regression comparison.

const glsl = @import("snail").shader.glsl;
const slang_gen = @import("snail_shaders");

pub const Gl330 = struct {
    const complete = glsl.programs.Gl330;

    pub const vertex_shader = complete.vertex;
    pub const vertex_shader_autohint = complete.autohint_vertex;
    pub const fragment_shader_text = complete.text_fragment;
    pub const fragment_shader_colr = complete.painted_fragment;
    pub const fragment_shader_path = complete.painted_fragment;
    pub const fragment_shader_tt_hinted_text = complete.hinted_fragment;
    pub const fragment_shader_autohint = complete.autohint_fragment;
    pub const fragment_shader_text_subpixel_dual = complete.subpixel_fragment;
    pub const fragment_shader_tt_hinted_subpixel_dual = complete.hinted_subpixel_fragment;
    pub const fragment_shader_autohint_subpixel_dual = complete.autohint_subpixel_fragment;
    pub const linear_resolve_vertex_shader = complete.linear_resolve_vertex;
    pub const linear_resolve_fragment_shader = complete.linear_resolve_fragment;

    // Native-Slang generated families: complete shaders, UBO parameter
    // block instead of loose uniforms. See `snail_shaders`
    // for the interface contract. The fragment-only families pair with
    // `native_text_vertex_shader` (shared stage IO).
    pub const native_text_vertex_shader = slang_gen.textGlsl330(.vertex);
    pub const native_text_fragment_shader = slang_gen.textGlsl330(.fragment);
    pub const native_colr_fragment_shader = slang_gen.colrFragGlsl330();
    pub const native_path_fragment_shader = slang_gen.pathFragGlsl330();
    pub const native_tt_hinted_fragment_shader = slang_gen.ttHintedFragGlsl330();
    pub const native_autohint_vertex_shader = slang_gen.autohintGlsl330(.vertex);
    pub const native_autohint_fragment_shader = slang_gen.autohintGlsl330(.fragment);
    pub const native_subpixel_fragment_shader = slang_gen.subpixelFragGlsl330();
    pub const native_tt_hinted_subpixel_fragment_shader = slang_gen.ttHintedSubpixelFragGlsl330();
    pub const native_autohint_subpixel_fragment_shader = slang_gen.autohintSubpixelFragGlsl330();
    pub const native_linear_resolve_vertex_shader = slang_gen.linearResolveGlsl330(.vertex);
    pub const native_linear_resolve_fragment_shader = slang_gen.linearResolveGlsl330(.fragment);
};

pub const Gles30 = struct {
    const complete = glsl.programs.Gles300;

    pub const vertex_shader = complete.vertex;
    pub const vertex_shader_autohint = complete.autohint_vertex;
    pub const fragment_shader_text = complete.text_fragment;
    pub const fragment_shader_colr = complete.painted_fragment;
    pub const fragment_shader_path = complete.painted_fragment;
    pub const fragment_shader_tt_hinted_text = complete.hinted_fragment;
    pub const fragment_shader_autohint = complete.autohint_fragment;
    pub const fragment_shader_text_subpixel_dual = "";
    pub const linear_resolve_vertex_shader = complete.linear_resolve_vertex;
    pub const linear_resolve_fragment_shader = complete.linear_resolve_fragment;

    // Native-Slang generated families; see Gl330 above.
    pub const native_text_vertex_shader = slang_gen.textGles300(.vertex);
    pub const native_text_fragment_shader = slang_gen.textGles300(.fragment);
    pub const native_colr_fragment_shader = slang_gen.colrFragGles300();
    pub const native_path_fragment_shader = slang_gen.pathFragGles300();
    pub const native_tt_hinted_fragment_shader = slang_gen.ttHintedFragGles300();
    pub const native_autohint_vertex_shader = slang_gen.autohintGles300(.vertex);
    pub const native_autohint_fragment_shader = slang_gen.autohintGles300(.fragment);
    pub const native_linear_resolve_vertex_shader = slang_gen.linearResolveGles300(.vertex);
    pub const native_linear_resolve_fragment_shader = slang_gen.linearResolveGles300(.fragment);
};

test "reference entry points stay outside the library shader surface" {
    const std = @import("std");
    try std.testing.expect(std.mem.indexOf(u8, Gl330.vertex_shader, "void main") != null);
    try std.testing.expect(std.mem.indexOf(u8, Gles30.fragment_shader_path, "void main") != null);
}
