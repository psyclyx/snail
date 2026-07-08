// Fragment main for the `autohint` special kind. Reads the slab record (base
// glyph band entry in texels 0-1, then the two packed knot runs), warps the
// sample coordinate back into base-outline space, rescales the AA footprint,
// and runs the ordinary text coverage evaluator against the shared unhinted
// base glyph. Mirrors the CPU path (renderer.zig renderTransformedAutohint*).

ivec2 snailAhLayerLoc(ivec2 base, int offset) {
    int width = textureSize(u_layer_tex, 0).x;
    int texel = base.y * width + base.x + offset;
    return ivec2(texel % width, texel / width);
}

// Float `block+i` of the record, fetched from the RGBA layer-info texture.
float snailWarpF(int block, int i) {
    int f = block + i;
    vec4 t = texelFetch(u_layer_tex, snailAhLayerLoc(v_glyph.xy, f >> 2), 0);
    int c = f & 3;
    return (c == 0) ? t.x : ((c == 1) ? t.y : ((c == 2) ? t.z : t.w));
}

void main() {
    int layer_byte = (v_glyph.w >> 8) & 0xFF;
    if (layer_byte != SNAIL_SPECIAL_LAYER_SENTINEL) discard;
    if ((v_glyph.w & 0xFF) != SNAIL_SPECIAL_KIND_AUTOHINT) discard;

    ivec2 infoBase = v_glyph.xy;
    vec4 h0 = texelFetch(u_layer_tex, infoBase, 0);
    vec4 h1 = texelFetch(u_layer_tex, snailAhLayerLoc(infoBase, 1), 0);
    ivec2 gLoc = ivec2(int(h0.x + 0.5), int(h0.y + 0.5));
    int packed_bands = floatBitsToInt(h0.z);
    int bandMaxH = packed_bands & 0xFFFF;
    int bandMaxV = (packed_bands >> 16) & 0xFFFF;
    int texLayer = u_layer_base + int(v_banding.w);

    vec2 rc = v_texcoord;
    vec2 dx = vec2(dFdx(rc.x), dFdy(rc.x));
    vec2 dy = vec2(dFdx(rc.y), dFdy(rc.y));
    vec2 epp = vec2(length(dx), length(dy));

    // Warp: x-run starts at float 8, y-run right after it.
    int x_block = 8;
    int x_count = int(snailWarpF(x_block, 0));
    int y_block = 8 + 1 + 2 * x_count;
    float slope_x, slope_y;
    float base_x = snailInverseWarpAxis(x_block, rc.x, slope_x);
    float base_y = snailInverseWarpAxis(y_block, rc.y, slope_y);
    rc = vec2(base_x, base_y);
    epp = vec2(epp.x * slope_x, epp.y * slope_y);
    vec2 ppe = vec2(1.0 / max(epp.x, 1.0 / 65536.0), 1.0 / max(epp.y, 1.0 / 65536.0));

    float cov = evalGlyphCoverage(rc, epp, ppe, gLoc, ivec2(bandMaxV, bandMaxH), h1, texLayer);
    if (cov < 1.0 / 255.0) discard;

    vec4 premul = premultiplyColor(v_color * v_tint, cov);
    frag_color = (SNAIL_MASK_OUTPUT != 0) ? vec4(premul.a) : ((SNAIL_OUTPUT_SRGB != 0) ? srgbEncodePremultiplied(premul) : premul);
}
