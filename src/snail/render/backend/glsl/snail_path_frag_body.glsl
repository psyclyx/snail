#define kDirectEncodingKindBias 4.0
const float kParamEps = 1e-5;
const float kCoordEps = 1.0 / 65536.0;
const float kDerivativeEps = 1e-6;
const int kCubicRootIterations = 14;
const uint kBandCurveLocXMask = 0x0FFFu;
const uint kBandCurveFirstMemberShift = 12u;

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

struct SegmentRoots {
    int count;
    vec3 t;
};

struct SegmentData {
    int kind;
    vec2 p0;
    vec2 p1;
    vec2 p2;
    vec2 p3;
    vec3 weights;
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

float cubicValue(float p0, float p1, float p2, float p3, float t) {
    float mt = 1.0 - t;
    return mt * mt * mt * p0 + 3.0 * mt * mt * t * p1 + 3.0 * mt * t * t * p2 + t * t * t * p3;
}

float cubicDerivative(float p0, float p1, float p2, float p3, float t) {
    float mt = 1.0 - t;
    return 3.0 * mt * mt * (p1 - p0) + 6.0 * mt * t * (p2 - p1) + 3.0 * t * t * (p3 - p2);
}

void appendCubicRootInterval(inout SegmentRoots roots, float p0, float p1, float p2, float p3, float target, float lo, float hi) {
    if (hi - lo <= kParamEps) return;

    float flo = cubicValue(p0, p1, p2, p3, lo) - target;
    float fhi = cubicValue(p0, p1, p2, p3, hi) - target;

    if (abs(flo) <= kCoordEps) {
        appendRoot(roots, lo);
        return;
    }
    if (abs(fhi) <= kCoordEps) {
        appendRoot(roots, hi);
        return;
    }
    if ((flo < 0.0) == (fhi < 0.0)) return;

    float denom = abs(flo) + abs(fhi);
    float t = (denom > kCoordEps) ? mix(lo, hi, abs(flo) / denom) : (lo + hi) * 0.5;
    for (int i = 0; i < kCubicRootIterations; i++) {
        float f = cubicValue(p0, p1, p2, p3, t) - target;
        float df = cubicDerivative(p0, p1, p2, p3, t);
        if ((f < 0.0) == (flo < 0.0)) {
            lo = t;
            flo = f;
        } else {
            hi = t;
            fhi = f;
        }

        float next = t;
        if (abs(df) > kDerivativeEps) {
            next = t - f / df;
        }
        if (next <= lo || next >= hi) {
            next = (lo + hi) * 0.5;
        }
        t = next;
    }
    appendRoot(roots, (lo + hi) * 0.5);
}

SegmentRoots solveCubicRootsMonotonic(float p0, float p1, float p2, float p3, float target) {
    SegmentRoots roots;
    roots.count = 0;
    roots.t = vec3(0.0);

    float a = -p0 + 3.0 * p1 - 3.0 * p2 + p3;
    float b = 3.0 * p0 - 6.0 * p1 + 3.0 * p2;
    float c = -3.0 * p0 + 3.0 * p1;
    SegmentRoots extrema = solveQuadraticRoots(3.0 * a, 2.0 * b, c);

    float lo = 0.0;
    for (int i = 0; i < extrema.count; i++) {
        float hi = extrema.t[i];
        if (hi > lo + kParamEps && hi < 1.0 - kParamEps) {
            appendCubicRootInterval(roots, p0, p1, p2, p3, target, lo, hi);
            lo = hi;
        }
    }
    appendCubicRootInterval(roots, p0, p1, p2, p3, target, lo, 1.0);
    return roots;
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

vec2 evalSegmentPoint(SegmentData seg, float t) {
    float mt = 1.0 - t;
    if (seg.kind == 3) {
        return mix(seg.p0, seg.p2, t);
    }
    if (seg.kind == 1) {
        float b0 = mt * mt;
        float b1 = 2.0 * mt * t;
        float b2 = t * t;
        float bw0 = b0 * seg.weights.x;
        float bw1 = b1 * seg.weights.y;
        float bw2 = b2 * seg.weights.z;
        float denom = max(bw0 + bw1 + bw2, kCoordEps);
        return (seg.p0 * bw0 + seg.p1 * bw1 + seg.p2 * bw2) / denom;
    }
    return mt * mt * seg.p0 + 2.0 * mt * t * seg.p1 + t * t * seg.p2;
}

vec2 evalCubicPoint(SegmentData seg, float t) {
    float mt = 1.0 - t;
    return mt * mt * mt * seg.p0 + 3.0 * mt * mt * t * seg.p1 + 3.0 * mt * t * t * seg.p2 + t * t * t * seg.p3;
}

vec2 evalSegmentDerivative(SegmentData seg, float t) {
    float mt = 1.0 - t;
    if (seg.kind == 3) {
        return seg.p2 - seg.p0;
    }
    if (seg.kind == 1) {
        float b0 = mt * mt;
        float b1 = 2.0 * mt * t;
        float b2 = t * t;
        float db0 = -2.0 * mt;
        float db1 = 2.0 - 4.0 * t;
        float db2 = 2.0 * t;
        float bw0 = b0 * seg.weights.x;
        float bw1 = b1 * seg.weights.y;
        float bw2 = b2 * seg.weights.z;
        float dbw0 = db0 * seg.weights.x;
        float dbw1 = db1 * seg.weights.y;
        float dbw2 = db2 * seg.weights.z;
        float denom = max(bw0 + bw1 + bw2, kCoordEps);
        float denomPrime = dbw0 + dbw1 + dbw2;
        vec2 numer = seg.p0 * bw0 + seg.p1 * bw1 + seg.p2 * bw2;
        vec2 numerPrime = seg.p0 * dbw0 + seg.p1 * dbw1 + seg.p2 * dbw2;
        return (numerPrime * denom - numer * denomPrime) / (denom * denom);
    }
    return 2.0 * mt * (seg.p1 - seg.p0) + 2.0 * t * (seg.p2 - seg.p1);
}

vec2 evalCubicDerivative(SegmentData seg, float t) {
    float mt = 1.0 - t;
    return 3.0 * mt * mt * (seg.p1 - seg.p0) + 6.0 * mt * t * (seg.p2 - seg.p1) + 3.0 * t * t * (seg.p3 - seg.p2);
}

SegmentRoots solveSegmentHorizontalRoots(SegmentData seg, float py) {
    if (seg.kind == 3) {
        return solveQuadraticRoots(0.0, seg.p2.y - seg.p0.y, seg.p0.y - py);
    }
    if (seg.kind == 1) {
        float c0 = seg.weights.x * (seg.p0.y - py);
        float c1 = seg.weights.y * (seg.p1.y - py);
        float c2 = seg.weights.z * (seg.p2.y - py);
        return solveQuadraticRoots(c0 - 2.0 * c1 + c2, 2.0 * (c1 - c0), c0);
    }
    float a = seg.p0.y - 2.0 * seg.p1.y + seg.p2.y;
    float b = 2.0 * (seg.p1.y - seg.p0.y);
    return solveQuadraticRoots(a, b, seg.p0.y - py);
}

SegmentRoots solveSegmentVerticalRoots(SegmentData seg, float px) {
    if (seg.kind == 3) {
        return solveQuadraticRoots(0.0, seg.p2.x - seg.p0.x, seg.p0.x - px);
    }
    if (seg.kind == 1) {
        float c0 = seg.weights.x * (seg.p0.x - px);
        float c1 = seg.weights.y * (seg.p1.x - px);
        float c2 = seg.weights.z * (seg.p2.x - px);
        return solveQuadraticRoots(c0 - 2.0 * c1 + c2, 2.0 * (c1 - c0), c0);
    }
    float a = seg.p0.x - 2.0 * seg.p1.x + seg.p2.x;
    float b = 2.0 * (seg.p1.x - seg.p0.x);
    return solveQuadraticRoots(a, b, seg.p0.x - px);
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

bool isHalfOpenEndpointRoot(float t, float endRootDelta) {
    return t >= 1.0 - kParamEps && abs(endRootDelta) <= kCoordEps;
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
            cov += (horizontal ? 1.0 : -1.0) * clamp(roots.x + 0.5, 0.0, 1.0);
            wgt = max(wgt, clamp(1.0 - abs(roots.x) * 2.0, 0.0, 1.0));
        }
        if (code > 1u) {
            cov += (horizontal ? -1.0 : 1.0) * clamp(roots.y + 0.5, 0.0, 1.0);
            wgt = max(wgt, clamp(1.0 - abs(roots.y) * 2.0, 0.0, 1.0));
        }
        return true;
    }

    SegmentRoots roots = (seg.kind == 2)
        ? (horizontal
            ? solveCubicRootsMonotonic(seg.p0.y, seg.p1.y, seg.p2.y, seg.p3.y, sampleRc.y)
            : solveCubicRootsMonotonic(seg.p0.x, seg.p1.x, seg.p2.x, seg.p3.x, sampleRc.x))
        : (horizontal ? solveSegmentHorizontalRoots(seg, sampleRc.y) : solveSegmentVerticalRoots(seg, sampleRc.x));
    for (int ri = 0; ri < roots.count; ri++) {
        float t = roots.t[ri];
        // Treat segment intersections as half-open [0, 1) so shared joins
        // between adjacent segments are counted once instead of twice. Do not
        // drop near-end roots unless the sample is actually on the endpoint;
        // otherwise a shallow cubic can lose a thin interior column.
        if (isHalfOpenEndpointRoot(t, segmentEndRootDelta(seg, sampleRc, horizontal))) continue;
        vec2 point = (seg.kind == 2) ? evalCubicPoint(seg, t) : evalSegmentPoint(seg, t);
        vec2 deriv = (seg.kind == 2) ? evalCubicDerivative(seg, t) : evalSegmentDerivative(seg, t);
        float derivAxis = horizontal ? deriv.y : -deriv.x;
        if (abs(derivAxis) <= kParamEps) continue;
        float dist = (horizontal ? point.x - sampleRc.x : point.y - sampleRc.y) * ppe;
        cov += (derivAxis > 0.0 ? 1.0 : -1.0) * clamp(dist + 0.5, 0.0, 1.0);
        wgt = max(wgt, clamp(1.0 - abs(dist) * 2.0, 0.0, 1.0));
    }
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
    int first = clamp(int(floor(center - halfWidth)), 0, bandMax);
    int last = clamp(int(floor(center + halfWidth)), 0, bandMax);
    return BandSpan(first, max(first, last));
}

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
    if (paintKind == 1) {
        return PathPaintSample(vec4(srgbDecode(data0.r), srgbDecode(data0.g), srgbDecode(data0.b), data0.a), 0.0);
    }

    vec4 color0 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 3), 0);
    vec4 color1 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 4), 0);

    if (paintKind == 2) {
        vec2 delta = data0.zw - data0.xy;
        float lenSq = dot(delta, delta);
        float t = 0.0;
        if (lenSq > 1e-10) {
            t = dot(rc - data0.xy, delta) / lenSq;
        }
        vec4 extra = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 5), 0);
        return PathPaintSample(mixGradient(color0, color1, wrapPaintT(t, extra.x)), 1.0);
    }

    if (paintKind == 3) {
        float radius = max(abs(data0.z), kCoordEps);
        float t = length(rc - data0.xy) / radius;
        return PathPaintSample(mixGradient(color0, color1, wrapPaintT(t, data0.w)), 1.0);
    }

    if (paintKind == 4) {
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
        ivec2 loc = offsetLayerLoc(infoBase, 1 + l * 6);
        vec4 info = texelFetch(u_layer_tex, loc, 0);
        vec4 band = texelFetch(u_layer_tex, offsetLayerLoc(loc, 1), 0);
        ivec2 gLoc = ivec2(info.xy);
        int bandMaxH = floatBitsToInt(info.z) & 0xFFFF;
        int bandMaxV = (floatBitsToInt(info.z) >> 16) & 0xFFFF;
        float cov = evalGlyphCoverage(rc, epp, ppe, gLoc, ivec2(bandMaxV, bandMaxH), band, texLayer);
        PathPaintSample paint = samplePathPaint(rc, loc, info);
        paint.color *= tint;

        if (composite_mode == 1 && layer_count >= 2 && l < 2) {
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

    if (composite_mode == 1 && layer_count >= 2) {
        float border_cov = min(fill_cov, stroke_cov);
        float interior_cov = max(fill_cov - border_cov, 0.0);
        if (fill_paint.gradient > 0.5 && interior_cov > 1e-6) has_gradient = 1.0;
        if (stroke_paint.gradient > 0.5 && border_cov > 1e-6) has_gradient = 1.0;
        vec4 combined = premultiplyColor(fill_paint.color, interior_cov) + premultiplyColor(stroke_paint.color, border_cov);
        result = result + combined * (1.0 - result.a);
    }

    return PathCompositeSample(result, has_gradient);
}

void main() {
    vec2 rc = v_texcoord;
    vec2 dx = vec2(dFdx(rc.x), dFdy(rc.x));
    vec2 dy = vec2(dFdx(rc.y), dFdy(rc.y));
    vec2 epp = vec2(length(dx), length(dy));
    vec2 ppe = 1.0 / max(epp, vec2(1.0 / 65536.0));

    int special_kind = v_glyph.w & 0xFF;
    if (((v_glyph.w >> 8) & 0xFF) != 0xFF || special_kind != 1) discard;
    ivec2 infoBase = v_glyph.xy;
    vec4 firstInfo = texelFetch(u_layer_tex, infoBase, 0);
    if (firstInfo.w >= 0.0) discard;

    int texLayer = u_layer_base + int(v_banding.w);
    vec4 linear_tint = vec4(srgbDecode(v_tint.r), srgbDecode(v_tint.g), srgbDecode(v_tint.b), v_tint.a);
    if (int(-firstInfo.w + 0.5) == 5) {
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
}
