//! Complete GL/GLES shader stages used by the reference renderer. These entry
//! points deliberately live with the demo: the library exports only the
//! reusable, entry-point-free pieces in `snail.shader.glsl`.

const glsl = @import("snail").shader.glsl;
const slang_gen = @import("snail").shader.slang_generated;
const vert_interface = glsl.source(.vertex_interface);
const autohint_vert_interface = glsl.source(.autohint_vertex_interface);
const frag_interface = glsl.source(.render_fragment_interface);
const autohint_frag_interface = glsl.source(.autohint_fragment_interface);
const text_interface = glsl.source(.text_subpixel_interface);
const render_abi = glsl.source(.render_abi);
const vertex_body = glsl.source(.vertex_body);
const coverage_common = glsl.source(.coverage_common);
const color_common = glsl.source(.color_common);
const text_coverage_body = glsl.source(.text_coverage_body);
const text_main = glsl.source(.regular_text_body);
const colr_body = glsl.source(.colr_body);
const path_body = glsl.source(.path_body);
const tt_hinted_body = glsl.source(.tt_hinted_text_body);
const autohint_warp = glsl.source(.autohint_warp);
const autohint_vert_body = glsl.source(.autohint_vertex_body);
const autohint_fast_main = glsl.source(.autohint_fast_body);
const subpixel_body = glsl.source(.text_subpixel_body);
const linear_resolve_body = glsl.source(.linear_resolve_body);

const vertex_entry = "\nvoid main() { snailVertex(); }\n";
const autohint_vertex_entry = "\nvoid main() { snailAutohintVertex(); }\n";
const text_coverage = render_abi ++ "\n" ++ coverage_common ++ "\n" ++ color_common ++ "\n" ++ text_coverage_body;
const text_fragment_body = text_coverage ++ "\n" ++ text_main ++ "\nvoid main() { snailTextFragment(); }\n";
const colr_fragment_body = render_abi ++ "\n" ++ coverage_common ++ "\n" ++ color_common ++ "\n" ++ path_body ++ "\n" ++ colr_body ++ "\nvoid main() { snailColrFragment(); }\n";
const path_fragment_body = render_abi ++ "\n" ++ coverage_common ++ "\n" ++ color_common ++ "\n" ++ path_body ++ "\nvoid main() { snailPathFragment(); }\n";
const hinted_fragment_body = text_coverage ++ "\n" ++ tt_hinted_body ++ "\nvoid main() { snailTtHintedTextFragment(); }\n";
const autohint_fast_fragment_body = text_coverage ++ "\n" ++ autohint_warp ++ "\n" ++ autohint_fast_main ++ "\nvoid main() { snailAutohintFragment(); }\n";
const autohint_vertex_source = autohint_vert_interface ++ "\n" ++ color_common ++ "\n" ++ autohint_warp ++ "\n" ++ vertex_body ++ "\n" ++ autohint_vert_body ++ autohint_vertex_entry;
const subpixel_fragment_body = render_abi ++ "\n" ++ coverage_common ++ "\n" ++ color_common ++ "\n" ++ subpixel_body ++ "\nvoid main() { snailSubpixelFragment(); }\n";

// Fullscreen linear-resolve pass (see snail_linear_resolve_body.glsl for
// the recipe). Vertex stage is the standard bufferless fullscreen triangle;
// the fragment stage dispatches seed vs encode on `u_mode`.
const linear_resolve_vertex_body =
    \\out vec2 v_uv;
    \\void main() {
    \\    vec2 pos = vec2((gl_VertexID == 1) ? 3.0 : -1.0,
    \\                    (gl_VertexID == 2) ? 3.0 : -1.0);
    \\    v_uv = pos * 0.5 + 0.5;
    \\    gl_Position = vec4(pos, 0.0, 1.0);
    \\}
    \\
;
const linear_resolve_fragment_frame =
    \\in vec2 v_uv;
    \\uniform sampler2D u_linear_tex;
    \\uniform sampler2D u_dst_tex;
    \\uniform int u_mode;
    \\out vec4 frag_color;
    \\void main() {
    \\    frag_color = (u_mode == 0)
    \\        ? snailLinearResolveSeed(texture(u_dst_tex, v_uv))
    \\        : snailLinearResolveEncode(texture(u_linear_tex, v_uv));
    \\}
    \\
;
const linear_resolve_fragment_body = color_common ++ "\n" ++ linear_resolve_body ++ "\n" ++ linear_resolve_fragment_frame;

pub const Gl330 = struct {
    const version = "#version 330 core\n\n";

    pub const vertex_shader = version ++ vert_interface ++ "\n" ++ color_common ++ "\n" ++ vertex_body ++ vertex_entry;
    pub const vertex_shader_autohint = version ++ autohint_vertex_source;
    pub const fragment_shader_text = version ++ text_interface ++ "\n" ++ text_fragment_body;
    pub const fragment_shader_colr = version ++ frag_interface ++ "\n" ++ colr_fragment_body;
    pub const fragment_shader_path = version ++ frag_interface ++ "\n" ++ path_fragment_body;
    pub const fragment_shader_tt_hinted_text = version ++ frag_interface ++ "\n" ++ hinted_fragment_body;
    pub const fragment_shader_autohint = version ++ autohint_frag_interface ++ "\n" ++ autohint_fast_fragment_body;
    pub const fragment_shader_text_subpixel_dual = version ++ "#define SNAIL_DUAL_SOURCE 1\n\n" ++ text_interface ++ "\n" ++ subpixel_fragment_body;
    pub const linear_resolve_vertex_shader = version ++ linear_resolve_vertex_body;
    pub const linear_resolve_fragment_shader = version ++ linear_resolve_fragment_body;

    // Native-Slang generated families: complete shaders, UBO parameter
    // block instead of loose uniforms. See `snail.shader.slang_generated`
    // for the interface contract. The fragment-only families pair with
    // `native_text_vertex_shader` (shared stage IO).
    pub const native_text_vertex_shader = slang_gen.textGlsl330(.vertex);
    pub const native_text_fragment_shader = slang_gen.textGlsl330(.fragment);
    pub const native_painted_vertex_shader = slang_gen.paintedVertGlsl330();
    pub const native_colr_fragment_shader = slang_gen.colrFragGlsl330();
    pub const native_path_fragment_shader = slang_gen.pathFragGlsl330();
    pub const native_tt_hinted_fragment_shader = slang_gen.ttHintedFragGlsl330();
    pub const native_autohint_vertex_shader = slang_gen.autohintGlsl330(.vertex);
    pub const native_autohint_fragment_shader = slang_gen.autohintGlsl330(.fragment);
    pub const native_subpixel_fragment_shader = slang_gen.subpixelFragGlsl330();
    pub const native_linear_resolve_vertex_shader = slang_gen.linearResolveGlsl330(.vertex);
    pub const native_linear_resolve_fragment_shader = slang_gen.linearResolveGlsl330(.fragment);
};

pub const Gles30 = struct {
    const version =
        "#version 300 es\n" ++
        "precision highp float;\n" ++
        "precision highp int;\n" ++
        "precision highp sampler2D;\n" ++
        "precision highp sampler2DArray;\n" ++
        "precision highp usampler2DArray;\n\n";

    pub const vertex_shader = version ++ vert_interface ++ "\n" ++ color_common ++ "\n" ++ vertex_body ++ vertex_entry;
    pub const vertex_shader_autohint = version ++ autohint_vertex_source;
    pub const fragment_shader_text = version ++ text_interface ++ "\n" ++ text_fragment_body;
    pub const fragment_shader_colr = version ++ frag_interface ++ "\n" ++ colr_fragment_body;
    pub const fragment_shader_path = version ++ frag_interface ++ "\n" ++ path_fragment_body;
    pub const fragment_shader_tt_hinted_text = version ++ frag_interface ++ "\n" ++ hinted_fragment_body;
    pub const fragment_shader_autohint = version ++ autohint_frag_interface ++ "\n" ++ autohint_fast_fragment_body;
    pub const fragment_shader_text_subpixel_dual = "";
    pub const linear_resolve_vertex_shader = version ++ linear_resolve_vertex_body;
    pub const linear_resolve_fragment_shader = version ++ linear_resolve_fragment_body;

    // Native-Slang generated families; see Gl330 above.
    pub const native_text_vertex_shader = slang_gen.textGles300(.vertex);
    pub const native_text_fragment_shader = slang_gen.textGles300(.fragment);
    pub const native_painted_vertex_shader = slang_gen.paintedVertGles300();
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
