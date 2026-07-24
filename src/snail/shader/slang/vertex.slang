// Shared non-autohint text vertex path. This module is canonical.
//
// Matrix convention note: generated GLSL `mat4` indexes columns (`M[c][r]`), Slang
// `float4x4` indexes rows (`M[r][c]`). The GLSL body builds
// `m0 = vec4(M[0].x, M[1].x, M[2].x, M[3].x)` — logical row 0 — which in
// Slang is simply `mvp[0]`. Likewise GLSL `M * v` is Slang `mul(M, v)`.
// The *memory* convention (how the 16 CPU floats map onto the logical
// matrix) is chosen by the -matrix-layout-* compile flag; see
// families/text.slang.
module vertex;

import color_common;

public struct TextVertexIn {
    public float4 rect;    // source bbox: min_x, min_y, max_x, max_y (em-space, f16 storage)
    public float4 xform;   // linear transform: xx, xy, yx, yy
    public float2 origin;  // tx, ty
    public uint2 glyph;    // gz, gw packed glyph data
    public uint4 payload;  // regular band-transform bits or compact autohint policy
    public float4 col;     // linear-light f16 base color
    public float4 tint;    // linear-light f16 instance tint
};

public struct TextVertexResult {
    public float4 position;
    public float4 color;
    public float4 tint;
    public float2 texcoord;
    public float4 banding;
    public int4 glyph;
};

static const float2 kCorners[4] = {
    float2(0.0, 0.0),
    float2(1.0, 0.0),
    float2(1.0, 1.0),
    float2(0.0, 1.0)
};

public float snailVertexDilationScale(int subpixel_order) {
    const float kCornerAxisScale = 1.41421356237;
    const float kLcdAxisSupportScale = 7.0 / 3.0;
    return kCornerAxisScale * ((subpixel_order == 0) ? 1.0 : kLcdAxisSupportScale);
}

public TextVertexResult snailTextVertex(TextVertexIn input, uint vertex_index, float4x4 mvp, float2 viewport, int subpixel_order) {
    float2 t = kCorners[vertex_index];

    float2 em = lerp(input.rect.xy, input.rect.zw, t);

    // Outward corner normal in local space (dilation direction).
    float2 nd = t * 2.0 - 1.0;

    float4 eff_xform = input.xform;
    float2 eff_origin = input.origin;
    float4 eff_tint = input.tint;

    float2 pos = float2(
        eff_xform.x * em.x + eff_xform.y * em.y + eff_origin.x,
        eff_xform.z * em.x + eff_xform.w * em.y + eff_origin.y
    );

    float2 wn = float2(
        eff_xform.x * nd.x + eff_xform.y * nd.y,
        eff_xform.z * nd.x + eff_xform.w * nd.y
    );

    // Normalize before forming the determinant: direct f32 products can
    // underflow/overflow for otherwise representable affine inverses.
    float xform_scale = max(max(abs(eff_xform.x), abs(eff_xform.y)),
                            max(abs(eff_xform.z), abs(eff_xform.w)));
    float4 unit_xform = eff_xform / xform_scale;
    float det = unit_xform.x * unit_xform.w - unit_xform.y * unit_xform.z;
    float inv_det_scale = 1.0 / (det * xform_scale);
    float4 jac = float4(
        unit_xform.w * inv_det_scale,
        -unit_xform.y * inv_det_scale,
        -unit_xform.z * inv_det_scale,
        unit_xform.x * inv_det_scale
    );

    TextVertexResult r;

    uint gz = input.glyph.x;
    uint gw = input.glyph.y;
    r.glyph = int4(int(gz & 0xFFFFu), int(gz >> 16u), int(gw & 0xFFFFu), int(gw >> 16u));
    r.banding = asfloat(input.payload);
    r.color = input.col;
    r.tint = eff_tint;

    // Slug dynamic dilation. GLSL gathered rows element-wise
    // (m0 = vec4(M[0].x, M[1].x, M[2].x, M[3].x)); Slang's row indexing
    // gives the same logical rows directly.
    float4 m0 = mvp[0];
    float4 m1 = mvp[1];
    float4 m3 = mvp[3];

    float2 n = normalize(wn);
    float s = dot(m3.xy, pos) + m3.w;
    float t_val = dot(m3.xy, n);

    float u_val = (s * dot(m0.xy, n) - t_val * (dot(m0.xy, pos) + m0.w)) * viewport.x;
    float v_val = (s * dot(m1.xy, n) - t_val * (dot(m1.xy, pos) + m1.w)) * viewport.y;

    float s2 = s * s;
    float st = s * t_val;
    float uv = u_val * u_val + v_val * v_val;
    float denom = uv - st * st;

    float2 d;
    if (abs(denom) > 1e-10) {
        d = n * (s2 * (st + sqrt(uv)) / denom);
    } else {
        d = n * 2.0 / viewport;
    }
    d *= snailVertexDilationScale(subpixel_order);

    float2 p = pos + d;
    r.texcoord = float2(em.x + dot(d, jac.xy), em.y + dot(d, jac.zw));

    r.position = mul(mvp, float4(p, 0.0, 1.0));
    return r;
}
