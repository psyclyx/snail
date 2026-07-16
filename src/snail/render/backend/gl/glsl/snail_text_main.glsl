void snailTextFragment() {
    int layer_byte = (v_glyph.w >> 8) & 0xFF;
    if (layer_byte == SNAIL_SPECIAL_LAYER_SENTINEL) discard;
    int atlas_layer = u_layer_base + layer_byte;
    vec2 rc = v_texcoord;
    vec2 dx = vec2(dFdx(rc.x), dFdy(rc.x));
    vec2 dy = vec2(dFdx(rc.y), dFdy(rc.y));
    vec2 epp = vec2(length(dx), length(dy));
    vec2 ppe = vec2(1.0 / max(epp.x, 1.0 / 65536.0), 1.0 / max(epp.y, 1.0 / 65536.0));
    float cov = evalGlyphCoverage(rc, epp, ppe, v_glyph.xy,
                                  ivec2(v_glyph.w & 0xFF, v_glyph.z),
                                  v_banding, atlas_layer);
    if (cov < 1.0 / 255.0) discard;
    // v_color / v_tint are already sRGB-decoded in the vertex shader.
    vec4 premul = premultiplyColor(v_color * v_tint, cov);
    frag_color = (SNAIL_MASK_OUTPUT != 0) ? vec4(premul.a) : ((SNAIL_OUTPUT_SRGB != 0) ? srgbEncodePremultiplied(premul) : premul);
}
