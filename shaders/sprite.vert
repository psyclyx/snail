#version 450

layout(location = 0) in vec4 a_pos_uv;
layout(location = 1) in vec4 a_col;
layout(location = 2) in vec4 a_params;

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    vec2 viewport;
    int fill_rule;
    int subpixel_order;
};

layout(location = 0) out vec2 v_uv;
layout(location = 1) out vec4 v_color;
layout(location = 2) flat out ivec2 v_image;

void main() {
    v_uv = a_pos_uv.zw;
    v_color = a_col;
    v_image = ivec2(int(a_params.x + 0.5), int(a_params.y + 0.5));
    gl_Position = mvp * vec4(a_pos_uv.xy, 0.0, 1.0);
}
