// Shared GLSL assembled for the GL backend.

const glsl_330_version = "#version 330 core\n\n";
const glsl_330_dual_source = "#define SNAIL_DUAL_SOURCE 1\n\n";

const gl330_vert_interface = @embedFile("glsl/snail_vert.interface.glsl");
const gl330_frag_interface = @embedFile("glsl/snail_frag.interface.glsl");
const gl330_text_subpixel_interface = @embedFile("glsl/snail_text_subpixel.interface.glsl");
const gl330_text_coverage_interface =
    \\in vec4 v_color;
    \\in vec2 v_texcoord;
    \\flat in vec4 v_banding;
    \\flat in ivec4 v_glyph;
    \\flat in vec4 v_hint_src;
    \\flat in vec4 v_hint_dst;
    \\flat in vec2 v_hint_bounds;
    \\
    \\uniform sampler2DArray u_curve_tex;
    \\uniform usampler2DArray u_band_tex;
    \\uniform int u_fill_rule;
    \\uniform int u_layer_base;
    \\
    \\#define SNAIL_FILL_RULE u_fill_rule
    \\
;

const shared_vertex_body = @embedFile("glsl/snail_vert_body.glsl");
const shared_text_coverage_fragment_body = @embedFile("glsl/snail_text_frag_body.glsl");
const shared_text_fragment_main =
    \\void main() {
    \\    int layer_byte = (v_glyph.w >> 8) & 0xFF;
    \\    if (layer_byte == 0xFF) discard;
    \\    int atlas_layer = u_layer_base + layer_byte;
    \\    vec2 rc = hintedLocalCoord(v_texcoord);
    \\    vec2 ppe = 1.0 / max(fwidth(rc), vec2(1.0 / 65536.0));
    \\    float cov = evalGlyphCoverage(rc, ppe, v_glyph.xy,
    \\                                  ivec2(v_glyph.z, v_glyph.w & 0xFF),
    \\                                  v_banding, atlas_layer);
    \\    if (cov < 1.0 / 255.0) discard;
    \\    vec4 linear_color = vec4(srgbDecode(v_color.r), srgbDecode(v_color.g), srgbDecode(v_color.b), v_color.a);
    \\    frag_color = premultiplyColor(linear_color, cov);
    \\}
    \\
;
const shared_text_fragment_body = shared_text_coverage_fragment_body ++ "\n" ++ shared_text_fragment_main;
const shared_colr_fragment_body = @embedFile("glsl/snail_colr_frag_body.glsl");
const shared_path_fragment_body = @embedFile("glsl/snail_path_frag_body.glsl");
const shared_text_subpixel_body = @embedFile("glsl/snail_text_subpixel_body.glsl");

pub const text_vertex_interface = gl330_vert_interface;
pub const text_fragment_interface = gl330_text_subpixel_interface;
pub const text_coverage_fragment_interface = gl330_text_coverage_interface;
pub const text_vertex_body = shared_vertex_body;
pub const text_fragment_body = shared_text_fragment_body;
pub const text_coverage_fragment_body = shared_text_coverage_fragment_body;

pub const vertex_shader =
    glsl_330_version ++
    gl330_vert_interface ++
    "\n" ++
    shared_vertex_body;

pub const fragment_shader_text =
    glsl_330_version ++
    gl330_text_subpixel_interface ++
    "\n" ++
    shared_text_fragment_body;

pub const fragment_shader_colr =
    glsl_330_version ++
    gl330_frag_interface ++
    "\n" ++
    shared_colr_fragment_body;

pub const fragment_shader =
    glsl_330_version ++
    gl330_frag_interface ++
    "\n" ++
    shared_path_fragment_body;

pub const fragment_shader_path = fragment_shader;

pub const fragment_shader_text_subpixel_dual =
    glsl_330_version ++
    glsl_330_dual_source ++
    gl330_text_subpixel_interface ++
    "\n" ++
    shared_text_subpixel_body;
