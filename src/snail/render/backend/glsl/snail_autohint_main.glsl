// Fragment main for immutable autohint records. It derives policy-specific
// knots transiently from the feature tuples, inverse-warps the sample, then
// evaluates ordinary coverage against the shared unhinted base glyph.

ivec2 snailAhLayerLoc(ivec2 base, int offset) {
    int width = textureSize(u_layer_tex, 0).x;
    int texel = base.y * width + base.x + offset;
    return ivec2(texel % width, texel / width);
}

float snailWarpF(int block, int i) {
    int f = block + i;
    vec4 t = texelFetch(u_layer_tex, snailAhLayerLoc(v_glyph.xy, f >> 2), 0);
    int c = f & 3;
    return (c == 0) ? t.x : ((c == 1) ? t.y : ((c == 2) ? t.z : t.w));
}

bool snailAhCount(float encoded, out int count) {
    if (!snailAhFinite(encoded) || encoded < 0.0 || encoded > float(SNAIL_AH_MAX_KNOTS) || floor(encoded) != encoded) {
        count = 0;
        return false;
    }
    count = int(encoded);
    return true;
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
    vec2 scale = vec2(1.0 / epp.x, 1.0 / epp.y);

    int xCount = 0;
    int yCount = 0;
    float xBase[SNAIL_AH_MAX_KNOTS];
    float xTarget[SNAIL_AH_MAX_KNOTS];
    float yBase[SNAIL_AH_MAX_KNOTS];
    float yTarget[SNAIL_AH_MAX_KNOTS];
    SnailAutohintPolicy policy;
    int blueCount = 0;
    int featureXCount = 0;
    int featureYCount = 0;
    bool valid = snailDecodeAutohintPolicy(v_policy0, v_policy1, policy) &&
        snailAhCount(snailWarpF(0, 10), blueCount);
    int xRun = 12 + 2 * blueCount;
    valid = valid && snailAhCount(snailWarpF(xRun, 0), featureXCount);
    int yRun = xRun + 1 + 4 * featureXCount;
    valid = valid && snailAhCount(snailWarpF(yRun, 0), featureYCount);
    if (valid) {
        bool xValid = snailFitAutohintAxis(0, xRun, blueCount, snailWarpF(0, 8), snailWarpF(0, 11),
            scale.x, policy, xCount, xBase, xTarget);
        bool yValid = snailFitAutohintAxis(1, yRun, blueCount, snailWarpF(0, 9), 0.0,
            scale.y, policy, yCount, yBase, yTarget);
        if (!xValid) xCount = 0;
        if (!yValid) yCount = 0;
    }

    float slopeX;
    float slopeY;
    rc.x = snailInverseWarpAxis(xCount, xBase, xTarget, rc.x, slopeX);
    rc.y = snailInverseWarpAxis(yCount, yBase, yTarget, rc.y, slopeY);
    epp *= vec2(slopeX, slopeY);
    vec2 ppe = vec2(1.0 / max(epp.x, 1.0 / 65536.0), 1.0 / max(epp.y, 1.0 / 65536.0));

    float cov = evalGlyphCoverage(rc, epp, ppe, gLoc, ivec2(bandMaxV, bandMaxH), h1, texLayer);
    if (cov < 1.0 / 255.0) discard;
    vec4 premul = premultiplyColor(v_color * v_tint, cov);
    frag_color = (SNAIL_MASK_OUTPUT != 0) ? vec4(premul.a) : ((SNAIL_OUTPUT_SRGB != 0) ? srgbEncodePremultiplied(premul) : premul);
}
