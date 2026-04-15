#version 450

layout(location = 0) in vec4 v_color;
layout(location = 1) in vec2 v_texcoord;
layout(location = 2) flat in vec4 v_banding;
layout(location = 3) flat in ivec4 v_glyph;

layout(set = 0, binding = 0) uniform sampler2DArray u_curve_tex;
layout(set = 0, binding = 1) uniform usampler2DArray u_band_tex;

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    vec2 viewport;
    int fill_rule;
};

layout(location = 0) out vec4 frag_color;

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
    if (fill_rule == 1) {
        return 1.0 - abs(fract(winding * 0.5) * 2.0 - 1.0);
    }
    return abs(winding);
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

ivec2 calcBandLoc(ivec2 glyphLoc, uint offset) {
    ivec2 loc = ivec2(glyphLoc.x + int(offset), glyphLoc.y);
    loc.y += loc.x >> kLogBandTextureWidth;
    loc.x &= (1 << kLogBandTextureWidth) - 1;
    return loc;
}

// Evaluate horizontal coverage at a given x offset from render coordinate
float evalHorizCoverage(vec2 rc, float xOffset, vec2 ppe,
                        ivec2 gLoc, ivec2 hLoc, int hCount, int layer) {
    float xcov = 0.0;
    vec2 samplePos = rc + vec2(xOffset, 0.0);
    for (int i = 0; i < hCount; i++) {
        ivec2 cLoc = ivec2(texelFetch(u_band_tex, ivec3(hLoc.x + i, hLoc.y, layer), 0).xy);
        vec4 p12 = texelFetch(u_curve_tex, ivec3(cLoc, layer), 0) - vec4(samplePos, samplePos);
        vec2 p3 = texelFetch(u_curve_tex, ivec3(cLoc.x + 1, cLoc.y, layer), 0).xy - samplePos;

        if (max(max(p12.x, p12.z), p3.x) * ppe.x < -0.5) break;

        uint code = calcRootCode(p12.y, p12.w, p3.y);
        if (code != 0u) {
            vec2 r = solveHorizPoly(p12, p3) * ppe.x;
            if ((code & 1u) != 0u) xcov += clamp(r.x + 0.5, 0.0, 1.0);
            if (code > 1u)         xcov -= clamp(r.y + 0.5, 0.0, 1.0);
        }
    }
    return xcov;
}

void main() {
    vec2 rc = v_texcoord;
    vec2 epp = fwidth(rc);
    vec2 ppe = 1.0 / epp;
    float subpixelOffset = epp.x / 3.0;

    int layer = (v_glyph.w >> 8) & 0xFF;
    ivec2 bandMax = ivec2(v_glyph.z, v_glyph.w & 0xFF);
    ivec2 bandIdx = clamp(ivec2(rc * v_banding.xy + v_banding.zw), ivec2(0), bandMax);
    ivec2 gLoc = v_glyph.xy;

    // Fetch horizontal band data (shared across subpixels)
    uvec2 hbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandIdx.y, gLoc.y, layer), 0).xy;
    ivec2 hLoc = calcBandLoc(gLoc, hbd.y);
    int hCount = int(hbd.x);

    // Evaluate horizontal coverage at 3 subpixel positions (R, G, B)
    float xcov_r = evalHorizCoverage(rc, -subpixelOffset, ppe, gLoc, hLoc, hCount, layer);
    float xcov_g = evalHorizCoverage(rc, 0.0,             ppe, gLoc, hLoc, hCount, layer);
    float xcov_b = evalHorizCoverage(rc, +subpixelOffset, ppe, gLoc, hLoc, hCount, layer);

    // Vertical band (shared across all subpixels)
    float ycov = 0.0, ywgt = 0.0;
    uvec2 vbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandMax.y + 1 + bandIdx.x, gLoc.y, layer), 0).xy;
    ivec2 vLoc = calcBandLoc(gLoc, vbd.y);
    int vCount = int(vbd.x);

    for (int i = 0; i < vCount; i++) {
        ivec2 cLoc = ivec2(texelFetch(u_band_tex, ivec3(vLoc.x + i, vLoc.y, layer), 0).xy);
        vec4 p12 = texelFetch(u_curve_tex, ivec3(cLoc, layer), 0) - vec4(rc, rc);
        vec2 p3 = texelFetch(u_curve_tex, ivec3(cLoc.x + 1, cLoc.y, layer), 0).xy - rc;

        if (max(max(p12.y, p12.w), p3.y) * ppe.y < -0.5) break;

        uint code = calcRootCode(p12.x, p12.z, p3.x);
        if (code != 0u) {
            vec2 r = solveVertPoly(p12, p3) * ppe.y;
            if ((code & 1u) != 0u) {
                ycov -= clamp(r.x + 0.5, 0.0, 1.0);
                ywgt = max(ywgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0));
            }
            if (code > 1u) {
                ycov += clamp(r.y + 0.5, 0.0, 1.0);
                ywgt = max(ywgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0));
            }
        }
    }

    // Combine per-subpixel horizontal + shared vertical into RGB coverage
    vec3 cov;
    cov.r = clamp(max(applyFillRule(xcov_r), min(applyFillRule(xcov_r), applyFillRule(ycov))), 0.0, 1.0);
    cov.g = clamp(max(applyFillRule(xcov_g), min(applyFillRule(xcov_g), applyFillRule(ycov))), 0.0, 1.0);
    cov.b = clamp(max(applyFillRule(xcov_b), min(applyFillRule(xcov_b), applyFillRule(ycov))), 0.0, 1.0);
    // sRGB gamma: linear -> sRGB transfer function
    cov = mix(cov * 12.92,
              1.055 * pow(cov, vec3(1.0 / 2.4)) - 0.055,
              step(vec3(0.0031308), cov));

    if (max(max(cov.r, cov.g), cov.b) < 1.0/255.0) discard;
    frag_color = vec4(v_color.rgb * cov, max(max(cov.r, cov.g), cov.b) * v_color.a);
}
