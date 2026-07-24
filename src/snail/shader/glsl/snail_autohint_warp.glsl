// Transient autohint fitting. This is a bounded GLSL port of
// font/autohint/warp.zig fitAxis + inverseWarp. Immutable slab records contain
// feature facts only; targets below exist only for the current draw invocation.

#ifndef SNAIL_AUTOHINT_VERTEX
// NVIDIA otherwise speculatively unrolls the complete 32-knot exceptional
// fitter during glLinkProgram. Keep the normal vertex fitter under the
// driver's default policy: it is hot (once per glyph instance), while this
// fragment copy runs only for oversized records or perspective projection.
// Other GLSL implementations ignore an unrecognized implementation pragma.
#pragma optionNV(unroll none)
#endif

#ifdef SNAIL_AUTOHINT_VERTEX
const int SNAIL_AH_MAX_KNOTS = 16;
#else
const int SNAIL_AH_MAX_KNOTS = 32;
#endif
const int SNAIL_AH_LEFT_SOURCE = 32;

// Implemented by the caller's vertex or fragment stage for layer-info access.
float snailWarpF(int block, int i);

struct SnailAutohintPolicy {
    int xAlign;
    int xStem;
    int xPositioning;
    int xRegistration;
    int yAlign;
    int yStem;
    int yOvershoot;
    int fadeEnabled;
    float fadeStart;
    float fadeFull;
    float xRatio;
    float xMaxPx;
    float yRatio;
    float yMaxPx;
    float overshootMinPx;
};

#ifdef SNAIL_WGSL
// WGSL has no isnan/isinf (NaN semantics are implementation-defined there); an
// abs() range check classifies NaN (any comparison is false) and ±inf alike.
bool snailAhFinite(float v) { return abs(v) <= 3.402823e38; }
#else
bool snailAhFinite(float v) { return !isnan(v) && !isinf(v); }
#endif

bool snailAhCount(float encoded, out int count) {
    if (!snailAhFinite(encoded) || encoded < 0.0 || encoded > float(SNAIL_AH_MAX_KNOTS) || floor(encoded) != encoded) {
        count = 0;
        return false;
    }
    count = int(encoded);
    return true;
}

// Decode a binary16 value using only uint32/float32 operations.
// unpackHalf2x16 is not core in GLSL 3.30 (it needs GLSL 4.20 or
// GL_ARB_shading_language_packing), so spell the decode out — mirror of
// autohint_warp.slang snailAhDecodeFloat16. Every binary16 value is exactly
// representable as an f32, including subnormals. Preserve infinities and NaNs
// so the policy's finite-value validation keeps rejecting corrupt payloads.
float snailAhDecodeFloat16(uint bits) {
    bits &= 0xffffu;
    uint sign = (bits & 0x8000u) << 16u;
    uint exponent = (bits >> 10u) & 31u;
    uint fraction = bits & 1023u;
    if (exponent == 0u) {
        if (fraction == 0u) return uintBitsToFloat(sign);
        float magnitude = float(fraction) * 5.960464477539063e-8;
        return sign == 0u ? magnitude : -magnitude;
    }
    if (exponent == 31u)
        return uintBitsToFloat(sign | 0x7f800000u | (fraction << 13u));
    return uintBitsToFloat(sign | ((exponent + 112u) << 23u) | (fraction << 13u));
}

bool snailDecodeAutohintPolicy(uvec4 words, out SnailAutohintPolicy p) {
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
    p.xRatio = snailAhDecodeFloat16(words.y);
    p.xMaxPx = snailAhDecodeFloat16(words.y >> 16u);
    p.yRatio = snailAhDecodeFloat16(words.z);
    p.yMaxPx = snailAhDecodeFloat16(words.z >> 16u);
    p.overshootMinPx = snailAhDecodeFloat16(words.w);
    if ((p.xStem != 0 && (!snailAhFinite(p.xRatio) || p.xRatio < 0.0)) ||
        (p.xStem == 1 && (!snailAhFinite(p.xMaxPx) || p.xMaxPx < 0.0)) ||
        (p.yStem != 0 && (!snailAhFinite(p.yRatio) || p.yRatio < 0.0)) ||
        (p.yStem == 1 && (!snailAhFinite(p.yMaxPx) || p.yMaxPx < 0.0)) ||
        (p.yOvershoot == 1 && (!snailAhFinite(p.overshootMinPx) || p.overshootMinPx < 0.0)) ||
        (p.xPositioning == 1 && p.xAlign == 0) ||
        (p.yOvershoot == 1 && p.yAlign != 2)) return false;
    return true;
}

float snailAhSnap(float v, float scale) { return round(v * scale) / scale; }
float snailAhStandardWidth(float raw, float standard, float ratio) {
    return (standard > 0.0 && abs(raw - standard) <= ratio * standard) ? standard : raw;
}

// Feature facts are immutable slab data, not independent transient state.
// Preserve their packed record representation in one private table rather than
// splitting them across a dozen 16/32-element arrays. This keeps desktop
// linkers from scalarizing every field into every fitter pass.
struct SnailAhFeature {
    float pos;
    float width;
    int stem;
    int blue;
    uint flags;
};

vec4 snailAhFeatureData(int run, int i) {
    int f = run + 1 + 4 * i;
    return vec4(
        snailWarpF(f, 0),
        snailWarpF(f, 1),
        snailWarpF(f, 2),
        snailWarpF(f, 3)
    );
}

SnailAhFeature snailAhFeature(vec4 data) {
    SnailAhFeature feature;
    feature.pos = data.x;
    feature.width = data.y;
    uint refs = floatBitsToUint(data.z);
    feature.stem = int(refs << 16u) >> 16;
    feature.blue = int(refs) >> 16;
    feature.flags = floatBitsToUint(data.w);
    return feature;
}

uint snailAhBit(int i) { return 1u << uint(i); }
bool snailAhBitSet(uint mask, int i) { return (mask & snailAhBit(i)) != 0u; }

// Reads one immutable feature run and derives transient knots. `axis` is 0=x,
// 1=y. Counts are validated against SNAIL_AH_MAX_KNOTS before they bound a
// loop. Keeping the count in the loop condition is important: fixed-bound
// loops with an internal break invite desktop drivers to unroll the complete
// 16/32-element fitter (including its nested searches) during program link.
bool snailFitAutohintAxis(
    int axis, int run, int blueCount, float standardWidth, float left,
    float scale, SnailAutohintPolicy policy,
    out int knotCount, out float knotBase[SNAIL_AH_MAX_KNOTS],
    out float knotTarget[SNAIL_AH_MAX_KNOTS],
    out int knotSource[SNAIL_AH_MAX_KNOTS]
) {
    knotCount = 0;
    if (!snailAhFinite(scale) || scale <= 0.0 || blueCount < 0 || blueCount > SNAIL_AH_MAX_KNOTS ||
        !snailAhFinite(standardWidth) || standardWidth < 0.0) return false;
    if ((axis == 0 && policy.xAlign == 0 && policy.xStem == 0 && policy.xPositioning == 0 && policy.xRegistration == 0) ||
        (axis == 1 && policy.yAlign == 0 && policy.yStem == 0 && policy.yOvershoot == 0)) return true;

    int n = int(snailWarpF(run, 0));
    if (n <= 0 || n > SNAIL_AH_MAX_KNOTS) return n == 0;
    bool useBlues = axis == 1 && policy.yAlign == 2;
    if (axis == 0 && policy.xRegistration == 1 && !snailAhFinite(left)) return false;

    vec4 featureData[SNAIL_AH_MAX_KNOTS];
    float targets[SNAIL_AH_MAX_KNOTS];
    uint hintedMask = 0u;
    uint knotBlueFixedMask = 0u;
    uint knotNaturalSpacingMask = 0u;
    for (int i = 0; i < n; ++i) {
        featureData[i] = snailAhFeatureData(run, i);
        SnailAhFeature feature = snailAhFeature(featureData[i]);
        if ((feature.flags & 4u) == 0u) return false;
        int encodedCompanion = int((feature.flags >> (useBlues ? 10u : 4u)) & 63u);
        bool rounded = (feature.flags & 1u) != 0u;
        if (encodedCompanion >= 63 && rounded && feature.blue >= 0) return false;
        if (!snailAhFinite(feature.pos) || !snailAhFinite(feature.width) || feature.width < 0.0 ||
            feature.stem < -1 || feature.stem >= n ||
            feature.blue < -1 || feature.blue >= blueCount) return false;
    }
    for (int i = 0; i < blueCount; ++i) {
        float ref = snailWarpF(12, 2 * i);
        float shoot = snailWarpF(12, 2 * i + 1);
        if (!snailAhFinite(ref) || !snailAhFinite(shoot)) return false;
    }
    float overshootLimit = (axis == 1 && policy.yOvershoot == 1) ? policy.overshootMinPx : 0.0;
    for (int i = 0; i < n; ++i) {
        SnailAhFeature feature = snailAhFeature(featureData[i]);
        bool validBlue = useBlues && feature.blue >= 0;
        if (validBlue) {
            float ref = snailWarpF(12, 2 * feature.blue);
            float shoot = snailWarpF(12, 2 * feature.blue + 1);
            // Preserve (y overshoot policy == 0): keep a round apex at its natural
            // position so the curve AA's into a round top instead of crushing flat
            // onto the snapped blue row. Suppress snaps it (crisper, flat).
            if ((feature.flags & 1u) != 0u && axis == 1 && policy.yOvershoot == 0) {
                targets[i] = feature.pos;
            } else {
                targets[i] = snailAhSnap(ref, scale);
                if ((feature.flags & 1u) != 0u && abs((shoot - ref) * scale) >= overshootLimit)
                    targets[i] += shoot - ref;
            }
        } else {
            targets[i] = snailAhSnap(feature.pos, scale);
        }
    }

    float grid = 1.0 / scale;
    int stemMode = axis == 0 ? policy.xStem : policy.yStem;
    float ratio = axis == 0 ? policy.xRatio : policy.yRatio;
    float maxPx = axis == 0 ? policy.xMaxPx : policy.yMaxPx;
    bool alignPositions = axis == 0 ? policy.xAlign == 1 : policy.yAlign != 0;
    bool relative = axis == 0 && policy.xPositioning == 1;
    bool anchorSet = false;
    float anchorBase = 0.0;
    float anchorTarget = 0.0;
    float clusterBase = 0.0;
    float clusterTarget = 0.0;
    int clusterRight = 0;
    float clusterDesiredRight = 0.0;
    int clusterStems = 0;
    for (int i = 0; i < n; ++i) {
        SnailAhFeature lower = snailAhFeature(featureData[i]);
        int j = lower.stem;
        if (j < 0 || j <= i) continue;
        SnailAhFeature upper = snailAhFeature(featureData[j]);
        float nominal = snailAhStandardWidth(lower.width, standardWidth, ratio);
        float widthUnits = lower.width;
        if (stemMode == 2 || (stemMode == 1 && nominal * scale < maxPx))
            widthUnits = max(round(nominal * scale), 1.0) * grid;
        if (relative) {
            if (anchorSet) targets[i] = anchorTarget + round((lower.pos - anchorBase) * scale) * grid;
            else {
                targets[i] = snailAhSnap(lower.pos, scale);
                anchorSet = true;
                clusterBase = lower.pos;
                clusterTarget = targets[i];
            }
            targets[j] = targets[i] + widthUnits;
            anchorBase = lower.pos;
            anchorTarget = targets[i];
            clusterRight = j;
            clusterDesiredRight = clusterTarget + round((lower.pos - clusterBase) * scale) * grid + widthUnits;
            clusterStems += 1;
        } else {
            bool axisAligned = axis == 0 ? policy.xAlign != 0 : policy.yAlign != 0;
            bool lowerBlue = axisAligned && lower.blue >= 0;
            bool upperBlue = axisAligned && upper.blue >= 0;
            if (!alignPositions) targets[i] = lower.pos;
            if (upperBlue && !lowerBlue && alignPositions) targets[i] = targets[j] - widthUnits;
            else targets[j] = targets[i] + widthUnits;
        }
        hintedMask |= snailAhBit(i) | snailAhBit(j);
    }
    if (relative && clusterStems > 1) {
        float shift = clusterDesiredRight - targets[clusterRight];
        for (int i = 0; i < n; ++i) {
            if (snailAhBitSet(hintedMask, i)) targets[i] += shift;
        }
    }

    // Preserve the weight next to a round blue-zone apex.
    float companionMax = stemMode == 1 ? maxPx : 1.6;
    for (int i = 0; i < n; ++i) {
        bool axisAligned = axis == 0 ? policy.xAlign != 0 : policy.yAlign != 0;
        SnailAhFeature apex = snailAhFeature(featureData[i]);
        if (!axisAligned || apex.blue < 0 || (apex.flags & 1u) == 0u ||
            snailAhBitSet(hintedMask, i)) continue;
        bool top;
        if (useBlues) {
            top = (apex.flags & 8u) == 0u;
        } else {
            bool partnerAbove = apex.stem >= 0 && snailAhFeature(featureData[apex.stem]).pos > apex.pos;
            top = !partnerAbove;
        }
        int encodedCompanion = int((apex.flags >> (useBlues ? 10u : 4u)) & 63u);
        int best = encodedCompanion >= 62 ? -1 : encodedCompanion;
        if (best < 0 || snailAhBitSet(hintedMask, best)) continue;
        SnailAhFeature mate = snailAhFeature(featureData[best]);
        float bestGap = top ? apex.pos - mate.pos : mate.pos - apex.pos;
        if (mate.blue >= 0 || bestGap * scale >= companionMax) continue;
        float widthUnits = (mate.flags & 2u) != 0u ?
            bestGap : max(round(bestGap * scale), 1.0) * grid;
        targets[best] = top ? targets[i] - widthUnits : targets[i] + widthUnits;
        hintedMask |= snailAhBit(best);
    }
    for (int i = 0; i < n; ++i) {
        bool axisAligned = axis == 0 ? policy.xAlign != 0 : policy.yAlign != 0;
        SnailAhFeature feature = snailAhFeature(featureData[i]);
        if (!snailAhBitSet(hintedMask, i) && !(axisAligned && feature.blue >= 0)) continue;
        knotBase[knotCount] = feature.pos;
        knotTarget[knotCount] = targets[i];
        if (axisAligned && feature.blue >= 0) knotBlueFixedMask |= snailAhBit(knotCount);
        if ((feature.flags & 2u) != 0u) knotNaturalSpacingMask |= snailAhBit(knotCount);
        knotSource[knotCount] = i;
        ++knotCount;
    }
    if (axis == 0 && policy.xRegistration == 1 && knotCount > 0 && knotCount < SNAIL_AH_MAX_KNOTS &&
        left < knotBase[0] - 0.25 * grid) {
        for (int i = knotCount; i > 0; --i) {
            knotBase[i] = knotBase[i - 1];
            knotTarget[i] = knotTarget[i - 1];
            knotSource[i] = knotSource[i - 1];
        }
        knotBlueFixedMask <<= 1u;
        knotNaturalSpacingMask <<= 1u;
        knotBase[0] = left;
        knotTarget[0] = snailAhSnap(left, scale);
        knotSource[0] = SNAIL_AH_LEFT_SOURCE;
        ++knotCount;
    }
    // Keep shared blue-zone targets fixed. If quantized interior features run
    // out of room below one, resolve their collisions inward before the
    // generic forward monotonicity repair can push the blue edge outward.
    for (int b = knotCount - 1; b > 0; --b) {
        if (!snailAhBitSet(knotBlueFixedMask, b)) continue;
        for (int j = b; j > 0; --j) {
            if (snailAhBitSet(knotBlueFixedMask, j - 1)) break;
            float spacing = snailAhBitSet(knotNaturalSpacingMask, j - 1) ? 1e-6 : grid;
            knotTarget[j - 1] = min(knotTarget[j - 1], knotTarget[j] - spacing);
        }
    }
    for (int i = 1; i < knotCount; ++i) {
        if (knotTarget[i] <= knotTarget[i - 1]) knotTarget[i] = knotTarget[i - 1] + grid;
    }
    // Fade to identity at large ppem — autohinting is a small-size tool, so above
    // the policy's fade start blend each knot's target back toward its natural
    // base, reaching no-warp by fadeFull (mirror of warp.zig fadeToIdentity;
    // blending toward the sorted base preserves monotonicity). `scale` is this
    // axis's pixels-per-em. The caller owns the range via AutohintPolicy.fade.
    if (policy.fadeEnabled != 0 && scale > policy.fadeStart) {
        float span = policy.fadeFull - policy.fadeStart;
        float fadeW = (span <= 0.0 || scale >= policy.fadeFull) ? 1.0 : (scale - policy.fadeStart) / span;
        for (int i = 0; i < knotCount; ++i) {
            knotTarget[i] += (knotBase[i] - knotTarget[i]) * fadeW;
        }
    }
    for (int i = 0; i < knotCount; ++i) {
        if (!snailAhFinite(knotBase[i]) || !snailAhFinite(knotTarget[i])) { knotCount = 0; return false; }
    }
    return true;
}

float snailInverseWarpAxis(int count, float bases[SNAIL_AH_MAX_KNOTS],
    float targets[SNAIL_AH_MAX_KNOTS], float hinted, out float invSlope) {
    invSlope = 1.0;
    if (count == 0) return hinted;
    if (hinted <= targets[0]) return bases[0] + hinted - targets[0];
    if (hinted >= targets[count - 1]) return bases[count - 1] + hinted - targets[count - 1];
    int lo = 0;
    for (int i = 0; i < count - 1; ++i) {
        if (targets[i + 1] >= hinted) { lo = i; break; }
    }
    float dt = targets[lo + 1] - targets[lo];
    float db = bases[lo + 1] - bases[lo];
    invSlope = abs(dt) > 1e-6 ? db / dt : 1.0;
    return bases[lo] + (hinted - targets[lo]) * invSlope;
}
