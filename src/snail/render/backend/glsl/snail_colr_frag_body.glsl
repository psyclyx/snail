#define kDirectEncodingKindBias 4.0

ivec2 decodeBandCurveLoc(uvec2 ref) {
    return decodeBandCurveLocCommon(ref);
}

ivec2 offsetLayerLoc(ivec2 base, int offset) {
    int width = textureSize(u_layer_tex, 0).x;
    int texel = base.y * width + base.x + offset;
    return ivec2(texel % width, texel / width);
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

bool accumulateColrAxisContribution(inout float cov, inout float wgt, vec2 rc, float ppe, ivec2 cLoc, int layer, bool horizontal) {
    // COLR curves come from font glyph extraction (font.zig), which is
    // always direct-encoded and always quadratic. The original code's
    // tex2 fetch + direct/indirect dispatch is reachable only by
    // workloads that don't exist in production — skip both.
    vec4 tex0 = texelFetch(u_curve_tex, ivec3(cLoc, layer), 0);
    vec4 tex1 = texelFetch(u_curve_tex, ivec3(offsetCurveLoc(cLoc, 1), layer), 0);
    vec4 p12 = vec4(tex0.xy, tex0.zw) - vec4(rc, rc);
    vec2 p3 = tex1.xy - rc;
    float maxCoord = horizontal ? max(max(p12.x, p12.z), p3.x) : max(max(p12.y, p12.w), p3.y);
    if (maxCoord * ppe < -0.5) return false;
    uint code = horizontal ? calcRootCode(p12.y, p12.w, p3.y) : calcRootCode(p12.x, p12.z, p3.x);
    if (code != 0u) {
        vec2 roots = horizontal ? solveHorizPoly(p12, p3) * ppe : solveVertPoly(p12, p3) * ppe;
        if ((code & 1u) != 0u) {
            cov += (horizontal ? 1.0 : -1.0) * clamp(roots.x + 0.5, 0.0, 1.0);
            wgt = max(wgt, clamp(1.0 - abs(roots.x) * 2.0, 0.0, 1.0));
        }
        if (code > 1u) {
            cov += (horizontal ? -1.0 : 1.0) * clamp(roots.y + 0.5, 0.0, 1.0);
            wgt = max(wgt, clamp(1.0 - abs(roots.y) * 2.0, 0.0, 1.0));
        }
    }
    return true;
}

vec2 evalAxisCoverageBandSpan(vec2 rc, float ppe, ivec2 gLoc, int headerBase, CoverageBandSpan span, int layer, bool horizontal) {
    float cov = 0.0;
    float wgt = 0.0;
    bool dedup = span.first != span.last;
    for (int band = span.first; band <= span.last; band++) {
        ivec2 headerLoc = calcBandLoc(gLoc, uint(headerBase + band));
        uvec2 bd = texelFetch(u_band_tex, ivec3(headerLoc, layer), 0).xy;
        ivec2 bandLoc = calcBandLoc(gLoc, bd.y);
        int count = int(bd.x);
        for (int i = 0; i < count; i++) {
            ivec2 bLoc = calcBandLoc(bandLoc, uint(i));
            uvec2 ref = texelFetch(u_band_tex, ivec3(bLoc, layer), 0).xy;
            if (dedup && !isCoverageBandSpanOwner(ref, band, span.first)) continue;
            ivec2 cLoc = decodeBandCurveLoc(ref);
            if (!accumulateColrAxisContribution(cov, wgt, rc, ppe, cLoc, layer, horizontal)) break;
        }
    }
    return vec2(cov, wgt);
}

float evalGlyphCoverage(vec2 rc, vec2 epp, vec2 ppe, ivec2 gLoc, ivec2 bandMax, vec4 banding, int texLayer) {
    CoverageBandSpan hSpan = computeCoverageBandSpan(rc.y, epp.y, banding.y, banding.w, bandMax.y);
    CoverageBandSpan vSpan = computeCoverageBandSpan(rc.x, epp.x, banding.x, banding.z, bandMax.x);
    vec2 horiz = evalAxisCoverageBandSpan(rc, ppe.x, gLoc, 0, hSpan, texLayer, true);
    vec2 vert = evalAxisCoverageBandSpan(rc, ppe.y, gLoc, bandMax.y + 1, vSpan, texLayer, false);
    float wsum = horiz.y + vert.y;
    float blended = horiz.x * horiz.y + vert.x * vert.y;
    float cov = max(applyFillRule(blended / max(wsum, 1.0 / 65536.0)),
                    min(applyFillRule(horiz.x), applyFillRule(vert.x)));
    return applyCoverageTransfer(cov);
}

void main() {
    int atlas_layer = (v_glyph.w >> 8) & 0xFF;
    int special_kind = v_glyph.w & 0xFF;
    if (atlas_layer != SNAIL_SPECIAL_LAYER_SENTINEL || special_kind != SNAIL_SPECIAL_KIND_COLR) discard;
    vec2 rc = v_texcoord;
    vec2 dx = vec2(dFdx(rc.x), dFdy(rc.x));
    vec2 dy = vec2(dFdx(rc.y), dFdy(rc.y));
    vec2 epp = vec2(length(dx), length(dy));
    vec2 ppe = 1.0 / max(epp, vec2(1.0 / 65536.0));
    ivec2 infoBase = v_glyph.xy;
    int layer_count = v_glyph.z;
    vec4 result = vec4(0.0);
    // v_color / v_tint are already sRGB-decoded in the vertex shader.
    for (int l = 0; l < layer_count; l++) {
        ivec2 loc = offsetLayerLoc(infoBase, l * 3);
        vec4 info = texelFetch(u_layer_tex, loc, 0);
        vec4 band = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, l * 3 + 1), 0);
        vec4 color = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, l * 3 + 2), 0);
        if (color.r < 0.0) color = v_color;
        else color = vec4(srgbDecode(color.r), srgbDecode(color.g), srgbDecode(color.b), color.a);
        color *= v_tint;
        ivec2 gLoc = ivec2(info.xy);
        int bandMaxH = floatBitsToInt(info.z) & 0xFFFF;
        int bandMaxV = (floatBitsToInt(info.z) >> 16) & 0xFFFF;
        int texLayer = u_layer_base + int(v_banding.w);
        float cov = evalGlyphCoverage(rc, epp, ppe, gLoc, ivec2(bandMaxV, bandMaxH), band, texLayer);
        vec4 premul = premultiplyColor(color, cov);
        result = premul + result * (1.0 - premul.a);
    }
    if (result.a < 1.0 / 255.0) discard;
    frag_color = (SNAIL_MASK_OUTPUT != 0) ? vec4(result.a) : ((SNAIL_OUTPUT_SRGB != 0) ? srgbEncodePremultiplied(result) : result);
}
