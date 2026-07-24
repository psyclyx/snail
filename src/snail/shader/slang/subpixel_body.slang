// LCD subpixel text evaluator (dual-source blended). This module is canonical.
//
// The per-channel coverage evaluator is the text-family evaluator run at
// three subpixel phases; it reuses text_coverage's solvers/accumulators
// (identical math to the subpixel body's local copies) and keeps this
// module's own copies of the pieces whose signatures differ (the
// no-transfer evalGlyphCoverage, the 5-tap filter, the blend packing).
module subpixel_body;

import resource_types;

import render_abi;
import color_common;
import coverage_common;
import text_coverage;

public struct SubpixelVaryings {
    public float4 color;
    public float4 tint;
    public float2 texcoord;
    public float4 banding;
    public int4 glyph;
};

public struct SubpixelResult {
    public float4 color;
    public float4 blend;
    public bool discard_fragment;
};

float3 applyCoverageTransfer3(float3 cov, float coverage_exponent) {
    return float3(
        applyCoverageTransfer(cov.r, coverage_exponent),
        applyCoverageTransfer(cov.g, coverage_exponent),
        applyCoverageTransfer(cov.b, coverage_exponent)
    );
}

// Clamped, no-transfer variant of the glyph coverage evaluation (the
// subpixel filter applies the transfer after filtering).
float evalGlyphCoverageRaw(float2 rc, float2 epp, float2 ppe, int2 glyph_loc, int2 band_max, float4 banding, int layer, SnailFloatTexture2DArray curve_tex, SnailUint2Texture2DArray band_tex) {
    CoverageBandSpan hSpan = computeCoverageBandSpan(rc.y, epp.y, banding.y, banding.w, band_max.y);
    CoverageBandSpan vSpan = computeCoverageBandSpan(rc.x, epp.x, banding.x, banding.z, band_max.x);

    float xcov = 0.0, xwgt = 0.0;
    {
        bool dedup = hSpan.first != hSpan.last;
        for (int band = hSpan.first; band <= hSpan.last; band++) {
            int2 h_header_loc = calcBandLoc(glyph_loc, uint(band));
            uint2 hbd = band_tex.Load(int4(h_header_loc, layer, 0)).xy;
            int2 h_loc = calcBandLoc(glyph_loc, hbd.y);
            int h_count = int(hbd.x);
            for (int i = 0; i < h_count; i++) {
                int2 b_loc = calcBandLoc(h_loc, uint(i));
                uint2 ref = band_tex.Load(int4(b_loc, layer, 0)).xy;
                if (dedup && !isCoverageBandSpanOwner(ref, band, hSpan.first)) continue;
                int2 c_loc = decodeBandCurveLoc(ref);
                if (!accumulateHorizContribution(xcov, xwgt, rc, ppe, c_loc, layer, curve_tex)) break;
            }
        }
    }

    float ycov = 0.0, ywgt = 0.0;
    {
        bool dedup = vSpan.first != vSpan.last;
        for (int band = vSpan.first; band <= vSpan.last; band++) {
            int2 v_header_loc = calcBandLoc(glyph_loc, uint(band_max.y + 1 + band));
            uint2 vbd = band_tex.Load(int4(v_header_loc, layer, 0)).xy;
            int2 v_loc = calcBandLoc(glyph_loc, vbd.y);
            int v_count = int(vbd.x);
            for (int i = 0; i < v_count; i++) {
                int2 b_loc = calcBandLoc(v_loc, uint(i));
                uint2 ref = band_tex.Load(int4(b_loc, layer, 0)).xy;
                if (dedup && !isCoverageBandSpanOwner(ref, band, vSpan.first)) continue;
                int2 c_loc = decodeBandCurveLoc(ref);
                if (!accumulateVertContribution(ycov, ywgt, rc, ppe, c_loc, layer, curve_tex)) break;
            }
        }
    }

    float wsum = xwgt + ywgt;
    float blended = xcov * xwgt + ycov * ywgt;
    return clamp(max(applyFillRule(blended / max(wsum, 1.0 / 65536.0), 0),
                     min(applyFillRule(xcov, 0), applyFillRule(ycov, 0))), 0.0, 1.0);
}

float4 filterSubpixelCoverage(float s_m3, float s_m2, float s_m1, float s_0, float s_p1, float s_p2, float s_p3, bool reverse_order) {
    const float w0 = 8.0 / 256.0;
    const float w1 = 77.0 / 256.0;
    const float w2 = 86.0 / 256.0;
    float left = w0 * s_m3 + w1 * s_m2 + w2 * s_m1 + w1 * s_0 + w0 * s_p1;
    float center = w0 * s_m2 + w1 * s_m1 + w2 * s_0 + w1 * s_p1 + w0 * s_p2;
    float right = w0 * s_m1 + w1 * s_0 + w2 * s_p1 + w1 * s_p2 + w0 * s_p3;
    float3 cov = reverse_order ? float3(right, center, left) : float3(left, center, right);
    cov = clamp(cov, 0.0, 1.0);
    return float4(cov, clamp((cov.r + cov.g + cov.b) * (1.0 / 3.0), 0.0, 1.0));
}

float4 premultiplyColorSubpixel(float4 color, float3 cov, float alpha_cov) {
    float3 alpha = float3(color.a) * cov;
    return float4(color.rgb * alpha, color.a * alpha_cov);
}

float2 subpixelCoverageEdgePixels(float2 display_dx, float2 display_dy, int subpixel_order) {
    float2 dx = abs(display_dx);
    float2 dy = abs(display_dy);
    return (subpixel_order <= 2)
        ? dx * (1.0 / 3.0) + dy
        : dx + dy * (1.0 / 3.0);
}

float evalGlyphSample(float2 rc, float2 display_epp, int2 glyph_loc, int2 band_max, float4 banding, int layer, SnailFloatTexture2DArray curve_tex, SnailUint2Texture2DArray band_tex) {
    float2 ppe = float2(1.0 / max(display_epp.x, 1.0 / 65536.0), 1.0 / max(display_epp.y, 1.0 / 65536.0));
    return evalGlyphCoverageRaw(rc, display_epp, ppe, glyph_loc, band_max, banding, layer, curve_tex, band_tex);
}

// Deriv-parameterized evaluator: callers with a remapped sample space
// (autohint's inverse warp) pass display-space derivatives already scaled
// into that space; the plain wrapper below feeds raw ddx/ddy.
public float4 snailEvalGlyphCoverageSubpixelDerivs(float2 rc, float2 display_dx, float2 display_dy, int2 glyph_loc, int2 band_max, float4 banding, int layer, int subpixel_order, float coverage_exponent, SnailFloatTexture2DArray curve_tex, SnailUint2Texture2DArray band_tex) {
    float2 sample_step = ((subpixel_order <= 2) ? display_dx : display_dy) * (1.0 / 3.0);
    float2 display_epp = subpixelCoverageEdgePixels(display_dx, display_dy, subpixel_order);
    // One evaluator call site avoids cloning the complete coverage call graph
    // seven times in GL backend linkers.
    float samples[7];
    for (int tap = 0; tap < 7; ++tap) {
        samples[tap] = evalGlyphSample(
            rc + sample_step * float(tap - 3),
            display_epp, glyph_loc, band_max, banding, layer,
            curve_tex, band_tex
        );
    }
    float4 coverage = filterSubpixelCoverage(
        samples[0],
        samples[1],
        samples[2],
        samples[3],
        samples[4],
        samples[5],
        samples[6],
        subpixel_order == 2 || subpixel_order == 4
    );
    return float4(applyCoverageTransfer3(coverage.rgb, coverage_exponent), applyCoverageTransfer(coverage.a, coverage_exponent));
}

public float4 evalGlyphCoverageSubpixel(float2 rc, int2 glyph_loc, int2 band_max, float4 banding, int layer, int subpixel_order, float coverage_exponent, SnailFloatTexture2DArray curve_tex, SnailUint2Texture2DArray band_tex) {
    return snailEvalGlyphCoverageSubpixelDerivs(rc, ddx(rc), ddy(rc), glyph_loc, band_max, banding, layer, subpixel_order, coverage_exponent, curve_tex, band_tex);
}

// Shared dual-source packaging: `color` is the linear, unpremultiplied,
// tint-multiplied paint. Threshold, sRGB-domain encode, per-channel
// premultiply, and the blend-attenuation output — identical to the tail
// of the regular-text subpixel fragment.
public SubpixelResult snailPackSubpixelResult(float4 color, float4 cov_alpha, int output_srgb) {
    SubpixelResult r;
    r.color = float4(0.0);
    r.blend = float4(0.0);
    r.discard_fragment = false;

    float3 cov = cov_alpha.rgb;
    if (max(max(cov.r, cov.g), cov.b) < 1.0 / 255.0) { r.discard_fragment = true; return r; }
    // For sRGB-output mode, encode the unpremultiplied color first; the
    // per-channel coverage is then applied to the encoded values to keep
    // the destination in sRGB-domain.
    float4 effective = (output_srgb != 0)
        ? float4(srgbEncode(max(color.r, 0.0)),
                 srgbEncode(max(color.g, 0.0)),
                 srgbEncode(max(color.b, 0.0)),
                 color.a)
        : color;
    r.color = premultiplyColorSubpixel(effective, cov, cov_alpha.a);
    r.blend = float4(float3(color.a) * cov, 0.0);
    return r;
}

public SubpixelResult snailSubpixelFragment(
    SubpixelVaryings v,
    SnailFloatTexture2DArray curve_tex,
    SnailUint2Texture2DArray band_tex,
    int layer_base,
    int subpixel_order,
    int output_srgb,
    float coverage_exponent)
{
    SubpixelResult r;
    r.color = float4(0.0);
    r.blend = float4(0.0);
    r.discard_fragment = false;

    if ((uint(v.glyph.w) & 0x8000u) != 0u) { r.discard_fragment = true; return r; }
    int layer_byte = (v.glyph.z >> 8) & 0xFF;
    int layer = layer_base + layer_byte;

    float2 rc = v.texcoord;
    int2 band_max = int2((v.glyph.z >> 4) & 0xF, v.glyph.z & 0xF);
    int2 glyph_loc = v.glyph.xy;
    float4 cov_alpha = evalGlyphCoverageSubpixel(rc, glyph_loc, band_max, v.banding, layer,
                                                subpixel_order, coverage_exponent, curve_tex, band_tex);

    // v.color / v.tint arrive as linear-light f16 vertex attributes.
    return snailPackSubpixelResult(v.color * v.tint, cov_alpha, output_srgb);
}
