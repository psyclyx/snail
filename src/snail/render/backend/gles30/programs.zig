const std = @import("std");
const gl = @import("bindings.zig").gl;

pub const ProgramState = struct {
    handle: gl.GLuint = 0,
    mvp_loc: gl.GLint = -1,
    viewport_loc: gl.GLint = -1,
    curve_tex_loc: gl.GLint = -1,
    band_tex_loc: gl.GLint = -1,
    image_tex_loc: gl.GLint = -1,
    fill_rule_loc: gl.GLint = -1,
    subpixel_order_loc: gl.GLint = -1,
    output_srgb_loc: gl.GLint = -1,
    coverage_exponent_loc: gl.GLint = -1,
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
        .layer_tex_loc = gl.glGetUniformLocation(handle, "u_layer_tex"),
        .layer_base_loc = gl.glGetUniformLocation(handle, "u_layer_base"),
    };

    // Sampler bindings (units 0..3 → curve/band/layer/image) and
    // `u_layer_base` never change at runtime, so set them once at link
    // time to remove a half-dozen `glUniform1i` calls from every draw.
    // Matches the GL 3.3/4.4 path in `gl/programs.zig`.
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

pub fn deleteProgramState(prog_state: *ProgramState) void {
    if (prog_state.handle != 0) gl.glDeleteProgram(prog_state.handle);
    prog_state.* = .{};
}

pub fn linkProgram(_: []const u8, vs_src: [*c]const u8, fs_src: [*c]const u8, dual_source: bool) !gl.GLuint {
    _ = dual_source;
    const vs = compileShader(gl.GL_VERTEX_SHADER, vs_src) orelse return error.VertexShaderFailed;
    defer gl.glDeleteShader(vs);
    const fs = compileShader(gl.GL_FRAGMENT_SHADER, fs_src) orelse return error.FragmentShaderFailed;
    defer gl.glDeleteShader(fs);

    const prog = gl.glCreateProgram();
    gl.glAttachShader(prog, vs);
    gl.glAttachShader(prog, fs);
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
