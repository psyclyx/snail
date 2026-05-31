#ifndef SNAIL_COVERAGE_COMMON_GLSL
#define SNAIL_COVERAGE_COMMON_GLSL

#define kLogBandTextureWidth 12
#define kRootCodeEps (1.0 / 65536.0)
#define kCoverageBandSpanParamEps (1.0 / 100000.0)
#define kBandCurveLocXMaskCommon 0x0FFFu
#define kBandCurveFirstMemberShiftCommon 12u

// Treat exact-edge float drift as the mathematical contour sample. The
// half-open segment convention still comes from the root ordering below.
float rootCodeCoord(float v) {
    return (abs(v) <= kRootCodeEps) ? 0.0 : v;
}

// Snap a near-tangent discriminant in the cancellation-free quadratic
// solver. When a curve mathematically grazes the sample line the true
// discriminant is zero, but FP cancellation in `b^2 - a*c` leaves it tiny
// and positive. The two roots then differ by `2*sqrt(disc)/a`, the two
// along-coordinates differ, and the ±-signed `clamp(distance + 0.5, 0, 1)`
// contributions stop cancelling -- leaving a visible coverage residual on
// pixels that should be fully outside (or fully inside) the shape and on
// other pixels in the same scanline. The relative tolerance accommodates
// the FP noise from the disc subtraction (~24 ULPs of the dominant
// operand) without disturbing genuine double-crossings.
float snapNearTangentSqrt(float disc, float b, float ac) {
    float tol = max(b * b, abs(ac)) * 3.0e-6;
    return (disc <= tol) ? 0.0 : sqrt(disc);
}

uint calcRootCode(float y1, float y2, float y3) {
    y1 = rootCodeCoord(y1);
    y2 = rootCodeCoord(y2);
    y3 = rootCodeCoord(y3);
    uint i1 = floatBitsToUint(y1) >> 31u;
    uint i2 = floatBitsToUint(y2) >> 30u;
    uint i3 = floatBitsToUint(y3) >> 29u;
    uint shift = (i2 & 2u) | (i1 & ~2u);
    shift = (i3 & 4u) | (shift & ~4u);
    return ((0x2E74u >> shift) & 0x0101u);
}

float applyFillRule(float winding, int fill_rule_mode) {
    if (fill_rule_mode == 1) {
        return 1.0 - abs(fract(winding * 0.5) * 2.0 - 1.0);
    }
    return abs(winding);
}

// Backwards-compat overload: text / colr / hinted glyphs from fonts are
// always non-zero winding. Callers that don't have a per-record rule
// (i.e. anything that's not a path paint record) call this overload.
float applyFillRule(float winding) {
    return applyFillRule(winding, 0);
}

#ifndef SNAIL_COVERAGE_EXPONENT
#define SNAIL_COVERAGE_EXPONENT 1.0
#endif

float applyCoverageTransfer(float cov) {
    float clamped = clamp(cov, 0.0, 1.0);
    float exponent = max(float(SNAIL_COVERAGE_EXPONENT), 1.0 / 65536.0);
    return (abs(exponent - 1.0) <= 1e-6) ? clamped : pow(clamped, exponent);
}

ivec2 calcBandLoc(ivec2 glyphLoc, uint offset) {
    ivec2 loc = ivec2(glyphLoc.x + int(offset), glyphLoc.y);
    loc.y += loc.x >> kLogBandTextureWidth;
    loc.x &= (1 << kLogBandTextureWidth) - 1;
    return loc;
}

ivec2 offsetCurveLoc(ivec2 base, int offset) {
    ivec2 loc = ivec2(base.x + offset, base.y);
    loc.y += loc.x >> kLogBandTextureWidth;
    loc.x &= (1 << kLogBandTextureWidth) - 1;
    return loc;
}

// ── Band span / dedup ──
//
// When a fragment's pixel footprint straddles a band boundary, the single
// `bandIdx` view would either land in band N or band N+1 depending on
// float truncation, and curves that overlap both bands would only be
// counted in one of them. The path / hinted-text shaders evaluate every
// touched band and de-duplicate curves that appear in more than one by
// only counting them at their first-member band. Text / colr / subpixel
// shaders use the same helpers below.

struct CoverageBandSpan {
    int first;
    int last;
};

CoverageBandSpan computeCoverageBandSpan(float coord, float eppAxis, float bandScale, float bandOffset, int bandMax) {
    float center = coord * bandScale + bandOffset;
    float halfWidth = max(abs(eppAxis * bandScale) * 0.5, kCoverageBandSpanParamEps);
    int first = clamp(int(center - halfWidth), 0, bandMax);
    int last = clamp(int(center + halfWidth), 0, bandMax);
    return CoverageBandSpan(first, max(first, last));
}

int decodeBandCurveFirstMemberCommon(uvec2 ref) {
    return int(ref.x >> kBandCurveFirstMemberShiftCommon);
}

ivec2 decodeBandCurveLocCommon(uvec2 ref) {
    return ivec2(int(ref.x & kBandCurveLocXMaskCommon), int(ref.y));
}

bool isCoverageBandSpanOwner(uvec2 ref, int band, int spanFirst) {
    int firstMember = decodeBandCurveFirstMemberCommon(ref);
    return band == max(firstMember, spanFirst);
}

#endif
