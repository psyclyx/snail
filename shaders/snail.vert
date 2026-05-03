#version 450

// Per-instance attributes (vertex input rate = per-instance)
layout(location = 0) in vec4 a_rect;   // bbox: min_x, min_y, max_x, max_y (em-space)
layout(location = 1) in vec4 a_xform;  // linear transform: xx, xy, yx, yy
layout(location = 2) in vec4 a_meta;   // tx, ty, gz (packed), gw (packed)
layout(location = 3) in vec4 a_bnd;    // band scale x, scale y, offset x, offset y
layout(location = 4) in vec4 a_col;    // vertex color RGBA

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    vec2 viewport;
    int fill_rule;
    int subpixel_order;
};

layout(location = 0) out vec4 v_color;
layout(location = 1) out vec2 v_texcoord;
layout(location = 2) flat out vec4 v_banding;
layout(location = 3) flat out ivec4 v_glyph;

const vec2 kCorners[4] = vec2[4](
    vec2(0.0, 0.0),
    vec2(1.0, 0.0),
    vec2(1.0, 1.0),
    vec2(0.0, 1.0)
);

void main() {
    vec2 t = kCorners[gl_VertexIndex];

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

    // Slug dynamic dilation
    vec4 m0 = vec4(mvp[0].x, mvp[1].x, mvp[2].x, mvp[3].x);
    vec4 m1 = vec4(mvp[0].y, mvp[1].y, mvp[2].y, mvp[3].y);
    vec4 m3 = vec4(mvp[0].w, mvp[1].w, mvp[2].w, mvp[3].w);

    vec2 n = normalize(wn);
    float s = dot(m3.xy, pos) + m3.w;
    float t_val = dot(m3.xy, n);

    float u_val = (s * dot(m0.xy, n) - t_val * (dot(m0.xy, pos) + m0.w)) * viewport.x;
    float v_val = (s * dot(m1.xy, n) - t_val * (dot(m1.xy, pos) + m1.w)) * viewport.y;

    float s2 = s * s;
    float st = s * t_val;
    float uv = u_val * u_val + v_val * v_val;
    float denom = uv - st * st;

    vec2 d;
    if (abs(denom) > 1e-10) {
        d = wn * (s2 * (st + sqrt(uv)) / denom);
    } else {
        d = n * 2.0 / viewport;
    }

    vec2 p = pos + d;
    v_texcoord = vec2(em.x + dot(d, jac.xy), em.y + dot(d, jac.zw));

    gl_Position = mvp * vec4(p, 0.0, 1.0);
}
