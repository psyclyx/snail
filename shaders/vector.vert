#version 450

layout(location = 0) in vec2 a_local;
layout(location = 1) in vec4 a_rect;
layout(location = 2) in vec4 a_fill;
layout(location = 3) in vec4 a_border;
layout(location = 4) in vec4 a_params;

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

void main() {
    vec2 pixel = a_rect.xy + a_local * a_rect.zw;
    vec2 ndc = (pixel / pc.viewport) * 2.0 - 1.0;
    ndc.y = -ndc.y;
    gl_Position = vec4(ndc, 0.0, 1.0);

    v_local_px = a_local * a_rect.zw;
    v_rect = a_rect;
    v_fill = a_fill;
    v_border = a_border;
    v_shape = a_params.xyz;
}
