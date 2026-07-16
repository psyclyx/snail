const vec2 kCorners[4] = vec2[4](
    vec2(0.0, 0.0),
    vec2(1.0, 0.0),
    vec2(1.0, 1.0),
    vec2(0.0, 1.0)
);

float snailVertexDilationScale() {
    const float kCornerAxisScale = 1.41421356237;
    const float kLcdAxisSupportScale = 7.0 / 3.0;
    return kCornerAxisScale * ((SNAIL_SUBPIXEL_ORDER == 0) ? 1.0 : kLcdAxisSupportScale);
}

void snailVertex() {
    vec2 t = kCorners[SNAIL_VERTEX_INDEX];

    vec2 em = mix(a_rect.xy, a_rect.zw, t);

    // Outward corner normal in local space (dilation direction).
    vec2 nd = t * 2.0 - 1.0;

    vec4 eff_xform = a_xform;
    vec2 eff_origin = a_origin;
    vec4 eff_tint = a_tint;

    vec2 pos = vec2(
        eff_xform.x * em.x + eff_xform.y * em.y + eff_origin.x,
        eff_xform.z * em.x + eff_xform.w * em.y + eff_origin.y
    );

    vec2 wn = vec2(
        eff_xform.x * nd.x + eff_xform.y * nd.y,
        eff_xform.z * nd.x + eff_xform.w * nd.y
    );

    float det = eff_xform.x * eff_xform.w - eff_xform.y * eff_xform.z;
    float inv_det = 1.0 / det;
    vec4 jac = vec4(
        eff_xform.w * inv_det,
        -eff_xform.y * inv_det,
        -eff_xform.z * inv_det,
        eff_xform.x * inv_det
    );

    uint gz = a_glyph.x;
    uint gw = a_glyph.y;
    v_glyph = ivec4(gz & 0xFFFFu, gz >> 16u, gw & 0xFFFFu, gw >> 16u);
    v_policy0 = a_policy0;
    v_policy1 = a_policy1;
    v_banding = a_bnd;
    // sRGB decode the per-instance color and tint at the vertex stage:
    // these are constant across all four corners of the glyph quad
    // (text uses one color per instance), so per-vertex conversion is
    // 4 invocations vs the ~100+ fragments per glyph that previously
    // each ran 6 `pow` calls. Fragment shaders now use `v_color` /
    // `v_tint` as already-linear values.
    v_color = vec4(srgbToLinear(a_col.rgb), a_col.a);
    v_tint = vec4(srgbToLinear(eff_tint.rgb), eff_tint.a);

    // Slug dynamic dilation
    vec4 m0 = vec4(SNAIL_MVP[0].x, SNAIL_MVP[1].x, SNAIL_MVP[2].x, SNAIL_MVP[3].x);
    vec4 m1 = vec4(SNAIL_MVP[0].y, SNAIL_MVP[1].y, SNAIL_MVP[2].y, SNAIL_MVP[3].y);
    vec4 m3 = vec4(SNAIL_MVP[0].w, SNAIL_MVP[1].w, SNAIL_MVP[2].w, SNAIL_MVP[3].w);

    vec2 n = normalize(wn);
    float s = dot(m3.xy, pos) + m3.w;
    float t_val = dot(m3.xy, n);

    float u_val = (s * dot(m0.xy, n) - t_val * (dot(m0.xy, pos) + m0.w)) * SNAIL_VIEWPORT.x;
    float v_val = (s * dot(m1.xy, n) - t_val * (dot(m1.xy, pos) + m1.w)) * SNAIL_VIEWPORT.y;

    float s2 = s * s;
    float st = s * t_val;
    float uv = u_val * u_val + v_val * v_val;
    float denom = uv - st * st;

    vec2 d;
    if (abs(denom) > 1e-10) {
        d = n * (s2 * (st + sqrt(uv)) / denom);
    } else {
        d = n * 2.0 / SNAIL_VIEWPORT;
    }
    d *= snailVertexDilationScale();

    vec2 p = pos + d;
    v_texcoord = vec2(em.x + dot(d, jac.xy), em.y + dot(d, jac.zw));

    gl_Position = SNAIL_MVP * vec4(p, 0.0, 1.0);
}
