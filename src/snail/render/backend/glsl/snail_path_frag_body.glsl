#define kDirectEncodingKindBias 4.0
const float kParamEps = 1e-5;
const float kCoordEps = 1.0 / 65536.0;
const uint kBandCurveLocXMask = 0x0FFFu;
const uint kBandCurveFirstMemberShift = 12u;

#ifndef SNAIL_ENABLE_PATH
#define SNAIL_ENABLE_PATH 1
#endif

#ifndef SNAIL_ENABLE_HINTED_TEXT
#define SNAIL_ENABLE_HINTED_TEXT 1
#endif

ivec2 decodeBandCurveLoc(uvec2 ref) {
    return ivec2(int(ref.x & kBandCurveLocXMask), int(ref.y));
}

int decodeBandCurveFirstMember(uvec2 ref) {
    return int(ref.x >> kBandCurveFirstMemberShift);
}

ivec2 offsetLayerLoc(ivec2 base, int offset) {
    int width = textureSize(u_layer_tex, 0).x;
    int texel = base.y * width + base.x + offset;
    return ivec2(texel % width, texel / width);
}

struct SegmentData {
    int kind;
    vec2 p0;
    vec2 p1;
    vec2 p2;
    vec2 p3;
    vec3 weights;
};

#if SNAIL_ENABLE_PATH
struct SegmentRoots {
    int count;
    vec3 t;
};

void appendRoot(inout SegmentRoots roots, float t) {
    if (roots.count >= 3) return;
    if (t < -kParamEps || t > 1.0 + kParamEps) return;
    float clamped = clamp(t, 0.0, 1.0);
    for (int i = 0; i < roots.count; i++) {
        if (abs(roots.t[i] - clamped) <= kParamEps) return;
    }
    int insertAt = roots.count;
    while (insertAt > 0 && roots.t[insertAt - 1] > clamped) {
        roots.t[insertAt] = roots.t[insertAt - 1];
        insertAt--;
    }
    roots.t[insertAt] = clamped;
    roots.count++;
}

SegmentRoots solveQuadraticRoots(float a, float b, float cVal) {
    SegmentRoots roots;
    roots.count = 0;
    roots.t = vec3(0.0);
    if (abs(a) < kCoordEps) {
        if (abs(b) < kCoordEps) return roots;
        appendRoot(roots, -cVal / b);
        return roots;
    }
    float disc = b * b - 4.0 * a * cVal;
    if (disc < 0.0) {
        if (disc > -1e-6) {
            disc = 0.0;
        } else {
            return roots;
        }
    }
    float sqrtDisc = sqrt(disc);
    float inv2a = 0.5 / a;
    appendRoot(roots, (-b - sqrtDisc) * inv2a);
    appendRoot(roots, (-b + sqrtDisc) * inv2a);
    return roots;
}

SegmentRoots solveCubicRoots(float a, float b, float cVal, float d) {
    // Path preparation splits cubics at x/y extrema, so each uploaded cubic is
    // monotonic along both sampling axes and can contribute at most one root.
    SegmentRoots roots;
    roots.count = 0;
    roots.t = vec3(0.0);
    float f0 = d;
    float f1 = ((a + b) + cVal) + d;
    if ((f0 < -kCoordEps && f1 < -kCoordEps) || (f0 > kCoordEps && f1 > kCoordEps)) return roots;

    float lo = 0.0;
    float hi = 1.0;
    float t = 0.5;
    bool increasing = f1 >= f0;
    for (int i = 0; i < 16; i++) {
        float f = ((a * t + b) * t + cVal) * t + d;
        if ((increasing && f < 0.0) || (!increasing && f > 0.0)) {
            lo = t;
        } else {
            hi = t;
        }
        float deriv = (3.0 * a * t + 2.0 * b) * t + cVal;
        float next = (lo + hi) * 0.5;
        if (abs(deriv) >= 1e-6) {
            float newton = t - f / deriv;
            if (newton > lo && newton < hi) next = newton;
        }
        t = next;
    }
    appendRoot(roots, t);
    return roots;
}
#endif

vec2 solveQuadraticHorizDistances(float p0x, float p0y, float p1x, float p1y, float p2x, float p2y, float ppeX) {
    float ax = p0x - p1x * 2.0 + p2x;
    float ay = p0y - p1y * 2.0 + p2y;
    float bx = p0x - p1x;
    float by = p0y - p1y;
    const float kEps = 1.0 / 65536.0;

    float t1, t2;
    if (abs(ay) < kEps) {
        t1 = (abs(by) < kEps) ? 0.0 : p0y * 0.5 / by;
        t2 = t1;
    } else {
        float sq = sqrt(max(by * by - ay * p0y, 0.0));
        if (by >= 0.0) {
            float q = by + sq;
            t2 = q / ay;
            t1 = (abs(q) < kEps) ? 0.0 : p0y / q;
        } else {
            float q = by - sq;
            t1 = q / ay;
            t2 = (abs(q) < kEps) ? 0.0 : p0y / q;
        }
    }

    float x1 = (ax * t1 - bx * 2.0) * t1 + p0x;
    float x2 = (ax * t2 - bx * 2.0) * t2 + p0x;
    return vec2(x1 * ppeX, x2 * ppeX);
}

vec2 solveQuadraticVertDistances(float p0x, float p0y, float p1x, float p1y, float p2x, float p2y, float ppeY) {
    float ax = p0x - p1x * 2.0 + p2x;
    float ay = p0y - p1y * 2.0 + p2y;
    float bx = p0x - p1x;
    float by = p0y - p1y;
    const float kEps = 1.0 / 65536.0;

    float t1, t2;
    if (abs(ax) < kEps) {
        t1 = (abs(bx) < kEps) ? 0.0 : p0x * 0.5 / bx;
        t2 = t1;
    } else {
        float sq = sqrt(max(bx * bx - ax * p0x, 0.0));
        if (bx >= 0.0) {
            float q = bx + sq;
            t2 = q / ax;
            t1 = (abs(q) < kEps) ? 0.0 : p0x / q;
        } else {
            float q = bx - sq;
            t1 = q / ax;
            t2 = (abs(q) < kEps) ? 0.0 : p0x / q;
        }
    }

    float y1 = (ay * t1 - by * 2.0) * t1 + p0y;
    float y2 = (ay * t2 - by * 2.0) * t2 + p0y;
    return vec2(y1 * ppeY, y2 * ppeY);
}

#if SNAIL_ENABLE_PATH
SegmentData fetchSegment(ivec2 loc, int layer) {
    vec4 tex0 = texelFetch(u_curve_tex, ivec3(loc, layer), 0);
    vec4 tex1 = texelFetch(u_curve_tex, ivec3(offsetCurveLoc(loc, 1), layer), 0);
    vec4 tex2 = texelFetch(u_curve_tex, ivec3(offsetCurveLoc(loc, 2), layer), 0);
    SegmentData seg;
    bool direct = tex2.z >= kDirectEncodingKindBias - 0.5;
    if (direct) {
        seg.kind = int(tex2.z - kDirectEncodingKindBias + 0.5);
        seg.p0 = tex0.xy;
        seg.p1 = tex0.zw;
        seg.p2 = tex1.xy;
        seg.p3 = tex1.zw;
        seg.weights = vec3(tex2.w, tex2.x, tex2.y);
    } else {
        vec2 anchor = tex0.xy * 256.0 + tex0.zw;
        seg.kind = int(tex2.z + 0.5);
        seg.p0 = anchor;
        seg.p1 = anchor + tex1.xy;
        seg.p2 = anchor + tex1.zw;
        seg.p3 = anchor + tex2.xy;
        seg.weights = vec3(1.0);
        if (seg.kind == 1) {
            vec4 meta = texelFetch(u_curve_tex, ivec3(offsetCurveLoc(loc, 3), layer), 0);
            seg.weights = vec3(tex2.w, meta.x, meta.y);
        }
    }
    return seg;
}
#endif

#if SNAIL_ENABLE_HINTED_TEXT
struct HintedTextRecord {
    ivec2 infoBase;
    int baseCurveTexel;
    int curveCount;
    int flags;
    ivec2 bandPad;
};

int curveTexelFromLoc(ivec2 loc) {
    return loc.y * (1 << kLogBandTextureWidth) + loc.x;
}

bool hintedTextHasExpandedBands(HintedTextRecord record) {
    return (record.flags & SNAIL_HINT_RECORD_FLAG_EXPANDED_BANDS) != 0;
}

bool hintedTextHasUnorderedBands(HintedTextRecord record) {
    return (record.flags & SNAIL_HINT_RECORD_FLAG_UNORDERED_BANDS) != 0;
}

SegmentData addCurveDeltas(SegmentData seg, vec4 delta0, vec4 delta1) {
    seg.p0 += delta0.xy;
    seg.p1 += delta0.zw;
    seg.p2 += delta1.xy;
    seg.p3 += delta1.zw;
    return seg;
}

SegmentData fetchHintedQuadraticSegment(ivec2 loc, int layer, HintedTextRecord record) {
    // Hinted TrueType outlines are emitted as direct-encoded quadratic segments.
    vec4 tex0 = texelFetch(u_curve_tex, ivec3(loc, layer), 0);
    vec4 tex1 = texelFetch(u_curve_tex, ivec3(offsetCurveLoc(loc, 1), layer), 0);
    SegmentData seg;
    seg.kind = 0;
    seg.p0 = tex0.xy;
    seg.p1 = tex0.zw;
    seg.p2 = tex1.xy;
    seg.p3 = vec2(0.0);
    seg.weights = vec3(1.0);

    int curveIndex = (curveTexelFromLoc(loc) - record.baseCurveTexel) / int(4);
    if (curveIndex < 0 || curveIndex >= record.curveCount) return seg;

    int deltaOffset = 3 + curveIndex * 2;
    vec4 delta0 = texelFetch(u_layer_tex, offsetLayerLoc(record.infoBase, deltaOffset), 0);
    vec4 delta1 = texelFetch(u_layer_tex, offsetLayerLoc(record.infoBase, deltaOffset + 1), 0);
    return addCurveDeltas(seg, delta0, delta1);
}
#endif

float segmentMaxX(SegmentData seg) {
    if (seg.kind == 3) return max(seg.p0.x, seg.p2.x);
    if (seg.kind == 2) return max(max(seg.p0.x, seg.p1.x), max(seg.p2.x, seg.p3.x));
    return max(max(seg.p0.x, seg.p1.x), seg.p2.x);
}

float segmentMaxY(SegmentData seg) {
    if (seg.kind == 3) return max(seg.p0.y, seg.p2.y);
    if (seg.kind == 2) return max(max(seg.p0.y, seg.p1.y), max(seg.p2.y, seg.p3.y));
    return max(max(seg.p0.y, seg.p1.y), seg.p2.y);
}

#if SNAIL_ENABLE_PATH
float segmentEndRootDelta(SegmentData seg, vec2 sampleRc, bool horizontal) {
    if (seg.kind == 2) {
        return horizontal ? seg.p3.y - sampleRc.y : seg.p3.x - sampleRc.x;
    }
    return horizontal ? seg.p2.y - sampleRc.y : seg.p2.x - sampleRc.x;
}

bool rootHullCanCross3(float p0, float p1, float p2, float sampleRoot) {
    float minRoot = min(min(p0, p1), p2);
    float maxRoot = max(max(p0, p1), p2);
    return minRoot - sampleRoot <= kCoordEps && maxRoot - sampleRoot >= -kCoordEps;
}

bool rootHullCanCross4(float p0, float p1, float p2, float p3, float sampleRoot) {
    float minRoot = min(min(p0, p1), min(p2, p3));
    float maxRoot = max(max(p0, p1), max(p2, p3));
    return minRoot - sampleRoot <= kCoordEps && maxRoot - sampleRoot >= -kCoordEps;
}

bool segmentRootHullCanCross(SegmentData seg, vec2 sampleRc, bool horizontal) {
    float sampleRoot = horizontal ? sampleRc.y : sampleRc.x;
    if (seg.kind == 2) {
        return rootHullCanCross4(
            horizontal ? seg.p0.y : seg.p0.x,
            horizontal ? seg.p1.y : seg.p1.x,
            horizontal ? seg.p2.y : seg.p2.x,
            horizontal ? seg.p3.y : seg.p3.x,
            sampleRoot
        );
    }
    return rootHullCanCross3(
        horizontal ? seg.p0.y : seg.p0.x,
        horizontal ? seg.p1.y : seg.p1.x,
        horizontal ? seg.p2.y : seg.p2.x,
        sampleRoot
    );
}

bool isNearEndRoot(float t) {
    return t >= 1.0 - kParamEps;
}

bool isEndpointRootDelta(float endRootDelta) {
    return abs(endRootDelta) <= kCoordEps;
}
#endif

void appendCoverageContribution(inout float cov, inout float wgt, float distance, float sign) {
    cov += sign * clamp(distance + 0.5, 0.0, 1.0);
    wgt = max(wgt, clamp(1.0 - abs(distance) * 2.0, 0.0, 1.0));
}

#if SNAIL_ENABLE_PATH
void accumulateLineCoverage(inout float cov, inout float wgt, float p0x, float p0y, float p2x, float p2y, float ppe, bool horizontal) {
    float rootAxis0 = horizontal ? p0y : p0x;
    float rootAxis2 = horizontal ? p2y : p2x;
    float denom = rootAxis2 - rootAxis0;
    if (abs(denom) < 1e-10) return;

    float tRaw = -rootAxis0 / denom;
    if (tRaw < -kParamEps || tRaw > 1.0 + kParamEps) return;
    float t = clamp(tRaw, 0.0, 1.0);
    if (isNearEndRoot(t) && isEndpointRootDelta(rootAxis2)) return;

    float derivativeAxis = horizontal ? p2y - p0y : p0x - p2x;
    if (abs(derivativeAxis) <= kParamEps) return;

    float distance = (horizontal ? p0x + (p2x - p0x) * t : p0y + (p2y - p0y) * t) * ppe;
    appendCoverageContribution(cov, wgt, distance, derivativeAxis > 0.0 ? 1.0 : -1.0);
}

void accumulateConicCoverage(inout float cov, inout float wgt, SegmentData seg, vec2 sampleRc, float ppe, bool horizontal) {
    if (!segmentRootHullCanCross(seg, sampleRc, horizontal)) return;

    float sampleRoot = horizontal ? sampleRc.y : sampleRc.x;
    float sampleAlong = horizontal ? sampleRc.x : sampleRc.y;
    float p0Root = horizontal ? seg.p0.y : seg.p0.x;
    float p1Root = horizontal ? seg.p1.y : seg.p1.x;
    float p2Root = horizontal ? seg.p2.y : seg.p2.x;
    float p0Along = horizontal ? seg.p0.x : seg.p0.y;
    float p1Along = horizontal ? seg.p1.x : seg.p1.y;
    float p2Along = horizontal ? seg.p2.x : seg.p2.y;

    float c0 = seg.weights.x * (p0Root - sampleRoot);
    float c1 = seg.weights.y * (p1Root - sampleRoot);
    float c2 = seg.weights.z * (p2Root - sampleRoot);
    SegmentRoots roots = solveQuadraticRoots(c0 - 2.0 * c1 + c2, 2.0 * (c1 - c0), c0);

    float rootA = p0Root * seg.weights.x - 2.0 * p1Root * seg.weights.y + p2Root * seg.weights.z;
    float rootB = 2.0 * (p1Root * seg.weights.y - p0Root * seg.weights.x);
    float rootC = p0Root * seg.weights.x;
    float alongA = p0Along * seg.weights.x - 2.0 * p1Along * seg.weights.y + p2Along * seg.weights.z;
    float alongB = 2.0 * (p1Along * seg.weights.y - p0Along * seg.weights.x);
    float alongC = p0Along * seg.weights.x;
    float denA = seg.weights.x - 2.0 * seg.weights.y + seg.weights.z;
    float denB = 2.0 * (seg.weights.y - seg.weights.x);
    float denC = seg.weights.x;

    for (int ri = 0; ri < roots.count; ri++) {
        float t = roots.t[ri];
        if (isNearEndRoot(t) && isEndpointRootDelta(segmentEndRootDelta(seg, sampleRc, horizontal))) continue;

        float den = max((denA * t + denB) * t + denC, kCoordEps);
        float along = ((alongA * t + alongB) * t + alongC) / den;
        float rootNumer = (rootA * t + rootB) * t + rootC;
        float rootPrime = 2.0 * rootA * t + rootB;
        float denPrime = 2.0 * denA * t + denB;
        float derivAxis = (rootPrime * den - rootNumer * denPrime) / (den * den);
        if (!horizontal) derivAxis = -derivAxis;
        if (abs(derivAxis) <= kParamEps) continue;

        float dist = (along - sampleAlong) * ppe;
        appendCoverageContribution(cov, wgt, dist, derivAxis > 0.0 ? 1.0 : -1.0);
    }
}

void accumulateCubicCoverage(inout float cov, inout float wgt, SegmentData seg, vec2 sampleRc, float ppe, bool horizontal) {
    if (!segmentRootHullCanCross(seg, sampleRc, horizontal)) return;

    float sampleRoot = horizontal ? sampleRc.y : sampleRc.x;
    float sampleAlong = horizontal ? sampleRc.x : sampleRc.y;
    float p0Root = horizontal ? seg.p0.y : seg.p0.x;
    float p1Root = horizontal ? seg.p1.y : seg.p1.x;
    float p2Root = horizontal ? seg.p2.y : seg.p2.x;
    float p3Root = horizontal ? seg.p3.y : seg.p3.x;
    float p0Along = horizontal ? seg.p0.x : seg.p0.y;
    float p1Along = horizontal ? seg.p1.x : seg.p1.y;
    float p2Along = horizontal ? seg.p2.x : seg.p2.y;
    float p3Along = horizontal ? seg.p3.x : seg.p3.y;

    float rootA = -p0Root + 3.0 * p1Root - 3.0 * p2Root + p3Root;
    float rootB = 3.0 * p0Root - 6.0 * p1Root + 3.0 * p2Root;
    float rootC = -3.0 * p0Root + 3.0 * p1Root;
    SegmentRoots roots = solveCubicRoots(rootA, rootB, rootC, p0Root - sampleRoot);

    float alongA = -p0Along + 3.0 * p1Along - 3.0 * p2Along + p3Along;
    float alongB = 3.0 * p0Along - 6.0 * p1Along + 3.0 * p2Along;
    float alongC = -3.0 * p0Along + 3.0 * p1Along;

    for (int ri = 0; ri < roots.count; ri++) {
        float t = roots.t[ri];
        if (isNearEndRoot(t) && isEndpointRootDelta(segmentEndRootDelta(seg, sampleRc, horizontal))) continue;

        float along = ((alongA * t + alongB) * t + alongC) * t + p0Along;
        float derivAxis = (3.0 * rootA * t + 2.0 * rootB) * t + rootC;
        if (!horizontal) derivAxis = -derivAxis;
        if (abs(derivAxis) <= kParamEps) continue;

        float dist = (along - sampleAlong) * ppe;
        appendCoverageContribution(cov, wgt, dist, derivAxis > 0.0 ? 1.0 : -1.0);
    }
}

bool accumulateAxisCoverageSegment(inout float cov, inout float wgt, vec2 sampleRc, float ppe, SegmentData seg, bool horizontal) {
    float maxCoord = (horizontal ? segmentMaxX(seg) - sampleRc.x : segmentMaxY(seg) - sampleRc.y);
    if (maxCoord * ppe < -0.5) return false;

    if (seg.kind == 0) {
        float p0x = seg.p0.x - sampleRc.x;
        float p0y = seg.p0.y - sampleRc.y;
        float p1x = seg.p1.x - sampleRc.x;
        float p1y = seg.p1.y - sampleRc.y;
        float p2x = seg.p2.x - sampleRc.x;
        float p2y = seg.p2.y - sampleRc.y;
        uint code = horizontal ? calcRootCode(p0y, p1y, p2y) : calcRootCode(p0x, p1x, p2x);
        if (code == 0u) return true;

        vec2 roots = horizontal
            ? solveQuadraticHorizDistances(p0x, p0y, p1x, p1y, p2x, p2y, ppe)
            : solveQuadraticVertDistances(p0x, p0y, p1x, p1y, p2x, p2y, ppe);

        if ((code & 1u) != 0u) {
            appendCoverageContribution(cov, wgt, roots.x, horizontal ? 1.0 : -1.0);
        }
        if (code > 1u) {
            appendCoverageContribution(cov, wgt, roots.y, horizontal ? -1.0 : 1.0);
        }
        return true;
    }

    if (seg.kind == 3) {
        accumulateLineCoverage(
            cov,
            wgt,
            seg.p0.x - sampleRc.x,
            seg.p0.y - sampleRc.y,
            seg.p2.x - sampleRc.x,
            seg.p2.y - sampleRc.y,
            ppe,
            horizontal
        );
        return true;
    }

    if (seg.kind == 1) {
        accumulateConicCoverage(cov, wgt, seg, sampleRc, ppe, horizontal);
        return true;
    }

    accumulateCubicCoverage(cov, wgt, seg, sampleRc, ppe, horizontal);
    return true;
}

vec2 evalAxisCoverageBands(vec2 sampleRc, float ppe, ivec2 gLoc, int headerBase, int firstBand, int lastBand, int layer, bool horizontal) {
    float cov = 0.0;
    float wgt = 0.0;
    bool dedup = firstBand != lastBand;
    for (int band = firstBand; band <= lastBand; band++) {
        ivec2 headerLoc = calcBandLoc(gLoc, uint(headerBase + band));
        uvec2 bd = texelFetch(u_band_tex, ivec3(headerLoc, layer), 0).xy;
        ivec2 bandLoc = calcBandLoc(gLoc, bd.y);
        int count = int(bd.x);
        for (int i = 0; i < count; i++) {
            ivec2 bLoc = calcBandLoc(bandLoc, uint(i));
            uvec2 ref = texelFetch(u_band_tex, ivec3(bLoc, layer), 0).xy;
            if (dedup) {
                int ownerBand = max(decodeBandCurveFirstMember(ref), firstBand);
                if (band != ownerBand) continue;
            }
            ivec2 cLoc = decodeBandCurveLoc(ref);
            if (!accumulateAxisCoverageSegment(cov, wgt, sampleRc, ppe, fetchSegment(cLoc, layer), horizontal)) break;
        }
    }
    return vec2(cov, wgt);
}
#endif

#if SNAIL_ENABLE_HINTED_TEXT
bool accumulateHintedTextSegment(inout float cov, inout float wgt, vec2 sampleRc, float ppe, SegmentData seg, bool horizontal);

vec2 evalAxisCoverageBandsHinted(vec2 sampleRc, float ppe, ivec2 gLoc, int headerBase, int firstBand, int lastBand, int layer, bool horizontal, HintedTextRecord record) {
    float cov = 0.0;
    float wgt = 0.0;
    bool dedup = firstBand != lastBand;
    bool ordered = !hintedTextHasUnorderedBands(record);
    for (int band = firstBand; band <= lastBand; band++) {
        ivec2 headerLoc = calcBandLoc(gLoc, uint(headerBase + band));
        uvec2 bd = texelFetch(u_band_tex, ivec3(headerLoc, layer), 0).xy;
        ivec2 bandLoc = calcBandLoc(gLoc, bd.y);
        int count = int(bd.x);
        for (int i = 0; i < count; i++) {
            ivec2 bLoc = calcBandLoc(bandLoc, uint(i));
            uvec2 ref = texelFetch(u_band_tex, ivec3(bLoc, layer), 0).xy;
            if (dedup) {
                int ownerBand = max(decodeBandCurveFirstMember(ref), firstBand);
                if (band != ownerBand) continue;
            }
            ivec2 cLoc = decodeBandCurveLoc(ref);
            if (!accumulateHintedTextSegment(cov, wgt, sampleRc, ppe, fetchHintedQuadraticSegment(cLoc, layer, record), horizontal) && ordered) break;
        }
    }
    return vec2(cov, wgt);
}

bool accumulateHintedTextSegment(inout float cov, inout float wgt, vec2 sampleRc, float ppe, SegmentData seg, bool horizontal) {
    // Keep hinted text off the generic conic/cubic coverage path; NVIDIA's
    // GLSL linker spends seconds optimizing that unreachable combination.
    if (seg.kind != 0) return true;

    float maxCoord = (horizontal ? segmentMaxX(seg) - sampleRc.x : segmentMaxY(seg) - sampleRc.y);
    if (maxCoord * ppe < -0.5) return false;

    float p0x = seg.p0.x - sampleRc.x;
    float p0y = seg.p0.y - sampleRc.y;
    float p1x = seg.p1.x - sampleRc.x;
    float p1y = seg.p1.y - sampleRc.y;
    float p2x = seg.p2.x - sampleRc.x;
    float p2y = seg.p2.y - sampleRc.y;
    uint code = horizontal ? calcRootCode(p0y, p1y, p2y) : calcRootCode(p0x, p1x, p2x);
    if (code == 0u) return true;

    vec2 roots = horizontal
        ? solveQuadraticHorizDistances(p0x, p0y, p1x, p1y, p2x, p2y, ppe)
        : solveQuadraticVertDistances(p0x, p0y, p1x, p1y, p2x, p2y, ppe);

    if (horizontal) {
        if ((code & 1u) != 0u) appendCoverageContribution(cov, wgt, roots.x, 1.0);
        if (code > 1u) appendCoverageContribution(cov, wgt, roots.y, -1.0);
    } else {
        if ((code & 1u) != 0u) appendCoverageContribution(cov, wgt, roots.x, -1.0);
        if (code > 1u) appendCoverageContribution(cov, wgt, roots.y, 1.0);
    }
    return true;
}

vec2 evalHintedTextSingleBand(vec2 sampleRc, float ppe, ivec2 gLoc, int headerOffset, int layer, bool horizontal, HintedTextRecord record) {
    float cov = 0.0;
    float wgt = 0.0;
    bool ordered = !hintedTextHasUnorderedBands(record);
    ivec2 headerLoc = calcBandLoc(gLoc, uint(headerOffset));
    uvec2 bd = texelFetch(u_band_tex, ivec3(headerLoc, layer), 0).xy;
    ivec2 bandLoc = calcBandLoc(gLoc, bd.y);
    int count = int(bd.x);
    for (int i = 0; i < count; i++) {
        ivec2 bLoc = calcBandLoc(bandLoc, uint(i));
        ivec2 cLoc = decodeBandCurveLoc(texelFetch(u_band_tex, ivec3(bLoc, layer), 0).xy);
        if (!accumulateHintedTextSegment(cov, wgt, sampleRc, ppe, fetchHintedQuadraticSegment(cLoc, layer, record), horizontal) && ordered) break;
    }
    return vec2(cov, wgt);
}
#endif

struct BandSpan {
    int first;
    int last;
};

#if SNAIL_ENABLE_HINTED_TEXT
vec2 evalHintedTextBandSpan(vec2 sampleRc, float ppe, ivec2 gLoc, int headerBase, BandSpan span, int layer, bool horizontal, HintedTextRecord record) {
    if (span.first == span.last) {
        return evalHintedTextSingleBand(sampleRc, ppe, gLoc, headerBase + span.first, layer, horizontal, record);
    }
    return evalAxisCoverageBandsHinted(sampleRc, ppe, gLoc, headerBase, span.first, span.last, layer, horizontal, record);
}
#endif

// Convert the pixel footprint into band space. Near a band boundary the
// renderer evaluates the covered band span and de-duplicates curve records,
// avoiding one-pixel cracks under fractional pan/zoom transforms.
BandSpan coverageBandSpan(float coord, float eppAxis, float bandScale, float bandOffset, int bandMax) {
    float center = coord * bandScale + bandOffset;
    float halfWidth = max(abs(eppAxis * bandScale) * 0.5, kParamEps);
    int first = clamp(int(center - halfWidth), 0, bandMax);
    int last = clamp(int(center + halfWidth), 0, bandMax);
    return BandSpan(first, max(first, last));
}

BandSpan expandBandSpan(BandSpan span, int pad, int bandMax) {
    return BandSpan(max(span.first - pad, 0), min(span.last + pad, bandMax));
}

#if SNAIL_ENABLE_PATH
float evalGlyphCoverage(vec2 rc, vec2 epp, vec2 ppe,
                        ivec2 gLoc, ivec2 bandMax, vec4 banding, int texLayer) {
    BandSpan hSpan = coverageBandSpan(rc.y, epp.y, banding.y, banding.w, bandMax.y);
    BandSpan vSpan = coverageBandSpan(rc.x, epp.x, banding.x, banding.z, bandMax.x);
    vec2 horiz = evalAxisCoverageBands(rc, ppe.x, gLoc, 0, hSpan.first, hSpan.last, texLayer, true);
    vec2 vert = evalAxisCoverageBands(rc, ppe.y, gLoc, bandMax.y + 1, vSpan.first, vSpan.last, texLayer, false);
    float wsum = horiz.y + vert.y;
    float blended = horiz.x * horiz.y + vert.x * vert.y;
    float cov = max(applyFillRule(blended / max(wsum, kCoordEps)),
                    min(applyFillRule(horiz.x), applyFillRule(vert.x)));
    return applyCoverageTransfer(cov);
}
#endif

#if SNAIL_ENABLE_HINTED_TEXT
float evalHintedTextCoverage(vec2 rc, vec2 epp, vec2 ppe,
                             ivec2 gLoc, ivec2 bandMax, vec4 banding, int texLayer, HintedTextRecord record) {
    BandSpan hSpan = coverageBandSpan(rc.y, epp.y, banding.y, banding.w, bandMax.y);
    BandSpan vSpan = coverageBandSpan(rc.x, epp.x, banding.x, banding.z, bandMax.x);
    if (hintedTextHasExpandedBands(record)) {
        hSpan = expandBandSpan(hSpan, record.bandPad.x, bandMax.y);
        vSpan = expandBandSpan(vSpan, record.bandPad.y, bandMax.x);
    }
    vec2 horiz = evalHintedTextBandSpan(rc, ppe.x, gLoc, 0, hSpan, texLayer, true, record);
    vec2 vert = evalHintedTextBandSpan(rc, ppe.y, gLoc, bandMax.y + 1, vSpan, texLayer, false, record);
    float wsum = horiz.y + vert.y;
    float blended = horiz.x * horiz.y + vert.x * vert.y;
    float cov = max(applyFillRule(blended / max(wsum, kCoordEps)),
                    min(applyFillRule(horiz.x), applyFillRule(vert.x)));
    return applyCoverageTransfer(cov);
}
#endif

#if SNAIL_ENABLE_PATH
float wrapPaintT(float t, float extendMode) {
    int mode = int(extendMode + 0.5);
    if (mode == 1) {
        return fract(t);
    }
    if (mode == 2) {
        float reflected = mod(t, 2.0);
        if (reflected < 0.0) reflected += 2.0;
        return 1.0 - abs(reflected - 1.0);
    }
    return clamp(t, 0.0, 1.0);
}

vec4 sampleImagePaintTex(vec2 uv, int layer, int filterMode) {
    if (filterMode == 1) {
        ivec3 size = textureSize(u_image_tex, 0);
        ivec2 texel = clamp(ivec2(uv * vec2(size.xy)), ivec2(0), size.xy - ivec2(1));
        return texelFetch(u_image_tex, ivec3(texel, layer), 0);
    }
    return texture(u_image_tex, vec3(uv, float(layer)));
}

struct PathPaintSample {
    vec4 color;
    float gradient;
};

struct PathCompositeSample {
    vec4 color;
    float gradient;
};

float interleavedGradientNoise(vec2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
}

vec4 mixGradient(vec4 c0, vec4 c1, float t) {
    vec4 s0 = vec4(linearToSrgb(c0.rgb), c0.a);
    vec4 s1 = vec4(linearToSrgb(c1.rgb), c1.a);
    vec4 m = mix(s0, s1, t);
    return vec4(srgbToLinear(m.rgb), m.a);
}

vec4 ditherPremultipliedColor(vec4 color) {
    if (color.a <= 0.0) return color;
    float dither = (interleavedGradientNoise(gl_FragCoord.xy) - 0.5) * (clamp(color.a, 0.0, 1.0) / 255.0);
    vec3 srgb = clamp(linearToSrgb(color.rgb) + vec3(dither), 0.0, 1.0);
    return vec4(srgbToLinear(srgb), color.a);
}

PathPaintSample samplePathPaint(vec2 rc, ivec2 infoBase, vec4 info) {
    int paintKind = int(-info.w + 0.5);
    vec4 data0 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 2), 0);
    if (paintKind == SNAIL_PAINT_KIND_SOLID) {
        return PathPaintSample(vec4(srgbDecode(data0.r), srgbDecode(data0.g), srgbDecode(data0.b), data0.a), 0.0);
    }

    vec4 color0 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 3), 0);
    vec4 color1 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 4), 0);

    if (paintKind == SNAIL_PAINT_KIND_LINEAR_GRADIENT) {
        vec2 delta = data0.zw - data0.xy;
        float lenSq = dot(delta, delta);
        float t = 0.0;
        if (lenSq > 1e-10) {
            t = dot(rc - data0.xy, delta) / lenSq;
        }
        vec4 extra = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 5), 0);
        return PathPaintSample(mixGradient(color0, color1, wrapPaintT(t, extra.x)), 1.0);
    }

    if (paintKind == SNAIL_PAINT_KIND_RADIAL_GRADIENT) {
        float radius = max(abs(data0.z), kCoordEps);
        float t = length(rc - data0.xy) / radius;
        return PathPaintSample(mixGradient(color0, color1, wrapPaintT(t, data0.w)), 1.0);
    }

    if (paintKind == SNAIL_PAINT_KIND_IMAGE) {
        vec4 data1 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 3), 0);
        vec4 tint = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 4), 0);
        vec4 extra = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 5), 0);
        vec2 rawUv = vec2(
            dot(vec3(rc, 1.0), vec3(data0.x, data0.y, data0.z)),
            dot(vec3(rc, 1.0), vec3(data1.x, data1.y, data1.z))
        );
        vec2 wrappedUv = vec2(
            wrapPaintT(rawUv.x, extra.z) * extra.x,
            wrapPaintT(rawUv.y, extra.w) * extra.y
        );
        return PathPaintSample(sampleImagePaintTex(wrappedUv, int(data0.w + 0.5), int(data1.w + 0.5)) * tint, 0.0);
    }

    return PathPaintSample(vec4(1.0, 0.0, 1.0, 1.0), 0.0);
}

PathCompositeSample compositePathGroup(vec2 rc, vec2 epp, vec2 ppe, ivec2 infoBase, vec4 header, int texLayer, vec4 tint) {
    int layer_count = int(header.x + 0.5);
    int composite_mode = int(header.y + 0.5);
    vec4 result = vec4(0.0);
    float has_gradient = 0.0;
    float fill_cov = 0.0;
    float stroke_cov = 0.0;
    PathPaintSample fill_paint = PathPaintSample(vec4(0.0), 0.0);
    PathPaintSample stroke_paint = PathPaintSample(vec4(0.0), 0.0);

    for (int l = 0; l < layer_count; l++) {
        ivec2 loc = offsetLayerLoc(infoBase, 1 + l * SNAIL_PAINT_TEXELS_PER_RECORD);
        vec4 info = texelFetch(u_layer_tex, loc, 0);
        vec4 band = texelFetch(u_layer_tex, offsetLayerLoc(loc, 1), 0);
        ivec2 gLoc = ivec2(info.xy);
        int bandMaxH = floatBitsToInt(info.z) & 0xFFFF;
        int bandMaxV = (floatBitsToInt(info.z) >> 16) & 0xFFFF;
        float cov = evalGlyphCoverage(rc, epp, ppe, gLoc, ivec2(bandMaxV, bandMaxH), band, texLayer);
        PathPaintSample paint = samplePathPaint(rc, loc, info);
        paint.color *= tint;

        if (composite_mode == SNAIL_PATH_COMPOSITE_MODE_FILL_STROKE_INSIDE && layer_count >= 2 && l < 2) {
            if (l == 0) {
                fill_cov = cov;
                fill_paint = paint;
            } else {
                stroke_cov = cov;
                stroke_paint = paint;
            }
            continue;
        }

        if (paint.gradient > 0.5 && cov > 1e-6) has_gradient = 1.0;
        vec4 premul = premultiplyColor(paint.color, cov);
        result = premul + result * (1.0 - premul.a);
    }

    if (composite_mode == SNAIL_PATH_COMPOSITE_MODE_FILL_STROKE_INSIDE && layer_count >= 2) {
        float border_cov = min(fill_cov, stroke_cov);
        float interior_cov = max(fill_cov - border_cov, 0.0);
        if (fill_paint.gradient > 0.5 && interior_cov > 1e-6) has_gradient = 1.0;
        if (stroke_paint.gradient > 0.5 && border_cov > 1e-6) has_gradient = 1.0;
        vec4 combined = premultiplyColor(fill_paint.color, interior_cov) + premultiplyColor(stroke_paint.color, border_cov);
        result = result + combined * (1.0 - result.a);
    }

    return PathCompositeSample(result, has_gradient);
}
#endif

void main() {
    vec2 rc = v_texcoord;
    vec2 dx = vec2(dFdx(rc.x), dFdy(rc.x));
    vec2 dy = vec2(dFdx(rc.y), dFdy(rc.y));
    vec2 epp = vec2(length(dx), length(dy));
    vec2 ppe = 1.0 / max(epp, vec2(1.0 / 65536.0));

    int special_kind = v_glyph.w & 0xFF;
    if (((v_glyph.w >> 8) & 0xFF) != SNAIL_SPECIAL_LAYER_SENTINEL) discard;
#if SNAIL_ENABLE_PATH && SNAIL_ENABLE_HINTED_TEXT
    if (special_kind != SNAIL_SPECIAL_KIND_PATH && special_kind != SNAIL_SPECIAL_KIND_HINTED_TEXT) discard;
#elif SNAIL_ENABLE_PATH
    if (special_kind != SNAIL_SPECIAL_KIND_PATH) discard;
#elif SNAIL_ENABLE_HINTED_TEXT
    if (special_kind != SNAIL_SPECIAL_KIND_HINTED_TEXT) discard;
#else
    discard;
#endif
    ivec2 infoBase = v_glyph.xy;
    vec4 firstInfo = texelFetch(u_layer_tex, infoBase, 0);

    int texLayer = u_layer_base + int(v_banding.w);
    vec4 linear_tint = vec4(srgbDecode(v_tint.r), srgbDecode(v_tint.g), srgbDecode(v_tint.b), v_tint.a);
#if SNAIL_ENABLE_HINTED_TEXT
    if (special_kind == SNAIL_SPECIAL_KIND_HINTED_TEXT) {
        vec4 band = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 1), 0);
        vec4 meta = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 2), 0);
        ivec2 gLoc = ivec2(firstInfo.xy);
        int bandMaxH = floatBitsToInt(firstInfo.z) & 0xFFFF;
        int bandMaxV = (floatBitsToInt(firstInfo.z) >> 16) & 0xFFFF;
        HintedTextRecord record;
        record.infoBase = infoBase;
        record.baseCurveTexel = int(meta.x + 0.5);
        record.curveCount = int(meta.y + 0.5);
        record.flags = int(meta.z + 0.5);
        int bandPad = int(meta.w + 0.5);
        record.bandPad = ivec2(bandPad & 0xffff, bandPad >> 16);
        float cov = evalHintedTextCoverage(rc, epp, ppe, gLoc, ivec2(bandMaxV, bandMaxH), band, texLayer, record);
        if (cov < 1.0 / 255.0) discard;
        vec4 linear_color = vec4(srgbDecode(v_color.r), srgbDecode(v_color.g), srgbDecode(v_color.b), v_color.a);
        vec4 result = premultiplyColor(linear_color * linear_tint, cov);
        frag_color = (SNAIL_OUTPUT_SRGB != 0) ? srgbEncodePremultiplied(result) : result;
        return;
    }
#endif

#if SNAIL_ENABLE_PATH
    if (special_kind != SNAIL_SPECIAL_KIND_PATH) discard;
    if (firstInfo.w >= 0.0) discard;
    if (int(-firstInfo.w + 0.5) == SNAIL_PAINT_KIND_COMPOSITE_GROUP) {
        PathCompositeSample result = compositePathGroup(rc, epp, ppe, infoBase, firstInfo, texLayer, linear_tint);
        if (result.color.a < 1.0 / 255.0) discard;
        vec4 emit = (result.gradient > 0.5) ? ditherPremultipliedColor(result.color) : result.color;
        frag_color = (SNAIL_OUTPUT_SRGB != 0) ? srgbEncodePremultiplied(emit) : emit;
        return;
    }

    vec4 band = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 1), 0);
    ivec2 gLoc = ivec2(firstInfo.xy);
    int bandMaxH = floatBitsToInt(firstInfo.z) & 0xFFFF;
    int bandMaxV = (floatBitsToInt(firstInfo.z) >> 16) & 0xFFFF;
    float cov = evalGlyphCoverage(rc, epp, ppe, gLoc, ivec2(bandMaxV, bandMaxH), band, texLayer);
    if (cov < 1.0 / 255.0) discard;
    PathPaintSample paint = samplePathPaint(rc, infoBase, firstInfo);
    paint.color *= linear_tint;
    vec4 result = premultiplyColor(paint.color, cov);
    vec4 emit = (paint.gradient > 0.5) ? ditherPremultipliedColor(result) : result;
    frag_color = (SNAIL_OUTPUT_SRGB != 0) ? srgbEncodePremultiplied(emit) : emit;
    return;
#endif
    discard;
}
