const std = @import("std");
const platform = @import("platform.zig");
const gl = platform.gl;
const shaders = @import("shaders.zig");
const vertex = @import("vertex.zig");
const vec = @import("../math/vec.zig");
const Mat4 = vec.Mat4;

var program: gl.GLuint = 0;
var program_subpixel: gl.GLuint = 0;
var mvp_loc: gl.GLint = -1;
var viewport_loc: gl.GLint = -1;
var curve_tex_loc: gl.GLint = -1;
var band_tex_loc: gl.GLint = -1;
var sp_mvp_loc: gl.GLint = -1;
var sp_viewport_loc: gl.GLint = -1;
var sp_curve_tex_loc: gl.GLint = -1;
var sp_band_tex_loc: gl.GLint = -1;

pub var subpixel_enabled: bool = false;

var vao: gl.GLuint = 0;
var vbo: gl.GLuint = 0;
var curve_texture: gl.GLuint = 0;
var band_texture: gl.GLuint = 0;

pub fn init() !void {
    program = try linkProgram(shaders.vertex_shader, shaders.fragment_shader);
    mvp_loc = gl.glGetUniformLocation(program, "u_mvp");
    viewport_loc = gl.glGetUniformLocation(program, "u_viewport");
    curve_tex_loc = gl.glGetUniformLocation(program, "u_curve_tex");
    band_tex_loc = gl.glGetUniformLocation(program, "u_band_tex");

    program_subpixel = try linkProgram(shaders.vertex_shader, shaders.fragment_shader_subpixel);
    sp_mvp_loc = gl.glGetUniformLocation(program_subpixel, "u_mvp");
    sp_viewport_loc = gl.glGetUniformLocation(program_subpixel, "u_viewport");
    sp_curve_tex_loc = gl.glGetUniformLocation(program_subpixel, "u_curve_tex");
    sp_band_tex_loc = gl.glGetUniformLocation(program_subpixel, "u_band_tex");

    gl.glGenVertexArrays(1, &vao);
    gl.glGenBuffers(1, &vbo);
    gl.glBindVertexArray(vao);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);

    const stride: gl.GLsizei = vertex.FLOATS_PER_VERTEX * @sizeOf(f32);

    // pos (location 0)
    gl.glVertexAttribPointer(0, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(0));
    gl.glEnableVertexAttribArray(0);
    // tex (location 1)
    gl.glVertexAttribPointer(1, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(4 * @sizeOf(f32)));
    gl.glEnableVertexAttribArray(1);
    // jac (location 2)
    gl.glVertexAttribPointer(2, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(8 * @sizeOf(f32)));
    gl.glEnableVertexAttribArray(2);
    // bnd (location 3)
    gl.glVertexAttribPointer(3, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(12 * @sizeOf(f32)));
    gl.glEnableVertexAttribArray(3);
    // col (location 4)
    gl.glVertexAttribPointer(4, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(16 * @sizeOf(f32)));
    gl.glEnableVertexAttribArray(4);

    gl.glBindVertexArray(0);
}

pub fn deinit() void {
    if (program != 0) gl.glDeleteProgram(program);
    if (program_subpixel != 0) gl.glDeleteProgram(program_subpixel);
    if (vao != 0) gl.glDeleteVertexArrays(1, &vao);
    if (vbo != 0) gl.glDeleteBuffers(1, &vbo);
    if (curve_texture != 0) gl.glDeleteTextures(1, &curve_texture);
    if (band_texture != 0) gl.glDeleteTextures(1, &band_texture);
}

pub fn uploadCurveTexture(data: []const f32, width: u32, height: u32) void {
    if (curve_texture == 0) gl.glGenTextures(1, &curve_texture);
    gl.glBindTexture(gl.GL_TEXTURE_2D, curve_texture);
    gl.glTexImage2D(
        gl.GL_TEXTURE_2D,
        0,
        gl.GL_RGBA32F,
        @intCast(width),
        @intCast(height),
        0,
        gl.GL_RGBA,
        gl.GL_FLOAT,
        data.ptr,
    );
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
}

pub fn uploadBandTexture(data: []const u16, width: u32, height: u32) void {
    if (band_texture == 0) gl.glGenTextures(1, &band_texture);
    gl.glBindTexture(gl.GL_TEXTURE_2D, band_texture);
    gl.glTexImage2D(
        gl.GL_TEXTURE_2D,
        0,
        gl.GL_RG16UI,
        @intCast(width),
        @intCast(height),
        0,
        gl.GL_RG_INTEGER,
        gl.GL_UNSIGNED_SHORT,
        data.ptr,
    );
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
}

pub fn drawText(vertices: []const f32, mvp: Mat4, viewport_w: f32, viewport_h: f32) void {
    const prog = if (subpixel_enabled) program_subpixel else program;
    const u_mvp = if (subpixel_enabled) sp_mvp_loc else mvp_loc;
    const u_vp = if (subpixel_enabled) sp_viewport_loc else viewport_loc;
    const u_ct = if (subpixel_enabled) sp_curve_tex_loc else curve_tex_loc;
    const u_bt = if (subpixel_enabled) sp_band_tex_loc else band_tex_loc;

    gl.glUseProgram(prog);
    gl.glUniformMatrix4fv(u_mvp, 1, gl.GL_FALSE, &mvp.data);
    gl.glUniform2f(u_vp, viewport_w, viewport_h);

    gl.glActiveTexture(gl.GL_TEXTURE0);
    gl.glBindTexture(gl.GL_TEXTURE_2D, curve_texture);
    gl.glUniform1i(u_ct, 0);

    gl.glActiveTexture(gl.GL_TEXTURE1);
    gl.glBindTexture(gl.GL_TEXTURE_2D, band_texture);
    gl.glUniform1i(u_bt, 1);

    gl.glBindVertexArray(vao);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);
    gl.glBufferData(
        gl.GL_ARRAY_BUFFER,
        @intCast(vertices.len * @sizeOf(f32)),
        vertices.ptr,
        gl.GL_STREAM_DRAW,
    );

    // Enable blending
    gl.glEnable(gl.GL_BLEND);
    gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA);

    const vertex_count: gl.GLsizei = @intCast(vertices.len / vertex.FLOATS_PER_VERTEX);
    gl.glDrawArrays(gl.GL_TRIANGLES, 0, vertex_count);

    gl.glDisable(gl.GL_BLEND);
    gl.glBindVertexArray(0);
}

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
        if (len > 0) {
            std.debug.print("Shader compile error:\n{s}\n", .{buf[0..@intCast(len)]});
        }
        gl.glDeleteShader(shader);
        return null;
    }
    return shader;
}

fn linkProgram(vs_src: [*c]const u8, fs_src: [*c]const u8) !gl.GLuint {
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
        if (len > 0) {
            std.debug.print("Shader link error:\n{s}\n", .{buf[0..@intCast(len)]});
        }
        return error.ShaderLinkFailed;
    }
    return prog;
}
