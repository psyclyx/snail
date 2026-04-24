const std = @import("std");
const gl = @import("gl.zig").gl;
const gl_backend = @import("gl_backend.zig");
const sprite_vertex = @import("sprite_vertex.zig");
const text_pipeline = @import("pipeline.zig");
const Mat4 = @import("../math/vec.zig").Mat4;

const Backend = gl_backend.Backend;

var program: gl.GLuint = 0;
var vao: gl.GLuint = 0;
var vbo: gl.GLuint = 0;
var ebo: gl.GLuint = 0;
var u_mvp: gl.GLint = -1;
var u_image_tex: gl.GLint = -1;
var backend: Backend = .gl33;

const RING_SEGMENTS = 3;
const RING_TOTAL_BYTES = 12 * 1024 * 1024;
const RING_SEGMENT_BYTES = RING_TOTAL_BYTES / RING_SEGMENTS;
const BYTES_PER_SPRITE = sprite_vertex.FLOATS_PER_SPRITE * @sizeOf(f32);
const MAX_SPRITES_PER_SEGMENT: usize = @max(1, RING_SEGMENT_BYTES / BYTES_PER_SPRITE);

var persistent_map: ?[*]u8 = null;
var ring_fences: [RING_SEGMENTS]gl.GLsync = .{null} ** RING_SEGMENTS;
var ring_segment: u32 = 0;

const vertex_shader =
    \\#version 330 core
    \\
    \\layout(location = 0) in vec4 a_pos_uv;
    \\layout(location = 1) in vec4 a_col;
    \\layout(location = 2) in vec4 a_params;
    \\
    \\uniform mat4 u_mvp;
    \\
    \\out vec2 v_uv;
    \\out vec4 v_color;
    \\flat out ivec2 v_image;
    \\
    \\void main() {
    \\    v_uv = a_pos_uv.zw;
    \\    v_color = a_col;
    \\    v_image = ivec2(int(a_params.x + 0.5), int(a_params.y + 0.5));
    \\    gl_Position = u_mvp * vec4(a_pos_uv.xy, 0.0, 1.0);
    \\}
;

const fragment_shader =
    \\#version 330 core
    \\
    \\in vec2 v_uv;
    \\in vec4 v_color;
    \\flat in ivec2 v_image;
    \\
    \\uniform sampler2DArray u_image_tex;
    \\
    \\out vec4 frag_color;
    \\
    \\vec4 sampleSprite(vec2 uv, int layer, int filter_mode) {
    \\    if (filter_mode == 1) {
    \\        ivec3 size = textureSize(u_image_tex, 0);
    \\        ivec2 texel = clamp(ivec2(uv * vec2(size.xy)), ivec2(0), size.xy - ivec2(1));
    \\        return texelFetch(u_image_tex, ivec3(texel, layer), 0);
    \\    }
    \\    return texture(u_image_tex, vec3(uv, float(layer)));
    \\}
    \\
    \\void main() {
    \\    vec4 color = sampleSprite(v_uv, v_image.x, v_image.y) * v_color;
    \\    float alpha = color.a;
    \\    if (alpha < 1.0 / 255.0) discard;
    \\    frag_color = vec4(color.rgb * alpha, alpha);
    \\}
;

pub fn init() !void {
    program = try linkProgram("sprite", vertex_shader, fragment_shader);
    u_mvp = gl.glGetUniformLocation(program, "u_mvp");
    u_image_tex = gl.glGetUniformLocation(program, "u_image_tex");

    backend = gl_backend.detect(gl);
    switch (backend) {
        .gl33 => initGl33(),
        .gl44 => initGl44(),
    }
}

fn initGl33() void {
    gl.glGenVertexArrays(1, &vao);
    gl.glGenBuffers(1, &vbo);
    gl.glGenBuffers(1, &ebo);
    gl.glBindVertexArray(vao);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);
    gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, ebo);
    initEbo();
    setupVertexAttribs();
}

fn initGl44() void {
    gl.glCreateVertexArrays(1, &vao);
    gl.glCreateBuffers(1, &vbo);
    gl.glCreateBuffers(1, &ebo);

    const flags: gl.GLbitfield = gl.GL_MAP_WRITE_BIT | gl.GL_MAP_PERSISTENT_BIT | gl.GL_MAP_COHERENT_BIT;
    gl.glNamedBufferStorage(vbo, RING_TOTAL_BYTES, null, flags);
    persistent_map = @ptrCast(gl.glMapNamedBufferRange(vbo, 0, RING_TOTAL_BYTES, flags));

    if (persistent_map == null) {
        gl.glDeleteVertexArrays(1, &vao);
        gl.glDeleteBuffers(1, &vbo);
        gl.glDeleteBuffers(1, &ebo);
        backend = .gl33;
        initGl33();
        return;
    }

    const stride: gl.GLint = sprite_vertex.FLOATS_PER_VERTEX * @sizeOf(f32);
    gl.glVertexArrayVertexBuffer(vao, 0, vbo, 0, stride);
    gl.glVertexArrayElementBuffer(vao, ebo);

    inline for (0..3) |i| {
        const loc: u32 = @intCast(i);
        gl.glEnableVertexArrayAttrib(vao, loc);
        gl.glVertexArrayAttribFormat(vao, loc, 4, gl.GL_FLOAT, gl.GL_FALSE, @intCast(i * 4 * @sizeOf(f32)));
        gl.glVertexArrayAttribBinding(vao, loc, 0);
    }

    gl.glBindVertexArray(vao);
    gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, ebo);
    initEbo();
}

pub fn deinit() void {
    if (backend == .gl44) {
        for (&ring_fences) |*fence_slot| {
            if (fence_slot.*) |fence| {
                gl.glDeleteSync(fence);
                fence_slot.* = null;
            }
        }
        if (persistent_map != null) {
            _ = gl.glUnmapNamedBuffer(vbo);
            persistent_map = null;
        }
    }

    if (program != 0) gl.glDeleteProgram(program);
    if (vao != 0) gl.glDeleteVertexArrays(1, &vao);
    if (vbo != 0) gl.glDeleteBuffers(1, &vbo);
    if (ebo != 0) gl.glDeleteBuffers(1, &ebo);
    program = 0;
    vao = 0;
    vbo = 0;
    ebo = 0;
    u_mvp = -1;
    u_image_tex = -1;
}

pub fn resetFrameState() void {}

pub fn drawSprites(vertices: []const f32, mvp: Mat4) void {
    if (vertices.len == 0) return;
    const image_tex = text_pipeline.imageTextureArray();
    if (image_tex == 0) return;

    const sprite_count = vertices.len / sprite_vertex.FLOATS_PER_SPRITE;
    if (sprite_count == 0) return;

    gl.glDisable(gl.GL_DEPTH_TEST);
    gl.glEnable(gl.GL_BLEND);
    gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
    gl.glUseProgram(program);
    gl.glUniformMatrix4fv(u_mvp, 1, gl.GL_FALSE, &mvp.data);
    gl.glUniform1i(u_image_tex, 0);

    gl.glBindVertexArray(vao);
    if (backend == .gl44) {
        gl.glBindTextureUnit(0, image_tex);
    } else {
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, image_tex);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);
    }

    var sprites_drawn: usize = 0;
    while (sprites_drawn < sprite_count) {
        const chunk: usize = @min(sprite_count - sprites_drawn, MAX_SPRITES_PER_SEGMENT);
        const float_offset = sprites_drawn * sprite_vertex.FLOATS_PER_SPRITE;
        const byte_size = chunk * BYTES_PER_SPRITE;

        if (backend == .gl44) {
            const segment = @as(usize, ring_segment);
            if (ring_fences[segment]) |fence| {
                const status = gl.glClientWaitSync(fence, 0, 0);
                if (status != gl.GL_ALREADY_SIGNALED and status != gl.GL_CONDITION_SATISFIED) {
                    _ = gl.glClientWaitSync(fence, gl.GL_SYNC_FLUSH_COMMANDS_BIT, 1_000_000_000);
                }
                gl.glDeleteSync(fence);
                ring_fences[segment] = null;
            }

            const offset = segment * RING_SEGMENT_BYTES;
            const dst = persistent_map.?[offset..][0..byte_size];
            const src: [*]const u8 = @ptrCast(vertices[float_offset..].ptr);
            @memcpy(dst, src[0..byte_size]);

            const stride: gl.GLint = sprite_vertex.FLOATS_PER_VERTEX * @sizeOf(f32);
            gl.glVertexArrayVertexBuffer(vao, 0, vbo, @intCast(offset), stride);
            gl.glDrawElements(gl.GL_TRIANGLES, @intCast(chunk * 6), gl.GL_UNSIGNED_INT, null);
            ring_fences[segment] = gl.glFenceSync(gl.GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
            ring_segment = (ring_segment + 1) % RING_SEGMENTS;
        } else {
            gl.glBufferData(
                gl.GL_ARRAY_BUFFER,
                @intCast(byte_size),
                @ptrCast(vertices[float_offset..].ptr),
                gl.GL_STREAM_DRAW,
            );
            gl.glDrawElements(gl.GL_TRIANGLES, @intCast(chunk * 6), gl.GL_UNSIGNED_INT, null);
        }

        sprites_drawn += chunk;
    }
}

fn setupVertexAttribs() void {
    const stride: gl.GLsizei = sprite_vertex.FLOATS_PER_VERTEX * @sizeOf(f32);
    inline for (0..3) |i| {
        gl.glVertexAttribPointer(@intCast(i), 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(i * 4 * @sizeOf(f32)));
        gl.glEnableVertexAttribArray(@intCast(i));
    }
}

fn initEbo() void {
    const total_indices: usize = MAX_SPRITES_PER_SEGMENT * 6;
    const buf_size: gl.GLsizeiptr = @intCast(total_indices * @sizeOf(u32));
    gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, buf_size, null, gl.GL_STATIC_DRAW);

    const ptr = gl.glMapBufferRange(gl.GL_ELEMENT_ARRAY_BUFFER, 0, buf_size, gl.GL_MAP_WRITE_BIT);
    if (ptr) |raw| {
        const indices: [*]u32 = @ptrCast(@alignCast(raw));
        for (0..MAX_SPRITES_PER_SEGMENT) |i| {
            const base: u32 = @intCast(i * 4);
            const idx = i * 6;
            indices[idx + 0] = base + 0;
            indices[idx + 1] = base + 1;
            indices[idx + 2] = base + 2;
            indices[idx + 3] = base + 0;
            indices[idx + 4] = base + 2;
            indices[idx + 5] = base + 3;
        }
        _ = gl.glUnmapBuffer(gl.GL_ELEMENT_ARRAY_BUFFER);
    }
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
        if (len > 0) std.debug.print("Sprite shader compile error:\n{s}\n", .{buf[0..@intCast(len)]});
        gl.glDeleteShader(shader);
        return null;
    }
    return shader;
}

fn linkProgram(_: []const u8, vs_src: [*c]const u8, fs_src: [*c]const u8) !gl.GLuint {
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
        if (len > 0) std.debug.print("Sprite shader link error:\n{s}\n", .{buf[0..@intCast(len)]});
        return error.ShaderLinkFailed;
    }
    return prog;
}
