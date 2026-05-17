const common = @import("common.zig");
const snail = common.snail;
const build_options = common.build_options;
const SnailMat4 = common.SnailMat4;
const fromMat4 = common.fromMat4;

// Compile-time features and constants

pub export fn snail_harfbuzz_available() bool {
    return build_options.enable_harfbuzz;
}

pub export fn snail_text_words_per_glyph() usize {
    return snail.TEXT_WORDS_PER_GLYPH;
}
pub export fn snail_text_words_per_vertex() usize {
    return snail.TEXT_WORDS_PER_VERTEX;
}
pub export fn snail_text_vertices_per_glyph() usize {
    return snail.TEXT_VERTICES_PER_GLYPH;
}
pub export fn snail_path_words_per_shape() usize {
    return snail.PATH_WORDS_PER_SHAPE;
}
pub export fn snail_path_words_per_vertex() usize {
    return snail.PATH_WORDS_PER_VERTEX;
}
pub export fn snail_path_vertices_per_shape() usize {
    return snail.PATH_VERTICES_PER_SHAPE;
}

pub export fn snail_mat4_identity() SnailMat4 {
    return fromMat4(snail.Mat4.identity);
}
