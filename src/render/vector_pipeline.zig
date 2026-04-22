const std = @import("std");
const gl = @import("gl.zig").gl;
const text_pipeline = @import("pipeline.zig");
const vector_vertex = @import("vector_vertex.zig");
const Mat4 = @import("../math/vec.zig").Mat4;

var program: gl.GLuint = 0;
var vao: gl.GLuint = 0;
var vbo: gl.GLuint = 0;
var u_mvp: gl.GLint = -1;
var u_fill_rule: gl.GLint = -1;
var u_subpixel_order: gl.GLint = -1;

const vertex_shader =
    \\#version 330 core
    \\
    \\layout(location = 0) in vec4 a_rect;
    \\layout(location = 1) in vec4 a_fill;
    \\layout(location = 2) in vec4 a_border;
    \\layout(location = 3) in vec4 a_params;
    \\layout(location = 4) in vec4 a_tx0;
    \\layout(location = 5) in vec4 a_tx1;
    \\
    \\uniform mat4 u_mvp;
    \\
    \\out vec2 v_local_px;
    \\flat out vec4 v_rect;
    \\flat out vec4 v_fill;
    \\flat out vec4 v_border;
    \\flat out vec3 v_shape;
    \\
    \\const vec2 kLocal[6] = vec2[6](
    \\    vec2(0.0, 0.0),
    \\    vec2(1.0, 0.0),
    \\    vec2(1.0, 1.0),
    \\    vec2(0.0, 0.0),
    \\    vec2(1.0, 1.0),
    \\    vec2(0.0, 1.0)
    \\);
    \\
    \\void main() {
    \\    vec2 a_local = kLocal[gl_VertexID];
    \\    float expand = a_params.w;
    \\    vec2 expanded_size = a_rect.zw + vec2(expand * 2.0);
    \\    vec2 local_px = -vec2(expand) + a_local * expanded_size;
    \\    vec2 local = a_rect.xy + local_px;
    \\    vec2 world = vec2(
    \\        dot(a_tx0.xyz, vec3(local, 1.0)),
    \\        dot(a_tx1.xyz, vec3(local, 1.0))
    \\    );
    \\    gl_Position = u_mvp * vec4(world, 0.0, 1.0);
    \\
    \\    v_local_px = local_px;
    \\    v_rect = a_rect;
    \\    v_fill = a_fill;
    \\    v_border = a_border;
    \\    v_shape = a_params.xyz;
    \\}
;

const fragment_shader =
    \\#version 330 core
    \\
    \\in vec2 v_local_px;
    \\flat in vec4 v_rect;
    \\flat in vec4 v_fill;
    \\flat in vec4 v_border;
    \\flat in vec3 v_shape;
    \\
    \\uniform int u_fill_rule;
    \\uniform int u_subpixel_order;
    \\
    \\out vec4 frag_color;
    \\
    \\const int PATH_KIND_RECT = 0;
    \\const int PATH_KIND_ROUNDED_RECT = 1;
    \\const int PATH_KIND_ELLIPSE = 2;
    \\const int RECT_CURVE_COUNT = 4;
    \\const int ARC_SEGMENTS_PER_CORNER = 4;
    \\const int ROUNDED_RECT_CURVE_COUNT = 4 + ARC_SEGMENTS_PER_CORNER * 4;
    \\const int ELLIPSE_SEGMENT_COUNT = 16;
    \\const int MAX_PATH_CURVES = ROUNDED_RECT_CURVE_COUNT;
    \\const float PI = 3.14159265358979323846;
    \\const float HALF_PI = 1.57079632679489661923;
    \\
    \\uint calcRootCode(float y1, float y2, float y3) {
    \\    uint i1 = floatBitsToUint(y1) >> 31u;
    \\    uint i2 = floatBitsToUint(y2) >> 30u;
    \\    uint i3 = floatBitsToUint(y3) >> 29u;
    \\    uint shift = (i2 & 2u) | (i1 & ~2u);
    \\    shift = (i3 & 4u) | (shift & ~4u);
    \\    return ((0x2E74u >> shift) & 0x0101u);
    \\}
    \\
    \\float applyFillRule(float winding) {
    \\    if (u_fill_rule == 1) {
    \\        return 1.0 - abs(fract(winding * 0.5) * 2.0 - 1.0);
    \\    }
    \\    return abs(winding);
    \\}
    \\
    \\vec2 solveHorizPoly(vec4 p12, vec2 p3) {
    \\    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    \\    vec2 b = p12.xy - p12.zw;
    \\    float ra = 1.0 / a.y;
    \\    float rb = 0.5 / b.y;
    \\    float d = sqrt(max(b.y * b.y - a.y * p12.y, 0.0));
    \\    float t1 = (b.y - d) * ra;
    \\    float t2 = (b.y + d) * ra;
    \\    if (abs(a.y) < 1.0 / 65536.0) { t1 = p12.y * rb; t2 = t1; }
    \\    return vec2((a.x * t1 - b.x * 2.0) * t1 + p12.x,
    \\               (a.x * t2 - b.x * 2.0) * t2 + p12.x);
    \\}
    \\
    \\vec2 solveVertPoly(vec4 p12, vec2 p3) {
    \\    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    \\    vec2 b = p12.xy - p12.zw;
    \\    float ra = 1.0 / a.x;
    \\    float rb = 0.5 / b.x;
    \\    float d = sqrt(max(b.x * b.x - a.x * p12.x, 0.0));
    \\    float t1 = (b.x - d) * ra;
    \\    float t2 = (b.x + d) * ra;
    \\    if (abs(a.x) < 1.0 / 65536.0) { t1 = p12.x * rb; t2 = t1; }
    \\    return vec2((a.y * t1 - b.y * 2.0) * t1 + p12.y,
    \\               (a.y * t2 - b.y * 2.0) * t2 + p12.y);
    \\}
    \\
    \\void makeLine(vec2 p0, vec2 p1, out vec4 p12, out vec2 p3) {
    \\    p12 = vec4(p0, mix(p0, p1, 0.5));
    \\    p3 = p1;
    \\}
    \\
    \\void makeArc(vec2 center, vec2 radii, float start_angle, float end_angle, out vec4 p12, out vec2 p3) {
    \\    float mid_angle = (start_angle + end_angle) * 0.5;
    \\    float control_scale = 1.0 / cos((end_angle - start_angle) * 0.5);
    \\    vec2 p0 = center + radii * vec2(cos(start_angle), sin(start_angle));
    \\    vec2 p1 = center + radii * (vec2(cos(mid_angle), sin(mid_angle)) * control_scale);
    \\    vec2 p2 = center + radii * vec2(cos(end_angle), sin(end_angle));
    \\    p12 = vec4(p0, p1);
    \\    p3 = p2;
    \\}
    \\
    \\int curveCountForPath(int kind, float radius) {
    \\    if (kind == PATH_KIND_ELLIPSE) return ELLIPSE_SEGMENT_COUNT;
    \\    if (kind == PATH_KIND_ROUNDED_RECT && radius > 1.0 / 65536.0) return ROUNDED_RECT_CURVE_COUNT;
    \\    return RECT_CURVE_COUNT;
    \\}
    \\
    \\void getRectCurve(vec2 origin, vec2 size, int segment, out vec4 p12, out vec2 p3) {
    \\    vec2 p0 = origin;
    \\    vec2 p1 = origin + vec2(size.x, 0.0);
    \\    vec2 p2 = origin + size;
    \\    vec2 p3p = origin + vec2(0.0, size.y);
    \\    if (segment == 0) makeLine(p0, p1, p12, p3);
    \\    else if (segment == 1) makeLine(p1, p2, p12, p3);
    \\    else if (segment == 2) makeLine(p2, p3p, p12, p3);
    \\    else makeLine(p3p, p0, p12, p3);
    \\}
    \\
    \\void getRoundedRectCurve(vec2 origin, vec2 size, float radius, int segment, out vec4 p12, out vec2 p3) {
    \\    if (radius <= 1.0 / 65536.0) {
    \\        getRectCurve(origin, size, segment, p12, p3);
    \\        return;
    \\    }
    \\
    \\    float step = HALF_PI / float(ARC_SEGMENTS_PER_CORNER);
    \\    vec2 arc = vec2(radius);
    \\    vec2 top_left = origin + vec2(radius, radius);
    \\    vec2 top_right = origin + vec2(size.x - radius, radius);
    \\    vec2 bottom_right = origin + size - vec2(radius, radius);
    \\    vec2 bottom_left = origin + vec2(radius, size.y - radius);
    \\
    \\    if (segment == 0) {
    \\        makeLine(origin + vec2(radius, 0.0), origin + vec2(size.x - radius, 0.0), p12, p3);
    \\        return;
    \\    }
    \\    segment -= 1;
    \\    if (segment < ARC_SEGMENTS_PER_CORNER) {
    \\        float start_angle = -HALF_PI + float(segment) * step;
    \\        makeArc(top_right, arc, start_angle, start_angle + step, p12, p3);
    \\        return;
    \\    }
    \\    segment -= ARC_SEGMENTS_PER_CORNER;
    \\    if (segment == 0) {
    \\        makeLine(origin + vec2(size.x, radius), origin + vec2(size.x, size.y - radius), p12, p3);
    \\        return;
    \\    }
    \\    segment -= 1;
    \\    if (segment < ARC_SEGMENTS_PER_CORNER) {
    \\        float start_angle = float(segment) * step;
    \\        makeArc(bottom_right, arc, start_angle, start_angle + step, p12, p3);
    \\        return;
    \\    }
    \\    segment -= ARC_SEGMENTS_PER_CORNER;
    \\    if (segment == 0) {
    \\        makeLine(origin + vec2(size.x - radius, size.y), origin + vec2(radius, size.y), p12, p3);
    \\        return;
    \\    }
    \\    segment -= 1;
    \\    if (segment < ARC_SEGMENTS_PER_CORNER) {
    \\        float start_angle = HALF_PI + float(segment) * step;
    \\        makeArc(bottom_left, arc, start_angle, start_angle + step, p12, p3);
    \\        return;
    \\    }
    \\    segment -= ARC_SEGMENTS_PER_CORNER;
    \\    if (segment == 0) {
    \\        makeLine(origin + vec2(0.0, size.y - radius), origin + vec2(0.0, radius), p12, p3);
    \\        return;
    \\    }
    \\    segment -= 1;
    \\    float start_angle = PI + float(segment) * step;
    \\    makeArc(top_left, arc, start_angle, start_angle + step, p12, p3);
    \\}
    \\
    \\void getEllipseCurve(vec2 origin, vec2 size, int segment, out vec4 p12, out vec2 p3) {
    \\    float step = (2.0 * PI) / float(ELLIPSE_SEGMENT_COUNT);
    \\    float start_angle = -HALF_PI + float(segment) * step;
    \\    makeArc(origin + size * 0.5, size * 0.5, start_angle, start_angle + step, p12, p3);
    \\}
    \\
    \\void getPathCurve(int kind, vec2 origin, vec2 size, float radius, int segment, out vec4 p12, out vec2 p3) {
    \\    if (kind == PATH_KIND_ELLIPSE) getEllipseCurve(origin, size, segment, p12, p3);
    \\    else if (kind == PATH_KIND_ROUNDED_RECT) getRoundedRectCurve(origin, size, radius, segment, p12, p3);
    \\    else getRectCurve(origin, size, segment, p12, p3);
    \\}
    \\
    \\vec2 evalHorizCoverage(vec2 rc, float x_offset, vec2 ppe, int kind, vec2 origin, vec2 size, float radius) {
    \\    float xcov = 0.0;
    \\    float xwgt = 0.0;
    \\    vec2 sample_rc = rc + vec2(x_offset, 0.0);
    \\    int curve_count = curveCountForPath(kind, radius);
    \\    for (int i = 0; i < MAX_PATH_CURVES; i++) {
    \\        if (i >= curve_count) break;
    \\        vec4 p12;
    \\        vec2 p3p;
    \\        getPathCurve(kind, origin, size, radius, i, p12, p3p);
    \\        p12 -= vec4(sample_rc, sample_rc);
    \\        p3p -= sample_rc;
    \\        uint code = calcRootCode(p12.y, p12.w, p3p.y);
    \\        if (code != 0u) {
    \\            vec2 r = solveHorizPoly(p12, p3p) * ppe.x;
    \\            if ((code & 1u) != 0u) {
    \\                xcov += clamp(r.x + 0.5, 0.0, 1.0);
    \\                xwgt = max(xwgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0));
    \\            }
    \\            if (code > 1u) {
    \\                xcov -= clamp(r.y + 0.5, 0.0, 1.0);
    \\                xwgt = max(xwgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0));
    \\            }
    \\        }
    \\    }
    \\    return vec2(xcov, xwgt);
    \\}
    \\
    \\vec2 evalVertCoverage(vec2 rc, float y_offset, vec2 ppe, int kind, vec2 origin, vec2 size, float radius) {
    \\    float ycov = 0.0;
    \\    float ywgt = 0.0;
    \\    vec2 sample_rc = rc + vec2(0.0, y_offset);
    \\    int curve_count = curveCountForPath(kind, radius);
    \\    for (int i = 0; i < MAX_PATH_CURVES; i++) {
    \\        if (i >= curve_count) break;
    \\        vec4 p12;
    \\        vec2 p3p;
    \\        getPathCurve(kind, origin, size, radius, i, p12, p3p);
    \\        p12 -= vec4(sample_rc, sample_rc);
    \\        p3p -= sample_rc;
    \\        uint code = calcRootCode(p12.x, p12.z, p3p.x);
    \\        if (code != 0u) {
    \\            vec2 r = solveVertPoly(p12, p3p) * ppe.y;
    \\            if ((code & 1u) != 0u) {
    \\                ycov -= clamp(r.x + 0.5, 0.0, 1.0);
    \\                ywgt = max(ywgt, clamp(1.0 - abs(r.x) * 2.0, 0.0, 1.0));
    \\            }
    \\            if (code > 1u) {
    \\                ycov += clamp(r.y + 0.5, 0.0, 1.0);
    \\                ywgt = max(ywgt, clamp(1.0 - abs(r.y) * 2.0, 0.0, 1.0));
    \\            }
    \\        }
    \\    }
    \\    return vec2(ycov, ywgt);
    \\}
    \\
    \\float evalPathCoverage(vec2 rc, vec2 ppe, int kind, vec2 origin, vec2 size, float radius) {
    \\    float xcov = 0.0;
    \\    float xwgt = 0.0;
    \\    float ycov = 0.0;
    \\    float ywgt = 0.0;
    \\    int curve_count = curveCountForPath(kind, radius);
    \\    for (int i = 0; i < MAX_PATH_CURVES; i++) {
    \\        if (i >= curve_count) break;
    \\        vec4 p12;
    \\        vec2 p3p;
    \\        getPathCurve(kind, origin, size, radius, i, p12, p3p);
    \\        p12 -= vec4(rc, rc);
    \\        p3p -= rc;
    \\
    \\        uint hcode = calcRootCode(p12.y, p12.w, p3p.y);
    \\        if (hcode != 0u) {
    \\            vec2 hr = solveHorizPoly(p12, p3p) * ppe.x;
    \\            if ((hcode & 1u) != 0u) {
    \\                xcov += clamp(hr.x + 0.5, 0.0, 1.0);
    \\                xwgt = max(xwgt, clamp(1.0 - abs(hr.x) * 2.0, 0.0, 1.0));
    \\            }
    \\            if (hcode > 1u) {
    \\                xcov -= clamp(hr.y + 0.5, 0.0, 1.0);
    \\                xwgt = max(xwgt, clamp(1.0 - abs(hr.y) * 2.0, 0.0, 1.0));
    \\            }
    \\        }
    \\
    \\        uint vcode = calcRootCode(p12.x, p12.z, p3p.x);
    \\        if (vcode != 0u) {
    \\            vec2 vr = solveVertPoly(p12, p3p) * ppe.y;
    \\            if ((vcode & 1u) != 0u) {
    \\                ycov -= clamp(vr.x + 0.5, 0.0, 1.0);
    \\                ywgt = max(ywgt, clamp(1.0 - abs(vr.x) * 2.0, 0.0, 1.0));
    \\            }
    \\            if (vcode > 1u) {
    \\                ycov += clamp(vr.y + 0.5, 0.0, 1.0);
    \\                ywgt = max(ywgt, clamp(1.0 - abs(vr.y) * 2.0, 0.0, 1.0));
    \\            }
    \\        }
    \\    }
    \\
    \\    float wsum = xwgt + ywgt;
    \\    float blended = xcov * xwgt + ycov * ywgt;
    \\    float cov = max(
    \\        applyFillRule(blended / max(wsum, 1.0 / 65536.0)),
    \\        min(applyFillRule(xcov), applyFillRule(ycov))
    \\    );
    \\    return clamp(cov, 0.0, 1.0);
    \\}
    \\
    \\vec3 blendSubpixel(vec2 cw_r, vec2 cw_g, vec2 cw_b, vec2 cw_o) {
    \\    float wsum_r = cw_r.y + cw_o.y;
    \\    float wsum_g = cw_g.y + cw_o.y;
    \\    float wsum_b = cw_b.y + cw_o.y;
    \\    float blend_r = cw_r.x * cw_r.y + cw_o.x * cw_o.y;
    \\    float blend_g = cw_g.x * cw_g.y + cw_o.x * cw_o.y;
    \\    float blend_b = cw_b.x * cw_b.y + cw_o.x * cw_o.y;
    \\    return vec3(
    \\        clamp(max(applyFillRule(blend_r / max(wsum_r, 1.0 / 65536.0)), min(applyFillRule(cw_r.x), applyFillRule(cw_o.x))), 0.0, 1.0),
    \\        clamp(max(applyFillRule(blend_g / max(wsum_g, 1.0 / 65536.0)), min(applyFillRule(cw_g.x), applyFillRule(cw_o.x))), 0.0, 1.0),
    \\        clamp(max(applyFillRule(blend_b / max(wsum_b, 1.0 / 65536.0)), min(applyFillRule(cw_b.x), applyFillRule(cw_o.x))), 0.0, 1.0)
    \\    );
    \\}
    \\
    \\vec4 premultiplyColor(vec4 color, float cov) {
    \\    float alpha = color.a * cov;
    \\    return vec4(color.rgb * alpha, alpha);
    \\}
    \\
    \\vec4 premultiplyColorSubpixel(vec4 color, vec3 cov) {
    \\    vec3 alpha = vec3(color.a) * cov;
    \\    return vec4(color.rgb * alpha, color.a * max(max(cov.r, cov.g), cov.b));
    \\}
    \\
    \\vec3 evalPathCoverageSubpixel(vec2 rc, vec2 epp, vec2 ppe, int kind, vec2 origin, vec2 size, float radius) {
    \\    if (u_subpixel_order <= 2) {
    \\        float sp = epp.x / 3.0;
    \\        float s = (u_subpixel_order == 2) ? -1.0 : 1.0;
    \\        vec2 cw_r = evalHorizCoverage(rc, -sp * s, ppe, kind, origin, size, radius);
    \\        vec2 cw_g = evalHorizCoverage(rc,  0.0,    ppe, kind, origin, size, radius);
    \\        vec2 cw_b = evalHorizCoverage(rc, +sp * s, ppe, kind, origin, size, radius);
    \\        vec2 cw_v = evalVertCoverage(rc, 0.0, ppe, kind, origin, size, radius);
    \\        return blendSubpixel(cw_r, cw_g, cw_b, cw_v);
    \\    }
    \\
    \\    float sp = epp.y / 3.0;
    \\    float s = (u_subpixel_order == 4) ? -1.0 : 1.0;
    \\    vec2 cw_h = evalHorizCoverage(rc, 0.0, ppe, kind, origin, size, radius);
    \\    vec2 cw_r = evalVertCoverage(rc, -sp * s, ppe, kind, origin, size, radius);
    \\    vec2 cw_g = evalVertCoverage(rc,  0.0,    ppe, kind, origin, size, radius);
    \\    vec2 cw_b = evalVertCoverage(rc, +sp * s, ppe, kind, origin, size, radius);
    \\    return blendSubpixel(cw_r, cw_g, cw_b, cw_h);
    \\}
    \\
    \\void main() {
    \\    vec2 size = max(v_rect.zw, vec2(0.0));
    \\    if (size.x <= 0.0 || size.y <= 0.0) discard;
    \\
    \\    int kind = int(v_shape.x + 0.5);
    \\    float max_radius = min(size.x, size.y) * 0.5;
    \\    float radius = clamp(v_shape.y, 0.0, max_radius);
    \\    float border_width = clamp(v_shape.z, 0.0, max_radius);
    \\    vec2 rc = v_local_px;
    \\    vec2 epp = max(fwidth(rc), vec2(1.0 / 65536.0));
    \\    vec2 ppe = 1.0 / epp;
    \\    vec2 origin = vec2(0.0);
    \\    vec2 inner_origin = vec2(border_width);
    \\    vec2 inner_size = max(size - vec2(border_width * 2.0), vec2(0.0));
    \\    float inner_max_radius = min(inner_size.x, inner_size.y) * 0.5;
    \\    float inner_radius = (kind == PATH_KIND_ROUNDED_RECT)
    \\        ? clamp(radius - border_width, 0.0, inner_max_radius)
    \\        : 0.0;
    \\    bool has_inner = border_width > 0.0 && inner_size.x > 1.0 / 65536.0 && inner_size.y > 1.0 / 65536.0;
    \\
    \\    if (kind == PATH_KIND_RECT) radius = 0.0;
    \\
    \\    if (u_subpixel_order == 0) {
    \\        float outer_cov = evalPathCoverage(rc, ppe, kind, origin, size, radius);
    \\        float inner_cov = has_inner ? evalPathCoverage(rc, ppe, kind, inner_origin, inner_size, inner_radius) : 0.0;
    \\        float fill_cov = (border_width > 0.0) ? (has_inner ? inner_cov : 0.0) : outer_cov;
    \\        float border_cov = (border_width > 0.0) ? (has_inner ? max(outer_cov - inner_cov, 0.0) : outer_cov) : 0.0;
    \\        frag_color = premultiplyColor(v_border, border_cov) + premultiplyColor(v_fill, fill_cov);
    \\    } else {
    \\        vec3 outer_cov = evalPathCoverageSubpixel(rc, epp, ppe, kind, origin, size, radius);
    \\        vec3 inner_cov = has_inner ? evalPathCoverageSubpixel(rc, epp, ppe, kind, inner_origin, inner_size, inner_radius) : vec3(0.0);
    \\        vec3 fill_cov = (border_width > 0.0) ? (has_inner ? inner_cov : vec3(0.0)) : outer_cov;
    \\        vec3 border_cov = (border_width > 0.0) ? (has_inner ? max(outer_cov - inner_cov, vec3(0.0)) : outer_cov) : vec3(0.0);
    \\        frag_color = premultiplyColorSubpixel(v_border, border_cov) + premultiplyColorSubpixel(v_fill, fill_cov);
    \\    }
    \\    if (frag_color.a < 1.0 / 255.0) discard;
    \\}
;

pub fn init() !void {
    program = try linkProgram(vertex_shader, fragment_shader);
    u_mvp = gl.glGetUniformLocation(program, "u_mvp");
    u_fill_rule = gl.glGetUniformLocation(program, "u_fill_rule");
    u_subpixel_order = gl.glGetUniformLocation(program, "u_subpixel_order");

    gl.glGenVertexArrays(1, &vao);
    gl.glGenBuffers(1, &vbo);
    gl.glBindVertexArray(vao);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);

    const stride: gl.GLsizei = vector_vertex.FLOATS_PER_VERTEX * @sizeOf(f32);
    gl.glVertexAttribPointer(0, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(0));
    gl.glEnableVertexAttribArray(0);
    gl.glVertexAttribPointer(1, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(4 * @sizeOf(f32)));
    gl.glEnableVertexAttribArray(1);
    gl.glVertexAttribPointer(2, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(8 * @sizeOf(f32)));
    gl.glEnableVertexAttribArray(2);
    gl.glVertexAttribPointer(3, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(12 * @sizeOf(f32)));
    gl.glEnableVertexAttribArray(3);
    gl.glVertexAttribPointer(4, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(16 * @sizeOf(f32)));
    gl.glEnableVertexAttribArray(4);
    gl.glVertexAttribPointer(5, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(20 * @sizeOf(f32)));
    gl.glEnableVertexAttribArray(5);
    gl.glVertexAttribDivisor(0, 1);
    gl.glVertexAttribDivisor(1, 1);
    gl.glVertexAttribDivisor(2, 1);
    gl.glVertexAttribDivisor(3, 1);
    gl.glVertexAttribDivisor(4, 1);
    gl.glVertexAttribDivisor(5, 1);
    gl.glBindVertexArray(0);
}

pub fn deinit() void {
    if (program != 0) gl.glDeleteProgram(program);
    if (vao != 0) gl.glDeleteVertexArrays(1, &vao);
    if (vbo != 0) gl.glDeleteBuffers(1, &vbo);
    program = 0;
    vao = 0;
    vbo = 0;
    u_mvp = -1;
    u_fill_rule = -1;
    u_subpixel_order = -1;
}

pub fn resetFrameState() void {}

pub fn drawPrimitives(vertices: []const f32, mvp: Mat4) void {
    if (vertices.len == 0) return;
    const primitive_count = vertices.len / vector_vertex.FLOATS_PER_PRIMITIVE;
    if (primitive_count == 0) return;

    gl.glBindVertexArray(vao);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);
    gl.glBufferData(
        gl.GL_ARRAY_BUFFER,
        @intCast(vertices.len * @sizeOf(f32)),
        @ptrCast(vertices.ptr),
        gl.GL_STREAM_DRAW,
    );

    gl.glDisable(gl.GL_DEPTH_TEST);
    gl.glEnable(gl.GL_BLEND);
    gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
    gl.glUseProgram(program);
    gl.glUniformMatrix4fv(u_mvp, 1, gl.GL_FALSE, &mvp.data);
    gl.glUniform1i(u_fill_rule, @intFromEnum(text_pipeline.fill_rule));
    gl.glUniform1i(u_subpixel_order, @intFromEnum(text_pipeline.subpixel_order));
    gl.glDrawArraysInstanced(gl.GL_TRIANGLES, 0, 6, @intCast(primitive_count));
}

fn compileShader(shader_type: gl.GLenum, source: [*c]const u8) ?gl.GLuint {
    const shader = gl.glCreateShader(shader_type);
    gl.glShaderSource(shader, 1, &source, null);
    gl.glCompileShader(shader);

    var ok: gl.GLint = 0;
    gl.glGetShaderiv(shader, gl.GL_COMPILE_STATUS, &ok);
    if (ok == 0) {
        var buf: [4096]u8 = undefined;
        var len: gl.GLsizei = 0;
        gl.glGetShaderInfoLog(shader, 4096, &len, &buf);
        if (len > 0) std.debug.print("Vector shader compile error:\n{s}\n", .{buf[0..@intCast(len)]});
        gl.glDeleteShader(shader);
        return null;
    }
    return shader;
}

fn linkProgram(vs_src: [*c]const u8, fs_src: [*c]const u8) !gl.GLuint {
    const vs = compileShader(gl.GL_VERTEX_SHADER, vs_src) orelse return error.VertexShaderFailed;
    defer gl.glDeleteShader(vs);
    const fs = compileShader(gl.GL_FRAGMENT_SHADER, fs_src) orelse return error.FragmentShaderFailed;
    defer gl.glDeleteShader(fs);

    const prog = gl.glCreateProgram();
    gl.glAttachShader(prog, vs);
    gl.glAttachShader(prog, fs);
    gl.glLinkProgram(prog);

    var ok: gl.GLint = 0;
    gl.glGetProgramiv(prog, gl.GL_LINK_STATUS, &ok);
    if (ok == 0) {
        var buf: [4096]u8 = undefined;
        var len: gl.GLsizei = 0;
        gl.glGetProgramInfoLog(prog, 4096, &len, &buf);
        if (len > 0) std.debug.print("Vector shader link error:\n{s}\n", .{buf[0..@intCast(len)]});
        return error.ShaderLinkFailed;
    }
    return prog;
}
