//! Embeddable coverage surface for the GL family (GL 3.3 / 4.4 / GLES 3.0).
//!
//! All `gl`-typed code (uniform-location programs, texture-binding backends)
//! and the GL GLSL source fragments live here in the `snail_gl` module — the
//! facade's `coverage.zig` only aggregates these into the cross-backend
//! `Shader` / `Program` / `Backend` unions. Disabled backends degrade to empty
//! shader strings + no-op backend types via `build_options`, so cross-backend
//! caller code compiles regardless of which GL variants are enabled.

const std = @import("std");
const build_options = @import("build_options");
const core = @import("snail_core");

const SubpixelOrder = core.SubpixelOrder;
const CoverageTransfer = core.CoverageTransfer;
const FillRule = core.FillRule;
const WORDS_PER_INSTANCE: usize = core.WORDS_PER_INSTANCE;

// ── Backend-module selection (empty stubs when a variant is disabled) ──

const gl_shaders = if (build_options.enable_gl33 or build_options.enable_gl44)
    @import("shaders.zig")
else
    struct {
        pub const text_vertex_interface = "";
        pub const text_coverage_fragment_interface = "";
        pub const text_coverage_fragment_body = "";
        pub const text_sample_interface = "";
        pub const text_sample_body = "";
    };

const gles30_shaders = if (build_options.enable_gles30)
    @import("gles30/shaders.zig")
else
    struct {
        pub const text_vertex_interface = "";
        pub const text_coverage_fragment_interface = "";
        pub const text_coverage_fragment_body = "";
        pub const text_sample_interface = "";
        pub const text_sample_body = "";
    };

const gl_backend_cache = if (build_options.enable_gl33 or build_options.enable_gl44)
    @import("backend_cache.zig")
else
    struct {
        pub const Gl33BackendCache = void;
        pub const Gl44BackendCache = void;
    };

const gles30_backend_cache = if (build_options.enable_gles30)
    @import("backend_cache.zig")
else
    struct {
        pub const Gles30BackendCache = void;
    };

const gl_state = if (build_options.enable_gl33 or build_options.enable_gl44)
    @import("state.zig")
else
    struct {
        pub const Gl33Renderer = void;
        pub const Gl44Renderer = void;
    };

const gles30_state = if (build_options.enable_gles30)
    @import("gles30/state.zig")
else
    struct {
        pub const Gles30Renderer = void;
    };

const gl_bindings = if (build_options.enable_gl33 or build_options.enable_gl44)
    @import("bindings.zig")
else
    struct {
        pub const gl = struct {
            pub const GLuint = u32;
            pub const GLint = i32;
        };
    };

const gles30_bindings = if (build_options.enable_gles30)
    @import("gles30/bindings.zig")
else
    struct {
        pub const gl = struct {
            pub const GLuint = u32;
            pub const GLint = i32;
        };
    };

// ── DrawState ──

/// The snail-side uniforms that change per draw. Filled by the caller from
/// their `snail.DrawState` (or constructed by hand for non-snail draw paths).
/// Only the GL family consumes this — the Vulkan path uses push constants.
pub const DrawState = struct {
    subpixel_order: SubpixelOrder = .none,
    output_srgb: bool = false,
    coverage_transfer: CoverageTransfer = .identity,
    /// Added to the per-instance layer byte to compute the absolute atlas
    /// texture-array layer. With the snail emit path this is always 0 (the
    /// per-instance glyph data already encodes the absolute layer).
    layer_base: u32 = 0,
};

// ── Shader sources ──

const text_color_funcs =
    \\vec4 snail_text_color_srgb() {
    \\    return v_color;
    \\}
    \\
    \\vec4 snail_text_color_linear() {
    \\    return vec4(srgbDecode(v_color.r), srgbDecode(v_color.g), srgbDecode(v_color.b), v_color.a);
    \\}
    \\
    \\float snail_text_coverage() {
    \\    int layer_byte = (v_glyph.w >> 8) & 0xFF;
    \\    if (layer_byte == SNAIL_SPECIAL_LAYER_SENTINEL) return 0.0;
    \\    int atlas_layer = u_layer_base + layer_byte;
    \\    vec2 rc = v_texcoord;
    \\    vec2 dx = vec2(dFdx(rc.x), dFdy(rc.x));
    \\    vec2 dy = vec2(dFdx(rc.y), dFdy(rc.y));
    \\    vec2 ppe = vec2(1.0 / max(length(dx), 1.0 / 65536.0), 1.0 / max(length(dy), 1.0 / 65536.0));
    \\    return evalGlyphCoverage(rc, ppe, v_glyph.xy,
    \\                             ivec2(v_glyph.w & 0xFF, v_glyph.z),
    \\                             v_banding, atlas_layer);
    \\}
    \\
;

const resource_interface_glsl =
    \\uniform sampler2DArray u_curve_tex;
    \\uniform usampler2DArray u_band_tex;
    \\uniform int u_fill_rule;
    \\uniform int u_layer_base;
    \\
    \\#define SNAIL_FILL_RULE u_fill_rule
    \\
;

const TEXT_WORDS_PER_GLYPH_PRELUDE = std.fmt.comptimePrint(
    "#define SNAIL_TEXT_RECORD_WORDS_PER_GLYPH {d}\n",
    .{WORDS_PER_INSTANCE},
);

/// GLSL source fragments callers concatenate into their own GL 3.3 / 4.4
/// shaders. The facade exposes this as `coverage.Shader.gl33` / `.gl44`.
pub const GlShaderSources = struct {
    /// Paste into a vertex shader that wants the standard snail per-
    /// instance attributes (the same `vertex.Instance` layout the snail
    /// draw path uses).
    pub const vertex_interface = gl_shaders.text_vertex_interface;
    /// Paste into a fragment shader that draws the prepared coverage
    /// geometry directly (per-fragment varyings from the vertex stage).
    pub const fragment_interface = gl_shaders.text_coverage_fragment_interface;
    /// Paste into a fragment shader that does NOT use snail varyings —
    /// just samples coverage from arbitrary positions (typically when
    /// snail text is "painted onto" some other geometry).
    pub const resource_interface = resource_interface_glsl;
    /// Shared coverage helpers (`evalGlyphCoverage`, fill-rule, sRGB).
    pub const coverage_functions = gl_shaders.text_coverage_fragment_body;
    /// Sample-buffer interface: declares `u_snail_text_records` and
    /// `u_snail_text_glyph_count`.
    pub const sample_interface = gl_shaders.text_sample_interface;
    /// Function bodies for `snail_text_sample_premul_linear(vec2)` and
    /// friends — random-access sampling of the records buffer.
    pub const sample_functions = if ((build_options.enable_gl33 or build_options.enable_gl44))
        TEXT_WORDS_PER_GLYPH_PRELUDE ++ gl_shaders.text_sample_body
    else
        "";
    /// Full fragment body: coverage helpers + snail_text_coverage() +
    /// snail_text_color_*(). Paste after `fragment_interface`.
    pub const fragment_body = coverage_functions ++ "\n" ++ text_color_funcs;
};

/// GLSL source fragments for GLES 3.0. Facade exposes as `coverage.Shader.gles30`.
pub const Gles30ShaderSources = struct {
    pub const vertex_interface = gles30_shaders.text_vertex_interface;
    pub const fragment_interface = gles30_shaders.text_coverage_fragment_interface;
    pub const resource_interface = resource_interface_glsl;
    pub const coverage_functions = gles30_shaders.text_coverage_fragment_body;
    pub const sample_interface = gles30_shaders.text_sample_interface;
    pub const sample_functions = if (build_options.enable_gles30)
        TEXT_WORDS_PER_GLYPH_PRELUDE ++ gles30_shaders.text_sample_body
    else
        "";
    pub const fragment_body = coverage_functions ++ "\n" ++ text_color_funcs;
};

// ── Program descriptors ──

const gl_GLint = gl_bindings.gl.GLint;

/// Snail-side uniform locations + texture units inside the caller's GL
/// program. Fill in from `glGetUniformLocation` after link and pass to
/// `Backend.bindProgram` / `Backend.bindDrawState`. A `_loc` of `-1` (the
/// default) skips the corresponding uniform write.
pub const GlProgram = struct {
    curve_tex_loc: gl_GLint = -1,
    band_tex_loc: gl_GLint = -1,
    layer_tex_loc: gl_GLint = -1,
    image_tex_loc: gl_GLint = -1,
    fill_rule_loc: gl_GLint = -1,
    subpixel_order_loc: gl_GLint = -1,
    output_srgb_loc: gl_GLint = -1,
    coverage_exponent_loc: gl_GLint = -1,
    layer_base_loc: gl_GLint = -1,
    curve_tex_unit: gl_GLint = 0,
    band_tex_unit: gl_GLint = 1,
    layer_tex_unit: gl_GLint = 2,
    image_tex_unit: gl_GLint = 3,
};

const gles30_GLint = gles30_bindings.gl.GLint;

pub const Gles30Program = struct {
    curve_tex_loc: gles30_GLint = -1,
    band_tex_loc: gles30_GLint = -1,
    layer_tex_loc: gles30_GLint = -1,
    image_tex_loc: gles30_GLint = -1,
    fill_rule_loc: gles30_GLint = -1,
    subpixel_order_loc: gles30_GLint = -1,
    output_srgb_loc: gles30_GLint = -1,
    coverage_exponent_loc: gles30_GLint = -1,
    layer_base_loc: gles30_GLint = -1,
    curve_tex_unit: gles30_GLint = 0,
    band_tex_unit: gles30_GLint = 1,
    layer_tex_unit: gles30_GLint = 2,
    image_tex_unit: gles30_GLint = 3,
};

// ── Backends (binding shims over the BackendCache caches) ──

/// No-op backend used as the disabled-variant fallback for the GL backend
/// types, so cross-backend union code compiles even when GL is off.
const Disabled = struct {};

fn GlBackendFor(comptime variant: gl_backend_cache.Variant) type {
    return struct {
        const Self = @This();
        const BackendCache = switch (variant) {
            .gl33 => gl_backend_cache.Gl33BackendCache,
            .gl44 => gl_backend_cache.Gl44BackendCache,
            .gles30 => unreachable, // covered by Gles30Backend below
        };
        const TextState = switch (variant) {
            .gl33 => gl_state.Gl33TextState,
            .gl44 => gl_state.Gl44TextState,
            .gles30 => unreachable,
        };
        const dsa = (variant == .gl44);

        cache: *const BackendCache,
        state: *TextState,

        /// Build from a `Gl{33,44}Renderer` + matching `Gl{33,44}BackendCache` cache.
        pub fn from(renderer: anytype, cache: *const BackendCache) Self {
            return .{ .cache = cache, .state = &renderer.state };
        }

        /// Bind snail's atlas textures to the texture units named in `program`.
        pub fn bindProgram(self: Self, program: GlProgram) !void {
            const gl = gl_bindings.gl;
            if (dsa) {
                gl.glBindTextureUnit(@intCast(program.curve_tex_unit), self.cache.curve_array);
                gl.glBindTextureUnit(@intCast(program.band_tex_unit), self.cache.band_array);
                if (program.layer_tex_loc >= 0 and self.cache.layer_info_tex != 0)
                    gl.glBindTextureUnit(@intCast(program.layer_tex_unit), self.cache.layer_info_tex);
                if (program.image_tex_loc >= 0 and self.cache.image_array_tex != 0)
                    gl.glBindTextureUnit(@intCast(program.image_tex_unit), self.cache.image_array_tex);
            } else {
                gl.glActiveTexture(textureUnitEnum(program.curve_tex_unit));
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.cache.curve_array);
                gl.glActiveTexture(textureUnitEnum(program.band_tex_unit));
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.cache.band_array);
                if (program.layer_tex_loc >= 0 and self.cache.layer_info_tex != 0) {
                    gl.glActiveTexture(textureUnitEnum(program.layer_tex_unit));
                    gl.glBindTexture(gl.GL_TEXTURE_2D, self.cache.layer_info_tex);
                }
                if (program.image_tex_loc >= 0 and self.cache.image_array_tex != 0) {
                    gl.glActiveTexture(textureUnitEnum(program.image_tex_unit));
                    gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.cache.image_array_tex);
                }
            }
            if (program.curve_tex_loc >= 0) gl.glUniform1i(program.curve_tex_loc, program.curve_tex_unit);
            if (program.band_tex_loc >= 0) gl.glUniform1i(program.band_tex_loc, program.band_tex_unit);
            if (program.layer_tex_loc >= 0) gl.glUniform1i(program.layer_tex_loc, program.layer_tex_unit);
            if (program.image_tex_loc >= 0) gl.glUniform1i(program.image_tex_loc, program.image_tex_unit);
        }

        /// Set the snail uniforms named in `program` from the caller's
        /// `DrawState`. Fill rule for text is always non-zero (font convention);
        /// callers using the same program to draw paths set it themselves.
        pub fn bindDrawState(self: Self, program: GlProgram, state: DrawState) !void {
            _ = self;
            const gl = gl_bindings.gl;
            if (program.fill_rule_loc >= 0) gl.glUniform1i(program.fill_rule_loc, @intFromEnum(FillRule.non_zero));
            if (program.subpixel_order_loc >= 0) gl.glUniform1i(program.subpixel_order_loc, @intFromEnum(state.subpixel_order));
            if (program.output_srgb_loc >= 0) gl.glUniform1i(program.output_srgb_loc, @intFromBool(state.output_srgb));
            if (program.coverage_exponent_loc >= 0) gl.glUniform1f(program.coverage_exponent_loc, state.coverage_transfer.shaderExponent());
            if (program.layer_base_loc >= 0) gl.glUniform1i(program.layer_base_loc, @intCast(state.layer_base));
        }
    };
}

pub const Gl33Backend = if (build_options.enable_gl33) GlBackendFor(.gl33) else Disabled;
pub const Gl44Backend = if (build_options.enable_gl44) GlBackendFor(.gl44) else Disabled;

pub const Gles30Backend = if (build_options.enable_gles30) struct {
    const Self = @This();

    cache: *const gles30_backend_cache.Gles30BackendCache,
    state: *gles30_state.Gles30TextState,

    pub fn from(renderer: anytype, cache: *const gles30_backend_cache.Gles30BackendCache) Self {
        return .{ .cache = cache, .state = &renderer.state };
    }

    pub fn bindProgram(self: Self, program: Gles30Program) !void {
        const gl = gles30_bindings.gl;
        gl.glActiveTexture(textureUnitEnumGles(program.curve_tex_unit));
        gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.cache.curve_array);
        gl.glActiveTexture(textureUnitEnumGles(program.band_tex_unit));
        gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.cache.band_array);
        if (program.layer_tex_loc >= 0 and self.cache.layer_info_tex != 0) {
            gl.glActiveTexture(textureUnitEnumGles(program.layer_tex_unit));
            gl.glBindTexture(gl.GL_TEXTURE_2D, self.cache.layer_info_tex);
        }
        if (program.image_tex_loc >= 0 and self.cache.image_array_tex != 0) {
            gl.glActiveTexture(textureUnitEnumGles(program.image_tex_unit));
            gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.cache.image_array_tex);
        }
        if (program.curve_tex_loc >= 0) gl.glUniform1i(program.curve_tex_loc, program.curve_tex_unit);
        if (program.band_tex_loc >= 0) gl.glUniform1i(program.band_tex_loc, program.band_tex_unit);
        if (program.layer_tex_loc >= 0) gl.glUniform1i(program.layer_tex_loc, program.layer_tex_unit);
        if (program.image_tex_loc >= 0) gl.glUniform1i(program.image_tex_loc, program.image_tex_unit);
    }

    pub fn bindDrawState(self: Self, program: Gles30Program, state: DrawState) !void {
        _ = self;
        const gl = gles30_bindings.gl;
        if (program.fill_rule_loc >= 0) gl.glUniform1i(program.fill_rule_loc, @intFromEnum(FillRule.non_zero));
        if (program.subpixel_order_loc >= 0) gl.glUniform1i(program.subpixel_order_loc, @intFromEnum(state.subpixel_order));
        if (program.output_srgb_loc >= 0) gl.glUniform1i(program.output_srgb_loc, @intFromBool(state.output_srgb));
        if (program.coverage_exponent_loc >= 0) gl.glUniform1f(program.coverage_exponent_loc, state.coverage_transfer.shaderExponent());
        if (program.layer_base_loc >= 0) gl.glUniform1i(program.layer_base_loc, @intCast(state.layer_base));
    }

    fn textureUnitEnumGles(unit: gles30_GLint) gles30_bindings.gl.GLenum {
        return @intCast(@as(i64, @intCast(gles30_bindings.gl.GL_TEXTURE0)) + @as(i64, unit));
    }
} else Disabled;

fn textureUnitEnum(unit: gl_GLint) gl_bindings.gl.GLenum {
    return @intCast(@as(i64, @intCast(gl_bindings.gl.GL_TEXTURE0)) + @as(i64, unit));
}

// ── TextCoverageRecords ──

/// Prepared per-glyph coverage records for a caller-owned material shader.
///
/// In the snail rewrite, the records are just the `u32` words `snail.emit.emit`
/// produces (the same `vertex.Instance` format the snail GPU draw consumes).
/// This struct is a thin wrapper that owns / borrows the words slice and
/// reports the implied glyph count for the caller's shader's
/// `u_snail_text_glyph_count` uniform.
///
/// To sample the records randomly in a fragment shader, upload the words
/// as a `GL_TEXTURE_BUFFER` of `GL_R32UI` and the shader's
/// `snail_text_sample_premul_linear(scene_pos)` (from `GlShaderSources.sample_functions`)
/// will walk it. The caller is responsible for the buffer-object lifecycle.
pub const TextCoverageRecords = struct {
    buffer: []u32,
    len: usize = 0,

    pub fn init(buffer: []u32) TextCoverageRecords {
        return .{ .buffer = buffer };
    }

    pub fn reset(self: *TextCoverageRecords) void {
        self.len = 0;
    }

    pub fn glyphCount(self: *const TextCoverageRecords) usize {
        return self.len / WORDS_PER_INSTANCE;
    }

    pub fn slice(self: *const TextCoverageRecords) []const u32 {
        return self.buffer[0..self.len];
    }
};

test {
    _ = WORDS_PER_INSTANCE;
}
