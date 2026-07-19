// Baked TrueType hints use the ordinary curve and band atlas. The small
// layer-info record exists only because the special-instance ABI needs an
// address for the band metadata while retaining a distinct program family.
ivec2 offsetHintedInfoLoc(ivec2 base, int offset) {
    int width = textureSize(u_layer_tex, 0).x;
    int texel = base.y * width + base.x + offset;
    return ivec2(texel % width, texel / width);
}

void snailHintedTextFragment() {
    int layer_byte = (v_glyph.w >> 8) & 0xFF;
    if (layer_byte != SNAIL_SPECIAL_LAYER_SENTINEL) discard;
    int special_kind = v_glyph.w & 0xFF;
    if (special_kind != SNAIL_SPECIAL_KIND_HINTED_TEXT) discard;

    vec2 rc = v_texcoord;
    vec2 epp = fwidth(rc);
    vec2 ppe = vec2(1.0 / max(epp.x, 1.0 / 65536.0),
                    1.0 / max(epp.y, 1.0 / 65536.0));

    ivec2 info_base = v_glyph.xy;
    vec4 header = texelFetch(u_layer_tex, info_base, 0);
    vec4 band = texelFetch(u_layer_tex, offsetHintedInfoLoc(info_base, 1), 0);
    int packed_counts = floatBitsToInt(header.z);
    int band_max_h = packed_counts & 0xFFFF;
    int band_max_v = (packed_counts >> 16) & 0xFFFF;
    int atlas_layer = u_layer_base + int(v_banding.w);

    float cov = evalGlyphCoverage(rc, epp, ppe, ivec2(header.xy),
                                  ivec2(band_max_v, band_max_h), band,
                                  atlas_layer);
    if (cov < 1.0 / 255.0) discard;

    vec4 premul = premultiplyColor(v_color * v_tint, cov);
    frag_color = (SNAIL_MASK_OUTPUT != 0) ? vec4(premul.a) :
        ((SNAIL_OUTPUT_SRGB != 0) ? srgbEncodePremultiplied(premul) : premul);
}
