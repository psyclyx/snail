// Canonical transient autohint fitting (a bounded port of
// snail-raster/autohint_warp.zig fitAxis + inverseWarp).
//
// Shader-specific plumbing:
//  - The fit runs once per quad in the vertex stage over at most
//    SNAIL_AH_KNOT_SLOTS features per axis, in register-resident tables (see
//    below); larger runs render unhinted.
//  - `snailWarpF` reads through explicit Texture2D + info-base parameters
//    instead of a caller-provided extern function.
//  - The WGSL finite check (no isnan/isinf there — NaN semantics are
//    implementation-defined) keeps its abs() range form behind
//    SNAIL_TARGET_WGSL, mirroring the catalog's SNAIL_WGSL variant.
module autohint_warp;

import resource_types;
import binary16;
import render_abi;

// Upper bound on record feature and blue-zone counts (max_features_per_axis).
public static const int SNAIL_AH_RECORD_FEATURES = 32;

public struct SnailAutohintPolicy {
    public int xAlign;
    public int xStem;
    public int xPositioning;
    public int xRegistration;
    public int yAlign;
    public int yStem;
    public int yOvershoot;
    public int fadeEnabled;
    public float fadeStart;
    public float fadeFull;
    public float xRatio;
    public float xMaxPx;
    public float yRatio;
    public float yMaxPx;
    public float overshootMinPx;
};

// WGSL has no isnan/isinf; Wine's d3dcompiler_47 (vkd3d-shader HLSL) does
// not implement isnan either, so the D3D11 leg shares the magnitude test
// (equivalent: NaN fails any comparison, |inf| exceeds FLT_MAX).
#if defined(SNAIL_TARGET_WGSL) || defined(SNAIL_TARGET_D3D11)
public bool snailAhFinite(float v) { return abs(v) <= 3.402823e38; }
#else
public bool snailAhFinite(float v) { return !isnan(v) && !isinf(v); }
#endif

// Records are addressed as a linear texel run that may wrap rows. The width is
// an ABI constant, so no texture-size query sits in front of every load.
public int2 snailAhLayerLoc(SnailFloatTexture2D layer_tex, int2 base, int offset) {
    int texel = base.y * SNAIL_PAINT_INFO_WIDTH + base.x + offset;
    return int2(texel % SNAIL_PAINT_INFO_WIDTH, texel / SNAIL_PAINT_INFO_WIDTH);
}

public float snailWarpF(SnailFloatTexture2D layer_tex, int2 info_base, int block, int i) {
    int f = block + i;
    float4 t = layer_tex.Load(int3(snailAhLayerLoc(layer_tex, info_base, f >> 2), 0));
    int c = f & 3;
    return (c == 0) ? t.x : ((c == 1) ? t.y : ((c == 2) ? t.z : t.w));
}

public bool snailAhCount(int max_knots, float encoded, out int count) {
    if (!snailAhFinite(encoded) || encoded < 0.0 || encoded > float(max_knots) || floor(encoded) != encoded) {
        count = 0;
        return false;
    }
    count = int(encoded);
    return true;
}

// Decode a binary16 value using only uint32/float32 operations. Slang's
// f16tof32 intrinsic requires native Int16 + FP16 arithmetic, which is not
// part of baseline GL 3.3 or GLES 3.0. Every binary16 value is exactly representable as an
// f32, including subnormals. Preserve infinities and NaNs so the policy's
// finite-value validation keeps rejecting corrupt/non-finite payloads.
public bool snailDecodeAutohintPolicy(uint4 words, out SnailAutohintPolicy p) {
    p = (SnailAutohintPolicy)0;
    uint config = words.x;
    if ((config & ~0x1fffffffu) != 0u || (words.w >> 16u) != 0u) return false;
    p.xAlign = int(config & 3u);
    p.xStem = int((config >> 2u) & 3u);
    p.xPositioning = int((config >> 4u) & 3u);
    p.xRegistration = int((config >> 6u) & 3u);
    p.yAlign = int((config >> 8u) & 3u);
    p.yStem = int((config >> 10u) & 3u);
    p.yOvershoot = int((config >> 12u) & 3u);
    p.fadeEnabled = int((config >> 14u) & 1u);
    p.fadeStart = float((config >> 15u) & 0x7fu);
    p.fadeFull = float((config >> 22u) & 0x7fu);
    if (p.xAlign > 1 || p.xStem > 2 || p.xPositioning > 1 ||
        p.xRegistration > 1 || p.yAlign > 2 || p.yStem > 2 || p.yOvershoot > 1)
        return false;
    p.xRatio = snailDecodeFloat16Exact(words.y);
    p.xMaxPx = snailDecodeFloat16Exact(words.y >> 16u);
    p.yRatio = snailDecodeFloat16Exact(words.z);
    p.yMaxPx = snailDecodeFloat16Exact(words.z >> 16u);
    p.overshootMinPx = snailDecodeFloat16Exact(words.w);
    if ((p.xStem != 0 && (!snailAhFinite(p.xRatio) || p.xRatio < 0.0)) ||
        (p.xStem == 1 && (!snailAhFinite(p.xMaxPx) || p.xMaxPx < 0.0)) ||
        (p.yStem != 0 && (!snailAhFinite(p.yRatio) || p.yRatio < 0.0)) ||
        (p.yStem == 1 && (!snailAhFinite(p.yMaxPx) || p.yMaxPx < 0.0)) ||
        (p.yOvershoot == 1 && (!snailAhFinite(p.overshootMinPx) || p.overshootMinPx < 0.0)) ||
        (p.xPositioning == 1 && p.xAlign == 0) ||
        (p.yOvershoot == 1 && p.yAlign != 2)) return false;
    return true;
}

public float snailAhSnap(float v, float scale) { return round(v * scale) / scale; }
public float snailAhStandardWidth(float raw, float standard, float ratio) {
    return (standard > 0.0 && abs(raw - standard) <= ratio * standard) ? standard : raw;
}

// Feature facts are immutable slab data, not independent transient state.
// Preserve their packed record representation in one private table rather than
// splitting them across a dozen 16/32-element arrays.
public struct SnailAhFeature {
    public float pos;
    public float width;
    public int stem;
    public int blue;
    public uint flags;
};

// One feature is four consecutive floats. A run's alignment within a texel is
// the same for every feature, so this is two texel loads at most.
public float4 snailAhFeatureData(
    SnailFloatTexture2D layer_tex, int2 info_base, int run, int i
) {
    int f = run + 1 + 4 * i;
    int c = f & 3;
    float4 a = layer_tex.Load(int3(snailAhLayerLoc(layer_tex, info_base, f >> 2), 0));
    if (c == 0) return a;
    float4 b = layer_tex.Load(int3(snailAhLayerLoc(layer_tex, info_base, (f >> 2) + 1), 0));
    return (c == 1) ? float4(a.yzw, b.x) : ((c == 2) ? float4(a.zw, b.xy) : float4(a.w, b.xyz));
}

public SnailAhFeature snailAhFeature(float4 data) {
    SnailAhFeature feature;
    feature.pos = data.x;
    feature.width = data.y;
    uint refs = asuint(data.z);
    feature.stem = int(refs << 16u) >> 16;
    feature.blue = int(refs) >> 16;
    feature.flags = asuint(data.w);
    return feature;
}

public uint snailAhBit(int i) { return 1u << uint(i); }
public bool snailAhBitSet(uint mask, int i) { return (mask & snailAhBit(i)) != 0u; }

// ── Register-resident fit tables ──
//
// The fit keeps per-feature state in 16-slot tables held as four 4-vectors.
// Every access selects the vector and lane from the slot index, so a table is
// only ever indexed by constants. A dynamically indexed array would be placed
// in local memory, and its mere presence in the vertex shader costs every
// vertex invocation — including the three per quad that never run the fit.

public static const int SNAIL_AH_KNOT_SLOTS = 16;
// Knot-mask bit for the left-bearing registration knot, which precedes every
// feature knot and carries its own target.
public static const uint SNAIL_AH_LEFT_KNOT = 0x10000u;

float snailAhLane(float4 v, int lane) {
    return lane == 0 ? v.x : (lane == 1 ? v.y : (lane == 2 ? v.z : v.w));
}

uint snailAhLaneU(uint4 v, int lane) {
    return lane == 0 ? v.x : (lane == 1 ? v.y : (lane == 2 ? v.z : v.w));
}

float snailAhTableGet(float4 table[4], int idx) {
    int w = idx >> 2;
    float4 v = w == 0 ? table[0] : (w == 1 ? table[1] : (w == 2 ? table[2] : table[3]));
    return snailAhLane(v, idx & 3);
}

uint snailAhTableGetU(uint4 table[4], int idx) {
    int w = idx >> 2;
    uint4 v = w == 0 ? table[0] : (w == 1 ? table[1] : (w == 2 ? table[2] : table[3]));
    return snailAhLaneU(v, idx & 3);
}

void snailAhTableSet(inout float4 table[4], int idx, float value) {
    bool4 lane = int4(0, 1, 2, 3) == int4(idx & 3);
    int w = idx >> 2;
    table[0] = select(lane && bool4(w == 0), float4(value), table[0]);
    table[1] = select(lane && bool4(w == 1), float4(value), table[1]);
    table[2] = select(lane && bool4(w == 2), float4(value), table[2]);
    table[3] = select(lane && bool4(w == 3), float4(value), table[3]);
}

// GLSL 3.30 has no integer-vector select (mix over uvec is 4.50), so the
// unsigned table selects per lane.
uint4 snailAhSelectLaneU(uint4 v, bool hit, int lane, uint value) {
    return uint4(hit && lane == 0 ? value : v.x, hit && lane == 1 ? value : v.y,
                 hit && lane == 2 ? value : v.z, hit && lane == 3 ? value : v.w);
}

void snailAhTableSetU(inout uint4 table[4], int idx, uint value) {
    int lane = idx & 3;
    int w = idx >> 2;
    table[0] = snailAhSelectLaneU(table[0], w == 0, lane, value);
    table[1] = snailAhSelectLaneU(table[1], w == 1, lane, value);
    table[2] = snailAhSelectLaneU(table[2], w == 2, lane, value);
    table[3] = snailAhSelectLaneU(table[3], w == 3, lane, value);
}

// Per-feature semantics the fit needs after validation, packed in one word:
// stem+1 [0..4], blue+1 [5..9], round [10], natural-width companion [11],
// negative blue direction [12], this axis's encoded companion [13..18].
uint snailAhPackMeta(SnailAhFeature f, bool useBlues) {
    uint companion = (f.flags >> (useBlues ? 10u : 4u)) & 63u;
    return uint(f.stem + 1) | (uint(f.blue + 1) << 5u) | ((f.flags & 1u) << 10u) |
        ((f.flags & 2u) << 10u) | ((f.flags & 8u) << 9u) | (companion << 13u);
}
int snailAhMetaStem(uint m) { return int(m & 31u) - 1; }
int snailAhMetaBlue(uint m) { return int((m >> 5u) & 31u) - 1; }
bool snailAhMetaRound(uint m) { return (m & (1u << 10u)) != 0u; }
bool snailAhMetaNaturalWidth(uint m) { return (m & (1u << 11u)) != 0u; }
bool snailAhMetaBlueDirNegative(uint m) { return (m & (1u << 12u)) != 0u; }
int snailAhMetaCompanion(uint m) { return int((m >> 13u) & 63u); }

// One axis's fitted warp. Knots live in feature slots: bit c of `mask` marks
// feature c as a knot with target slot c of `targets` (its base is the
// feature's record position). `mask == 0` is the identity warp.
public struct SnailAhAxisFit {
    public float4 targets[4];
    public uint mask;
    public float leftTarget;
};

SnailAhAxisFit snailAhIdentityFit() {
    SnailAhAxisFit fit;
    for (int w = 0; w < 4; ++w) fit.targets[w] = float4(0.0);
    fit.mask = 0u;
    fit.leftTarget = 0.0;
    return fit;
}

// Reads one immutable feature run and derives the transient warp. `axis` is
// 0=x, 1=y. Invalid records, and runs over SNAIL_AH_KNOT_SLOTS features or
// blue zones, fit to the identity (unhinted). Semantics mirror
// snail-raster/autohint_warp.zig fitAxis; knots are reported per feature slot
// rather than compacted. Counts are validated before they bound a loop;
// keeping the data-dependent count in the condition avoids fixed-bound unroll
// explosions in desktop GL linkers.
public SnailAhAxisFit snailFitAutohintAxis(
    SnailFloatTexture2D layer_tex, int2 info_base,
    int axis, int run, int blueCount, float standardWidth, float left,
    float scale, SnailAutohintPolicy policy
) {
    SnailAhAxisFit fit = snailAhIdentityFit();
    if (!snailAhFinite(scale) || scale <= 0.0 || blueCount < 0 || blueCount > SNAIL_AH_KNOT_SLOTS ||
        !snailAhFinite(standardWidth) || standardWidth < 0.0) return fit;
    if ((axis == 0 && policy.xAlign == 0 && policy.xStem == 0 && policy.xPositioning == 0 && policy.xRegistration == 0) ||
        (axis == 1 && policy.yAlign == 0 && policy.yStem == 0 && policy.yOvershoot == 0)) return fit;

    int n = int(snailWarpF(layer_tex, info_base, run, 0));
    if (n <= 0 || n > SNAIL_AH_KNOT_SLOTS) return fit;
    bool useBlues = axis == 1 && policy.yAlign == 2;
    if (axis == 0 && policy.xRegistration == 1 && !snailAhFinite(left)) return fit;

    float4 pos[4];
    uint4 meta[4];
    for (int w = 0; w < 4; ++w) { pos[w] = float4(0.0); meta[w] = uint4(0u); }
    for (int i = 0; i < n; ++i) {
        SnailAhFeature feature = snailAhFeature(snailAhFeatureData(layer_tex, info_base, run, i));
        if ((feature.flags & 4u) == 0u) return fit;
        int encodedCompanion = int((feature.flags >> (useBlues ? 10u : 4u)) & 63u);
        bool rounded = (feature.flags & 1u) != 0u;
        if (encodedCompanion >= 63 && rounded && feature.blue >= 0) return fit;
        if (encodedCompanion >= n && encodedCompanion < 62) return fit;
        if (!snailAhFinite(feature.pos) || !snailAhFinite(feature.width) || feature.width < 0.0 ||
            feature.stem < -1 || feature.stem >= n ||
            feature.blue < -1 || feature.blue >= blueCount) return fit;
        snailAhTableSet(pos, i, feature.pos);
        snailAhTableSetU(meta, i, snailAhPackMeta(feature, useBlues));
    }
    for (int i = 0; i < blueCount; ++i) {
        float ref = snailWarpF(layer_tex, info_base, 12, 2 * i);
        float shoot = snailWarpF(layer_tex, info_base, 12, 2 * i + 1);
        if (!snailAhFinite(ref) || !snailAhFinite(shoot)) return fit;
    }

    float overshootLimit = (axis == 1 && policy.yOvershoot == 1) ? policy.overshootMinPx : 0.0;
    float4 targets[4];
    for (int w = 0; w < 4; ++w) targets[w] = float4(0.0);
    for (int i = 0; i < n; ++i) {
        uint m = snailAhTableGetU(meta, i);
        float p = snailAhTableGet(pos, i);
        int blue = snailAhMetaBlue(m);
        bool round = snailAhMetaRound(m);
        float target;
        if (useBlues && blue >= 0) {
            // Preserve (y overshoot policy == 0): keep a round apex at its natural
            // position so the curve AA's into a round top instead of crushing flat
            // onto the snapped blue row. Suppress snaps it (crisper, flat).
            if (round && axis == 1 && policy.yOvershoot == 0) {
                target = p;
            } else {
                float ref = snailWarpF(layer_tex, info_base, 12, 2 * blue);
                float shoot = snailWarpF(layer_tex, info_base, 12, 2 * blue + 1);
                target = snailAhSnap(ref, scale);
                if (round && abs((shoot - ref) * scale) >= overshootLimit)
                    target += shoot - ref;
            }
        } else {
            target = snailAhSnap(p, scale);
        }
        snailAhTableSet(targets, i, target);
    }

    float grid = 1.0 / scale;
    int stemMode = axis == 0 ? policy.xStem : policy.yStem;
    float ratio = axis == 0 ? policy.xRatio : policy.yRatio;
    float maxPx = axis == 0 ? policy.xMaxPx : policy.yMaxPx;
    bool axisAligned = axis == 0 ? policy.xAlign != 0 : policy.yAlign != 0;
    bool alignPositions = axis == 0 ? policy.xAlign == 1 : policy.yAlign != 0;
    bool relative = axis == 0 && policy.xPositioning == 1;
    uint hintedMask = 0u;
    bool anchorSet = false;
    float anchorBase = 0.0;
    float anchorTarget = 0.0;
    float clusterBase = 0.0;
    float clusterTarget = 0.0;
    float clusterRightTarget = 0.0;
    float clusterDesiredRight = 0.0;
    int clusterStems = 0;
    // Stems in lower-edge order. Each feature belongs to at most one stem, so
    // the upper edge's target is written exactly once, here.
    for (int i = 0; i < n; ++i) {
        uint m = snailAhTableGetU(meta, i);
        int j = snailAhMetaStem(m);
        if (j <= i) continue;
        float lowerPos = snailAhTableGet(pos, i);
        float lowerTarget = snailAhTableGet(targets, i);
        float lowerWidth = snailWarpF(layer_tex, info_base, run + 1 + 4 * i, 1);
        float nominal = snailAhStandardWidth(lowerWidth, standardWidth, ratio);
        float widthUnits = lowerWidth;
        if (stemMode == 2 || (stemMode == 1 && nominal * scale < maxPx))
            widthUnits = max(round(nominal * scale), 1.0) * grid;
        if (relative) {
            if (anchorSet) lowerTarget = anchorTarget + round((lowerPos - anchorBase) * scale) * grid;
            else {
                lowerTarget = snailAhSnap(lowerPos, scale);
                anchorSet = true;
                clusterBase = lowerPos;
                clusterTarget = lowerTarget;
            }
            float upperTarget = lowerTarget + widthUnits;
            snailAhTableSet(targets, j, upperTarget);
            anchorBase = lowerPos;
            anchorTarget = lowerTarget;
            clusterRightTarget = upperTarget;
            clusterDesiredRight = clusterTarget + round((lowerPos - clusterBase) * scale) * grid + widthUnits;
            clusterStems += 1;
        } else {
            bool lowerBlue = axisAligned && snailAhMetaBlue(m) >= 0;
            bool upperBlue = axisAligned && snailAhMetaBlue(snailAhTableGetU(meta, j)) >= 0;
            if (!alignPositions) lowerTarget = lowerPos;
            if (upperBlue && !lowerBlue && alignPositions) lowerTarget = snailAhTableGet(targets, j) - widthUnits;
            else snailAhTableSet(targets, j, lowerTarget + widthUnits);
        }
        snailAhTableSet(targets, i, lowerTarget);
        hintedMask |= snailAhBit(i) | snailAhBit(j);
    }
    if (relative && clusterStems > 1) {
        float shift = clusterDesiredRight - clusterRightTarget;
        for (int i = 0; i < n; ++i) {
            if (snailAhBitSet(hintedMask, i)) snailAhTableSet(targets, i, snailAhTableGet(targets, i) + shift);
        }
    }

    // Preserve the weight next to a round blue-zone apex.
    float companionMax = stemMode == 1 ? maxPx : 1.6;
    for (int i = 0; i < n; ++i) {
        uint m = snailAhTableGetU(meta, i);
        if (!axisAligned || snailAhMetaBlue(m) < 0 || !snailAhMetaRound(m) ||
            snailAhBitSet(hintedMask, i)) continue;
        float apexPos = snailAhTableGet(pos, i);
        bool top;
        if (useBlues) {
            top = !snailAhMetaBlueDirNegative(m);
        } else {
            int partner = snailAhMetaStem(m);
            bool partnerAbove = partner >= 0 && snailAhTableGet(pos, partner) > apexPos;
            top = !partnerAbove;
        }
        int encodedCompanion = snailAhMetaCompanion(m);
        int best = encodedCompanion >= 62 ? -1 : encodedCompanion;
        if (best < 0 || snailAhBitSet(hintedMask, best)) continue;
        uint mateMeta = snailAhTableGetU(meta, best);
        float matePos = snailAhTableGet(pos, best);
        float bestGap = top ? apexPos - matePos : matePos - apexPos;
        if (snailAhMetaBlue(mateMeta) >= 0 || bestGap * scale >= companionMax) continue;
        float widthUnits = snailAhMetaNaturalWidth(mateMeta) ?
            bestGap : max(round(bestGap * scale), 1.0) * grid;
        float apexTarget = snailAhTableGet(targets, i);
        snailAhTableSet(targets, best, top ? apexTarget - widthUnits : apexTarget + widthUnits);
        hintedMask |= snailAhBit(best);
    }

    // Knots are the hinted features plus every aligned blue-linked feature;
    // blue-linked knots stay fixed during collision resolution.
    uint knotMask = 0u;
    uint blueFixedMask = 0u;
    int knotCount = 0;
    int firstKnot = -1;
    for (int i = n - 1; i >= 0; --i) {
        bool blueFixed = axisAligned && snailAhMetaBlue(snailAhTableGetU(meta, i)) >= 0;
        if (!snailAhBitSet(hintedMask, i) && !blueFixed) continue;
        knotMask |= snailAhBit(i);
        if (blueFixed) blueFixedMask |= snailAhBit(i);
        knotCount += 1;
        firstKnot = i;
    }
    bool hasLeft = false;
    float leftTarget = 0.0;
    if (axis == 0 && policy.xRegistration == 1 && knotCount > 0 && knotCount < SNAIL_AH_KNOT_SLOTS &&
        left < snailAhTableGet(pos, firstKnot) - 0.25 * grid) {
        hasLeft = true;
        leftTarget = snailAhSnap(left, scale);
    }

    // Collision resolution in knot order (left knot first). Minimum spacings
    // are the pre-resolution gaps, so the unresolved targets stay alongside.
    float4 settled[4] = targets;
    float settledLeft = leftTarget;
    // Keep shared blue-zone targets fixed. If quantized interior features run
    // out of room below one, resolve their collisions inward while preserving
    // fitted stem widths and allowing impossible counters to collapse. Every
    // non-fixed knot with a fixed knot anywhere above it is pulled down.
    bool fixedAbove = false;
    bool havePrev = false;
    float prevSettled = 0.0;
    float prevTarget = 0.0;
    for (int i = n - 1; i >= 0; --i) {
        if (!snailAhBitSet(knotMask, i)) continue;
        bool fixedHere = snailAhBitSet(blueFixedMask, i);
        float target = snailAhTableGet(targets, i);
        float current = snailAhTableGet(settled, i);
        if (havePrev && fixedAbove && !fixedHere) {
            current = min(current, prevSettled - max(prevTarget - target, 1e-6));
            snailAhTableSet(settled, i, current);
        }
        if (fixedHere) fixedAbove = true;
        havePrev = true;
        prevSettled = current;
        prevTarget = target;
    }
    if (hasLeft && fixedAbove)
        settledLeft = min(settledLeft, prevSettled - max(prevTarget - leftTarget, 1e-6));
    havePrev = hasLeft;
    prevSettled = settledLeft;
    prevTarget = leftTarget;
    for (int i = 0; i < n; ++i) {
        if (!snailAhBitSet(knotMask, i)) continue;
        float target = snailAhTableGet(targets, i);
        float current = snailAhTableGet(settled, i);
        if (havePrev) {
            float required = prevSettled + max(target - prevTarget, 1e-6);
            if (current < required) {
                current = required;
                snailAhTableSet(settled, i, current);
            }
        }
        havePrev = true;
        prevSettled = current;
        prevTarget = target;
    }

    // Fade to identity at large ppem — autohinting is a small-size tool, so above
    // the policy's fade start blend each knot's target back toward its natural
    // base, reaching no-warp by fadeFull (mirror of warp.zig fadeToIdentity;
    // blending toward the sorted base preserves monotonicity). `scale` is this
    // axis's pixels-per-em. The caller owns the range via AutohintPolicy.fade.
    if (policy.fadeEnabled != 0 && scale > policy.fadeStart) {
        float span = policy.fadeFull - policy.fadeStart;
        float fadeW = (span <= 0.0 || scale >= policy.fadeFull) ? 1.0 : (scale - policy.fadeStart) / span;
        for (int i = 0; i < n; ++i) {
            if (!snailAhBitSet(knotMask, i)) continue;
            float current = snailAhTableGet(settled, i);
            snailAhTableSet(settled, i, current + (snailAhTableGet(pos, i) - current) * fadeW);
        }
        settledLeft += (left - settledLeft) * fadeW;
    }
    for (int i = 0; i < n; ++i) {
        if (snailAhBitSet(knotMask, i) && !snailAhFinite(snailAhTableGet(settled, i))) return fit;
    }
    if (hasLeft && !snailAhFinite(settledLeft)) return fit;

    fit.targets = settled;
    fit.mask = knotMask | (hasLeft ? SNAIL_AH_LEFT_KNOT : 0u);
    fit.leftTarget = hasLeft ? settledLeft : 0.0;
    return fit;
}
