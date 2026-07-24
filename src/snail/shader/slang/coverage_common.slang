// Canonical shared coverage implementation.
//
// The coverage-transfer exponent is an explicit function parameter.
module coverage_common;

public static const int kLogBandTextureWidth = 12;
public static const float kRootCodeEps = 1.0 / 65536.0;
public static const float kCoverageBandSpanParamEps = 1.0 / 100000.0;
public static const uint kBandCurveLocXMaskCommon = 0x0FFFu;
public static const uint kBandCurveLocYMaskCommon = 0x3FFFu;
public static const uint kBandCurveFirstMemberShiftCommon = 12u;
public static const uint kBandCurveKindShiftCommon = 14u;

// Treat exact-edge float drift as the mathematical contour sample. The
// half-open segment convention still comes from the root ordering below.
public float rootCodeCoord(float v) {
    return (abs(v) <= kRootCodeEps) ? 0.0 : v;
}

// Snap a near-tangent discriminant in the cancellation-free quadratic
// solver. See snail_coverage_common.glsl for the full derivation; the
// relative tolerance accommodates ~24 ULPs of FP noise from the disc
// subtraction without disturbing genuine double-crossings.
public float snapNearTangentSqrt(float disc, float b, float ac) {
    float tol = max(b * b, abs(ac)) * 3.0e-6;
    return (disc <= tol) ? 0.0 : sqrt(disc);
}

public uint calcRootCode(float y1, float y2, float y3) {
    y1 = rootCodeCoord(y1);
    y2 = rootCodeCoord(y2);
    y3 = rootCodeCoord(y3);
    uint i1 = asuint(y1) >> 31u;
    uint i2 = asuint(y2) >> 30u;
    uint i3 = asuint(y3) >> 29u;
    uint shift = (i2 & 2u) | (i1 & ~2u);
    shift = (i3 & 4u) | (shift & ~4u);
    return ((0x2E74u >> shift) & 0x0101u);
}

public float applyFillRule(float winding, int fill_rule_mode) {
    if (fill_rule_mode == 1) {
        return 1.0 - abs(frac(winding * 0.5) * 2.0 - 1.0);
    }
    return abs(winding);
}

public float applyCoverageTransfer(float cov, float coverage_exponent) {
    float clamped = clamp(cov, 0.0, 1.0);
    float exponent = max(coverage_exponent, 1.0 / 65536.0);
    return (abs(exponent - 1.0) <= 1e-6) ? clamped : pow(clamped, exponent);
}

public int2 calcBandLoc(int2 glyphLoc, uint offset) {
    int2 loc = int2(glyphLoc.x + int(offset), glyphLoc.y);
    loc.y += loc.x >> kLogBandTextureWidth;
    loc.x &= (1 << kLogBandTextureWidth) - 1;
    return loc;
}

public int2 offsetCurveLoc(int2 base, int offset) {
    int2 loc = int2(base.x + offset, base.y);
    loc.y += loc.x >> kLogBandTextureWidth;
    loc.x &= (1 << kLogBandTextureWidth) - 1;
    return loc;
}

// ── Band span / dedup ──
//
// When a fragment's pixel footprint straddles a band boundary, the single
// `bandIdx` view would either land in band N or band N+1 depending on
// float truncation, and curves that overlap both bands would only be
// counted in one of them. Every touched band is evaluated and curves that
// appear in more than one are only counted at their first-member band.

public struct CoverageBandSpan {
    public int first;
    public int last;
};

public CoverageBandSpan computeCoverageBandSpan(float coord, float eppAxis, float bandScale, float bandOffset, int bandMax) {
    float center = coord * bandScale + bandOffset;
    float halfWidth = max(abs(eppAxis * bandScale) * 0.5, kCoverageBandSpanParamEps);
    int first = clamp(int(center - halfWidth), 0, bandMax);
    int last = clamp(int(center + halfWidth), 0, bandMax);
    CoverageBandSpan span = { first, max(first, last) };
    return span;
}

public int decodeBandCurveFirstMemberCommon(uint2 ref) {
    return int(ref.x >> kBandCurveFirstMemberShiftCommon);
}

public int2 decodeBandCurveLocCommon(uint2 ref) {
    return int2(int(ref.x & kBandCurveLocXMaskCommon), int(ref.y & kBandCurveLocYMaskCommon));
}

public int decodeBandCurveKindCommon(uint2 ref) {
    return int(ref.y >> kBandCurveKindShiftCommon);
}

public bool isCoverageBandSpanOwner(uint2 ref, int band, int spanFirst) {
    int firstMember = decodeBandCurveFirstMemberCommon(ref);
    return band == max(firstMember, spanFirst);
}
