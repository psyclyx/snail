//! Complete GL/GLES stages used by the reference renderer, all generated
//! directly from the Slang source modules.

const slang_gen = @import("snail_shaders");

pub const Gl330 = struct {
    pub const vertex_shader = slang_gen.textGlsl330(.vertex);
    pub const vertex_shader_autohint = slang_gen.autohintGlsl330(.vertex);
    pub const fragment_shader_text = slang_gen.flatFragGlsl330(.text);
    pub const fragment_shader_colr = slang_gen.flatFragGlsl330(.colr);
    pub const fragment_shader_path_quadratic = slang_gen.flatFragGlsl330(.path_quadratic);
    pub const fragment_shader_path_conic = slang_gen.flatFragGlsl330(.path_conic);
    pub const fragment_shader_path = slang_gen.flatFragGlsl330(.path);
    pub const fragment_shader_tt_hinted_text = slang_gen.flatFragGlsl330(.tt_hinted_text);
    pub const fragment_shader_autohint = slang_gen.flatFragGlsl330(.autohint);
    pub const fragment_shader_text_subpixel_dual = slang_gen.flatFragGlsl330(.text_subpixel);
    pub const fragment_shader_tt_hinted_subpixel_dual = slang_gen.flatFragGlsl330(.tt_hinted_text_subpixel);
    pub const fragment_shader_autohint_subpixel_dual = slang_gen.flatFragGlsl330(.autohint_subpixel);
    pub const linear_resolve_vertex_shader = slang_gen.linearResolveGlsl330(.vertex);
    pub const linear_resolve_fragment_shader = slang_gen.linearResolveGlsl330(.fragment);
};

pub const Gles30 = struct {
    pub const vertex_shader = slang_gen.textGles300(.vertex);
    pub const vertex_shader_autohint = slang_gen.autohintGles300(.vertex);
    pub const fragment_shader_text = slang_gen.textGles300(.fragment);
    pub const fragment_shader_colr = slang_gen.colrFragGles300();
    pub const fragment_shader_path_quadratic = slang_gen.pathQuadraticFragGles300();
    pub const fragment_shader_path_conic = slang_gen.pathConicFragGles300();
    pub const fragment_shader_path = slang_gen.pathFragGles300();
    pub const fragment_shader_tt_hinted_text = slang_gen.ttHintedFragGles300();
    pub const fragment_shader_autohint = slang_gen.autohintGles300(.fragment);
    pub const fragment_shader_text_subpixel_dual = "";
    pub const linear_resolve_vertex_shader = slang_gen.linearResolveGles300(.vertex);
    pub const linear_resolve_fragment_shader = slang_gen.linearResolveGles300(.fragment);
};

test "reference entry points stay outside the library shader surface" {
    const std = @import("std");
    try std.testing.expect(std.mem.indexOf(u8, Gl330.vertex_shader, "void main") != null);
    try std.testing.expect(std.mem.indexOf(u8, Gles30.fragment_shader_path, "void main") != null);
}
