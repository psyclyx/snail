#define kLogBandTextureWidth 12
#define kDirectEncodingKindBias 4.0
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

ivec2 offsetLayerLoc(ivec2 base, int offset) {
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

vec2 evalAxisCoverage(vec2 rc, float ppe, ivec2 bandLoc, int count, int layer, bool horizontal) {
    float cov = 0.0;
    float wgt = 0.0;
    for (int i = 0; i < count; i++) {
        ivec2 bLoc = calcBandLoc(bandLoc, uint(i));
        ivec2 cLoc = ivec2(texelFetch(u_band_tex, ivec3(bLoc, layer), 0).xy);
        vec4 tex0 = texelFetch(u_curve_tex, ivec3(cLoc, layer), 0);
        vec4 tex1 = texelFetch(u_curve_tex, ivec3(offsetCurveLoc(cLoc, 1), layer), 0);
        vec4 tex2 = texelFetch(u_curve_tex, ivec3(offsetCurveLoc(cLoc, 2), layer), 0);
        bool direct = tex2.z >= kDirectEncodingKindBias - 0.5;
        vec4 p12;
        vec2 p3;
        if (direct) {
            p12 = vec4(tex0.xy, tex0.zw) - vec4(rc, rc);
            p3 = tex1.xy - rc;
        } else {
            vec2 anchor = tex0.xy * 256.0 + tex0.zw;
            p12 = vec4(anchor, anchor + tex1.xy) - vec4(rc, rc);
            p3 = anchor + tex1.zw - rc;
        }
        float maxCoord = horizontal ? max(max(p12.x, p12.z), p3.x) : max(max(p12.y, p12.w), p3.y);
        if (maxCoord * ppe < -0.5) break;
        uint code = horizontal ? calcRootCode(p12.y, p12.w, p3.y) : calcRootCode(p12.x, p12.z, p3.x);
        if (code == 0u) continue;
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
    return vec2(cov, wgt);
}

float evalGlyphCoverage(vec2 rc, vec2 ppe, ivec2 gLoc, ivec2 bandMax, vec4 banding, int texLayer) {
    ivec2 bandIdx = clamp(ivec2(rc * banding.xy + banding.zw), ivec2(0), bandMax);
    uvec2 hbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandIdx.y, gLoc.y, texLayer), 0).xy;
    ivec2 hLoc = calcBandLoc(gLoc, hbd.y);
    int hCount = int(hbd.x);
    vec2 horiz = evalAxisCoverage(rc, ppe.x, hLoc, hCount, texLayer, true);
    uvec2 vbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandMax.y + 1 + bandIdx.x, gLoc.y, texLayer), 0).xy;
    ivec2 vLoc = calcBandLoc(gLoc, vbd.y);
    int vCount = int(vbd.x);
    vec2 vert = evalAxisCoverage(rc, ppe.y, vLoc, vCount, texLayer, false);
    float wsum = horiz.y + vert.y;
    float blended = horiz.x * horiz.y + vert.x * vert.y;
    float cov = max(applyFillRule(blended / max(wsum, 1.0 / 65536.0)),
                    min(applyFillRule(horiz.x), applyFillRule(vert.x)));
    return clamp(cov, 0.0, 1.0);
}

float srgbDecode(float c) {
    return (c <= 0.04045) ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

vec4 premultiplyColor(vec4 color, float cov) {
    float alpha = color.a * cov;
    return vec4(color.rgb * alpha, alpha);
}

void main() {
    int atlas_layer = (v_glyph.w >> 8) & 0xFF;
    if (atlas_layer != 0xFF) discard;
    vec2 rc = v_texcoord;
    vec2 dx = vec2(dFdx(rc.x), dFdy(rc.x));
    vec2 dy = vec2(dFdx(rc.y), dFdy(rc.y));
    vec2 epp = vec2(length(dx), length(dy));
    vec2 ppe = 1.0 / max(epp, vec2(1.0 / 65536.0));
    ivec2 infoBase = v_glyph.xy;
    int layer_count = v_glyph.z;
    vec4 result = vec4(0.0);
    vec4 linear_v_color = vec4(srgbDecode(v_color.r), srgbDecode(v_color.g), srgbDecode(v_color.b), v_color.a);
    for (int l = 0; l < layer_count; l++) {
        ivec2 loc = offsetLayerLoc(infoBase, l * 3);
        vec4 info = texelFetch(u_layer_tex, loc, 0);
        vec4 band = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, l * 3 + 1), 0);
        vec4 color = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, l * 3 + 2), 0);
        if (color.r < 0.0) color = linear_v_color;
        else color = vec4(srgbDecode(color.r), srgbDecode(color.g), srgbDecode(color.b), color.a);
        ivec2 gLoc = ivec2(info.xy);
        int bandMaxH = floatBitsToInt(info.z) & 0xFFFF;
        int bandMaxV = (floatBitsToInt(info.z) >> 16) & 0xFFFF;
        int texLayer = u_layer_base + int(v_banding.w);
        float cov = evalGlyphCoverage(rc, ppe, gLoc, ivec2(bandMaxH, bandMaxV), band, texLayer);
        vec4 premul = premultiplyColor(color, cov);
        result = premul + result * (1.0 - premul.a);
    }
    if (result.a < 1.0 / 255.0) discard;
    frag_color = result;
}
