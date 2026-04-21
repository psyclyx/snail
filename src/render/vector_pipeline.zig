const std = @import("std");
const gl = @import("gl.zig").gl;
const SubpixelOrder = @import("subpixel_order.zig").SubpixelOrder;
const vector_vertex = @import("vector_vertex.zig");
const Mat4 = @import("../math/vec.zig").Mat4;

var program: gl.GLuint = 0;
var vao: gl.GLuint = 0;
var vbo: gl.GLuint = 0;
var u_mvp: gl.GLint = -1;
var u_subpixel_order: gl.GLint = -1;

pub var subpixel_order: SubpixelOrder = .none;

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
    \\uniform int u_subpixel_order;
    \\
    \\out vec4 frag_color;
    \\
    \\float sdRoundRect(vec2 p, vec2 half_size, float radius) {
    \\    vec2 q = abs(p) - half_size + vec2(radius);
    \\    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    \\}
    \\
    \\float sdEllipse(vec2 p, vec2 half_size) {
    \\    vec2 safe_half = max(half_size, vec2(1e-4));
    \\    return (length(p / safe_half) - 1.0) * min(safe_half.x, safe_half.y);
    \\}
    \\
    \\vec4 sampleShape(vec2 local_px, vec2 half_size, int kind, float radius, float border_width, float aa) {
    \\    vec2 p = local_px - half_size;
    \\    float outer_dist = (kind == 2)
    \\        ? sdEllipse(p, half_size)
    \\        : sdRoundRect(p, half_size, radius);
    \\    float outer_alpha = 1.0 - smoothstep(0.0, aa, outer_dist);
    \\
    \\    float inner_alpha = outer_alpha;
    \\    if (border_width > 0.0) {
    \\        vec2 inner_half = max(half_size - vec2(border_width), vec2(0.0));
    \\        float inner_radius = min(max(radius - border_width, 0.0), min(inner_half.x, inner_half.y));
    \\        float inner_dist = (kind == 2)
    \\            ? sdEllipse(p, inner_half)
    \\            : sdRoundRect(p, inner_half, inner_radius);
    \\        inner_alpha = 1.0 - smoothstep(0.0, aa, inner_dist);
    \\    }
    \\
    \\    float border_alpha = max(outer_alpha - inner_alpha, 0.0);
    \\    return v_border * border_alpha + v_fill * inner_alpha;
    \\}
    \\
    \\void main() {
    \\    vec2 half_size = v_rect.zw * 0.5;
    \\    int kind = int(v_shape.x + 0.5);
    \\    float radius = min(max(v_shape.y, 0.0), min(half_size.x, half_size.y));
    \\    float border_width = min(max(v_shape.z, 0.0), min(half_size.x, half_size.y));
    \\    vec2 p = v_local_px - half_size;
    \\
    \\    if (kind == 0) radius = 0.0;
    \\    float center_dist = (kind == 2)
    \\        ? sdEllipse(p, half_size)
    \\        : sdRoundRect(p, half_size, radius);
    \\    float aa = max(fwidth(center_dist), 0.5);
    \\
    \\    if (u_subpixel_order == 0) {
    \\        frag_color = sampleShape(v_local_px, half_size, kind, radius, border_width, aa);
    \\    } else {
    \\        vec2 sample_axis = (u_subpixel_order <= 2) ? dFdx(v_local_px) : dFdy(v_local_px);
    \\        float s = (u_subpixel_order == 2 || u_subpixel_order == 4) ? -1.0 : 1.0;
    \\        vec2 offset = sample_axis * (s / 3.0);
    \\        vec4 sub_r = sampleShape(v_local_px - offset, half_size, kind, radius, border_width, aa);
    \\        vec4 sub_g = sampleShape(v_local_px, half_size, kind, radius, border_width, aa);
    \\        vec4 sub_b = sampleShape(v_local_px + offset, half_size, kind, radius, border_width, aa);
    \\        frag_color = vec4(sub_r.r, sub_g.g, sub_b.b, max(sub_r.a, max(sub_g.a, sub_b.a)));
    \\    }
    \\    if (frag_color.a < 1.0 / 255.0) discard;
    \\}
;

pub fn init() !void {
    program = try linkProgram(vertex_shader, fragment_shader);
    u_mvp = gl.glGetUniformLocation(program, "u_mvp");
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
    u_subpixel_order = -1;
    subpixel_order = .none;
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
    gl.glUniform1i(u_subpixel_order, @intFromEnum(subpixel_order));
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
