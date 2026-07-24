// Canonical arbitrary-path segment coverage evaluator and general
// paint-record sampler. COLRv0 uses colr_body.slang's smaller quadratic
// glyph + solid-layer path.
//
// Per-target plumbing:
//  - the four textures (+ the image sampler) and the per-draw scalars are
//    explicit function parameters; the family entry file owns global bindings.
//  - `texelFetch(tex, ivec3(l, a), 0)` becomes `tex.Load(int4(l, a, 0))`;
//    `texture(u_image_tex, vec3(uv, layer))` becomes
//    `image_tex.Sample(image_sampler, float3(uv, layer))`.
//  - GLSL-compatible `mod(t, 2.0)` is written out as its spec definition
//    `t - 2.0 * floor(t / 2.0)` (Slang's `fmod` is truncation-based).
//  - `gl_FragCoord.xy` arrives as the `frag_coord` parameter (the family
//    entry passes its SV_Position input).
module path_body;

import resource_types;
import render_abi;
import color_common;
import coverage_common;

static const float kParamEps = 1e-5;
static const float kCoordEps = 1.0 / 65536.0;

public struct PaintedParams {
    public int layer_base;
    public int output_srgb;
    public float coverage_exponent;
    public float dither_scale;
    public int mask_output;
};

int2 offsetLayerLoc(SnailFloatTexture2D layer_tex, int2 base, int offset) {
    uint uw, uh;
    layer_tex.GetDimensions(uw, uh);
    int width = int(uw);
    int texel = base.y * width + base.x + offset;
    return int2(texel % width, texel / width);
}

struct SegmentData {
    int kind;
    float2 p0;
    float2 p1;
    float2 p2;
    float2 p3;
    float3 weights;
};

bool solveMonotonicCubicRoot(float a, float b, float cVal, float d, float endDelta, out float tOut) {
    // Path preparation splits cubics at x/y extrema, so each uploaded cubic is
    // monotonic along both sampling axes and can contribute at most one root.
    tOut = 0.0;
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

float2 solveQuadraticHorizDistances(float p0x, float p0y, float p1x, float p1y, float p2x, float p2y, float ppeX) {
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
    return float2(x1 * ppeX, x2 * ppeX);
}

float2 solveQuadraticVertDistances(float p0x, float p0y, float p1x, float p1y, float p2x, float p2y, float ppeY) {
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
    return float2(y1 * ppeY, y2 * ppeY);
}

// Kind is packed into the band ref's top 2 bits (see
// format/band_texture.zig::packBandCurveRef), so non-conic curves can
// skip the third texel Load entirely — the weights field is only
// referenced by conic (kind=1). The indirect-encoding branch the
// original code switched on `tex2.z` against `kDirectEncodingKindBias`
// is no longer reachable from the path producer: every path glyph and
// every freed vector picture goes through `encodeDirectSingleGlyphCurves`
// / `prefer_direct_encoding = true`, so segments are always direct.
SegmentData fetchSegment(SnailFloatTexture2DArray curve_tex, int2 loc, int layer, int kind) {
    float4 tex0 = curve_tex.Load(int4(loc, layer, 0));
    float4 tex1 = curve_tex.Load(int4(offsetCurveLoc(loc, 1), layer, 0));
    SegmentData seg;
    seg.kind = kind;
    seg.p0 = tex0.xy;
    seg.p1 = tex0.zw;
    seg.p2 = tex1.xy;
    seg.p3 = tex1.zw;
    if (kind == 1) {
        float4 tex2 = curve_tex.Load(int4(offsetCurveLoc(loc, 2), layer, 0));
        seg.weights = float3(tex2.w, tex2.x, tex2.y);
    } else {
        seg.weights = float3(1.0);
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

float segmentEndRootDelta(SegmentData seg, float2 sampleRc, bool horizontal) {
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

bool segmentRootHullCanCross(SegmentData seg, float2 sampleRc, bool horizontal) {
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
    // them. See snail_path_frag_body.glsl for the full derivation.
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
    // the gate.
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

void accumulateConicCoverage(inout float cov, inout float wgt, SegmentData seg, float2 sampleRc, float ppe, bool horizontal) {
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
    // Bernstein control values (c0,c1,c2) actually change sign.
    uint code = calcRootCode(c0, c1, c2);
    if (code == 0u) return;

    // `calcRootCode` is the robust source of truth for the crossing count. The
    // polynomial solve only supplies the parameter values, which can FP-drift
    // just outside [0,1] at a shared vertex; clamp them in (never reject).
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

void accumulateCubicCoverage(inout float cov, inout float wgt, SegmentData seg, float2 sampleRc, float ppe, bool horizontal) {
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
    // convention as lines, quadratics, and conics.
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
    // Cubics are packed as monotonic spans. Endpoint direction is the
    // scale-invariant winding sign.
    float derivAxis = horizontal ? p3Root - p0Root : p0Root - p3Root;

    float dist = (along - sampleAlong) * ppe;
    appendCoverageContribution(cov, wgt, dist, derivAxis > 0.0 ? 1.0 : -1.0);
}

bool accumulateAxisCoverageSegment(inout float cov, inout float wgt, float2 sampleRc, float ppe, SegmentData seg, bool horizontal) {
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

        float2 roots = horizontal
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

float2 evalAxisCoverageBands(SnailFloatTexture2DArray curve_tex, SnailUint2Texture2DArray band_tex, float2 sampleRc, float ppe, int2 gLoc, int headerBase, int firstBand, int lastBand, int layer, bool horizontal) {
    float cov = 0.0;
    float wgt = 0.0;
    bool dedup = firstBand != lastBand;
    for (int band = firstBand; band <= lastBand; band++) {
        int2 headerLoc = calcBandLoc(gLoc, uint(headerBase + band));
        uint2 bd = band_tex.Load(int4(headerLoc, layer, 0)).xy;
        int2 bandLoc = calcBandLoc(gLoc, bd.y);
        int count = int(bd.x);
        for (int i = 0; i < count; i++) {
            int2 bLoc = calcBandLoc(bandLoc, uint(i));
            uint2 ref = band_tex.Load(int4(bLoc, layer, 0)).xy;
            if (dedup) {
                int ownerBand = max(decodeBandCurveFirstMemberCommon(ref), firstBand);
                if (band != ownerBand) continue;
            }
            int2 cLoc = decodeBandCurveLocCommon(ref);
            int kind = decodeBandCurveKindCommon(ref);
            if (!accumulateAxisCoverageSegment(cov, wgt, sampleRc, ppe, fetchSegment(curve_tex, cLoc, layer, kind), horizontal)) break;
        }
    }
    return float2(cov, wgt);
}

float evalPathGlyphCoverage(SnailFloatTexture2DArray curve_tex, SnailUint2Texture2DArray band_tex, float2 rc, float2 epp, float2 ppe,
                            int2 gLoc, int2 bandMax, float4 banding, int texLayer, int fill_rule, float coverage_exponent) {
    // Band-span epsilon: the GLSL body's coverageBandSpan uses kParamEps
    // (1e-5), the same value as coverage_common's
    // kCoverageBandSpanParamEps (1/100000).
    CoverageBandSpan hSpan = computeCoverageBandSpan(rc.y, epp.y, banding.y, banding.w, bandMax.y);
    CoverageBandSpan vSpan = computeCoverageBandSpan(rc.x, epp.x, banding.x, banding.z, bandMax.x);
    float2 horiz = evalAxisCoverageBands(curve_tex, band_tex, rc, ppe.x, gLoc, 0, hSpan.first, hSpan.last, texLayer, true);
    float2 vert = evalAxisCoverageBands(curve_tex, band_tex, rc, ppe.y, gLoc, bandMax.y + 1, vSpan.first, vSpan.last, texLayer, false);
    float wsum = horiz.y + vert.y;
    float blended = horiz.x * horiz.y + vert.x * vert.y;
    float cov = max(applyFillRule(blended / max(wsum, kCoordEps), fill_rule),
                    min(applyFillRule(horiz.x, fill_rule), applyFillRule(vert.x, fill_rule)));
    return applyCoverageTransfer(cov, coverage_exponent);
}

float wrapPaintT(float t, float extendMode) {
    int mode = int(extendMode + 0.5);
    if (mode == 1) {
        return frac(t);
    }
    if (mode == 2) {
        // GLSL `mod(t, 2.0)` written out per its spec definition
        // (floor-based; Slang's fmod truncates).
        float reflected = t - 2.0 * floor(t / 2.0);
        if (reflected < 0.0) reflected += 2.0;
        return 1.0 - abs(reflected - 1.0);
    }
    return clamp(t, 0.0, 1.0);
}

float4 sampleImagePaintTex(SnailFloatTexture2DArray image_tex, SnailSamplerState image_sampler, float2 uv, int layer, int filterMode) {
    if (filterMode == 1) {
        uint uw, uh, ue;
        image_tex.GetDimensions(uw, uh, ue);
        int2 size = int2(int(uw), int(uh));
        int2 texel = clamp(int2(uv * float2(size)), int2(0), size - int2(1));
        return image_tex.Load(int4(texel, layer, 0));
    }
    return snailSample2DArray(image_tex, image_sampler, float3(uv, float(layer)));
}

struct PathPaintSample {
    float4 color;
    float gradient;
};

struct PathCompositeSample {
    float4 color;
    float gradient;
};

float interleavedGradientNoise(float2 pixel) {
    return frac(52.9829189 * frac(dot(pixel, float2(0.06711056, 0.00583715))));
}

// Gradient endpoints are uploaded linear (paint_records writes them via
// srgbToLinearColor, like solid), so interpolation is linear-light.
float4 mixGradient(float4 c0, float4 c1, float t) {
    return lerp(c0, c1, t);
}

float4 ditherPremultipliedColor(float4 color, float2 frag_coord, float dither_scale) {
    if (color.a <= 0.0 || dither_scale <= 0.0) return color; // float targets: no dither
    float dither = (interleavedGradientNoise(frag_coord) - 0.5) * (clamp(color.a, 0.0, 1.0) * dither_scale);
    float3 srgb = clamp(linearToSrgb(color.rgb) + float3(dither), 0.0, 1.0);
    return float4(srgbToLinear(srgb), color.a);
}

PathPaintSample samplePathPaint(SnailFloatTexture2D layer_tex, SnailFloatTexture2DArray image_tex, SnailSamplerState image_sampler, float2 rc, int2 infoBase, float4 info) {
    int paintKind = int(-info.w + 0.5);
    float4 data0 = layer_tex.Load(int3(offsetLayerLoc(layer_tex, infoBase, 2), 0));
    if (paintKind == SNAIL_PAINT_KIND_SOLID) {
        // Solid color stored linear at upload (paint_records.writePaint).
        PathPaintSample s = { data0, 0.0 };
        return s;
    }

    float4 color0 = layer_tex.Load(int3(offsetLayerLoc(layer_tex, infoBase, 3), 0));
    float4 color1 = layer_tex.Load(int3(offsetLayerLoc(layer_tex, infoBase, 4), 0));

    if (paintKind == SNAIL_PAINT_KIND_LINEAR_GRADIENT) {
        float2 delta = data0.zw - data0.xy;
        float lenSq = dot(delta, delta);
        float t = 0.0;
        if (lenSq > 1e-10) {
            t = dot(rc - data0.xy, delta) / lenSq;
        }
        float4 extra = layer_tex.Load(int3(offsetLayerLoc(layer_tex, infoBase, 5), 0));
        PathPaintSample s = { mixGradient(color0, color1, wrapPaintT(t, extra.x)), 1.0 };
        return s;
    }

    if (paintKind == SNAIL_PAINT_KIND_RADIAL_GRADIENT) {
        float radius = max(abs(data0.z), kCoordEps);
        float t = length(rc - data0.xy) / radius;
        PathPaintSample s = { mixGradient(color0, color1, wrapPaintT(t, data0.w)), 1.0 };
        return s;
    }

    if (paintKind == SNAIL_PAINT_KIND_CONIC_GRADIENT) {
        // data0.xy = center, data0.z = start angle, data0.w = extend.
        // t sweeps the full turn; extend wraps it. GLSL two-arg atan is
        // atan2.
        float2 d = rc - data0.xy;
        float t = (atan2(d.y, d.x) - data0.z) * (1.0 / 6.28318530718);
        PathPaintSample s = { mixGradient(color0, color1, wrapPaintT(t, data0.w)), 1.0 };
        return s;
    }

    if (paintKind == SNAIL_PAINT_KIND_IMAGE) {
        float4 data1 = layer_tex.Load(int3(offsetLayerLoc(layer_tex, infoBase, 3), 0));
        float4 extra = layer_tex.Load(int3(offsetLayerLoc(layer_tex, infoBase, 5), 0));
        float2 rawUv = float2(
            dot(float3(rc, 1.0), float3(data0.x, data0.y, data0.z)),
            dot(float3(rc, 1.0), float3(data1.x, data1.y, data1.z))
        );
        float2 wrappedUv = float2(
            wrapPaintT(rawUv.x, extra.z) * extra.x,
            wrapPaintT(rawUv.y, extra.w) * extra.y
        );
        // Image color modulation is per-instance tint (applied by the
        // caller in compositePathGroup / the entry), not a per-paint field.
        PathPaintSample s = { sampleImagePaintTex(image_tex, image_sampler, wrappedUv, int(data0.w + 0.5), int(data1.w + 0.5)), 0.0 };
        return s;
    }

    PathPaintSample s = { float4(1.0, 0.0, 1.0, 1.0), 0.0 };
    return s;
}

PathCompositeSample compositePathGroup(SnailFloatTexture2DArray curve_tex, SnailUint2Texture2DArray band_tex, SnailFloatTexture2D layer_tex, SnailFloatTexture2DArray image_tex, SnailSamplerState image_sampler, float2 rc, float2 epp, float2 ppe, int2 infoBase, float4 header, int texLayer, float4 tint, float coverage_exponent) {
    int layer_count = int(header.x + 0.5);
    int composite_mode = int(header.y + 0.5);
    float4 result = float4(0.0);
    float has_gradient = 0.0;
    float fill_cov = 0.0;
    float stroke_cov = 0.0;
    PathPaintSample fill_paint = { float4(0.0), 0.0 };
    PathPaintSample stroke_paint = { float4(0.0), 0.0 };

    for (int l = 0; l < layer_count; l++) {
        int2 loc = offsetLayerLoc(layer_tex, infoBase, 1 + l * SNAIL_PAINT_TEXELS_PER_RECORD);
        float4 info = layer_tex.Load(int3(loc, 0));
        float4 band = layer_tex.Load(int3(offsetLayerLoc(layer_tex, loc, 1), 0));
        int packed_gx = int(info.x);
        int2 gLoc = int2(packed_gx & 0x7FFF, int(info.y));
        int rec_fill_rule = (packed_gx >> 15) & 1;
        int bandMaxH = asint(info.z) & 0xFFFF;
        int bandMaxV = (asint(info.z) >> 16) & 0xFFFF;
        float cov = evalPathGlyphCoverage(curve_tex, band_tex, rc, epp, ppe, gLoc, int2(bandMaxV, bandMaxH), band, texLayer, rec_fill_rule, coverage_exponent);
        PathPaintSample paint = samplePathPaint(layer_tex, image_tex, image_sampler, rc, loc, info);
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
        float4 premul = premultiplyColor(paint.color, cov);
        result = premul + result * (1.0 - premul.a);
    }

    if (composite_mode == SNAIL_PATH_COMPOSITE_MODE_FILL_STROKE_INSIDE && layer_count >= 2) {
        float border_cov = min(fill_cov, stroke_cov);
        float interior_cov = max(fill_cov - border_cov, 0.0);
        if (fill_paint.gradient > 0.5 && interior_cov > 1e-6) has_gradient = 1.0;
        if (stroke_paint.gradient > 0.5 && border_cov > 1e-6) has_gradient = 1.0;
        float4 combined = premultiplyColor(fill_paint.color, interior_cov) + premultiplyColor(stroke_paint.color, border_cov);
        result = result + combined * (1.0 - result.a);
    }

    PathCompositeSample out_sample = { result, has_gradient };
    return out_sample;
}

public struct PaintedVaryings {
    public float4 tint;
    public float2 texcoord;
    public float4 banding;
    public int4 glyph;
};

public float4 snailPaintedFragment(
    PaintedVaryings v,
    float2 frag_coord,
    SnailFloatTexture2DArray curve_tex,
    SnailUint2Texture2DArray band_tex,
    SnailFloatTexture2D layer_tex,
    SnailFloatTexture2DArray image_tex,
    SnailSamplerState image_sampler,
    PaintedParams p)
{
    float2 rc = v.texcoord;
    float2 epp = fwidth(rc);
    float2 ppe = 1.0 / max(epp, float2(1.0 / 65536.0));

    int special_kind = v.glyph.w & 0x3;
    if ((uint(v.glyph.w) & 0x8000u) == 0u) discard;
    if (special_kind != SNAIL_SPECIAL_KIND_COLR && special_kind != SNAIL_SPECIAL_KIND_PATH) discard;

    int2 infoBase = v.glyph.xy;
    float4 firstInfo = layer_tex.Load(int3(infoBase, 0));
    if (firstInfo.w >= 0.0) discard;

    int texLayer = p.layer_base + ((v.glyph.w >> 2) & 0xff);
    // v.tint arrives as a linear-light f16 vertex attribute.

    if (int(-firstInfo.w + 0.5) == SNAIL_PAINT_KIND_COMPOSITE_GROUP) {
        PathCompositeSample result = compositePathGroup(curve_tex, band_tex, layer_tex, image_tex, image_sampler, rc, epp, ppe, infoBase, firstInfo, texLayer, v.tint, p.coverage_exponent);
        if (result.color.a < 1.0 / 255.0) discard;
        float4 emit = (result.gradient > 0.5) ? ditherPremultipliedColor(result.color, frag_coord, p.dither_scale) : result.color;
        return (p.mask_output != 0) ? float4(emit.a) : ((p.output_srgb != 0) ? srgbEncodePremultiplied(emit) : emit);
    }

    float4 band = layer_tex.Load(int3(offsetLayerLoc(layer_tex, infoBase, 1), 0));
    int packed_gx = int(firstInfo.x);
    int2 gLoc = int2(packed_gx & 0x7FFF, int(firstInfo.y));
    int rec_fill_rule = (packed_gx >> 15) & 1;
    int bandMaxH = asint(firstInfo.z) & 0xFFFF;
    int bandMaxV = (asint(firstInfo.z) >> 16) & 0xFFFF;
    float cov = evalPathGlyphCoverage(curve_tex, band_tex, rc, epp, ppe, gLoc, int2(bandMaxV, bandMaxH), band, texLayer, rec_fill_rule, p.coverage_exponent);
    if (cov < 1.0 / 255.0) discard;
    PathPaintSample paint = samplePathPaint(layer_tex, image_tex, image_sampler, rc, infoBase, firstInfo);
    paint.color *= v.tint;
    float4 result = premultiplyColor(paint.color, cov);
    float4 emit = (paint.gradient > 0.5) ? ditherPremultipliedColor(result, frag_coord, p.dither_scale) : result;
    return (p.mask_output != 0) ? float4(emit.a) : ((p.output_srgb != 0) ? srgbEncodePremultiplied(emit) : emit);
}
