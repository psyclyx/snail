#version 300 es

layout(std140) uniform GameMaterialParams_std140
{
    layout(row_major) mat4 view_proj;
    layout(row_major) mat4 model;
    vec4 base_color;
    vec4 light_dir;
    vec2 scene_size;
    int glyph_count;
    int output_srgb;
    float relief;
    float roughness;
} pc;

layout(location = 1) in vec2 input_uv;
layout(location = 0) in vec3 input_pos;
out vec2 snail_io0;

highp mat4 spvWorkaroundRowMajor(highp mat4 wrap) { return wrap; }
mediump mat4 spvWorkaroundRowMajorMP(mediump mat4 wrap) { return wrap; }

void main()
{
    gl_Position = vec4(input_pos, 1.0) * (spvWorkaroundRowMajor(pc.model) * spvWorkaroundRowMajor(pc.view_proj));
    snail_io0 = input_uv;
}

