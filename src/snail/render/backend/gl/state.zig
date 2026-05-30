const std = @import("std");
const gl = @import("bindings.zig").gl;
const gl_backend = @import("backend.zig");
const gl_programs = @import("programs.zig");
const gl_resources = @import("resources.zig");
const gl_upload = @import("prepared_pages.zig");
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
pub const Gl33PreparedResources = gl_resources.Gl33PreparedResources;
pub const Gl44PreparedResources = gl_resources.Gl44PreparedResources;

pub const text_vertex_interface = shaders.text_vertex_interface;
pub const text_fragment_interface = shaders.text_fragment_interface;
pub const text_coverage_fragment_interface = shaders.text_coverage_fragment_interface;
pub const text_sample_interface = shaders.text_sample_interface;
pub const text_fragment_body = shaders.text_fragment_body;
pub const text_coverage_fragment_body = shaders.text_coverage_fragment_body;
pub const text_sample_body = shaders.text_sample_body;

// ── GL 4.4 persistent mapping constants ──

const RING_SEGMENTS = 3;
const RING_TOTAL_BYTES = 12 * 1024 * 1024; // 12 MB (4 MB per segment)
const RING_SEGMENT_BYTES = RING_TOTAL_BYTES / RING_SEGMENTS;
const GL33_STREAM_BYTES = RING_SEGMENT_BYTES;
const BYTES_PER_GLYPH = vertex.BYTES_PER_INSTANCE;
const MAX_GLYPHS_PER_SEGMENT = RING_SEGMENT_BYTES / BYTES_PER_GLYPH;

// ── GL text state ──

pub const LinearResolveRestore = struct {
    draw_fbo: gl.GLint = 0,
    read_fbo: gl.GLint = 0,
    viewport: [4]gl.GLint = .{ 0, 0, 0, 0 },
    resolve_rect: PixelRect = .{},
    depth_test: bool = false,
    scissor_test: bool = false,
    blend: bool = false,
};

fn TextStateFor(comptime backend: Backend) type {
    return struct {
        const GlTextState = @This();
        const PreparedResources = switch (backend) {
            .gl33 => Gl33PreparedResources,
            .gl44 => Gl44PreparedResources,
        };

        text_program: ProgramState = .{},
        text_subpixel_dual_program: ProgramState = .{},
        colr_program: ProgramState = .{},
        path_program: ProgramState = .{},
        hinted_text_program: ProgramState = .{},
        // Replicated variants: same fragment, vertex shader composes
        // shape × override via per-attribute divisor. Used by the new-API
        // replicated DrawSegment to issue N*M hardware-instanced draws.
        text_program_replicated: ProgramState = .{},
        text_subpixel_dual_program_replicated: ProgramState = .{},
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
        active_resource_bank_id: u32 = std.math.maxInt(u32),
        frame_begun: bool = false,
        supports_dual_source_blend: bool = false,
        persistent_map: ?[*]u8 = null,
        ring_fences: [RING_SEGMENTS]gl.GLsync = .{null} ** RING_SEGMENTS,
        ring_segment: u32 = 0,
        ring_offset: usize = 0,
        ring_segment_dirty: [RING_SEGMENTS]bool = .{false} ** RING_SEGMENTS,
        resource_cache: ?PreparedResources = null,

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
            if (self.supports_dual_source_blend) {
                self.text_subpixel_dual_program = try loadProgramState("text-subpixel-dual", shaders.vertex_shader, shaders.fragment_shader_text_subpixel_dual, true);
            }
            self.text_program_replicated = try loadProgramState("text-replicated", shaders.vertex_shader_replicated, shaders.fragment_shader_text, false);
            self.colr_program_replicated = try loadProgramState("text-colr-replicated", shaders.vertex_shader_replicated, shaders.fragment_shader_colr, false);
            self.path_program_replicated = try loadProgramState("path-replicated", shaders.vertex_shader_replicated, shaders.fragment_shader_path, false);
            self.hinted_text_program_replicated = try loadProgramState("hinted-text-replicated", shaders.vertex_shader_replicated, shaders.fragment_shader_hinted_text, false);
            if (self.supports_dual_source_blend) {
                self.text_subpixel_dual_program_replicated = try loadProgramState("text-subpixel-dual-replicated", shaders.vertex_shader_replicated, shaders.fragment_shader_text_subpixel_dual, true);
            }
            self.linear_resolve_program = try linkProgram("linear-resolve", linear_resolve_vertex_shader, linear_resolve_fragment_shader, false);
            self.linear_resolve_tex_loc = gl.glGetUniformLocation(self.linear_resolve_program, "u_linear_tex");
            self.linear_resolve_dst_tex_loc = gl.glGetUniformLocation(self.linear_resolve_program, "u_dst_tex");
            self.linear_resolve_mode_loc = gl.glGetUniformLocation(self.linear_resolve_program, "u_mode");
            gl.glGenVertexArrays(1, &self.linear_resolve_vao);

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

            const flags: gl.GLbitfield = gl.GL_MAP_WRITE_BIT | gl.GL_MAP_PERSISTENT_BIT | gl.GL_MAP_COHERENT_BIT;
            gl.glNamedBufferStorage(self.vbo, RING_TOTAL_BYTES, null, flags);
            self.persistent_map = @ptrCast(gl.glMapNamedBufferRange(self.vbo, 0, RING_TOTAL_BYTES, flags));

            if (self.persistent_map == null) {
                gl.glDeleteVertexArrays(1, &self.vao);
                gl.glDeleteBuffers(1, &self.vbo);
                gl.glDeleteBuffers(1, &self.ebo);
                self.vao = 0;
                self.vbo = 0;
                self.ebo = 0;
                return error.UnsupportedOpenGlBackend;
            }

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
            if (self.resource_cache) |*cache| {
                cache.deinit();
                self.resource_cache = null;
            }
            if (comptime backend == .gl44) {
                for (&self.ring_fences) |*f| {
                    if (f.*) |fence| {
                        gl.glDeleteSync(fence);
                        f.* = null;
                    }
                }
                if (self.persistent_map != null) {
                    _ = gl.glUnmapNamedBuffer(self.vbo);
                    self.persistent_map = null;
                }
            }

            deleteProgramState(&self.text_program);
            deleteProgramState(&self.text_subpixel_dual_program);
            deleteProgramState(&self.colr_program);
            deleteProgramState(&self.path_program);
            deleteProgramState(&self.hinted_text_program);
            deleteProgramState(&self.text_program_replicated);
            deleteProgramState(&self.text_subpixel_dual_program_replicated);
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

        pub fn resourceCache(self: *GlTextState, allocator: std.mem.Allocator) *PreparedResources {
            if (self.resource_cache == null) {
                self.resource_cache = PreparedResources{
                    .allocator = allocator,
                };
            }
            if (self.resource_cache) |*cache| {
                return cache;
            }
            unreachable;
        }

        pub fn resetResourceCache(self: *GlTextState) void {
            if (self.resource_cache) |*cache| {
                const allocator = cache.allocator;
                const generation = cache.generation +% 1;
                cache.deinit();
                cache.* = .{
                    .allocator = allocator,
                    .generation = generation,
                };
            }
        }

        pub fn resourceCacheStats(self: *const GlTextState) snail_mod.ResourceCacheStats {
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

        pub fn backendName(_: *const GlTextState) [:0]const u8 {
            return switch (backend) {
                .gl33 => "GL 3.3",
                .gl44 => "GL 4.4 (persistent mapped)",
            };
        }

        pub fn beginLinearResolve(self: *GlTextState, surface: TargetSurface, resolve: LinearResolve) !LinearResolveRestore {
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

        pub fn endLinearResolve(self: *GlTextState, restore: LinearResolveRestore) void {
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

        fn snapshotResolveDestination(self: *GlTextState, restore: LinearResolveRestore, width: u32, height: u32) void {
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

        fn drawLinearResolveTriangle(self: *GlTextState, pass: LinearResolvePass) void {
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

        fn setResolveScissor(_: *GlTextState, rect: PixelRect, viewport_y: gl.GLint, viewport_height: u32) void {
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

        fn ensureLinearResolve(self: *GlTextState, width: u32, height: u32, format: IntermediateFormat) !void {
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
            initLinearResolveTexture(self.linear_resolve_dst_tex, width, height, format);
            gl.glBindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, self.linear_resolve_fbo);
            gl.glFramebufferTexture2D(gl.GL_DRAW_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, self.linear_resolve_tex, 0);
            if (gl.glCheckFramebufferStatus(gl.GL_DRAW_FRAMEBUFFER) != gl.GL_FRAMEBUFFER_COMPLETE) {
                return error.FramebufferIncomplete;
            }

            self.linear_resolve_width = width;
            self.linear_resolve_height = height;
        }

        fn linearResolveReady(self: *const GlTextState, width: u32, height: u32, format: IntermediateFormat) bool {
            return self.linear_resolve_fbo != 0 and
                self.linear_resolve_tex != 0 and
                self.linear_resolve_dst_tex != 0 and
                self.linear_resolve_width == width and
                self.linear_resolve_height == height and
                self.linear_resolve_format == format;
        }

        fn resetLinearResolveObjects(self: *GlTextState, format: IntermediateFormat) void {
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

        // ── Draw ──

        fn drawTextInternal(self: *GlTextState, prepared: *const PreparedResources, vertices: []const u32, draw_state: DrawState, texture_layer_base: u32, allow_subpixel: bool) !void {
            // VAO may have been unbound by other renderers in the same context.
            gl.glBindVertexArray(self.vao);
            if (comptime backend == .gl33) {
                gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
            }

            const total_glyphs = vertices.len / vertex.WORDS_PER_INSTANCE;
            const render_mode = subpixel_policy.chooseTextRenderMode(
                vertices,
                draw_state.mvp,
                allow_subpixel,
                draw_state.raster.subpixel_order,
                self.supports_dual_source_blend,
            );
            if (!prepared.atlas_has_special_text_runs) {
                setTextBlendMode(false, render_mode);
                const prog_state = switch (render_mode) {
                    .grayscale => &self.text_program,
                    .subpixel_dual_source => &self.text_subpixel_dual_program,
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
                        self.supports_dual_source_blend,
                    );
                setTextBlendMode(run_kind != .regular, run_mode);
                const prog_state = switch (run_kind) {
                    .regular => switch (run_mode) {
                        .grayscale => &self.text_program,
                        .subpixel_dual_source => &self.text_subpixel_dual_program,
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

        pub fn drawTextPrepared(self: *GlTextState, prepared: *const PreparedResources, vertices: []const u32, draw_state: DrawState, texture_layer_base: u32) !void {
            try self.drawTextInternal(prepared, vertices, draw_state, texture_layer_base, true);
        }

        pub fn drawPreparedText(self: *GlTextState, prepared: *const PreparedResources, vertices: []const u32) void {
            _ = prepared;
            if (vertices.len == 0) return;
            gl.glBindVertexArray(self.vao);
            if (comptime backend == .gl33) {
                gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
            }
            self.drawGlyphRange(vertices, 0, vertices.len / vertex.WORDS_PER_INSTANCE);
        }

        pub fn drawPathsPrepared(self: *GlTextState, prepared: *const PreparedResources, vertices: []const u32, draw_state: DrawState, texture_layer_base: u32) !void {
            const render_mode: subpixel_policy.TextRenderMode = .grayscale;
            const prog_state = self.ensurePathProgram();
            gl.glBindVertexArray(self.vao);
            if (comptime backend == .gl33) {
                gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
            }

            setTextBlendMode(false, render_mode);

            try self.bindProgramState(prepared, prog_state, draw_state, texture_layer_base, render_mode);
            self.drawGlyphRange(vertices, 0, vertices.len / vertex.WORDS_PER_INSTANCE);
        }

        // ── New-API draw entry (Phase 5a) ──

        const gl_upload_variant: gl_upload.Variant = switch (backend) {
            .gl33 => .gl33,
            .gl44 => .gl44,
        };
        const GlPreparedPages = gl_upload.GlPreparedPagesFor(gl_upload_variant);

        pub const DrawError = error{
            MissingBinding,
            StaleBinding,
            MalformedSegment,
        } || std.mem.Allocator.Error;

        /// Walk `DrawRecords.segments`, bind each segment's matching
        /// `GlPreparedPages` cache, dispatch the encoded instances through
        /// the existing program set. Replicated segments materialize
        /// composed instances in a caller-supplied scratch allocator.
        pub fn draw(
            self: *GlTextState,
            scratch: std.mem.Allocator,
            draw_state: DrawState,
            records: draw_records_mod.DrawRecords,
            caches: []const *const GlPreparedPages,
        ) DrawError!void {
            gl.glBindVertexArray(self.vao);
            if (comptime backend == .gl33) gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);

            for (records.segments) |seg| {
                const cache = findNewApiCache(caches, seg.binding.pool) orelse return error.MissingBinding;
                if (seg.binding.generation != 0 and cache.upload_generation < seg.binding.generation) return error.StaleBinding;
                const seg_words = records.words[seg.words_offset..][0..seg.words_len];
                switch (seg.kind) {
                    .heterogeneous => try self.drawHeterogeneous(cache, draw_state, seg_words),
                    .replicated => try self.drawReplicated(scratch, cache, draw_state, seg, seg_words),
                }
            }
        }

        fn drawHeterogeneous(self: *GlTextState, cache: *const GlPreparedPages, draw_state: DrawState, vertices: []const u32) DrawError!void {
            const total_glyphs = vertices.len / vertex.WORDS_PER_INSTANCE;
            if (total_glyphs == 0) return;

            const allow_subpixel = true;

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
                setTextBlendMode(run_kind != .regular, run_mode);
                const prog_state = switch (run_kind) {
                    .regular => switch (run_mode) {
                        .grayscale => &self.text_program,
                        .subpixel_dual_source => &self.text_subpixel_dual_program,
                    },
                    .colr => self.ensureColrProgram(),
                    .path => self.ensurePathProgram(),
                    .hinted_text => self.ensureHintedTextProgram(),
                };
                self.bindProgramState_(cache, prog_state, draw_state, run_mode);
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
        /// binding's buffer offset shifted by s × 64 bytes. The
        /// replicated vertex shader composes shape × override
        /// per-instance and emits the final pixel.
        ///
        /// `scratch` is unused on this path — the whole point of GPU
        /// instancing is avoiding the N*M CPU-side composition.
        fn drawReplicated(
            self: *GlTextState,
            _: std.mem.Allocator,
            cache: *const GlPreparedPages,
            draw_state: DrawState,
            seg: draw_records_mod.DrawSegment,
            seg_words: []const u32,
        ) DrawError!void {
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

            // Upload shape + override data into the replicated VBO (laid
            // out contiguously by emit).
            gl.glBindVertexArray(self.vao_replicated);
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
                    inline for (0..7) |i| gl.glVertexAttribDivisor(@intCast(i), m);
                    inline for (7..10) |i| gl.glVertexAttribDivisor(@intCast(i), 1);
                    self.replicated_shape_divisor = m;
                }
            }

            const allow_subpixel = true;
            const shape_words_view = seg_words[0..@as(usize, n) * vertex.WORDS_PER_INSTANCE];

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
                setTextBlendMode(run_kind != .regular, run_mode);
                const prog_state = switch (run_kind) {
                    .regular => switch (run_mode) {
                        .grayscale => &self.text_program_replicated,
                        .subpixel_dual_source => &self.text_subpixel_dual_program_replicated,
                    },
                    .colr => &self.colr_program_replicated,
                    .path => &self.path_program_replicated,
                    .hinted_text => &self.hinted_text_program_replicated,
                };
                self.bindProgramState_(cache, prog_state, draw_state, run_mode);
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

        /// Bind one GlPreparedPages' texture set + uniforms. Mirrors
        /// `bindProgramState` but reads from the new-API cache. The
        /// `layer_base` uniform is always 0 — the new model encodes the
        /// absolute texture-array layer in the per-instance `glyph` data,
        /// not via a bank-relative offset like the legacy path.
        fn bindProgramState_(self: *GlTextState, cache: *const GlPreparedPages, prog_state: *const ProgramState, draw_state: DrawState, render_mode: subpixel_policy.TextRenderMode) void {
            const program_changed = prog_state.handle != self.active_program or !self.frame_begun;
            if (program_changed) {
                gl.glUseProgram(prog_state.handle);
                self.active_program = prog_state.handle;
                // Force-reset the bank id so legacy/new paths don't conflict.
                self.active_resource_bank_id = std.math.maxInt(u32);
                self.frame_begun = true;
            }

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

        pub fn beginDraw(self: *GlTextState) void {
            self.frame_begun = false;
            if (comptime backend == .gl44) {
                if (!self.ring_segment_dirty[self.ring_segment]) return;
                self.fenceRingSegment(self.ring_segment);
                self.ring_segment = (self.ring_segment + 1) % RING_SEGMENTS;
                self.ring_offset = 0;
            }
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

        fn bindProgramState(self: *GlTextState, prepared: *const PreparedResources, prog_state: *const ProgramState, draw_state: DrawState, texture_layer_base: u32, render_mode: subpixel_policy.TextRenderMode) !void {
            const bank_id = texture_layers.bank(texture_layer_base);
            const bank = prepared.bankForId(bank_id) orelse return error.MissingPreparedResource;
            if (prog_state.handle != self.active_program or !self.frame_begun or bank_id != self.active_resource_bank_id) {
                gl.glUseProgram(prog_state.handle);
                self.active_program = prog_state.handle;
                self.active_resource_bank_id = bank_id;

                if (comptime backend == .gl44) {
                    gl.glBindTextureUnit(0, bank.curve_array);
                    gl.glBindTextureUnit(1, bank.band_array);
                    if (prog_state.layer_tex_loc >= 0 and bank.layer_info_tex != 0) gl.glBindTextureUnit(2, bank.layer_info_tex);
                    if (prog_state.image_tex_loc >= 0 and bank.image_array != 0) gl.glBindTextureUnit(3, bank.image_array);
                } else {
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

        fn waitRingSegment(self: *GlTextState, segment: u32) void {
            if (self.ring_fences[segment]) |fence| {
                const status = gl.glClientWaitSync(fence, 0, 0);
                if (status != gl.GL_ALREADY_SIGNALED and status != gl.GL_CONDITION_SATISFIED) {
                    _ = gl.glClientWaitSync(fence, gl.GL_SYNC_FLUSH_COMMANDS_BIT, 1_000_000_000);
                }
                gl.glDeleteSync(fence);
                self.ring_fences[segment] = null;
            }
        }

        fn fenceRingSegment(self: *GlTextState, segment: u32) void {
            if (!self.ring_segment_dirty[segment]) return;
            self.ring_fences[segment] = gl.glFenceSync(gl.GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
            self.ring_segment_dirty[segment] = false;
        }

        fn advanceRingSegment(self: *GlTextState) void {
            self.fenceRingSegment(self.ring_segment);
            self.ring_segment = (self.ring_segment + 1) % RING_SEGMENTS;
            self.ring_offset = 0;
            self.waitRingSegment(self.ring_segment);
        }

        fn drawGlyphRange(self: *GlTextState, vertices: []const u32, glyph_offset: usize, glyph_count: usize) void {
            var glyphs_drawn: usize = 0;
            while (glyphs_drawn < glyph_count) {
                const word_offset = (glyph_offset + glyphs_drawn) * vertex.WORDS_PER_INSTANCE;
                var chunk: usize = @min(glyph_count - glyphs_drawn, MAX_GLYPHS_PER_SEGMENT);
                if (comptime backend == .gl44) {
                    if (RING_SEGMENT_BYTES - self.ring_offset < BYTES_PER_GLYPH) {
                        self.advanceRingSegment();
                    } else {
                        self.waitRingSegment(self.ring_segment);
                    }
                    const segment_capacity = (RING_SEGMENT_BYTES - self.ring_offset) / BYTES_PER_GLYPH;
                    chunk = @min(chunk, segment_capacity);
                }
                const byte_size = chunk * BYTES_PER_GLYPH;

                if (comptime backend == .gl33) {
                    gl.glBufferSubData(gl.GL_ARRAY_BUFFER, 0, @intCast(byte_size), @ptrCast(vertices[word_offset..].ptr));
                } else {
                    const offset = @as(usize, self.ring_segment) * RING_SEGMENT_BYTES + self.ring_offset;
                    const dst = self.persistent_map.?[offset..][0..byte_size];
                    const src: [*]const u8 = @ptrCast(vertices[word_offset..].ptr);
                    @memcpy(dst, src[0..byte_size]);

                    const stride: gl.GLint = vertex.BYTES_PER_INSTANCE;
                    gl.glVertexArrayVertexBuffer(self.vao, 0, self.vbo, @intCast(offset), stride);
                }

                gl.glDrawElementsInstanced(gl.GL_TRIANGLES, 6, gl.GL_UNSIGNED_INT, null, @intCast(chunk));

                if (comptime backend == .gl44) {
                    self.ring_offset += byte_size;
                    self.ring_segment_dirty[self.ring_segment] = true;
                }

                glyphs_drawn += chunk;
            }
        }
    };
}

pub const Gl33TextState = TextStateFor(.gl33);
pub const Gl44TextState = TextStateFor(.gl44);

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
}

fn setupVertexArrayAttrib(vao: gl.GLuint, loc: u32, components: gl.GLint, ty: gl.GLenum, normalized: gl.GLboolean, offset: usize) void {
    gl.glEnableVertexArrayAttrib(vao, loc);
    gl.glVertexArrayAttribFormat(vao, loc, components, ty, normalized, @intCast(offset));
    gl.glVertexArrayAttribBinding(vao, loc, 0);
}

/// DSA setup for the replicated VAO: same shape attributes as the
/// heterogeneous VAO bound to binding 0 (configurable divisor M), plus
/// override attributes 7-9 bound to binding 1 (divisor 1).
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
    // Override attributes, binding 1. Layout matches `emit.writeOverride`:
    // bytes 0-15  = vec4 (xx, xy, tx, yx)
    // bytes 16-23 = vec2 (yy, ty); the shader reads only the first two
    //               components of b_xform_b, so byte 24-31 (packed tint
    //               + pad) safely cohabit the same vec4 slot.
    // bytes 24-27 = packed u8x4 tint (read as b_tint with normalized u8)
    gl.glEnableVertexArrayAttrib(vao, 7);
    gl.glVertexArrayAttribFormat(vao, 7, 4, gl.GL_FLOAT, gl.GL_FALSE, 0);
    gl.glVertexArrayAttribBinding(vao, 7, 1);
    gl.glEnableVertexArrayAttrib(vao, 8);
    gl.glVertexArrayAttribFormat(vao, 8, 4, gl.GL_FLOAT, gl.GL_FALSE, 16);
    gl.glVertexArrayAttribBinding(vao, 8, 1);
    gl.glEnableVertexArrayAttrib(vao, 9);
    gl.glVertexArrayAttribFormat(vao, 9, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, 24);
    gl.glVertexArrayAttribBinding(vao, 9, 1);
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
    const override_stride: gl.GLsizei = 32;
    setupVertexAttrib(7, 4, gl.GL_FLOAT, gl.GL_FALSE, override_stride, override_base + 0);
    setupVertexAttrib(8, 4, gl.GL_FLOAT, gl.GL_FALSE, override_stride, override_base + 16);
    setupVertexAttrib(9, 4, gl.GL_UNSIGNED_BYTE, gl.GL_TRUE, override_stride, override_base + 24);
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

fn setTextBlendMode(special: bool, render_mode: subpixel_policy.TextRenderMode) void {
    if (!special and render_mode == .subpixel_dual_source) {
        gl.glEnable(gl.GL_BLEND);
        gl.glBlendFuncSeparate(gl.GL_ONE, gl.GL_ONE_MINUS_SRC1_COLOR, gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
        return;
    }
    gl.glEnable(gl.GL_BLEND);
    gl.glBlendFuncSeparate(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA, gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
}

fn detectDualSourceBlendSupport() bool {
    var max_draw_buffers: gl.GLint = 0;
    gl.glGetIntegerv(gl.GL_MAX_DUAL_SOURCE_DRAW_BUFFERS, &max_draw_buffers);
    return max_draw_buffers >= 1;
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
