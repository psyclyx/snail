const std = @import("std");
const gl = @import("bindings.zig").gl;
const gl_backend = @import("detect.zig");
const gl_programs = @import("programs.zig");
const gl_upload = @import("../device_atlas.zig");
const ring_buffer_mod = @import("ring_buffer.zig");
const RingBuffer = ring_buffer_mod.RingBuffer;
const gl_common = @import("../common.zig");
const linear_resolve = @import("../linear_resolve.zig");
const draw_records_mod = @import("snail").render.records;
const shaders = @import("../shaders.zig").Gl330;
const vertex = @import("snail").render.records;
const snail_mod = @import("snail");
const render_state = @import("render-state");
const SubpixelOrder = @import("render-state").SubpixelOrder;
const LinearResolve = render_state.LinearResolve;
const DrawState = render_state.DrawState;
const TargetSurface = render_state.TargetSurface;

const ShapeKind = draw_records_mod.ShapeKind;
const TextRenderMode = enum { grayscale, subpixel_dual_source };

fn textRenderMode(order: SubpixelOrder, supports_dual_source: bool) TextRenderMode {
    if (order != .none and supports_dual_source) return .subpixel_dual_source;
    return .grayscale;
}

/// Whether a shape kind has an LCD dual-source program (the three text
/// kinds). colr/path always render premultiplied grayscale.
fn kindHasSubpixelProgram(kind: ShapeKind) bool {
    return switch (kind) {
        .regular, .tt_hinted_text, .autohint => true,
        .colr, .path => false,
    };
}

pub const LinearResolveRestore = gl_common.LinearResolveRestore;

const LinearResolveState = linear_resolve.StateFor(gl, .{
    .vertex_shader = shaders.native_linear_resolve_vertex_shader,
    .fragment_shader = shaders.native_linear_resolve_fragment_shader,
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
        tt_hinted_text_program: ProgramState = .{},
        tt_hinted_subpixel_dual_program: ProgramState = .{},
        autohint_program: ProgramState = .{},
        autohint_subpixel_dual_program: ProgramState = .{},
        linear_resolve: LinearResolveState = .{},
        vao: gl.GLuint = 0,
        vbo: gl.GLuint = 0,
        ebo: gl.GLuint = 0,
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
        active_cache: ?*const GlDeviceAtlas = null,
        program_cache_count: usize = 0,
        program_uniform_caches: [8]ProgramUniformCache = [_]ProgramUniformCache{.{}} ** 8,
        // Per-draw GL state shadows.
        cached_blend_mode: BlendMode = .uninitialized,
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
            // Native-Slang text program only: shadow of the last-uploaded
            // 96-byte UBO block.
            push_block_set: bool = false,
            push_block: gl_common.NativeTextPushBlock = undefined,
        };

        // ── Init / Deinit ──

        pub fn init(self: *GlTextState) !void {
            if (comptime backend == .gl44) {
                if (gl_backend.detect(gl) != .gl44) return error.UnsupportedOpenGlBackend;
            }
            self.supports_dual_source_blend = detectDualSourceBlendSupport();
            errdefer self.deinit();

            // Link all draw programs during renderer init so draw never compiles or links.
            // Regular text and colr use the native-Slang generated shaders
            // (stages A/B of the Slang cutover); the remaining families keep
            // the composed GLSL-fragment catalog. The fragment-only native
            // families share the native text vertex stage.
            self.text_program = try gl_programs.loadNativeProgramState("text-native", shaders.native_text_vertex_shader, shaders.native_text_fragment_shader);
            self.colr_program = try gl_programs.loadNativeProgramState("colr-native", shaders.native_text_vertex_shader, shaders.native_colr_fragment_shader);
            self.path_program = try gl_programs.loadNativeProgramState("path-native", shaders.native_text_vertex_shader, shaders.native_path_fragment_shader);
            self.tt_hinted_text_program = try gl_programs.loadNativeProgramState("hinted-text-native", shaders.native_text_vertex_shader, shaders.native_tt_hinted_fragment_shader);
            self.autohint_program = try gl_programs.loadNativeProgramState("autohint-native", shaders.native_autohint_vertex_shader, shaders.native_autohint_fragment_shader);
            if (self.supports_dual_source_blend) {
                // Native subpixel fragments carry their own
                // layout(location = 0, index = N) qualifiers, so no
                // glBindFragDataLocationIndexed calls are needed.
                self.text_subpixel_dual_program = try gl_programs.loadNativeProgramState("text-subpixel-native", shaders.native_text_vertex_shader, shaders.native_subpixel_fragment_shader);
                self.tt_hinted_subpixel_dual_program = try gl_programs.loadNativeProgramState("hinted-subpixel-native", shaders.native_text_vertex_shader, shaders.native_tt_hinted_subpixel_fragment_shader);
                self.autohint_subpixel_dual_program = try gl_programs.loadNativeProgramState("autohint-subpixel-native", shaders.native_autohint_vertex_shader, shaders.native_autohint_subpixel_fragment_shader);
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
        }

        pub fn deinit(self: *GlTextState) void {
            if (comptime backend == .gl44) {
                self.ring.deinit(self.vbo);
            }

            deleteProgramState(&self.text_program);
            deleteProgramState(&self.text_subpixel_dual_program);
            deleteProgramState(&self.colr_program);
            deleteProgramState(&self.path_program);
            deleteProgramState(&self.tt_hinted_text_program);
            deleteProgramState(&self.tt_hinted_subpixel_dual_program);
            deleteProgramState(&self.autohint_program);
            deleteProgramState(&self.autohint_subpixel_dual_program);
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
        const GlDeviceAtlas = gl_upload.GlDeviceAtlasFor(gl_upload_variant);

        pub const DrawError = error{
            MissingBinding,
            StaleBinding,
        } || draw_records_mod.DrawRecords.ValidationError || std.mem.Allocator.Error;

        /// Walk `DrawRecords.batches`, bind each batch's matching
        /// `GlDeviceAtlas` cache, dispatch the encoded instances through
        /// the existing program set.
        pub fn draw(
            self: *GlTextState,
            scratch: std.mem.Allocator,
            draw_state: DrawState,
            records: draw_records_mod.DrawRecords,
            caches: []const *const GlDeviceAtlas,
        ) DrawError!void {
            try records.validate();
            // Apply `draw_state.scissor_rect` via `GL_SCISSOR_TEST`. We
            // save / restore both the enable flag and the rect so a
            // surrounding linear-resolve pass (which uses scissor too)
            // is undisturbed. The scissor coordinate system is GL's
            // y-up framebuffer space, so we flip from snail's y-down
            // `PixelRect`.
            const scissor_restore: ?ScissorRestore = if (draw_state.scissor_rect) |rect|
                applyScissor(rect, @floatFromInt(draw_state.surface.pixel_height))
            else
                null;
            defer if (scissor_restore) |r| r.restore();

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

        const ScissorRestore = struct {
            was_enabled: bool,
            prev_box: [4]gl.GLint,

            fn restore(self: ScissorRestore) void {
                gl.glScissor(self.prev_box[0], self.prev_box[1], self.prev_box[2], self.prev_box[3]);
                if (!self.was_enabled) gl.glDisable(gl.GL_SCISSOR_TEST);
            }
        };

        fn applyScissor(rect: render_state.PixelRect, surface_height: f32) ScissorRestore {
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
        }

        fn drawBatch(self: *GlTextState, cache: *const GlDeviceAtlas, draw_state: DrawState, instances: []const vertex.Instance, kind: ShapeKind) DrawError!void {
            const total_glyphs = instances.len;
            if (total_glyphs == 0) return;
            self.ensureHeterogeneousVaoBound();

            const run_mode: TextRenderMode = if (kindHasSubpixelProgram(kind))
                textRenderMode(draw_state.raster.subpixel_order, self.supports_dual_source_blend)
            else
                .grayscale;
            self.setBlendMode(textBlendMode(run_mode));
            const prog_state = switch (kind) {
                .regular => switch (run_mode) {
                    .grayscale => &self.text_program,
                    .subpixel_dual_source => &self.text_subpixel_dual_program,
                },
                .colr => self.ensureColrProgram(),
                .path => self.ensurePathProgram(),
                .tt_hinted_text => switch (run_mode) {
                    .grayscale => self.ensureTtHintedTextProgram(),
                    .subpixel_dual_source => &self.tt_hinted_subpixel_dual_program,
                },
                .autohint => switch (run_mode) {
                    .grayscale => self.ensureAutohintProgram(),
                    .subpixel_dual_source => &self.autohint_subpixel_dual_program,
                },
            };
            self.bindProgramState(cache, prog_state, draw_state, run_mode);
            self.drawGlyphRange(instances, 0, total_glyphs);
        }

        /// Bind one GlDeviceAtlas' texture set + uniforms. Texture-unit
        /// sampler bindings and `u_layer_base` are set once at program
        /// load (see programs.zig) and never need to be re-set here. The
        /// per-call uniforms (mvp/viewport/subpixel_order/output_srgb/
        /// coverage_exponent) are shadow-cached per program so steady-
        /// state frames upload only what actually changed.
        fn bindProgramState(self: *GlTextState, cache: *const GlDeviceAtlas, prog_state: *const ProgramState, draw_state: DrawState, render_mode: TextRenderMode) void {
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

            // Native-Slang text program: every per-draw parameter lives in
            // one 96-byte UBO block; upload it when it changed and (re)bind
            // the buffer to the block binding point. Loose-uniform locs are
            // all -1 for this program, so the code below is a no-op for it —
            // return early instead of probing them.
            if (prog_state.ubo != 0) {
                const order: i32 = @intFromEnum(if (render_mode == .grayscale) SubpixelOrder.none else draw_state.raster.subpixel_order);
                const block = gl_common.NativeTextPushBlock{
                    .mvp = draw_state.mvp.data,
                    .viewport = .{ @floatFromInt(draw_state.surface.pixel_width), @floatFromInt(draw_state.surface.pixel_height) },
                    .subpixel_order = order,
                    .output_srgb = @intFromBool(draw_state.surface.encoding.shaderEncodesSrgb() and !self.linear_resolve.active),
                    .layer_base = 0,
                    .coverage_exponent = draw_state.raster.coverage_transfer.shaderExponent(),
                    .dither_scale = draw_state.surface.format.ditherAmplitude(),
                    .mask_output = if (draw_state.surface.format.hasColor()) 0 else 1,
                };
                gl.glBindBufferBase(gl.GL_UNIFORM_BUFFER, gl_common.NATIVE_TEXT_UBO_BINDING, prog_state.ubo);
                if (!cache_slot.push_block_set or !std.mem.eql(u8, std.mem.asBytes(&cache_slot.push_block), std.mem.asBytes(&block))) {
                    gl.glBufferSubData(gl.GL_UNIFORM_BUFFER, 0, @sizeOf(gl_common.NativeTextPushBlock), &block);
                    cache_slot.push_block = block;
                    cache_slot.push_block_set = true;
                }
                return;
            }

            if (!cache_slot.mvp_set or !std.mem.eql(f32, &cache_slot.mvp_data, &draw_state.mvp.data)) {
                gl.glUniformMatrix4fv(prog_state.mvp_loc, 1, gl.GL_FALSE, &draw_state.mvp.data);
                cache_slot.mvp_data = draw_state.mvp.data;
                cache_slot.mvp_set = true;
            }
            const vw: f32 = @floatFromInt(draw_state.surface.pixel_width);
            const vh: f32 = @floatFromInt(draw_state.surface.pixel_height);
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
        /// on first sighting. The slot array is small (eight entries —
        /// text, colr, path, hinted text, autohint, and the three
        /// dual-source subpixel variants); a linear scan is faster than
        /// a hashmap at this size and keeps `bindProgramState`
        /// allocation-free.
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
                slot.push_block_set = false;
            }
            self.active_program = 0;
            self.active_cache = null;
            self.cached_blend_mode = .uninitialized;
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

        fn ensureTtHintedTextProgram(self: *GlTextState) *const ProgramState {
            std.debug.assert(self.tt_hinted_text_program.handle != 0);
            return &self.tt_hinted_text_program;
        }

        fn ensureAutohintProgram(self: *GlTextState) *const ProgramState {
            std.debug.assert(self.autohint_program.handle != 0);
            return &self.autohint_program;
        }

        fn drawGlyphRange(self: *GlTextState, instances: []const vertex.Instance, glyph_offset: usize, glyph_count: usize) void {
            var glyphs_drawn: usize = 0;
            while (glyphs_drawn < glyph_count) {
                const instance_offset = glyph_offset + glyphs_drawn;
                const remaining = glyph_count - glyphs_drawn;
                const max_byte_size = @min(remaining, MAX_GLYPHS_PER_SEGMENT) * BYTES_PER_GLYPH;
                const src: [*]const u8 = @ptrCast(instances[instance_offset..].ptr);

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
// The demos call this module's `Gl33Renderer.init(allocator)` and access
// `.state` to drive draws. The allocator parameter is unused — text state
// has no heap allocations of its own — but the signature keeps the demo
// wrappers uniform across backends.

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

fn setupVertexArrayAttribs(vao: gl.GLuint) void {
    setupVertexArrayAttrib(vao, 0, 4, gl.GL_HALF_FLOAT, gl.GL_FALSE, @offsetOf(vertex.Instance, "rect"));
    setupVertexArrayAttrib(vao, 1, 4, gl.GL_FLOAT, gl.GL_FALSE, @offsetOf(vertex.Instance, "xform"));
    setupVertexArrayAttrib(vao, 2, 2, gl.GL_FLOAT, gl.GL_FALSE, @offsetOf(vertex.Instance, "origin"));
    gl.glEnableVertexArrayAttrib(vao, 3);
    gl.glVertexArrayAttribIFormat(vao, 3, 2, gl.GL_UNSIGNED_INT, @intCast(@offsetOf(vertex.Instance, "glyph")));
    gl.glVertexArrayAttribBinding(vao, 3, 0);
    gl.glEnableVertexArrayAttrib(vao, 4);
    gl.glVertexArrayAttribIFormat(vao, 4, 4, gl.GL_UNSIGNED_INT, @intCast(@offsetOf(vertex.Instance, "payload")));
    gl.glVertexArrayAttribBinding(vao, 4, 0);
    setupVertexArrayAttrib(vao, 5, 4, gl.GL_HALF_FLOAT, gl.GL_FALSE, @offsetOf(vertex.Instance, "color"));
    setupVertexArrayAttrib(vao, 6, 4, gl.GL_HALF_FLOAT, gl.GL_FALSE, @offsetOf(vertex.Instance, "tint"));
}

fn setupVertexArrayAttrib(vao: gl.GLuint, loc: u32, components: gl.GLint, ty: gl.GLenum, normalized: gl.GLboolean, offset: usize) void {
    gl.glEnableVertexArrayAttrib(vao, loc);
    gl.glVertexArrayAttribFormat(vao, loc, components, ty, normalized, @intCast(offset));
    gl.glVertexArrayAttribBinding(vao, loc, 0);
}

fn initEbo() void {
    // Single quad index pattern — instancing repeats it per glyph.
    const indices = [6]u32{ 1, 2, 0, 2, 3, 0 };
    gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(indices)), &indices, gl.GL_STATIC_DRAW);
}

// ── Shader compilation ──

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

fn textBlendMode(render_mode: TextRenderMode) BlendMode {
    // `render_mode` is already forced to .grayscale for kinds without a
    // dual-source program (colr/path), so the mode alone decides the blend.
    if (render_mode == .subpixel_dual_source) return .dual_source;
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
    binding: draw_records_mod.Binding,
) ?@TypeOf(caches[0]) {
    for (caches) |c| {
        if (c.isBindingLive(binding)) return c;
    }
    return null;
}
