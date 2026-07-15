const std = @import("std");
const gl = @import("snail").gl.gles30_bindings.gl;
const gl_backend = @import("embed_gles30_detect.zig");
const gl_programs = @import("embed_gles30_programs.zig");
const gles30_upload = @import("embed_gl_cache.zig");
const gl_common = @import("embed_gl_common.zig");
const linear_resolve = @import("embed_gl_linear_resolve.zig");
const draw_records_mod = @import("snail").core.files.picture_draw_records;
const shaders = @import("snail").gl.gles30_shaders;
const subpixel_policy = @import("snail").core.files.backend_subpixel_policy;
const vertex = @import("snail").core.files.format_vertex;
const snail_mod = @import("snail").core;
const SubpixelOrder = @import("snail").core.files.format_subpixel_order.SubpixelOrder;
const LinearResolve = snail_mod.LinearResolve;
const DrawState = snail_mod.DrawState;
const TargetSurface = snail_mod.TargetSurface;

pub const LinearResolveRestore = gl_common.LinearResolveRestore;

const LinearResolveState = linear_resolve.StateFor(gl, .{
    .vertex_shader = linear_resolve_vertex_shader,
    .fragment_shader = linear_resolve_fragment_shader,
    .dst_format = .srgb8,
    .linkProgram = gl_programs.linkProgram,
});

// ── Backend selection ──

pub const Backend = gl_backend.Backend;

// ── Shared types ──

const ProgramState = gl_programs.ProgramState;
const deleteProgramState = gl_programs.deleteProgramState;
const loadProgramState = gl_programs.loadProgramState;

// ── GLES30 streaming constants ──

const STREAM_BYTES = 4 * 1024 * 1024;
const BYTES_PER_GLYPH = vertex.BYTES_PER_INSTANCE;
const MAX_GLYPHS_PER_UPLOAD = STREAM_BYTES / BYTES_PER_GLYPH;

// ── Gles30TextState ──

pub const Gles30TextState = struct {
    backend: Backend = .gles30,
    text_program: ProgramState = .{},
    colr_program: ProgramState = .{},
    path_program: ProgramState = .{},
    hinted_text_program: ProgramState = .{},
    autohint_program: ProgramState = .{},
    text_program_replicated: ProgramState = .{},
    colr_program_replicated: ProgramState = .{},
    path_program_replicated: ProgramState = .{},
    hinted_text_program_replicated: ProgramState = .{},
    autohint_program_replicated: ProgramState = .{},
    linear_resolve: LinearResolveState = .{},
    vao: gl.GLuint = 0,
    vbo: gl.GLuint = 0,
    ebo: gl.GLuint = 0,
    vao_replicated: gl.GLuint = 0,
    vbo_replicated: gl.GLuint = 0,
    replicated_shape_divisor: u32 = 0,
    active_program: gl.GLuint = 0,
    frame_begun: bool = false,

    // ── Init / Deinit ──

    pub fn init(self: *Gles30TextState) !void {
        self.backend = gl_backend.detect(gl);

        // Link all draw programs during renderer init so draw never compiles or links.
        self.text_program = try loadProgramState("text", shaders.vertex_shader, shaders.fragment_shader_text, false);
        self.colr_program = try loadProgramState("text-colr", shaders.vertex_shader, shaders.fragment_shader_colr, false);
        self.path_program = try loadProgramState("path", shaders.vertex_shader, shaders.fragment_shader_path, false);
        self.hinted_text_program = try loadProgramState("hinted-text", shaders.vertex_shader, shaders.fragment_shader_hinted_text, false);
        self.autohint_program = try loadProgramState("autohint", shaders.vertex_shader, shaders.fragment_shader_autohint, false);
        self.text_program_replicated = try loadProgramState("text-replicated", shaders.vertex_shader_replicated, shaders.fragment_shader_text, false);
        self.colr_program_replicated = try loadProgramState("text-colr-replicated", shaders.vertex_shader_replicated, shaders.fragment_shader_colr, false);
        self.path_program_replicated = try loadProgramState("path-replicated", shaders.vertex_shader_replicated, shaders.fragment_shader_path, false);
        self.hinted_text_program_replicated = try loadProgramState("hinted-text-replicated", shaders.vertex_shader_replicated, shaders.fragment_shader_hinted_text, false);
        self.autohint_program_replicated = try loadProgramState("autohint-replicated", shaders.vertex_shader_replicated, shaders.fragment_shader_autohint, false);
        try self.linear_resolve.init();

        self.initGles30();

        gl.glEnable(gl.GL_BLEND);
        // Shader outputs premultiplied alpha (frag_color = v_color * coverage),
        // so use GL_ONE for src to avoid double-multiplying coverage.
        gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);

        // OpenGL ES 3.0 has no GL_FRAMEBUFFER_SRGB toggle. sRGB framebuffer
        // conversion is controlled by the framebuffer attachment format.
    }

    fn initGles30(self: *Gles30TextState) void {
        gl.glGenVertexArrays(1, &self.vao);
        gl.glGenBuffers(1, &self.vbo);
        gl.glGenBuffers(1, &self.ebo);
        gl.glBindVertexArray(self.vao);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
        gl.glBufferData(gl.GL_ARRAY_BUFFER, STREAM_BYTES, null, gl.GL_STREAM_DRAW);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ebo);
        initEbo();
        setupVertexAttribs();
        setupInstanceDivisors();

        // Replicated VAO: shares the EBO, override divisor pre-set;
        // shape divisor + buffer offsets get updated per draw.
        gl.glGenVertexArrays(1, &self.vao_replicated);
        gl.glGenBuffers(1, &self.vbo_replicated);
        gl.glBindVertexArray(self.vao_replicated);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ebo);
        gl.glBindVertexArray(self.vao);
    }

    pub fn deinit(self: *Gles30TextState) void {
        deleteProgramState(&self.text_program);
        deleteProgramState(&self.colr_program);
        deleteProgramState(&self.path_program);
        deleteProgramState(&self.hinted_text_program);
        deleteProgramState(&self.autohint_program);
        deleteProgramState(&self.text_program_replicated);
        deleteProgramState(&self.colr_program_replicated);
        deleteProgramState(&self.path_program_replicated);
        deleteProgramState(&self.hinted_text_program_replicated);
        deleteProgramState(&self.autohint_program_replicated);
        if (self.vao_replicated != 0) gl.glDeleteVertexArrays(1, &self.vao_replicated);
        if (self.vbo_replicated != 0) gl.glDeleteBuffers(1, &self.vbo_replicated);
        self.linear_resolve.deinit();
        if (self.vao != 0) gl.glDeleteVertexArrays(1, &self.vao);
        if (self.vbo != 0) gl.glDeleteBuffers(1, &self.vbo);
        if (self.ebo != 0) gl.glDeleteBuffers(1, &self.ebo);
    }

    pub fn backendName(self: *const Gles30TextState) [:0]const u8 {
        _ = self;
        return "OpenGL ES 3.0";
    }

    pub fn beginLinearResolve(self: *Gles30TextState, surface: TargetSurface, resolve: LinearResolve) !LinearResolveRestore {
        return self.linear_resolve.begin(surface, resolve);
    }

    pub fn endLinearResolve(self: *Gles30TextState, restore: LinearResolveRestore) void {
        self.linear_resolve.end(restore);
        self.frame_begun = false;
    }

    // ── New-API draw entry ──

    pub const DrawError = error{
        MissingBinding,
        StaleBinding,
        MalformedSegment,
    } || std.mem.Allocator.Error;

    /// Walk `DrawRecords.segments`, bind each segment's matching
    /// `Gles30BackendCache` cache, dispatch the encoded instances
    /// through the existing program set. GLES3 has no dual-source
    /// blend, so subpixel runs fall back to grayscale.
    pub fn draw(
        self: *Gles30TextState,
        scratch: std.mem.Allocator,
        draw_state: DrawState,
        records: draw_records_mod.DrawRecords,
        caches: []const *const gles30_upload.Gles30BackendCache,
    ) DrawError!void {
        gl.glBindVertexArray(self.vao);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);

        for (records.segments) |seg| {
            const cache = findCache(caches, seg.binding.pool) orelse return error.MissingBinding;
            if (seg.binding.generation != 0 and cache.upload_generation < seg.binding.generation) return error.StaleBinding;
            const seg_words = records.words[seg.words_offset..][0..seg.words_len];
            switch (seg.kind) {
                .heterogeneous => try self.drawHeterogeneous(cache, draw_state, seg_words),
                .replicated => try self.drawReplicated(scratch, cache, draw_state, seg, seg_words),
            }
        }
    }

    fn drawHeterogeneous(self: *Gles30TextState, cache: *const gles30_upload.Gles30BackendCache, draw_state: DrawState, vertices: []const u32) DrawError!void {
        const total_glyphs = vertices.len / vertex.WORDS_PER_INSTANCE;
        if (total_glyphs == 0) return;

        // GLES3 has no dual-source blend → no LCD subpixel; force
        // grayscale for regular runs.
        const allow_subpixel = false;

        var run_start: usize = 0;
        while (run_start < total_glyphs) {
            const run_kind = subpixel_policy.glyphRunKind(vertices, run_start);
            const run_end = subpixel_policy.glyphRunEnd(vertices, run_start, run_kind);
            const run_mode: subpixel_policy.TextRenderMode = if (run_kind != .regular)
                .grayscale
            else
                subpixel_policy.chooseTextRenderModeRange(
                    vertices,
                    run_start,
                    run_end - run_start,
                    draw_state.mvp,
                    allow_subpixel,
                    draw_state.raster.subpixel_order,
                    false,
                );
            setTextBlendMode(run_kind != .regular, run_mode);
            const prog_state = switch (run_kind) {
                .regular => &self.text_program,
                .colr => self.ensureColrProgram(),
                .path => self.ensurePathProgram(),
                .hinted_text => self.ensureHintedTextProgram(),
                .autohint => self.ensureAutohintProgram(),
            };
            self.bindProgramState(cache, prog_state, draw_state, run_mode);
            self.drawGlyphRange(vertices, run_start, run_end - run_start);
            run_start = run_end;
        }
    }

    /// Real hardware GPU instancing for the GLES3 replicated path. See
    /// the GL state.zig counterpart for the design notes — one
    /// instanced draw per shape, M instances each, shape attrs
    /// at divisor M (constant within a draw) and overrides at divisor 1.
    fn drawReplicated(
        self: *Gles30TextState,
        _: std.mem.Allocator,
        cache: *const gles30_upload.Gles30BackendCache,
        draw_state: DrawState,
        seg: draw_records_mod.DrawSegment,
        seg_words: []const u32,
    ) DrawError!void {
        const n = seg.shape_count;
        const m = seg.override_count;
        if (n == 0 or m == 0) return;
        const WORDS_PER_OVERRIDE: usize = vertex.WORDS_PER_OVERRIDE;
        const expected = @as(usize, n) * vertex.WORDS_PER_INSTANCE + @as(usize, m) * WORDS_PER_OVERRIDE;
        if (seg_words.len != expected) return error.MalformedSegment;

        const shape_bytes: usize = @as(usize, n) * vertex.BYTES_PER_INSTANCE;
        const override_bytes: usize = @as(usize, m) * 32;
        const total_bytes: usize = shape_bytes + override_bytes;
        const src_ptr: [*]const u8 = @ptrCast(seg_words.ptr);

        gl.glBindVertexArray(self.vao_replicated);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo_replicated);
        gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(total_bytes), src_ptr, gl.GL_STREAM_DRAW);
        if (self.replicated_shape_divisor != m) {
            inline for (0..9) |i| gl.glVertexAttribDivisor(@intCast(i), m);
            inline for (9..12) |i| gl.glVertexAttribDivisor(@intCast(i), 1);
            self.replicated_shape_divisor = m;
        }

        const allow_subpixel = false; // GLES3 has no dual-source blend.
        const shape_words_view = seg_words[0 .. @as(usize, n) * vertex.WORDS_PER_INSTANCE];

        var run_start: usize = 0;
        while (run_start < n) {
            const run_kind = subpixel_policy.glyphRunKind(shape_words_view, run_start);
            const run_end_in_shapes = subpixel_policy.glyphRunEnd(shape_words_view, run_start, run_kind);
            const run_shape_count = run_end_in_shapes - run_start;
            const run_mode: subpixel_policy.TextRenderMode = if (run_kind != .regular)
                .grayscale
            else
                subpixel_policy.chooseTextRenderModeRange(
                    shape_words_view,
                    run_start,
                    run_shape_count,
                    draw_state.mvp,
                    allow_subpixel,
                    draw_state.raster.subpixel_order,
                    false,
                );
            setTextBlendMode(run_kind != .regular, run_mode);
            const prog_state = switch (run_kind) {
                .regular => &self.text_program_replicated,
                .colr => &self.colr_program_replicated,
                .path => &self.path_program_replicated,
                .hinted_text => &self.hinted_text_program_replicated,
                .autohint => &self.autohint_program_replicated,
            };
            self.bindProgramState(cache, prog_state, draw_state, run_mode);
            var s: usize = run_start;
            while (s < run_end_in_shapes) : (s += 1) {
                setupReplicatedVertexAttribsGles(s * vertex.BYTES_PER_INSTANCE, shape_bytes);
                gl.glDrawElementsInstanced(gl.GL_TRIANGLES, 6, gl.GL_UNSIGNED_INT, null, @intCast(m));
            }
            run_start = run_end_in_shapes;
        }

        gl.glBindVertexArray(self.vao);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
    }

    /// Configure attribute pointers on the currently-bound VAO + VBO
    /// for the replicated draw, with shape stream starting at
    /// `shape_base` and override stream at `override_base`.
    fn setupReplicatedVertexAttribsGles(shape_base: usize, override_base: usize) void {
        const shape_stride: gl.GLsizei = vertex.BYTES_PER_INSTANCE;
        const override_stride: gl.GLsizei = 32;
        gl.glVertexAttribPointer(0, 4, gl.GL_HALF_FLOAT, gl.GL_FALSE, shape_stride, @ptrFromInt(shape_base + @offsetOf(vertex.Instance, "rect")));
        gl.glEnableVertexAttribArray(0);
        gl.glVertexAttribPointer(1, 4, gl.GL_FLOAT, gl.GL_FALSE, shape_stride, @ptrFromInt(shape_base + @offsetOf(vertex.Instance, "xform")));
        gl.glEnableVertexAttribArray(1);
        gl.glVertexAttribPointer(2, 2, gl.GL_FLOAT, gl.GL_FALSE, shape_stride, @ptrFromInt(shape_base + @offsetOf(vertex.Instance, "origin")));
        gl.glEnableVertexAttribArray(2);
        gl.glVertexAttribIPointer(3, 2, gl.GL_UNSIGNED_INT, shape_stride, @ptrFromInt(shape_base + @offsetOf(vertex.Instance, "glyph")));
        gl.glEnableVertexAttribArray(3);
        gl.glVertexAttribPointer(4, 4, gl.GL_FLOAT, gl.GL_FALSE, shape_stride, @ptrFromInt(shape_base + @offsetOf(vertex.Instance, "band")));
        gl.glEnableVertexAttribArray(4);
        gl.glVertexAttribPointer(5, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, shape_stride, @ptrFromInt(shape_base + @offsetOf(vertex.Instance, "color")));
        gl.glEnableVertexAttribArray(5);
        gl.glVertexAttribPointer(6, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, shape_stride, @ptrFromInt(shape_base + @offsetOf(vertex.Instance, "tint")));
        gl.glEnableVertexAttribArray(6);
        gl.glVertexAttribIPointer(7, 4, gl.GL_UNSIGNED_INT, shape_stride, @ptrFromInt(shape_base + @offsetOf(vertex.Instance, "policy")));
        gl.glEnableVertexAttribArray(7);
        gl.glVertexAttribIPointer(8, 3, gl.GL_UNSIGNED_INT, shape_stride, @ptrFromInt(shape_base + @offsetOf(vertex.Instance, "policy") + 16));
        gl.glEnableVertexAttribArray(8);
        gl.glVertexAttribPointer(9, 4, gl.GL_FLOAT, gl.GL_FALSE, override_stride, @ptrFromInt(override_base + 0));
        gl.glEnableVertexAttribArray(9);
        gl.glVertexAttribPointer(10, 4, gl.GL_FLOAT, gl.GL_FALSE, override_stride, @ptrFromInt(override_base + 16));
        gl.glEnableVertexAttribArray(10);
        gl.glVertexAttribPointer(11, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, override_stride, @ptrFromInt(override_base + 24));
        gl.glEnableVertexAttribArray(11);
    }

    fn bindProgramState(self: *Gles30TextState, cache: *const gles30_upload.Gles30BackendCache, prog_state: *const ProgramState, draw_state: DrawState, render_mode: subpixel_policy.TextRenderMode) void {
        const program_changed = prog_state.handle != self.active_program or !self.frame_begun;
        if (program_changed) {
            gl.glUseProgram(prog_state.handle);
            self.active_program = prog_state.handle;
            self.frame_begun = true;
        }

        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, cache.curve_array);
        gl.glActiveTexture(gl.GL_TEXTURE1);
        gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, cache.band_array);
        if (prog_state.layer_tex_loc >= 0 and cache.layer_info_tex != 0) {
            gl.glActiveTexture(gl.GL_TEXTURE2);
            gl.glBindTexture(gl.GL_TEXTURE_2D, cache.layer_info_tex);
        }
        if (prog_state.image_tex_loc >= 0 and cache.image_array_tex != 0) {
            gl.glActiveTexture(gl.GL_TEXTURE3);
            gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, cache.image_array_tex);
        }
        // Sampler unit pinning + u_layer_base = 0 are baked at link
        // time by loadProgramState; no per-draw glUniform1i needed.

        gl.glUniformMatrix4fv(prog_state.mvp_loc, 1, gl.GL_FALSE, &draw_state.mvp.data);
        gl.glUniform2f(prog_state.viewport_loc, draw_state.surface.pixel_width, draw_state.surface.pixel_height);
        if (prog_state.subpixel_order_loc >= 0) {
            const order = if (render_mode == .grayscale) SubpixelOrder.none else draw_state.raster.subpixel_order;
            gl.glUniform1i(prog_state.subpixel_order_loc, @intFromEnum(order));
        }
        if (prog_state.output_srgb_loc >= 0) {
            const output_srgb = draw_state.surface.encoding.shaderEncodesSrgb() and !self.linear_resolve.active;
            gl.glUniform1i(prog_state.output_srgb_loc, @intFromBool(output_srgb));
        }
        if (prog_state.coverage_exponent_loc >= 0) {
            gl.glUniform1f(prog_state.coverage_exponent_loc, draw_state.raster.coverage_transfer.shaderExponent());
        }
        if (prog_state.dither_scale_loc >= 0) {
            gl.glUniform1f(prog_state.dither_scale_loc, draw_state.surface.format.ditherAmplitude());
        }
        if (prog_state.mask_output_loc >= 0) {
            gl.glUniform1i(prog_state.mask_output_loc, if (draw_state.surface.format.hasColor()) 0 else 1);
        }
    }

    pub fn beginDraw(self: *Gles30TextState) void {
        self.frame_begun = false;
    }

    fn ensureColrProgram(self: *Gles30TextState) *const ProgramState {
        std.debug.assert(self.colr_program.handle != 0);
        return &self.colr_program;
    }

    fn ensurePathProgram(self: *Gles30TextState) *const ProgramState {
        std.debug.assert(self.path_program.handle != 0);
        return &self.path_program;
    }

    fn ensureHintedTextProgram(self: *Gles30TextState) *const ProgramState {
        std.debug.assert(self.hinted_text_program.handle != 0);
        return &self.hinted_text_program;
    }

    fn ensureAutohintProgram(self: *Gles30TextState) *const ProgramState {
        std.debug.assert(self.autohint_program.handle != 0);
        return &self.autohint_program;
    }

    fn drawGlyphRange(self: *Gles30TextState, vertices: []const u32, glyph_offset: usize, glyph_count: usize) void {
        _ = self;
        var glyphs_drawn: usize = 0;
        while (glyphs_drawn < glyph_count) {
            const word_offset = (glyph_offset + glyphs_drawn) * vertex.WORDS_PER_INSTANCE;
            const chunk: usize = @min(glyph_count - glyphs_drawn, MAX_GLYPHS_PER_UPLOAD);
            const byte_size = chunk * BYTES_PER_GLYPH;

            gl.glBufferSubData(gl.GL_ARRAY_BUFFER, 0, @intCast(byte_size), @ptrCast(vertices[word_offset..].ptr));

            gl.glDrawElementsInstanced(gl.GL_TRIANGLES, 6, gl.GL_UNSIGNED_INT, null, @intCast(chunk));

            glyphs_drawn += chunk;
        }
    }
};

// ── Renderer wrapper ──

pub const Gles30Renderer = struct {
    state: Gles30TextState = .{},

    pub fn init(_: std.mem.Allocator) !Gles30Renderer {
        var self = Gles30Renderer{};
        try self.state.init();
        return self;
    }

    pub fn deinit(self: *Gles30Renderer) void {
        self.state.deinit();
    }
};

// ── Pure utility functions (no mutable state access) ──

fn setupVertexAttribs() void {
    const stride: gl.GLsizei = vertex.BYTES_PER_INSTANCE;
    setupVertexAttrib(0, 4, gl.GL_HALF_FLOAT, gl.GL_FALSE, stride, @offsetOf(vertex.Instance, "rect"));
    setupVertexAttrib(1, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @offsetOf(vertex.Instance, "xform"));
    setupVertexAttrib(2, 2, gl.GL_FLOAT, gl.GL_FALSE, stride, @offsetOf(vertex.Instance, "origin"));
    gl.glVertexAttribIPointer(3, 2, gl.GL_UNSIGNED_INT, stride, @ptrFromInt(@offsetOf(vertex.Instance, "glyph")));
    gl.glEnableVertexAttribArray(3);
    setupVertexAttrib(4, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @offsetOf(vertex.Instance, "band"));
    setupVertexAttrib(5, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, stride, @offsetOf(vertex.Instance, "color"));
    setupVertexAttrib(6, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, stride, @offsetOf(vertex.Instance, "tint"));
    gl.glVertexAttribIPointer(7, 4, gl.GL_UNSIGNED_INT, stride, @ptrFromInt(@offsetOf(vertex.Instance, "policy")));
    gl.glEnableVertexAttribArray(7);
    gl.glVertexAttribIPointer(8, 3, gl.GL_UNSIGNED_INT, stride, @ptrFromInt(@offsetOf(vertex.Instance, "policy") + 16));
    gl.glEnableVertexAttribArray(8);
}

fn setupInstanceDivisors() void {
    inline for (0..9) |i| {
        gl.glVertexAttribDivisor(@intCast(i), 1);
    }
}

fn setupVertexAttrib(loc: u32, components: gl.GLint, ty: gl.GLenum, normalized: gl.GLboolean, stride: gl.GLsizei, offset: usize) void {
    gl.glVertexAttribPointer(loc, components, ty, normalized, stride, @ptrFromInt(offset));
    gl.glEnableVertexAttribArray(loc);
}

fn initEbo() void {
    // Single quad index pattern — instancing repeats it per glyph.
    const indices = [6]u32{ 0, 1, 2, 0, 2, 3 };
    gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(indices)), &indices, gl.GL_STATIC_DRAW);
}

// ── Shader compilation ──

const linear_resolve_vertex_shader: [:0]const u8 =
    \\#version 300 es
    \\precision highp float;
    \\precision highp int;
    \\out vec2 v_uv;
    \\void main() {
    \\    vec2 pos = vec2((gl_VertexID == 1) ? 3.0 : -1.0,
    \\                    (gl_VertexID == 2) ? 3.0 : -1.0);
    \\    v_uv = pos * 0.5 + 0.5;
    \\    gl_Position = vec4(pos, 0.0, 1.0);
    \\}
;

const linear_resolve_fragment_shader: [:0]const u8 =
    \\#version 300 es
    \\precision highp float;
    \\precision highp int;
    \\in vec2 v_uv;
    \\uniform sampler2D u_linear_tex;
    \\uniform sampler2D u_dst_tex;
    \\uniform int u_mode;
    \\out vec4 frag_color;
    \\
    \\float srgbDecode(float c) {
    \\    return (c <= 0.04045) ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
    \\}
    \\
    \\float srgbEncode(float c) {
    \\    return (c <= 0.0031308) ? c * 12.92 : 1.055 * pow(c, 1.0 / 2.4) - 0.055;
    \\}
    \\
    \\vec4 srgbDecodePremultiplied(vec4 premul) {
    \\    if (premul.a <= 0.0) return vec4(0.0);
    \\    float inv_a = 1.0 / premul.a;
    \\    return vec4(
    \\        srgbDecode(clamp(premul.r * inv_a, 0.0, 1.0)) * premul.a,
    \\        srgbDecode(clamp(premul.g * inv_a, 0.0, 1.0)) * premul.a,
    \\        srgbDecode(clamp(premul.b * inv_a, 0.0, 1.0)) * premul.a,
    \\        premul.a
    \\    );
    \\}
    \\
    \\vec4 srgbEncodePremultiplied(vec4 premul) {
    \\    if (premul.a <= 0.0) return vec4(0.0);
    \\    float inv_a = 1.0 / premul.a;
    \\    return vec4(
    \\        srgbEncode(max(premul.r * inv_a, 0.0)) * premul.a,
    \\        srgbEncode(max(premul.g * inv_a, 0.0)) * premul.a,
    \\        srgbEncode(max(premul.b * inv_a, 0.0)) * premul.a,
    \\        premul.a
    \\    );
    \\}
    \\
    \\void main() {
    \\    if (u_mode == 0) {
    \\        frag_color = srgbDecodePremultiplied(texture(u_dst_tex, v_uv));
    \\    } else {
    \\        frag_color = srgbEncodePremultiplied(texture(u_linear_tex, v_uv));
    \\    }
    \\}
;

fn setTextBlendMode(special: bool, render_mode: subpixel_policy.TextRenderMode) void {
    _ = special;
    _ = render_mode;
    gl.glEnable(gl.GL_BLEND);
    gl.glBlendFuncSeparate(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA, gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
}

fn findCache(
    caches: anytype,
    pool: *snail_mod.PagePool,
) ?@TypeOf(caches[0]) {
    for (caches) |c| {
        if (c.pool == pool) return c;
    }
    return null;
}
