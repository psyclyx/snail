#version 450

layout(location = 0) in vec2 v_local_px;
layout(location = 1) flat in vec4 v_rect;
layout(location = 2) flat in vec4 v_fill;
layout(location = 3) flat in vec4 v_border;
layout(location = 4) flat in vec3 v_shape;

layout(location = 0) out vec4 frag_color;

float sdRoundRect(vec2 p, vec2 half_size, float radius) {
    vec2 q = abs(p) - half_size + vec2(radius);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

float sdEllipse(vec2 p, vec2 half_size) {
    vec2 safe_half = max(half_size, vec2(1e-4));
    return (length(p / safe_half) - 1.0) * min(safe_half.x, safe_half.y);
}

void main() {
    vec2 half_size = v_rect.zw * 0.5;
    int kind = int(v_shape.x + 0.5);
    float radius = min(max(v_shape.y, 0.0), min(half_size.x, half_size.y));
    float border_width = min(max(v_shape.z, 0.0), min(half_size.x, half_size.y));
    vec2 p = v_local_px - half_size;

    if (kind == 0) radius = 0.0;
    float outer_dist = (kind == 2)
        ? sdEllipse(p, half_size)
        : sdRoundRect(p, half_size, radius);
    float aa = max(fwidth(outer_dist), 0.5);
    float outer_alpha = 1.0 - smoothstep(0.0, aa, outer_dist);

    float inner_alpha = outer_alpha;
    if (border_width > 0.0) {
        vec2 inner_half = max(half_size - vec2(border_width), vec2(0.0));
        float inner_radius = min(max(radius - border_width, 0.0), min(inner_half.x, inner_half.y));
        float inner_dist = (kind == 2)
            ? sdEllipse(p, inner_half)
            : sdRoundRect(p, inner_half, inner_radius);
        inner_alpha = 1.0 - smoothstep(0.0, aa, inner_dist);
    }

    float border_alpha = max(outer_alpha - inner_alpha, 0.0);
    vec4 fill = v_fill * inner_alpha;
    vec4 border = v_border * border_alpha;
    frag_color = border + fill;
    if (frag_color.a < 1.0 / 255.0) discard;
}
