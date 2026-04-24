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
    int subpixel_order;
    int subpixel_render_mode;
    vec4 subpixel_backdrop;
};

layout(location = 0) out vec4 frag_color;
#ifdef SNAIL_DUAL_SOURCE
layout(location = 0, index = 1) out vec4 frag_blend;
#endif

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

ivec2 calcBandLoc(ivec2 glyphLoc, uint offset) {
    ivec2 loc = ivec2(glyphLoc.x + int(offset), glyphLoc.y);
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

vec2 evalHorizCoverage(vec2 rc, float x_offset, vec2 ppe, ivec2 band_loc, int count, int layer) {
    float cov = 0.0;
    float wgt = 0.0;
    rc += vec2(x_offset, 0.0);
    for (int i = 0; i < count; i++) {
        ivec2 b_loc = calcBandLoc(band_loc, uint(i));
        ivec2 c_loc = ivec2(texelFetch(u_band_tex, ivec3(b_loc, layer), 0).xy);
        vec4 tex0 = texelFetch(u_curve_tex, ivec3(c_loc, layer), 0);
        vec4 tex1 = texelFetch(u_curve_tex, ivec3(c_loc + ivec2(1, 0), layer), 0);
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
        vec4 tex1 = texelFetch(u_curve_tex, ivec3(c_loc + ivec2(1, 0), layer), 0);
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

float blendSubpixelSample(vec2 cw_s, vec2 cw_o) {
    float wsum = cw_s.y + cw_o.y;
    float blended = cw_s.x * cw_s.y + cw_o.x * cw_o.y;
    return clamp(max(applyFillRule(blended / max(wsum, 1.0 / 65536.0)),
                     min(applyFillRule(cw_s.x), applyFillRule(cw_o.x))), 0.0, 1.0);
}

vec3 blendSubpixel(vec2 cw_r, vec2 cw_g, vec2 cw_b, vec2 cw_o) {
    return vec3(
        blendSubpixelSample(cw_r, cw_o),
        blendSubpixelSample(cw_g, cw_o),
        blendSubpixelSample(cw_b, cw_o)
    );
}

vec4 blendSubpixelWithAlpha(vec2 cw_r, vec2 cw_g, vec2 cw_b, vec2 cw_o) {
    vec3 cov = blendSubpixel(cw_r, cw_g, cw_b, cw_o);
    return vec4(cov, blendSubpixelSample(cw_g, cw_o));
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

vec4 resolveSubpixelOverOpaqueBackdrop(vec4 color, vec3 cov, vec4 backdrop) {
    vec3 src_alpha = vec3(color.a) * cov;
    vec3 resolved = color.rgb * src_alpha + backdrop.rgb * (vec3(1.0) - src_alpha);
    return vec4(resolved, 1.0);
}

void emitSubpixelColor(vec4 color, vec3 cov, float alpha_cov) {
    vec4 premul = premultiplyColorSubpixel(color, cov, alpha_cov);
    frag_color = premul;
#ifdef SNAIL_DUAL_SOURCE
    frag_blend = vec4(vec3(color.a) * cov, 0.0);
#endif
}

void main() {
#ifdef SNAIL_DUAL_SOURCE
    frag_blend = vec4(0.0);
#endif
    int layer = (v_glyph.w >> 8) & 0xFF;
    if (layer == 0xFF) discard;

    vec2 rc = v_texcoord;
    vec2 epp = fwidth(rc);
    vec2 ppe = 1.0 / epp;
    ivec2 band_max = ivec2(v_glyph.z, v_glyph.w & 0xFF);
    ivec2 band_idx = clamp(ivec2(rc * v_banding.xy + v_banding.zw), ivec2(0), band_max);
    ivec2 glyph_loc = v_glyph.xy;

    uvec2 hbd = texelFetch(u_band_tex, ivec3(glyph_loc.x + band_idx.y, glyph_loc.y, layer), 0).xy;
    ivec2 h_loc = calcBandLoc(glyph_loc, hbd.y);
    int h_count = int(hbd.x);

    uvec2 vbd = texelFetch(u_band_tex, ivec3(glyph_loc.x + band_max.y + 1 + band_idx.x, glyph_loc.y, layer), 0).xy;
    ivec2 v_loc = calcBandLoc(glyph_loc, vbd.y);
    int v_count = int(vbd.x);

    vec4 cov_alpha;
    bool safe_mode = subpixel_render_mode != 0;
    if (subpixel_order <= 2) {
        float sp = epp.x / 3.0;
        vec2 cw_v = evalVertCoverage(rc, 0.0, ppe, v_loc, v_count, layer);
        if (!safe_mode) {
            float s = (subpixel_order == 2) ? -1.0 : 1.0;
            vec2 cw_r = evalHorizCoverage(rc, -sp * s, ppe, h_loc, h_count, layer);
            vec2 cw_g = evalHorizCoverage(rc,  0.0,    ppe, h_loc, h_count, layer);
            vec2 cw_b = evalHorizCoverage(rc, +sp * s, ppe, h_loc, h_count, layer);
            cov_alpha = blendSubpixelWithAlpha(cw_r, cw_g, cw_b, cw_v);
        } else {
            float s_m3 = blendSubpixelSample(evalHorizCoverage(rc, -3.0 * sp, ppe, h_loc, h_count, layer), cw_v);
            float s_m2 = blendSubpixelSample(evalHorizCoverage(rc, -2.0 * sp, ppe, h_loc, h_count, layer), cw_v);
            float s_m1 = blendSubpixelSample(evalHorizCoverage(rc, -1.0 * sp, ppe, h_loc, h_count, layer), cw_v);
            float s_0 = blendSubpixelSample(evalHorizCoverage(rc, 0.0, ppe, h_loc, h_count, layer), cw_v);
            float s_p1 = blendSubpixelSample(evalHorizCoverage(rc, 1.0 * sp, ppe, h_loc, h_count, layer), cw_v);
            float s_p2 = blendSubpixelSample(evalHorizCoverage(rc, 2.0 * sp, ppe, h_loc, h_count, layer), cw_v);
            float s_p3 = blendSubpixelSample(evalHorizCoverage(rc, 3.0 * sp, ppe, h_loc, h_count, layer), cw_v);
            cov_alpha = filterSubpixelCoverage(s_m3, s_m2, s_m1, s_0, s_p1, s_p2, s_p3, subpixel_order == 2);
        }
    } else {
        float sp = epp.y / 3.0;
        vec2 cw_h = evalHorizCoverage(rc, 0.0, ppe, h_loc, h_count, layer);
        if (!safe_mode) {
            float s = (subpixel_order == 4) ? -1.0 : 1.0;
            vec2 cw_r = evalVertCoverage(rc, -sp * s, ppe, v_loc, v_count, layer);
            vec2 cw_g = evalVertCoverage(rc,  0.0,    ppe, v_loc, v_count, layer);
            vec2 cw_b = evalVertCoverage(rc, +sp * s, ppe, v_loc, v_count, layer);
            cov_alpha = blendSubpixelWithAlpha(cw_r, cw_g, cw_b, cw_h);
        } else {
            float s_m3 = blendSubpixelSample(evalVertCoverage(rc, -3.0 * sp, ppe, v_loc, v_count, layer), cw_h);
            float s_m2 = blendSubpixelSample(evalVertCoverage(rc, -2.0 * sp, ppe, v_loc, v_count, layer), cw_h);
            float s_m1 = blendSubpixelSample(evalVertCoverage(rc, -1.0 * sp, ppe, v_loc, v_count, layer), cw_h);
            float s_0 = blendSubpixelSample(evalVertCoverage(rc, 0.0, ppe, v_loc, v_count, layer), cw_h);
            float s_p1 = blendSubpixelSample(evalVertCoverage(rc, 1.0 * sp, ppe, v_loc, v_count, layer), cw_h);
            float s_p2 = blendSubpixelSample(evalVertCoverage(rc, 2.0 * sp, ppe, v_loc, v_count, layer), cw_h);
            float s_p3 = blendSubpixelSample(evalVertCoverage(rc, 3.0 * sp, ppe, v_loc, v_count, layer), cw_h);
            cov_alpha = filterSubpixelCoverage(s_m3, s_m2, s_m1, s_0, s_p1, s_p2, s_p3, subpixel_order == 4);
        }
    }

    vec3 cov = cov_alpha.rgb;
    if (max(max(cov.r, cov.g), cov.b) < 1.0 / 255.0) discard;
    if (subpixel_render_mode == 1 && subpixel_backdrop.a >= 1.0 - 1e-6) {
        frag_color = resolveSubpixelOverOpaqueBackdrop(v_color, cov, subpixel_backdrop);
        return;
    }
    emitSubpixelColor(v_color, cov, cov_alpha.a);
}
