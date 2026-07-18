// Desktop GL 3.3 / 4.4 records storage: the emit words live in a
// GL_TEXTURE_BUFFER of GL_R32UI, sampled as a texel buffer.
uniform usamplerBuffer u_snail_text_records;
uniform int u_snail_text_glyph_count;

uint snailTextRecordWord(int linear_index) {
    return texelFetch(u_snail_text_records, linear_index).r;
}
