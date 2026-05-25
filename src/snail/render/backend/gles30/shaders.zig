// Shared GLSL assembled for the GLES30 backend.

const glsl_300es_version =
    "#version 300 es\n" ++
    "precision highp float;\n" ++
    "precision highp int;\n" ++
    "precision highp sampler2D;\n" ++
    "precision highp sampler2DArray;\n" ++
    "precision highp usampler2DArray;\n\n";

const gles30_vert_interface = @embedFile("../glsl/snail_vert.interface.glsl");
const gles30_frag_interface = @embedFile("../glsl/snail_frag.interface.glsl");
const gles30_text_subpixel_interface = @embedFile("../glsl/snail_text_subpixel.interface.glsl");
const gles30_text_coverage_interface = @embedFile("../glsl/snail_text_coverage.interface.glsl");
const gles30_text_sample_interface = @embedFile("../glsl/snail_text_sample.interface.glsl");

const shared_render_abi = @embedFile("../glsl/snail_render_abi.glsl");
const shared_vertex_body = @embedFile("../glsl/snail_vert_body.glsl");
const shared_coverage_common = @embedFile("../glsl/snail_coverage_common.glsl");
const shared_color_common = @embedFile("../glsl/snail_color_common.glsl");
const shared_text_coverage_fragment_body =
    shared_render_abi ++
    "\n" ++
    shared_coverage_common ++
    "\n" ++
    shared_color_common ++
    "\n" ++
    @embedFile("../glsl/snail_text_frag_body.glsl");
const shared_text_fragment_main = @embedFile("../glsl/snail_text_main.glsl");
const shared_text_fragment_body = shared_text_coverage_fragment_body ++ "\n" ++ shared_text_fragment_main;
const shared_colr_fragment_body =
    shared_render_abi ++
    "\n" ++
    shared_coverage_common ++
    "\n" ++
    shared_color_common ++
    "\n" ++
    @embedFile("../glsl/snail_colr_frag_body.glsl");
const shared_path_fragment_body =
    shared_render_abi ++
    "\n" ++
    shared_coverage_common ++
    "\n" ++
    shared_color_common ++
    "\n" ++
    @embedFile("../glsl/snail_path_frag_body.glsl");
const shared_hinted_text_fragment_body =
    shared_render_abi ++
    "\n" ++
    shared_coverage_common ++
    "\n" ++
    shared_color_common ++
    "\n" ++
    @embedFile("../glsl/snail_hinted_text_frag_body.glsl");
const shared_text_subpixel_body =
    shared_render_abi ++
    "\n" ++
    shared_coverage_common ++
    "\n" ++
    shared_color_common ++
    "\n" ++
    @embedFile("../glsl/snail_text_subpixel_body.glsl");
const shared_text_sample_body = @embedFile("../glsl/snail_text_sample_body.glsl");

pub const text_vertex_interface = gles30_vert_interface;
pub const text_fragment_interface = gles30_text_subpixel_interface;
pub const text_coverage_fragment_interface = gles30_text_coverage_interface;
pub const text_sample_interface = gles30_text_sample_interface;
pub const text_vertex_body = shared_vertex_body;
pub const text_fragment_body = shared_text_fragment_body;
pub const text_coverage_fragment_body = shared_text_coverage_fragment_body;
pub const text_sample_body = shared_text_sample_body;

pub const vertex_shader =
    glsl_300es_version ++
    gles30_vert_interface ++
    "\n" ++
    shared_vertex_body;

pub const fragment_shader_text =
    glsl_300es_version ++
    gles30_text_subpixel_interface ++
    "\n" ++
    shared_text_fragment_body;

pub const fragment_shader_colr =
    glsl_300es_version ++
    gles30_frag_interface ++
    "\n" ++
    shared_colr_fragment_body;

pub const fragment_shader_path =
    glsl_300es_version ++
    gles30_frag_interface ++
    "\n" ++
    shared_path_fragment_body;

pub const fragment_shader_hinted_text =
    glsl_300es_version ++
    gles30_frag_interface ++
    "\n" ++
    shared_hinted_text_fragment_body;

pub const fragment_shader_text_subpixel_dual = "";
