// Canonical fragment half of the vertex-fit autohint path. The vertex stage
// supplies draw-time knot targets per feature slot; immutable base positions
// stay in the analysis record. Axes the vertex stage could not fit
// render unhinted.
module autohint_frag;

import resource_types;

import render_abi;
import color_common;
import coverage_common;
import text_coverage;
import autohint_warp;

public struct AutohintVaryings {
    public float4 paint;
    public float3 texcoord_layer;
    public int2 info;
    public uint4 policy;
    public float4 x_targets[4];
    public float4 y_targets[4];
    // Per axis: (knot mask, left-knot target bits, record run offset, left
    // edge bits); see SnailAhAxisFit and snailAhPackFit.
    public uint4 x_knots;
    public uint4 y_knots;
};

// Inverse of one axis's piecewise-linear warp. Knots are feature slots marked
// in the mask (plus an optional left knot preceding them); a force-unrolled
// scan finds the bracketing pair so slot targets stay constant-indexed.
// Bases are the features' immutable record positions.
float snailInverseFastAxis(
    SnailFloatTexture2D layer_tex,
    int2 info_base,
    float4 targets[4],
    uint4 knots,
    float hinted,
    out float invSlope
) {
    invSlope = 1.0;
    uint mask = knots.x;
    if (mask == 0u) return hinted;
    bool hasLeft = (mask & SNAIL_AH_LEFT_KNOT) != 0u;
    int run = int(knots.z);
    float left = asfloat(knots.w);

    // Slot -1 is the left knot. Track the first and last knots and the first
    // knot after the first whose target reaches `hinted`, with its predecessor.
    int firstSlot = -1;
    float firstTarget = asfloat(knots.y);
    bool haveKnot = hasLeft;
    int prevSlot = -1;
    float prevTarget = firstTarget;
    int loSlot = -1;
    int hiSlot = -1;
    float loTarget = 0.0;
    float hiTarget = 0.0;
    bool found = false;
    [ForceUnroll]
    for (int c = 0; c < SNAIL_AH_KNOT_SLOTS; ++c) {
        if ((mask & snailAhBit(c)) != 0u) {
            float t = targets[c >> 2][c & 3];
            if (!haveKnot) {
                firstSlot = c;
                firstTarget = t;
            } else if (!found && t >= hinted) {
                found = true;
                loSlot = prevSlot;
                loTarget = prevTarget;
                hiSlot = c;
                hiTarget = t;
            }
            haveKnot = true;
            prevSlot = c;
            prevTarget = t;
        }
    }

    if (hinted <= firstTarget) {
        float firstBase = firstSlot < 0 ? left : snailWarpF(layer_tex, info_base, run + 1 + 4 * firstSlot, 0);
        return firstBase + hinted - firstTarget;
    }
    if (hinted >= prevTarget) {
        float lastBase = prevSlot < 0 ? left : snailWarpF(layer_tex, info_base, run + 1 + 4 * prevSlot, 0);
        return lastBase + hinted - prevTarget;
    }
    float loBase = loSlot < 0 ? left : snailWarpF(layer_tex, info_base, run + 1 + 4 * loSlot, 0);
    float hiBase = snailWarpF(layer_tex, info_base, run + 1 + 4 * hiSlot, 0);
    float dt = hiTarget - loTarget;
    float db = hiBase - loBase;
    invSlope = abs(dt) > 1e-6 ? db / dt : 1.0;
    return loBase + (hinted - loTarget) * invSlope;
}

// The per-fragment warp state: everything the coverage evaluators need
// after the inverse warp has been resolved. `epp` is the UNWARPED
// footprint (fwidth of the varying); `slope` is the per-axis inverse-warp
// slope the caller multiplies into its footprint/derivatives (the local
// linearization the grayscale path has always used).
public struct SnailAutohintWarped {
    public float2 rc;
    public float2 epp;
    public float2 slope;
    public int2 gLoc;
    public int2 bandMax;
    public float4 band;
    public int texLayer;
};

public SnailAutohintWarped snailAutohintWarpSample(
    AutohintVaryings v,
    SnailFloatTexture2D layer_tex,
    int page_base)
{
    SnailAutohintWarped w;
    float4 h0 = layer_tex.Load(int3(v.info, 0));
    float4 h1 = layer_tex.Load(int3(snailAhLayerLoc(layer_tex, v.info, 1), 0));
    int2 gLoc = int2(int(h0.x + 0.5), int(h0.y + 0.5));
    int packedBands = asint(h0.z);
    int bandMaxH = packedBands & 0xFFFF;
    int bandMaxV = (packedBands >> 16) & 0xFFFF;
    int texLayer = page_base + int(v.texcoord_layer.z);

    float2 rc = v.texcoord_layer.xy;
    float2 epp = fwidth(rc);
    // An axis the vertex stage did not fit (non-affine, over the knot slots,
    // or invalid) arrives with an empty mask and renders unhinted.
    float slopeX = 1.0;
    float slopeY = 1.0;
    rc.x = snailInverseFastAxis(layer_tex, v.info, v.x_targets, v.x_knots, rc.x, slopeX);
    rc.y = snailInverseFastAxis(layer_tex, v.info, v.y_targets, v.y_knots, rc.y, slopeY);

    w.rc = rc;
    w.epp = epp;
    w.slope = float2(slopeX, slopeY);
    w.gLoc = gLoc;
    w.bandMax = int2(bandMaxV, bandMaxH);
    w.band = h1;
    w.texLayer = texLayer;
    return w;
}

public float4 snailAutohintFragment(
    AutohintVaryings v,
    SnailCurveStorage curve_tex,
    SnailBandStorage band_tex,
    SnailFloatTexture2D layer_tex,
    int page_base,
    SnailAtlasLayout atlas_layout,
    int output_srgb,
    float coverage_exponent,
    int mask_output)
{
    SnailAutohintWarped w = snailAutohintWarpSample(v, layer_tex, page_base);
    float2 epp = w.epp * w.slope;
    float2 ppe = float2(1.0 / max(epp.x, 1.0 / 65536.0), 1.0 / max(epp.y, 1.0 / 65536.0));
    float cov = evalGlyphCoverage(w.rc, epp, ppe, w.gLoc, w.bandMax, w.band, w.texLayer, atlas_layout,
                                  curve_tex, band_tex, coverage_exponent);
    if (cov < 1.0 / 255.0) discard;
    float4 premul = premultiplyColor(v.paint, cov);
    return (mask_output != 0) ? float4(premul.a) :
        ((output_srgb != 0) ? srgbEncodePremultiplied(premul) : premul);
}
