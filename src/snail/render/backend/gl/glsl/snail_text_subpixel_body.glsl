vec3 applyCoverageTransfer(vec3 cov) {
    return vec3(
        applyCoverageTransfer(cov.r),
        applyCoverageTransfer(cov.g),
        applyCoverageTransfer(cov.b)
    );
}

ivec2 decodeBandCurveLoc(uvec2 ref) {
    return decodeBandCurveLocCommon(ref);
}

vec2 solveHorizPoly(vec4 p12, vec2 p3) {
    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    vec2 b = p12.xy - p12.zw;
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
    return vec2((a.x * t1 - b.x * 2.0) * t1 + p12.x,
                (a.x * t2 - b.x * 2.0) * t2 + p12.x);
}

vec2 solveVertPoly(vec4 p12, vec2 p3) {
    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    vec2 b = p12.xy - p12.zw;
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
    return vec2((a.y * t1 - b.y * 2.0) * t1 + p12.y,
                (a.y * t2 - b.y * 2.0) * t2 + p12.y);
}

bool accumulateSubpixelHoriz(inout float cov, inout float wgt, vec2 rc, vec2 ppe, ivec2 c_loc, int layer) {
    vec4 tex0 = texelFetch(u_curve_tex, ivec3(c_loc, layer), 0);
    vec4 tex1 = texelFetch(u_curve_tex, ivec3(offsetCurveLoc(c_loc, 1), layer), 0);
    vec4 p12 = vec4(tex0.xy, tex0.zw) - vec4(rc, rc);
    vec2 p3 = tex1.xy - rc;
    if (max(max(p12.x, p12.z), p3.x) * ppe.x < -0.5) return false;
    uint code = calcRootCode(p12.y, p12.w, p3.y);
    if (code != 0u) {
        vec2 roots = solveHorizPoly(p12, p3) * ppe.x;
        if ((code & 1u) != 0u) {
            cov += clamp(roots.x + 0.5, 0.0, 1.0);
            wgt = max(wgt, clamp(1.0 - abs(roots.x) * 2.0, 0.0, 1.0));
        }
        if (code > 1u) {
            cov -= clamp(roots.y + 0.5, 0.0, 1.0);
            wgt = max(wgt, clamp(1.0 - abs(roots.y) * 2.0, 0.0, 1.0));
        }
    }
    return true;
}

bool accumulateSubpixelVert(inout float cov, inout float wgt, vec2 rc, vec2 ppe, ivec2 c_loc, int layer) {
    vec4 tex0 = texelFetch(u_curve_tex, ivec3(c_loc, layer), 0);
    vec4 tex1 = texelFetch(u_curve_tex, ivec3(offsetCurveLoc(c_loc, 1), layer), 0);
    vec4 p12 = vec4(tex0.xy, tex0.zw) - vec4(rc, rc);
    vec2 p3 = tex1.xy - rc;
    if (max(max(p12.y, p12.w), p3.y) * ppe.y < -0.5) return false;
    uint code = calcRootCode(p12.x, p12.z, p3.x);
    if (code != 0u) {
        vec2 roots = solveVertPoly(p12, p3) * ppe.y;
        if ((code & 1u) != 0u) {
            cov -= clamp(roots.x + 0.5, 0.0, 1.0);
            wgt = max(wgt, clamp(1.0 - abs(roots.x) * 2.0, 0.0, 1.0));
        }
        if (code > 1u) {
            cov += clamp(roots.y + 0.5, 0.0, 1.0);
            wgt = max(wgt, clamp(1.0 - abs(roots.y) * 2.0, 0.0, 1.0));
        }
    }
    return true;
}

float evalGlyphCoverage(vec2 rc, vec2 epp, vec2 ppe, ivec2 glyph_loc, ivec2 band_max, vec4 banding, int layer) {
    CoverageBandSpan hSpan = computeCoverageBandSpan(rc.y, epp.y, banding.y, banding.w, band_max.y);
    CoverageBandSpan vSpan = computeCoverageBandSpan(rc.x, epp.x, banding.x, banding.z, band_max.x);

    float xcov = 0.0, xwgt = 0.0;
    {
        bool dedup = hSpan.first != hSpan.last;
        for (int band = hSpan.first; band <= hSpan.last; band++) {
            ivec2 h_header_loc = calcBandLoc(glyph_loc, uint(band));
            uvec2 hbd = texelFetch(u_band_tex, ivec3(h_header_loc, layer), 0).xy;
            ivec2 h_loc = calcBandLoc(glyph_loc, hbd.y);
            int h_count = int(hbd.x);
            for (int i = 0; i < h_count; i++) {
                ivec2 b_loc = calcBandLoc(h_loc, uint(i));
                uvec2 ref = texelFetch(u_band_tex, ivec3(b_loc, layer), 0).xy;
                if (dedup && !isCoverageBandSpanOwner(ref, band, hSpan.first)) continue;
                ivec2 c_loc = decodeBandCurveLoc(ref);
                if (!accumulateSubpixelHoriz(xcov, xwgt, rc, ppe, c_loc, layer)) break;
            }
        }
    }

    float ycov = 0.0, ywgt = 0.0;
    {
        bool dedup = vSpan.first != vSpan.last;
        for (int band = vSpan.first; band <= vSpan.last; band++) {
            ivec2 v_header_loc = calcBandLoc(glyph_loc, uint(band_max.y + 1 + band));
            uvec2 vbd = texelFetch(u_band_tex, ivec3(v_header_loc, layer), 0).xy;
            ivec2 v_loc = calcBandLoc(glyph_loc, vbd.y);
            int v_count = int(vbd.x);
            for (int i = 0; i < v_count; i++) {
                ivec2 b_loc = calcBandLoc(v_loc, uint(i));
                uvec2 ref = texelFetch(u_band_tex, ivec3(b_loc, layer), 0).xy;
                if (dedup && !isCoverageBandSpanOwner(ref, band, vSpan.first)) continue;
                ivec2 c_loc = decodeBandCurveLoc(ref);
                if (!accumulateSubpixelVert(ycov, ywgt, rc, ppe, c_loc, layer)) break;
            }
        }
    }

    float wsum = xwgt + ywgt;
    float blended = xcov * xwgt + ycov * ywgt;
    return clamp(max(applyFillRule(blended / max(wsum, 1.0 / 65536.0)),
                     min(applyFillRule(xcov), applyFillRule(ycov))), 0.0, 1.0);
}

float blendSubpixelSample(vec2 cw_s, vec2 cw_o) {
    float wsum = cw_s.y + cw_o.y;
    float blended = cw_s.x * cw_s.y + cw_o.x * cw_o.y;
    return clamp(max(applyFillRule(blended / max(wsum, 1.0 / 65536.0)),
                     min(applyFillRule(cw_s.x), applyFillRule(cw_o.x))), 0.0, 1.0);
}

vec4 filterSubpixelCoverage(float s_m3, float s_m2, float s_m1, float s_0, float s_p1, float s_p2, float s_p3, bool reverse_order) {
    const float w0 = 8.0 / 256.0;
    const float w1 = 77.0 / 256.0;
    const float w2 = 86.0 / 256.0;
    float left = w0 * s_m3 + w1 * s_m2 + w2 * s_m1 + w1 * s_0 + w0 * s_p1;
    float center = w0 * s_m2 + w1 * s_m1 + w2 * s_0 + w1 * s_p1 + w0 * s_p2;
    float right = w0 * s_m1 + w1 * s_0 + w2 * s_p1 + w1 * s_p2 + w0 * s_p3;
    vec3 cov = reverse_order ? vec3(right, center, left) : vec3(left, center, right);
    cov = clamp(cov, 0.0, 1.0);
    return vec4(cov, clamp((cov.r + cov.g + cov.b) * (1.0 / 3.0), 0.0, 1.0));
}

vec4 premultiplyColorSubpixel(vec4 color, vec3 cov, float alpha_cov) {
    vec3 alpha = vec3(color.a) * cov;
    return vec4(color.rgb * alpha, color.a * alpha_cov);
}

void emitSubpixelColor(vec4 color, vec3 cov, float alpha_cov) {
    // For sRGB-output mode, encode the unpremultiplied color first; the
    // per-channel coverage is then applied to the encoded values to keep
    // the destination in sRGB-domain. (The premul-from-linear divide
    // approach used by the non-subpixel paths doesn't apply cleanly here
    // because rgb is premultiplied with per-channel alpha.)
    vec4 effective = (SNAIL_OUTPUT_SRGB != 0)
        ? vec4(srgbEncode(max(color.r, 0.0)),
               srgbEncode(max(color.g, 0.0)),
               srgbEncode(max(color.b, 0.0)),
               color.a)
        : color;
    vec4 premul = premultiplyColorSubpixel(effective, cov, alpha_cov);
    frag_color = premul;
#ifdef SNAIL_DUAL_SOURCE
    frag_blend = vec4(vec3(color.a) * cov, 0.0);
#endif
}

vec2 subpixelCoverageEdgePixels(vec2 display_dx, vec2 display_dy) {
    vec2 dx = abs(display_dx);
    vec2 dy = abs(display_dy);
    return (SNAIL_SUBPIXEL_ORDER <= 2)
        ? dx * (1.0 / 3.0) + dy
        : dx + dy * (1.0 / 3.0);
}

float evalGlyphSample(vec2 rc, vec2 display_epp, ivec2 glyph_loc, ivec2 band_max, vec4 banding, int layer) {
    vec2 ppe = vec2(1.0 / max(display_epp.x, 1.0 / 65536.0), 1.0 / max(display_epp.y, 1.0 / 65536.0));
    return evalGlyphCoverage(rc, display_epp, ppe, glyph_loc, band_max, banding, layer);
}

vec4 evalGlyphCoverageSubpixel(vec2 rc, ivec2 glyph_loc, ivec2 band_max, vec4 banding, int layer) {
    vec2 display_dx = dFdx(rc);
    vec2 display_dy = dFdy(rc);
    vec2 sample_step = ((SNAIL_SUBPIXEL_ORDER <= 2) ? display_dx : display_dy) * (1.0 / 3.0);
    vec2 display_epp = subpixelCoverageEdgePixels(display_dx, display_dy);
    vec2 rc_m3 = rc - sample_step * 3.0;
    vec2 rc_m2 = rc - sample_step * 2.0;
    vec2 rc_m1 = rc - sample_step * 1.0;
    vec2 rc_p1 = rc + sample_step * 1.0;
    vec2 rc_p2 = rc + sample_step * 2.0;
    vec2 rc_p3 = rc + sample_step * 3.0;

    float s_m3 = evalGlyphSample(rc_m3, display_epp, glyph_loc, band_max, banding, layer);
    float s_m2 = evalGlyphSample(rc_m2, display_epp, glyph_loc, band_max, banding, layer);
    float s_m1 = evalGlyphSample(rc_m1, display_epp, glyph_loc, band_max, banding, layer);
    float s_0 = evalGlyphSample(rc, display_epp, glyph_loc, band_max, banding, layer);
    float s_p1 = evalGlyphSample(rc_p1, display_epp, glyph_loc, band_max, banding, layer);
    float s_p2 = evalGlyphSample(rc_p2, display_epp, glyph_loc, band_max, banding, layer);
    float s_p3 = evalGlyphSample(rc_p3, display_epp, glyph_loc, band_max, banding, layer);
    vec4 coverage = filterSubpixelCoverage(
        s_m3,
        s_m2,
        s_m1,
        s_0,
        s_p1,
        s_p2,
        s_p3,
        SNAIL_SUBPIXEL_ORDER == 2 || SNAIL_SUBPIXEL_ORDER == 4
    );
    return vec4(applyCoverageTransfer(coverage.rgb), applyCoverageTransfer(coverage.a));
}

void main() {
#ifdef SNAIL_DUAL_SOURCE
    frag_blend = vec4(0.0);
#endif
    int layer_byte = (v_glyph.w >> 8) & 0xFF;
    if (layer_byte == SNAIL_SPECIAL_LAYER_SENTINEL) discard;
    int layer = u_layer_base + layer_byte;

    vec2 rc = v_texcoord;
    ivec2 band_max = ivec2(v_glyph.w & 0xFF, v_glyph.z);
    ivec2 glyph_loc = v_glyph.xy;
    vec4 cov_alpha = evalGlyphCoverageSubpixel(rc, glyph_loc, band_max, v_banding, layer);

    vec3 cov = cov_alpha.rgb;
    if (max(max(cov.r, cov.g), cov.b) < 1.0 / 255.0) discard;
    // v_color / v_tint are already sRGB-decoded in the vertex shader.
    emitSubpixelColor(v_color * v_tint, cov, cov_alpha.a);
}
