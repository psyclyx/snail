#define kLogBandTextureWidth 12

uint calcRootCode(float y1, float y2, float y3) {
    uint i1 = floatBitsToUint(y1) >> 31u;
    uint i2 = floatBitsToUint(y2) >> 30u;
    uint i3 = floatBitsToUint(y3) >> 29u;
    uint shift = (i2 & 2u) | (i1 & ~2u);
    shift = (i3 & 4u) | (shift & ~4u);
    return ((0x2E74u >> shift) & 0x0101u);
}

float applyFillRule(float winding) {
    if (SNAIL_FILL_RULE == 1) {
        return 1.0 - abs(fract(winding * 0.5) * 2.0 - 1.0);
    }
    return abs(winding);
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

vec2 solveHorizPoly(vec4 p12, vec2 p3) {
    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    vec2 b = p12.xy - p12.zw;
    const float kEps = 1.0 / 65536.0;
    float t1, t2;
    if (abs(a.y) < kEps) {
        t1 = (abs(b.y) < kEps) ? 0.0 : p12.y * 0.5 / b.y;
        t2 = t1;
    } else {
        float sq = sqrt(max(b.y * b.y - a.y * p12.y, 0.0));
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
        float sq = sqrt(max(b.x * b.x - a.x * p12.x, 0.0));
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

vec2 evalHorizCoverage(vec2 rc, float x_offset, vec2 ppe, ivec2 band_loc, int count, int layer) {
    float cov = 0.0;
    float wgt = 0.0;
    rc += vec2(x_offset, 0.0);
    for (int i = 0; i < count; i++) {
        ivec2 b_loc = calcBandLoc(band_loc, uint(i));
        ivec2 c_loc = ivec2(texelFetch(u_band_tex, ivec3(b_loc, layer), 0).xy);
        vec4 tex0 = texelFetch(u_curve_tex, ivec3(c_loc, layer), 0);
        vec4 tex1 = texelFetch(u_curve_tex, ivec3(offsetCurveLoc(c_loc, 1), layer), 0);
        vec4 p12 = vec4(tex0.xy, tex0.zw) - vec4(rc, rc);
        vec2 p3 = tex1.xy - rc;
        if (max(max(p12.x, p12.z), p3.x) * ppe.x < -0.5) break;
        uint code = calcRootCode(p12.y, p12.w, p3.y);
        if (code == 0u) continue;
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
    return vec2(cov, wgt);
}

vec2 evalVertCoverage(vec2 rc, float y_offset, vec2 ppe, ivec2 band_loc, int count, int layer) {
    float cov = 0.0;
    float wgt = 0.0;
    rc += vec2(0.0, y_offset);
    for (int i = 0; i < count; i++) {
        ivec2 b_loc = calcBandLoc(band_loc, uint(i));
        ivec2 c_loc = ivec2(texelFetch(u_band_tex, ivec3(b_loc, layer), 0).xy);
        vec4 tex0 = texelFetch(u_curve_tex, ivec3(c_loc, layer), 0);
        vec4 tex1 = texelFetch(u_curve_tex, ivec3(offsetCurveLoc(c_loc, 1), layer), 0);
        vec4 p12 = vec4(tex0.xy, tex0.zw) - vec4(rc, rc);
        vec2 p3 = tex1.xy - rc;
        if (max(max(p12.y, p12.w), p3.y) * ppe.y < -0.5) break;
        uint code = calcRootCode(p12.x, p12.z, p3.x);
        if (code == 0u) continue;
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
    return vec2(cov, wgt);
}

float evalGlyphCoverage(vec2 rc, vec2 ppe, ivec2 glyph_loc, ivec2 band_max, vec4 banding, int layer) {
    ivec2 band_idx = clamp(ivec2(rc * banding.xy + banding.zw), ivec2(0), band_max);

    uvec2 hbd = texelFetch(u_band_tex, ivec3(glyph_loc.x + band_idx.y, glyph_loc.y, layer), 0).xy;
    ivec2 h_loc = calcBandLoc(glyph_loc, hbd.y);
    int h_count = int(hbd.x);
    vec2 horiz = evalHorizCoverage(rc, 0.0, ppe, h_loc, h_count, layer);

    uvec2 vbd = texelFetch(u_band_tex, ivec3(glyph_loc.x + band_max.y + 1 + band_idx.x, glyph_loc.y, layer), 0).xy;
    ivec2 v_loc = calcBandLoc(glyph_loc, vbd.y);
    int v_count = int(vbd.x);
    vec2 vert = evalVertCoverage(rc, 0.0, ppe, v_loc, v_count, layer);

    float wsum = horiz.y + vert.y;
    float blended = horiz.x * horiz.y + vert.x * vert.y;
    return clamp(max(applyFillRule(blended / max(wsum, 1.0 / 65536.0)),
                     min(applyFillRule(horiz.x), applyFillRule(vert.x))), 0.0, 1.0);
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

float srgbDecode(float c) {
    return (c <= 0.04045) ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

vec4 premultiplyColorSubpixel(vec4 color, vec3 cov, float alpha_cov) {
    vec3 alpha = vec3(color.a) * cov;
    return vec4(color.rgb * alpha, color.a * alpha_cov);
}

void emitSubpixelColor(vec4 color, vec3 cov, float alpha_cov) {
    vec4 premul = premultiplyColorSubpixel(color, cov, alpha_cov);
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
    return evalGlyphCoverage(rc, ppe, glyph_loc, band_max, banding, layer);
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
    return filterSubpixelCoverage(
        s_m3,
        s_m2,
        s_m1,
        s_0,
        s_p1,
        s_p2,
        s_p3,
        SNAIL_SUBPIXEL_ORDER == 2 || SNAIL_SUBPIXEL_ORDER == 4
    );
}

void main() {
#ifdef SNAIL_DUAL_SOURCE
    frag_blend = vec4(0.0);
#endif
    int layer_byte = (v_glyph.w >> 8) & 0xFF;
    if (layer_byte == 0xFF) discard;
    int layer = u_layer_base + layer_byte;

    vec2 rc = v_texcoord;
    ivec2 band_max = ivec2(v_glyph.w & 0xFF, v_glyph.z);
    ivec2 glyph_loc = v_glyph.xy;
    vec4 cov_alpha = evalGlyphCoverageSubpixel(rc, glyph_loc, band_max, v_banding, layer);

    vec3 cov = cov_alpha.rgb;
    if (max(max(cov.r, cov.g), cov.b) < 1.0 / 255.0) discard;
    vec4 linear_color = vec4(srgbDecode(v_color.r), srgbDecode(v_color.g), srgbDecode(v_color.b), v_color.a);
    emitSubpixelColor(linear_color, cov, cov_alpha.a);
}
