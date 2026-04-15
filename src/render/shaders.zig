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
    \\uniform int u_fill_rule; // 0 = non-zero winding (default), 1 = even-odd
    \\
    \\out vec4 frag_color;
    \\
    \\#define kLogBandTextureWidth 12
    \\
    \\uint calcRootCode(float y1, float y2, float y3) {
    \\    uint i1 = floatBitsToUint(y1) >> 31u;
    \\    uint i2 = floatBitsToUint(y2) >> 30u;
    \\    uint i3 = floatBitsToUint(y3) >> 29u;
    \\    uint shift = (i2 & 2u) | (i1 & ~2u);
    \\    shift = (i3 & 4u) | (shift & ~4u);
    \\    return ((0x2E74u >> shift) & 0x0101u);
    \\}
    \\
    \\// Apply fill rule to winding number
    \\float applyFillRule(float winding) {
    \\    if (u_fill_rule == 1) {
    \\        return 1.0 - abs(fract(winding * 0.5) * 2.0 - 1.0);
    \\    }
    \\    return abs(winding);
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
    \\ivec2 calcBandLoc(ivec2 glyphLoc, uint offset) {
    \\    ivec2 loc = ivec2(glyphLoc.x + int(offset), glyphLoc.y);
    \\    loc.y += loc.x >> kLogBandTextureWidth;
    \\    loc.x &= (1 << kLogBandTextureWidth) - 1;
    \\    return loc;
    \\}
    \\
    \\void main() {
    \\    vec2 rc = v_texcoord;
    \\    vec2 epp = fwidth(rc);
    \\    vec2 ppe = 1.0 / epp;
    \\
    \\    int layer = (v_glyph.w >> 8) & 0xFF;
    \\    ivec2 bandMax = ivec2(v_glyph.z, v_glyph.w & 0xFF);
    \\    ivec2 bandIdx = clamp(ivec2(rc * v_banding.xy + v_banding.zw), ivec2(0), bandMax);
    \\    ivec2 gLoc = v_glyph.xy;
    \\
    \\    float xcov = 0.0, xwgt = 0.0;
    \\
    \\    // Horizontal band
    \\    uvec2 hbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandIdx.y, gLoc.y, layer), 0).xy;
    \\    ivec2 hLoc = calcBandLoc(gLoc, hbd.y);
    \\    int hCount = int(hbd.x);
    \\
    \\    for (int i = 0; i < hCount; i++) {
    \\        ivec2 bLoc_h = calcBandLoc(hLoc, uint(i));
    \\        ivec2 cLoc = ivec2(texelFetch(u_band_tex, ivec3(bLoc_h, layer), 0).xy);
    \\        vec4 p12 = texelFetch(u_curve_tex, ivec3(cLoc, layer), 0) - vec4(rc, rc);
    \\        vec2 p3 = texelFetch(u_curve_tex, ivec3(cLoc.x + 1, cLoc.y, layer), 0).xy - rc;
    \\
    \\        if (max(max(p12.x, p12.z), p3.x) * ppe.x < -0.5) break;
    \\
    \\        uint code = calcRootCode(p12.y, p12.w, p3.y);
    \\        if (code != 0u) {
    \\            vec2 r = solveHorizPoly(p12, p3) * ppe.x;
    \\            if ((code & 1u) != 0u) {
    \\                xcov += clamp(r.x + 0.5, 0.0, 1.0);
    \\                xwgt = max(xwgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0));
    \\            }
    \\            if (code > 1u) {
    \\                xcov -= clamp(r.y + 0.5, 0.0, 1.0);
    \\                xwgt = max(xwgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0));
    \\            }
    \\        }
    \\    }
    \\
    \\    float ycov = 0.0, ywgt = 0.0;
    \\
    \\    // Vertical band
    \\    uvec2 vbd = texelFetch(u_band_tex, ivec3(gLoc.x + bandMax.y + 1 + bandIdx.x, gLoc.y, layer), 0).xy;
    \\    ivec2 vLoc = calcBandLoc(gLoc, vbd.y);
    \\    int vCount = int(vbd.x);
    \\
    \\    for (int i = 0; i < vCount; i++) {
    \\        ivec2 bLoc_v = calcBandLoc(vLoc, uint(i));
    \\        ivec2 cLoc = ivec2(texelFetch(u_band_tex, ivec3(bLoc_v, layer), 0).xy);
    \\        vec4 p12 = texelFetch(u_curve_tex, ivec3(cLoc, layer), 0) - vec4(rc, rc);
    \\        vec2 p3 = texelFetch(u_curve_tex, ivec3(cLoc.x + 1, cLoc.y, layer), 0).xy - rc;
    \\
    \\        if (max(max(p12.y, p12.w), p3.y) * ppe.y < -0.5) break;
    \\
    \\        uint code = calcRootCode(p12.x, p12.z, p3.x);
    \\        if (code != 0u) {
    \\            vec2 r = solveVertPoly(p12, p3) * ppe.y;
    \\            if ((code & 1u) != 0u) {
    \\                ycov -= clamp(r.x + 0.5, 0.0, 1.0);
    \\                ywgt = max(ywgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0));
    \\            }
    \\            if (code > 1u) {
    \\                ycov += clamp(r.y + 0.5, 0.0, 1.0);
    \\                ywgt = max(ywgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0));
    \\            }
    \\        }
    \\    }
    \\
    \\    float wsum = xwgt + ywgt;
    \\    float blended = xcov * xwgt + ycov * ywgt;
    \\    float coverage = max(applyFillRule(blended / max(wsum, 1.0 / 65536.0)),
    \\                         min(applyFillRule(xcov), applyFillRule(ycov)));
    \\    coverage = clamp(coverage, 0.0, 1.0);
    \\    // sRGB gamma: linear → sRGB transfer function
    \\    coverage = (coverage <= 0.0031308)
    \\        ? coverage * 12.92
    \\        : 1.055 * pow(coverage, 1.0 / 2.4) - 0.055;
    \\
    \\    if (coverage < 1.0/255.0) discard;
    \\    frag_color = v_color * coverage;
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
    \\uniform int u_fill_rule;      // 0 = non-zero winding (default), 1 = even-odd
    \\uniform int u_subpixel_order; // 1=RGB, 2=BGR, 3=VRGB, 4=VBGR
    \\
    \\out vec4 frag_color;
    \\
    \\#define kLogBandTextureWidth 12
    \\
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
    \\ivec2 calcBandLoc(ivec2 glyphLoc, uint offset) {
    \\    ivec2 loc = ivec2(glyphLoc.x + int(offset), glyphLoc.y);
    \\    loc.y += loc.x >> kLogBandTextureWidth;
    \\    loc.x &= (1 << kLogBandTextureWidth) - 1;
    \\    return loc;
    \\}
    \\
    \\// Evaluate horizontal coverage (against vertical glyph edges) at xOffset from rc.
    \\// Returns vec2(xcov, xwgt).
    \\vec2 evalHorizCoverage(vec2 rc, float xOffset, vec2 ppe,
    \\                       ivec2 gLoc, ivec2 hLoc, int hCount, int layer) {
    \\    float xcov = 0.0;
    \\    float xwgt = 0.0;
    \\    vec2 sp = rc + vec2(xOffset, 0.0);
    \\    for (int i = 0; i < hCount; i++) {
    \\        ivec2 bLoc_h = calcBandLoc(hLoc, uint(i));
    \\        ivec2 cLoc = ivec2(texelFetch(u_band_tex, ivec3(bLoc_h, layer), 0).xy);
    \\        vec4 p12 = texelFetch(u_curve_tex, ivec3(cLoc, layer), 0) - vec4(sp, sp);
    \\        vec2 p3 = texelFetch(u_curve_tex, ivec3(cLoc.x + 1, cLoc.y, layer), 0).xy - sp;
    \\
    \\        if (max(max(p12.x, p12.z), p3.x) * ppe.x < -0.5) break;
    \\
    \\        uint code = calcRootCode(p12.y, p12.w, p3.y);
    \\        if (code != 0u) {
    \\            vec2 r = solveHorizPoly(p12, p3) * ppe.x;
    \\            if ((code & 1u) != 0u) {
    \\                xcov += clamp(r.x + 0.5, 0.0, 1.0);
    \\                xwgt = max(xwgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0));
    \\            }
    \\            if (code > 1u) {
    \\                xcov -= clamp(r.y + 0.5, 0.0, 1.0);
    \\                xwgt = max(xwgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0));
    \\            }
    \\        }
    \\    }
    \\    return vec2(xcov, xwgt);
    \\}
    \\
    \\// Evaluate vertical coverage (against horizontal glyph edges) at yOffset from rc.
    \\// Returns vec2(ycov, ywgt).
    \\vec2 evalVertCoverage(vec2 rc, float yOffset, vec2 ppe,
    \\                      ivec2 vLoc, int vCount, int layer) {
    \\    float ycov = 0.0;
    \\    float ywgt = 0.0;
    \\    vec2 sp = rc + vec2(0.0, yOffset);
    \\    for (int i = 0; i < vCount; i++) {
    \\        ivec2 bLoc_v = calcBandLoc(vLoc, uint(i));
    \\        ivec2 cLoc = ivec2(texelFetch(u_band_tex, ivec3(bLoc_v, layer), 0).xy);
    \\        vec4 p12 = texelFetch(u_curve_tex, ivec3(cLoc, layer), 0) - vec4(sp, sp);
    \\        vec2 p3 = texelFetch(u_curve_tex, ivec3(cLoc.x + 1, cLoc.y, layer), 0).xy - sp;
    \\
    \\        if (max(max(p12.y, p12.w), p3.y) * ppe.y < -0.5) break;
    \\
    \\        uint code = calcRootCode(p12.x, p12.z, p3.x);
    \\        if (code != 0u) {
    \\            vec2 r = solveVertPoly(p12, p3) * ppe.y;
    \\            if ((code & 1u) != 0u) {
    \\                ycov -= clamp(r.x + 0.5, 0.0, 1.0);
    \\                ywgt = max(ywgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0));
    \\            }
    \\            if (code > 1u) {
    \\                ycov += clamp(r.y + 0.5, 0.0, 1.0);
    \\                ywgt = max(ywgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0));
    \\            }
    \\        }
    \\    }
    \\    return vec2(ycov, ywgt);
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
    \\void main() {
    \\    vec2 rc = v_texcoord;
    \\    vec2 epp = fwidth(rc);
    \\    vec2 ppe = 1.0 / epp;
    \\
    \\    int layer = (v_glyph.w >> 8) & 0xFF;
    \\    ivec2 bandMax = ivec2(v_glyph.z, v_glyph.w & 0xFF);
    \\    ivec2 bandIdx = clamp(ivec2(rc * v_banding.xy + v_banding.zw), ivec2(0), bandMax);
    \\    ivec2 gLoc = v_glyph.xy;
    \\
    \\    // Fetch both band headers upfront — needed by both horizontal and vertical paths.
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
    \\        // Horizontal subpixels: RGB (1) runs left→right, BGR (2) right→left.
    \\        float sp = epp.x / 3.0;
    \\        float s = (u_subpixel_order == 2) ? -1.0 : 1.0;
    \\        vec2 cw_r = evalHorizCoverage(rc, -sp * s, ppe, gLoc, hLoc, hCount, layer);
    \\        vec2 cw_g = evalHorizCoverage(rc,  0.0,    ppe, gLoc, hLoc, hCount, layer);
    \\        vec2 cw_b = evalHorizCoverage(rc, +sp * s, ppe, gLoc, hLoc, hCount, layer);
    \\        vec2 cw_v = evalVertCoverage(rc, 0.0, ppe, vLoc, vCount, layer);
    \\        cov = blendSubpixel(cw_r, cw_g, cw_b, cw_v);
    \\    } else {
    \\        // Vertical subpixels: VRGB (3) runs top→bottom, VBGR (4) bottom→top.
    \\        float sp = epp.y / 3.0;
    \\        float s = (u_subpixel_order == 4) ? -1.0 : 1.0;
    \\        vec2 cw_h = evalHorizCoverage(rc, 0.0, ppe, gLoc, hLoc, hCount, layer);
    \\        vec2 cw_r = evalVertCoverage(rc, -sp * s, ppe, vLoc, vCount, layer);
    \\        vec2 cw_g = evalVertCoverage(rc,  0.0,    ppe, vLoc, vCount, layer);
    \\        vec2 cw_b = evalVertCoverage(rc, +sp * s, ppe, vLoc, vCount, layer);
    \\        cov = blendSubpixel(cw_r, cw_g, cw_b, cw_h);
    \\    }
    \\
    \\    // sRGB gamma: linear → sRGB transfer function
    \\    cov = mix(cov * 12.92,
    \\              1.055 * pow(cov, vec3(1.0 / 2.4)) - 0.055,
    \\              step(vec3(0.0031308), cov));
    \\
    \\    if (max(max(cov.r, cov.g), cov.b) < 1.0/255.0) discard;
    \\    frag_color = vec4(v_color.rgb * cov, max(max(cov.r, cov.g), cov.b) * v_color.a);
    \\}
;

