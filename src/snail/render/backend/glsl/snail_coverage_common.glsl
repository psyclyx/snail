#ifndef SNAIL_COVERAGE_COMMON_GLSL
#define SNAIL_COVERAGE_COMMON_GLSL

#define kLogBandTextureWidth 12
#define kRootCodeEps (1.0 / 65536.0)

// Treat exact-edge float drift as the mathematical contour sample. The
// half-open segment convention still comes from the root ordering below.
float rootCodeCoord(float v) {
    return (abs(v) <= kRootCodeEps) ? 0.0 : v;
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

#endif
