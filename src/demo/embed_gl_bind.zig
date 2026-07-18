//! Caller-side GL texture/uniform binding for snail's coverage contract.
//!
//! In the embeddable-only model the library ships the contract as *data*
//! The program locations, texture handles, and draw binding policy are all
//! caller-owned values defined here; Snail only supplies shader algorithms and
//! packed data contracts.
//! GL calls — so `snail.shader.glsl` links no OpenGL, exactly like the Vulkan contract links
//! no Vulkan. The actual `glBindTexture`/`glUniform*` loop lives here, in caller
//! code, because the caller owns the GL context. This is the GL analog of the
//! Vulkan reference renderer binding its own descriptor set.
//!
//! `Gl{33,44}Backend` / `Gles30Backend` are thin values over the four atlas
//! texture handles; `.from(handles)` then `bindProgram` + `bindDrawState`.

const snail = @import("snail");
const render_state = @import("render-state");

const gl_bindings = @import("embed_gl_bindings.zig");
const gles30_bindings = @import("embed_gles30_bindings.zig");

const Variant = enum { gl33, gl44 };
const FillRule = snail.FillRule;

pub const DrawState = struct {
    subpixel_order: render_state.SubpixelOrder = .none,
    output_srgb: bool = false,
    coverage_transfer: render_state.CoverageTransfer = .identity,
    layer_base: u32 = 0,
};

pub const GlProgram = struct {
    curve_tex_loc: i32 = -1,
    band_tex_loc: i32 = -1,
    layer_tex_loc: i32 = -1,
    image_tex_loc: i32 = -1,
    fill_rule_loc: i32 = -1,
    subpixel_order_loc: i32 = -1,
    output_srgb_loc: i32 = -1,
    coverage_exponent_loc: i32 = -1,
    layer_base_loc: i32 = -1,
    curve_tex_unit: i32 = 0,
    band_tex_unit: i32 = 1,
    layer_tex_unit: i32 = 2,
    image_tex_unit: i32 = 3,
};

pub const Gles30Program = GlProgram;

pub const TextureHandles = struct {
    curve_array: u32 = 0,
    band_array: u32 = 0,
    layer_info_tex: u32 = 0,
    image_array_tex: u32 = 0,
};

fn GlBackendFor(comptime variant: Variant) type {
    return struct {
        const Self = @This();
        const dsa = (variant == .gl44);

        tex: TextureHandles,

        /// Build from the caller's atlas texture handles (read off its cache).
        pub fn from(tex: TextureHandles) Self {
            return .{ .tex = tex };
        }

        /// Bind snail's atlas textures to the texture units named in `program`.
        pub fn bindProgram(self: Self, program: GlProgram) !void {
            const gl = gl_bindings.gl;
            if (dsa) {
                gl.glBindTextureUnit(@intCast(program.curve_tex_unit), self.tex.curve_array);
                gl.glBindTextureUnit(@intCast(program.band_tex_unit), self.tex.band_array);
                if (program.layer_tex_loc >= 0 and self.tex.layer_info_tex != 0)
                    gl.glBindTextureUnit(@intCast(program.layer_tex_unit), self.tex.layer_info_tex);
                if (program.image_tex_loc >= 0 and self.tex.image_array_tex != 0)
                    gl.glBindTextureUnit(@intCast(program.image_tex_unit), self.tex.image_array_tex);
            } else {
                gl.glActiveTexture(textureUnitEnum(program.curve_tex_unit));
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.tex.curve_array);
                gl.glActiveTexture(textureUnitEnum(program.band_tex_unit));
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.tex.band_array);
                if (program.layer_tex_loc >= 0 and self.tex.layer_info_tex != 0) {
                    gl.glActiveTexture(textureUnitEnum(program.layer_tex_unit));
                    gl.glBindTexture(gl.GL_TEXTURE_2D, self.tex.layer_info_tex);
                }
                if (program.image_tex_loc >= 0 and self.tex.image_array_tex != 0) {
                    gl.glActiveTexture(textureUnitEnum(program.image_tex_unit));
                    gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.tex.image_array_tex);
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

        fn textureUnitEnum(unit: gl_bindings.gl.GLint) gl_bindings.gl.GLenum {
            return @intCast(@as(i64, @intCast(gl_bindings.gl.GL_TEXTURE0)) + @as(i64, unit));
        }
    };
}

pub const Gl33Backend = GlBackendFor(.gl33);
pub const Gl44Backend = GlBackendFor(.gl44);

pub const Gles30Backend = struct {
    const Self = @This();

    tex: TextureHandles,

    pub fn from(tex: TextureHandles) Self {
        return .{ .tex = tex };
    }

    pub fn bindProgram(self: Self, program: Gles30Program) !void {
        const gl = gles30_bindings.gl;
        gl.glActiveTexture(textureUnitEnumGles(program.curve_tex_unit));
        gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.tex.curve_array);
        gl.glActiveTexture(textureUnitEnumGles(program.band_tex_unit));
        gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.tex.band_array);
        if (program.layer_tex_loc >= 0 and self.tex.layer_info_tex != 0) {
            gl.glActiveTexture(textureUnitEnumGles(program.layer_tex_unit));
            gl.glBindTexture(gl.GL_TEXTURE_2D, self.tex.layer_info_tex);
        }
        if (program.image_tex_loc >= 0 and self.tex.image_array_tex != 0) {
            gl.glActiveTexture(textureUnitEnumGles(program.image_tex_unit));
            gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.tex.image_array_tex);
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

    fn textureUnitEnumGles(unit: gles30_bindings.gl.GLint) gles30_bindings.gl.GLenum {
        return @intCast(@as(i64, @intCast(gles30_bindings.gl.GL_TEXTURE0)) + @as(i64, unit));
    }
};
