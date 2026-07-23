const std = @import("std");
const gl = @import("bindings.zig").gl;
const gl_backend = @import("detect.zig");
const gl_programs = @import("programs.zig");
const gles30_upload = @import("../device_atlas.zig");
const gl_common = @import("../common.zig");
const linear_resolve = @import("../linear_resolve.zig");
const draw_records_mod = @import("snail").render.records;
const shaders = @import("../shaders.zig").Gles30;
const vertex = @import("snail").render.records;
const snail_mod = @import("snail");
const render_state = @import("render-state");
const SubpixelOrder = @import("render-state").SubpixelOrder;
const LinearResolve = render_state.LinearResolve;
const DrawState = render_state.DrawState;
const TargetSurface = render_state.TargetSurface;

const TextRenderMode = enum { grayscale };

pub const LinearResolveRestore = gl_common.LinearResolveRestore;

const LinearResolveState = linear_resolve.StateFor(gl, .{
    .vertex_shader = shaders.native_linear_resolve_vertex_shader,
    .fragment_shader = shaders.native_linear_resolve_fragment_shader,
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
    tt_hinted_text_program: ProgramState = .{},
    autohint_program: ProgramState = .{},
    linear_resolve: LinearResolveState = .{},
    vao: gl.GLuint = 0,
    vbo: gl.GLuint = 0,
    ebo: gl.GLuint = 0,
    active_program: gl.GLuint = 0,
    frame_begun: bool = false,

    // ── Init / Deinit ──

    pub fn init(self: *Gles30TextState) !void {
        self.backend = gl_backend.detect(gl);

        // Link all draw programs during renderer init so draw never compiles or links.
        // Regular text and colr use the native-Slang generated shaders
        // (stages A/B of the Slang cutover); the remaining families keep the
        // composed GLSL-fragment catalog. The fragment-only native families
        // share the native text vertex stage.
        self.text_program = try gl_programs.loadNativeProgramState("text-native", shaders.native_text_vertex_shader, shaders.native_text_fragment_shader);
        self.colr_program = try gl_programs.loadNativeProgramState("colr-native", shaders.native_text_vertex_shader, shaders.native_colr_fragment_shader);
        self.path_program = try gl_programs.loadNativeProgramState("path-native", shaders.native_text_vertex_shader, shaders.native_path_fragment_shader);
        self.tt_hinted_text_program = try gl_programs.loadNativeProgramState("hinted-text-native", shaders.native_text_vertex_shader, shaders.native_tt_hinted_fragment_shader);
        self.autohint_program = try gl_programs.loadNativeProgramState("autohint-native", shaders.native_autohint_vertex_shader, shaders.native_autohint_fragment_shader);
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
    }

    pub fn deinit(self: *Gles30TextState) void {
        deleteProgramState(&self.text_program);
        deleteProgramState(&self.colr_program);
        deleteProgramState(&self.path_program);
        deleteProgramState(&self.tt_hinted_text_program);
        deleteProgramState(&self.autohint_program);
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
    } || draw_records_mod.DrawRecords.ValidationError || std.mem.Allocator.Error;

    /// Walk `DrawRecords.segments`, bind each segment's matching
    /// `Gles30DeviceAtlas` cache, dispatch the encoded instances
    /// through the existing program set. GLES3 has no dual-source
    /// blend, so subpixel runs fall back to grayscale.
    pub fn draw(
        self: *Gles30TextState,
        scratch: std.mem.Allocator,
        draw_state: DrawState,
        records: draw_records_mod.DrawRecords,
        caches: []const *const gles30_upload.Gles30DeviceAtlas,
    ) DrawError!void {
        try records.validate();
        gl.glBindVertexArray(self.vao);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);

        for (records.batches) |batch| {
            const cache = findCache(caches, batch.binding) orelse {
                for (caches) |candidate| if (candidate.pool == batch.binding.pool) return error.StaleBinding;
                return error.MissingBinding;
            };
            const batch_instances = records.instances[batch.first_instance..][0..batch.instance_count];
            _ = scratch;
            try self.drawBatch(cache, draw_state, batch_instances, batch.kind);
        }
    }

    fn drawBatch(self: *Gles30TextState, cache: *const gles30_upload.Gles30DeviceAtlas, draw_state: DrawState, instances: []const vertex.Instance, kind: draw_records_mod.ShapeKind) DrawError!void {
        const total_glyphs = instances.len;
        if (total_glyphs == 0) return;

        const run_mode: TextRenderMode = .grayscale;
        setTextBlendMode(kind != .regular, run_mode);
        const prog_state = switch (kind) {
            .regular => &self.text_program,
            .colr => self.ensureColrProgram(),
            .path => self.ensurePathProgram(),
            .tt_hinted_text => self.ensureTtHintedTextProgram(),
            .autohint => self.ensureAutohintProgram(),
        };
        self.bindProgramState(cache, prog_state, draw_state, run_mode);
        self.drawGlyphRange(instances, 0, total_glyphs);
    }

    fn bindProgramState(self: *Gles30TextState, cache: *const gles30_upload.Gles30DeviceAtlas, prog_state: *const ProgramState, draw_state: DrawState, render_mode: TextRenderMode) void {
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

        // Native-Slang text program: every per-draw parameter lives in one
        // 96-byte UBO block; loose-uniform locs are all -1 for it.
        if (prog_state.ubo != 0) {
            const order = if (render_mode == .grayscale) SubpixelOrder.none else draw_state.raster.subpixel_order;
            const block = gl_common.NativeTextPushBlock{
                .mvp = draw_state.mvp.data,
                .viewport = .{ @floatFromInt(draw_state.surface.pixel_width), @floatFromInt(draw_state.surface.pixel_height) },
                .subpixel_order = @intFromEnum(order),
                .output_srgb = @intFromBool(draw_state.surface.encoding.shaderEncodesSrgb() and !self.linear_resolve.active),
                .layer_base = 0,
                .coverage_exponent = draw_state.raster.coverage_transfer.shaderExponent(),
                .dither_scale = draw_state.surface.format.ditherAmplitude(),
                .mask_output = if (draw_state.surface.format.hasColor()) 0 else 1,
            };
            gl.glBindBufferBase(gl.GL_UNIFORM_BUFFER, gl_common.NATIVE_TEXT_UBO_BINDING, prog_state.ubo);
            gl.glBufferSubData(gl.GL_UNIFORM_BUFFER, 0, @sizeOf(gl_common.NativeTextPushBlock), &block);
            return;
        }

        gl.glUniformMatrix4fv(prog_state.mvp_loc, 1, gl.GL_FALSE, &draw_state.mvp.data);
        gl.glUniform2f(prog_state.viewport_loc, @floatFromInt(draw_state.surface.pixel_width), @floatFromInt(draw_state.surface.pixel_height));
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

    fn ensureTtHintedTextProgram(self: *Gles30TextState) *const ProgramState {
        std.debug.assert(self.tt_hinted_text_program.handle != 0);
        return &self.tt_hinted_text_program;
    }

    fn ensureAutohintProgram(self: *Gles30TextState) *const ProgramState {
        std.debug.assert(self.autohint_program.handle != 0);
        return &self.autohint_program;
    }

    fn drawGlyphRange(self: *Gles30TextState, instances: []const vertex.Instance, glyph_offset: usize, glyph_count: usize) void {
        _ = self;
        var glyphs_drawn: usize = 0;
        while (glyphs_drawn < glyph_count) {
            const instance_offset = glyph_offset + glyphs_drawn;
            const chunk: usize = @min(glyph_count - glyphs_drawn, MAX_GLYPHS_PER_UPLOAD);
            const byte_size = chunk * BYTES_PER_GLYPH;

            gl.glBufferSubData(gl.GL_ARRAY_BUFFER, 0, @intCast(byte_size), @ptrCast(instances[instance_offset..].ptr));

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
    gl.glVertexAttribIPointer(4, 4, gl.GL_UNSIGNED_INT, stride, @ptrFromInt(@offsetOf(vertex.Instance, "payload")));
    gl.glEnableVertexAttribArray(4);
    setupVertexAttrib(5, 4, gl.GL_HALF_FLOAT, gl.GL_FALSE, stride, @offsetOf(vertex.Instance, "color"));
    setupVertexAttrib(6, 4, gl.GL_HALF_FLOAT, gl.GL_FALSE, stride, @offsetOf(vertex.Instance, "tint"));
}

fn setupInstanceDivisors() void {
    inline for (0..7) |i| {
        gl.glVertexAttribDivisor(@intCast(i), 1);
    }
}

fn setupVertexAttrib(loc: u32, components: gl.GLint, ty: gl.GLenum, normalized: gl.GLboolean, stride: gl.GLsizei, offset: usize) void {
    gl.glVertexAttribPointer(loc, components, ty, normalized, stride, @ptrFromInt(offset));
    gl.glEnableVertexAttribArray(loc);
}

fn initEbo() void {
    // Single quad index pattern — instancing repeats it per glyph.
    const indices = [6]u32{ 1, 2, 0, 2, 3, 0 };
    gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(indices)), &indices, gl.GL_STATIC_DRAW);
}

fn setTextBlendMode(special: bool, render_mode: TextRenderMode) void {
    _ = special;
    _ = render_mode;
    gl.glEnable(gl.GL_BLEND);
    gl.glBlendFuncSeparate(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA, gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
}

fn findCache(
    caches: anytype,
    binding: draw_records_mod.Binding,
) ?@TypeOf(caches[0]) {
    for (caches) |c| {
        if (c.isBindingLive(binding)) return c;
    }
    return null;
}
