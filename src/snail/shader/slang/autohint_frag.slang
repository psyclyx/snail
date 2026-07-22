// Native-Slang port of snail_autohint_fast_main.glsl — the fragment half of
// the vertex-fit autohint path. The vertex stage supplies draw-time targets
// and compact source indices; immutable base positions stay in the analysis
// record. Oversized/perspective axes use the full fitter. The GLSL fragment
// is the behavioral spec: every epsilon, literal, and operation order is
// preserved.
module autohint_frag;

import render_abi;
import color_common;
import coverage_common;
import text_coverage;
import autohint_warp;

static const int SNAIL_AH_FRAG_KNOTS = 32;
static const uint SNAIL_AH_FAST_UNUSED = 255u;
static const uint SNAIL_AH_FAST_FALLBACK = 254u;

public struct AutohintVaryings {
    public float4 paint;
    public float3 texcoord_layer;
    public int2 info;
    public uint4 policy0;
    public uint3 policy1;
    public float4 x_targets[4];
    public float4 y_targets[4];
    public uint4 x_sources;
    public uint4 y_sources;
};

uint snailAhFastSource(uint4 words, int idx) {
    uint word = words[idx >> 2];
    return (word >> uint((idx & 3) * 8)) & 255u;
}

float snailAhFastTarget(float4 values[4], int idx) {
    return values[idx >> 2][idx & 3];
}

// -1 means use the full fragment fitter; 0..16 is an exact vertex-fit count.
int snailAhFastCount(uint4 words) {
    if (snailAhFastSource(words, 0) == SNAIL_AH_FAST_FALLBACK) return -1;
    int count = 0;
    for (int i = 0; i < 16; ++i) {
        if (snailAhFastSource(words, i) == SNAIL_AH_FAST_UNUSED) break;
        ++count;
    }
    return count;
}

float snailAhFastBase(Texture2D<float4> layer_tex, int2 info_base, int run, float left, uint4 sources, int idx) {
    uint source = snailAhFastSource(sources, idx);
    return source == uint(SNAIL_AH_LEFT_SOURCE) ? left : snailWarpF(layer_tex, info_base, run + 1 + 4 * int(source), 0);
}

float snailInverseFastAxis(
    Texture2D<float4> layer_tex,
    int2 info_base,
    int count,
    float4 targets[4],
    uint4 sources,
    int run,
    float left,
    float hinted,
    out float invSlope
) {
    invSlope = 1.0;
    if (count == 0) return hinted;
    float firstTarget = snailAhFastTarget(targets, 0);
    float firstBase = snailAhFastBase(layer_tex, info_base, run, left, sources, 0);
    if (hinted <= firstTarget) return firstBase + hinted - firstTarget;
    float lastTarget = snailAhFastTarget(targets, count - 1);
    float lastBase = snailAhFastBase(layer_tex, info_base, run, left, sources, count - 1);
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
    float loBase = snailAhFastBase(layer_tex, info_base, run, left, sources, lo);
    float hiBase = snailAhFastBase(layer_tex, info_base, run, left, sources, lo + 1);
    float dt = hiTarget - loTarget;
    float db = hiBase - loBase;
    invSlope = abs(dt) > 1e-6 ? db / dt : 1.0;
    return loBase + (hinted - loTarget) * invSlope;
}

public float4 snailAutohintFragment(
    AutohintVaryings v,
    Texture2DArray<float4> curve_tex,
    Texture2DArray<uint2> band_tex,
    Texture2D<float4> layer_tex,
    int layer_base,
    int output_srgb,
    float coverage_exponent,
    int mask_output)
{
    float4 h0 = layer_tex.Load(int3(v.info, 0));
    float4 h1 = layer_tex.Load(int3(snailAhLayerLoc(layer_tex, v.info, 1), 0));
    int2 gLoc = int2(int(h0.x + 0.5), int(h0.y + 0.5));
    int packedBands = asint(h0.z);
    int bandMaxH = packedBands & 0xFFFF;
    int bandMaxV = (packedBands >> 16) & 0xFFFF;
    int texLayer = layer_base + int(v.texcoord_layer.z);

    float2 rc = v.texcoord_layer.xy;
    float2 epp = fwidth(rc);
    float2 scale = float2(1.0 / epp.x, 1.0 / epp.y);
    int blueCount = 0;
    int featureXCount = 0;
    int featureYCount = 0;
    bool valid = snailAhCount(SNAIL_AH_FRAG_KNOTS, snailWarpF(layer_tex, v.info, 0, 10), blueCount);
    int xRun = 12 + 2 * blueCount;
    valid = valid && snailAhCount(SNAIL_AH_FRAG_KNOTS, snailWarpF(layer_tex, v.info, xRun, 0), featureXCount);
    int yRun = xRun + 1 + 4 * featureXCount;
    valid = valid && snailAhCount(SNAIL_AH_FRAG_KNOTS, snailWarpF(layer_tex, v.info, yRun, 0), featureYCount);

    int xCount = valid ? snailAhFastCount(v.x_sources) : 0;
    int yCount = valid ? snailAhFastCount(v.y_sources) : 0;
    float slopeX = 1.0;
    float slopeY = 1.0;
    bool fallbackX = xCount < 0;
    bool fallbackY = yCount < 0;

    if (valid && (fallbackX || fallbackY)) {
        SnailAutohintPolicy policy;
        float stdX = snailWarpF(layer_tex, v.info, 0, 8);
        float stdY = snailWarpF(layer_tex, v.info, 0, 9);
        valid = snailDecodeAutohintPolicy(v.policy0, v.policy1, policy) &&
            snailAhFinite(stdX) && stdX >= 0.0 && snailAhFinite(stdY) && stdY >= 0.0;
        if (valid && fallbackX) {
            float bases[SNAIL_AH_FRAG_KNOTS];
            float targets[SNAIL_AH_FRAG_KNOTS];
            int sources[SNAIL_AH_FRAG_KNOTS];
            bool fitValid = snailFitAutohintAxis<SNAIL_AH_FRAG_KNOTS, false>(layer_tex, v.info,
                0, xRun, blueCount, stdX, snailWarpF(layer_tex, v.info, 0, 11),
                scale.x, policy, xCount, bases, targets, sources);
            if (!fitValid) xCount = 0;
            rc.x = snailInverseWarpAxis<SNAIL_AH_FRAG_KNOTS>(xCount, bases, targets, rc.x, slopeX);
        }
        if (valid && fallbackY) {
            float bases[SNAIL_AH_FRAG_KNOTS];
            float targets[SNAIL_AH_FRAG_KNOTS];
            int sources[SNAIL_AH_FRAG_KNOTS];
            bool fitValid = snailFitAutohintAxis<SNAIL_AH_FRAG_KNOTS, false>(layer_tex, v.info,
                1, yRun, blueCount, stdY, 0.0,
                scale.y, policy, yCount, bases, targets, sources);
            if (!fitValid) yCount = 0;
            rc.y = snailInverseWarpAxis<SNAIL_AH_FRAG_KNOTS>(yCount, bases, targets, rc.y, slopeY);
        }
    }
    if (!fallbackX) rc.x = snailInverseFastAxis(layer_tex, v.info, xCount, v.x_targets, v.x_sources, xRun, snailWarpF(layer_tex, v.info, 0, 11), rc.x, slopeX);
    if (!fallbackY) rc.y = snailInverseFastAxis(layer_tex, v.info, yCount, v.y_targets, v.y_sources, yRun, 0.0, rc.y, slopeY);

    epp *= float2(slopeX, slopeY);
    float2 ppe = float2(1.0 / max(epp.x, 1.0 / 65536.0), 1.0 / max(epp.y, 1.0 / 65536.0));
    float cov = evalGlyphCoverage(rc, epp, ppe, gLoc, int2(bandMaxV, bandMaxH), h1, texLayer,
                                  curve_tex, band_tex, coverage_exponent);
    if (cov < 1.0 / 255.0) discard;
    float4 premul = premultiplyColor(v.paint, cov);
    return (mask_output != 0) ? float4(premul.a) :
        ((output_srgb != 0) ? srgbEncodePremultiplied(premul) : premul);
}
