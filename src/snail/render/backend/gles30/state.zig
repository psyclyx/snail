const std = @import("std");
const gl = @import("bindings.zig").gl;
const gl_backend = @import("backend.zig");
const gl_programs = @import("programs.zig");
const gl_resources = @import("resources.zig");
const gles30_upload = @import("../gl/prepared_pages.zig");
const draw_records_mod = @import("../../../draw_records.zig");
const shaders = @import("shaders.zig");
const subpixel_policy = @import("../subpixel_policy.zig");
const texture_layers = @import("../../format/texture_layers.zig");
const vertex = @import("../../format/vertex.zig");
const snail_mod = @import("../../../root.zig");
const SubpixelOrder = @import("../../format/subpixel_order.zig").SubpixelOrder;
const LinearResolve = snail_mod.LinearResolve;
const PixelRect = snail_mod.PixelRect;
const IntermediateFormat = snail_mod.IntermediateFormat;
const DrawState = snail_mod.DrawState;
const TargetSurface = snail_mod.TargetSurface;

// ── Backend selection ──

pub const Backend = gl_backend.Backend;

// ── Shared types ──

const ProgramState = gl_programs.ProgramState;
const deleteProgramState = gl_programs.deleteProgramState;
const linkProgram = gl_programs.linkProgram;
const loadProgramState = gl_programs.loadProgramState;

pub const TextCoverageProgram = gl_resources.TextCoverageProgram;
pub const TextCoverageDrawState = gl_resources.TextCoverageDrawState;
pub const PreparedResources = gl_resources.PreparedResources;

pub const text_vertex_interface = shaders.text_vertex_interface;
pub const text_fragment_interface = shaders.text_fragment_interface;
pub const text_coverage_fragment_interface = shaders.text_coverage_fragment_interface;
pub const text_sample_interface = shaders.text_sample_interface;
pub const text_fragment_body = shaders.text_fragment_body;
pub const text_coverage_fragment_body = shaders.text_coverage_fragment_body;
pub const text_sample_body = shaders.text_sample_body;

// ── GLES30 streaming constants ──

const STREAM_BYTES = 4 * 1024 * 1024;
const BYTES_PER_GLYPH = vertex.BYTES_PER_INSTANCE;
const MAX_GLYPHS_PER_UPLOAD = STREAM_BYTES / BYTES_PER_GLYPH;

// ── Gles30TextState ──

pub const LinearResolveRestore = struct {
    draw_fbo: gl.GLint = 0,
    read_fbo: gl.GLint = 0,
    viewport: [4]gl.GLint = .{ 0, 0, 0, 0 },
    resolve_rect: PixelRect = .{},
    depth_test: bool = false,
    scissor_test: bool = false,
    blend: bool = false,
};

pub const Gles30TextState = struct {
    backend: Backend = .gles30,
    text_program: ProgramState = .{},
    colr_program: ProgramState = .{},
    path_program: ProgramState = .{},
    hinted_text_program: ProgramState = .{},
    text_program_replicated: ProgramState = .{},
    colr_program_replicated: ProgramState = .{},
    path_program_replicated: ProgramState = .{},
    hinted_text_program_replicated: ProgramState = .{},
    linear_resolve_program: gl.GLuint = 0,
    linear_resolve_tex_loc: gl.GLint = -1,
    linear_resolve_dst_tex_loc: gl.GLint = -1,
    linear_resolve_mode_loc: gl.GLint = -1,
    linear_resolve_vao: gl.GLuint = 0,
    linear_resolve_fbo: gl.GLuint = 0,
    linear_resolve_tex: gl.GLuint = 0,
    linear_resolve_dst_tex: gl.GLuint = 0,
    linear_resolve_width: u32 = 0,
    linear_resolve_height: u32 = 0,
    linear_resolve_format: IntermediateFormat = .rgba16f,
    linear_resolve_active: bool = false,
    vao: gl.GLuint = 0,
    vbo: gl.GLuint = 0,
    ebo: gl.GLuint = 0,
    vao_replicated: gl.GLuint = 0,
    vbo_replicated: gl.GLuint = 0,
    replicated_shape_divisor: u32 = 0,
    active_program: gl.GLuint = 0,
    active_resource_bank_id: u32 = std.math.maxInt(u32),
    frame_begun: bool = false,
    resource_cache: ?PreparedResources = null,

    // ── Init / Deinit ──

    pub fn init(self: *Gles30TextState) !void {
        self.backend = gl_backend.detect(gl);

        // Link all draw programs during renderer init so draw never compiles or links.
        self.text_program = try loadProgramState("text", shaders.vertex_shader, shaders.fragment_shader_text, false);
        self.colr_program = try loadProgramState("text-colr", shaders.vertex_shader, shaders.fragment_shader_colr, false);
        self.path_program = try loadProgramState("path", shaders.vertex_shader, shaders.fragment_shader_path, false);
        self.hinted_text_program = try loadProgramState("hinted-text", shaders.vertex_shader, shaders.fragment_shader_hinted_text, false);
        self.text_program_replicated = try loadProgramState("text-replicated", shaders.vertex_shader_replicated, shaders.fragment_shader_text, false);
        self.colr_program_replicated = try loadProgramState("text-colr-replicated", shaders.vertex_shader_replicated, shaders.fragment_shader_colr, false);
        self.path_program_replicated = try loadProgramState("path-replicated", shaders.vertex_shader_replicated, shaders.fragment_shader_path, false);
        self.hinted_text_program_replicated = try loadProgramState("hinted-text-replicated", shaders.vertex_shader_replicated, shaders.fragment_shader_hinted_text, false);
        self.linear_resolve_program = try linkProgram("linear-resolve", linear_resolve_vertex_shader, linear_resolve_fragment_shader, false);
        self.linear_resolve_tex_loc = gl.glGetUniformLocation(self.linear_resolve_program, "u_linear_tex");
        self.linear_resolve_dst_tex_loc = gl.glGetUniformLocation(self.linear_resolve_program, "u_dst_tex");
        self.linear_resolve_mode_loc = gl.glGetUniformLocation(self.linear_resolve_program, "u_mode");
        gl.glGenVertexArrays(1, &self.linear_resolve_vao);

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
        if (self.resource_cache) |*cache| {
            cache.deinit();
            self.resource_cache = null;
        }

        deleteProgramState(&self.text_program);
        deleteProgramState(&self.colr_program);
        deleteProgramState(&self.path_program);
        deleteProgramState(&self.hinted_text_program);
        deleteProgramState(&self.text_program_replicated);
        deleteProgramState(&self.colr_program_replicated);
        deleteProgramState(&self.path_program_replicated);
        deleteProgramState(&self.hinted_text_program_replicated);
        if (self.vao_replicated != 0) gl.glDeleteVertexArrays(1, &self.vao_replicated);
        if (self.vbo_replicated != 0) gl.glDeleteBuffers(1, &self.vbo_replicated);
        if (self.linear_resolve_program != 0) gl.glDeleteProgram(self.linear_resolve_program);
        if (self.linear_resolve_vao != 0) gl.glDeleteVertexArrays(1, &self.linear_resolve_vao);
        if (self.linear_resolve_fbo != 0) gl.glDeleteFramebuffers(1, &self.linear_resolve_fbo);
        if (self.linear_resolve_tex != 0) gl.glDeleteTextures(1, &self.linear_resolve_tex);
        if (self.linear_resolve_dst_tex != 0) gl.glDeleteTextures(1, &self.linear_resolve_dst_tex);
        if (self.vao != 0) gl.glDeleteVertexArrays(1, &self.vao);
        if (self.vbo != 0) gl.glDeleteBuffers(1, &self.vbo);
        if (self.ebo != 0) gl.glDeleteBuffers(1, &self.ebo);
    }

    pub fn resourceCache(self: *Gles30TextState, allocator: std.mem.Allocator) *PreparedResources {
        if (self.resource_cache == null) {
            self.resource_cache = PreparedResources{
                .allocator = allocator,
                .backend = self.backend,
            };
        }
        if (self.resource_cache) |*cache| {
            cache.backend = self.backend;
            return cache;
        }
        unreachable;
    }

    pub fn resetResourceCache(self: *Gles30TextState) void {
        if (self.resource_cache) |*cache| {
            const allocator = cache.allocator;
            const generation = cache.generation +% 1;
            cache.deinit();
            cache.* = .{
                .allocator = allocator,
                .backend = self.backend,
                .generation = generation,
            };
        }
    }

    pub fn resourceCacheStats(self: *const Gles30TextState) snail_mod.ResourceCacheStats {
        if (self.resource_cache) |*cache| {
            const active_atlas_pages = gl_resources.atlasPagesInBank(cache.atlas_slots[0..cache.atlas_slot_count], cache.active_atlas_bank_id);
            const active_image_layers: u32 = @intCast(cache.image_slot_count);
            var atlas_pages = active_atlas_pages;
            var atlas_layers = cache.allocated_layer_count;
            var image_layers_resident = active_image_layers;
            var image_layers = cache.allocated_image_count;
            for (cache.atlas_banks[0..cache.atlas_bank_count]) |bank| {
                atlas_pages += bank.resident_atlas_pages;
                atlas_layers += bank.allocated_layer_count;
                image_layers_resident += bank.resident_image_layers;
                image_layers += bank.allocated_image_count;
            }
            return .{
                .generation = cache.generation,
                .active_atlas_pages_resident = active_atlas_pages,
                .active_atlas_layers_allocated = cache.allocated_layer_count,
                .atlas_pages_resident = atlas_pages,
                .atlas_layers_allocated = atlas_layers,
                .active_image_layers_resident = active_image_layers,
                .active_image_layers_allocated = cache.allocated_image_count,
                .image_layers_resident = image_layers_resident,
                .image_layers_allocated = image_layers,
            };
        }
        return .{};
    }

    pub fn backendName(self: *const Gles30TextState) [:0]const u8 {
        _ = self;
        return "OpenGL ES 3.0";
    }

    pub fn beginLinearResolve(self: *Gles30TextState, surface: TargetSurface, resolve: LinearResolve) !LinearResolveRestore {
        if (!surface.supportsLinearResolve()) return error.UnsupportedResolve;
        if (self.linear_resolve_active) return error.LinearResolveAlreadyActive;
        const target_rect = surface.pixelRect();
        const width = target_rect.w;
        const height = target_rect.h;
        if (width == 0 or height == 0) return error.InvalidTargetSurface;
        try self.ensureLinearResolve(width, height, resolve.intermediate_format);

        var restore: LinearResolveRestore = .{};
        gl.glGetIntegerv(gl.GL_DRAW_FRAMEBUFFER_BINDING, &restore.draw_fbo);
        gl.glGetIntegerv(gl.GL_READ_FRAMEBUFFER_BINDING, &restore.read_fbo);
        gl.glGetIntegerv(gl.GL_VIEWPORT, &restore.viewport);
        restore.resolve_rect = resolve.region.rect(width, height);
        restore.depth_test = gl.glIsEnabled(gl.GL_DEPTH_TEST) == gl.GL_TRUE;
        restore.scissor_test = gl.glIsEnabled(gl.GL_SCISSOR_TEST) == gl.GL_TRUE;
        restore.blend = gl.glIsEnabled(gl.GL_BLEND) == gl.GL_TRUE;

        gl.glBindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, self.linear_resolve_fbo);
        gl.glViewport(0, 0, @intCast(width), @intCast(height));
        gl.glDisable(gl.GL_DEPTH_TEST);
        self.setResolveScissor(restore.resolve_rect, 0, height);
        gl.glDisable(gl.GL_BLEND);
        switch (resolve.backdrop) {
            .target => {
                self.snapshotResolveDestination(restore, width, height);
                self.drawLinearResolveTriangle(.seed_intermediate);
            },
            .clear => |color| {
                const linear = linearPremultipliedBackdropColor(color);
                gl.glClearBufferfv(gl.GL_COLOR, 0, &linear);
            },
            .transparent => {
                const zero = [4]f32{ 0, 0, 0, 0 };
                gl.glClearBufferfv(gl.GL_COLOR, 0, &zero);
            },
            .dont_care => {},
        }
        self.linear_resolve_active = true;
        return restore;
    }

    pub fn endLinearResolve(self: *Gles30TextState, restore: LinearResolveRestore) void {
        std.debug.assert(self.linear_resolve_active);
        gl.glBindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, @intCast(restore.draw_fbo));
        gl.glViewport(restore.viewport[0], restore.viewport[1], restore.viewport[2], restore.viewport[3]);
        gl.glDisable(gl.GL_DEPTH_TEST);
        self.setResolveScissor(restore.resolve_rect, restore.viewport[1], @intCast(restore.viewport[3]));

        gl.glDisable(gl.GL_BLEND);
        self.drawLinearResolveTriangle(.encode_to_target);

        if (restore.blend) {
            gl.glEnable(gl.GL_BLEND);
        } else {
            gl.glDisable(gl.GL_BLEND);
        }
        gl.glBlendFuncSeparate(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA, gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
        if (restore.depth_test) {
            gl.glEnable(gl.GL_DEPTH_TEST);
        } else {
            gl.glDisable(gl.GL_DEPTH_TEST);
        }
        if (restore.scissor_test) {
            gl.glEnable(gl.GL_SCISSOR_TEST);
        } else {
            gl.glDisable(gl.GL_SCISSOR_TEST);
        }
        gl.glBindFramebuffer(gl.GL_READ_FRAMEBUFFER, @intCast(restore.read_fbo));
        self.linear_resolve_active = false;
        self.frame_begun = false;
    }

    const LinearResolvePass = enum(gl.GLint) {
        seed_intermediate = 0,
        encode_to_target = 1,
    };

    fn snapshotResolveDestination(self: *Gles30TextState, restore: LinearResolveRestore, width: u32, height: u32) void {
        var prev_tex: gl.GLint = 0;
        gl.glGetIntegerv(gl.GL_TEXTURE_BINDING_2D, &prev_tex);
        defer gl.glBindTexture(gl.GL_TEXTURE_2D, @intCast(prev_tex));

        const rect = restore.resolve_rect;
        if (rect.w == 0 or rect.h == 0) return;
        const y = glRectY(rect, height);
        gl.glBindFramebuffer(gl.GL_READ_FRAMEBUFFER, @intCast(restore.draw_fbo));
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.linear_resolve_dst_tex);
        gl.glCopyTexSubImage2D(
            gl.GL_TEXTURE_2D,
            0,
            rect.x,
            y,
            restore.viewport[0] + rect.x,
            restore.viewport[1] + y,
            @intCast(@min(rect.w, width)),
            @intCast(@min(rect.h, height)),
        );
    }

    fn drawLinearResolveTriangle(self: *Gles30TextState, pass: LinearResolvePass) void {
        gl.glUseProgram(self.linear_resolve_program);
        gl.glBindVertexArray(self.linear_resolve_vao);
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D, if (pass == .seed_intermediate) 0 else self.linear_resolve_tex);
        gl.glActiveTexture(gl.GL_TEXTURE1);
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.linear_resolve_dst_tex);
        if (self.linear_resolve_tex_loc >= 0) gl.glUniform1i(self.linear_resolve_tex_loc, 0);
        if (self.linear_resolve_dst_tex_loc >= 0) gl.glUniform1i(self.linear_resolve_dst_tex_loc, 1);
        if (self.linear_resolve_mode_loc >= 0) gl.glUniform1i(self.linear_resolve_mode_loc, @intFromEnum(pass));
        gl.glDrawArrays(gl.GL_TRIANGLES, 0, 3);
    }

    fn setResolveScissor(_: *Gles30TextState, rect: PixelRect, viewport_y: gl.GLint, viewport_height: u32) void {
        const y = viewport_y + glRectY(rect, viewport_height);
        gl.glEnable(gl.GL_SCISSOR_TEST);
        gl.glScissor(rect.x, y, @intCast(rect.w), @intCast(rect.h));
    }

    fn glRectY(rect: PixelRect, height: u32) gl.GLint {
        return @intCast(@as(i32, @intCast(height)) - rect.y - @as(i32, @intCast(rect.h)));
    }

    fn srgbFloatToLinear(v: f32) f32 {
        const c = std.math.clamp(v, 0.0, 1.0);
        return if (c <= 0.04045) c / 12.92 else std.math.pow(f32, (c + 0.055) / 1.055, 2.4);
    }

    fn linearPremultipliedBackdropColor(color_srgb: [4]f32) [4]f32 {
        const alpha = std.math.clamp(color_srgb[3], 0.0, 1.0);
        return .{
            srgbFloatToLinear(color_srgb[0]) * alpha,
            srgbFloatToLinear(color_srgb[1]) * alpha,
            srgbFloatToLinear(color_srgb[2]) * alpha,
            alpha,
        };
    }

    fn ensureLinearResolve(self: *Gles30TextState, width: u32, height: u32, format: IntermediateFormat) !void {
        if (self.linearResolveReady(width, height, format)) return;
        self.resetLinearResolveObjects(format);

        var prev_draw: gl.GLint = 0;
        var prev_read: gl.GLint = 0;
        var prev_tex: gl.GLint = 0;
        gl.glGetIntegerv(gl.GL_DRAW_FRAMEBUFFER_BINDING, &prev_draw);
        gl.glGetIntegerv(gl.GL_READ_FRAMEBUFFER_BINDING, &prev_read);
        gl.glGetIntegerv(gl.GL_TEXTURE_BINDING_2D, &prev_tex);
        defer {
            gl.glBindTexture(gl.GL_TEXTURE_2D, @intCast(prev_tex));
            gl.glBindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, @intCast(prev_draw));
            gl.glBindFramebuffer(gl.GL_READ_FRAMEBUFFER, @intCast(prev_read));
        }

        gl.glGenFramebuffers(1, &self.linear_resolve_fbo);
        gl.glGenTextures(1, &self.linear_resolve_tex);
        gl.glGenTextures(1, &self.linear_resolve_dst_tex);
        initLinearResolveTexture(self.linear_resolve_tex, width, height, format);
        initLinearResolveDestinationTexture(self.linear_resolve_dst_tex, width, height);
        gl.glBindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, self.linear_resolve_fbo);
        gl.glFramebufferTexture2D(gl.GL_DRAW_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, self.linear_resolve_tex, 0);
        if (gl.glCheckFramebufferStatus(gl.GL_DRAW_FRAMEBUFFER) != gl.GL_FRAMEBUFFER_COMPLETE) {
            return error.FramebufferIncomplete;
        }

        self.linear_resolve_width = width;
        self.linear_resolve_height = height;
    }

    fn linearResolveReady(self: *const Gles30TextState, width: u32, height: u32, format: IntermediateFormat) bool {
        return self.linear_resolve_fbo != 0 and
            self.linear_resolve_tex != 0 and
            self.linear_resolve_dst_tex != 0 and
            self.linear_resolve_width == width and
            self.linear_resolve_height == height and
            self.linear_resolve_format == format;
    }

    fn resetLinearResolveObjects(self: *Gles30TextState, format: IntermediateFormat) void {
        if (self.linear_resolve_fbo != 0) gl.glDeleteFramebuffers(1, &self.linear_resolve_fbo);
        if (self.linear_resolve_tex != 0) gl.glDeleteTextures(1, &self.linear_resolve_tex);
        if (self.linear_resolve_dst_tex != 0) gl.glDeleteTextures(1, &self.linear_resolve_dst_tex);
        self.linear_resolve_fbo = 0;
        self.linear_resolve_tex = 0;
        self.linear_resolve_dst_tex = 0;
        self.linear_resolve_width = 0;
        self.linear_resolve_height = 0;
        self.linear_resolve_format = format;
    }

    fn initLinearResolveTexture(texture: gl.GLuint, width: u32, height: u32, format: IntermediateFormat) void {
        const internal_format: gl.GLint = switch (format) {
            .rgba16f => gl.GL_RGBA16F,
            .rgba32f => gl.GL_RGBA32F,
        };
        const pixel_type: gl.GLenum = switch (format) {
            .rgba16f => gl.GL_HALF_FLOAT,
            .rgba32f => gl.GL_FLOAT,
        };
        gl.glBindTexture(gl.GL_TEXTURE_2D, texture);
        gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, internal_format, @intCast(width), @intCast(height), 0, gl.GL_RGBA, pixel_type, null);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
    }

    fn initLinearResolveDestinationTexture(texture: gl.GLuint, width: u32, height: u32) void {
        gl.glBindTexture(gl.GL_TEXTURE_2D, texture);
        gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA8, @intCast(width), @intCast(height), 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, null);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
    }

    // ── Draw ──

    fn drawTextInternal(self: *Gles30TextState, prepared: *const PreparedResources, vertices: []const u32, draw_state: DrawState, texture_layer_base: u32, allow_subpixel: bool) !void {
        // VAO may have been unbound by other renderers in the same context.
        gl.glBindVertexArray(self.vao);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);

        const total_glyphs = vertices.len / vertex.WORDS_PER_INSTANCE;
        const render_mode = subpixel_policy.chooseTextRenderMode(
            vertices,
            draw_state.mvp,
            allow_subpixel,
            draw_state.raster.subpixel_order,
            false,
        );
        if (!prepared.atlas_has_special_text_runs) {
            setTextBlendMode(false, render_mode);
            const prog_state = switch (render_mode) {
                .grayscale => &self.text_program,
                .subpixel_dual_source => &self.text_program,
            };
            try self.bindProgramState(prepared, prog_state, draw_state, texture_layer_base, render_mode);
            self.drawGlyphRange(vertices, 0, total_glyphs);
            return;
        }

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
                .regular => switch (run_mode) {
                    .grayscale => &self.text_program,
                    .subpixel_dual_source => &self.text_program,
                },
                .colr => self.ensureColrProgram(),
                .path => self.ensurePathProgram(),
                .hinted_text => self.ensureHintedTextProgram(),
            };
            try self.bindProgramState(prepared, prog_state, draw_state, texture_layer_base, run_mode);
            self.drawGlyphRange(vertices, run_start, run_end - run_start);
            run_start = run_end;
        }
    }

    pub fn drawTextPrepared(self: *Gles30TextState, prepared: *const PreparedResources, vertices: []const u32, draw_state: DrawState, texture_layer_base: u32) !void {
        try self.drawTextInternal(prepared, vertices, draw_state, texture_layer_base, true);
    }

    pub fn drawPreparedText(self: *Gles30TextState, prepared: *const PreparedResources, vertices: []const u32) void {
        _ = prepared;
        if (vertices.len == 0) return;
        gl.glBindVertexArray(self.vao);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
        self.drawGlyphRange(vertices, 0, vertices.len / vertex.WORDS_PER_INSTANCE);
    }

    pub fn drawPathsPrepared(self: *Gles30TextState, prepared: *const PreparedResources, vertices: []const u32, draw_state: DrawState, texture_layer_base: u32) !void {
        const render_mode: subpixel_policy.TextRenderMode = .grayscale;
        const prog_state = self.ensurePathProgram();
        gl.glBindVertexArray(self.vao);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);

        setTextBlendMode(false, render_mode);

        try self.bindProgramState(prepared, prog_state, draw_state, texture_layer_base, render_mode);
        self.drawGlyphRange(vertices, 0, vertices.len / vertex.WORDS_PER_INSTANCE);
    }

    // ── New-API draw entry (Phase 5b) ──

    pub const NewDrawError = error{
        MissingBinding,
        StaleBinding,
        MalformedSegment,
    } || std.mem.Allocator.Error;

    /// Walk `DrawRecords.segments`, bind each segment's matching
    /// `Gles30PreparedPages` cache, dispatch the encoded instances
    /// through the existing program set. Mirrors `drawNewApi` on the
    /// GL backend; the only differences are the GLES3 binding namespace
    /// (no DSA, no persistent ring buffer) and that subpixel runs
    /// without dual-source-blend support fall back to grayscale.
    pub fn drawNewApi(
        self: *Gles30TextState,
        scratch: std.mem.Allocator,
        draw_state: DrawState,
        records: draw_records_mod.DrawRecords,
        caches: []const *const gles30_upload.Gles30PreparedPages,
    ) NewDrawError!void {
        gl.glBindVertexArray(self.vao);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);

        for (records.segments) |seg| {
            const cache = findNewApiCache(caches, seg.binding.pool) orelse return error.MissingBinding;
            if (seg.binding.generation != 0 and cache.upload_generation < seg.binding.generation) return error.StaleBinding;
            const seg_words = records.words[seg.words_offset..][0..seg.words_len];
            switch (seg.kind) {
                .heterogeneous => try self.drawHeterogeneousNewApi(cache, draw_state, seg_words),
                .replicated => try self.drawReplicatedNewApi(scratch, cache, draw_state, seg, seg_words),
            }
        }
    }

    fn drawHeterogeneousNewApi(self: *Gles30TextState, cache: *const gles30_upload.Gles30PreparedPages, draw_state: DrawState, vertices: []const u32) NewDrawError!void {
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
            };
            self.bindProgramStateNewApi(cache, prog_state, draw_state, run_mode);
            self.drawGlyphRange(vertices, run_start, run_end - run_start);
            run_start = run_end;
        }
    }

    /// Real hardware GPU instancing for the GLES3 replicated path. See
    /// the GL state.zig counterpart for the design notes — one
    /// instanced draw per shape, M instances each, shape attrs
    /// at divisor M (constant within a draw) and overrides at divisor 1.
    fn drawReplicatedNewApi(
        self: *Gles30TextState,
        _: std.mem.Allocator,
        cache: *const gles30_upload.Gles30PreparedPages,
        draw_state: DrawState,
        seg: draw_records_mod.DrawSegment,
        seg_words: []const u32,
    ) NewDrawError!void {
        const n = seg.shape_count;
        const m = seg.override_count;
        if (n == 0 or m == 0) return;
        const WORDS_PER_OVERRIDE: usize = 8;
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
            inline for (0..7) |i| gl.glVertexAttribDivisor(@intCast(i), m);
            inline for (7..10) |i| gl.glVertexAttribDivisor(@intCast(i), 1);
            self.replicated_shape_divisor = m;
        }

        const allow_subpixel = false; // GLES3 has no dual-source blend.
        const shape_words_view = seg_words[0..@as(usize, n) * vertex.WORDS_PER_INSTANCE];

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
            };
            self.bindProgramStateNewApi(cache, prog_state, draw_state, run_mode);
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
        gl.glVertexAttribPointer(7, 4, gl.GL_FLOAT, gl.GL_FALSE, override_stride, @ptrFromInt(override_base + 0));
        gl.glEnableVertexAttribArray(7);
        gl.glVertexAttribPointer(8, 4, gl.GL_FLOAT, gl.GL_FALSE, override_stride, @ptrFromInt(override_base + 16));
        gl.glEnableVertexAttribArray(8);
        gl.glVertexAttribPointer(9, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, override_stride, @ptrFromInt(override_base + 24));
        gl.glEnableVertexAttribArray(9);
    }

    fn bindProgramStateNewApi(self: *Gles30TextState, cache: *const gles30_upload.Gles30PreparedPages, prog_state: *const ProgramState, draw_state: DrawState, render_mode: subpixel_policy.TextRenderMode) void {
        const program_changed = prog_state.handle != self.active_program or !self.frame_begun;
        if (program_changed) {
            gl.glUseProgram(prog_state.handle);
            self.active_program = prog_state.handle;
            // Reset bank id so legacy/new paths don't conflict.
            self.active_resource_bank_id = std.math.maxInt(u32);
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

        if (prog_state.curve_tex_loc >= 0) gl.glUniform1i(prog_state.curve_tex_loc, 0);
        if (prog_state.band_tex_loc >= 0) gl.glUniform1i(prog_state.band_tex_loc, 1);
        if (prog_state.layer_tex_loc >= 0) gl.glUniform1i(prog_state.layer_tex_loc, 2);
        if (prog_state.image_tex_loc >= 0) gl.glUniform1i(prog_state.image_tex_loc, 3);

        gl.glUniformMatrix4fv(prog_state.mvp_loc, 1, gl.GL_FALSE, &draw_state.mvp.data);
        gl.glUniform2f(prog_state.viewport_loc, draw_state.surface.pixel_width, draw_state.surface.pixel_height);
        if (prog_state.layer_base_loc >= 0) gl.glUniform1i(prog_state.layer_base_loc, 0);
        if (prog_state.subpixel_order_loc >= 0) {
            const order = if (render_mode == .grayscale) SubpixelOrder.none else draw_state.raster.subpixel_order;
            gl.glUniform1i(prog_state.subpixel_order_loc, @intFromEnum(order));
        }
        if (prog_state.output_srgb_loc >= 0) {
            const output_srgb = draw_state.surface.encoding.shaderEncodesSrgb() and !self.linear_resolve_active;
            gl.glUniform1i(prog_state.output_srgb_loc, @intFromBool(output_srgb));
        }
        if (prog_state.coverage_exponent_loc >= 0) {
            gl.glUniform1f(prog_state.coverage_exponent_loc, draw_state.raster.coverage_transfer.shaderExponent());
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

    fn bindProgramState(self: *Gles30TextState, prepared: *const PreparedResources, prog_state: *const ProgramState, draw_state: DrawState, texture_layer_base: u32, render_mode: subpixel_policy.TextRenderMode) !void {
        const bank_id = texture_layers.bank(texture_layer_base);
        const bank = prepared.bankForId(bank_id) orelse return error.MissingPreparedResource;
        if (prog_state.handle != self.active_program or !self.frame_begun or bank_id != self.active_resource_bank_id) {
            gl.glUseProgram(prog_state.handle);
            self.active_program = prog_state.handle;
            self.active_resource_bank_id = bank_id;

            gl.glActiveTexture(gl.GL_TEXTURE0);
            gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, bank.curve_array);
            gl.glActiveTexture(gl.GL_TEXTURE1);
            gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, bank.band_array);
            if (prog_state.layer_tex_loc >= 0 and bank.layer_info_tex != 0) {
                gl.glActiveTexture(gl.GL_TEXTURE2);
                gl.glBindTexture(gl.GL_TEXTURE_2D, bank.layer_info_tex);
            }
            if (prog_state.image_tex_loc >= 0 and bank.image_array != 0) {
                gl.glActiveTexture(gl.GL_TEXTURE3);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, bank.image_array);
            }

            if (prog_state.curve_tex_loc >= 0) gl.glUniform1i(prog_state.curve_tex_loc, 0);
            if (prog_state.band_tex_loc >= 0) gl.glUniform1i(prog_state.band_tex_loc, 1);
            if (prog_state.layer_tex_loc >= 0) gl.glUniform1i(prog_state.layer_tex_loc, 2);
            if (prog_state.image_tex_loc >= 0) gl.glUniform1i(prog_state.image_tex_loc, 3);
            self.frame_begun = true;
        }

        gl.glUniformMatrix4fv(prog_state.mvp_loc, 1, gl.GL_FALSE, &draw_state.mvp.data);
        gl.glUniform2f(prog_state.viewport_loc, draw_state.surface.pixel_width, draw_state.surface.pixel_height);
        if (prog_state.layer_base_loc >= 0) gl.glUniform1i(prog_state.layer_base_loc, @intCast(texture_layers.bankLocal(texture_layer_base)));
        // fill_rule is now per-paint-record (encoded into texel 0.x bit 15
        // by paint_records.write). Text/COLR/hinted glyphs use non-zero by
        // convention. The shader no longer reads u_fill_rule.
        if (prog_state.subpixel_order_loc >= 0) {
            const order = if (render_mode == .grayscale) SubpixelOrder.none else draw_state.raster.subpixel_order;
            gl.glUniform1i(prog_state.subpixel_order_loc, @intFromEnum(order));
        }
        if (prog_state.output_srgb_loc >= 0) {
            const output_srgb = draw_state.surface.encoding.shaderEncodesSrgb() and !self.linear_resolve_active;
            gl.glUniform1i(prog_state.output_srgb_loc, @intFromBool(output_srgb));
        }
        if (prog_state.coverage_exponent_loc >= 0) {
            gl.glUniform1f(prog_state.coverage_exponent_loc, draw_state.raster.coverage_transfer.shaderExponent());
        }
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

// ── Module-level state instance ──

pub var state: Gles30TextState = .{};

pub fn init() !void {
    return state.init();
}

pub fn deinit() void {
    state.deinit();
}

pub fn beginFrame() void {
    state.beginDraw();
}

pub fn backendName() [:0]const u8 {
    return state.backendName();
}

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

fn findNewApiCache(
    caches: anytype,
    pool: *snail_mod.PagePool,
) ?@TypeOf(caches[0]) {
    for (caches) |c| {
        if (c.pool == pool) return c;
    }
    return null;
}

fn composeShapeOverrideNewApi(dst: []u32, shape: []const u32, override: []const u32) void {
    std.debug.assert(dst.len == vertex.WORDS_PER_INSTANCE);
    std.debug.assert(shape.len == vertex.WORDS_PER_INSTANCE);
    std.debug.assert(override.len == 8);
    @memcpy(dst, shape);
    const Transform2D = snail_mod.Transform2D;
    const shape_t = Transform2D{
        .xx = @bitCast(shape[2]),
        .xy = @bitCast(shape[3]),
        .yx = @bitCast(shape[4]),
        .yy = @bitCast(shape[5]),
        .tx = @bitCast(shape[6]),
        .ty = @bitCast(shape[7]),
    };
    const override_t = Transform2D{
        .xx = @bitCast(override[0]),
        .xy = @bitCast(override[1]),
        .tx = @bitCast(override[2]),
        .yx = @bitCast(override[3]),
        .yy = @bitCast(override[4]),
        .ty = @bitCast(override[5]),
    };
    const composed_t = Transform2D.multiply(override_t, shape_t);
    dst[2] = @bitCast(composed_t.xx);
    dst[3] = @bitCast(composed_t.xy);
    dst[4] = @bitCast(composed_t.yx);
    dst[5] = @bitCast(composed_t.yy);
    dst[6] = @bitCast(composed_t.tx);
    dst[7] = @bitCast(composed_t.ty);
    dst[15] = override[6];
}
