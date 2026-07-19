// Fragment half of the vertex-fit autohint path. The vertex stage supplies
// draw-time targets and compact source indices; immutable base positions stay
// in the analysis record. Oversized/perspective axes use the full fitter below.

const uint SNAIL_AH_FAST_UNUSED = 255u;
const uint SNAIL_AH_FAST_FALLBACK = 254u;

ivec2 snailAhLayerLoc(ivec2 base, int offset) {
    int width = textureSize(u_layer_tex, 0).x;
    int texel = base.y * width + base.x + offset;
    return ivec2(texel % width, texel / width);
}

float snailWarpF(int block, int i) {
    int f = block + i;
    vec4 t = texelFetch(u_layer_tex, snailAhLayerLoc(v_info, f >> 2), 0);
    int c = f & 3;
    return (c == 0) ? t.x : ((c == 1) ? t.y : ((c == 2) ? t.z : t.w));
}

uint snailAhFastSource(uvec4 words, int idx) {
    uint word = words[idx >> 2];
    return (word >> uint((idx & 3) * 8)) & 255u;
}

float snailAhFastTarget(vec4 values[4], int idx) {
    return values[idx >> 2][idx & 3];
}

// -1 means use the full fragment fitter; 0..16 is an exact vertex-fit count.
int snailAhFastCount(uvec4 words) {
    if (snailAhFastSource(words, 0) == SNAIL_AH_FAST_FALLBACK) return -1;
    int count = 0;
    for (int i = 0; i < 16; ++i) {
        if (snailAhFastSource(words, i) == SNAIL_AH_FAST_UNUSED) break;
        ++count;
    }
    return count;
}

float snailAhFastBase(int run, float left, uvec4 sources, int idx) {
    uint source = snailAhFastSource(sources, idx);
    return source == uint(SNAIL_AH_LEFT_SOURCE) ? left : snailWarpF(run + 1 + 4 * int(source), 0);
}

float snailInverseFastAxis(
    int count,
    vec4 targets[4],
    uvec4 sources,
    int run,
    float left,
    float hinted,
    out float invSlope
) {
    invSlope = 1.0;
    if (count == 0) return hinted;
    float firstTarget = snailAhFastTarget(targets, 0);
    float firstBase = snailAhFastBase(run, left, sources, 0);
    if (hinted <= firstTarget) return firstBase + hinted - firstTarget;
    float lastTarget = snailAhFastTarget(targets, count - 1);
    float lastBase = snailAhFastBase(run, left, sources, count - 1);
    if (hinted >= lastTarget) return lastBase + hinted - lastTarget;

    int lo = 0;
    for (int i = 0; i < 15; ++i) {
        if (i + 1 >= count || snailAhFastTarget(targets, i + 1) >= hinted) {
            lo = i;
            break;
        }
    }
    float loTarget = snailAhFastTarget(targets, lo);
    float hiTarget = snailAhFastTarget(targets, lo + 1);
    float loBase = snailAhFastBase(run, left, sources, lo);
    float hiBase = snailAhFastBase(run, left, sources, lo + 1);
    float dt = hiTarget - loTarget;
    float db = hiBase - loBase;
    invSlope = abs(dt) > 1e-6 ? db / dt : 1.0;
    return loBase + (hinted - loTarget) * invSlope;
}

void snailAutohintFragment() {
    vec4 h0 = texelFetch(u_layer_tex, v_info, 0);
    vec4 h1 = texelFetch(u_layer_tex, snailAhLayerLoc(v_info, 1), 0);
    ivec2 gLoc = ivec2(int(h0.x + 0.5), int(h0.y + 0.5));
    int packedBands = floatBitsToInt(h0.z);
    int bandMaxH = packedBands & 0xFFFF;
    int bandMaxV = (packedBands >> 16) & 0xFFFF;
    int texLayer = u_layer_base + int(v_texcoord_layer.z);

    vec2 rc = v_texcoord_layer.xy;
    vec2 epp = fwidth(rc);
    vec2 scale = vec2(1.0 / epp.x, 1.0 / epp.y);
    int blueCount = 0;
    int featureXCount = 0;
    int featureYCount = 0;
    bool valid = snailAhCount(snailWarpF(0, 10), blueCount);
    int xRun = 12 + 2 * blueCount;
    valid = valid && snailAhCount(snailWarpF(xRun, 0), featureXCount);
    int yRun = xRun + 1 + 4 * featureXCount;
    valid = valid && snailAhCount(snailWarpF(yRun, 0), featureYCount);

    int xCount = valid ? snailAhFastCount(v_ah_x_sources) : 0;
    int yCount = valid ? snailAhFastCount(v_ah_y_sources) : 0;
    float slopeX = 1.0;
    float slopeY = 1.0;
    bool fallbackX = xCount < 0;
    bool fallbackY = yCount < 0;

    if (valid && (fallbackX || fallbackY)) {
        SnailAutohintPolicy policy;
        float stdX = snailWarpF(0, 8);
        float stdY = snailWarpF(0, 9);
        valid = snailDecodeAutohintPolicy(v_policy0, v_policy1, policy) &&
            snailAhFinite(stdX) && stdX >= 0.0 && snailAhFinite(stdY) && stdY >= 0.0;
        if (valid && fallbackX) {
            float bases[SNAIL_AH_MAX_KNOTS];
            float targets[SNAIL_AH_MAX_KNOTS];
            int sources[SNAIL_AH_MAX_KNOTS];
            bool fitValid = snailFitAutohintAxis(0, xRun, blueCount, stdX, snailWarpF(0, 11),
                scale.x, policy, xCount, bases, targets, sources);
            if (!fitValid) xCount = 0;
            rc.x = snailInverseWarpAxis(xCount, bases, targets, rc.x, slopeX);
        }
        if (valid && fallbackY) {
            float bases[SNAIL_AH_MAX_KNOTS];
            float targets[SNAIL_AH_MAX_KNOTS];
            int sources[SNAIL_AH_MAX_KNOTS];
            bool fitValid = snailFitAutohintAxis(1, yRun, blueCount, stdY, 0.0,
                scale.y, policy, yCount, bases, targets, sources);
            if (!fitValid) yCount = 0;
            rc.y = snailInverseWarpAxis(yCount, bases, targets, rc.y, slopeY);
        }
    }
    if (!fallbackX) rc.x = snailInverseFastAxis(xCount, v_ah_x_targets, v_ah_x_sources, xRun, snailWarpF(0, 11), rc.x, slopeX);
    if (!fallbackY) rc.y = snailInverseFastAxis(yCount, v_ah_y_targets, v_ah_y_sources, yRun, 0.0, rc.y, slopeY);

    epp *= vec2(slopeX, slopeY);
    vec2 ppe = vec2(1.0 / max(epp.x, 1.0 / 65536.0), 1.0 / max(epp.y, 1.0 / 65536.0));
    float cov = evalGlyphCoverage(rc, epp, ppe, gLoc, ivec2(bandMaxV, bandMaxH), h1, texLayer);
    if (cov < 1.0 / 255.0) discard;
    vec4 premul = premultiplyColor(v_paint, cov);
    frag_color = (SNAIL_MASK_OUTPUT != 0) ? vec4(premul.a) :
        ((SNAIL_OUTPUT_SRGB != 0) ? srgbEncodePremultiplied(premul) : premul);
}
