#version 450

layout(location = 0) in vec2 v_local_px;
layout(location = 1) flat in vec4 v_rect;
layout(location = 2) flat in vec4 v_fill;
layout(location = 3) flat in vec4 v_border;
layout(location = 4) flat in vec3 v_shape;

layout(push_constant) uniform PushConstants {
    mat4 mvp;
    vec2 viewport;
    int fill_rule;
    int subpixel_order;
} pc;

layout(location = 0) out vec4 frag_color;

float sdRoundRect(vec2 p, vec2 half_size, float radius) {
    vec2 q = abs(p) - half_size + vec2(radius);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

float sdEllipse(vec2 p, vec2 half_size) {
    vec2 safe_half = max(half_size, vec2(1e-4));
    return (length(p / safe_half) - 1.0) * min(safe_half.x, safe_half.y);
}

vec4 sampleShape(vec2 local_px, vec2 half_size, int kind, float radius, float border_width, float aa) {
    vec2 p = local_px - half_size;
    float outer_dist = (kind == 2)
        ? sdEllipse(p, half_size)
        : sdRoundRect(p, half_size, radius);
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
    return v_border * border_alpha + v_fill * inner_alpha;
}

void main() {
    vec2 half_size = v_rect.zw * 0.5;
    int kind = int(v_shape.x + 0.5);
    float radius = min(max(v_shape.y, 0.0), min(half_size.x, half_size.y));
    float border_width = min(max(v_shape.z, 0.0), min(half_size.x, half_size.y));
    vec2 p = v_local_px - half_size;

    if (kind == 0) radius = 0.0;
    float center_dist = (kind == 2)
        ? sdEllipse(p, half_size)
        : sdRoundRect(p, half_size, radius);
    float aa = max(fwidth(center_dist), 0.5);

    if (pc.subpixel_order == 0) {
        frag_color = sampleShape(v_local_px, half_size, kind, radius, border_width, aa);
    } else {
        vec2 sample_axis = (pc.subpixel_order <= 2) ? dFdx(v_local_px) : dFdy(v_local_px);
        float s = (pc.subpixel_order == 2 || pc.subpixel_order == 4) ? -1.0 : 1.0;
        vec2 offset = sample_axis * (s / 3.0);
        vec4 sub_r = sampleShape(v_local_px - offset, half_size, kind, radius, border_width, aa);
        vec4 sub_g = sampleShape(v_local_px, half_size, kind, radius, border_width, aa);
        vec4 sub_b = sampleShape(v_local_px + offset, half_size, kind, radius, border_width, aa);
        frag_color = vec4(sub_r.r, sub_g.g, sub_b.b, max(sub_r.a, max(sub_g.a, sub_b.a)));
    }
    if (frag_color.a < 1.0 / 255.0) discard;
}
