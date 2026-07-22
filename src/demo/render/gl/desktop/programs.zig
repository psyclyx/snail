const std = @import("std");
const gl = @import("bindings.zig").gl;
const gl_common = @import("../common.zig");
const slang_gen = @import("snail").shader.generated;

pub const ProgramState = struct {
    handle: gl.GLuint = 0,
    /// Non-zero for the native-Slang text program: the 96-byte UBO backing
    /// its `SnailPushConstants` uniform blocks (loose-uniform locs stay -1).
    ubo: gl.GLuint = 0,
    mvp_loc: gl.GLint = -1,
    viewport_loc: gl.GLint = -1,
    curve_tex_loc: gl.GLint = -1,
    band_tex_loc: gl.GLint = -1,
    image_tex_loc: gl.GLint = -1,
    fill_rule_loc: gl.GLint = -1,
    subpixel_order_loc: gl.GLint = -1,
    output_srgb_loc: gl.GLint = -1,
    coverage_exponent_loc: gl.GLint = -1,
    dither_scale_loc: gl.GLint = -1,
    mask_output_loc: gl.GLint = -1,
    layer_tex_loc: gl.GLint = -1,
    layer_base_loc: gl.GLint = -1,
};

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
        if (len > 0) std.debug.print("Shader compile error:\n{s}\n", .{buf[0..@intCast(len)]});
        gl.glDeleteShader(shader);
        return null;
    }
    return shader;
}

pub fn loadProgramState(cache_label: []const u8, vs_src: [*c]const u8, fs_src: [*c]const u8, dual_source: bool) !ProgramState {
    const handle = try linkProgram(cache_label, vs_src, fs_src, dual_source);
    const ps = ProgramState{
        .handle = handle,
        .mvp_loc = gl.glGetUniformLocation(handle, "u_mvp"),
        .viewport_loc = gl.glGetUniformLocation(handle, "u_viewport"),
        .curve_tex_loc = gl.glGetUniformLocation(handle, "u_curve_tex"),
        .band_tex_loc = gl.glGetUniformLocation(handle, "u_band_tex"),
        .image_tex_loc = gl.glGetUniformLocation(handle, "u_image_tex"),
        .fill_rule_loc = gl.glGetUniformLocation(handle, "u_fill_rule"),
        .subpixel_order_loc = gl.glGetUniformLocation(handle, "u_subpixel_order"),
        .output_srgb_loc = gl.glGetUniformLocation(handle, "u_output_srgb"),
        .coverage_exponent_loc = gl.glGetUniformLocation(handle, "u_coverage_exponent"),
        .dither_scale_loc = gl.glGetUniformLocation(handle, "u_dither_scale"),
        .mask_output_loc = gl.glGetUniformLocation(handle, "u_mask_output"),
        .layer_tex_loc = gl.glGetUniformLocation(handle, "u_layer_tex"),
        .layer_base_loc = gl.glGetUniformLocation(handle, "u_layer_base"),
    };

    // Sampler bindings (texture units) and `u_layer_base` never change at
    // runtime — units 0..3 stay mapped to curve/band/layer/image, and
    // `u_layer_base` is always 0 in the new ABI (absolute layer is encoded
    // per-instance). Setting these once at link time removes a half-dozen
    // glUniform1i calls from every draw.
    var prev_program: gl.GLint = 0;
    gl.glGetIntegerv(gl.GL_CURRENT_PROGRAM, &prev_program);
    gl.glUseProgram(handle);
    if (ps.curve_tex_loc >= 0) gl.glUniform1i(ps.curve_tex_loc, 0);
    if (ps.band_tex_loc >= 0) gl.glUniform1i(ps.band_tex_loc, 1);
    if (ps.layer_tex_loc >= 0) gl.glUniform1i(ps.layer_tex_loc, 2);
    if (ps.image_tex_loc >= 0) gl.glUniform1i(ps.image_tex_loc, 3);
    if (ps.layer_base_loc >= 0) gl.glUniform1i(ps.layer_base_loc, 0);
    gl.glUseProgram(@intCast(prev_program));
    return ps;
}

/// Link a native-Slang program (generated GLSL 330; see
/// `snail.shader.generated`). Uniforms live in one 96-byte std140
/// block per stage — both block indices are bound to
/// `NATIVE_TEXT_UBO_BINDING`, backed by the UBO created here — and the
/// generated combined samplers are pinned to texture units 0..3
/// (curve/band/layer/image) at link time, exactly like the composed
/// programs. Sampler locations that a family's fragment does not declare
/// resolve to -1 and stay unbound (the shadow-cache binder keys off them).
pub fn loadNativeProgramState(cache_label: []const u8, vs_src: [*c]const u8, fs_src: [*c]const u8) !ProgramState {
    const handle = try linkProgram(cache_label, vs_src, fs_src, false);
    var ps = ProgramState{
        .handle = handle,
        .curve_tex_loc = gl.glGetUniformLocation(handle, slang_gen.glsl_curve_tex_name),
        .band_tex_loc = gl.glGetUniformLocation(handle, slang_gen.glsl_band_tex_name),
        .layer_tex_loc = gl.glGetUniformLocation(handle, slang_gen.glsl_layer_tex_name),
        .image_tex_loc = gl.glGetUniformLocation(handle, slang_gen.glsl_image_tex_name),
    };

    // Both stages declare the identically-named, identically-shaped block,
    // so the linker merges them into one block index.
    const push_block = gl.glGetUniformBlockIndex(handle, slang_gen.glsl_vertex_block_name);
    if (push_block == gl.GL_INVALID_INDEX) {
        gl.glDeleteProgram(handle);
        return error.ShaderLinkFailed;
    }
    gl.glUniformBlockBinding(handle, push_block, gl_common.NATIVE_TEXT_UBO_BINDING);

    gl.glGenBuffers(1, &ps.ubo);
    gl.glBindBuffer(gl.GL_UNIFORM_BUFFER, ps.ubo);
    gl.glBufferData(gl.GL_UNIFORM_BUFFER, @sizeOf(gl_common.NativeTextPushBlock), null, gl.GL_DYNAMIC_DRAW);
    gl.glBindBuffer(gl.GL_UNIFORM_BUFFER, 0);

    // u_image_tex is both Loaded and Sampled, so SPIRV-Cross emits a
    // second combined uniform for the Sample sites; pin it to the same
    // image unit. (The autohint vertex stage's layer read shares the
    // fragment's combined-sampler name — the linker merged them above.)
    const image_sampled_loc = gl.glGetUniformLocation(handle, slang_gen.glsl_image_tex_sampled_name);

    var prev_program: gl.GLint = 0;
    gl.glGetIntegerv(gl.GL_CURRENT_PROGRAM, &prev_program);
    gl.glUseProgram(handle);
    if (ps.curve_tex_loc >= 0) gl.glUniform1i(ps.curve_tex_loc, 0);
    if (ps.band_tex_loc >= 0) gl.glUniform1i(ps.band_tex_loc, 1);
    if (ps.layer_tex_loc >= 0) gl.glUniform1i(ps.layer_tex_loc, 2);
    if (ps.image_tex_loc >= 0) gl.glUniform1i(ps.image_tex_loc, 3);
    if (image_sampled_loc >= 0) gl.glUniform1i(image_sampled_loc, 3);
    gl.glUseProgram(@intCast(prev_program));
    return ps;
}

pub fn deleteProgramState(prog_state: *ProgramState) void {
    if (prog_state.handle != 0) gl.glDeleteProgram(prog_state.handle);
    if (prog_state.ubo != 0) gl.glDeleteBuffers(1, &prog_state.ubo);
    prog_state.* = .{};
}

pub fn linkProgram(_: []const u8, vs_src: [*c]const u8, fs_src: [*c]const u8, dual_source: bool) !gl.GLuint {
    const vs = compileShader(gl.GL_VERTEX_SHADER, vs_src) orelse return error.VertexShaderFailed;
    defer gl.glDeleteShader(vs);
    const fs = compileShader(gl.GL_FRAGMENT_SHADER, fs_src) orelse return error.FragmentShaderFailed;
    defer gl.glDeleteShader(fs);

    const prog = gl.glCreateProgram();
    gl.glAttachShader(prog, vs);
    gl.glAttachShader(prog, fs);
    if (dual_source) {
        gl.glBindFragDataLocationIndexed(prog, 0, 0, "frag_color");
        gl.glBindFragDataLocationIndexed(prog, 0, 1, "frag_blend");
    }
    gl.glLinkProgram(prog);

    var ok: gl.GLint = 0;
    gl.glGetProgramiv(prog, gl.GL_LINK_STATUS, &ok);
    if (ok == 0) {
        var buf: [4096]u8 = undefined;
        var len: gl.GLsizei = 0;
        gl.glGetProgramInfoLog(prog, 4096, &len, &buf);
        if (len > 0) std.debug.print("Shader link error:\n{s}\n", .{buf[0..@intCast(len)]});
        return error.ShaderLinkFailed;
    }
    return prog;
}
