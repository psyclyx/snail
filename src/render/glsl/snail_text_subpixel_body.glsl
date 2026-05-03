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
    float ra = 1.0 / a.y;
    float rb = 0.5 / b.y;
    float d = sqrt(max(b.y * b.y - a.y * p12.y, 0.0));
    float t1 = (b.y - d) * ra;
    float t2 = (b.y + d) * ra;
    if (abs(a.y) < 1.0 / 65536.0) {
        t1 = p12.y * rb;
        t2 = t1;
    }
    return vec2((a.x * t1 - b.x * 2.0) * t1 + p12.x,
                (a.x * t2 - b.x * 2.0) * t2 + p12.x);
}

vec2 solveVertPoly(vec4 p12, vec2 p3) {
    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    vec2 b = p12.xy - p12.zw;
    float ra = 1.0 / a.x;
    float rb = 0.5 / b.x;
    float d = sqrt(max(b.x * b.x - a.x * p12.x, 0.0));
    float t1 = (b.x - d) * ra;
    float t2 = (b.x + d) * ra;
    if (abs(a.x) < 1.0 / 65536.0) {
        t1 = p12.x * rb;
        t2 = t1;
    }
    return vec2((a.y * t1 - b.y * 2.0) * t1 + p12.y,
                (a.y * t2 - b.y * 2.0) * t2 + p12.y);
}

int hintStemCount() {
    bool first = v_hint_src.x < v_hint_src.y;
    bool second = v_hint_src.z < v_hint_src.w;
    return second ? 2 : (first ? 1 : 0);
}

float mapHintSegment(float display_x, float display_a, float display_b, float source_a, float source_b) {
    float span = display_b - display_a;
    if (abs(span) <= 1.0 / 65536.0) return source_a;
    return source_a + (display_x - display_a) * ((source_b - source_a) / span);
}

float hintSegmentScale(float display_a, float display_b, float source_a, float source_b) {
    float span = display_b - display_a;
    if (abs(span) <= 1.0 / 65536.0) return 1.0;
    return (source_b - source_a) / span;
}

float inverseHintWarpX(float display_x) {
    int stem_count = hintStemCount();
    if (stem_count == 0) return display_x;

    if (stem_count == 1) {
        if (display_x <= v_hint_dst.x) return mapHintSegment(display_x, v_hint_bounds.x, v_hint_dst.x, v_hint_bounds.x, v_hint_src.x);
        if (display_x <= v_hint_dst.y) return mapHintSegment(display_x, v_hint_dst.x, v_hint_dst.y, v_hint_src.x, v_hint_src.y);
        return mapHintSegment(display_x, v_hint_dst.y, v_hint_bounds.y, v_hint_src.y, v_hint_bounds.y);
    }

    if (display_x <= v_hint_dst.x) return mapHintSegment(display_x, v_hint_bounds.x, v_hint_dst.x, v_hint_bounds.x, v_hint_src.x);
    if (display_x <= v_hint_dst.y) return mapHintSegment(display_x, v_hint_dst.x, v_hint_dst.y, v_hint_src.x, v_hint_src.y);
    if (display_x <= v_hint_dst.z) return mapHintSegment(display_x, v_hint_dst.y, v_hint_dst.z, v_hint_src.y, v_hint_src.z);
    if (display_x <= v_hint_dst.w) return mapHintSegment(display_x, v_hint_dst.z, v_hint_dst.w, v_hint_src.z, v_hint_src.w);
    return mapHintSegment(display_x, v_hint_dst.w, v_hint_bounds.y, v_hint_src.w, v_hint_bounds.y);
}

float inverseHintWarpScaleX(float display_x) {
    int stem_count = hintStemCount();
    if (stem_count == 0) return 1.0;

    if (stem_count == 1) {
        if (display_x <= v_hint_dst.x) return hintSegmentScale(v_hint_bounds.x, v_hint_dst.x, v_hint_bounds.x, v_hint_src.x);
        if (display_x <= v_hint_dst.y) return hintSegmentScale(v_hint_dst.x, v_hint_dst.y, v_hint_src.x, v_hint_src.y);
        return hintSegmentScale(v_hint_dst.y, v_hint_bounds.y, v_hint_src.y, v_hint_bounds.y);
    }

    if (display_x <= v_hint_dst.x) return hintSegmentScale(v_hint_bounds.x, v_hint_dst.x, v_hint_bounds.x, v_hint_src.x);
    if (display_x <= v_hint_dst.y) return hintSegmentScale(v_hint_dst.x, v_hint_dst.y, v_hint_src.x, v_hint_src.y);
    if (display_x <= v_hint_dst.z) return hintSegmentScale(v_hint_dst.y, v_hint_dst.z, v_hint_src.y, v_hint_src.z);
    if (display_x <= v_hint_dst.w) return hintSegmentScale(v_hint_dst.z, v_hint_dst.w, v_hint_src.z, v_hint_src.w);
    return hintSegmentScale(v_hint_dst.w, v_hint_bounds.y, v_hint_src.w, v_hint_bounds.y);
}

vec2 hintedLocalCoord(vec2 rc) {
    return vec2(inverseHintWarpX(rc.x), rc.y);
}

vec2 hintedPixelsPerEm(vec2 display_epp, float display_x) {
    float scale_x = max(abs(inverseHintWarpScaleX(display_x)), 1.0 / 65536.0);
    return vec2(
        1.0 / max(display_epp.x * scale_x, 1.0 / 65536.0),
        1.0 / max(display_epp.y, 1.0 / 65536.0)
    );
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
    const float w0 = 18.0 / 256.0;
    const float w1 = 67.0 / 256.0;
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

float evalHintedGlyphSample(vec2 display_rc, ivec2 glyph_loc, ivec2 band_max, vec4 banding, int layer) {
    vec2 hinted_rc = hintedLocalCoord(display_rc);
    vec2 ppe = 1.0 / max(fwidth(hinted_rc), vec2(1.0 / 65536.0));
    return evalGlyphCoverage(hinted_rc, ppe, glyph_loc, band_max, banding, layer);
}

vec4 evalGlyphCoverageSubpixel(vec2 rc, ivec2 glyph_loc, ivec2 band_max, vec4 banding, int layer) {
    vec2 sample_step = ((SNAIL_SUBPIXEL_ORDER <= 2) ? dFdx(rc) : dFdy(rc)) * (1.0 / 3.0);
    vec2 rc_m3 = rc - sample_step * 3.0;
    vec2 rc_m2 = rc - sample_step * 2.0;
    vec2 rc_m1 = rc - sample_step * 1.0;
    vec2 rc_p1 = rc + sample_step * 1.0;
    vec2 rc_p2 = rc + sample_step * 2.0;
    vec2 rc_p3 = rc + sample_step * 3.0;

    float s_m3 = evalHintedGlyphSample(rc_m3, glyph_loc, band_max, banding, layer);
    float s_m2 = evalHintedGlyphSample(rc_m2, glyph_loc, band_max, banding, layer);
    float s_m1 = evalHintedGlyphSample(rc_m1, glyph_loc, band_max, banding, layer);
    float s_0 = evalHintedGlyphSample(rc, glyph_loc, band_max, banding, layer);
    float s_p1 = evalHintedGlyphSample(rc_p1, glyph_loc, band_max, banding, layer);
    float s_p2 = evalHintedGlyphSample(rc_p2, glyph_loc, band_max, banding, layer);
    float s_p3 = evalHintedGlyphSample(rc_p3, glyph_loc, band_max, banding, layer);
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
    ivec2 band_max = ivec2(v_glyph.z, v_glyph.w & 0xFF);
    ivec2 glyph_loc = v_glyph.xy;
    vec4 cov_alpha = evalGlyphCoverageSubpixel(rc, glyph_loc, band_max, v_banding, layer);

    vec3 cov = cov_alpha.rgb;
    if (max(max(cov.r, cov.g), cov.b) < 1.0 / 255.0) discard;
    vec4 linear_color = vec4(srgbDecode(v_color.r), srgbDecode(v_color.g), srgbDecode(v_color.b), v_color.a);
    emitSubpixelColor(linear_color, cov, cov_alpha.a);
}
