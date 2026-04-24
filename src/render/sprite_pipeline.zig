const std = @import("std");
const gl = @import("gl.zig").gl;
const gl_backend = @import("gl_backend.zig");
const sprite_vertex = @import("sprite_vertex.zig");
const Mat4 = @import("../math/vec.zig").Mat4;

const Backend = gl_backend.Backend;

const RING_SEGMENTS = 3;
const RING_TOTAL_BYTES = 12 * 1024 * 1024;
const RING_SEGMENT_BYTES = RING_TOTAL_BYTES / RING_SEGMENTS;
const BYTES_PER_SPRITE = sprite_vertex.FLOATS_PER_SPRITE * @sizeOf(f32);
const MAX_SPRITES_PER_SEGMENT: usize = @max(1, RING_SEGMENT_BYTES / BYTES_PER_SPRITE);

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

pub const GlSpriteState = struct {
    program: gl.GLuint = 0,
    vao: gl.GLuint = 0,
    vbo: gl.GLuint = 0,
    ebo: gl.GLuint = 0,
    u_mvp: gl.GLint = -1,
    u_image_tex: gl.GLint = -1,
    backend: Backend = .gl33,
    persistent_map: ?[*]u8 = null,
    ring_fences: [RING_SEGMENTS]gl.GLsync = .{null} ** RING_SEGMENTS,
    ring_segment: u32 = 0,

    pub fn init(self: *GlSpriteState) !void {
        self.program = try linkProgram("sprite", vertex_shader, fragment_shader);
        self.u_mvp = gl.glGetUniformLocation(self.program, "u_mvp");
        self.u_image_tex = gl.glGetUniformLocation(self.program, "u_image_tex");

        self.backend = gl_backend.detect(gl);
        switch (self.backend) {
            .gl33 => self.initGl33(),
            .gl44 => self.initGl44(),
        }
    }

    pub fn deinit(self: *GlSpriteState) void {
        if (self.backend == .gl44) {
            for (&self.ring_fences) |*fence_slot| {
                if (fence_slot.*) |fence| {
                    gl.glDeleteSync(fence);
                    fence_slot.* = null;
                }
            }
            if (self.persistent_map != null) {
                _ = gl.glUnmapNamedBuffer(self.vbo);
                self.persistent_map = null;
            }
        }

        if (self.program != 0) gl.glDeleteProgram(self.program);
        if (self.vao != 0) gl.glDeleteVertexArrays(1, &self.vao);
        if (self.vbo != 0) gl.glDeleteBuffers(1, &self.vbo);
        if (self.ebo != 0) gl.glDeleteBuffers(1, &self.ebo);
        self.program = 0;
        self.vao = 0;
        self.vbo = 0;
        self.ebo = 0;
        self.u_mvp = -1;
        self.u_image_tex = -1;
    }

    pub fn resetFrameState(self: *GlSpriteState) void {
        _ = self;
    }

    pub fn drawSprites(self: *GlSpriteState, vertices: []const f32, mvp: Mat4, image_tex: gl.GLuint) void {
        if (vertices.len == 0) return;
        if (image_tex == 0) return;

        const sprite_count = vertices.len / sprite_vertex.FLOATS_PER_SPRITE;
        if (sprite_count == 0) return;

        gl.glDisable(gl.GL_DEPTH_TEST);
        gl.glEnable(gl.GL_BLEND);
        gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
        gl.glUseProgram(self.program);
        gl.glUniformMatrix4fv(self.u_mvp, 1, gl.GL_FALSE, &mvp.data);
        gl.glUniform1i(self.u_image_tex, 0);

        gl.glBindVertexArray(self.vao);
        if (self.backend == .gl44) {
            gl.glBindTextureUnit(0, image_tex);
        } else {
            gl.glActiveTexture(gl.GL_TEXTURE0);
            gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, image_tex);
            gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
        }

        var sprites_drawn: usize = 0;
        while (sprites_drawn < sprite_count) {
            const chunk: usize = @min(sprite_count - sprites_drawn, MAX_SPRITES_PER_SEGMENT);
            const float_offset = sprites_drawn * sprite_vertex.FLOATS_PER_SPRITE;
            const byte_size = chunk * BYTES_PER_SPRITE;

            if (self.backend == .gl44) {
                const segment = @as(usize, self.ring_segment);
                if (self.ring_fences[segment]) |fence| {
                    const status = gl.glClientWaitSync(fence, 0, 0);
                    if (status != gl.GL_ALREADY_SIGNALED and status != gl.GL_CONDITION_SATISFIED) {
                        _ = gl.glClientWaitSync(fence, gl.GL_SYNC_FLUSH_COMMANDS_BIT, 1_000_000_000);
                    }
                    gl.glDeleteSync(fence);
                    self.ring_fences[segment] = null;
                }

                const offset = segment * RING_SEGMENT_BYTES;
                const dst = self.persistent_map.?[offset..][0..byte_size];
                const src: [*]const u8 = @ptrCast(vertices[float_offset..].ptr);
                @memcpy(dst, src[0..byte_size]);

                const stride: gl.GLint = sprite_vertex.FLOATS_PER_VERTEX * @sizeOf(f32);
                gl.glVertexArrayVertexBuffer(self.vao, 0, self.vbo, @intCast(offset), stride);
                gl.glDrawElements(gl.GL_TRIANGLES, @intCast(chunk * 6), gl.GL_UNSIGNED_INT, null);
                self.ring_fences[segment] = gl.glFenceSync(gl.GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
                self.ring_segment = (self.ring_segment + 1) % RING_SEGMENTS;
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

    fn initGl33(self: *GlSpriteState) void {
        gl.glGenVertexArrays(1, &self.vao);
        gl.glGenBuffers(1, &self.vbo);
        gl.glGenBuffers(1, &self.ebo);
        gl.glBindVertexArray(self.vao);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ebo);
        initEbo();
        setupVertexAttribs();
    }

    fn initGl44(self: *GlSpriteState) void {
        gl.glCreateVertexArrays(1, &self.vao);
        gl.glCreateBuffers(1, &self.vbo);
        gl.glCreateBuffers(1, &self.ebo);

        const flags: gl.GLbitfield = gl.GL_MAP_WRITE_BIT | gl.GL_MAP_PERSISTENT_BIT | gl.GL_MAP_COHERENT_BIT;
        gl.glNamedBufferStorage(self.vbo, RING_TOTAL_BYTES, null, flags);
        self.persistent_map = @ptrCast(gl.glMapNamedBufferRange(self.vbo, 0, RING_TOTAL_BYTES, flags));

        if (self.persistent_map == null) {
            gl.glDeleteVertexArrays(1, &self.vao);
            gl.glDeleteBuffers(1, &self.vbo);
            gl.glDeleteBuffers(1, &self.ebo);
            self.backend = .gl33;
            self.initGl33();
            return;
        }

        const stride: gl.GLint = sprite_vertex.FLOATS_PER_VERTEX * @sizeOf(f32);
        gl.glVertexArrayVertexBuffer(self.vao, 0, self.vbo, 0, stride);
        gl.glVertexArrayElementBuffer(self.vao, self.ebo);

        inline for (0..3) |i| {
            const loc: u32 = @intCast(i);
            gl.glEnableVertexArrayAttrib(self.vao, loc);
            gl.glVertexArrayAttribFormat(self.vao, loc, 4, gl.GL_FLOAT, gl.GL_FALSE, @intCast(i * 4 * @sizeOf(f32)));
            gl.glVertexArrayAttribBinding(self.vao, loc, 0);
        }

        gl.glBindVertexArray(self.vao);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ebo);
        initEbo();
    }
};

// --- Module-level forwarding ---

pub var state: GlSpriteState = .{};

pub fn init() !void {
    return state.init();
}

pub fn deinit() void {
    state.deinit();
}

pub fn resetFrameState() void {
    state.resetFrameState();
}

pub fn drawSprites(vertices: []const f32, mvp: Mat4) void {
    const text_pipeline = @import("pipeline.zig");
    state.drawSprites(vertices, mvp, text_pipeline.imageTextureArray());
}

// --- Pure helper functions (no state access) ---

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
