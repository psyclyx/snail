const std = @import("std");
const gl = @import("snail").gl.bindings.gl;
const gl_backend = @import("embed_gl_detect.zig");
const gl_programs = @import("embed_gl_programs.zig");
const gl_upload = @import("embed_gl_cache.zig");
const ring_buffer_mod = @import("embed_gl_ring_buffer.zig");
const RingBuffer = ring_buffer_mod.RingBuffer;
const gl_common = @import("embed_gl_common.zig");
const linear_resolve = @import("embed_gl_linear_resolve.zig");
const draw_records_mod = @import("snail").core.files.picture_draw_records;
const shaders = @import("snail").gl.shaders;
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
    .dst_format = .intermediate,
    .linkProgram = gl_programs.linkProgram,
});

// ── Backend selection ──

pub const Backend = gl_backend.Backend;

// ── Shared types ──

const ProgramState = gl_programs.ProgramState;
const deleteProgramState = gl_programs.deleteProgramState;
const loadProgramState = gl_programs.loadProgramState;

// ── Streaming constants ──

const GL33_STREAM_BYTES = ring_buffer_mod.SEGMENT_BYTES;
const BYTES_PER_GLYPH = vertex.BYTES_PER_INSTANCE;
const MAX_GLYPHS_PER_SEGMENT = ring_buffer_mod.SEGMENT_BYTES / BYTES_PER_GLYPH;

// ── GL text state ──

fn TextStateFor(comptime backend: Backend) type {
    return struct {
        const GlTextState = @This();

        text_program: ProgramState = .{},
        text_subpixel_dual_program: ProgramState = .{},
        colr_program: ProgramState = .{},
        path_program: ProgramState = .{},
        hinted_text_program: ProgramState = .{},
        autohint_program: ProgramState = .{},
        // Replicated variants: same fragment, vertex shader composes
        // shape × override via per-attribute divisor. Used by the new-API
        // replicated DrawSegment to issue N*M hardware-instanced draws.
        text_program_replicated: ProgramState = .{},
        text_subpixel_dual_program_replicated: ProgramState = .{},
        colr_program_replicated: ProgramState = .{},
        path_program_replicated: ProgramState = .{},
        hinted_text_program_replicated: ProgramState = .{},
        autohint_program_replicated: ProgramState = .{},
        linear_resolve: LinearResolveState = .{},
        vao: gl.GLuint = 0,
        vbo: gl.GLuint = 0,
        ebo: gl.GLuint = 0,
        /// Replicated-draw VAO: attributes 0-6 sourced from a shape
        /// stream (binding 0) with hardware divisor M, attributes 7-9
        /// from an override stream (binding 1) with divisor 1. Backing
        /// VBO is `vbo_replicated`; both bindings read from it at
        /// different offsets within the same buffer.
        vao_replicated: gl.GLuint = 0,
        vbo_replicated: gl.GLuint = 0,
        /// Active shape-stream divisor on `vao_replicated`. Tracked so we
        /// only issue `glVertexAttribDivisor` when M changes between
        /// successive replicated draws.
        replicated_shape_divisor: u32 = 0,
        active_program: gl.GLuint = 0,
        frame_begun: bool = false,
        supports_dual_source_blend: bool = false,
        ring: RingBuffer = .{},

        // ── Per-program uniform shadow cache ──
        //
        // Bench scenes typically draw N glyphs with one program and a
        // constant MVP/viewport/encoding/etc. The pre-cache version
        // re-set every uniform on every `bindProgramState` call, which
        // hit the driver 7+ times per draw. The shadow tracks
        // last-uploaded values per program; `bindProgramState` skips
        // glUniform* calls whose value matches what the program already
        // holds. The shadow is invalidated on program creation/reload
        // and (defensively) when the bound cache changes.
        active_cache: ?*const GlBackendCache = null,
        program_cache_count: usize = 0,
        program_uniform_caches: [10]ProgramUniformCache = [_]ProgramUniformCache{.{}} ** 10,
        // Per-draw GL state shadows.
        cached_blend_mode: BlendMode = .uninitialized,
        cached_replicated_vao_bound: bool = false,
        cached_heterogeneous_vao_bound: bool = false,

        const ProgramUniformCache = struct {
            program: gl.GLuint = 0,
            mvp_set: bool = false,
            mvp_data: [16]f32 = undefined,
            viewport_set: bool = false,
            viewport: [2]f32 = .{ 0, 0 },
            subpixel_order_set: bool = false,
            subpixel_order: i32 = 0,
            output_srgb_set: bool = false,
            output_srgb: i32 = 0,
            coverage_exponent_set: bool = false,
            coverage_exponent: f32 = 0,
        };

        // ── Init / Deinit ──

        pub fn init(self: *GlTextState) !void {
            if (comptime backend == .gl44) {
                if (gl_backend.detect(gl) != .gl44) return error.UnsupportedOpenGlBackend;
            }
            self.supports_dual_source_blend = detectDualSourceBlendSupport();
            errdefer self.deinit();

            // Link all draw programs during renderer init so draw never compiles or links.
            self.text_program = try loadProgramState("text", shaders.vertex_shader, shaders.fragment_shader_text, false);
            self.colr_program = try loadProgramState("text-colr", shaders.vertex_shader, shaders.fragment_shader_colr, false);
            self.path_program = try loadProgramState("path", shaders.vertex_shader, shaders.fragment_shader_path, false);
            self.hinted_text_program = try loadProgramState("hinted-text", shaders.vertex_shader, shaders.fragment_shader_hinted_text, false);
            self.autohint_program = try loadProgramState("autohint", shaders.vertex_shader, shaders.fragment_shader_autohint, false);
            if (self.supports_dual_source_blend) {
                self.text_subpixel_dual_program = try loadProgramState("text-subpixel-dual", shaders.vertex_shader, shaders.fragment_shader_text_subpixel_dual, true);
            }
            self.text_program_replicated = try loadProgramState("text-replicated", shaders.vertex_shader_replicated, shaders.fragment_shader_text, false);
            self.colr_program_replicated = try loadProgramState("text-colr-replicated", shaders.vertex_shader_replicated, shaders.fragment_shader_colr, false);
            self.path_program_replicated = try loadProgramState("path-replicated", shaders.vertex_shader_replicated, shaders.fragment_shader_path, false);
            self.hinted_text_program_replicated = try loadProgramState("hinted-text-replicated", shaders.vertex_shader_replicated, shaders.fragment_shader_hinted_text, false);
            self.autohint_program_replicated = try loadProgramState("autohint-replicated", shaders.vertex_shader_replicated, shaders.fragment_shader_autohint, false);
            if (self.supports_dual_source_blend) {
                self.text_subpixel_dual_program_replicated = try loadProgramState("text-subpixel-dual-replicated", shaders.vertex_shader_replicated, shaders.fragment_shader_text_subpixel_dual, true);
            }
            try self.linear_resolve.init();

            if (comptime backend == .gl33) {
                self.initGl33();
            } else {
                try self.initGl44();
            }

            gl.glEnable(gl.GL_BLEND);
            // Shader outputs premultiplied alpha (frag_color = v_color * coverage),
            // so use GL_ONE for src to avoid double-multiplying coverage.
            gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);

            // Enable sRGB framebuffer so GL handles gamma correction during blending.
            // The fragment shaders output linear premultiplied color; GL linearizes
            // existing framebuffer values before blending and applies sRGB gamma on write.
            gl.glEnable(gl.GL_FRAMEBUFFER_SRGB);
        }

        fn initGl33(self: *GlTextState) void {
            gl.glGenVertexArrays(1, &self.vao);
            gl.glGenBuffers(1, &self.vbo);
            gl.glGenBuffers(1, &self.ebo);
            gl.glBindVertexArray(self.vao);
            gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
            gl.glBufferData(gl.GL_ARRAY_BUFFER, GL33_STREAM_BYTES, null, gl.GL_STREAM_DRAW);
            gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ebo);
            initEbo();
            setupVertexAttribs();
            setupInstanceDivisors();

            // Replicated VAO: attribute formats are stable, buffer
            // offsets + shape divisor get updated per draw.
            gl.glGenVertexArrays(1, &self.vao_replicated);
            gl.glGenBuffers(1, &self.vbo_replicated);
            gl.glBindVertexArray(self.vao_replicated);
            gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ebo);
            // Attributes are configured lazily in drawReplicated
            // when the actual buffer + offsets are known.
            gl.glBindVertexArray(self.vao);
        }

        fn initGl44(self: *GlTextState) !void {
            gl.glCreateVertexArrays(1, &self.vao);
            gl.glCreateBuffers(1, &self.vbo);
            gl.glCreateBuffers(1, &self.ebo);

            self.ring.init(self.vbo) catch |err| {
                gl.glDeleteVertexArrays(1, &self.vao);
                gl.glDeleteBuffers(1, &self.vbo);
                gl.glDeleteBuffers(1, &self.ebo);
                self.vao = 0;
                self.vbo = 0;
                self.ebo = 0;
                return err;
            };

            // All vertex attribs are per-instance (binding divisor = 1).
            const stride: gl.GLint = vertex.BYTES_PER_INSTANCE;
            gl.glVertexArrayVertexBuffer(self.vao, 0, self.vbo, 0, stride);
            gl.glVertexArrayElementBuffer(self.vao, self.ebo);
            gl.glVertexArrayBindingDivisor(self.vao, 0, 1);

            setupVertexArrayAttribs(self.vao);

            gl.glBindVertexArray(self.vao);
            gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ebo);
            initEbo();

            // Replicated VAO + VBO: bindings 0 (shape, divisor M) and 1
            // (override, divisor 1) configured statically; vertex buffer
            // bindings + shape divisor updated per draw.
            gl.glCreateVertexArrays(1, &self.vao_replicated);
            gl.glCreateBuffers(1, &self.vbo_replicated);
            gl.glVertexArrayElementBuffer(self.vao_replicated, self.ebo);
            setupReplicatedVertexArrayAttribs(self.vao_replicated);
            gl.glVertexArrayBindingDivisor(self.vao_replicated, 1, 1);
        }

        pub fn deinit(self: *GlTextState) void {
            if (comptime backend == .gl44) {
                self.ring.deinit(self.vbo);
            }

            deleteProgramState(&self.text_program);
            deleteProgramState(&self.text_subpixel_dual_program);
            deleteProgramState(&self.colr_program);
            deleteProgramState(&self.path_program);
            deleteProgramState(&self.hinted_text_program);
            deleteProgramState(&self.autohint_program);
            deleteProgramState(&self.text_program_replicated);
            deleteProgramState(&self.text_subpixel_dual_program_replicated);
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

        pub fn backendName(_: *const GlTextState) [:0]const u8 {
            return switch (backend) {
                .gl33 => "GL 3.3",
                .gl44 => "GL 4.4 (persistent mapped)",
            };
        }

        pub fn beginLinearResolve(self: *GlTextState, surface: TargetSurface, resolve: LinearResolve) !LinearResolveRestore {
            const restore = try self.linear_resolve.begin(surface, resolve);
            // The resolve pass binds its own program / VAO / textures /
            // blend state — our text-draw shadow caches no longer
            // reflect the GL state machine, so drop them.
            self.invalidateUniformShadows();
            return restore;
        }

        pub fn endLinearResolve(self: *GlTextState, restore: LinearResolveRestore) void {
            self.linear_resolve.end(restore);
            // Same reason as in beginLinearResolve: the encode-to-target
            // draw mutates program / VAO / blend / etc. Force the next
            // text-path bindProgramState call to re-issue every uniform.
            self.invalidateUniformShadows();
            self.frame_begun = false;
        }

        // ── New-API draw entry ──

        const gl_upload_variant: gl_upload.Variant = switch (backend) {
            .gl33 => .gl33,
            .gl44 => .gl44,
        };
        const GlBackendCache = gl_upload.GlBackendCacheFor(gl_upload_variant);

        pub const DrawError = error{
            MissingBinding,
            StaleBinding,
            MalformedSegment,
        } || std.mem.Allocator.Error;

        /// Walk `DrawRecords.segments`, bind each segment's matching
        /// `GlBackendCache` cache, dispatch the encoded instances through
        /// the existing program set. Replicated segments materialize
        /// composed instances in a caller-supplied scratch allocator.
        pub fn draw(
            self: *GlTextState,
            scratch: std.mem.Allocator,
            draw_state: DrawState,
            records: draw_records_mod.DrawRecords,
            caches: []const *const GlBackendCache,
        ) DrawError!void {
            // Apply `draw_state.scissor_rect` via `GL_SCISSOR_TEST`. We
            // save / restore both the enable flag and the rect so a
            // surrounding linear-resolve pass (which uses scissor too)
            // is undisturbed. The scissor coordinate system is GL's
            // y-up framebuffer space, so we flip from snail's y-down
            // `PixelRect`.
            const scissor_restore: ?ScissorRestore = if (draw_state.scissor_rect) |rect|
                applyScissor(rect, draw_state.surface.pixel_height)
            else
                null;
            defer if (scissor_restore) |r| r.restore();

            for (records.segments) |seg| {
                const cache = findCache(caches, seg.binding.pool) orelse return error.MissingBinding;
                if (seg.binding.generation != 0 and cache.upload_generation < seg.binding.generation) return error.StaleBinding;
                const seg_words = records.words[seg.words_offset..][0..seg.words_len];
                switch (seg.kind) {
                    .heterogeneous => try self.drawHeterogeneous(cache, draw_state, seg_words, seg.kind_mask),
                    .replicated => try self.drawReplicated(scratch, cache, draw_state, seg, seg_words),
                }
            }
        }

        const ScissorRestore = struct {
            was_enabled: bool,
            prev_box: [4]gl.GLint,

            fn restore(self: ScissorRestore) void {
                gl.glScissor(self.prev_box[0], self.prev_box[1], self.prev_box[2], self.prev_box[3]);
                if (!self.was_enabled) gl.glDisable(gl.GL_SCISSOR_TEST);
            }
        };

        fn applyScissor(rect: snail_mod.PixelRect, surface_height: f32) ScissorRestore {
            var prev_box: [4]gl.GLint = .{ 0, 0, 0, 0 };
            gl.glGetIntegerv(gl.GL_SCISSOR_BOX, &prev_box[0]);
            const was_enabled = gl.glIsEnabled(gl.GL_SCISSOR_TEST) == gl.GL_TRUE;
            gl.glEnable(gl.GL_SCISSOR_TEST);
            const h_i: gl.GLint = @intFromFloat(@max(surface_height, 0.0));
            const gl_y: gl.GLint = h_i - rect.y - @as(gl.GLint, @intCast(rect.h));
            gl.glScissor(rect.x, gl_y, @intCast(rect.w), @intCast(rect.h));
            return .{ .was_enabled = was_enabled, .prev_box = prev_box };
        }

        fn ensureHeterogeneousVaoBound(self: *GlTextState) void {
            if (self.cached_heterogeneous_vao_bound) return;
            gl.glBindVertexArray(self.vao);
            if (comptime backend == .gl33) gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
            self.cached_heterogeneous_vao_bound = true;
            self.cached_replicated_vao_bound = false;
        }

        fn ensureReplicatedVaoBound(self: *GlTextState) void {
            if (self.cached_replicated_vao_bound) return;
            gl.glBindVertexArray(self.vao_replicated);
            self.cached_replicated_vao_bound = true;
            self.cached_heterogeneous_vao_bound = false;
        }

        fn drawHeterogeneous(self: *GlTextState, cache: *const GlBackendCache, draw_state: DrawState, vertices: []const u32, seg_kind_mask: u8) DrawError!void {
            const total_glyphs = vertices.len / vertex.WORDS_PER_INSTANCE;
            if (total_glyphs == 0) return;
            self.ensureHeterogeneousVaoBound();

            const allow_subpixel = true;

            // emit tags every segment with a kind_mask bitset. When only
            // one bit is set, every shape in the segment uses the same
            // program — issue one dispatch and skip the per-instance
            // run-kind walk. Multi-kind segments still go through the
            // generic walk; segments with a missing/legacy zero mask
            // also fall through for safety.
            if (seg_kind_mask != 0 and @popCount(seg_kind_mask) == 1) {
                const run_kind: subpixel_policy.GlyphRunKind = switch (seg_kind_mask) {
                    draw_records_mod.KIND_BIT_REGULAR => .regular,
                    draw_records_mod.KIND_BIT_COLR => .colr,
                    draw_records_mod.KIND_BIT_PATH => .path,
                    draw_records_mod.KIND_BIT_HINTED_TEXT => .hinted_text,
                    draw_records_mod.KIND_BIT_AUTOHINT => .autohint,
                    else => unreachable,
                };
                const run_mode: subpixel_policy.TextRenderMode = if (run_kind != .regular)
                    .grayscale
                else
                    subpixel_policy.chooseBaseTextRenderMode(
                        draw_state.mvp,
                        allow_subpixel,
                        draw_state.raster.subpixel_order,
                        self.supports_dual_source_blend,
                    );
                self.setBlendMode(textBlendMode(run_kind != .regular, run_mode));
                const prog_state = switch (run_kind) {
                    .regular => switch (run_mode) {
                        .grayscale => &self.text_program,
                        .subpixel_dual_source => &self.text_subpixel_dual_program,
                    },
                    .colr => self.ensureColrProgram(),
                    .path => self.ensurePathProgram(),
                    .hinted_text => self.ensureHintedTextProgram(),
                    .autohint => self.ensureAutohintProgram(),
                };
                self.bindProgramState(cache, prog_state, draw_state, run_mode);
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
                        self.supports_dual_source_blend,
                    );
                self.setBlendMode(textBlendMode(run_kind != .regular, run_mode));
                const prog_state = switch (run_kind) {
                    .regular => switch (run_mode) {
                        .grayscale => &self.text_program,
                        .subpixel_dual_source => &self.text_subpixel_dual_program,
                    },
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

        /// Real hardware GPU instancing for the replicated path. The
        /// shape stream uses divisor M so that within one
        /// `glDrawElementsInstanced(..., M)` call all M GPU instances
        /// see the same shape; the override stream uses divisor 1 so
        /// each instance picks up a different override. To handle N>1
        /// shapes without OOB reads on the override stream (it has only
        /// M entries), the draw is issued once per shape with the shape
        /// binding's buffer offset shifted by s × `BYTES_PER_INSTANCE`. The
        /// replicated vertex shader composes shape × override
        /// per-instance and emits the final pixel.
        ///
        /// `scratch` is unused on this path — the whole point of GPU
        /// instancing is avoiding the N*M CPU-side composition.
        fn drawReplicated(
            self: *GlTextState,
            _: std.mem.Allocator,
            cache: *const GlBackendCache,
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

            // Upload shape + override data into the replicated VBO (laid
            // out contiguously by emit).
            self.ensureReplicatedVaoBound();
            if (comptime backend == .gl44) {
                gl.glNamedBufferData(self.vbo_replicated, @intCast(total_bytes), src_ptr, gl.GL_STREAM_DRAW);
                gl.glVertexArrayVertexBuffer(self.vao_replicated, 1, self.vbo_replicated, @intCast(shape_bytes), 32);
                if (self.replicated_shape_divisor != m) {
                    gl.glVertexArrayBindingDivisor(self.vao_replicated, 0, m);
                    self.replicated_shape_divisor = m;
                }
            } else {
                gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo_replicated);
                gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(total_bytes), src_ptr, gl.GL_STREAM_DRAW);
                if (self.replicated_shape_divisor != m) {
                    inline for (0..9) |i| gl.glVertexAttribDivisor(@intCast(i), m);
                    inline for (9..12) |i| gl.glVertexAttribDivisor(@intCast(i), 1);
                    self.replicated_shape_divisor = m;
                }
            }

            const allow_subpixel = true;
            const shape_words_view = seg_words[0 .. @as(usize, n) * vertex.WORDS_PER_INSTANCE];

            // Walk shape kind-runs. For each shape in a run, shift the
            // shape vertex binding to that shape's offset and issue an
            // instanced draw of M instances (one per override).
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
                        self.supports_dual_source_blend,
                    );
                self.setBlendMode(textBlendMode(run_kind != .regular, run_mode));
                const prog_state = switch (run_kind) {
                    .regular => switch (run_mode) {
                        .grayscale => &self.text_program_replicated,
                        .subpixel_dual_source => &self.text_subpixel_dual_program_replicated,
                    },
                    .colr => &self.colr_program_replicated,
                    .path => &self.path_program_replicated,
                    .hinted_text => &self.hinted_text_program_replicated,
                    .autohint => &self.autohint_program_replicated,
                };
                self.bindProgramState(cache, prog_state, draw_state, run_mode);
                var s: usize = run_start;
                while (s < run_end_in_shapes) : (s += 1) {
                    const shape_base: usize = s * vertex.BYTES_PER_INSTANCE;
                    if (comptime backend == .gl44) {
                        gl.glVertexArrayVertexBuffer(self.vao_replicated, 0, self.vbo_replicated, @intCast(shape_base), vertex.BYTES_PER_INSTANCE);
                    } else {
                        setupReplicatedVertexAttribs33(shape_base, shape_bytes);
                    }
                    gl.glDrawElementsInstanced(gl.GL_TRIANGLES, 6, gl.GL_UNSIGNED_INT, null, @intCast(m));
                }
                run_start = run_end_in_shapes;
            }

            // Restore the main heterogeneous VAO for any subsequent
            // segments in the same draw invocation.
            gl.glBindVertexArray(self.vao);
            if (comptime backend == .gl33) gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
        }

        /// Bind one GlBackendCache' texture set + uniforms. Texture-unit
        /// sampler bindings and `u_layer_base` are set once at program
        /// load (see programs.zig) and never need to be re-set here. The
        /// per-call uniforms (mvp/viewport/subpixel_order/output_srgb/
        /// coverage_exponent) are shadow-cached per program so steady-
        /// state frames upload only what actually changed.
        fn bindProgramState(self: *GlTextState, cache: *const GlBackendCache, prog_state: *const ProgramState, draw_state: DrawState, render_mode: subpixel_policy.TextRenderMode) void {
            const program_changed = prog_state.handle != self.active_program or !self.frame_begun;
            if (program_changed) {
                gl.glUseProgram(prog_state.handle);
                self.active_program = prog_state.handle;
                self.frame_begun = true;
            }

            // Rebind on program change too, not just cache change: the layer /
            // image sampler binding is *program-dependent* (a path/colr program
            // samples `u_layer_tex` on unit 2, the text program doesn't), so a
            // text→path switch on the same cache must (re)bind unit 2 for path.
            const cache_changed = self.active_cache != cache or program_changed;
            if (cache_changed) {
                self.active_cache = cache;
                if (comptime backend == .gl44) {
                    gl.glBindTextureUnit(0, cache.curve_array);
                    gl.glBindTextureUnit(1, cache.band_array);
                    if (prog_state.layer_tex_loc >= 0 and cache.layer_info_tex != 0) gl.glBindTextureUnit(2, cache.layer_info_tex);
                    if (prog_state.image_tex_loc >= 0 and cache.image_array_tex != 0) gl.glBindTextureUnit(3, cache.image_array_tex);
                } else {
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
                }
            }

            const cache_slot = self.programUniformCache(prog_state.handle);

            if (!cache_slot.mvp_set or !std.mem.eql(f32, &cache_slot.mvp_data, &draw_state.mvp.data)) {
                gl.glUniformMatrix4fv(prog_state.mvp_loc, 1, gl.GL_FALSE, &draw_state.mvp.data);
                cache_slot.mvp_data = draw_state.mvp.data;
                cache_slot.mvp_set = true;
            }
            const vw = draw_state.surface.pixel_width;
            const vh = draw_state.surface.pixel_height;
            if (!cache_slot.viewport_set or cache_slot.viewport[0] != vw or cache_slot.viewport[1] != vh) {
                gl.glUniform2f(prog_state.viewport_loc, vw, vh);
                cache_slot.viewport = .{ vw, vh };
                cache_slot.viewport_set = true;
            }
            if (prog_state.subpixel_order_loc >= 0) {
                const order: i32 = @intFromEnum(if (render_mode == .grayscale) SubpixelOrder.none else draw_state.raster.subpixel_order);
                if (!cache_slot.subpixel_order_set or cache_slot.subpixel_order != order) {
                    gl.glUniform1i(prog_state.subpixel_order_loc, order);
                    cache_slot.subpixel_order = order;
                    cache_slot.subpixel_order_set = true;
                }
            }
            if (prog_state.output_srgb_loc >= 0) {
                const output_srgb: i32 = @intFromBool(draw_state.surface.encoding.shaderEncodesSrgb() and !self.linear_resolve.active);
                if (!cache_slot.output_srgb_set or cache_slot.output_srgb != output_srgb) {
                    gl.glUniform1i(prog_state.output_srgb_loc, output_srgb);
                    cache_slot.output_srgb = output_srgb;
                    cache_slot.output_srgb_set = true;
                }
            }
            if (prog_state.coverage_exponent_loc >= 0) {
                const exp = draw_state.raster.coverage_transfer.shaderExponent();
                if (!cache_slot.coverage_exponent_set or cache_slot.coverage_exponent != exp) {
                    gl.glUniform1f(prog_state.coverage_exponent_loc, exp);
                    cache_slot.coverage_exponent = exp;
                    cache_slot.coverage_exponent_set = true;
                }
            }
            if (prog_state.dither_scale_loc >= 0) {
                gl.glUniform1f(prog_state.dither_scale_loc, draw_state.surface.format.ditherAmplitude());
            }
            if (prog_state.mask_output_loc >= 0) {
                gl.glUniform1i(prog_state.mask_output_loc, if (draw_state.surface.format.hasColor()) 0 else 1);
            }
        }

        /// Return the shadow-cache slot for `program`, allocating one
        /// on first sighting. The slot array is small (10 entries —
        /// regular + replicated × {text, text-subpixel, colr, path,
        /// hinted_text}); a linear scan is faster than a hashmap at
        /// this size and keeps `bindProgramState` allocation-free.
        fn programUniformCache(self: *GlTextState, program: gl.GLuint) *ProgramUniformCache {
            for (self.program_uniform_caches[0..self.program_cache_count]) |*slot| {
                if (slot.program == program) return slot;
            }
            std.debug.assert(self.program_cache_count < self.program_uniform_caches.len);
            const slot = &self.program_uniform_caches[self.program_cache_count];
            self.program_cache_count += 1;
            slot.* = .{ .program = program };
            return slot;
        }

        /// Invalidate every shadow cache. Called when the renderer's
        /// trust in driver-side uniform state is broken — i.e. after a
        /// linear-resolve pass binds its own program + uniforms.
        fn invalidateUniformShadows(self: *GlTextState) void {
            for (self.program_uniform_caches[0..self.program_cache_count]) |*slot| {
                slot.mvp_set = false;
                slot.viewport_set = false;
                slot.subpixel_order_set = false;
                slot.output_srgb_set = false;
                slot.coverage_exponent_set = false;
            }
            self.active_program = 0;
            self.active_cache = null;
            self.cached_blend_mode = .uninitialized;
            self.cached_replicated_vao_bound = false;
            self.cached_heterogeneous_vao_bound = false;
        }

        fn setBlendMode(self: *GlTextState, mode: BlendMode) void {
            if (self.cached_blend_mode == mode) return;
            applyBlendMode(mode);
            self.cached_blend_mode = mode;
        }

        pub fn beginDraw(self: *GlTextState) void {
            // Force the next bindProgramState to re-issue glUseProgram and
            // the next ensure*VaoBound to re-bind the VAO. This is the
            // begin/end boundary where snail loses track of foreign GL
            // mutations (clear, blit, app's own GL work); per-uniform
            // shadow values stay live across the boundary because the
            // values themselves don't change — only program/VAO bind
            // identity might.
            self.frame_begun = false;
            self.cached_heterogeneous_vao_bound = false;
            self.cached_replicated_vao_bound = false;

            // Re-assert the global blend/sRGB state snail's draw depends on.
            // Like the program/VAO bind above, this is foreign-mutable: the
            // app's own GL work between frames can change it (e.g. the game's
            // world pass disables GL_BLEND for opaque geometry, then draws the
            // HUD text). Invalidating `cached_blend_mode` forces the next
            // setBlendMode to actually re-issue glEnable(GL_BLEND) + blend func
            // instead of trusting its shadow; otherwise the first pass renders
            // unblended, writing premultiplied glyph edges opaque = hard/dark AA
            // fringes (worst on no-backing text over a varied background).
            self.cached_blend_mode = .uninitialized;
            gl.glEnable(gl.GL_FRAMEBUFFER_SRGB);

            if (comptime backend == .gl44) self.ring.beginFrame();
        }

        fn ensureColrProgram(self: *GlTextState) *const ProgramState {
            std.debug.assert(self.colr_program.handle != 0);
            return &self.colr_program;
        }

        fn ensurePathProgram(self: *GlTextState) *const ProgramState {
            std.debug.assert(self.path_program.handle != 0);
            return &self.path_program;
        }

        fn ensureHintedTextProgram(self: *GlTextState) *const ProgramState {
            std.debug.assert(self.hinted_text_program.handle != 0);
            return &self.hinted_text_program;
        }

        fn ensureAutohintProgram(self: *GlTextState) *const ProgramState {
            std.debug.assert(self.autohint_program.handle != 0);
            return &self.autohint_program;
        }

        fn drawGlyphRange(self: *GlTextState, vertices: []const u32, glyph_offset: usize, glyph_count: usize) void {
            var glyphs_drawn: usize = 0;
            while (glyphs_drawn < glyph_count) {
                const word_offset = (glyph_offset + glyphs_drawn) * vertex.WORDS_PER_INSTANCE;
                const remaining = glyph_count - glyphs_drawn;
                const max_byte_size = @min(remaining, MAX_GLYPHS_PER_SEGMENT) * BYTES_PER_GLYPH;
                const src: [*]const u8 = @ptrCast(vertices[word_offset..].ptr);

                var byte_size: usize = max_byte_size;
                if (comptime backend == .gl44) {
                    const grant = self.ring.reserve(max_byte_size, BYTES_PER_GLYPH);
                    byte_size = grant.bytes;
                    const dst = self.ring.map.?[grant.offset..][0..byte_size];
                    @memcpy(dst, src[0..byte_size]);

                    const stride: gl.GLint = vertex.BYTES_PER_INSTANCE;
                    gl.glVertexArrayVertexBuffer(self.vao, 0, self.vbo, @intCast(grant.offset), stride);
                } else {
                    gl.glBufferSubData(gl.GL_ARRAY_BUFFER, 0, @intCast(byte_size), src);
                }

                const chunk = byte_size / BYTES_PER_GLYPH;
                gl.glDrawElementsInstanced(gl.GL_TRIANGLES, 6, gl.GL_UNSIGNED_INT, null, @intCast(chunk));

                if (comptime backend == .gl44) self.ring.commit(byte_size);

                glyphs_drawn += chunk;
            }
        }
    };
}

pub const Gl33TextState = TextStateFor(.gl33);
pub const Gl44TextState = TextStateFor(.gl44);

// ── Renderer wrappers ──
//
// The demos call `snail.Gl33Renderer.init(allocator)` and access
// `.state` to drive draws. The allocator parameter is unused — text
// state has no heap allocations of its own — but the signature keeps
// the public API uniform across backends.

pub const Gl33Renderer = struct {
    state: Gl33TextState = .{},

    pub fn init(_: std.mem.Allocator) !Gl33Renderer {
        var self = Gl33Renderer{};
        try self.state.init();
        return self;
    }

    pub fn deinit(self: *Gl33Renderer) void {
        self.state.deinit();
    }
};

pub const Gl44Renderer = struct {
    state: Gl44TextState = .{},

    pub fn init(_: std.mem.Allocator) !Gl44Renderer {
        var self = Gl44Renderer{};
        try self.state.init();
        return self;
    }

    pub fn deinit(self: *Gl44Renderer) void {
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

fn setupVertexArrayAttribs(vao: gl.GLuint) void {
    setupVertexArrayAttrib(vao, 0, 4, gl.GL_HALF_FLOAT, gl.GL_FALSE, @offsetOf(vertex.Instance, "rect"));
    setupVertexArrayAttrib(vao, 1, 4, gl.GL_FLOAT, gl.GL_FALSE, @offsetOf(vertex.Instance, "xform"));
    setupVertexArrayAttrib(vao, 2, 2, gl.GL_FLOAT, gl.GL_FALSE, @offsetOf(vertex.Instance, "origin"));
    gl.glEnableVertexArrayAttrib(vao, 3);
    gl.glVertexArrayAttribIFormat(vao, 3, 2, gl.GL_UNSIGNED_INT, @intCast(@offsetOf(vertex.Instance, "glyph")));
    gl.glVertexArrayAttribBinding(vao, 3, 0);
    setupVertexArrayAttrib(vao, 4, 4, gl.GL_FLOAT, gl.GL_FALSE, @offsetOf(vertex.Instance, "band"));
    setupVertexArrayAttrib(vao, 5, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, @offsetOf(vertex.Instance, "color"));
    setupVertexArrayAttrib(vao, 6, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, @offsetOf(vertex.Instance, "tint"));
    gl.glEnableVertexArrayAttrib(vao, 7);
    gl.glVertexArrayAttribIFormat(vao, 7, 4, gl.GL_UNSIGNED_INT, @intCast(@offsetOf(vertex.Instance, "policy")));
    gl.glVertexArrayAttribBinding(vao, 7, 0);
    gl.glEnableVertexArrayAttrib(vao, 8);
    gl.glVertexArrayAttribIFormat(vao, 8, 3, gl.GL_UNSIGNED_INT, @intCast(@offsetOf(vertex.Instance, "policy") + 16));
    gl.glVertexArrayAttribBinding(vao, 8, 0);
}

fn setupVertexArrayAttrib(vao: gl.GLuint, loc: u32, components: gl.GLint, ty: gl.GLenum, normalized: gl.GLboolean, offset: usize) void {
    gl.glEnableVertexArrayAttrib(vao, loc);
    gl.glVertexArrayAttribFormat(vao, loc, components, ty, normalized, @intCast(offset));
    gl.glVertexArrayAttribBinding(vao, loc, 0);
}

/// DSA setup for the replicated VAO: same shape attributes as the
/// heterogeneous VAO bound to binding 0 (configurable divisor M), plus
/// policy attributes 7-8 on binding 0 and override attributes 9-11 on binding 1.
fn setupReplicatedVertexArrayAttribs(vao: gl.GLuint) void {
    // Shape attributes, binding 0.
    setupVertexArrayAttrib(vao, 0, 4, gl.GL_HALF_FLOAT, gl.GL_FALSE, @offsetOf(vertex.Instance, "rect"));
    setupVertexArrayAttrib(vao, 1, 4, gl.GL_FLOAT, gl.GL_FALSE, @offsetOf(vertex.Instance, "xform"));
    setupVertexArrayAttrib(vao, 2, 2, gl.GL_FLOAT, gl.GL_FALSE, @offsetOf(vertex.Instance, "origin"));
    gl.glEnableVertexArrayAttrib(vao, 3);
    gl.glVertexArrayAttribIFormat(vao, 3, 2, gl.GL_UNSIGNED_INT, @intCast(@offsetOf(vertex.Instance, "glyph")));
    gl.glVertexArrayAttribBinding(vao, 3, 0);
    setupVertexArrayAttrib(vao, 4, 4, gl.GL_FLOAT, gl.GL_FALSE, @offsetOf(vertex.Instance, "band"));
    setupVertexArrayAttrib(vao, 5, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, @offsetOf(vertex.Instance, "color"));
    setupVertexArrayAttrib(vao, 6, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, @offsetOf(vertex.Instance, "tint"));
    gl.glEnableVertexArrayAttrib(vao, 7);
    gl.glVertexArrayAttribIFormat(vao, 7, 4, gl.GL_UNSIGNED_INT, @intCast(@offsetOf(vertex.Instance, "policy")));
    gl.glVertexArrayAttribBinding(vao, 7, 0);
    gl.glEnableVertexArrayAttrib(vao, 8);
    gl.glVertexArrayAttribIFormat(vao, 8, 3, gl.GL_UNSIGNED_INT, @intCast(@offsetOf(vertex.Instance, "policy") + 16));
    gl.glVertexArrayAttribBinding(vao, 8, 0);
    // Override attributes, binding 1. Layout matches `emit.writeOverride`:
    // bytes 0-15  = vec4 (xx, xy, tx, yx)
    // bytes 16-23 = vec2 (yy, ty); the shader reads only the first two
    //               components of b_xform_b, so byte 24-31 (packed tint
    //               + pad) safely cohabit the same vec4 slot.
    // bytes 24-27 = packed u8x4 tint (read as b_tint with normalized u8)
    gl.glEnableVertexArrayAttrib(vao, 9);
    gl.glVertexArrayAttribFormat(vao, 9, 4, gl.GL_FLOAT, gl.GL_FALSE, 0);
    gl.glVertexArrayAttribBinding(vao, 9, 1);
    gl.glEnableVertexArrayAttrib(vao, 10);
    gl.glVertexArrayAttribFormat(vao, 10, 4, gl.GL_FLOAT, gl.GL_FALSE, 16);
    gl.glVertexArrayAttribBinding(vao, 10, 1);
    gl.glEnableVertexArrayAttrib(vao, 11);
    gl.glVertexArrayAttribFormat(vao, 11, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, 24);
    gl.glVertexArrayAttribBinding(vao, 11, 1);
}

/// Classic (non-DSA) setup for the GL 3.3 replicated VAO. Both shape
/// and override attributes read from the same bound VBO; absolute byte
/// offsets are derived from `shape_base` and `override_base`.
fn setupReplicatedVertexAttribs33(shape_base: usize, override_base: usize) void {
    const shape_stride: gl.GLsizei = vertex.BYTES_PER_INSTANCE;
    setupVertexAttrib(0, 4, gl.GL_HALF_FLOAT, gl.GL_FALSE, shape_stride, shape_base + @offsetOf(vertex.Instance, "rect"));
    setupVertexAttrib(1, 4, gl.GL_FLOAT, gl.GL_FALSE, shape_stride, shape_base + @offsetOf(vertex.Instance, "xform"));
    setupVertexAttrib(2, 2, gl.GL_FLOAT, gl.GL_FALSE, shape_stride, shape_base + @offsetOf(vertex.Instance, "origin"));
    gl.glVertexAttribIPointer(3, 2, gl.GL_UNSIGNED_INT, shape_stride, @ptrFromInt(shape_base + @offsetOf(vertex.Instance, "glyph")));
    gl.glEnableVertexAttribArray(3);
    setupVertexAttrib(4, 4, gl.GL_FLOAT, gl.GL_FALSE, shape_stride, shape_base + @offsetOf(vertex.Instance, "band"));
    setupVertexAttrib(5, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, shape_stride, shape_base + @offsetOf(vertex.Instance, "color"));
    setupVertexAttrib(6, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, shape_stride, shape_base + @offsetOf(vertex.Instance, "tint"));
    gl.glVertexAttribIPointer(7, 4, gl.GL_UNSIGNED_INT, shape_stride, @ptrFromInt(shape_base + @offsetOf(vertex.Instance, "policy")));
    gl.glEnableVertexAttribArray(7);
    gl.glVertexAttribIPointer(8, 3, gl.GL_UNSIGNED_INT, shape_stride, @ptrFromInt(shape_base + @offsetOf(vertex.Instance, "policy") + 16));
    gl.glEnableVertexAttribArray(8);
    const override_stride: gl.GLsizei = 32;
    setupVertexAttrib(9, 4, gl.GL_FLOAT, gl.GL_FALSE, override_stride, override_base + 0);
    setupVertexAttrib(10, 4, gl.GL_FLOAT, gl.GL_FALSE, override_stride, override_base + 16);
    setupVertexAttrib(11, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, override_stride, override_base + 24);
}

fn initEbo() void {
    // Single quad index pattern — instancing repeats it per glyph.
    const indices = [6]u32{ 0, 1, 2, 0, 2, 3 };
    gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(indices)), &indices, gl.GL_STATIC_DRAW);
}

// ── Shader compilation ──

const linear_resolve_vertex_shader: [:0]const u8 =
    \\#version 330 core
    \\out vec2 v_uv;
    \\void main() {
    \\    vec2 pos = vec2((gl_VertexID == 1) ? 3.0 : -1.0,
    \\                    (gl_VertexID == 2) ? 3.0 : -1.0);
    \\    v_uv = pos * 0.5 + 0.5;
    \\    gl_Position = vec4(pos, 0.0, 1.0);
    \\}
;

const linear_resolve_fragment_shader: [:0]const u8 =
    \\#version 330 core
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

fn applyBlendMode(mode: BlendMode) void {
    switch (mode) {
        .uninitialized => unreachable,
        .dual_source => {
            gl.glEnable(gl.GL_BLEND);
            gl.glBlendFuncSeparate(gl.GL_ONE, gl.GL_ONE_MINUS_SRC1_COLOR, gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
        },
        .normal => {
            gl.glEnable(gl.GL_BLEND);
            gl.glBlendFuncSeparate(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA, gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
        },
    }
}

fn textBlendMode(special: bool, render_mode: subpixel_policy.TextRenderMode) BlendMode {
    if (!special and render_mode == .subpixel_dual_source) return .dual_source;
    return .normal;
}

const BlendMode = enum { uninitialized, normal, dual_source };

fn detectDualSourceBlendSupport() bool {
    var max_draw_buffers: gl.GLint = 0;
    gl.glGetIntegerv(gl.GL_MAX_DUAL_SOURCE_DRAW_BUFFERS, &max_draw_buffers);
    return max_draw_buffers >= 1;
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
