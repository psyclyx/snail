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
    if (abs(a.y) < 1.0 / 65536.0) { t1 = p12.y * rb; t2 = t1; }
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
    if (abs(a.x) < 1.0 / 65536.0) { t1 = p12.x * rb; t2 = t1; }
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

float evalGlyphCoverage(vec2 rc, vec2 ppe, ivec2 gLoc, ivec2 bandMax, vec4 banding, int texLayer) {
    ivec2 bandIdx = clamp(ivec2(rc * banding.xy + banding.zw), ivec2(0), bandMax);

    float xcov = 0.0, xwgt = 0.0;
    uvec2 hbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandIdx.y, gLoc.y, texLayer), 0).xy;
    ivec2 hLoc = calcBandLoc(gLoc, hbd.y);
    int hCount = int(hbd.x);
    for (int i = 0; i < hCount; i++) {
        ivec2 bLoc_h = calcBandLoc(hLoc, uint(i));
        ivec2 cLoc = ivec2(texelFetch(u_band_tex, ivec3(bLoc_h, texLayer), 0).xy);
        vec4 tex0 = texelFetch(u_curve_tex, ivec3(cLoc, texLayer), 0);
        vec4 tex1 = texelFetch(u_curve_tex, ivec3(offsetCurveLoc(cLoc, 1), texLayer), 0);
        vec4 p12 = vec4(tex0.xy, tex0.zw) - vec4(rc, rc);
        vec2 p3 = tex1.xy - rc;
        if (max(max(p12.x, p12.z), p3.x) * ppe.x < -0.5) break;
        uint code = calcRootCode(p12.y, p12.w, p3.y);
        if (code != 0u) {
            vec2 r = solveHorizPoly(p12, p3) * ppe.x;
            if ((code & 1u) != 0u) { xcov += clamp(r.x + 0.5, 0.0, 1.0); xwgt = max(xwgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0)); }
            if (code > 1u) { xcov -= clamp(r.y + 0.5, 0.0, 1.0); xwgt = max(xwgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0)); }
        }
    }

    float ycov = 0.0, ywgt = 0.0;
    uvec2 vbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandMax.y + 1 + bandIdx.x, gLoc.y, texLayer), 0).xy;
    ivec2 vLoc = calcBandLoc(gLoc, vbd.y);
    int vCount = int(vbd.x);
    for (int i = 0; i < vCount; i++) {
        ivec2 bLoc_v = calcBandLoc(vLoc, uint(i));
        ivec2 cLoc = ivec2(texelFetch(u_band_tex, ivec3(bLoc_v, texLayer), 0).xy);
        vec4 tex0 = texelFetch(u_curve_tex, ivec3(cLoc, texLayer), 0);
        vec4 tex1 = texelFetch(u_curve_tex, ivec3(offsetCurveLoc(cLoc, 1), texLayer), 0);
        vec4 p12 = vec4(tex0.xy, tex0.zw) - vec4(rc, rc);
        vec2 p3 = tex1.xy - rc;
        if (max(max(p12.y, p12.w), p3.y) * ppe.y < -0.5) break;
        uint code = calcRootCode(p12.x, p12.z, p3.x);
        if (code != 0u) {
            vec2 r = solveVertPoly(p12, p3) * ppe.y;
            if ((code & 1u) != 0u) { ycov -= clamp(r.x + 0.5, 0.0, 1.0); ywgt = max(ywgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0)); }
            if (code > 1u) { ycov += clamp(r.y + 0.5, 0.0, 1.0); ywgt = max(ywgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0)); }
        }
    }

    float wsum = xwgt + ywgt;
    float blended = xcov * xwgt + ycov * ywgt;
    float cov = max(applyFillRule(blended / max(wsum, 1.0 / 65536.0)),
                    min(applyFillRule(xcov), applyFillRule(ycov)));
    return clamp(cov, 0.0, 1.0);
}

float srgbDecode(float c) {
    return (c <= 0.04045) ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

vec4 premultiplyColor(vec4 color, float cov) {
    float alpha = color.a * cov;
    return vec4(color.rgb * alpha, alpha);
}
