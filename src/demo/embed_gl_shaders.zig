//! Complete GL/GLES shader stages used by the reference renderer. These entry
//! points deliberately live with the demo: the library exports only the
//! reusable, entry-point-free pieces in `snail.gl.shader_library` and
//! `snail.gl.embeddable`.

const library = @import("snail").gl.shader_library;
const vert_interface = @embedFile("snail_ref_vert_interface");
const frag_interface = @embedFile("snail_ref_frag_interface");
const text_interface = @embedFile("snail_ref_text_interface");
const render_abi = library.render_abi;
const vertex_body = @embedFile("snail_ref_vert_body");
const coverage_common = library.coverage_functions;
const color_common = library.color_functions;
const text_coverage = library.text_coverage_fragment_body;
const text_main = @embedFile("snail_ref_text_main");
const colr_body = @embedFile("snail_ref_colr_body");
const path_body = @embedFile("snail_ref_path_body");
const hinted_body = @embedFile("snail_ref_hinted_body");
const autohint_warp = @embedFile("snail_ref_autohint_warp");
const autohint_main = @embedFile("snail_ref_autohint_main");
const subpixel_body = @embedFile("snail_ref_subpixel_body");

const vertex_entry = "\nvoid main() { snailVertex(); }\n";
const text_fragment_body = text_coverage ++ "\n" ++ text_main ++ "\nvoid main() { snailTextFragment(); }\n";
const colr_fragment_body = render_abi ++ "\n" ++ coverage_common ++ "\n" ++ color_common ++ "\n" ++ colr_body ++ "\nvoid main() { snailColrFragment(); }\n";
const path_fragment_body = render_abi ++ "\n" ++ coverage_common ++ "\n" ++ color_common ++ "\n" ++ path_body ++ "\nvoid main() { snailPathFragment(); }\n";
const hinted_fragment_body = render_abi ++ "\n" ++ coverage_common ++ "\n" ++ color_common ++ "\n" ++ hinted_body ++ "\nvoid main() { snailHintedTextFragment(); }\n";
const autohint_fragment_body = text_coverage ++ "\n" ++ autohint_warp ++ "\n" ++ autohint_main ++ "\nvoid main() { snailAutohintFragment(); }\n";
const subpixel_fragment_body = render_abi ++ "\n" ++ coverage_common ++ "\n" ++ color_common ++ "\n" ++ subpixel_body ++ "\nvoid main() { snailSubpixelFragment(); }\n";

pub const Gl330 = struct {
    const version = "#version 330 core\n\n";

    pub const vertex_shader = version ++ vert_interface ++ "\n" ++ color_common ++ "\n" ++ vertex_body ++ vertex_entry;
    pub const fragment_shader_text = version ++ text_interface ++ "\n" ++ text_fragment_body;
    pub const fragment_shader_colr = version ++ frag_interface ++ "\n" ++ colr_fragment_body;
    pub const fragment_shader_path = version ++ frag_interface ++ "\n" ++ path_fragment_body;
    pub const fragment_shader_hinted_text = version ++ frag_interface ++ "\n" ++ hinted_fragment_body;
    pub const fragment_shader_autohint = version ++ frag_interface ++ "\n" ++ autohint_fragment_body;
    pub const fragment_shader_text_subpixel_dual = version ++ "#define SNAIL_DUAL_SOURCE 1\n\n" ++ text_interface ++ "\n" ++ subpixel_fragment_body;
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
    pub const fragment_shader_text = version ++ text_interface ++ "\n" ++ text_fragment_body;
    pub const fragment_shader_colr = version ++ frag_interface ++ "\n" ++ colr_fragment_body;
    pub const fragment_shader_path = version ++ frag_interface ++ "\n" ++ path_fragment_body;
    pub const fragment_shader_hinted_text = version ++ frag_interface ++ "\n" ++ hinted_fragment_body;
    pub const fragment_shader_autohint = version ++ frag_interface ++ "\n" ++ autohint_fragment_body;
    pub const fragment_shader_text_subpixel_dual = "";
};

test "reference entry points stay outside the library shader surface" {
    const std = @import("std");
    try std.testing.expect(std.mem.indexOf(u8, Gl330.vertex_shader, "void main") != null);
    try std.testing.expect(std.mem.indexOf(u8, Gles30.fragment_shader_path, "void main") != null);
}
