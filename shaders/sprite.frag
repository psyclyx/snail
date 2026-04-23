#version 450

layout(location = 0) in vec2 v_uv;
layout(location = 1) in vec4 v_color;
layout(location = 2) flat in ivec2 v_image;

layout(set = 0, binding = 3) uniform sampler2DArray u_image_tex;

layout(location = 0) out vec4 frag_color;

vec4 sampleSprite(vec2 uv, int layer, int filterMode) {
    if (filterMode == 1) {
        ivec3 size = textureSize(u_image_tex, 0);
        ivec2 texel = clamp(ivec2(uv * vec2(size.xy)), ivec2(0), size.xy - ivec2(1));
        return texelFetch(u_image_tex, ivec3(texel, layer), 0);
    }
    return texture(u_image_tex, vec3(uv, float(layer)));
}

void main() {
    vec4 color = sampleSprite(v_uv, v_image.x, v_image.y) * v_color;
    float alpha = color.a;
    if (alpha < 1.0 / 255.0) discard;
    frag_color = vec4(color.rgb * alpha, alpha);
}
