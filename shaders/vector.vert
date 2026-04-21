#version 450

layout(location = 0) in vec4 a_rect;
layout(location = 1) in vec4 a_fill;
layout(location = 2) in vec4 a_border;
layout(location = 3) in vec4 a_params;
layout(location = 4) in vec4 a_tx0;
layout(location = 5) in vec4 a_tx1;

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    vec2 viewport;
    int fill_rule;
    int subpixel_order;
} pc;

layout(location = 0) out vec2 v_local_px;
layout(location = 1) flat out vec4 v_rect;
layout(location = 2) flat out vec4 v_fill;
layout(location = 3) flat out vec4 v_border;
layout(location = 4) flat out vec3 v_shape;

const vec2 kLocal[6] = vec2[6](
    vec2(0.0, 0.0),
    vec2(1.0, 0.0),
    vec2(1.0, 1.0),
    vec2(0.0, 0.0),
    vec2(1.0, 1.0),
    vec2(0.0, 1.0)
);

void main() {
    vec2 a_local = kLocal[gl_VertexIndex];
    float expand = a_params.w;
    vec2 expanded_size = a_rect.zw + vec2(expand * 2.0);
    vec2 local_px = -vec2(expand) + a_local * expanded_size;
    vec2 local = a_rect.xy + local_px;
    vec2 world = vec2(
        dot(a_tx0.xyz, vec3(local, 1.0)),
        dot(a_tx1.xyz, vec3(local, 1.0))
    );
    gl_Position = pc.mvp * vec4(world, 0.0, 1.0);

    v_local_px = local_px;
    v_rect = a_rect;
    v_fill = a_fill;
    v_border = a_border;
    v_shape = a_params.xyz;
}
