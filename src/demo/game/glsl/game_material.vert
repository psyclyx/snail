#version 450

layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec2 a_uv;

layout(push_constant) uniform PC {
    mat4 mvp;
    vec4 base_color;
    vec2 scene_size;
    int glyph_count;
    int output_srgb;
    float light;
} pc;

layout(location = 0) out vec2 v_uv;

void main() {
    v_uv = a_uv;
    gl_Position = pc.mvp * vec4(a_pos, 1.0);
}
