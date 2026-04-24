// GLSL 330 port of the Slug algorithm reference shaders.
// Original HLSL by Eric Lengyel (MIT/Apache-2.0), ported for snail.

pub const vertex_shader =
    \\#version 330 core
    \\
    \\layout(location = 0) in vec4 a_pos;    // xy = position, zw = normal
    \\layout(location = 1) in vec4 a_tex;    // xy = em-space coords, zw = packed glyph/band data
    \\layout(location = 2) in vec4 a_jac;    // inverse Jacobian (j00, j01, j10, j11)
    \\layout(location = 3) in vec4 a_bnd;    // band scale x, scale y, offset x, offset y
    \\layout(location = 4) in vec4 a_col;    // vertex color RGBA
    \\
    \\uniform mat4 u_mvp;
    \\uniform vec2 u_viewport;
    \\
    \\out vec4 v_color;
    \\out vec2 v_texcoord;
    \\flat out vec4 v_banding;
    \\flat out ivec4 v_glyph;
    \\
    \\void main() {
    \\    uint gz = floatBitsToUint(a_tex.z);
    \\    uint gw = floatBitsToUint(a_tex.w);
    \\    v_glyph = ivec4(gz & 0xFFFFu, gz >> 16u, gw & 0xFFFFu, gw >> 16u);
    \\    v_banding = a_bnd;
    \\    v_color = a_col;
    \\
    \\    // Slug dynamic dilation: expand quad by ~0.5px along normal.
    \\    // Extract MVP rows (GLSL is column-major, so row i = vec4(col0[i], col1[i], col2[i], col3[i]))
    \\    vec4 m0 = vec4(u_mvp[0].x, u_mvp[1].x, u_mvp[2].x, u_mvp[3].x);
    \\    vec4 m1 = vec4(u_mvp[0].y, u_mvp[1].y, u_mvp[2].y, u_mvp[3].y);
    \\    vec4 m3 = vec4(u_mvp[0].w, u_mvp[1].w, u_mvp[2].w, u_mvp[3].w);
    \\
    \\    vec2 n = normalize(a_pos.zw);
    \\    float s = dot(m3.xy, a_pos.xy) + m3.w;
    \\    float t_val = dot(m3.xy, n);
    \\
    \\    float u_val = (s * dot(m0.xy, n) - t_val * (dot(m0.xy, a_pos.xy) + m0.w)) * u_viewport.x;
    \\    float v_val = (s * dot(m1.xy, n) - t_val * (dot(m1.xy, a_pos.xy) + m1.w)) * u_viewport.y;
    \\
    \\    float s2 = s * s;
    \\    float st = s * t_val;
    \\    float uv = u_val * u_val + v_val * v_val;
    \\    float denom = uv - st * st;
    \\
    \\    vec2 d;
    \\    if (abs(denom) > 1e-10) {
    \\        d = a_pos.zw * (s2 * (st + sqrt(uv)) / denom);
    \\    } else {
    \\        // Fallback: fixed dilation of 1px in screen space
    \\        d = n * 2.0 / u_viewport;
    \\    }
    \\
    \\    vec2 p = a_pos.xy + d;
    \\    v_texcoord = vec2(a_tex.x + dot(d, a_jac.xy), a_tex.y + dot(d, a_jac.zw));
    \\
    \\    gl_Position = u_mvp * vec4(p, 0.0, 1.0);
    \\}
;

pub const fragment_shader_text =
    \\#version 330 core
    \\
    \\in vec4 v_color;
    \\in vec2 v_texcoord;
    \\flat in vec4 v_banding;
    \\flat in ivec4 v_glyph;
    \\
    \\uniform sampler2DArray u_curve_tex;
    \\uniform usampler2DArray u_band_tex;
    \\uniform int u_fill_rule;
    \\
    \\out vec4 frag_color;
    \\
    \\#define kLogBandTextureWidth 12
    \\uint calcRootCode(float y1, float y2, float y3) {
    \\    uint i1 = floatBitsToUint(y1) >> 31u;
    \\    uint i2 = floatBitsToUint(y2) >> 30u;
    \\    uint i3 = floatBitsToUint(y3) >> 29u;
    \\    uint shift = (i2 & 2u) | (i1 & ~2u);
    \\    shift = (i3 & 4u) | (shift & ~4u);
    \\    return ((0x2E74u >> shift) & 0x0101u);
    \\}
    \\
    \\float applyFillRule(float winding) {
    \\    if (u_fill_rule == 1) {
    \\        return 1.0 - abs(fract(winding * 0.5) * 2.0 - 1.0);
    \\    }
    \\    return abs(winding);
    \\}
    \\
    \\ivec2 calcBandLoc(ivec2 glyphLoc, uint offset) {
    \\    ivec2 loc = ivec2(glyphLoc.x + int(offset), glyphLoc.y);
    \\    loc.y += loc.x >> kLogBandTextureWidth;
    \\    loc.x &= (1 << kLogBandTextureWidth) - 1;
    \\    return loc;
    \\}
    \\
    \\vec2 solveHorizPoly(vec4 p12, vec2 p3) {
    \\    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    \\    vec2 b = p12.xy - p12.zw;
    \\    float ra = 1.0 / a.y;
    \\    float rb = 0.5 / b.y;
    \\    float d = sqrt(max(b.y * b.y - a.y * p12.y, 0.0));
    \\    float t1 = (b.y - d) * ra;
    \\    float t2 = (b.y + d) * ra;
    \\    if (abs(a.y) < 1.0 / 65536.0) { t1 = p12.y * rb; t2 = t1; }
    \\    return vec2((a.x * t1 - b.x * 2.0) * t1 + p12.x,
    \\               (a.x * t2 - b.x * 2.0) * t2 + p12.x);
    \\}
    \\
    \\vec2 solveVertPoly(vec4 p12, vec2 p3) {
    \\    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    \\    vec2 b = p12.xy - p12.zw;
    \\    float ra = 1.0 / a.x;
    \\    float rb = 0.5 / b.x;
    \\    float d = sqrt(max(b.x * b.x - a.x * p12.x, 0.0));
    \\    float t1 = (b.x - d) * ra;
    \\    float t2 = (b.x + d) * ra;
    \\    if (abs(a.x) < 1.0 / 65536.0) { t1 = p12.x * rb; t2 = t1; }
    \\    return vec2((a.y * t1 - b.y * 2.0) * t1 + p12.y,
    \\               (a.y * t2 - b.y * 2.0) * t2 + p12.y);
    \\}
    \\
    \\float evalGlyphCoverage(vec2 rc, vec2 ppe, ivec2 gLoc, ivec2 bandMax, vec4 banding, int texLayer) {
    \\    ivec2 bandIdx = clamp(ivec2(rc * banding.xy + banding.zw), ivec2(0), bandMax);
    \\
    \\    float xcov = 0.0, xwgt = 0.0;
    \\    uvec2 hbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandIdx.y, gLoc.y, texLayer), 0).xy;
    \\    ivec2 hLoc = calcBandLoc(gLoc, hbd.y);
    \\    int hCount = int(hbd.x);
    \\    for (int i = 0; i < hCount; i++) {
    \\        ivec2 bLoc_h = calcBandLoc(hLoc, uint(i));
    \\        ivec2 cLoc = ivec2(texelFetch(u_band_tex, ivec3(bLoc_h, texLayer), 0).xy);
    \\        vec4 tex0 = texelFetch(u_curve_tex, ivec3(cLoc, texLayer), 0);
    \\        vec4 tex1 = texelFetch(u_curve_tex, ivec3(cLoc + ivec2(1, 0), texLayer), 0);
    \\        vec4 p12 = vec4(tex0.xy, tex0.zw) - vec4(rc, rc);
    \\        vec2 p3 = tex1.xy - rc;
    \\        if (max(max(p12.x, p12.z), p3.x) * ppe.x < -0.5) break;
    \\        uint code = calcRootCode(p12.y, p12.w, p3.y);
    \\        if (code != 0u) {
    \\            vec2 r = solveHorizPoly(p12, p3) * ppe.x;
    \\            if ((code & 1u) != 0u) { xcov += clamp(r.x + 0.5, 0.0, 1.0); xwgt = max(xwgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0)); }
    \\            if (code > 1u) { xcov -= clamp(r.y + 0.5, 0.0, 1.0); xwgt = max(xwgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0)); }
    \\        }
    \\    }
    \\
    \\    float ycov = 0.0, ywgt = 0.0;
    \\    uvec2 vbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandMax.y + 1 + bandIdx.x, gLoc.y, texLayer), 0).xy;
    \\    ivec2 vLoc = calcBandLoc(gLoc, vbd.y);
    \\    int vCount = int(vbd.x);
    \\    for (int i = 0; i < vCount; i++) {
    \\        ivec2 bLoc_v = calcBandLoc(vLoc, uint(i));
    \\        ivec2 cLoc = ivec2(texelFetch(u_band_tex, ivec3(bLoc_v, texLayer), 0).xy);
    \\        vec4 tex0 = texelFetch(u_curve_tex, ivec3(cLoc, texLayer), 0);
    \\        vec4 tex1 = texelFetch(u_curve_tex, ivec3(cLoc + ivec2(1, 0), texLayer), 0);
    \\        vec4 p12 = vec4(tex0.xy, tex0.zw) - vec4(rc, rc);
    \\        vec2 p3 = tex1.xy - rc;
    \\        if (max(max(p12.y, p12.w), p3.y) * ppe.y < -0.5) break;
    \\        uint code = calcRootCode(p12.x, p12.z, p3.x);
    \\        if (code != 0u) {
    \\            vec2 r = solveVertPoly(p12, p3) * ppe.y;
    \\            if ((code & 1u) != 0u) { ycov -= clamp(r.x + 0.5, 0.0, 1.0); ywgt = max(ywgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0)); }
    \\            if (code > 1u) { ycov += clamp(r.y + 0.5, 0.0, 1.0); ywgt = max(ywgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0)); }
    \\        }
    \\    }
    \\
    \\    float wsum = xwgt + ywgt;
    \\    float blended = xcov * xwgt + ycov * ywgt;
    \\    float cov = max(applyFillRule(blended / max(wsum, 1.0 / 65536.0)),
    \\                    min(applyFillRule(xcov), applyFillRule(ycov)));
    \\    return clamp(cov, 0.0, 1.0);
    \\}
    \\
    \\vec4 premultiplyColor(vec4 color, float cov) {
    \\    float alpha = color.a * cov;
    \\    return vec4(color.rgb * alpha, alpha);
    \\}
    \\
    \\void main() {
    \\    int atlas_layer = (v_glyph.w >> 8) & 0xFF;
    \\    if (atlas_layer == 0xFF) discard;
    \\    vec2 rc = v_texcoord;
    \\    vec2 epp = fwidth(rc);
    \\    vec2 ppe = 1.0 / epp;
    \\    float cov = evalGlyphCoverage(rc, ppe, v_glyph.xy,
    \\                                  ivec2(v_glyph.z, v_glyph.w & 0xFF),
    \\                                  v_banding, atlas_layer);
    \\    if (cov < 1.0 / 255.0) discard;
    \\    frag_color = premultiplyColor(v_color, cov);
    \\}
;

pub const fragment_shader_text_subpixel =
    \\#version 330 core
    \\
    \\in vec4 v_color;
    \\in vec2 v_texcoord;
    \\flat in vec4 v_banding;
    \\flat in ivec4 v_glyph;
    \\
    \\uniform sampler2DArray u_curve_tex;
    \\uniform usampler2DArray u_band_tex;
    \\uniform int u_fill_rule;
    \\uniform int u_subpixel_order; // 1=RGB, 2=BGR, 3=VRGB, 4=VBGR
    \\
    \\out vec4 frag_color;
    \\
    \\#define kLogBandTextureWidth 12
    \\uint calcRootCode(float y1, float y2, float y3) {
    \\    uint i1 = floatBitsToUint(y1) >> 31u;
    \\    uint i2 = floatBitsToUint(y2) >> 30u;
    \\    uint i3 = floatBitsToUint(y3) >> 29u;
    \\    uint shift = (i2 & 2u) | (i1 & ~2u);
    \\    shift = (i3 & 4u) | (shift & ~4u);
    \\    return ((0x2E74u >> shift) & 0x0101u);
    \\}
    \\
    \\float applyFillRule(float winding) {
    \\    if (u_fill_rule == 1) {
    \\        return 1.0 - abs(fract(winding * 0.5) * 2.0 - 1.0);
    \\    }
    \\    return abs(winding);
    \\}
    \\
    \\ivec2 calcBandLoc(ivec2 glyphLoc, uint offset) {
    \\    ivec2 loc = ivec2(glyphLoc.x + int(offset), glyphLoc.y);
    \\    loc.y += loc.x >> kLogBandTextureWidth;
    \\    loc.x &= (1 << kLogBandTextureWidth) - 1;
    \\    return loc;
    \\}
    \\
    \\vec2 solveHorizPoly(vec4 p12, vec2 p3) {
    \\    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    \\    vec2 b = p12.xy - p12.zw;
    \\    float ra = 1.0 / a.y;
    \\    float rb = 0.5 / b.y;
    \\    float d = sqrt(max(b.y * b.y - a.y * p12.y, 0.0));
    \\    float t1 = (b.y - d) * ra;
    \\    float t2 = (b.y + d) * ra;
    \\    if (abs(a.y) < 1.0 / 65536.0) { t1 = p12.y * rb; t2 = t1; }
    \\    return vec2((a.x * t1 - b.x * 2.0) * t1 + p12.x,
    \\               (a.x * t2 - b.x * 2.0) * t2 + p12.x);
    \\}
    \\
    \\vec2 solveVertPoly(vec4 p12, vec2 p3) {
    \\    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    \\    vec2 b = p12.xy - p12.zw;
    \\    float ra = 1.0 / a.x;
    \\    float rb = 0.5 / b.x;
    \\    float d = sqrt(max(b.x * b.x - a.x * p12.x, 0.0));
    \\    float t1 = (b.x - d) * ra;
    \\    float t2 = (b.x + d) * ra;
    \\    if (abs(a.x) < 1.0 / 65536.0) { t1 = p12.x * rb; t2 = t1; }
    \\    return vec2((a.y * t1 - b.y * 2.0) * t1 + p12.y,
    \\               (a.y * t2 - b.y * 2.0) * t2 + p12.y);
    \\}
    \\
    \\vec2 evalHorizCoverage(vec2 rc, float xOffset, vec2 ppe, ivec2 hLoc, int hCount, int layer) {
    \\    float cov = 0.0;
    \\    float wgt = 0.0;
    \\    rc += vec2(xOffset, 0.0);
    \\    for (int i = 0; i < hCount; i++) {
    \\        ivec2 bLoc = calcBandLoc(hLoc, uint(i));
    \\        ivec2 cLoc = ivec2(texelFetch(u_band_tex, ivec3(bLoc, layer), 0).xy);
    \\        vec4 tex0 = texelFetch(u_curve_tex, ivec3(cLoc, layer), 0);
    \\        vec4 tex1 = texelFetch(u_curve_tex, ivec3(cLoc + ivec2(1, 0), layer), 0);
    \\        vec4 p12 = vec4(tex0.xy, tex0.zw) - vec4(rc, rc);
    \\        vec2 p3 = tex1.xy - rc;
    \\        if (max(max(p12.x, p12.z), p3.x) * ppe.x < -0.5) break;
    \\        uint code = calcRootCode(p12.y, p12.w, p3.y);
    \\        if (code == 0u) continue;
    \\        vec2 roots = solveHorizPoly(p12, p3) * ppe.x;
    \\        if ((code & 1u) != 0u) { cov += clamp(roots.x + 0.5, 0.0, 1.0); wgt = max(wgt, clamp(1.0 - abs(roots.x) * 2.0, 0.0, 1.0)); }
    \\        if (code > 1u) { cov -= clamp(roots.y + 0.5, 0.0, 1.0); wgt = max(wgt, clamp(1.0 - abs(roots.y) * 2.0, 0.0, 1.0)); }
    \\    }
    \\    return vec2(cov, wgt);
    \\}
    \\
    \\vec2 evalVertCoverage(vec2 rc, float yOffset, vec2 ppe, ivec2 vLoc, int vCount, int layer) {
    \\    float cov = 0.0;
    \\    float wgt = 0.0;
    \\    rc += vec2(0.0, yOffset);
    \\    for (int i = 0; i < vCount; i++) {
    \\        ivec2 bLoc = calcBandLoc(vLoc, uint(i));
    \\        ivec2 cLoc = ivec2(texelFetch(u_band_tex, ivec3(bLoc, layer), 0).xy);
    \\        vec4 tex0 = texelFetch(u_curve_tex, ivec3(cLoc, layer), 0);
    \\        vec4 tex1 = texelFetch(u_curve_tex, ivec3(cLoc + ivec2(1, 0), layer), 0);
    \\        vec4 p12 = vec4(tex0.xy, tex0.zw) - vec4(rc, rc);
    \\        vec2 p3 = tex1.xy - rc;
    \\        if (max(max(p12.y, p12.w), p3.y) * ppe.y < -0.5) break;
    \\        uint code = calcRootCode(p12.x, p12.z, p3.x);
    \\        if (code == 0u) continue;
    \\        vec2 roots = solveVertPoly(p12, p3) * ppe.y;
    \\        if ((code & 1u) != 0u) { cov -= clamp(roots.x + 0.5, 0.0, 1.0); wgt = max(wgt, clamp(1.0 - abs(roots.x) * 2.0, 0.0, 1.0)); }
    \\        if (code > 1u) { cov += clamp(roots.y + 0.5, 0.0, 1.0); wgt = max(wgt, clamp(1.0 - abs(roots.y) * 2.0, 0.0, 1.0)); }
    \\    }
    \\    return vec2(cov, wgt);
    \\}
    \\
    \\vec3 blendSubpixel(vec2 cw_r, vec2 cw_g, vec2 cw_b, vec2 cw_o) {
    \\    float wsum_r = cw_r.y + cw_o.y; float blend_r = cw_r.x * cw_r.y + cw_o.x * cw_o.y;
    \\    float wsum_g = cw_g.y + cw_o.y; float blend_g = cw_g.x * cw_g.y + cw_o.x * cw_o.y;
    \\    float wsum_b = cw_b.y + cw_o.y; float blend_b = cw_b.x * cw_b.y + cw_o.x * cw_o.y;
    \\    return vec3(
    \\        clamp(max(applyFillRule(blend_r / max(wsum_r, 1.0/65536.0)),
    \\                  min(applyFillRule(cw_r.x), applyFillRule(cw_o.x))), 0.0, 1.0),
    \\        clamp(max(applyFillRule(blend_g / max(wsum_g, 1.0/65536.0)),
    \\                  min(applyFillRule(cw_g.x), applyFillRule(cw_o.x))), 0.0, 1.0),
    \\        clamp(max(applyFillRule(blend_b / max(wsum_b, 1.0/65536.0)),
    \\                  min(applyFillRule(cw_b.x), applyFillRule(cw_o.x))), 0.0, 1.0)
    \\    );
    \\}
    \\
    \\vec4 premultiplyColorSubpixel(vec4 color, vec3 cov) {
    \\    vec3 alpha = vec3(color.a) * cov;
    \\    return vec4(color.rgb * alpha, color.a * max(max(cov.r, cov.g), cov.b));
    \\}
    \\
    \\void main() {
    \\    int layer = (v_glyph.w >> 8) & 0xFF;
    \\    if (layer == 0xFF) discard;
    \\    vec2 rc = v_texcoord;
    \\    vec2 epp = fwidth(rc);
    \\    vec2 ppe = 1.0 / epp;
    \\    ivec2 bandMax = ivec2(v_glyph.z, v_glyph.w & 0xFF);
    \\    ivec2 bandIdx = clamp(ivec2(rc * v_banding.xy + v_banding.zw), ivec2(0), bandMax);
    \\    ivec2 gLoc = v_glyph.xy;
    \\    uvec2 hbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandIdx.y, gLoc.y, layer), 0).xy;
    \\    ivec2 hLoc = calcBandLoc(gLoc, hbd.y);
    \\    int hCount = int(hbd.x);
    \\    uvec2 vbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandMax.y + 1 + bandIdx.x, gLoc.y, layer), 0).xy;
    \\    ivec2 vLoc = calcBandLoc(gLoc, vbd.y);
    \\    int vCount = int(vbd.x);
    \\    vec3 cov;
    \\    if (u_subpixel_order <= 2) {
    \\        float sp = epp.x / 3.0;
    \\        float s = (u_subpixel_order == 2) ? -1.0 : 1.0;
    \\        vec2 cw_r = evalHorizCoverage(rc, -sp * s, ppe, hLoc, hCount, layer);
    \\        vec2 cw_g = evalHorizCoverage(rc,  0.0,    ppe, hLoc, hCount, layer);
    \\        vec2 cw_b = evalHorizCoverage(rc, +sp * s, ppe, hLoc, hCount, layer);
    \\        vec2 cw_v = evalVertCoverage(rc, 0.0, ppe, vLoc, vCount, layer);
    \\        cov = blendSubpixel(cw_r, cw_g, cw_b, cw_v);
    \\    } else {
    \\        float sp = epp.y / 3.0;
    \\        float s = (u_subpixel_order == 4) ? -1.0 : 1.0;
    \\        vec2 cw_h = evalHorizCoverage(rc, 0.0, ppe, hLoc, hCount, layer);
    \\        vec2 cw_r = evalVertCoverage(rc, -sp * s, ppe, vLoc, vCount, layer);
    \\        vec2 cw_g = evalVertCoverage(rc,  0.0,    ppe, vLoc, vCount, layer);
    \\        vec2 cw_b = evalVertCoverage(rc, +sp * s, ppe, vLoc, vCount, layer);
    \\        cov = blendSubpixel(cw_r, cw_g, cw_b, cw_h);
    \\    }
    \\    if (max(max(cov.r, cov.g), cov.b) < 1.0 / 255.0) discard;
    \\    frag_color = premultiplyColorSubpixel(v_color, cov);
    \\}
;

pub const fragment_shader_colr =
    \\#version 330 core
    \\
    \\in vec4 v_color;
    \\in vec2 v_texcoord;
    \\flat in vec4 v_banding;
    \\flat in ivec4 v_glyph;
    \\
    \\uniform sampler2DArray u_curve_tex;
    \\uniform usampler2DArray u_band_tex;
    \\uniform sampler2D u_layer_tex;
    \\uniform int u_fill_rule;
    \\
    \\out vec4 frag_color;
    \\
    \\#define kLogBandTextureWidth 12
    \\#define kDirectEncodingKindBias 4.0
    \\uint calcRootCode(float y1, float y2, float y3) {
    \\    uint i1 = floatBitsToUint(y1) >> 31u;
    \\    uint i2 = floatBitsToUint(y2) >> 30u;
    \\    uint i3 = floatBitsToUint(y3) >> 29u;
    \\    uint shift = (i2 & 2u) | (i1 & ~2u);
    \\    shift = (i3 & 4u) | (shift & ~4u);
    \\    return ((0x2E74u >> shift) & 0x0101u);
    \\}
    \\
    \\float applyFillRule(float winding) {
    \\    if (u_fill_rule == 1) {
    \\        return 1.0 - abs(fract(winding * 0.5) * 2.0 - 1.0);
    \\    }
    \\    return abs(winding);
    \\}
    \\
    \\ivec2 calcBandLoc(ivec2 glyphLoc, uint offset) {
    \\    ivec2 loc = ivec2(glyphLoc.x + int(offset), glyphLoc.y);
    \\    loc.y += loc.x >> kLogBandTextureWidth;
    \\    loc.x &= (1 << kLogBandTextureWidth) - 1;
    \\    return loc;
    \\}
    \\
    \\ivec2 offsetCurveLoc(ivec2 base, int offset) {
    \\    ivec2 loc = ivec2(base.x + offset, base.y);
    \\    loc.y += loc.x >> kLogBandTextureWidth;
    \\    loc.x &= (1 << kLogBandTextureWidth) - 1;
    \\    return loc;
    \\}
    \\
    \\ivec2 offsetLayerLoc(ivec2 base, int offset) {
    \\    ivec2 loc = ivec2(base.x + offset, base.y);
    \\    loc.y += loc.x >> kLogBandTextureWidth;
    \\    loc.x &= (1 << kLogBandTextureWidth) - 1;
    \\    return loc;
    \\}
    \\
    \\vec2 solveHorizPoly(vec4 p12, vec2 p3) {
    \\    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    \\    vec2 b = p12.xy - p12.zw;
    \\    float ra = 1.0 / a.y;
    \\    float rb = 0.5 / b.y;
    \\    float d = sqrt(max(b.y * b.y - a.y * p12.y, 0.0));
    \\    float t1 = (b.y - d) * ra;
    \\    float t2 = (b.y + d) * ra;
    \\    if (abs(a.y) < 1.0 / 65536.0) { t1 = p12.y * rb; t2 = t1; }
    \\    return vec2((a.x * t1 - b.x * 2.0) * t1 + p12.x,
    \\               (a.x * t2 - b.x * 2.0) * t2 + p12.x);
    \\}
    \\
    \\vec2 solveVertPoly(vec4 p12, vec2 p3) {
    \\    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    \\    vec2 b = p12.xy - p12.zw;
    \\    float ra = 1.0 / a.x;
    \\    float rb = 0.5 / b.x;
    \\    float d = sqrt(max(b.x * b.x - a.x * p12.x, 0.0));
    \\    float t1 = (b.x - d) * ra;
    \\    float t2 = (b.x + d) * ra;
    \\    if (abs(a.x) < 1.0 / 65536.0) { t1 = p12.x * rb; t2 = t1; }
    \\    return vec2((a.y * t1 - b.y * 2.0) * t1 + p12.y,
    \\               (a.y * t2 - b.y * 2.0) * t2 + p12.y);
    \\}
    \\
    \\vec2 evalAxisCoverage(vec2 rc, float ppe, ivec2 bandLoc, int count, int layer, bool horizontal) {
    \\    float cov = 0.0;
    \\    float wgt = 0.0;
    \\    for (int i = 0; i < count; i++) {
    \\        ivec2 bLoc = calcBandLoc(bandLoc, uint(i));
    \\        ivec2 cLoc = ivec2(texelFetch(u_band_tex, ivec3(bLoc, layer), 0).xy);
    \\        vec4 tex0 = texelFetch(u_curve_tex, ivec3(cLoc, layer), 0);
    \\        vec4 tex1 = texelFetch(u_curve_tex, ivec3(offsetCurveLoc(cLoc, 1), layer), 0);
    \\        vec4 tex2 = texelFetch(u_curve_tex, ivec3(offsetCurveLoc(cLoc, 2), layer), 0);
    \\        bool direct = tex2.z >= kDirectEncodingKindBias - 0.5;
    \\        vec4 p12;
    \\        vec2 p3;
    \\        if (direct) {
    \\            p12 = vec4(tex0.xy, tex0.zw) - vec4(rc, rc);
    \\            p3 = tex1.xy - rc;
    \\        } else {
    \\            vec2 anchor = tex0.xy * 256.0 + tex0.zw;
    \\            p12 = vec4(anchor, anchor + tex1.xy) - vec4(rc, rc);
    \\            p3 = anchor + tex1.zw - rc;
    \\        }
    \\        float maxCoord = horizontal ? max(max(p12.x, p12.z), p3.x) : max(max(p12.y, p12.w), p3.y);
    \\        if (maxCoord * ppe < -0.5) break;
    \\        uint code = horizontal ? calcRootCode(p12.y, p12.w, p3.y) : calcRootCode(p12.x, p12.z, p3.x);
    \\        if (code == 0u) continue;
    \\        vec2 roots = horizontal ? solveHorizPoly(p12, p3) * ppe : solveVertPoly(p12, p3) * ppe;
    \\        if ((code & 1u) != 0u) {
    \\            cov += (horizontal ? 1.0 : -1.0) * clamp(roots.x + 0.5, 0.0, 1.0);
    \\            wgt = max(wgt, clamp(1.0 - abs(roots.x) * 2.0, 0.0, 1.0));
    \\        }
    \\        if (code > 1u) {
    \\            cov += (horizontal ? -1.0 : 1.0) * clamp(roots.y + 0.5, 0.0, 1.0);
    \\            wgt = max(wgt, clamp(1.0 - abs(roots.y) * 2.0, 0.0, 1.0));
    \\        }
    \\    }
    \\    return vec2(cov, wgt);
    \\}
    \\
    \\float evalGlyphCoverage(vec2 rc, vec2 ppe, ivec2 gLoc, ivec2 bandMax, vec4 banding, int texLayer) {
    \\    ivec2 bandIdx = clamp(ivec2(rc * banding.xy + banding.zw), ivec2(0), bandMax);
    \\    uvec2 hbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandIdx.y, gLoc.y, texLayer), 0).xy;
    \\    ivec2 hLoc = calcBandLoc(gLoc, hbd.y);
    \\    int hCount = int(hbd.x);
    \\    vec2 horiz = evalAxisCoverage(rc, ppe.x, hLoc, hCount, texLayer, true);
    \\    uvec2 vbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandMax.y + 1 + bandIdx.x, gLoc.y, texLayer), 0).xy;
    \\    ivec2 vLoc = calcBandLoc(gLoc, vbd.y);
    \\    int vCount = int(vbd.x);
    \\    vec2 vert = evalAxisCoverage(rc, ppe.y, vLoc, vCount, texLayer, false);
    \\    float wsum = horiz.y + vert.y;
    \\    float blended = horiz.x * horiz.y + vert.x * vert.y;
    \\    float cov = max(applyFillRule(blended / max(wsum, 1.0 / 65536.0)),
    \\                    min(applyFillRule(horiz.x), applyFillRule(vert.x)));
    \\    return clamp(cov, 0.0, 1.0);
    \\}
    \\
    \\vec4 premultiplyColor(vec4 color, float cov) {
    \\    float alpha = color.a * cov;
    \\    return vec4(color.rgb * alpha, alpha);
    \\}
    \\
    \\void main() {
    \\    int atlas_layer = (v_glyph.w >> 8) & 0xFF;
    \\    if (atlas_layer != 0xFF) discard;
    \\    vec2 rc = v_texcoord;
    \\    vec2 epp = fwidth(rc);
    \\    vec2 ppe = 1.0 / epp;
    \\    ivec2 infoBase = v_glyph.xy;
    \\    int layer_count = v_glyph.z;
    \\    vec4 result = vec4(0.0);
    \\    for (int l = 0; l < layer_count; l++) {
    \\        ivec2 loc = offsetLayerLoc(infoBase, l * 3);
    \\        vec4 info = texelFetch(u_layer_tex, loc, 0);
    \\        vec4 band = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, l * 3 + 1), 0);
    \\        vec4 color = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, l * 3 + 2), 0);
    \\        if (color.r < 0.0) color = v_color;
    \\        ivec2 gLoc = ivec2(info.xy);
    \\        int bandMaxH = floatBitsToInt(info.z) & 0xFFFF;
    \\        int bandMaxV = (floatBitsToInt(info.z) >> 16) & 0xFFFF;
    \\        int texLayer = int(v_banding.w);
    \\        float cov = evalGlyphCoverage(rc, ppe, gLoc, ivec2(bandMaxH, bandMaxV), band, texLayer);
    \\        vec4 premul = premultiplyColor(color, cov);
    \\        result = premul + result * (1.0 - premul.a);
    \\    }
    \\    if (result.a < 1.0 / 255.0) discard;
    \\    frag_color = result;
    \\}
;

pub const fragment_shader_path =
    \\#version 330 core
    \\
    \\in vec4 v_color;
    \\in vec2 v_texcoord;
    \\flat in vec4 v_banding;
    \\flat in ivec4 v_glyph;
    \\
    \\uniform sampler2DArray u_curve_tex;
    \\uniform usampler2DArray u_band_tex;
    \\uniform sampler2D u_layer_tex;
    \\uniform sampler2DArray u_image_tex;
    \\uniform int u_fill_rule;
    \\
    \\out vec4 frag_color;
    \\
    \\#define kLogBandTextureWidth 12
    \\#define kDirectEncodingKindBias 4.0
    \\uint calcRootCode(float y1, float y2, float y3) {
    \\    uint i1 = floatBitsToUint(y1) >> 31u;
    \\    uint i2 = floatBitsToUint(y2) >> 30u;
    \\    uint i3 = floatBitsToUint(y3) >> 29u;
    \\    uint shift = (i2 & 2u) | (i1 & ~2u);
    \\    shift = (i3 & 4u) | (shift & ~4u);
    \\    return ((0x2E74u >> shift) & 0x0101u);
    \\}
    \\
    \\float applyFillRule(float winding) {
    \\    if (u_fill_rule == 1) {
    \\        return 1.0 - abs(fract(winding * 0.5) * 2.0 - 1.0);
    \\    }
    \\    return abs(winding);
    \\}
    \\
    \\ivec2 calcBandLoc(ivec2 glyphLoc, uint offset) {
    \\    ivec2 loc = ivec2(glyphLoc.x + int(offset), glyphLoc.y);
    \\    loc.y += loc.x >> kLogBandTextureWidth;
    \\    loc.x &= (1 << kLogBandTextureWidth) - 1;
    \\    return loc;
    \\}
    \\
    \\ivec2 offsetCurveLoc(ivec2 base, int offset) {
    \\    ivec2 loc = ivec2(base.x + offset, base.y);
    \\    loc.y += loc.x >> kLogBandTextureWidth;
    \\    loc.x &= (1 << kLogBandTextureWidth) - 1;
    \\    return loc;
    \\}
    \\
    \\ivec2 offsetLayerLoc(ivec2 base, int offset) {
    \\    ivec2 loc = ivec2(base.x + offset, base.y);
    \\    loc.y += loc.x >> kLogBandTextureWidth;
    \\    loc.x &= (1 << kLogBandTextureWidth) - 1;
    \\    return loc;
    \\}
    \\
    \\vec2 solveHorizPoly(vec4 p12, vec2 p3) {
    \\    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    \\    vec2 b = p12.xy - p12.zw;
    \\    float ra = 1.0 / a.y;
    \\    float rb = 0.5 / b.y;
    \\    float d = sqrt(max(b.y * b.y - a.y * p12.y, 0.0));
    \\    float t1 = (b.y - d) * ra;
    \\    float t2 = (b.y + d) * ra;
    \\    if (abs(a.y) < 1.0 / 65536.0) { t1 = p12.y * rb; t2 = t1; }
    \\    return vec2((a.x * t1 - b.x * 2.0) * t1 + p12.x,
    \\               (a.x * t2 - b.x * 2.0) * t2 + p12.x);
    \\}
    \\
    \\vec2 solveVertPoly(vec4 p12, vec2 p3) {
    \\    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    \\    vec2 b = p12.xy - p12.zw;
    \\    float ra = 1.0 / a.x;
    \\    float rb = 0.5 / b.x;
    \\    float d = sqrt(max(b.x * b.x - a.x * p12.x, 0.0));
    \\    float t1 = (b.x - d) * ra;
    \\    float t2 = (b.x + d) * ra;
    \\    if (abs(a.x) < 1.0 / 65536.0) { t1 = p12.x * rb; t2 = t1; }
    \\    return vec2((a.y * t1 - b.y * 2.0) * t1 + p12.y,
    \\               (a.y * t2 - b.y * 2.0) * t2 + p12.y);
    \\}
    \\
    \\vec2 evalAxisCoverage(vec2 rc, float ppe, ivec2 bandLoc, int count, int layer, bool horizontal) {
    \\    float cov = 0.0;
    \\    float wgt = 0.0;
    \\    for (int i = 0; i < count; i++) {
    \\        ivec2 bLoc = calcBandLoc(bandLoc, uint(i));
    \\        ivec2 cLoc = ivec2(texelFetch(u_band_tex, ivec3(bLoc, layer), 0).xy);
    \\        vec4 tex0 = texelFetch(u_curve_tex, ivec3(cLoc, layer), 0);
    \\        vec4 tex1 = texelFetch(u_curve_tex, ivec3(offsetCurveLoc(cLoc, 1), layer), 0);
    \\        vec4 tex2 = texelFetch(u_curve_tex, ivec3(offsetCurveLoc(cLoc, 2), layer), 0);
    \\        bool direct = tex2.z >= kDirectEncodingKindBias - 0.5;
    \\        vec4 p12;
    \\        vec2 p3;
    \\        if (direct) {
    \\            p12 = vec4(tex0.xy, tex0.zw) - vec4(rc, rc);
    \\            p3 = tex1.xy - rc;
    \\        } else {
    \\            vec2 anchor = tex0.xy * 256.0 + tex0.zw;
    \\            p12 = vec4(anchor, anchor + tex1.xy) - vec4(rc, rc);
    \\            p3 = anchor + tex1.zw - rc;
    \\        }
    \\        float maxCoord = horizontal ? max(max(p12.x, p12.z), p3.x) : max(max(p12.y, p12.w), p3.y);
    \\        if (maxCoord * ppe < -0.5) break;
    \\        uint code = horizontal ? calcRootCode(p12.y, p12.w, p3.y) : calcRootCode(p12.x, p12.z, p3.x);
    \\        if (code == 0u) continue;
    \\        vec2 roots = horizontal ? solveHorizPoly(p12, p3) * ppe : solveVertPoly(p12, p3) * ppe;
    \\        if ((code & 1u) != 0u) {
    \\            cov += (horizontal ? 1.0 : -1.0) * clamp(roots.x + 0.5, 0.0, 1.0);
    \\            wgt = max(wgt, clamp(1.0 - abs(roots.x) * 2.0, 0.0, 1.0));
    \\        }
    \\        if (code > 1u) {
    \\            cov += (horizontal ? -1.0 : 1.0) * clamp(roots.y + 0.5, 0.0, 1.0);
    \\            wgt = max(wgt, clamp(1.0 - abs(roots.y) * 2.0, 0.0, 1.0));
    \\        }
    \\    }
    \\    return vec2(cov, wgt);
    \\}
    \\
    \\float evalGlyphCoverage(vec2 rc, vec2 ppe, ivec2 gLoc, ivec2 bandMax, vec4 banding, int texLayer) {
    \\    ivec2 bandIdx = clamp(ivec2(rc * banding.xy + banding.zw), ivec2(0), bandMax);
    \\    uvec2 hbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandIdx.y, gLoc.y, texLayer), 0).xy;
    \\    ivec2 hLoc = calcBandLoc(gLoc, hbd.y);
    \\    int hCount = int(hbd.x);
    \\    vec2 horiz = evalAxisCoverage(rc, ppe.x, hLoc, hCount, texLayer, true);
    \\    uvec2 vbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandMax.y + 1 + bandIdx.x, gLoc.y, texLayer), 0).xy;
    \\    ivec2 vLoc = calcBandLoc(gLoc, vbd.y);
    \\    int vCount = int(vbd.x);
    \\    vec2 vert = evalAxisCoverage(rc, ppe.y, vLoc, vCount, texLayer, false);
    \\    float wsum = horiz.y + vert.y;
    \\    float blended = horiz.x * horiz.y + vert.x * vert.y;
    \\    float cov = max(applyFillRule(blended / max(wsum, 1.0 / 65536.0)),
    \\                    min(applyFillRule(horiz.x), applyFillRule(vert.x)));
    \\    return clamp(cov, 0.0, 1.0);
    \\}
    \\
    \\float wrapPaintT(float t, float extendMode) {
    \\    int mode = int(extendMode + 0.5);
    \\    if (mode == 1) return fract(t);
    \\    if (mode == 2) {
    \\        float reflected = mod(t, 2.0);
    \\        if (reflected < 0.0) reflected += 2.0;
    \\        return 1.0 - abs(reflected - 1.0);
    \\    }
    \\    return clamp(t, 0.0, 1.0);
    \\}
    \\
    \\vec4 sampleImagePaintTex(vec2 uv, int layer, int filterMode) {
    \\    if (filterMode == 1) {
    \\        ivec3 size = textureSize(u_image_tex, 0);
    \\        ivec2 texel = clamp(ivec2(uv * vec2(size.xy)), ivec2(0), size.xy - ivec2(1));
    \\        return texelFetch(u_image_tex, ivec3(texel, layer), 0);
    \\    }
    \\    return texture(u_image_tex, vec3(uv, float(layer)));
    \\}
    \\
    \\vec4 samplePathPaint(vec2 rc, ivec2 infoBase, vec4 info) {
    \\    int paintKind = int(-info.w + 0.5);
    \\    vec4 data0 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 2), 0);
    \\    if (paintKind == 1) return data0;
    \\    vec4 color0 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 3), 0);
    \\    vec4 color1 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 4), 0);
    \\    if (paintKind == 2) {
    \\        vec2 delta = data0.zw - data0.xy;
    \\        float lenSq = dot(delta, delta);
    \\        float t = 0.0;
    \\        if (lenSq > 1e-10) t = dot(rc - data0.xy, delta) / lenSq;
    \\        vec4 extra = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 5), 0);
    \\        return mix(color0, color1, wrapPaintT(t, extra.x));
    \\    }
    \\    if (paintKind == 3) {
    \\        float radius = max(abs(data0.z), 1.0 / 65536.0);
    \\        float t = length(rc - data0.xy) / radius;
    \\        return mix(color0, color1, wrapPaintT(t, data0.w));
    \\    }
    \\    if (paintKind == 4) {
    \\        vec4 data1 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 3), 0);
    \\        vec4 tint = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 4), 0);
    \\        vec4 extra = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 5), 0);
    \\        vec2 rawUv = vec2(
    \\            dot(vec3(rc, 1.0), vec3(data0.x, data0.y, data0.z)),
    \\            dot(vec3(rc, 1.0), vec3(data1.x, data1.y, data1.z))
    \\        );
    \\        vec2 wrappedUv = vec2(
    \\            wrapPaintT(rawUv.x, extra.z) * extra.x,
    \\            wrapPaintT(rawUv.y, extra.w) * extra.y
    \\        );
    \\        return sampleImagePaintTex(wrappedUv, int(data0.w + 0.5), int(data1.w + 0.5)) * tint;
    \\    }
    \\    return vec4(1.0, 0.0, 1.0, 1.0);
    \\}
    \\
    \\vec4 premultiplyColor(vec4 color, float cov) {
    \\    float alpha = color.a * cov;
    \\    return vec4(color.rgb * alpha, alpha);
    \\}
    \\
    \\vec4 compositePathGroup(vec2 rc, vec2 ppe, ivec2 infoBase, vec4 header, int texLayer) {
    \\    int layer_count = int(header.x + 0.5);
    \\    int composite_mode = int(header.y + 0.5);
    \\    vec4 result = vec4(0.0);
    \\    float fill_cov = 0.0;
    \\    float stroke_cov = 0.0;
    \\    vec4 fill_paint = vec4(0.0);
    \\    vec4 stroke_paint = vec4(0.0);
    \\    for (int l = 0; l < layer_count; l++) {
    \\        ivec2 loc = offsetLayerLoc(infoBase, 1 + l * 6);
    \\        vec4 info = texelFetch(u_layer_tex, loc, 0);
    \\        vec4 band = texelFetch(u_layer_tex, offsetLayerLoc(loc, 1), 0);
    \\        ivec2 gLoc = ivec2(info.xy);
    \\        int bandMaxH = floatBitsToInt(info.z) & 0xFFFF;
    \\        int bandMaxV = (floatBitsToInt(info.z) >> 16) & 0xFFFF;
    \\        float cov = evalGlyphCoverage(rc, ppe, gLoc, ivec2(bandMaxH, bandMaxV), band, texLayer);
    \\        vec4 paint = samplePathPaint(rc, loc, info);
    \\        if (composite_mode == 1 && layer_count >= 2 && l < 2) {
    \\            if (l == 0) { fill_cov = cov; fill_paint = paint; }
    \\            else { stroke_cov = cov; stroke_paint = paint; }
    \\            continue;
    \\        }
    \\        vec4 premul = premultiplyColor(paint, cov);
    \\        result = premul + result * (1.0 - premul.a);
    \\    }
    \\    if (composite_mode == 1 && layer_count >= 2) {
    \\        float border_cov = min(fill_cov, stroke_cov);
    \\        float interior_cov = max(fill_cov - border_cov, 0.0);
    \\        vec4 combined = premultiplyColor(fill_paint, interior_cov) + premultiplyColor(stroke_paint, border_cov);
    \\        result = result + combined * (1.0 - result.a);
    \\    }
    \\    return result;
    \\}
    \\
    \\void main() {
    \\    if (((v_glyph.w >> 8) & 0xFF) != 0xFF) discard;
    \\    ivec2 infoBase = v_glyph.xy;
    \\    vec4 firstInfo = texelFetch(u_layer_tex, infoBase, 0);
    \\    if (firstInfo.w >= 0.0) discard;
    \\    vec2 rc = v_texcoord;
    \\    vec2 ppe = 1.0 / fwidth(rc);
    \\    int texLayer = int(v_banding.w);
    \\    if (int(-firstInfo.w + 0.5) == 5) {
    \\        vec4 result = compositePathGroup(rc, ppe, infoBase, firstInfo, texLayer);
    \\        if (result.a < 1.0 / 255.0) discard;
    \\        frag_color = result;
    \\        return;
    \\    }
    \\    vec4 band = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 1), 0);
    \\    ivec2 gLoc = ivec2(firstInfo.xy);
    \\    int bandMaxH = floatBitsToInt(firstInfo.z) & 0xFFFF;
    \\    int bandMaxV = (floatBitsToInt(firstInfo.z) >> 16) & 0xFFFF;
    \\    float cov = evalGlyphCoverage(rc, ppe, gLoc, ivec2(bandMaxH, bandMaxV), band, texLayer);
    \\    if (cov < 1.0 / 255.0) discard;
    \\    frag_color = premultiplyColor(samplePathPaint(rc, infoBase, firstInfo), cov);
    \\}
;

pub const fragment_shader =
    \\#version 330 core
    \\
    \\in vec4 v_color;
    \\in vec2 v_texcoord;
    \\flat in vec4 v_banding;
    \\flat in ivec4 v_glyph;
    \\
    \\uniform sampler2DArray u_curve_tex;
    \\uniform usampler2DArray u_band_tex;
    \\uniform sampler2D u_layer_tex;
    \\uniform sampler2DArray u_image_tex;
    \\uniform int u_fill_rule; // 0 = non-zero winding (default), 1 = even-odd
    \\
    \\out vec4 frag_color;
    \\
    \\#define kLogBandTextureWidth 12
    \\#define kDirectEncodingKindBias 4.0
    \\uint calcRootCode(float y1, float y2, float y3) {
    \\    uint i1 = floatBitsToUint(y1) >> 31u;
    \\    uint i2 = floatBitsToUint(y2) >> 30u;
    \\    uint i3 = floatBitsToUint(y3) >> 29u;
    \\    uint shift = (i2 & 2u) | (i1 & ~2u);
    \\    shift = (i3 & 4u) | (shift & ~4u);
    \\    return ((0x2E74u >> shift) & 0x0101u);
    \\}
    \\
    \\float applyFillRule(float winding) {
    \\    if (u_fill_rule == 1) {
    \\        return 1.0 - abs(fract(winding * 0.5) * 2.0 - 1.0);
    \\    }
    \\    return abs(winding);
    \\}
    \\
    \\ivec2 calcBandLoc(ivec2 glyphLoc, uint offset) {
    \\    ivec2 loc = ivec2(glyphLoc.x + int(offset), glyphLoc.y);
    \\    loc.y += loc.x >> kLogBandTextureWidth;
    \\    loc.x &= (1 << kLogBandTextureWidth) - 1;
    \\    return loc;
    \\}
    \\
    \\ivec2 offsetCurveLoc(ivec2 base, int offset) {
    \\    ivec2 loc = ivec2(base.x + offset, base.y);
    \\    loc.y += loc.x >> kLogBandTextureWidth;
    \\    loc.x &= (1 << kLogBandTextureWidth) - 1;
    \\    return loc;
    \\}
    \\
    \\ivec2 offsetLayerLoc(ivec2 base, int offset) {
    \\    ivec2 loc = ivec2(base.x + offset, base.y);
    \\    loc.y += loc.x >> kLogBandTextureWidth;
    \\    loc.x &= (1 << kLogBandTextureWidth) - 1;
    \\    return loc;
    \\}
    \\
    \\struct SegmentRoots {
    \\    int count;
    \\    vec3 t;
    \\};
    \\
    \\struct SegmentData {
    \\    int kind;
    \\    vec2 p0;
    \\    vec2 p1;
    \\    vec2 p2;
    \\    vec2 p3;
    \\    vec3 weights;
    \\};
    \\
    \\float cbrtSigned(float v) {
    \\    return (v == 0.0) ? 0.0 : sign(v) * pow(abs(v), 1.0 / 3.0);
    \\}
    \\
    \\void appendRoot(inout SegmentRoots roots, float t) {
    \\    if (roots.count >= 3) return;
    \\    if (t < -1e-5 || t > 1.0 + 1e-5) return;
    \\    float clamped = clamp(t, 0.0, 1.0);
    \\    for (int i = 0; i < roots.count; i++) {
    \\        if (abs(roots.t[i] - clamped) <= 1e-5) return;
    \\    }
    \\    int insertAt = roots.count;
    \\    while (insertAt > 0 && roots.t[insertAt - 1] > clamped) {
    \\        roots.t[insertAt] = roots.t[insertAt - 1];
    \\        insertAt--;
    \\    }
    \\    roots.t[insertAt] = clamped;
    \\    roots.count++;
    \\}
    \\
    \\SegmentRoots solveQuadraticRoots(float a, float b, float cVal) {
    \\    SegmentRoots roots;
    \\    roots.count = 0;
    \\    roots.t = vec3(0.0);
    \\    if (abs(a) < 1.0 / 65536.0) {
    \\        if (abs(b) < 1.0 / 65536.0) return roots;
    \\        appendRoot(roots, -cVal / b);
    \\        return roots;
    \\    }
    \\    float disc = b * b - 4.0 * a * cVal;
    \\    if (disc < 0.0) {
    \\        if (disc > -1e-6) {
    \\            disc = 0.0;
    \\        } else {
    \\            return roots;
    \\        }
    \\    }
    \\    float sqrtDisc = sqrt(disc);
    \\    float inv2a = 0.5 / a;
    \\    appendRoot(roots, (-b - sqrtDisc) * inv2a);
    \\    appendRoot(roots, (-b + sqrtDisc) * inv2a);
    \\    return roots;
    \\}
    \\
    \\SegmentRoots solveCubicRoots(float a, float b, float cVal, float d) {
    \\    if (abs(a) < 1.0 / 65536.0) {
    \\        return solveQuadraticRoots(b, cVal, d);
    \\    }
    \\    SegmentRoots roots;
    \\    roots.count = 0;
    \\    roots.t = vec3(0.0);
    \\    float invA = 1.0 / a;
    \\    float aa = b * invA;
    \\    float bb = cVal * invA;
    \\    float cc = d * invA;
    \\    float p = bb - aa * aa / 3.0;
    \\    float q = (2.0 * aa * aa * aa) / 27.0 - (aa * bb) / 3.0 + cc;
    \\    float halfQ = q * 0.5;
    \\    float thirdP = p / 3.0;
    \\    float disc = halfQ * halfQ + thirdP * thirdP * thirdP;
    \\    float offset = aa / 3.0;
    \\    if (disc > 1e-8) {
    \\        float sqrtDisc = sqrt(disc);
    \\        float u = cbrtSigned(-halfQ + sqrtDisc);
    \\        float v = cbrtSigned(-halfQ - sqrtDisc);
    \\        appendRoot(roots, u + v - offset);
    \\        return roots;
    \\    }
    \\    if (disc >= -1e-8) {
    \\        float u = cbrtSigned(-halfQ);
    \\        appendRoot(roots, 2.0 * u - offset);
    \\        appendRoot(roots, -u - offset);
    \\        return roots;
    \\    }
    \\    float r = sqrt(-thirdP);
    \\    float phi = acos(clamp(-halfQ / (r * r * r), -1.0, 1.0));
    \\    float twoR = 2.0 * r;
    \\    appendRoot(roots, twoR * cos(phi / 3.0) - offset);
    \\    appendRoot(roots, twoR * cos((phi + 2.0 * 3.14159265358979323846) / 3.0) - offset);
    \\    appendRoot(roots, twoR * cos((phi + 4.0 * 3.14159265358979323846) / 3.0) - offset);
    \\    return roots;
    \\}
    \\
    \\vec2 solveQuadraticHorizDistances(float p0x, float p0y, float p1x, float p1y, float p2x, float p2y, float ppeX) {
    \\    float ax = p0x - p1x * 2.0 + p2x;
    \\    float ay = p0y - p1y * 2.0 + p2y;
    \\    float bx = p0x - p1x;
    \\    float by = p0y - p1y;
    \\
    \\    float t1;
    \\    float t2;
    \\    if (abs(ay) < 1.0 / 65536.0) {
    \\        float rb = 0.5 / by;
    \\        t1 = p0y * rb;
    \\        t2 = t1;
    \\    } else {
    \\        float ra = 1.0 / ay;
    \\        float d = sqrt(max(by * by - ay * p0y, 0.0));
    \\        t1 = (by - d) * ra;
    \\        t2 = (by + d) * ra;
    \\    }
    \\
    \\    float x1 = (ax * t1 - bx * 2.0) * t1 + p0x;
    \\    float x2 = (ax * t2 - bx * 2.0) * t2 + p0x;
    \\    return vec2(x1 * ppeX, x2 * ppeX);
    \\}
    \\
    \\vec2 solveQuadraticVertDistances(float p0x, float p0y, float p1x, float p1y, float p2x, float p2y, float ppeY) {
    \\    float ax = p0x - p1x * 2.0 + p2x;
    \\    float ay = p0y - p1y * 2.0 + p2y;
    \\    float bx = p0x - p1x;
    \\    float by = p0y - p1y;
    \\
    \\    float t1;
    \\    float t2;
    \\    if (abs(ax) < 1.0 / 65536.0) {
    \\        float rb = 0.5 / bx;
    \\        t1 = p0x * rb;
    \\        t2 = t1;
    \\    } else {
    \\        float ra = 1.0 / ax;
    \\        float d = sqrt(max(bx * bx - ax * p0x, 0.0));
    \\        t1 = (bx - d) * ra;
    \\        t2 = (bx + d) * ra;
    \\    }
    \\
    \\    float y1 = (ay * t1 - by * 2.0) * t1 + p0y;
    \\    float y2 = (ay * t2 - by * 2.0) * t2 + p0y;
    \\    return vec2(y1 * ppeY, y2 * ppeY);
    \\}
    \\
    \\SegmentData fetchSegment(ivec2 loc, int layer) {
    \\    vec4 tex0 = texelFetch(u_curve_tex, ivec3(loc, layer), 0);
    \\    ivec2 loc1 = offsetCurveLoc(loc, 1);
    \\    vec4 tex1 = texelFetch(u_curve_tex, ivec3(loc1, layer), 0);
    \\    ivec2 loc2 = offsetCurveLoc(loc, 2);
    \\    vec4 tex2 = texelFetch(u_curve_tex, ivec3(loc2, layer), 0);
    \\    ivec2 loc3 = offsetCurveLoc(loc, 3);
    \\    vec4 meta = texelFetch(u_curve_tex, ivec3(loc3, layer), 0);
    \\    SegmentData seg;
    \\    bool direct = tex2.z >= kDirectEncodingKindBias - 0.5;
    \\    if (direct) {
    \\        seg.kind = int(tex2.z - kDirectEncodingKindBias + 0.5);
    \\        seg.p0 = tex0.xy;
    \\        seg.p1 = tex0.zw;
    \\        seg.p2 = tex1.xy;
    \\        seg.p3 = tex1.zw;
    \\    } else {
    \\        vec2 anchor = tex0.xy * 256.0 + tex0.zw;
    \\        seg.kind = int(tex2.z + 0.5);
    \\        seg.p0 = anchor;
    \\        seg.p1 = anchor + tex1.xy;
    \\        seg.p2 = anchor + tex1.zw;
    \\        seg.p3 = anchor + tex2.xy;
    \\    }
    \\    seg.weights = vec3(tex2.w, meta.x, meta.y);
    \\    return seg;
    \\}
    \\
    \\vec2 evalSegmentPoint(SegmentData seg, float t) {
    \\    float mt = 1.0 - t;
    \\    if (seg.kind == 2) {
    \\        return mt * mt * mt * seg.p0 +
    \\            3.0 * mt * mt * t * seg.p1 +
    \\            3.0 * mt * t * t * seg.p2 +
    \\            t * t * t * seg.p3;
    \\    }
    \\    if (seg.kind == 1) {
    \\        float b0 = mt * mt;
    \\        float b1 = 2.0 * mt * t;
    \\        float b2 = t * t;
    \\        float bw0 = b0 * seg.weights.x;
    \\        float bw1 = b1 * seg.weights.y;
    \\        float bw2 = b2 * seg.weights.z;
    \\        float denom = max(bw0 + bw1 + bw2, 1.0 / 65536.0);
    \\        return (seg.p0 * bw0 + seg.p1 * bw1 + seg.p2 * bw2) / denom;
    \\    }
    \\    return mt * mt * seg.p0 + 2.0 * mt * t * seg.p1 + t * t * seg.p2;
    \\}
    \\
    \\vec2 evalSegmentDerivative(SegmentData seg, float t) {
    \\    float mt = 1.0 - t;
    \\    if (seg.kind == 2) {
    \\        return 3.0 * mt * mt * (seg.p1 - seg.p0) +
    \\            6.0 * mt * t * (seg.p2 - seg.p1) +
    \\            3.0 * t * t * (seg.p3 - seg.p2);
    \\    }
    \\    if (seg.kind == 1) {
    \\        float b0 = mt * mt;
    \\        float b1 = 2.0 * mt * t;
    \\        float b2 = t * t;
    \\        float db0 = -2.0 * mt;
    \\        float db1 = 2.0 - 4.0 * t;
    \\        float db2 = 2.0 * t;
    \\        float bw0 = b0 * seg.weights.x;
    \\        float bw1 = b1 * seg.weights.y;
    \\        float bw2 = b2 * seg.weights.z;
    \\        float dbw0 = db0 * seg.weights.x;
    \\        float dbw1 = db1 * seg.weights.y;
    \\        float dbw2 = db2 * seg.weights.z;
    \\        float denom = max(bw0 + bw1 + bw2, 1.0 / 65536.0);
    \\        float denomPrime = dbw0 + dbw1 + dbw2;
    \\        vec2 numer = seg.p0 * bw0 + seg.p1 * bw1 + seg.p2 * bw2;
    \\        vec2 numerPrime = seg.p0 * dbw0 + seg.p1 * dbw1 + seg.p2 * dbw2;
    \\        return (numerPrime * denom - numer * denomPrime) / (denom * denom);
    \\    }
    \\    return 2.0 * mt * (seg.p1 - seg.p0) + 2.0 * t * (seg.p2 - seg.p1);
    \\}
    \\
    \\SegmentRoots solveSegmentHorizontalRoots(SegmentData seg, float py) {
    \\    if (seg.kind == 2) {
    \\        float a = -seg.p0.y + 3.0 * seg.p1.y - 3.0 * seg.p2.y + seg.p3.y;
    \\        float b = 3.0 * seg.p0.y - 6.0 * seg.p1.y + 3.0 * seg.p2.y;
    \\        float cVal = -3.0 * seg.p0.y + 3.0 * seg.p1.y;
    \\        float d = seg.p0.y - py;
    \\        return solveCubicRoots(a, b, cVal, d);
    \\    }
    \\    if (seg.kind == 1) {
    \\        float c0 = seg.weights.x * (seg.p0.y - py);
    \\        float c1 = seg.weights.y * (seg.p1.y - py);
    \\        float c2 = seg.weights.z * (seg.p2.y - py);
    \\        return solveQuadraticRoots(c0 - 2.0 * c1 + c2, 2.0 * (c1 - c0), c0);
    \\    }
    \\    float a = seg.p0.y - 2.0 * seg.p1.y + seg.p2.y;
    \\    float b = 2.0 * (seg.p1.y - seg.p0.y);
    \\    return solveQuadraticRoots(a, b, seg.p0.y - py);
    \\}
    \\
    \\SegmentRoots solveSegmentVerticalRoots(SegmentData seg, float px) {
    \\    if (seg.kind == 2) {
    \\        float a = -seg.p0.x + 3.0 * seg.p1.x - 3.0 * seg.p2.x + seg.p3.x;
    \\        float b = 3.0 * seg.p0.x - 6.0 * seg.p1.x + 3.0 * seg.p2.x;
    \\        float cVal = -3.0 * seg.p0.x + 3.0 * seg.p1.x;
    \\        float d = seg.p0.x - px;
    \\        return solveCubicRoots(a, b, cVal, d);
    \\    }
    \\    if (seg.kind == 1) {
    \\        float c0 = seg.weights.x * (seg.p0.x - px);
    \\        float c1 = seg.weights.y * (seg.p1.x - px);
    \\        float c2 = seg.weights.z * (seg.p2.x - px);
    \\        return solveQuadraticRoots(c0 - 2.0 * c1 + c2, 2.0 * (c1 - c0), c0);
    \\    }
    \\    float a = seg.p0.x - 2.0 * seg.p1.x + seg.p2.x;
    \\    float b = 2.0 * (seg.p1.x - seg.p0.x);
    \\    return solveQuadraticRoots(a, b, seg.p0.x - px);
    \\}
    \\
    \\float segmentMaxX(SegmentData seg) {
    \\    float result = max(max(seg.p0.x, seg.p1.x), seg.p2.x);
    \\    if (seg.kind == 2) result = max(result, seg.p3.x);
    \\    return result;
    \\}
    \\
    \\float segmentMaxY(SegmentData seg) {
    \\    float result = max(max(seg.p0.y, seg.p1.y), seg.p2.y);
    \\    if (seg.kind == 2) result = max(result, seg.p3.y);
    \\    return result;
    \\}
    \\
    \\vec2 evalAxisCoverage(vec2 sampleRc, float ppe, ivec2 bandLoc, int count, int layer, bool horizontal) {
    \\    float cov = 0.0;
    \\    float wgt = 0.0;
    \\    for (int i = 0; i < count; i++) {
    \\        ivec2 bLoc = calcBandLoc(bandLoc, uint(i));
    \\        ivec2 cLoc = ivec2(texelFetch(u_band_tex, ivec3(bLoc, layer), 0).xy);
    \\        SegmentData seg = fetchSegment(cLoc, layer);
    \\        float maxCoord = (horizontal ? segmentMaxX(seg) - sampleRc.x : segmentMaxY(seg) - sampleRc.y);
    \\        if (maxCoord * ppe < -0.5) break;
    \\        if (seg.kind == 0) {
    \\            float p0x = seg.p0.x - sampleRc.x;
    \\            float p0y = seg.p0.y - sampleRc.y;
    \\            float p1x = seg.p1.x - sampleRc.x;
    \\            float p1y = seg.p1.y - sampleRc.y;
    \\            float p2x = seg.p2.x - sampleRc.x;
    \\            float p2y = seg.p2.y - sampleRc.y;
    \\            uint code = horizontal ? calcRootCode(p0y, p1y, p2y) : calcRootCode(p0x, p1x, p2x);
    \\            if (code == 0u) continue;
    \\
    \\            vec2 roots = horizontal
    \\                ? solveQuadraticHorizDistances(p0x, p0y, p1x, p1y, p2x, p2y, ppe)
    \\                : solveQuadraticVertDistances(p0x, p0y, p1x, p1y, p2x, p2y, ppe);
    \\
    \\            if ((code & 1u) != 0u) {
    \\                cov += (horizontal ? 1.0 : -1.0) * clamp(roots.x + 0.5, 0.0, 1.0);
    \\                wgt = max(wgt, clamp(1.0 - abs(roots.x) * 2.0, 0.0, 1.0));
    \\            }
    \\            if (code > 1u) {
    \\                cov += (horizontal ? -1.0 : 1.0) * clamp(roots.y + 0.5, 0.0, 1.0);
    \\                wgt = max(wgt, clamp(1.0 - abs(roots.y) * 2.0, 0.0, 1.0));
    \\            }
    \\            continue;
    \\        }
    \\        SegmentRoots roots = horizontal ? solveSegmentHorizontalRoots(seg, sampleRc.y) : solveSegmentVerticalRoots(seg, sampleRc.x);
    \\        for (int ri = 0; ri < roots.count; ri++) {
    \\            float t = roots.t[ri];
    \\            // Treat segment intersections as half-open [0, 1) so shared joins
    \\            // between adjacent segments are counted once instead of twice.
    \\            if (t >= 1.0 - 1e-5) continue;
    \\            vec2 point = evalSegmentPoint(seg, t);
    \\            vec2 deriv = evalSegmentDerivative(seg, t);
    \\            float derivAxis = horizontal ? deriv.y : -deriv.x;
    \\            if (abs(derivAxis) <= 1e-5) continue;
    \\            float dist = (horizontal ? point.x - sampleRc.x : point.y - sampleRc.y) * ppe;
    \\            cov += (derivAxis > 0.0 ? 1.0 : -1.0) * clamp(dist + 0.5, 0.0, 1.0);
    \\            wgt = max(wgt, clamp(1.0 - abs(dist) * 2.0, 0.0, 1.0));
    \\        }
    \\    }
    \\    return vec2(cov, wgt);
    \\}
    \\
    \\// Evaluate Slug coverage for a single glyph layer.
    \\float evalGlyphCoverage(vec2 rc, vec2 epp, vec2 ppe,
    \\                        ivec2 gLoc, ivec2 bandMax, vec4 banding, int texLayer) {
    \\    ivec2 bandIdx = clamp(ivec2(rc * banding.xy + banding.zw), ivec2(0), bandMax);
    \\    uvec2 hbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandIdx.y, gLoc.y, texLayer), 0).xy;
    \\    ivec2 hLoc = calcBandLoc(gLoc, hbd.y);
    \\    int hCount = int(hbd.x);
    \\    vec2 horiz = evalAxisCoverage(rc, ppe.x, hLoc, hCount, texLayer, true);
    \\    uvec2 vbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandMax.y + 1 + bandIdx.x, gLoc.y, texLayer), 0).xy;
    \\    ivec2 vLoc = calcBandLoc(gLoc, vbd.y);
    \\    int vCount = int(vbd.x);
    \\    vec2 vert = evalAxisCoverage(rc, ppe.y, vLoc, vCount, texLayer, false);
    \\    float wsum = horiz.y + vert.y;
    \\    float blended = horiz.x * horiz.y + vert.x * vert.y;
    \\    float cov = max(applyFillRule(blended / max(wsum, 1.0 / 65536.0)),
    \\                    min(applyFillRule(horiz.x), applyFillRule(vert.x)));
    \\    return clamp(cov, 0.0, 1.0);
    \\}
    \\
    \\
    \\float wrapPaintT(float t, float extendMode) {
    \\    int mode = int(extendMode + 0.5);
    \\    if (mode == 1) {
    \\        return fract(t);
    \\    }
    \\    if (mode == 2) {
    \\        float reflected = mod(t, 2.0);
    \\        if (reflected < 0.0) reflected += 2.0;
    \\        return 1.0 - abs(reflected - 1.0);
    \\    }
    \\    return clamp(t, 0.0, 1.0);
    \\}
    \\
    \\vec4 sampleImagePaintTex(vec2 uv, int layer, int filterMode) {
    \\    if (filterMode == 1) {
    \\        ivec3 size = textureSize(u_image_tex, 0);
    \\        ivec2 texel = clamp(ivec2(uv * vec2(size.xy)), ivec2(0), size.xy - ivec2(1));
    \\        return texelFetch(u_image_tex, ivec3(texel, layer), 0);
    \\    }
    \\    return texture(u_image_tex, vec3(uv, float(layer)));
    \\}
    \\
    \\vec4 samplePathPaint(vec2 rc, ivec2 infoBase, vec4 info) {
    \\    int paintKind = int(-info.w + 0.5);
    \\    vec4 data0 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 2), 0);
    \\    if (paintKind == 1) {
    \\        return data0;
    \\    }
    \\
    \\    vec4 color0 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 3), 0);
    \\    vec4 color1 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 4), 0);
    \\
    \\    if (paintKind == 2) {
    \\        vec2 delta = data0.zw - data0.xy;
    \\        float lenSq = dot(delta, delta);
    \\        float t = 0.0;
    \\        if (lenSq > 1e-10) {
    \\            t = dot(rc - data0.xy, delta) / lenSq;
    \\        }
    \\        vec4 extra = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 5), 0);
    \\        return mix(color0, color1, wrapPaintT(t, extra.x));
    \\    }
    \\
    \\    if (paintKind == 3) {
    \\        float radius = max(abs(data0.z), 1.0 / 65536.0);
    \\        float t = length(rc - data0.xy) / radius;
    \\        return mix(color0, color1, wrapPaintT(t, data0.w));
    \\    }
    \\
    \\    if (paintKind == 4) {
    \\        vec4 data1 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 3), 0);
    \\        vec4 tint = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 4), 0);
    \\        vec4 extra = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 5), 0);
    \\        vec2 rawUv = vec2(
    \\            dot(vec3(rc, 1.0), vec3(data0.x, data0.y, data0.z)),
    \\            dot(vec3(rc, 1.0), vec3(data1.x, data1.y, data1.z))
    \\        );
    \\        vec2 wrappedUv = vec2(
    \\            wrapPaintT(rawUv.x, extra.z) * extra.x,
    \\            wrapPaintT(rawUv.y, extra.w) * extra.y
    \\        );
    \\        return sampleImagePaintTex(wrappedUv, int(data0.w + 0.5), int(data1.w + 0.5)) * tint;
    \\    }
    \\
    \\    return vec4(1.0, 0.0, 1.0, 1.0);
    \\}
    \\
    \\vec4 premultiplyColor(vec4 color, float cov) {
    \\    float alpha = color.a * cov;
    \\    return vec4(color.rgb * alpha, alpha);
    \\}
    \\
    \\vec4 compositePathGroup(vec2 rc, vec2 epp, vec2 ppe, ivec2 infoBase, vec4 header, int texLayer) {
    \\    int layer_count = int(header.x + 0.5);
    \\    int composite_mode = int(header.y + 0.5);
    \\    vec4 result = vec4(0.0);
    \\    float fill_cov = 0.0;
    \\    float stroke_cov = 0.0;
    \\    vec4 fill_paint = vec4(0.0);
    \\    vec4 stroke_paint = vec4(0.0);
    \\
    \\    for (int l = 0; l < layer_count; l++) {
    \\        ivec2 loc = offsetLayerLoc(infoBase, 1 + l * 6);
    \\        vec4 info = texelFetch(u_layer_tex, loc, 0);
    \\        vec4 band = texelFetch(u_layer_tex, offsetLayerLoc(loc, 1), 0);
    \\        ivec2 gLoc = ivec2(info.xy);
    \\        int bandMaxH = floatBitsToInt(info.z) & 0xFFFF;
    \\        int bandMaxV = (floatBitsToInt(info.z) >> 16) & 0xFFFF;
    \\        float cov = evalGlyphCoverage(rc, epp, ppe, gLoc, ivec2(bandMaxH, bandMaxV), band, texLayer);
    \\        vec4 paint = samplePathPaint(rc, loc, info);
    \\
    \\        if (composite_mode == 1 && layer_count >= 2 && l < 2) {
    \\            if (l == 0) {
    \\                fill_cov = cov;
    \\                fill_paint = paint;
    \\            } else {
    \\                stroke_cov = cov;
    \\                stroke_paint = paint;
    \\            }
    \\            continue;
    \\        }
    \\
    \\        vec4 premul = premultiplyColor(paint, cov);
    \\        result = premul + result * (1.0 - premul.a);
    \\    }
    \\
    \\    if (composite_mode == 1 && layer_count >= 2) {
    \\        float border_cov = min(fill_cov, stroke_cov);
    \\        float interior_cov = max(fill_cov - border_cov, 0.0);
    \\        vec4 combined = premultiplyColor(fill_paint, interior_cov) + premultiplyColor(stroke_paint, border_cov);
    \\        result = result + combined * (1.0 - result.a);
    \\    }
    \\
    \\    return result;
    \\}
    \\
    \\void main() {
    \\    if (((v_glyph.w >> 8) & 0xFF) != 0xFF) discard;
    \\    ivec2 infoBase = v_glyph.xy;
    \\    vec4 firstInfo = texelFetch(u_layer_tex, infoBase, 0);
    \\    if (firstInfo.w >= 0.0) discard;
    \\
    \\    vec2 rc = v_texcoord;
    \\    vec2 epp = fwidth(rc);
    \\    vec2 ppe = 1.0 / epp;
    \\    int texLayer = int(v_banding.w);
    \\
    \\    if (int(-firstInfo.w + 0.5) == 5) {
    \\        vec4 result = compositePathGroup(rc, epp, ppe, infoBase, firstInfo, texLayer);
    \\        if (result.a < 1.0 / 255.0) discard;
    \\        frag_color = result;
    \\        return;
    \\    }
    \\
    \\    vec4 band = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 1), 0);
    \\    ivec2 gLoc = ivec2(firstInfo.xy);
    \\    int bandMaxH = floatBitsToInt(firstInfo.z) & 0xFFFF;
    \\    int bandMaxV = (floatBitsToInt(firstInfo.z) >> 16) & 0xFFFF;
    \\    float cov = evalGlyphCoverage(rc, epp, ppe, gLoc, ivec2(bandMaxH, bandMaxV), band, texLayer);
    \\    if (cov < 1.0 / 255.0) discard;
    \\    frag_color = premultiplyColor(samplePathPaint(rc, infoBase, firstInfo), cov);
    \\}
;

pub const fragment_shader_subpixel =
    \\#version 330 core
    \\
    \\in vec4 v_color;
    \\in vec2 v_texcoord;
    \\flat in vec4 v_banding;
    \\flat in ivec4 v_glyph;
    \\
    \\uniform sampler2DArray u_curve_tex;
    \\uniform usampler2DArray u_band_tex;
    \\uniform sampler2D u_layer_tex;
    \\uniform sampler2DArray u_image_tex;
    \\uniform int u_fill_rule;      // 0 = non-zero winding (default), 1 = even-odd
    \\uniform int u_subpixel_order; // 1=RGB, 2=BGR, 3=VRGB, 4=VBGR
    \\
    \\out vec4 frag_color;
    \\
    \\#define kLogBandTextureWidth 12
    \\#define kDirectEncodingKindBias 4.0
    \\uint calcRootCode(float y1, float y2, float y3) {
    \\    uint i1 = floatBitsToUint(y1) >> 31u;
    \\    uint i2 = floatBitsToUint(y2) >> 30u;
    \\    uint i3 = floatBitsToUint(y3) >> 29u;
    \\    uint shift = (i2 & 2u) | (i1 & ~2u);
    \\    shift = (i3 & 4u) | (shift & ~4u);
    \\    return ((0x2E74u >> shift) & 0x0101u);
    \\}
    \\
    \\float applyFillRule(float winding) {
    \\    if (u_fill_rule == 1) {
    \\        return 1.0 - abs(fract(winding * 0.5) * 2.0 - 1.0);
    \\    }
    \\    return abs(winding);
    \\}
    \\
    \\ivec2 calcBandLoc(ivec2 glyphLoc, uint offset) {
    \\    ivec2 loc = ivec2(glyphLoc.x + int(offset), glyphLoc.y);
    \\    loc.y += loc.x >> kLogBandTextureWidth;
    \\    loc.x &= (1 << kLogBandTextureWidth) - 1;
    \\    return loc;
    \\}
    \\
    \\ivec2 offsetCurveLoc(ivec2 base, int offset) {
    \\    ivec2 loc = ivec2(base.x + offset, base.y);
    \\    loc.y += loc.x >> kLogBandTextureWidth;
    \\    loc.x &= (1 << kLogBandTextureWidth) - 1;
    \\    return loc;
    \\}
    \\
    \\ivec2 offsetLayerLoc(ivec2 base, int offset) {
    \\    ivec2 loc = ivec2(base.x + offset, base.y);
    \\    loc.y += loc.x >> kLogBandTextureWidth;
    \\    loc.x &= (1 << kLogBandTextureWidth) - 1;
    \\    return loc;
    \\}
    \\
    \\struct SegmentRoots {
    \\    int count;
    \\    vec3 t;
    \\};
    \\
    \\struct SegmentData {
    \\    int kind;
    \\    vec2 p0;
    \\    vec2 p1;
    \\    vec2 p2;
    \\    vec2 p3;
    \\    vec3 weights;
    \\};
    \\
    \\float cbrtSigned(float v) {
    \\    return (v == 0.0) ? 0.0 : sign(v) * pow(abs(v), 1.0 / 3.0);
    \\}
    \\
    \\void appendRoot(inout SegmentRoots roots, float t) {
    \\    if (roots.count >= 3) return;
    \\    if (t < -1e-5 || t > 1.0 + 1e-5) return;
    \\    float clamped = clamp(t, 0.0, 1.0);
    \\    for (int i = 0; i < roots.count; i++) {
    \\        if (abs(roots.t[i] - clamped) <= 1e-5) return;
    \\    }
    \\    int insertAt = roots.count;
    \\    while (insertAt > 0 && roots.t[insertAt - 1] > clamped) {
    \\        roots.t[insertAt] = roots.t[insertAt - 1];
    \\        insertAt--;
    \\    }
    \\    roots.t[insertAt] = clamped;
    \\    roots.count++;
    \\}
    \\
    \\SegmentRoots solveQuadraticRoots(float a, float b, float cVal) {
    \\    SegmentRoots roots;
    \\    roots.count = 0;
    \\    roots.t = vec3(0.0);
    \\    if (abs(a) < 1.0 / 65536.0) {
    \\        if (abs(b) < 1.0 / 65536.0) return roots;
    \\        appendRoot(roots, -cVal / b);
    \\        return roots;
    \\    }
    \\    float disc = b * b - 4.0 * a * cVal;
    \\    if (disc < 0.0) {
    \\        if (disc > -1e-6) {
    \\            disc = 0.0;
    \\        } else {
    \\            return roots;
    \\        }
    \\    }
    \\    float sqrtDisc = sqrt(disc);
    \\    float inv2a = 0.5 / a;
    \\    appendRoot(roots, (-b - sqrtDisc) * inv2a);
    \\    appendRoot(roots, (-b + sqrtDisc) * inv2a);
    \\    return roots;
    \\}
    \\
    \\SegmentRoots solveCubicRoots(float a, float b, float cVal, float d) {
    \\    if (abs(a) < 1.0 / 65536.0) {
    \\        return solveQuadraticRoots(b, cVal, d);
    \\    }
    \\    SegmentRoots roots;
    \\    roots.count = 0;
    \\    roots.t = vec3(0.0);
    \\    float invA = 1.0 / a;
    \\    float aa = b * invA;
    \\    float bb = cVal * invA;
    \\    float cc = d * invA;
    \\    float p = bb - aa * aa / 3.0;
    \\    float q = (2.0 * aa * aa * aa) / 27.0 - (aa * bb) / 3.0 + cc;
    \\    float halfQ = q * 0.5;
    \\    float thirdP = p / 3.0;
    \\    float disc = halfQ * halfQ + thirdP * thirdP * thirdP;
    \\    float offset = aa / 3.0;
    \\    if (disc > 1e-8) {
    \\        float sqrtDisc = sqrt(disc);
    \\        float u = cbrtSigned(-halfQ + sqrtDisc);
    \\        float v = cbrtSigned(-halfQ - sqrtDisc);
    \\        appendRoot(roots, u + v - offset);
    \\        return roots;
    \\    }
    \\    if (disc >= -1e-8) {
    \\        float u = cbrtSigned(-halfQ);
    \\        appendRoot(roots, 2.0 * u - offset);
    \\        appendRoot(roots, -u - offset);
    \\        return roots;
    \\    }
    \\    float r = sqrt(-thirdP);
    \\    float phi = acos(clamp(-halfQ / (r * r * r), -1.0, 1.0));
    \\    float twoR = 2.0 * r;
    \\    appendRoot(roots, twoR * cos(phi / 3.0) - offset);
    \\    appendRoot(roots, twoR * cos((phi + 2.0 * 3.14159265358979323846) / 3.0) - offset);
    \\    appendRoot(roots, twoR * cos((phi + 4.0 * 3.14159265358979323846) / 3.0) - offset);
    \\    return roots;
    \\}
    \\
    \\vec2 solveQuadraticHorizDistances(float p0x, float p0y, float p1x, float p1y, float p2x, float p2y, float ppeX) {
    \\    float ax = p0x - p1x * 2.0 + p2x;
    \\    float ay = p0y - p1y * 2.0 + p2y;
    \\    float bx = p0x - p1x;
    \\    float by = p0y - p1y;
    \\
    \\    float t1;
    \\    float t2;
    \\    if (abs(ay) < 1.0 / 65536.0) {
    \\        float rb = 0.5 / by;
    \\        t1 = p0y * rb;
    \\        t2 = t1;
    \\    } else {
    \\        float ra = 1.0 / ay;
    \\        float d = sqrt(max(by * by - ay * p0y, 0.0));
    \\        t1 = (by - d) * ra;
    \\        t2 = (by + d) * ra;
    \\    }
    \\
    \\    float x1 = (ax * t1 - bx * 2.0) * t1 + p0x;
    \\    float x2 = (ax * t2 - bx * 2.0) * t2 + p0x;
    \\    return vec2(x1 * ppeX, x2 * ppeX);
    \\}
    \\
    \\vec2 solveQuadraticVertDistances(float p0x, float p0y, float p1x, float p1y, float p2x, float p2y, float ppeY) {
    \\    float ax = p0x - p1x * 2.0 + p2x;
    \\    float ay = p0y - p1y * 2.0 + p2y;
    \\    float bx = p0x - p1x;
    \\    float by = p0y - p1y;
    \\
    \\    float t1;
    \\    float t2;
    \\    if (abs(ax) < 1.0 / 65536.0) {
    \\        float rb = 0.5 / bx;
    \\        t1 = p0x * rb;
    \\        t2 = t1;
    \\    } else {
    \\        float ra = 1.0 / ax;
    \\        float d = sqrt(max(bx * bx - ax * p0x, 0.0));
    \\        t1 = (bx - d) * ra;
    \\        t2 = (bx + d) * ra;
    \\    }
    \\
    \\    float y1 = (ay * t1 - by * 2.0) * t1 + p0y;
    \\    float y2 = (ay * t2 - by * 2.0) * t2 + p0y;
    \\    return vec2(y1 * ppeY, y2 * ppeY);
    \\}
    \\
    \\SegmentData fetchSegment(ivec2 loc, int layer) {
    \\    vec4 tex0 = texelFetch(u_curve_tex, ivec3(loc, layer), 0);
    \\    ivec2 loc1 = offsetCurveLoc(loc, 1);
    \\    vec4 tex1 = texelFetch(u_curve_tex, ivec3(loc1, layer), 0);
    \\    ivec2 loc2 = offsetCurveLoc(loc, 2);
    \\    vec4 tex2 = texelFetch(u_curve_tex, ivec3(loc2, layer), 0);
    \\    ivec2 loc3 = offsetCurveLoc(loc, 3);
    \\    vec4 meta = texelFetch(u_curve_tex, ivec3(loc3, layer), 0);
    \\    SegmentData seg;
    \\    bool direct = tex2.z >= kDirectEncodingKindBias - 0.5;
    \\    if (direct) {
    \\        seg.kind = int(tex2.z - kDirectEncodingKindBias + 0.5);
    \\        seg.p0 = tex0.xy;
    \\        seg.p1 = tex0.zw;
    \\        seg.p2 = tex1.xy;
    \\        seg.p3 = tex1.zw;
    \\    } else {
    \\        vec2 anchor = tex0.xy * 256.0 + tex0.zw;
    \\        seg.kind = int(tex2.z + 0.5);
    \\        seg.p0 = anchor;
    \\        seg.p1 = anchor + tex1.xy;
    \\        seg.p2 = anchor + tex1.zw;
    \\        seg.p3 = anchor + tex2.xy;
    \\    }
    \\    seg.weights = vec3(tex2.w, meta.x, meta.y);
    \\    return seg;
    \\}
    \\
    \\vec2 evalSegmentPoint(SegmentData seg, float t) {
    \\    float mt = 1.0 - t;
    \\    if (seg.kind == 2) {
    \\        return mt * mt * mt * seg.p0 +
    \\            3.0 * mt * mt * t * seg.p1 +
    \\            3.0 * mt * t * t * seg.p2 +
    \\            t * t * t * seg.p3;
    \\    }
    \\    if (seg.kind == 1) {
    \\        float b0 = mt * mt;
    \\        float b1 = 2.0 * mt * t;
    \\        float b2 = t * t;
    \\        float bw0 = b0 * seg.weights.x;
    \\        float bw1 = b1 * seg.weights.y;
    \\        float bw2 = b2 * seg.weights.z;
    \\        float denom = max(bw0 + bw1 + bw2, 1.0 / 65536.0);
    \\        return (seg.p0 * bw0 + seg.p1 * bw1 + seg.p2 * bw2) / denom;
    \\    }
    \\    return mt * mt * seg.p0 + 2.0 * mt * t * seg.p1 + t * t * seg.p2;
    \\}
    \\
    \\vec2 evalSegmentDerivative(SegmentData seg, float t) {
    \\    float mt = 1.0 - t;
    \\    if (seg.kind == 2) {
    \\        return 3.0 * mt * mt * (seg.p1 - seg.p0) +
    \\            6.0 * mt * t * (seg.p2 - seg.p1) +
    \\            3.0 * t * t * (seg.p3 - seg.p2);
    \\    }
    \\    if (seg.kind == 1) {
    \\        float b0 = mt * mt;
    \\        float b1 = 2.0 * mt * t;
    \\        float b2 = t * t;
    \\        float db0 = -2.0 * mt;
    \\        float db1 = 2.0 - 4.0 * t;
    \\        float db2 = 2.0 * t;
    \\        float bw0 = b0 * seg.weights.x;
    \\        float bw1 = b1 * seg.weights.y;
    \\        float bw2 = b2 * seg.weights.z;
    \\        float dbw0 = db0 * seg.weights.x;
    \\        float dbw1 = db1 * seg.weights.y;
    \\        float dbw2 = db2 * seg.weights.z;
    \\        float denom = max(bw0 + bw1 + bw2, 1.0 / 65536.0);
    \\        float denomPrime = dbw0 + dbw1 + dbw2;
    \\        vec2 numer = seg.p0 * bw0 + seg.p1 * bw1 + seg.p2 * bw2;
    \\        vec2 numerPrime = seg.p0 * dbw0 + seg.p1 * dbw1 + seg.p2 * dbw2;
    \\        return (numerPrime * denom - numer * denomPrime) / (denom * denom);
    \\    }
    \\    return 2.0 * mt * (seg.p1 - seg.p0) + 2.0 * t * (seg.p2 - seg.p1);
    \\}
    \\
    \\SegmentRoots solveSegmentHorizontalRoots(SegmentData seg, float py) {
    \\    if (seg.kind == 2) {
    \\        float a = -seg.p0.y + 3.0 * seg.p1.y - 3.0 * seg.p2.y + seg.p3.y;
    \\        float b = 3.0 * seg.p0.y - 6.0 * seg.p1.y + 3.0 * seg.p2.y;
    \\        float cVal = -3.0 * seg.p0.y + 3.0 * seg.p1.y;
    \\        float d = seg.p0.y - py;
    \\        return solveCubicRoots(a, b, cVal, d);
    \\    }
    \\    if (seg.kind == 1) {
    \\        float c0 = seg.weights.x * (seg.p0.y - py);
    \\        float c1 = seg.weights.y * (seg.p1.y - py);
    \\        float c2 = seg.weights.z * (seg.p2.y - py);
    \\        return solveQuadraticRoots(c0 - 2.0 * c1 + c2, 2.0 * (c1 - c0), c0);
    \\    }
    \\    float a = seg.p0.y - 2.0 * seg.p1.y + seg.p2.y;
    \\    float b = 2.0 * (seg.p1.y - seg.p0.y);
    \\    return solveQuadraticRoots(a, b, seg.p0.y - py);
    \\}
    \\
    \\SegmentRoots solveSegmentVerticalRoots(SegmentData seg, float px) {
    \\    if (seg.kind == 2) {
    \\        float a = -seg.p0.x + 3.0 * seg.p1.x - 3.0 * seg.p2.x + seg.p3.x;
    \\        float b = 3.0 * seg.p0.x - 6.0 * seg.p1.x + 3.0 * seg.p2.x;
    \\        float cVal = -3.0 * seg.p0.x + 3.0 * seg.p1.x;
    \\        float d = seg.p0.x - px;
    \\        return solveCubicRoots(a, b, cVal, d);
    \\    }
    \\    if (seg.kind == 1) {
    \\        float c0 = seg.weights.x * (seg.p0.x - px);
    \\        float c1 = seg.weights.y * (seg.p1.x - px);
    \\        float c2 = seg.weights.z * (seg.p2.x - px);
    \\        return solveQuadraticRoots(c0 - 2.0 * c1 + c2, 2.0 * (c1 - c0), c0);
    \\    }
    \\    float a = seg.p0.x - 2.0 * seg.p1.x + seg.p2.x;
    \\    float b = 2.0 * (seg.p1.x - seg.p0.x);
    \\    return solveQuadraticRoots(a, b, seg.p0.x - px);
    \\}
    \\
    \\float segmentMaxX(SegmentData seg) {
    \\    float result = max(max(seg.p0.x, seg.p1.x), seg.p2.x);
    \\    if (seg.kind == 2) result = max(result, seg.p3.x);
    \\    return result;
    \\}
    \\
    \\float segmentMaxY(SegmentData seg) {
    \\    float result = max(max(seg.p0.y, seg.p1.y), seg.p2.y);
    \\    if (seg.kind == 2) result = max(result, seg.p3.y);
    \\    return result;
    \\}
    \\
    \\vec2 evalAxisCoverage(vec2 sampleRc, float ppe, ivec2 bandLoc, int count, int layer, bool horizontal) {
    \\    float cov = 0.0;
    \\    float wgt = 0.0;
    \\    for (int i = 0; i < count; i++) {
    \\        ivec2 bLoc = calcBandLoc(bandLoc, uint(i));
    \\        ivec2 cLoc = ivec2(texelFetch(u_band_tex, ivec3(bLoc, layer), 0).xy);
    \\        SegmentData seg = fetchSegment(cLoc, layer);
    \\        float maxCoord = (horizontal ? segmentMaxX(seg) - sampleRc.x : segmentMaxY(seg) - sampleRc.y);
    \\        if (maxCoord * ppe < -0.5) break;
    \\        if (seg.kind == 0) {
    \\            float p0x = seg.p0.x - sampleRc.x;
    \\            float p0y = seg.p0.y - sampleRc.y;
    \\            float p1x = seg.p1.x - sampleRc.x;
    \\            float p1y = seg.p1.y - sampleRc.y;
    \\            float p2x = seg.p2.x - sampleRc.x;
    \\            float p2y = seg.p2.y - sampleRc.y;
    \\            uint code = horizontal ? calcRootCode(p0y, p1y, p2y) : calcRootCode(p0x, p1x, p2x);
    \\            if (code == 0u) continue;
    \\
    \\            vec2 roots = horizontal
    \\                ? solveQuadraticHorizDistances(p0x, p0y, p1x, p1y, p2x, p2y, ppe)
    \\                : solveQuadraticVertDistances(p0x, p0y, p1x, p1y, p2x, p2y, ppe);
    \\
    \\            if ((code & 1u) != 0u) {
    \\                cov += (horizontal ? 1.0 : -1.0) * clamp(roots.x + 0.5, 0.0, 1.0);
    \\                wgt = max(wgt, clamp(1.0 - abs(roots.x) * 2.0, 0.0, 1.0));
    \\            }
    \\            if (code > 1u) {
    \\                cov += (horizontal ? -1.0 : 1.0) * clamp(roots.y + 0.5, 0.0, 1.0);
    \\                wgt = max(wgt, clamp(1.0 - abs(roots.y) * 2.0, 0.0, 1.0));
    \\            }
    \\            continue;
    \\        }
    \\        SegmentRoots roots = horizontal ? solveSegmentHorizontalRoots(seg, sampleRc.y) : solveSegmentVerticalRoots(seg, sampleRc.x);
    \\        for (int ri = 0; ri < roots.count; ri++) {
    \\            float t = roots.t[ri];
    \\            // Treat segment intersections as half-open [0, 1) so shared joins
    \\            // between adjacent segments are counted once instead of twice.
    \\            if (t >= 1.0 - 1e-5) continue;
    \\            vec2 point = evalSegmentPoint(seg, t);
    \\            vec2 deriv = evalSegmentDerivative(seg, t);
    \\            float derivAxis = horizontal ? deriv.y : -deriv.x;
    \\            if (abs(derivAxis) <= 1e-5) continue;
    \\            float dist = (horizontal ? point.x - sampleRc.x : point.y - sampleRc.y) * ppe;
    \\            cov += (derivAxis > 0.0 ? 1.0 : -1.0) * clamp(dist + 0.5, 0.0, 1.0);
    \\            wgt = max(wgt, clamp(1.0 - abs(dist) * 2.0, 0.0, 1.0));
    \\        }
    \\    }
    \\    return vec2(cov, wgt);
    \\}
    \\
    \\float wrapPaintT(float t, float extendMode) {
    \\    int mode = int(extendMode + 0.5);
    \\    if (mode == 1) {
    \\        return fract(t);
    \\    }
    \\    if (mode == 2) {
    \\        float reflected = mod(t, 2.0);
    \\        if (reflected < 0.0) reflected += 2.0;
    \\        return 1.0 - abs(reflected - 1.0);
    \\    }
    \\    return clamp(t, 0.0, 1.0);
    \\}
    \\
    \\vec4 sampleImagePaintTex(vec2 uv, int layer, int filterMode) {
    \\    if (filterMode == 1) {
    \\        ivec3 size = textureSize(u_image_tex, 0);
    \\        ivec2 texel = clamp(ivec2(uv * vec2(size.xy)), ivec2(0), size.xy - ivec2(1));
    \\        return texelFetch(u_image_tex, ivec3(texel, layer), 0);
    \\    }
    \\    return texture(u_image_tex, vec3(uv, float(layer)));
    \\}
    \\
    \\vec4 samplePathPaint(vec2 rc, ivec2 infoBase, vec4 info) {
    \\    int paintKind = int(-info.w + 0.5);
    \\    vec4 data0 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 2), 0);
    \\    if (paintKind == 1) {
    \\        return data0;
    \\    }
    \\
    \\    vec4 color0 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 3), 0);
    \\    vec4 color1 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 4), 0);
    \\
    \\    if (paintKind == 2) {
    \\        vec2 delta = data0.zw - data0.xy;
    \\        float lenSq = dot(delta, delta);
    \\        float t = 0.0;
    \\        if (lenSq > 1e-10) {
    \\            t = dot(rc - data0.xy, delta) / lenSq;
    \\        }
    \\        vec4 extra = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 5), 0);
    \\        return mix(color0, color1, wrapPaintT(t, extra.x));
    \\    }
    \\
    \\    if (paintKind == 3) {
    \\        float radius = max(abs(data0.z), 1.0 / 65536.0);
    \\        float t = length(rc - data0.xy) / radius;
    \\        return mix(color0, color1, wrapPaintT(t, data0.w));
    \\    }
    \\
    \\    if (paintKind == 4) {
    \\        vec4 data1 = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 3), 0);
    \\        vec4 tint = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 4), 0);
    \\        vec4 extra = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 5), 0);
    \\        vec2 rawUv = vec2(
    \\            dot(vec3(rc, 1.0), vec3(data0.x, data0.y, data0.z)),
    \\            dot(vec3(rc, 1.0), vec3(data1.x, data1.y, data1.z))
    \\        );
    \\        vec2 wrappedUv = vec2(
    \\            wrapPaintT(rawUv.x, extra.z) * extra.x,
    \\            wrapPaintT(rawUv.y, extra.w) * extra.y
    \\        );
    \\        return sampleImagePaintTex(wrappedUv, int(data0.w + 0.5), int(data1.w + 0.5)) * tint;
    \\    }
    \\
    \\    return vec4(1.0, 0.0, 1.0, 1.0);
    \\}
    \\
    \\// Evaluate Slug coverage for a single glyph layer (non-subpixel).
    \\float evalGlyphCoverage(vec2 rc, vec2 epp, vec2 ppe,
    \\                        ivec2 gLoc, ivec2 bandMax, vec4 banding, int texLayer) {
    \\    ivec2 bandIdx = clamp(ivec2(rc * banding.xy + banding.zw), ivec2(0), bandMax);
    \\    uvec2 hbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandIdx.y, gLoc.y, texLayer), 0).xy;
    \\    ivec2 hLoc = calcBandLoc(gLoc, hbd.y);
    \\    int hCount = int(hbd.x);
    \\    vec2 horiz = evalAxisCoverage(rc, ppe.x, hLoc, hCount, texLayer, true);
    \\    uvec2 vbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandMax.y + 1 + bandIdx.x, gLoc.y, texLayer), 0).xy;
    \\    ivec2 vLoc = calcBandLoc(gLoc, vbd.y);
    \\    int vCount = int(vbd.x);
    \\    vec2 vert = evalAxisCoverage(rc, ppe.y, vLoc, vCount, texLayer, false);
    \\    float wsum = horiz.y + vert.y;
    \\    float blended = horiz.x * horiz.y + vert.x * vert.y;
    \\    float cov = max(applyFillRule(blended / max(wsum, 1.0 / 65536.0)),
    \\                    min(applyFillRule(horiz.x), applyFillRule(vert.x)));
    \\    return clamp(cov, 0.0, 1.0);
    \\}
    \\
    \\float srgbGamma(float c) {
    \\    return (c <= 0.0031308) ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
    \\}
    \\
    \\vec4 premultiplyColor(vec4 color, float cov) {
    \\    float alpha = color.a * cov;
    \\    return vec4(color.rgb * alpha, alpha);
    \\}
    \\
    \\vec4 premultiplyColorSubpixel(vec4 color, vec3 cov) {
    \\    vec3 alpha = vec3(color.a) * cov;
    \\    return vec4(color.rgb * alpha, color.a * max(max(cov.r, cov.g), cov.b));
    \\}
    \\
    \\// Evaluate horizontal coverage (against vertical glyph edges) at xOffset from rc.
    \\// Returns vec2(xcov, xwgt).
    \\vec2 evalHorizCoverage(vec2 rc, float xOffset, vec2 ppe,
    \\                       ivec2 gLoc, ivec2 hLoc, int hCount, int layer) {
    \\    return evalAxisCoverage(rc + vec2(xOffset, 0.0), ppe.x, hLoc, hCount, layer, true);
    \\}
    \\
    \\// Evaluate vertical coverage (against horizontal glyph edges) at yOffset from rc.
    \\// Returns vec2(ycov, ywgt).
    \\vec2 evalVertCoverage(vec2 rc, float yOffset, vec2 ppe,
    \\                      ivec2 vLoc, int vCount, int layer) {
    \\    return evalAxisCoverage(rc + vec2(0.0, yOffset), ppe.y, vLoc, vCount, layer, false);
    \\}
    \\
    \\// Blend per-subpixel coverage against the shared orthogonal axis coverage.
    \\vec3 blendSubpixel(vec2 cw_r, vec2 cw_g, vec2 cw_b, vec2 cw_o) {
    \\    float wsum_r = cw_r.y + cw_o.y; float blend_r = cw_r.x * cw_r.y + cw_o.x * cw_o.y;
    \\    float wsum_g = cw_g.y + cw_o.y; float blend_g = cw_g.x * cw_g.y + cw_o.x * cw_o.y;
    \\    float wsum_b = cw_b.y + cw_o.y; float blend_b = cw_b.x * cw_b.y + cw_o.x * cw_o.y;
    \\    return vec3(
    \\        clamp(max(applyFillRule(blend_r / max(wsum_r, 1.0/65536.0)),
    \\                  min(applyFillRule(cw_r.x), applyFillRule(cw_o.x))), 0.0, 1.0),
    \\        clamp(max(applyFillRule(blend_g / max(wsum_g, 1.0/65536.0)),
    \\                  min(applyFillRule(cw_g.x), applyFillRule(cw_o.x))), 0.0, 1.0),
    \\        clamp(max(applyFillRule(blend_b / max(wsum_b, 1.0/65536.0)),
    \\                  min(applyFillRule(cw_b.x), applyFillRule(cw_o.x))), 0.0, 1.0)
    \\    );
    \\}
    \\
    \\vec3 evalGlyphCoverageSubpixelLayer(vec2 rc, vec2 epp, vec2 ppe, ivec2 gLoc, ivec2 bandMax, int layer) {
    \\    ivec2 bandIdx = clamp(ivec2(rc * v_banding.xy + v_banding.zw), ivec2(0), bandMax);
    \\
    \\    uvec2 hbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandIdx.y, gLoc.y, layer), 0).xy;
    \\    ivec2 hLoc = calcBandLoc(gLoc, hbd.y);
    \\    int hCount = int(hbd.x);
    \\
    \\    uvec2 vbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandMax.y + 1 + bandIdx.x, gLoc.y, layer), 0).xy;
    \\    ivec2 vLoc = calcBandLoc(gLoc, vbd.y);
    \\    int vCount = int(vbd.x);
    \\
    \\    if (u_subpixel_order <= 2) {
    \\        float sp = epp.x / 3.0;
    \\        float s = (u_subpixel_order == 2) ? -1.0 : 1.0;
    \\        vec2 cw_r = evalHorizCoverage(rc, -sp * s, ppe, gLoc, hLoc, hCount, layer);
    \\        vec2 cw_g = evalHorizCoverage(rc,  0.0,    ppe, gLoc, hLoc, hCount, layer);
    \\        vec2 cw_b = evalHorizCoverage(rc, +sp * s, ppe, gLoc, hLoc, hCount, layer);
    \\        vec2 cw_v = evalVertCoverage(rc, 0.0, ppe, vLoc, vCount, layer);
    \\        return blendSubpixel(cw_r, cw_g, cw_b, cw_v);
    \\    }
    \\
    \\    float sp = epp.y / 3.0;
    \\    float s = (u_subpixel_order == 4) ? -1.0 : 1.0;
    \\    vec2 cw_h = evalHorizCoverage(rc, 0.0, ppe, gLoc, hLoc, hCount, layer);
    \\    vec2 cw_r = evalVertCoverage(rc, -sp * s, ppe, vLoc, vCount, layer);
    \\    vec2 cw_g = evalVertCoverage(rc,  0.0,    ppe, vLoc, vCount, layer);
    \\    vec2 cw_b = evalVertCoverage(rc, +sp * s, ppe, vLoc, vCount, layer);
    \\    return blendSubpixel(cw_r, cw_g, cw_b, cw_h);
    \\}
    \\
    \\vec4 compositePathGroupSubpixel(vec2 rc, vec2 epp, vec2 ppe, ivec2 infoBase, vec4 header, int texLayer) {
    \\    int layer_count = int(header.x + 0.5);
    \\    int composite_mode = int(header.y + 0.5);
    \\    vec4 result = vec4(0.0);
    \\    vec3 fill_cov = vec3(0.0);
    \\    vec3 stroke_cov = vec3(0.0);
    \\    vec4 fill_paint = vec4(0.0);
    \\    vec4 stroke_paint = vec4(0.0);
    \\
    \\    for (int l = 0; l < layer_count; l++) {
    \\        ivec2 loc = offsetLayerLoc(infoBase, 1 + l * 6);
    \\        vec4 info = texelFetch(u_layer_tex, loc, 0);
    \\        ivec2 gLoc = ivec2(info.xy);
    \\        ivec2 bandMax = ivec2(floatBitsToInt(info.z) & 0xFFFF,
    \\                              (floatBitsToInt(info.z) >> 16) & 0xFFFF);
    \\        vec3 cov = evalGlyphCoverageSubpixelLayer(rc, epp, ppe, gLoc, bandMax, texLayer);
    \\        vec4 paint = samplePathPaint(rc, loc, info);
    \\
    \\        if (composite_mode == 1 && layer_count >= 2 && l < 2) {
    \\            if (l == 0) {
    \\                fill_cov = cov;
    \\                fill_paint = paint;
    \\            } else {
    \\                stroke_cov = cov;
    \\                stroke_paint = paint;
    \\            }
    \\            continue;
    \\        }
    \\
    \\        vec4 premul = premultiplyColorSubpixel(paint, cov);
    \\        result = premul + result * (1.0 - premul.a);
    \\    }
    \\
    \\    if (composite_mode == 1 && layer_count >= 2) {
    \\        vec3 border_cov = min(fill_cov, stroke_cov);
    \\        vec3 interior_cov = max(fill_cov - border_cov, vec3(0.0));
    \\        vec4 combined = premultiplyColorSubpixel(fill_paint, interior_cov) + premultiplyColorSubpixel(stroke_paint, border_cov);
    \\        result = result + combined * (1.0 - result.a);
    \\    }
    \\
    \\    return result;
    \\}
    \\
    \\void main() {
    \\    vec2 rc = v_texcoord;
    \\    vec2 epp = fwidth(rc);
    \\    vec2 ppe = 1.0 / epp;
    \\
    \\    int atlas_layer = (v_glyph.w >> 8) & 0xFF;
    \\
    \\    if (atlas_layer == 0xFF) {
    \\        ivec2 infoBase = v_glyph.xy;
    \\        vec4 firstInfo = texelFetch(u_layer_tex, infoBase, 0);
    \\        if (firstInfo.w < 0.0) {
    \\            if (int(-firstInfo.w + 0.5) == 5) {
    \\                vec4 result = compositePathGroupSubpixel(rc, epp, ppe, infoBase, firstInfo, int(v_banding.w));
    \\                if (result.a < 1.0/255.0) discard;
    \\                frag_color = result;
    \\                return;
    \\            }
    \\            vec4 band = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, 1), 0);
    \\            ivec2 gLoc = ivec2(firstInfo.xy);
    \\            ivec2 bandMax = ivec2(floatBitsToInt(firstInfo.z) & 0xFFFF,
    \\                                  (floatBitsToInt(firstInfo.z) >> 16) & 0xFFFF);
    \\            int layer = int(v_banding.w);
    \\            ivec2 bandIdx = clamp(ivec2(rc * band.xy + band.zw), ivec2(0), bandMax);
    \\
    \\            uvec2 hbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandIdx.y, gLoc.y, layer), 0).xy;
    \\            ivec2 hLoc = calcBandLoc(gLoc, hbd.y);
    \\            int hCount = int(hbd.x);
    \\
    \\            uvec2 vbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandMax.y + 1 + bandIdx.x, gLoc.y, layer), 0).xy;
    \\            ivec2 vLoc = calcBandLoc(gLoc, vbd.y);
    \\            int vCount = int(vbd.x);
    \\
    \\            vec3 cov;
    \\            if (u_subpixel_order <= 2) {
    \\                float sp = epp.x / 3.0;
    \\                float s = (u_subpixel_order == 2) ? -1.0 : 1.0;
    \\                vec2 cw_r = evalHorizCoverage(rc, -sp * s, ppe, gLoc, hLoc, hCount, layer);
    \\                vec2 cw_g = evalHorizCoverage(rc,  0.0,    ppe, gLoc, hLoc, hCount, layer);
    \\                vec2 cw_b = evalHorizCoverage(rc, +sp * s, ppe, gLoc, hLoc, hCount, layer);
    \\                vec2 cw_v = evalVertCoverage(rc, 0.0, ppe, vLoc, vCount, layer);
    \\                cov = blendSubpixel(cw_r, cw_g, cw_b, cw_v);
    \\            } else {
    \\                float sp = epp.y / 3.0;
    \\                float s = (u_subpixel_order == 4) ? -1.0 : 1.0;
    \\                vec2 cw_h = evalHorizCoverage(rc, 0.0, ppe, gLoc, hLoc, hCount, layer);
    \\                vec2 cw_r = evalVertCoverage(rc, -sp * s, ppe, vLoc, vCount, layer);
    \\                vec2 cw_g = evalVertCoverage(rc,  0.0,    ppe, vLoc, vCount, layer);
    \\                vec2 cw_b = evalVertCoverage(rc, +sp * s, ppe, vLoc, vCount, layer);
    \\                cov = blendSubpixel(cw_r, cw_g, cw_b, cw_h);
    \\            }
    \\
    \\            if (max(max(cov.r, cov.g), cov.b) < 1.0/255.0) discard;
    \\            frag_color = premultiplyColorSubpixel(samplePathPaint(rc, infoBase, firstInfo), cov);
    \\            return;
    \\        }
    \\
    \\        // Multi-layer COLR: use non-subpixel evaluation (color emoji don't need subpixel AA)
    \\        int layer_count = v_glyph.z;
    \\        vec4 result = vec4(0.0);
    \\        for (int l = 0; l < layer_count; l++) {
    \\            ivec2 loc = offsetLayerLoc(infoBase, l * 3);
    \\            vec4 info  = texelFetch(u_layer_tex, loc, 0);
    \\            vec4 band  = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, l * 3 + 1), 0);
    \\            vec4 color = texelFetch(u_layer_tex, offsetLayerLoc(infoBase, l * 3 + 2), 0);
    \\            if (color.r < 0.0) color = v_color;
    \\            ivec2 lGLoc = ivec2(info.xy);
    \\            int bandMaxH = floatBitsToInt(info.z) & 0xFFFF;
    \\            int bandMaxV = (floatBitsToInt(info.z) >> 16) & 0xFFFF;
    \\            int texLayer = int(v_banding.w);
    \\            float cov = evalGlyphCoverage(rc, epp, ppe, lGLoc,
    \\                                          ivec2(bandMaxH, bandMaxV), band, texLayer);
    \\            vec4 premul = premultiplyColor(color, cov);
    \\            result = premul + result * (1.0 - premul.a);
    \\        }
    \\        if (result.a < 1.0/255.0) discard;
    \\        frag_color = result;
    \\        return;
    \\    }
    \\
    \\    // Single-layer subpixel path
    \\    int layer = atlas_layer;
    \\    ivec2 bandMax = ivec2(v_glyph.z, v_glyph.w & 0xFF);
    \\    ivec2 bandIdx = clamp(ivec2(rc * v_banding.xy + v_banding.zw), ivec2(0), bandMax);
    \\    ivec2 gLoc = v_glyph.xy;
    \\
    \\    uvec2 hbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandIdx.y, gLoc.y, layer), 0).xy;
    \\    ivec2 hLoc = calcBandLoc(gLoc, hbd.y);
    \\    int hCount = int(hbd.x);
    \\
    \\    uvec2 vbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandMax.y + 1 + bandIdx.x, gLoc.y, layer), 0).xy;
    \\    ivec2 vLoc = calcBandLoc(gLoc, vbd.y);
    \\    int vCount = int(vbd.x);
    \\
    \\    vec3 cov;
    \\
    \\    if (u_subpixel_order <= 2) {
    \\        float sp = epp.x / 3.0;
    \\        float s = (u_subpixel_order == 2) ? -1.0 : 1.0;
    \\        vec2 cw_r = evalHorizCoverage(rc, -sp * s, ppe, gLoc, hLoc, hCount, layer);
    \\        vec2 cw_g = evalHorizCoverage(rc,  0.0,    ppe, gLoc, hLoc, hCount, layer);
    \\        vec2 cw_b = evalHorizCoverage(rc, +sp * s, ppe, gLoc, hLoc, hCount, layer);
    \\        vec2 cw_v = evalVertCoverage(rc, 0.0, ppe, vLoc, vCount, layer);
    \\        cov = blendSubpixel(cw_r, cw_g, cw_b, cw_v);
    \\    } else {
    \\        float sp = epp.y / 3.0;
    \\        float s = (u_subpixel_order == 4) ? -1.0 : 1.0;
    \\        vec2 cw_h = evalHorizCoverage(rc, 0.0, ppe, gLoc, hLoc, hCount, layer);
    \\        vec2 cw_r = evalVertCoverage(rc, -sp * s, ppe, vLoc, vCount, layer);
    \\        vec2 cw_g = evalVertCoverage(rc,  0.0,    ppe, vLoc, vCount, layer);
    \\        vec2 cw_b = evalVertCoverage(rc, +sp * s, ppe, vLoc, vCount, layer);
    \\        cov = blendSubpixel(cw_r, cw_g, cw_b, cw_h);
    \\    }
    \\
    \\    if (max(max(cov.r, cov.g), cov.b) < 1.0/255.0) discard;
    \\    frag_color = premultiplyColorSubpixel(v_color, cov);
    \\}
;
