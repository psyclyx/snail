#version 450

layout(location = 0) in vec4 a_pos;    // xy = position, zw = normal
layout(location = 1) in vec4 a_tex;    // xy = em-space coords, zw = packed glyph/band data
layout(location = 2) in vec4 a_jac;    // inverse Jacobian (j00, j01, j10, j11)
layout(location = 3) in vec4 a_bnd;    // band scale x, scale y, offset x, offset y
layout(location = 4) in vec4 a_col;    // vertex color RGBA

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    vec2 viewport;
    int fill_rule;
};

layout(location = 0) out vec4 v_color;
layout(location = 1) out vec2 v_texcoord;
layout(location = 2) flat out vec4 v_banding;
layout(location = 3) flat out ivec4 v_glyph;

void main() {
    uint gz = floatBitsToUint(a_tex.z);
    uint gw = floatBitsToUint(a_tex.w);
    v_glyph = ivec4(gz & 0xFFFFu, gz >> 16u, gw & 0xFFFFu, gw >> 16u);
    v_banding = a_bnd;
    v_color = a_col;

    // Slug dynamic dilation: expand quad by ~0.5px along normal.
    vec4 m0 = vec4(mvp[0].x, mvp[1].x, mvp[2].x, mvp[3].x);
    vec4 m1 = vec4(mvp[0].y, mvp[1].y, mvp[2].y, mvp[3].y);
    vec4 m3 = vec4(mvp[0].w, mvp[1].w, mvp[2].w, mvp[3].w);

    vec2 n = normalize(a_pos.zw);
    float s = dot(m3.xy, a_pos.xy) + m3.w;
    float t_val = dot(m3.xy, n);

    float u_val = (s * dot(m0.xy, n) - t_val * (dot(m0.xy, a_pos.xy) + m0.w)) * viewport.x;
    float v_val = (s * dot(m1.xy, n) - t_val * (dot(m1.xy, a_pos.xy) + m1.w)) * viewport.y;

    float s2 = s * s;
    float st = s * t_val;
    float uv = u_val * u_val + v_val * v_val;
    float denom = uv - st * st;

    vec2 d;
    if (abs(denom) > 1e-10) {
        d = a_pos.zw * (s2 * (st + sqrt(uv)) / denom);
    } else {
        d = n * 2.0 / viewport;
    }

    vec2 p = a_pos.xy + d;
    v_texcoord = vec2(a_tex.x + dot(d, a_jac.xy), a_tex.y + dot(d, a_jac.zw));

    gl_Position = mvp * vec4(p, 0.0, 1.0);
}
