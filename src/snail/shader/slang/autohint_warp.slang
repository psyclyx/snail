// Native-Slang port of snail_autohint_warp.glsl — transient autohint
// fitting (a bounded port of font/autohint/warp.zig fitAxis + inverseWarp).
// The GLSL fragment is the behavioral spec: every epsilon, literal, and
// operation order is preserved.
//
// Structural differences from GLSL (plumbing only, math unchanged):
//  - The stage split (SNAIL_AUTOHINT_VERTEX: 16-knot bound, resolved
//    semantics required) becomes generic parameters
//    `<let N : int, let IS_VERTEX : bool>`; the compile-time branches fold
//    exactly like the preprocessor did.
//  - `snailWarpF` reads through explicit Texture2D + info-base parameters
//    instead of a caller-provided extern function.
//  - The WGSL finite check (no isnan/isinf there — NaN semantics are
//    implementation-defined) keeps its abs() range form behind
//    SNAIL_TARGET_WGSL, mirroring the catalog's SNAIL_WGSL variant.
module autohint_warp;

public static const int SNAIL_AH_LEFT_SOURCE = 32;

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

public int2 snailAhLayerLoc(Texture2D<float4> layer_tex, int2 base, int offset) {
    uint uw, uh;
    layer_tex.GetDimensions(uw, uh);
    int width = int(uw);
    int texel = base.y * width + base.x + offset;
    return int2(texel % width, texel / width);
}

public float snailWarpF(Texture2D<float4> layer_tex, int2 info_base, int block, int i) {
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

public bool snailDecodeAutohintPolicy(uint4 p0, uint3 p1, out SnailAutohintPolicy p) {
    p = (SnailAutohintPolicy)0;
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
    p.xRatio = asfloat(p0.z);
    p.xMaxPx = asfloat(p0.w);
    p.yRatio = asfloat(p1.x);
    p.yMaxPx = asfloat(p1.y);
    p.overshootMinPx = asfloat(p1.z);
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

// Reads one immutable feature run and derives transient knots. `axis` is 0=x,
// 1=y. Every loop has a compile-time bound for GLES 3.0 drivers.
public bool snailFitAutohintAxis<let N : int, let IS_VERTEX : bool>(
    Texture2D<float4> layer_tex, int2 info_base,
    int axis, int run, int blueCount, float standardWidth, float left,
    float scale, SnailAutohintPolicy policy,
    out int knotCount, out float knotBase[N],
    out float knotTarget[N],
    out int knotSource[N]
) {
    knotCount = 0;
    for (int i = 0; i < N; ++i) { knotBase[i] = 0.0; knotTarget[i] = 0.0; knotSource[i] = 0; }
    if (!snailAhFinite(scale) || scale <= 0.0 || blueCount < 0 || blueCount > N ||
        !snailAhFinite(standardWidth) || standardWidth < 0.0) return false;
    if ((axis == 0 && policy.xAlign == 0 && policy.xStem == 0 && policy.xPositioning == 0 && policy.xRegistration == 0) ||
        (axis == 1 && policy.yAlign == 0 && policy.yStem == 0 && policy.yOvershoot == 0)) return true;

    int n = int(snailWarpF(layer_tex, info_base, run, 0));
    if (n <= 0 || n > N) return n == 0;
    bool useBlues = axis == 1 && policy.yAlign == 2;
    if (axis == 0 && policy.xRegistration == 1 && !snailAhFinite(left)) return false;

    float pos[N];
    float width[N];
    int stem[N];
    int blue[N];
    bool rounded[N];
    bool syntheticApex[N];
    int companion[N];
    bool semanticsResolved[N];
    bool blueDirNegative[N];
    int gridCompanion[N];
    int blueCompanion[N];
    int dir[N];
    float targets[N];
    bool hinted[N];
    bool knotBlueFixed[N];
    bool knotNaturalSpacing[N];

    for (int i = 0; i < N; ++i) {
        if (i >= n) break;
        int f = run + 1 + 4 * i;
        pos[i] = snailWarpF(layer_tex, info_base, f, 0);
        width[i] = snailWarpF(layer_tex, info_base, f, 1);
        uint refs = asuint(snailWarpF(layer_tex, info_base, f, 2));
        stem[i] = int(refs << 16u) >> 16;
        blue[i] = int(refs) >> 16;
        uint flags = asuint(snailWarpF(layer_tex, info_base, f, 3));
        rounded[i] = (flags & 1u) != 0u;
        syntheticApex[i] = (flags & 2u) != 0u;
        if (IS_VERTEX) {
            if ((flags & 4u) == 0u) return false;
            dir[i] = (flags & 8u) != 0u ? -1 : 1;
            int encodedCompanion = int((flags >> (useBlues ? 10u : 4u)) & 63u);
            companion[i] = encodedCompanion >= 62 ? -1 : encodedCompanion;
            if (encodedCompanion >= 63 && rounded[i] && blue[i] >= 0) return false;
        } else {
            semanticsResolved[i] = (flags & 4u) != 0u;
            blueDirNegative[i] = (flags & 8u) != 0u;
            gridCompanion[i] = int((flags >> 4u) & 63u);
            blueCompanion[i] = int((flags >> 10u) & 63u);
        }
        hinted[i] = false;
        if (!snailAhFinite(pos[i]) || !snailAhFinite(width[i]) || width[i] < 0.0 ||
            stem[i] < -1 || stem[i] >= n || blue[i] < -1 || (blue[i] >= blueCount)) return false;
    }
    for (int i = 0; i < N; ++i) {
        if (i >= blueCount) break;
        float ref = snailWarpF(layer_tex, info_base, 12, 2 * i);
        float shoot = snailWarpF(layer_tex, info_base, 12, 2 * i + 1);
        if (!snailAhFinite(ref) || !snailAhFinite(shoot)) return false;
    }
    if (!IS_VERTEX) {
        for (int i = 0; i < N; ++i) {
            if (i >= n) break;
            if (stem[i] >= 0) {
                int j = stem[i];
                if (j >= n || j == i || stem[j] != i || !snailAhFinite(pos[j]) ||
                    pos[j] == pos[i] || !snailAhFinite(width[j]) || width[j] != width[i]) return false;
            }
        }
    }

    float overshootLimit = (axis == 1 && policy.yOvershoot == 1) ? policy.overshootMinPx : 0.0;
    for (int i = 0; i < N; ++i) {
        if (i >= n) break;
        bool partnerAbove = stem[i] >= 0 && pos[stem[i]] > pos[i];
        bool validBlue = useBlues && blue[i] >= 0;
        if (IS_VERTEX) {
            if (!useBlues) dir[i] = partnerAbove ? -1 : 1;
        } else {
            bool bottomBlue = validBlue && snailWarpF(layer_tex, info_base, 12, 2 * blue[i] + 1) < snailWarpF(layer_tex, info_base, 12, 2 * blue[i]);
            int companionDir = 1;
            if (!semanticsResolved[i] && stem[i] < 0 && !validBlue && useBlues) {
                float nearest = 3.402823466e38;
                for (int k = 0; k < N; ++k) {
                    if (k >= n) break;
                    if (blue[k] < 0) continue;
                    float gap = abs(pos[k] - pos[i]);
                    if (gap >= nearest) continue;
                    nearest = gap;
                    companionDir = snailWarpF(layer_tex, info_base, 12, 2 * blue[k] + 1) < snailWarpF(layer_tex, info_base, 12, 2 * blue[k]) ? 1 : -1;
                }
            }
            dir[i] = semanticsResolved[i]
                ? ((useBlues && blueDirNegative[i]) || (!useBlues && partnerAbove) ? -1 : 1)
                : ((partnerAbove || bottomBlue) ? -1 : companionDir);
            int encodedCompanion = useBlues ? blueCompanion[i] : gridCompanion[i];
            companion[i] = !semanticsResolved[i] || encodedCompanion == 63
                ? -2
                : (encodedCompanion == 62 ? -1 : encodedCompanion);
        }
        if (validBlue) {
            float ref = snailWarpF(layer_tex, info_base, 12, 2 * blue[i]);
            float shoot = snailWarpF(layer_tex, info_base, 12, 2 * blue[i] + 1);
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
    for (int i = 0; i < N; ++i) {
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
        for (int i = 0; i < N; ++i) {
            if (i >= n) break;
            if (hinted[i]) targets[i] += shift;
        }
    }

    // Preserve the weight next to a round blue-zone apex.
    float companionMax = stemMode == 1 ? maxPx : 1.6;
    for (int i = 0; i < N; ++i) {
        if (i >= n) break;
        bool axisAligned = axis == 0 ? policy.xAlign != 0 : policy.yAlign != 0;
        if (!axisAligned || blue[i] < 0 || !rounded[i] || hinted[i]) continue;
        bool top = dir[i] > 0;
        int best = companion[i];
        float bestGap = 3.402823466e38;
        if (best >= 0) {
            bestGap = top ? pos[i] - pos[best] : pos[best] - pos[i];
        } else if (best == -2) {
            for (int k = 0; k < N; ++k) {
            if (k >= n) break;
                if (k == i || dir[k] == dir[i]) continue;
                float gap = top ? pos[i] - pos[k] : pos[k] - pos[i];
                if (gap <= 0.0 || gap >= bestGap) continue;
                bestGap = gap;
                best = k;
            }
        }
        if (best < 0 || hinted[best] || blue[best] >= 0 || bestGap * scale >= companionMax) continue;
        float widthUnits = syntheticApex[best] ? bestGap : max(round(bestGap * scale), 1.0) * grid;
        targets[best] = top ? targets[i] - widthUnits : targets[i] + widthUnits;
        hinted[best] = true;
    }

    for (int i = 0; i < N; ++i) {
        if (i >= n) break;
        bool axisAligned = axis == 0 ? policy.xAlign != 0 : policy.yAlign != 0;
        if (!hinted[i] && !(axisAligned && blue[i] >= 0)) continue;
        knotBase[knotCount] = pos[i];
        knotTarget[knotCount] = targets[i];
        knotBlueFixed[knotCount] = axisAligned && blue[i] >= 0;
        knotNaturalSpacing[knotCount] = syntheticApex[i];
        knotSource[knotCount] = i;
        ++knotCount;
    }
    if (axis == 0 && policy.xRegistration == 1 && knotCount > 0 && knotCount < N &&
        left < knotBase[0] - 0.25 * grid) {
        for (int i = N - 1; i > 0; --i) {
            if (i <= knotCount) {
                knotBase[i] = knotBase[i - 1];
                knotTarget[i] = knotTarget[i - 1];
                knotBlueFixed[i] = knotBlueFixed[i - 1];
                knotNaturalSpacing[i] = knotNaturalSpacing[i - 1];
                knotSource[i] = knotSource[i - 1];
            }
        }
        knotBase[0] = left;
        knotTarget[0] = snailAhSnap(left, scale);
        knotBlueFixed[0] = false;
        knotNaturalSpacing[0] = false;
        knotSource[0] = SNAIL_AH_LEFT_SOURCE;
        ++knotCount;
    }
    // Keep shared blue-zone targets fixed. If quantized interior features run
    // out of room below one, resolve their collisions inward before the
    // generic forward monotonicity repair can push the blue edge outward.
    for (int b = N - 1; b > 0; --b) {
        if (b >= knotCount || !knotBlueFixed[b]) continue;
        for (int j = N - 1; j > 0; --j) {
            if (j > b) continue;
            if (knotBlueFixed[j - 1]) break;
            float spacing = knotNaturalSpacing[j - 1] ? 1e-6 : grid;
            knotTarget[j - 1] = min(knotTarget[j - 1], knotTarget[j] - spacing);
        }
    }
    for (int i = 1; i < N; ++i) {
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
        for (int i = 0; i < N; ++i) {
            if (i >= knotCount) break;
            knotTarget[i] += (knotBase[i] - knotTarget[i]) * fadeW;
        }
    }
    for (int i = 0; i < N; ++i) {
        if (i >= knotCount) break;
        if (!snailAhFinite(knotBase[i]) || !snailAhFinite(knotTarget[i])) { knotCount = 0; return false; }
    }
    return true;
}

public float snailInverseWarpAxis<let N : int>(int count, float bases[N],
    float targets[N], float hinted, out float invSlope) {
    invSlope = 1.0;
    if (count == 0) return hinted;
    if (hinted <= targets[0]) return bases[0] + hinted - targets[0];
    if (hinted >= targets[count - 1]) return bases[count - 1] + hinted - targets[count - 1];
    int lo = 0;
    for (int i = 0; i < N - 1; ++i) {
        if (i + 1 >= count || targets[i + 1] >= hinted) { lo = i; break; }
    }
    float dt = targets[lo + 1] - targets[lo];
    float db = bases[lo + 1] - bases[lo];
    invSlope = abs(dt) > 1e-6 ? db / dt : 1.0;
    return bases[lo] + (hinted - targets[lo]) * invSlope;
}
