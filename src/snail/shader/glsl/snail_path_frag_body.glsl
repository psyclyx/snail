#define kDirectEncodingKindBias 4.0
const float kParamEps = 1e-5;
const float kCoordEps = 1.0 / 65536.0;
const uint kBandCurveLocXMask = 0x0FFFu;
const uint kBandCurveLocYMask = 0x3FFFu;
const uint kBandCurveFirstMemberShift = 12u;
const uint kBandCurveKindShift = 14u;

ivec2 decodeBandCurveLoc(uvec2 ref) {
    return ivec2(int(ref.x & kBandCurveLocXMask), int(ref.y & kBandCurveLocYMask));
}

int decodeBandCurveFirstMember(uvec2 ref) {
    return int(ref.x >> kBandCurveFirstMemberShift);
}

int decodeBandCurveKind(uvec2 ref) {
    return int(ref.y >> kBandCurveKindShift);
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

bool solveMonotonicCubicRoot(float a, float b, float cVal, float d, float endDelta, out float tOut) {
    // Path preparation splits cubics at x/y extrema, so each uploaded cubic is
    // monotonic along both sampling axes and can contribute at most one root.
    float f0 = d;
    // Use the uploaded p3 directly. Reconstructing f(1) through a+b+c+d
    // loses enough precision near shallow extrema to corrupt the bracket.
    float f1 = endDelta;
    if ((f0 < -kCoordEps && f1 < -kCoordEps) || (f0 > kCoordEps && f1 > kCoordEps)) return false;

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
    tOut = t;
    return true;
}

bool clampSegmentRoot(float tRaw, out float t) {
    if (tRaw < -kParamEps || tRaw > 1.0 + kParamEps) return false;
    t = clamp(tRaw, 0.0, 1.0);
    return true;
}

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
        float sq = snapNearTangentSqrt(by * by - ay * p0y, by, ay * p0y);
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
        float sq = snapNearTangentSqrt(bx * bx - ax * p0x, bx, ax * p0x);
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

// Kind is now packed into the band ref's top 2 bits (see
// format/band_texture.zig::packBandCurveRef), so non-conic curves can
// skip the third texelFetch entirely — the weights field is only
// referenced by conic (kind=1). The indirect-encoding branch the
// original code switched on `tex2.z` against `kDirectEncodingKindBias`
// is no longer reachable from the path producer: every path glyph and
// every freed vector picture goes through `encodeDirectSingleGlyphCurves`
// / `prefer_direct_encoding = true`, so segments are always direct.
SegmentData fetchSegment(ivec2 loc, int layer, int kind) {
    vec4 tex0 = texelFetch(u_curve_tex, ivec3(loc, layer), 0);
    vec4 tex1 = texelFetch(u_curve_tex, ivec3(offsetCurveLoc(loc, 1), layer), 0);
    SegmentData seg;
    seg.kind = kind;
    seg.p0 = tex0.xy;
    seg.p1 = tex0.zw;
    seg.p2 = tex1.xy;
    seg.p3 = tex1.zw;
    if (kind == 1) {
        vec4 tex2 = texelFetch(u_curve_tex, ivec3(offsetCurveLoc(loc, 2), layer), 0);
        seg.weights = vec3(tex2.w, tex2.x, tex2.y);
    } else {
        seg.weights = vec3(1.0);
    }
    return seg;
}

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

void appendCoverageContribution(inout float cov, inout float wgt, float distance, float sign) {
    cov += sign * clamp(distance + 0.5, 0.0, 1.0);
    wgt = max(wgt, clamp(1.0 - abs(distance) * 2.0, 0.0, 1.0));
}

void accumulateLineCoverage(inout float cov, inout float wgt, float p0x, float p0y, float p2x, float p2y, float ppe, bool horizontal) {
    float rootAxis0 = horizontal ? p0y : p0x;
    float rootAxis2 = horizontal ? p2y : p2x;

    // Half-open sign-of-zero crossing test (same convention as `calcRootCode`).
    // A vertex exactly on the scanline snaps to +0 and reads as the positive
    // side, so a vertex shared with the next segment is owned by exactly one of
    // them. This replaces a plain `isNearEndRoot && isEndpointRootDelta` skip of
    // the line's end vertex: that skip assumed the next segment would count the
    // shared vertex, but at a line->conic junction the conic's start root can
    // FP-drift just outside [0,1] (worst at small authoring frames) and also
    // drop it -- leaving the crossing counted by neither, which collapses an
    // interior pixel's winding to zero (a dropped speck under perspective).
    float a0 = rootCodeCoord(rootAxis0);
    float a2 = rootCodeCoord(rootAxis2);
    if ((a0 < 0.0) == (a2 < 0.0)) return;

    float denom = rootAxis2 - rootAxis0;
    if (abs(denom) < 1e-10) return;
    float t = clamp(-rootAxis0 / denom, 0.0, 1.0);

    float derivativeAxis = horizontal ? p2y - p0y : p0x - p2x;
    if (abs(derivativeAxis) <= kParamEps) return;

    float distance = (horizontal ? p0x + (p2x - p0x) * t : p0y + (p2y - p0y) * t) * ppe;
    appendCoverageContribution(cov, wgt, distance, derivativeAxis > 0.0 ? 1.0 : -1.0);
}

float distToUnitInterval(float t) {
    return max(max(0.0, -t), t - 1.0);
}

void accumulateConicRoot(inout float cov,
                         inout float wgt,
                         float t,
                         float endRootDelta,
                         float sampleAlong,
                         float ppe,
                         bool horizontal,
                         float rootA,
                         float rootB,
                         float rootC,
                         float alongA,
                         float alongB,
                         float alongC,
                         float denA,
                         float denB,
                         float denC) {
    // No endpoint skip: crossing ownership at a shared vertex is decided by the
    // sign-of-zero `calcRootCode` gate in accumulateConicCoverage (matching the
    // line + quadratic paths), so the conic must count every root that survives
    // the gate -- otherwise a vertex the conic owns (conic-end meeting a
    // line-start on the scanline) is dropped by both segments.
    float den = max((denA * t + denB) * t + denC, kCoordEps);
    float along = ((alongA * t + alongB) * t + alongC) / den;
    float rootNumer = (rootA * t + rootB) * t + rootC;
    float rootPrime = 2.0 * rootA * t + rootB;
    float denPrime = 2.0 * denA * t + denB;
    float derivAxis = (rootPrime * den - rootNumer * denPrime) / (den * den);
    if (!horizontal) derivAxis = -derivAxis;
    if (abs(derivAxis) <= kParamEps) return;

    float dist = (along - sampleAlong) * ppe;
    appendCoverageContribution(cov, wgt, dist, derivAxis > 0.0 ? 1.0 : -1.0);
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
    // Half-open ownership gate (same sign-of-zero convention as the line and the
    // quadratic-bezier path): the conic contributes a crossing only where the
    // Bernstein control values (c0,c1,c2) actually change sign. This keeps the
    // conic from double-claiming -- or, at a shared vertex, both dropping -- a
    // crossing that the neighbouring line owns. Weights are positive, so the c_i
    // signs match the raw coordinate deltas the code expects.
    uint code = calcRootCode(c0, c1, c2);
    if (code == 0u) return;

    // `calcRootCode` is the robust source of truth for the crossing count. The
    // polynomial solve only supplies the parameter values, which can FP-drift
    // just outside [0,1] at a shared vertex; clamp them in (never reject) so a
    // crossing the conic owns is not dropped. `want` = popcount of the code.
    int want = (code == 0x0101u) ? 2 : 1;
    float quadA = c0 - 2.0 * c1 + c2;
    float quadB = 2.0 * (c1 - c0);
    float cand0 = 0.0;
    float cand1 = 0.0;
    int ncand = 0;
    if (abs(quadA) < kCoordEps) {
        if (abs(quadB) >= kCoordEps) {
            cand0 = -c0 / quadB;
            ncand = 1;
        }
    } else {
        float disc = max(quadB * quadB - 4.0 * quadA * c0, 0.0); // <0: near-tangent double root
        float sqrtDisc = sqrt(disc);
        float inv2a = 0.5 / quadA;
        cand0 = (-quadB - sqrtDisc) * inv2a;
        cand1 = (-quadB + sqrtDisc) * inv2a;
        ncand = 2;
    }
    if (ncand == 0) return;

    float root0;
    float root1 = 0.0;
    int rootCount;
    if (want == 1) {
        // Nearest candidate to [0,1], clamped.
        root0 = (ncand == 2 && distToUnitInterval(cand1) < distToUnitInterval(cand0)) ? cand1 : cand0;
        root0 = clamp(root0, 0.0, 1.0);
        rootCount = 1;
    } else {
        root0 = clamp(cand0, 0.0, 1.0);
        root1 = clamp(cand1, 0.0, 1.0);
        rootCount = 2;
    }

    float rootA = p0Root * seg.weights.x - 2.0 * p1Root * seg.weights.y + p2Root * seg.weights.z;
    float rootB = 2.0 * (p1Root * seg.weights.y - p0Root * seg.weights.x);
    float rootC = p0Root * seg.weights.x;
    float alongA = p0Along * seg.weights.x - 2.0 * p1Along * seg.weights.y + p2Along * seg.weights.z;
    float alongB = 2.0 * (p1Along * seg.weights.y - p0Along * seg.weights.x);
    float alongC = p0Along * seg.weights.x;
    float denA = seg.weights.x - 2.0 * seg.weights.y + seg.weights.z;
    float denB = 2.0 * (seg.weights.y - seg.weights.x);
    float denC = seg.weights.x;
    float endRootDelta = segmentEndRootDelta(seg, sampleRc, horizontal);

    accumulateConicRoot(cov, wgt, root0, endRootDelta, sampleAlong, ppe, horizontal,
                        rootA, rootB, rootC, alongA, alongB, alongC, denA, denB, denC);
    if (rootCount == 2) {
        accumulateConicRoot(cov, wgt, root1, endRootDelta, sampleAlong, ppe, horizontal,
                            rootA, rootB, rootC, alongA, alongB, alongC, denA, denB, denC);
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

    // Decide half-open endpoint ownership before solving, using the same +0
    // convention as lines, quadratics, and conics. Reconstructing f(1) from
    // rootA+rootB+rootC+d can move an endpoint root by a few ULPs; under a
    // perspective transform that used to make ownership depend on the camera.
    float startDelta = p0Root - sampleRoot;
    float endDelta = p3Root - sampleRoot;
    if ((rootCodeCoord(startDelta) < 0.0) == (rootCodeCoord(endDelta) < 0.0)) return;

    float t = 0.0;
    if (abs(startDelta) <= kCoordEps) {
        t = 0.0;
    } else if (abs(endDelta) <= kCoordEps) {
        t = 1.0;
    } else if (!solveMonotonicCubicRoot(rootA, rootB, rootC, startDelta, endDelta, t)) {
        return;
    }

    float alongA = -p0Along + 3.0 * p1Along - 3.0 * p2Along + p3Along;
    float alongB = 3.0 * p0Along - 6.0 * p1Along + 3.0 * p2Along;
    float alongC = -3.0 * p0Along + 3.0 * p1Along;

    float along = (t == 1.0) ? p3Along : ((alongA * t + alongB) * t + alongC) * t + p0Along;
    // Cubics are packed as monotonic spans.  Endpoint direction is the
    // scale-invariant winding sign, including stationary inflections and
    // near-tangent crossings whose derivative becomes tiny when a source path
    // is normalized into its unit design frame.
    float derivAxis = horizontal ? p3Root - p0Root : p0Root - p3Root;

    float dist = (along - sampleAlong) * ppe;
    appendCoverageContribution(cov, wgt, dist, derivAxis > 0.0 ? 1.0 : -1.0);
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
            int kind = decodeBandCurveKind(ref);
            if (!accumulateAxisCoverageSegment(cov, wgt, sampleRc, ppe, fetchSegment(cLoc, layer, kind), horizontal)) break;
        }
    }
    return vec2(cov, wgt);
}

struct BandSpan {
    int first;
    int last;
};

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

float evalGlyphCoverage(vec2 rc, vec2 epp, vec2 ppe,
                        ivec2 gLoc, ivec2 bandMax, vec4 banding, int texLayer, int fill_rule) {
    BandSpan hSpan = coverageBandSpan(rc.y, epp.y, banding.y, banding.w, bandMax.y);
    BandSpan vSpan = coverageBandSpan(rc.x, epp.x, banding.x, banding.z, bandMax.x);
    vec2 horiz = evalAxisCoverageBands(rc, ppe.x, gLoc, 0, hSpan.first, hSpan.last, texLayer, true);
    vec2 vert = evalAxisCoverageBands(rc, ppe.y, gLoc, bandMax.y + 1, vSpan.first, vSpan.last, texLayer, false);
    float wsum = horiz.y + vert.y;
    float blended = horiz.x * horiz.y + vert.x * vert.y;
    float cov = max(applyFillRule(blended / max(wsum, kCoordEps), fill_rule),
                    min(applyFillRule(horiz.x, fill_rule), applyFillRule(vert.x, fill_rule)));
    return applyCoverageTransfer(cov);
}

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
        // `.xy` directly on the query (never materializing the ivec3): the
        // arrayed size query's layer component trips naga's SPIR-V front end
        // during WGSL generation, and only the extent is wanted here anyway.
        ivec2 size = textureSize(u_image_tex, 0).xy;
        ivec2 texel = clamp(ivec2(uv * vec2(size)), ivec2(0), size - ivec2(1));
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

// Gradient endpoints are uploaded linear (paint_records writes them via
// srgbToLinearColor, like solid), so interpolation is linear-light — matching
// the rest of the pipeline and free of the sRGB-space muddy midpoint. No
// per-fragment sRGB conversion.
vec4 mixGradient(vec4 c0, vec4 c1, float t) {
    return mix(c0, c1, t);
}

vec4 ditherPremultipliedColor(vec4 color) {
    if (color.a <= 0.0 || SNAIL_DITHER_SCALE <= 0.0) return color; // float targets: no dither
    float dither = (interleavedGradientNoise(gl_FragCoord.xy) - 0.5) * (clamp(color.a, 0.0, 1.0) * SNAIL_DITHER_SCALE);
    vec3 srgb = clamp(linearToSrgb(color.rgb) + vec3(dither), 0.0, 1.0);
    return vec4(srgbToLinear(srgb), color.a);
}

PathPaintSample samplePathPaint(vec2 rc, ivec2 infoBase, vec4 info) {
    int paintKind = int(-info.w + 0.5);
    vec4 data0 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 2), 0);
    if (paintKind == SNAIL_PAINT_KIND_SOLID) {
        // Solid color stored linear at upload (paint_records.writePaint).
        return PathPaintSample(data0, 0.0);
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

    if (paintKind == SNAIL_PAINT_KIND_CONIC_GRADIENT) {
        // data0.xy = center, data0.z = start angle, data0.w = extend.
        // t sweeps the full turn; extend wraps it (repeat = standard conic,
        // reflect = seamless mirror). atan() here is atan2.
        vec2 d = rc - data0.xy;
        float t = (atan(d.y, d.x) - data0.z) * (1.0 / 6.28318530718);
        return PathPaintSample(mixGradient(color0, color1, wrapPaintT(t, data0.w)), 1.0);
    }

    if (paintKind == SNAIL_PAINT_KIND_IMAGE) {
        vec4 data1 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 3), 0);
        vec4 extra = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 5), 0);
        vec2 rawUv = vec2(
            dot(vec3(rc, 1.0), vec3(data0.x, data0.y, data0.z)),
            dot(vec3(rc, 1.0), vec3(data1.x, data1.y, data1.z))
        );
        vec2 wrappedUv = vec2(
            wrapPaintT(rawUv.x, extra.z) * extra.x,
            wrapPaintT(rawUv.y, extra.w) * extra.y
        );
        // Image color modulation is per-instance tint (applied by the
        // caller in compositePathGroup / main), not a per-paint field.
        return PathPaintSample(sampleImagePaintTex(wrappedUv, int(data0.w + 0.5), int(data1.w + 0.5)), 0.0);
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
        int packed_gx = int(info.x);
        ivec2 gLoc = ivec2(packed_gx & 0x7FFF, int(info.y));
        int rec_fill_rule = (packed_gx >> 15) & 1;
        int bandMaxH = floatBitsToInt(info.z) & 0xFFFF;
        int bandMaxV = (floatBitsToInt(info.z) >> 16) & 0xFFFF;
        float cov = evalGlyphCoverage(rc, epp, ppe, gLoc, ivec2(bandMaxV, bandMaxH), band, texLayer, rec_fill_rule);
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

void snailPaintedFragment(int expected_special_kind) {
    vec2 rc = v_texcoord;
    vec2 epp = fwidth(rc);
    vec2 ppe = 1.0 / max(epp, vec2(1.0 / 65536.0));

    int special_kind = v_glyph.w & 0x3;
    if ((uint(v_glyph.w) & 0x8000u) == 0u) discard;
    if (special_kind != expected_special_kind) discard;

    ivec2 infoBase = v_glyph.xy;
    vec4 firstInfo = texelFetch(u_layer_tex, infoBase, 0);
    if (firstInfo.w >= 0.0) discard;

    int texLayer = u_layer_base + ((v_glyph.w >> 2) & 0xff);
    // v_tint arrives as a linear-light f16 vertex attribute.

    if (int(-firstInfo.w + 0.5) == SNAIL_PAINT_KIND_COMPOSITE_GROUP) {
        PathCompositeSample result = compositePathGroup(rc, epp, ppe, infoBase, firstInfo, texLayer, v_tint);
        if (result.color.a < 1.0 / 255.0) discard;
        vec4 emit = (result.gradient > 0.5) ? ditherPremultipliedColor(result.color) : result.color;
        frag_color = (SNAIL_MASK_OUTPUT != 0) ? vec4(emit.a) : ((SNAIL_OUTPUT_SRGB != 0) ? srgbEncodePremultiplied(emit) : emit);
        return;
    }

    vec4 band = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 1), 0);
    int packed_gx = int(firstInfo.x);
    ivec2 gLoc = ivec2(packed_gx & 0x7FFF, int(firstInfo.y));
    int rec_fill_rule = (packed_gx >> 15) & 1;
    int bandMaxH = floatBitsToInt(firstInfo.z) & 0xFFFF;
    int bandMaxV = (floatBitsToInt(firstInfo.z) >> 16) & 0xFFFF;
    float cov = evalGlyphCoverage(rc, epp, ppe, gLoc, ivec2(bandMaxV, bandMaxH), band, texLayer, rec_fill_rule);
    if (cov < 1.0 / 255.0) discard;
    PathPaintSample paint = samplePathPaint(rc, infoBase, firstInfo);
    paint.color *= v_tint;
    vec4 result = premultiplyColor(paint.color, cov);
    vec4 emit = (paint.gradient > 0.5) ? ditherPremultipliedColor(result) : result;
    frag_color = (SNAIL_MASK_OUTPUT != 0) ? vec4(emit.a) : ((SNAIL_OUTPUT_SRGB != 0) ? srgbEncodePremultiplied(emit) : emit);
}

void snailPathFragment() {
    snailPaintedFragment(SNAIL_SPECIAL_KIND_PATH);
}
