// GLES 3.0 records storage. Buffer textures (GL_TEXTURE_BUFFER / usamplerBuffer)
// are not in GLES 3.0 core, so the emit words live in a 2D GL_R32UI texture
// instead, addressed row-major at a fixed width. The caller uploads the words
// into a `SNAIL_TEXT_RECORDS_TEX_WIDTH`-wide R32UI texture (height =
// ceil(word_count / width)); `snail.shader.glsl.gles_records_texture_width`
// exposes the same constant to the upload side.
#define SNAIL_TEXT_RECORDS_TEX_WIDTH 1024

uniform highp usampler2D u_snail_text_records;
uniform int u_snail_text_glyph_count;

uint snailTextRecordWord(int linear_index) {
    return texelFetch(
        u_snail_text_records,
        ivec2(linear_index % SNAIL_TEXT_RECORDS_TEX_WIDTH,
              linear_index / SNAIL_TEXT_RECORDS_TEX_WIDTH),
        0
    ).r;
}
