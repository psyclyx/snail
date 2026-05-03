const vec2 kCorners[4] = vec2[4](
    vec2(0.0, 0.0),
    vec2(1.0, 0.0),
    vec2(1.0, 1.0),
    vec2(0.0, 1.0)
);

void main() {
    vec2 t = kCorners[SNAIL_VERTEX_INDEX];

    // Em-space coordinates from bbox
    vec2 em = mix(a_rect.xy, a_rect.zw, t);

    // Outward corner normal in local space
    vec2 nd = t * 2.0 - 1.0;

    // Transform em-space to world-space
    vec2 pos = vec2(
        a_xform.x * em.x + a_xform.y * em.y + a_meta.x,
        a_xform.z * em.x + a_xform.w * em.y + a_meta.y
    );

    // Normal in world space (for dilation direction)
    vec2 wn = vec2(
        a_xform.x * nd.x + a_xform.y * nd.y,
        a_xform.z * nd.x + a_xform.w * nd.y
    );

    // Inverse Jacobian from transform
    float det = a_xform.x * a_xform.w - a_xform.y * a_xform.z;
    float inv_det = 1.0 / det;
    vec4 jac = vec4(
        a_xform.w * inv_det,
        -a_xform.y * inv_det,
        -a_xform.z * inv_det,
        a_xform.x * inv_det
    );

    uint gz = floatBitsToUint(a_meta.z);
    uint gw = floatBitsToUint(a_meta.w);
    v_glyph = ivec4(gz & 0xFFFFu, gz >> 16u, gw & 0xFFFFu, gw >> 16u);
    v_banding = a_bnd;
    v_color = a_col;
    v_hint_src = a_hint_src;
    v_hint_dst = a_hint_dst;
    v_hint_bounds = a_rect.xz;

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
        d = wn * (s2 * (st + sqrt(uv)) / denom);
    } else {
        d = n * 2.0 / SNAIL_VIEWPORT;
    }

    vec2 p = pos + d;
    v_texcoord = vec2(em.x + dot(d, jac.xy), em.y + dot(d, jac.zw));

    gl_Position = SNAIL_MVP * vec4(p, 0.0, 1.0);
}
