// Native-Slang port of snail_text_frag_body.glsl — the text-family glyph
// coverage evaluator. The GLSL fragment is the behavioral spec: every
// epsilon, literal, and operation order is preserved.
//
// Structural differences from GLSL (plumbing only, math unchanged):
//  - `u_curve_tex` / `u_band_tex` are explicit `Texture2DArray` parameters
//    (Slang-native style; the family entry file owns the global bindings).
//  - `texelFetch(tex, ivec3(loc, layer), 0)` becomes
//    `tex.Load(int4(loc, layer, 0))` (same texel, mip 0).
//  - the coverage-transfer exponent is threaded through as a parameter.
module text_coverage;

import resource_types;

import coverage_common;

public int2 decodeBandCurveLoc(uint2 ref) {
    return decodeBandCurveLocCommon(ref);
}

// Solve a*t² - 2*b*t + p0 = 0 using the cancellation-free form
// q = b + sign(b)*sqrt(disc); roots are q/a and p0/q (Vieta).
// Preserves the original t1=(b-d)/a, t2=(b+d)/a ordering so downstream
// `calcRootCode` bit interpretation stays correct.
public float2 solveHorizPoly(float4 p12, float2 p3) {
    float2 a = p12.xy - p12.zw * 2.0 + p3;
    float2 b = p12.xy - p12.zw;
    const float kEps = 1.0 / 65536.0;
    float t1, t2;
    if (abs(a.y) < kEps) {
        t1 = (abs(b.y) < kEps) ? 0.0 : p12.y * 0.5 / b.y;
        t2 = t1;
    } else {
        float sq = snapNearTangentSqrt(b.y * b.y - a.y * p12.y, b.y, a.y * p12.y);
        if (b.y >= 0.0) {
            float q = b.y + sq;
            t2 = q / a.y;
            t1 = (abs(q) < kEps) ? 0.0 : p12.y / q;
        } else {
            float q = b.y - sq;
            t1 = q / a.y;
            t2 = (abs(q) < kEps) ? 0.0 : p12.y / q;
        }
    }
    return float2((a.x * t1 - b.x * 2.0) * t1 + p12.x,
                  (a.x * t2 - b.x * 2.0) * t2 + p12.x);
}

public float2 solveVertPoly(float4 p12, float2 p3) {
    float2 a = p12.xy - p12.zw * 2.0 + p3;
    float2 b = p12.xy - p12.zw;
    const float kEps = 1.0 / 65536.0;
    float t1, t2;
    if (abs(a.x) < kEps) {
        t1 = (abs(b.x) < kEps) ? 0.0 : p12.x * 0.5 / b.x;
        t2 = t1;
    } else {
        float sq = snapNearTangentSqrt(b.x * b.x - a.x * p12.x, b.x, a.x * p12.x);
        if (b.x >= 0.0) {
            float q = b.x + sq;
            t2 = q / a.x;
            t1 = (abs(q) < kEps) ? 0.0 : p12.x / q;
        } else {
            float q = b.x - sq;
            t1 = q / a.x;
            t2 = (abs(q) < kEps) ? 0.0 : p12.x / q;
        }
    }
    return float2((a.y * t1 - b.y * 2.0) * t1 + p12.y,
                  (a.y * t2 - b.y * 2.0) * t2 + p12.y);
}

// Accumulate one quadratic's horizontal coverage contribution. Returns
// false when the curve's max-along is behind sampleRc, so ordered band
// scans can stop early.
public bool accumulateHorizContribution(inout float xcov, inout float xwgt, float2 rc, float2 ppe, int2 cLoc, int texLayer, SnailFloatTexture2DArray curve_tex) {
    float4 tex0 = curve_tex.Load(int4(cLoc, texLayer, 0));
    float4 tex1 = curve_tex.Load(int4(offsetCurveLoc(cLoc, 1), texLayer, 0));
    float4 p12 = float4(tex0.xy, tex0.zw) - float4(rc, rc);
    float2 p3 = tex1.xy - rc;
    if (max(max(p12.x, p12.z), p3.x) * ppe.x < -0.5) return false;
    uint code = calcRootCode(p12.y, p12.w, p3.y);
    if (code != 0u) {
        float2 r = solveHorizPoly(p12, p3) * ppe.x;
        if ((code & 1u) != 0u) { xcov += clamp(r.x + 0.5, 0.0, 1.0); xwgt = max(xwgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0)); }
        if (code > 1u) { xcov -= clamp(r.y + 0.5, 0.0, 1.0); xwgt = max(xwgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0)); }
    }
    return true;
}

public bool accumulateVertContribution(inout float ycov, inout float ywgt, float2 rc, float2 ppe, int2 cLoc, int texLayer, SnailFloatTexture2DArray curve_tex) {
    float4 tex0 = curve_tex.Load(int4(cLoc, texLayer, 0));
    float4 tex1 = curve_tex.Load(int4(offsetCurveLoc(cLoc, 1), texLayer, 0));
    float4 p12 = float4(tex0.xy, tex0.zw) - float4(rc, rc);
    float2 p3 = tex1.xy - rc;
    if (max(max(p12.y, p12.w), p3.y) * ppe.y < -0.5) return false;
    uint code = calcRootCode(p12.x, p12.z, p3.x);
    if (code != 0u) {
        float2 r = solveVertPoly(p12, p3) * ppe.y;
        if ((code & 1u) != 0u) { ycov -= clamp(r.x + 0.5, 0.0, 1.0); ywgt = max(ywgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0)); }
        if (code > 1u) { ycov += clamp(r.y + 0.5, 0.0, 1.0); ywgt = max(ywgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0)); }
    }
    return true;
}

public float evalGlyphCoverage(float2 rc, float2 epp, float2 ppe, int2 gLoc, int2 bandMax, float4 banding, int texLayer, SnailFloatTexture2DArray curve_tex, SnailUint2Texture2DArray band_tex, float coverage_exponent) {
    // Evaluate every band the pixel footprint touches and de-duplicate
    // curves that span multiple bands by counting them only at their
    // owner band. Mirrors the path-shader fix from commit 94d76bd.
    CoverageBandSpan hSpan = computeCoverageBandSpan(rc.y, epp.y, banding.y, banding.w, bandMax.y);
    CoverageBandSpan vSpan = computeCoverageBandSpan(rc.x, epp.x, banding.x, banding.z, bandMax.x);

    float xcov = 0.0, xwgt = 0.0;
    {
        bool dedup = hSpan.first != hSpan.last;
        for (int band = hSpan.first; band <= hSpan.last; band++) {
            int2 hHeaderLoc = calcBandLoc(gLoc, uint(band));
            uint2 hbd = band_tex.Load(int4(hHeaderLoc, texLayer, 0)).xy;
            int2 hLoc = calcBandLoc(gLoc, hbd.y);
            int hCount = int(hbd.x);
            for (int i = 0; i < hCount; i++) {
                int2 bLoc_h = calcBandLoc(hLoc, uint(i));
                uint2 ref = band_tex.Load(int4(bLoc_h, texLayer, 0)).xy;
                if (dedup && !isCoverageBandSpanOwner(ref, band, hSpan.first)) continue;
                int2 cLoc = decodeBandCurveLoc(ref);
                if (!accumulateHorizContribution(xcov, xwgt, rc, ppe, cLoc, texLayer, curve_tex)) break;
            }
        }
    }

    float ycov = 0.0, ywgt = 0.0;
    {
        bool dedup = vSpan.first != vSpan.last;
        for (int band = vSpan.first; band <= vSpan.last; band++) {
            int2 vHeaderLoc = calcBandLoc(gLoc, uint(bandMax.y + 1 + band));
            uint2 vbd = band_tex.Load(int4(vHeaderLoc, texLayer, 0)).xy;
            int2 vLoc = calcBandLoc(gLoc, vbd.y);
            int vCount = int(vbd.x);
            for (int i = 0; i < vCount; i++) {
                int2 bLoc_v = calcBandLoc(vLoc, uint(i));
                uint2 ref = band_tex.Load(int4(bLoc_v, texLayer, 0)).xy;
                if (dedup && !isCoverageBandSpanOwner(ref, band, vSpan.first)) continue;
                int2 cLoc = decodeBandCurveLoc(ref);
                if (!accumulateVertContribution(ycov, ywgt, rc, ppe, cLoc, texLayer, curve_tex)) break;
            }
        }
    }

    float wsum = xwgt + ywgt;
    float blended = xcov * xwgt + ycov * ywgt;
    float cov = max(applyFillRule(blended / max(wsum, 1.0 / 65536.0), 0),
                    min(applyFillRule(xcov, 0), applyFillRule(ycov, 0)));
    return applyCoverageTransfer(cov, coverage_exponent);
}
