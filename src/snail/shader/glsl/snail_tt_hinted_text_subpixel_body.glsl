ivec2 offsetTtHintedSubpixelInfoLoc(ivec2 base, int offset) {
    int width = textureSize(u_layer_tex, 0).x;
    int texel = base.y * width + base.x + offset;
    return ivec2(texel % width, texel / width);
}

void snailTtHintedSubpixelFragment() {
#ifdef SNAIL_DUAL_SOURCE
    frag_blend = vec4(0.0);
#endif
    if ((uint(v_glyph.w) & 0x8000u) == 0u) discard;
    if ((v_glyph.w & 0x3) != SNAIL_SPECIAL_KIND_TT_HINTED_TEXT) discard;

    ivec2 info_base = v_glyph.xy;
    vec4 header = texelFetch(u_layer_tex, info_base, 0);
    vec4 band = texelFetch(u_layer_tex, offsetTtHintedSubpixelInfoLoc(info_base, 1), 0);
    int packed_counts = floatBitsToInt(header.z);
    ivec2 band_max = ivec2(
        (packed_counts >> 16) & 0xFFFF,
        packed_counts & 0xFFFF
    );
    int layer = u_layer_base + ((v_glyph.w >> 2) & 0xff);
    vec4 cov_alpha = evalGlyphCoverageSubpixel(
        v_texcoord, ivec2(int(header.x), int(header.y)),
        band_max, band, layer
    );
    vec3 cov = cov_alpha.rgb;
    if (max(max(cov.r, cov.g), cov.b) < 1.0 / 255.0) discard;
    emitSubpixelColor(v_color * v_tint, cov, cov_alpha.a);
}
