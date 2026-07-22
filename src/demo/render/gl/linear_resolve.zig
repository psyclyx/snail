//! Linear-resolve passes for both `gl/state.zig` and `gles30/state.zig`.
//!
//! A linear-resolve pass renders a frame into a float intermediate
//! (RGBA16F / RGBA32F), then encodes back to the final sRGB target.
//! Both GL backends do this byte-identically — the only variations are
//! the bindings module (different `@cImport` headers) and one tiny
//! per-backend choice: GL relies on `GL_FRAMEBUFFER_SRGB` for output
//! conversion and uses the intermediate format for the dst snapshot
//! texture, while GLES3 has no such toggle and stores the dst snapshot
//! as RGBA8 sRGB.
//!
//! `StateFor(gl, config)` instantiates the state for a backend. The
//! config carries shader sources, the program linker, and the dst
//! texture format choice.

const std = @import("std");
const snail_mod = @import("snail");
const render_state = @import("render-state");
const gl_common = @import("common.zig");
const slang_gen = snail_mod.shader.slang_generated;

const LinearResolve = render_state.LinearResolve;
const IntermediateFormat = LinearResolve.Format;
const PixelRect = render_state.PixelRect;
const TargetSurface = render_state.TargetSurface;
const LinearResolveRestore = gl_common.LinearResolveRestore;
const LinearResolvePass = gl_common.LinearResolvePass;
const linearPremultipliedBackdropColor = gl_common.linearPremultipliedBackdropColor;
const glRectY = gl_common.glRectY;

pub const DstFormat = enum {
    /// Dst snapshot texture matches the intermediate float format.
    /// Used by desktop GL where `GL_FRAMEBUFFER_SRGB` handles encoding.
    intermediate,
    /// Dst snapshot texture is RGBA8 sRGB. Used by GLES3 which lacks
    /// `GL_FRAMEBUFFER_SRGB`.
    srgb8,
};

pub fn StateFor(comptime gl: type, comptime config: anytype) type {
    // Bind config fields to their expected types so call sites can use
    // enum-literal / string-literal shorthand.
    const linkProgram = config.linkProgram;
    const vertex_shader: [:0]const u8 = config.vertex_shader;
    const fragment_shader: [:0]const u8 = config.fragment_shader;
    const dst_format: DstFormat = config.dst_format;

    return struct {
        const Self = @This();

        program: gl.GLuint = 0,
        mode_ubo: gl.GLuint = 0,
        vao: gl.GLuint = 0,
        fbo: gl.GLuint = 0,
        tex: gl.GLuint = 0,
        dst_tex: gl.GLuint = 0,
        width: u32 = 0,
        height: u32 = 0,
        format: IntermediateFormat = .rgba16f,
        active: bool = false,

        pub fn init(self: *Self) !void {
            self.program = try linkProgram("linear-resolve", vertex_shader, fragment_shader, false);
            // Native-Slang generated program: the mode lives in a one-int
            // std140 block, samplers carry the generated names (see
            // snail.shader.slang_generated). Pin the samplers to units 0/1
            // at link time; bind the block to binding point 0 (rebound with
            // its buffer on every drawTriangle).
            const linear_loc = gl.glGetUniformLocation(self.program, slang_gen.glsl_linear_resolve_linear_tex_name);
            const dst_loc = gl.glGetUniformLocation(self.program, slang_gen.glsl_linear_resolve_dst_tex_name);
            const block = gl.glGetUniformBlockIndex(self.program, slang_gen.glsl_linear_resolve_block_name);
            if (block == gl.GL_INVALID_INDEX) return error.ShaderLinkFailed;
            gl.glUniformBlockBinding(self.program, block, gl_common.NATIVE_TEXT_UBO_BINDING);
            gl.glGenBuffers(1, &self.mode_ubo);
            gl.glBindBuffer(gl.GL_UNIFORM_BUFFER, self.mode_ubo);
            gl.glBufferData(gl.GL_UNIFORM_BUFFER, 16, null, gl.GL_DYNAMIC_DRAW);
            gl.glBindBuffer(gl.GL_UNIFORM_BUFFER, 0);
            var prev_program: gl.GLint = 0;
            gl.glGetIntegerv(gl.GL_CURRENT_PROGRAM, &prev_program);
            gl.glUseProgram(self.program);
            if (linear_loc >= 0) gl.glUniform1i(linear_loc, 0);
            if (dst_loc >= 0) gl.glUniform1i(dst_loc, 1);
            gl.glUseProgram(@intCast(prev_program));
            gl.glGenVertexArrays(1, &self.vao);
        }

        pub fn deinit(self: *Self) void {
            if (self.program != 0) gl.glDeleteProgram(self.program);
            if (self.mode_ubo != 0) gl.glDeleteBuffers(1, &self.mode_ubo);
            if (self.vao != 0) gl.glDeleteVertexArrays(1, &self.vao);
            if (self.fbo != 0) gl.glDeleteFramebuffers(1, &self.fbo);
            if (self.tex != 0) gl.glDeleteTextures(1, &self.tex);
            if (self.dst_tex != 0) gl.glDeleteTextures(1, &self.dst_tex);
        }

        pub fn begin(self: *Self, surface: TargetSurface, resolve: LinearResolve) !LinearResolveRestore {
            if (!surface.supportsLinearResolve()) return error.UnsupportedResolve;
            if (self.active) return error.LinearResolveAlreadyActive;
            const target_rect = surface.pixelRect();
            const width = target_rect.w;
            const height = target_rect.h;
            if (width == 0 or height == 0) return error.InvalidTargetSurface;
            try self.ensure(width, height, resolve.intermediate_format);

            var restore: LinearResolveRestore = .{};
            gl.glGetIntegerv(gl.GL_DRAW_FRAMEBUFFER_BINDING, &restore.draw_fbo);
            gl.glGetIntegerv(gl.GL_READ_FRAMEBUFFER_BINDING, &restore.read_fbo);
            gl.glGetIntegerv(gl.GL_VIEWPORT, &restore.viewport);
            restore.resolve_rect = resolve.region.rect(width, height);
            restore.depth_test = gl.glIsEnabled(gl.GL_DEPTH_TEST) == gl.GL_TRUE;
            restore.scissor_test = gl.glIsEnabled(gl.GL_SCISSOR_TEST) == gl.GL_TRUE;
            restore.blend = gl.glIsEnabled(gl.GL_BLEND) == gl.GL_TRUE;

            gl.glBindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, self.fbo);
            gl.glViewport(0, 0, @intCast(width), @intCast(height));
            gl.glDisable(gl.GL_DEPTH_TEST);
            setScissor(restore.resolve_rect, 0, height);
            gl.glDisable(gl.GL_BLEND);
            switch (resolve.backdrop) {
                .target => {
                    self.snapshotDestination(restore, width, height);
                    self.drawTriangle(.seed_intermediate);
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
            self.active = true;
            return restore;
        }

        pub fn end(self: *Self, restore: LinearResolveRestore) void {
            std.debug.assert(self.active);
            gl.glBindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, @intCast(restore.draw_fbo));
            gl.glViewport(restore.viewport[0], restore.viewport[1], restore.viewport[2], restore.viewport[3]);
            gl.glDisable(gl.GL_DEPTH_TEST);
            setScissor(restore.resolve_rect, restore.viewport[1], @intCast(restore.viewport[3]));

            gl.glDisable(gl.GL_BLEND);
            self.drawTriangle(.encode_to_target);

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
            self.active = false;
        }

        fn snapshotDestination(self: *Self, restore: LinearResolveRestore, width: u32, height: u32) void {
            var prev_tex: gl.GLint = 0;
            gl.glGetIntegerv(gl.GL_TEXTURE_BINDING_2D, &prev_tex);
            defer gl.glBindTexture(gl.GL_TEXTURE_2D, @intCast(prev_tex));

            const rect = restore.resolve_rect;
            if (rect.w == 0 or rect.h == 0) return;
            const y = glRectY(rect, height);
            gl.glBindFramebuffer(gl.GL_READ_FRAMEBUFFER, @intCast(restore.draw_fbo));
            gl.glBindTexture(gl.GL_TEXTURE_2D, self.dst_tex);
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

        fn drawTriangle(self: *Self, pass: LinearResolvePass) void {
            gl.glUseProgram(self.program);
            gl.glBindVertexArray(self.vao);
            gl.glActiveTexture(gl.GL_TEXTURE0);
            gl.glBindTexture(gl.GL_TEXTURE_2D, if (pass == .seed_intermediate) 0 else self.tex);
            gl.glActiveTexture(gl.GL_TEXTURE1);
            gl.glBindTexture(gl.GL_TEXTURE_2D, self.dst_tex);
            const block = [4]i32{ @intFromEnum(pass), 0, 0, 0 };
            gl.glBindBufferBase(gl.GL_UNIFORM_BUFFER, gl_common.NATIVE_TEXT_UBO_BINDING, self.mode_ubo);
            gl.glBufferSubData(gl.GL_UNIFORM_BUFFER, 0, 16, &block);
            gl.glDrawArrays(gl.GL_TRIANGLES, 0, 3);
        }

        fn setScissor(rect: PixelRect, viewport_y: gl.GLint, viewport_height: u32) void {
            const y = viewport_y + glRectY(rect, viewport_height);
            gl.glEnable(gl.GL_SCISSOR_TEST);
            gl.glScissor(rect.x, y, @intCast(rect.w), @intCast(rect.h));
        }

        fn ensure(self: *Self, width: u32, height: u32, format: IntermediateFormat) !void {
            if (self.ready(width, height, format)) return;
            self.resetObjects(format);

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

            gl.glGenFramebuffers(1, &self.fbo);
            gl.glGenTextures(1, &self.tex);
            gl.glGenTextures(1, &self.dst_tex);
            initIntermediateTexture(self.tex, width, height, format);
            switch (dst_format) {
                .intermediate => initIntermediateTexture(self.dst_tex, width, height, format),
                .srgb8 => initSrgb8Texture(self.dst_tex, width, height),
            }
            gl.glBindFramebuffer(gl.GL_DRAW_FRAMEBUFFER, self.fbo);
            gl.glFramebufferTexture2D(gl.GL_DRAW_FRAMEBUFFER, gl.GL_COLOR_ATTACHMENT0, gl.GL_TEXTURE_2D, self.tex, 0);
            if (gl.glCheckFramebufferStatus(gl.GL_DRAW_FRAMEBUFFER) != gl.GL_FRAMEBUFFER_COMPLETE) {
                return error.FramebufferIncomplete;
            }

            self.width = width;
            self.height = height;
        }

        fn ready(self: *const Self, width: u32, height: u32, format: IntermediateFormat) bool {
            return self.fbo != 0 and
                self.tex != 0 and
                self.dst_tex != 0 and
                self.width == width and
                self.height == height and
                self.format == format;
        }

        fn resetObjects(self: *Self, format: IntermediateFormat) void {
            if (self.fbo != 0) gl.glDeleteFramebuffers(1, &self.fbo);
            if (self.tex != 0) gl.glDeleteTextures(1, &self.tex);
            if (self.dst_tex != 0) gl.glDeleteTextures(1, &self.dst_tex);
            self.fbo = 0;
            self.tex = 0;
            self.dst_tex = 0;
            self.width = 0;
            self.height = 0;
            self.format = format;
        }

        fn initIntermediateTexture(texture: gl.GLuint, width: u32, height: u32, format: IntermediateFormat) void {
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
            applyNearestClampParams();
        }

        fn initSrgb8Texture(texture: gl.GLuint, width: u32, height: u32) void {
            gl.glBindTexture(gl.GL_TEXTURE_2D, texture);
            gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA8, @intCast(width), @intCast(height), 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, null);
            applyNearestClampParams();
        }

        fn applyNearestClampParams() void {
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
        }
    };
}
