//! Canonical, entry-point-free GLSL fragment catalog.
//!
//! Every fragment has one source file, one runtime string, and one include
//! filename. OpenGL callers pass `source(id)` to `glShaderSource`; offline
//! compilers include `fileName(id)` from Snail's `snail_glsl` build path.
//! `dependencies` records the required order without choosing a stage
//! interface, resource bindings, entry point, or complete shader.

pub const Fragment = enum {
    render_abi,
    coverage_common,
    color_common,
    vertex_interface,
    vertex_body,
    autohint_vertex_interface,
    autohint_fragment_interface,
    autohint_vertex_body,
    render_fragment_interface,
    text_coverage_interface,
    text_subpixel_interface,
    text_coverage_body,
    regular_text_body,
    colr_body,
    path_body,
    hinted_text_body,
    autohint_warp,
    autohint_fast_body,
    text_subpixel_body,
    text_sample_interface_gl,
    text_sample_interface_gles,
    text_sample_interface_vulkan,
    text_sample_body,
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
        .autohint_vertex_body => @embedFile("glsl/snail_autohint_vert_body.glsl"),
        .render_fragment_interface => @embedFile("glsl/snail_frag.interface.glsl"),
        .text_coverage_interface => @embedFile("glsl/snail_text_coverage.interface.glsl"),
        .text_subpixel_interface => @embedFile("glsl/snail_text_subpixel.interface.glsl"),
        .text_coverage_body => @embedFile("glsl/snail_text_frag_body.glsl"),
        .regular_text_body => @embedFile("glsl/snail_text_main.glsl"),
        .colr_body => @embedFile("glsl/snail_colr_frag_body.glsl"),
        .path_body => @embedFile("glsl/snail_path_frag_body.glsl"),
        .hinted_text_body => @embedFile("glsl/snail_hinted_text_frag_body.glsl"),
        .autohint_warp => @embedFile("glsl/snail_autohint_warp.glsl"),
        .autohint_fast_body => @embedFile("glsl/snail_autohint_fast_main.glsl"),
        .text_subpixel_body => @embedFile("glsl/snail_text_subpixel_body.glsl"),
        .text_sample_interface_gl => @embedFile("glsl/snail_text_sample.interface.glsl"),
        .text_sample_interface_gles => @embedFile("glsl/snail_text_sample.interface.gles30.glsl"),
        .text_sample_interface_vulkan => @embedFile("glsl/snail_text_sample.interface.vulkan.glsl"),
        .text_sample_body => @embedFile("glsl/snail_text_sample_body.glsl"),
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
        .autohint_vertex_body => "snail_autohint_vert_body.glsl",
        .render_fragment_interface => "snail_frag.interface.glsl",
        .text_coverage_interface => "snail_text_coverage.interface.glsl",
        .text_subpixel_interface => "snail_text_subpixel.interface.glsl",
        .text_coverage_body => "snail_text_frag_body.glsl",
        .regular_text_body => "snail_text_main.glsl",
        .colr_body => "snail_colr_frag_body.glsl",
        .path_body => "snail_path_frag_body.glsl",
        .hinted_text_body => "snail_hinted_text_frag_body.glsl",
        .autohint_warp => "snail_autohint_warp.glsl",
        .autohint_fast_body => "snail_autohint_fast_main.glsl",
        .text_subpixel_body => "snail_text_subpixel_body.glsl",
        .text_sample_interface_gl => "snail_text_sample.interface.glsl",
        .text_sample_interface_gles => "snail_text_sample.interface.gles30.glsl",
        .text_sample_interface_vulkan => "snail_text_sample.interface.vulkan.glsl",
        .text_sample_body => "snail_text_sample_body.glsl",
    };
}

/// Required algorithm-fragment order for each reusable operation. Stage
/// interfaces are deliberately absent: the caller chooses those separately.
pub const dependencies = struct {
    pub const vertex = [_]Fragment{ .color_common, .vertex_body };
    pub const regular_text = [_]Fragment{ .render_abi, .coverage_common, .color_common, .text_coverage_body, .regular_text_body };
    pub const colr = [_]Fragment{ .render_abi, .coverage_common, .color_common, .path_body, .colr_body };
    pub const path = [_]Fragment{ .render_abi, .coverage_common, .color_common, .path_body };
    pub const hinted_text = [_]Fragment{ .render_abi, .coverage_common, .color_common, .text_coverage_body, .hinted_text_body };
    pub const autohint_vertex = [_]Fragment{ .color_common, .autohint_warp, .vertex_body, .autohint_vertex_body };
    pub const autohint_fast = [_]Fragment{ .render_abi, .coverage_common, .color_common, .text_coverage_body, .autohint_warp, .autohint_fast_body };
    pub const text_subpixel = [_]Fragment{ .render_abi, .coverage_common, .color_common, .text_subpixel_body };
    pub const text_sample = [_]Fragment{ .render_abi, .coverage_common, .color_common, .text_coverage_body, .text_sample_body };
};

/// Storage width required by the GLES records-interface fragment.
pub const gles_records_texture_width: u32 = 1024;

test "catalog sources and filenames describe the same atomic fragments" {
    const std = @import("std");
    inline for (std.meta.tags(Fragment)) |fragment| {
        try std.testing.expect(source(fragment).len != 0);
        try std.testing.expect(std.mem.endsWith(u8, fileName(fragment), ".glsl"));
        try std.testing.expect(std.mem.indexOf(u8, source(fragment), "void main") == null);
    }
    try std.testing.expect(std.mem.indexOf(
        u8,
        source(.text_sample_body),
        "snail_text_sample_premul_linear_with_footprint",
    ) != null);
}
