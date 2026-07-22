void snailTextFragment() {
    if ((uint(v_glyph.w) & 0x8000u) != 0u) discard;
    int layer_byte = (v_glyph.z >> 8) & 0xFF;
    int atlas_layer = u_layer_base + layer_byte;
    vec2 rc = v_texcoord;
    vec2 epp = fwidth(rc);
    vec2 ppe = vec2(1.0 / max(epp.x, 1.0 / 65536.0), 1.0 / max(epp.y, 1.0 / 65536.0));
    float cov = evalGlyphCoverage(rc, epp, ppe, v_glyph.xy,
                                  ivec2((v_glyph.z >> 4) & 0xF, v_glyph.z & 0xF),
                                  v_banding, atlas_layer);
    if (cov < 1.0 / 255.0) discard;
    // v_color / v_tint arrive as linear-light f16 vertex attributes.
    vec4 premul = premultiplyColor(v_color * v_tint, cov);
    frag_color = (SNAIL_MASK_OUTPUT != 0) ? vec4(premul.a) : ((SNAIL_OUTPUT_SRGB != 0) ? srgbEncodePremultiplied(premul) : premul);
}
