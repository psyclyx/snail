// Transient autohint fitting. This is a bounded GLSL port of
// font/autohint/warp.zig fitAxis + inverseWarp. Immutable slab records contain
// feature facts only; targets below exist only for this fragment invocation.

const int SNAIL_AH_MAX_KNOTS = 32;

// Implemented by snail_autohint_main.glsl for the layer-info texture.
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

bool snailAhFinite(float v) { return !isnan(v) && !isinf(v); }

bool snailDecodeAutohintPolicy(uvec4 p0, uvec3 p1, out SnailAutohintPolicy p) {
    uint x = p0.x;
    uint y = p0.y;
    // word0: x config bits 0-7, then the packed whole-glyph fade (bits 8-22).
    if ((x & ~0x7fffffu) != 0u || (y & ~0x3fu) != 0u) return false;
    p.xAlign = int(x & 3u);
    p.xStem = int((x >> 2u) & 3u);
    p.xPositioning = int((x >> 4u) & 3u);
    p.xRegistration = int((x >> 6u) & 3u);
    p.fadeEnabled = int((x >> 8u) & 1u);
    p.fadeStart = float((x >> 9u) & 0x7fu);
    p.fadeFull = float((x >> 16u) & 0x7fu);
    p.yAlign = int(y & 3u);
    p.yStem = int((y >> 2u) & 3u);
    p.yOvershoot = int((y >> 4u) & 3u);
    if (p.xAlign > 1 || p.xStem > 2 || p.xPositioning > 1 ||
        p.xRegistration > 1 || p.yAlign > 2 || p.yStem > 2 || p.yOvershoot > 1)
        return false;
    p.xRatio = uintBitsToFloat(p0.z);
    p.xMaxPx = uintBitsToFloat(p0.w);
    p.yRatio = uintBitsToFloat(p1.x);
    p.yMaxPx = uintBitsToFloat(p1.y);
    p.overshootMinPx = uintBitsToFloat(p1.z);
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

// Reads one immutable feature run and derives transient knots. `axis` is 0=x,
// 1=y. Every loop has a compile-time bound for GLES 3.0 drivers.
bool snailFitAutohintAxis(
    int axis, int run, int blueCount, float standardWidth, float left,
    float scale, SnailAutohintPolicy policy,
    out int knotCount, out float knotBase[SNAIL_AH_MAX_KNOTS],
    out float knotTarget[SNAIL_AH_MAX_KNOTS]
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

    float pos[SNAIL_AH_MAX_KNOTS];
    float width[SNAIL_AH_MAX_KNOTS];
    int stem[SNAIL_AH_MAX_KNOTS];
    int blue[SNAIL_AH_MAX_KNOTS];
    bool rounded[SNAIL_AH_MAX_KNOTS];
    bool syntheticApex[SNAIL_AH_MAX_KNOTS];
    int dir[SNAIL_AH_MAX_KNOTS];
    float targets[SNAIL_AH_MAX_KNOTS];
    bool hinted[SNAIL_AH_MAX_KNOTS];
    bool knotBlueFixed[SNAIL_AH_MAX_KNOTS];
    bool knotNaturalSpacing[SNAIL_AH_MAX_KNOTS];

    for (int i = 0; i < SNAIL_AH_MAX_KNOTS; ++i) {
        if (i >= n) break;
        int f = run + 1 + 4 * i;
        pos[i] = snailWarpF(f, 0);
        width[i] = snailWarpF(f, 1);
        uint refs = floatBitsToUint(snailWarpF(f, 2));
        stem[i] = int(refs << 16u) >> 16;
        blue[i] = int(refs) >> 16;
        uint flags = floatBitsToUint(snailWarpF(f, 3));
        rounded[i] = (flags & 1u) != 0u;
        syntheticApex[i] = (flags & 2u) != 0u;
        hinted[i] = false;
        if (!snailAhFinite(pos[i]) || !snailAhFinite(width[i]) || width[i] < 0.0 ||
            stem[i] < -1 || blue[i] < -1 || (blue[i] >= blueCount)) return false;
    }
    for (int i = 0; i < SNAIL_AH_MAX_KNOTS; ++i) {
        if (i >= blueCount) break;
        float ref = snailWarpF(12, 2 * i);
        float shoot = snailWarpF(12, 2 * i + 1);
        if (!snailAhFinite(ref) || !snailAhFinite(shoot)) return false;
    }
    for (int i = 0; i < SNAIL_AH_MAX_KNOTS; ++i) {
        if (i >= n) break;
        if (stem[i] >= 0) {
            int j = stem[i];
            if (j >= n || j == i || stem[j] != i || !snailAhFinite(pos[j]) ||
                pos[j] == pos[i] || !snailAhFinite(width[j]) || width[j] != width[i]) return false;
        }
    }

    float overshootLimit = (axis == 1 && policy.yOvershoot == 1) ? policy.overshootMinPx : 0.0;
    for (int i = 0; i < SNAIL_AH_MAX_KNOTS; ++i) {
        if (i >= n) break;
        bool partnerAbove = stem[i] >= 0 && pos[stem[i]] > pos[i];
        bool validBlue = useBlues && blue[i] >= 0;
        bool bottomBlue = validBlue && snailWarpF(12, 2 * blue[i] + 1) < snailWarpF(12, 2 * blue[i]);
        int companionDir = 1;
        if (stem[i] < 0 && !validBlue && useBlues) {
            float nearest = 3.402823466e38;
            for (int k = 0; k < SNAIL_AH_MAX_KNOTS; ++k) {
                if (k >= n) break;
                if (blue[k] < 0) continue;
                float gap = abs(pos[k] - pos[i]);
                if (gap >= nearest) continue;
                nearest = gap;
                companionDir = snailWarpF(12, 2 * blue[k] + 1) < snailWarpF(12, 2 * blue[k]) ? 1 : -1;
            }
        }
        dir[i] = (partnerAbove || bottomBlue) ? -1 : companionDir;
        if (validBlue) {
            float ref = snailWarpF(12, 2 * blue[i]);
            float shoot = snailWarpF(12, 2 * blue[i] + 1);
            // Preserve (y overshoot policy == 0): keep a round apex at its natural
            // position so the curve AA's into a round top instead of crushing flat
            // onto the snapped blue row. Suppress snaps it (crisper, flat).
            if (rounded[i] && axis == 1 && policy.yOvershoot == 0) {
                targets[i] = pos[i];
            } else {
                targets[i] = snailAhSnap(ref, scale);
                if (rounded[i] && abs((shoot - ref) * scale) >= overshootLimit) targets[i] += shoot - ref;
            }
        } else {
            targets[i] = snailAhSnap(pos[i], scale);
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
    for (int i = 0; i < SNAIL_AH_MAX_KNOTS; ++i) {
        if (i >= n) break;
        int j = stem[i];
        if (j < 0 || j <= i) continue;
        float nominal = snailAhStandardWidth(width[i], standardWidth, ratio);
        float widthUnits = width[i];
        if (stemMode == 2 || (stemMode == 1 && nominal * scale < maxPx))
            widthUnits = max(round(nominal * scale), 1.0) * grid;
        if (relative) {
            if (anchorSet) targets[i] = anchorTarget + round((pos[i] - anchorBase) * scale) * grid;
            else {
                targets[i] = snailAhSnap(pos[i], scale);
                anchorSet = true;
                clusterBase = pos[i];
                clusterTarget = targets[i];
            }
            targets[j] = targets[i] + widthUnits;
            anchorBase = pos[i];
            anchorTarget = targets[i];
            clusterRight = j;
            clusterDesiredRight = clusterTarget + round((pos[i] - clusterBase) * scale) * grid + widthUnits;
            clusterStems += 1;
        } else {
            bool axisAligned = axis == 0 ? policy.xAlign != 0 : policy.yAlign != 0;
            bool lowerBlue = axisAligned && blue[i] >= 0;
            bool upperBlue = axisAligned && blue[j] >= 0;
            if (!alignPositions) targets[i] = pos[i];
            if (upperBlue && !lowerBlue && alignPositions) targets[i] = targets[j] - widthUnits;
            else targets[j] = targets[i] + widthUnits;
        }
        hinted[i] = true;
        hinted[j] = true;
    }
    if (relative && clusterStems > 1) {
        float shift = clusterDesiredRight - targets[clusterRight];
        for (int i = 0; i < SNAIL_AH_MAX_KNOTS; ++i) {
            if (i >= n) break;
            if (hinted[i]) targets[i] += shift;
        }
    }

    // Preserve the weight next to a round blue-zone apex.
    float companionMax = stemMode == 1 ? maxPx : 1.6;
    for (int i = 0; i < SNAIL_AH_MAX_KNOTS; ++i) {
        if (i >= n) break;
        bool axisAligned = axis == 0 ? policy.xAlign != 0 : policy.yAlign != 0;
        if (!axisAligned || blue[i] < 0 || !rounded[i] || hinted[i]) continue;
        bool top = dir[i] > 0;
        int best = -1;
        float bestGap = 3.402823466e38;
        for (int k = 0; k < SNAIL_AH_MAX_KNOTS; ++k) {
            if (k >= n) break;
            if (k == i || dir[k] == dir[i]) continue;
            float gap = top ? pos[i] - pos[k] : pos[k] - pos[i];
            if (gap <= 0.0 || gap >= bestGap) continue;
            bestGap = gap;
            best = k;
        }
        if (best < 0 || hinted[best] || blue[best] >= 0 || bestGap * scale >= companionMax) continue;
        float widthUnits = syntheticApex[best] ? bestGap : max(round(bestGap * scale), 1.0) * grid;
        targets[best] = top ? targets[i] - widthUnits : targets[i] + widthUnits;
        hinted[best] = true;
    }

    for (int i = 0; i < SNAIL_AH_MAX_KNOTS; ++i) {
        if (i >= n) break;
        bool axisAligned = axis == 0 ? policy.xAlign != 0 : policy.yAlign != 0;
        if (!hinted[i] && !(axisAligned && blue[i] >= 0)) continue;
        knotBase[knotCount] = pos[i];
        knotTarget[knotCount] = targets[i];
        knotBlueFixed[knotCount] = axisAligned && blue[i] >= 0;
        knotNaturalSpacing[knotCount] = syntheticApex[i];
        ++knotCount;
    }
    if (axis == 0 && policy.xRegistration == 1 && knotCount > 0 && knotCount < SNAIL_AH_MAX_KNOTS &&
        left < knotBase[0] - 0.25 * grid) {
        for (int i = SNAIL_AH_MAX_KNOTS - 1; i > 0; --i) {
            if (i <= knotCount) {
                knotBase[i] = knotBase[i - 1];
                knotTarget[i] = knotTarget[i - 1];
                knotBlueFixed[i] = knotBlueFixed[i - 1];
                knotNaturalSpacing[i] = knotNaturalSpacing[i - 1];
            }
        }
        knotBase[0] = left;
        knotTarget[0] = snailAhSnap(left, scale);
        knotBlueFixed[0] = false;
        knotNaturalSpacing[0] = false;
        ++knotCount;
    }
    // Keep shared blue-zone targets fixed. If quantized interior features run
    // out of room below one, resolve their collisions inward before the
    // generic forward monotonicity repair can push the blue edge outward.
    for (int b = SNAIL_AH_MAX_KNOTS - 1; b > 0; --b) {
        if (b >= knotCount || !knotBlueFixed[b]) continue;
        for (int j = SNAIL_AH_MAX_KNOTS - 1; j > 0; --j) {
            if (j > b) continue;
            if (knotBlueFixed[j - 1]) break;
            float spacing = knotNaturalSpacing[j - 1] ? 1e-6 : grid;
            knotTarget[j - 1] = min(knotTarget[j - 1], knotTarget[j] - spacing);
        }
    }
    for (int i = 1; i < SNAIL_AH_MAX_KNOTS; ++i) {
        if (i >= knotCount) break;
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
        for (int i = 0; i < SNAIL_AH_MAX_KNOTS; ++i) {
            if (i >= knotCount) break;
            knotTarget[i] += (knotBase[i] - knotTarget[i]) * fadeW;
        }
    }
    for (int i = 0; i < SNAIL_AH_MAX_KNOTS; ++i) {
        if (i >= knotCount) break;
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
    for (int i = 0; i < SNAIL_AH_MAX_KNOTS - 1; ++i) {
        if (i + 1 >= count || targets[i + 1] >= hinted) { lo = i; break; }
    }
    float dt = targets[lo + 1] - targets[lo];
    float db = bases[lo + 1] - bases[lo];
    invSlope = abs(dt) > 1e-6 ? db / dt : 1.0;
    return bases[lo] + (hinted - targets[lo]) * invSlope;
}
