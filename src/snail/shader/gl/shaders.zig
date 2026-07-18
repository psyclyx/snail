//! Reusable GLSL source fragments. These deliberately contain no `#version`,
//! resource binding numbers, output declarations, or complete shader stages.
//! Applications concatenate/include the pieces they need inside shader entry
//! points they own. Complete reference shaders live under `src/demo`.

const gl330_vert_interface = @embedFile("glsl/snail_vert.interface.glsl");
const gl330_render_fragment_interface = @embedFile("glsl/snail_frag.interface.glsl");
const gl330_text_subpixel_interface = @embedFile("glsl/snail_text_subpixel.interface.glsl");
const gl330_text_coverage_interface = @embedFile("glsl/snail_text_coverage.interface.glsl");
const gl330_text_sample_interface = @embedFile("glsl/snail_text_sample.interface.glsl");

const shared_render_abi = @embedFile("glsl/snail_render_abi.glsl");
const shared_coverage_common = @embedFile("glsl/snail_coverage_common.glsl");
const shared_color_common = @embedFile("glsl/snail_color_common.glsl");
const shared_text_coverage_fragment_body =
    shared_render_abi ++
    "\n" ++
    shared_coverage_common ++
    "\n" ++
    shared_color_common ++
    "\n" ++
    @embedFile("glsl/snail_text_frag_body.glsl");
const shared_text_sample_body = @embedFile("glsl/snail_text_sample_body.glsl");
const shared_vertex_functions = shared_color_common ++ "\n" ++ @embedFile("glsl/snail_vert_body.glsl");
const shared_regular_text_functions = shared_text_coverage_fragment_body ++ "\n" ++ @embedFile("glsl/snail_text_main.glsl");
const shared_path_functions = shared_render_abi ++ "\n" ++ shared_coverage_common ++ "\n" ++ shared_color_common ++ "\n" ++ @embedFile("glsl/snail_path_frag_body.glsl");
const shared_hinted_text_functions = shared_render_abi ++ "\n" ++ shared_coverage_common ++ "\n" ++ shared_color_common ++ "\n" ++ @embedFile("glsl/snail_hinted_text_frag_body.glsl");
const shared_autohint_functions = shared_text_coverage_fragment_body ++ "\n" ++ @embedFile("glsl/snail_autohint_warp.glsl") ++ "\n" ++ @embedFile("glsl/snail_autohint_main.glsl");

pub const text_vertex_interface = gl330_vert_interface;
pub const render_fragment_interface = gl330_render_fragment_interface;
pub const text_fragment_interface = gl330_text_subpixel_interface;
pub const text_coverage_fragment_interface = gl330_text_coverage_interface;
pub const text_sample_interface = gl330_text_sample_interface;
pub const text_coverage_fragment_body = shared_text_coverage_fragment_body;
pub const text_sample_body = shared_text_sample_body;
pub const vertex_functions = shared_vertex_functions;
pub const regular_text_functions = shared_regular_text_functions;
pub const path_functions = shared_path_functions;
pub const hinted_text_functions = shared_hinted_text_functions;
pub const autohint_functions = shared_autohint_functions;
pub const render_abi = shared_render_abi;
pub const coverage_functions = shared_coverage_common;
pub const color_functions = shared_color_common;
pub const gles30_text_sample_interface = @embedFile("glsl/snail_text_sample.interface.gles30.glsl");

test "shader library contains reusable coverage and sampling functions" {
    const std = @import("std");
    try std.testing.expect(std.mem.indexOf(u8, text_coverage_fragment_body, "evalGlyphCoverage") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_sample_body, "snail_text_sample_premul_linear") != null);
    try std.testing.expect(std.mem.indexOf(u8, text_coverage_fragment_body, "void main") == null);
    try std.testing.expect(std.mem.indexOf(u8, text_sample_body, "void main") == null);
    try std.testing.expect(std.mem.indexOf(u8, text_vertex_interface, "void main") == null);
    try std.testing.expect(std.mem.indexOf(u8, text_fragment_interface, "void main") == null);
    try std.testing.expect(std.mem.indexOf(u8, vertex_functions, "void snailVertex()") != null);
    try std.testing.expect(std.mem.indexOf(u8, path_functions, "void snailPathFragment()") != null);
    try std.testing.expect(std.mem.indexOf(u8, hinted_text_functions, "void snailHintedTextFragment()") != null);
    try std.testing.expect(std.mem.indexOf(u8, autohint_functions, "void snailAutohintFragment()") != null);
    try std.testing.expect(std.mem.indexOf(u8, vertex_functions, "void main") == null);
    try std.testing.expect(std.mem.indexOf(u8, path_functions, "void main") == null);
}
