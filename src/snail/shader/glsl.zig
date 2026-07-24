//! Canonical GLSL fragment catalog plus complete driver-oriented programs.
//!
//! Every fragment has one source file, one runtime string, and one include
//! filename. OpenGL callers pass `source(id)` to `glShaderSource`; offline
//! compilers include `fileName(id)` from Snail's `snail_glsl` build path.
//! `dependencies` records the required order without choosing a stage
//! interface, resource bindings, or entry point. `programs` supplies complete
//! GL 3.3 / GLES 3.0 stages for hosts that do not need custom composition.

pub const Fragment = enum {
    render_abi,
    coverage_common,
    color_common,
    vertex_interface,
    vertex_body,
    autohint_vertex_interface,
    autohint_fragment_interface,
    autohint_subpixel_fragment_interface,
    autohint_vertex_body,
    render_fragment_interface,
    text_coverage_interface,
    text_subpixel_interface,
    text_coverage_body,
    regular_text_body,
    colr_body,
    path_body,
    tt_hinted_text_body,
    tt_hinted_text_subpixel_body,
    autohint_warp,
    autohint_fast_body,
    autohint_subpixel_body,
    text_subpixel_body,
    linear_resolve_body,
};

/// Runtime source for one canonical fragment.
pub fn source(comptime fragment: Fragment) [:0]const u8 {
    return switch (fragment) {
        .render_abi => @embedFile("glsl/snail_render_abi.glsl"),
        .coverage_common => @embedFile("glsl/snail_coverage_common.glsl"),
        .color_common => @embedFile("glsl/snail_color_common.glsl"),
        .vertex_interface => @embedFile("glsl/snail_vert.interface.glsl"),
        .vertex_body => @embedFile("glsl/snail_vert_body.glsl"),
        .autohint_vertex_interface => @embedFile("glsl/snail_autohint_vert.interface.glsl"),
        .autohint_fragment_interface => @embedFile("glsl/snail_autohint_frag.interface.glsl"),
        .autohint_subpixel_fragment_interface => @embedFile("glsl/snail_autohint_subpixel_frag.interface.glsl"),
        .autohint_vertex_body => @embedFile("glsl/snail_autohint_vert_body.glsl"),
        .render_fragment_interface => @embedFile("glsl/snail_frag.interface.glsl"),
        .text_coverage_interface => @embedFile("glsl/snail_text_coverage.interface.glsl"),
        .text_subpixel_interface => @embedFile("glsl/snail_text_subpixel.interface.glsl"),
        .text_coverage_body => @embedFile("glsl/snail_text_frag_body.glsl"),
        .regular_text_body => @embedFile("glsl/snail_text_main.glsl"),
        .colr_body => @embedFile("glsl/snail_colr_frag_body.glsl"),
        .path_body => @embedFile("glsl/snail_path_frag_body.glsl"),
        .tt_hinted_text_body => @embedFile("glsl/snail_tt_hinted_text_frag_body.glsl"),
        .tt_hinted_text_subpixel_body => @embedFile("glsl/snail_tt_hinted_text_subpixel_body.glsl"),
        .autohint_warp => @embedFile("glsl/snail_autohint_warp.glsl"),
        .autohint_fast_body => @embedFile("glsl/snail_autohint_fast_main.glsl"),
        .autohint_subpixel_body => @embedFile("glsl/snail_autohint_subpixel_body.glsl"),
        .text_subpixel_body => @embedFile("glsl/snail_text_subpixel_body.glsl"),
        .linear_resolve_body => @embedFile("glsl/snail_linear_resolve_body.glsl"),
    };
}

/// Include filename for the same canonical fragment.
pub fn fileName(fragment: Fragment) []const u8 {
    return switch (fragment) {
        .render_abi => "snail_render_abi.glsl",
        .coverage_common => "snail_coverage_common.glsl",
        .color_common => "snail_color_common.glsl",
        .vertex_interface => "snail_vert.interface.glsl",
        .vertex_body => "snail_vert_body.glsl",
        .autohint_vertex_interface => "snail_autohint_vert.interface.glsl",
        .autohint_fragment_interface => "snail_autohint_frag.interface.glsl",
        .autohint_subpixel_fragment_interface => "snail_autohint_subpixel_frag.interface.glsl",
        .autohint_vertex_body => "snail_autohint_vert_body.glsl",
        .render_fragment_interface => "snail_frag.interface.glsl",
        .text_coverage_interface => "snail_text_coverage.interface.glsl",
        .text_subpixel_interface => "snail_text_subpixel.interface.glsl",
        .text_coverage_body => "snail_text_frag_body.glsl",
        .regular_text_body => "snail_text_main.glsl",
        .colr_body => "snail_colr_frag_body.glsl",
        .path_body => "snail_path_frag_body.glsl",
        .tt_hinted_text_body => "snail_tt_hinted_text_frag_body.glsl",
        .tt_hinted_text_subpixel_body => "snail_tt_hinted_text_subpixel_body.glsl",
        .autohint_warp => "snail_autohint_warp.glsl",
        .autohint_fast_body => "snail_autohint_fast_main.glsl",
        .autohint_subpixel_body => "snail_autohint_subpixel_body.glsl",
        .text_subpixel_body => "snail_text_subpixel_body.glsl",
        .linear_resolve_body => "snail_linear_resolve_body.glsl",
    };
}

/// Required algorithm-fragment order for each reusable operation. Stage
/// interfaces are deliberately absent: the caller chooses those separately.
pub const dependencies = struct {
    pub const vertex = [_]Fragment{ .color_common, .vertex_body };
    pub const regular_text = [_]Fragment{ .render_abi, .coverage_common, .color_common, .text_coverage_body, .regular_text_body };
    pub const colr = [_]Fragment{ .render_abi, .coverage_common, .color_common, .path_body, .colr_body };
    pub const path = [_]Fragment{ .render_abi, .coverage_common, .color_common, .path_body };
    pub const tt_hinted_text = [_]Fragment{ .render_abi, .coverage_common, .color_common, .text_coverage_body, .tt_hinted_text_body };
    pub const tt_hinted_text_subpixel = [_]Fragment{ .render_abi, .coverage_common, .color_common, .text_subpixel_body, .tt_hinted_text_subpixel_body };
    pub const autohint_vertex = [_]Fragment{ .color_common, .autohint_warp, .vertex_body, .autohint_vertex_body };
    pub const autohint_fast = [_]Fragment{ .render_abi, .coverage_common, .color_common, .text_coverage_body, .autohint_warp, .autohint_fast_body };
    pub const autohint_subpixel = [_]Fragment{ .render_abi, .coverage_common, .color_common, .text_subpixel_body, .autohint_warp, .autohint_fast_body, .autohint_subpixel_body };
    pub const text_subpixel = [_]Fragment{ .render_abi, .coverage_common, .color_common, .text_subpixel_body };
    /// Fullscreen linear-resolve pass (float intermediate seed/encode) for
    /// hosts without hardware sRGB encode; see the fragment's recipe doc.
    pub const linear_resolve = [_]Fragment{ .color_common, .linear_resolve_body };
};

/// Complete, driver-friendly GL programs assembled from the canonical
/// structured fragments. These are the preferred shipping stages for OpenGL:
/// unlike the portable Slang -> SPIR-V -> GLSL artifacts, they preserve the
/// loops and helper boundaries authored for GL driver compilers.
pub const programs = struct {
    const vert_interface = source(.vertex_interface);
    const autohint_vert_interface = source(.autohint_vertex_interface);
    const frag_interface = source(.render_fragment_interface);
    const autohint_frag_interface = source(.autohint_fragment_interface);
    const autohint_subpixel_frag_interface = source(.autohint_subpixel_fragment_interface);
    const text_interface = source(.text_subpixel_interface);
    const render_abi = source(.render_abi);
    const vertex_body = source(.vertex_body);
    const coverage_common = source(.coverage_common);
    const color_common = source(.color_common);
    const text_coverage_body = source(.text_coverage_body);
    const text_main = source(.regular_text_body);
    const path_body = source(.path_body);
    const tt_hinted_body = source(.tt_hinted_text_body);
    const tt_hinted_subpixel_body = source(.tt_hinted_text_subpixel_body);
    const autohint_warp = source(.autohint_warp);
    const autohint_vert_body = source(.autohint_vertex_body);
    const autohint_fast_main = source(.autohint_fast_body);
    const autohint_subpixel_body = source(.autohint_subpixel_body);
    const subpixel_body = source(.text_subpixel_body);
    const linear_resolve_body = source(.linear_resolve_body);

    const vertex_entry = "\nvoid main() { snailVertex(); }\n";
    const autohint_vertex_entry = "\nvoid main() { snailAutohintVertex(); }\n";
    const text_coverage = render_abi ++ "\n" ++ coverage_common ++ "\n" ++ color_common ++ "\n" ++ text_coverage_body;
    const text_fragment = text_coverage ++ "\n" ++ text_main ++ "\nvoid main() { snailTextFragment(); }\n";
    const painted_fragment = render_abi ++ "\n" ++ coverage_common ++ "\n" ++ color_common ++ "\n" ++ path_body ++ "\nvoid main() { snailPaintedFragment(); }\n";
    const hinted_fragment = text_coverage ++ "\n" ++ tt_hinted_body ++ "\nvoid main() { snailTtHintedTextFragment(); }\n";
    const autohint_fragment = text_coverage ++ "\n" ++ autohint_warp ++ "\n" ++ autohint_fast_main ++ "\nvoid main() { snailAutohintFragment(); }\n";
    const autohint_vertex = autohint_vert_interface ++ "\n" ++ color_common ++ "\n" ++ autohint_warp ++ "\n" ++ vertex_body ++ "\n" ++ autohint_vert_body ++ autohint_vertex_entry;
    const subpixel_fragment = render_abi ++ "\n" ++ coverage_common ++ "\n" ++ color_common ++ "\n" ++ subpixel_body ++ "\nvoid main() { snailSubpixelFragment(); }\n";
    const hinted_subpixel_fragment = render_abi ++ "\n" ++ coverage_common ++ "\n" ++ color_common ++ "\n" ++ subpixel_body ++ "\n" ++ tt_hinted_subpixel_body ++ "\nvoid main() { snailTtHintedSubpixelFragment(); }\n";
    const autohint_subpixel_fragment = render_abi ++ "\n" ++ coverage_common ++ "\n" ++ color_common ++ "\n#define SNAIL_SUBPIXEL_NO_REGULAR_ENTRY 1\n" ++ subpixel_body ++ "\n" ++ autohint_warp ++ "\n" ++ autohint_fast_main ++ "\n" ++ autohint_subpixel_body ++ "\nvoid main() { snailAutohintSubpixelFragment(); }\n";

    const linear_resolve_vertex =
        \\out vec2 v_uv;
        \\void main() {
        \\    vec2 pos = vec2((gl_VertexID == 1) ? 3.0 : -1.0,
        \\                    (gl_VertexID == 2) ? 3.0 : -1.0);
        \\    v_uv = pos * 0.5 + 0.5;
        \\    gl_Position = vec4(pos, 0.0, 1.0);
        \\}
        \\
    ;
    const linear_resolve_frame =
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
    const linear_resolve_fragment = color_common ++ "\n" ++ linear_resolve_body ++ "\n" ++ linear_resolve_frame;

    pub const Gl330 = struct {
        const version = "#version 330 core\n\n";

        pub const vertex = version ++ vert_interface ++ "\n" ++ color_common ++ "\n" ++ vertex_body ++ vertex_entry;
        pub const autohint_vertex = version ++ programs.autohint_vertex;
        pub const text_fragment = version ++ programs.text_interface ++ "\n" ++ programs.text_fragment;
        pub const painted_fragment = version ++ frag_interface ++ "\n" ++ programs.painted_fragment;
        pub const hinted_fragment = version ++ frag_interface ++ "\n" ++ programs.hinted_fragment;
        pub const autohint_fragment = version ++ autohint_frag_interface ++ "\n" ++ programs.autohint_fragment;
        pub const subpixel_fragment = version ++ "#define SNAIL_DUAL_SOURCE 1\n\n" ++ text_interface ++ "\n" ++ programs.subpixel_fragment;
        pub const hinted_subpixel_fragment = version ++ "#define SNAIL_DUAL_SOURCE 1\n\n" ++ text_interface ++ "\n" ++ programs.hinted_subpixel_fragment;
        pub const autohint_subpixel_fragment = version ++ "#define SNAIL_DUAL_SOURCE 1\n\n" ++ autohint_subpixel_frag_interface ++ "\n" ++ programs.autohint_subpixel_fragment;
        pub const linear_resolve_vertex = version ++ programs.linear_resolve_vertex;
        pub const linear_resolve_fragment = version ++ programs.linear_resolve_fragment;
    };

    pub const Gles300 = struct {
        const version =
            "#version 300 es\n" ++
            "precision highp float;\n" ++
            "precision highp int;\n" ++
            "precision highp sampler2D;\n" ++
            "precision highp sampler2DArray;\n" ++
            "precision highp usampler2DArray;\n\n";

        pub const vertex = version ++ vert_interface ++ "\n" ++ color_common ++ "\n" ++ vertex_body ++ vertex_entry;
        pub const autohint_vertex = version ++ programs.autohint_vertex;
        pub const text_fragment = version ++ programs.text_interface ++ "\n" ++ programs.text_fragment;
        pub const painted_fragment = version ++ frag_interface ++ "\n" ++ programs.painted_fragment;
        pub const hinted_fragment = version ++ frag_interface ++ "\n" ++ programs.hinted_fragment;
        pub const autohint_fragment = version ++ autohint_frag_interface ++ "\n" ++ programs.autohint_fragment;
        pub const linear_resolve_vertex = version ++ programs.linear_resolve_vertex;
        pub const linear_resolve_fragment = version ++ programs.linear_resolve_fragment;
    };
};

test "catalog sources and filenames describe the same atomic fragments" {
    const std = @import("std");
    inline for (comptime std.meta.tags(Fragment)) |fragment| {
        try std.testing.expect(source(fragment).len != 0);
        try std.testing.expect(std.mem.endsWith(u8, fileName(fragment), ".glsl"));
        try std.testing.expect(std.mem.indexOf(u8, source(fragment), "void main") == null);
    }
}

test "complete GL programs expose one shared painted stage and authored LCD families" {
    const std = @import("std");
    try std.testing.expect(std.mem.indexOf(u8, programs.Gl330.painted_fragment, "snailPaintedFragment") != null);
    try std.testing.expect(std.mem.indexOf(u8, programs.Gl330.hinted_subpixel_fragment, "snailTtHintedSubpixelFragment") != null);
    try std.testing.expect(std.mem.indexOf(u8, programs.Gl330.autohint_subpixel_fragment, "snailAutohintSubpixelFragment") != null);
    try std.testing.expect(std.mem.indexOf(u8, programs.Gles300.painted_fragment, "void main") != null);
}
