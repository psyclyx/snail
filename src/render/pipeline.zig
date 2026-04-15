const std = @import("std");
const platform = @import("platform.zig");
const gl = platform.gl;
const shaders = @import("shaders.zig");
const vertex = @import("vertex.zig");
const vec = @import("../math/vec.zig");
const Mat4 = vec.Mat4;
const snail_mod = @import("../snail.zig");

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
var fill_rule_loc: gl.GLint = -1;
var sp_fill_rule_loc: gl.GLint = -1;

pub var subpixel_enabled: bool = false;
pub var fill_rule: FillRule = .non_zero;

pub const FillRule = enum(c_int) {
    non_zero = 0,
    even_odd = 1,
};

var vao: gl.GLuint = 0;
var vbo: gl.GLuint = 0;
var ebo: gl.GLuint = 0;
var ebo_glyph_capacity: u32 = 0; // how many glyphs the EBO can handle

// Texture array handles
var curve_array: gl.GLuint = 0;
var band_array: gl.GLuint = 0;

// State tracking
var active_program: gl.GLuint = 0;
var frame_begun: bool = false;

pub fn init() !void {
    program = try linkProgram(shaders.vertex_shader, shaders.fragment_shader);
    mvp_loc = gl.glGetUniformLocation(program, "u_mvp");
    viewport_loc = gl.glGetUniformLocation(program, "u_viewport");
    curve_tex_loc = gl.glGetUniformLocation(program, "u_curve_tex");
    band_tex_loc = gl.glGetUniformLocation(program, "u_band_tex");
    fill_rule_loc = gl.glGetUniformLocation(program, "u_fill_rule");

    program_subpixel = try linkProgram(shaders.vertex_shader, shaders.fragment_shader_subpixel);
    sp_mvp_loc = gl.glGetUniformLocation(program_subpixel, "u_mvp");
    sp_viewport_loc = gl.glGetUniformLocation(program_subpixel, "u_viewport");
    sp_curve_tex_loc = gl.glGetUniformLocation(program_subpixel, "u_curve_tex");
    sp_band_tex_loc = gl.glGetUniformLocation(program_subpixel, "u_band_tex");
    sp_fill_rule_loc = gl.glGetUniformLocation(program_subpixel, "u_fill_rule");

    gl.glGenVertexArrays(1, &vao);
    gl.glGenBuffers(1, &vbo);
    gl.glGenBuffers(1, &ebo);
    gl.glBindVertexArray(vao);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);
    gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, ebo);

    // Pre-build index buffer for 10000 quads
    ensureEboCapacity(10000);

    const stride: gl.GLsizei = vertex.FLOATS_PER_VERTEX * @sizeOf(f32);

    gl.glVertexAttribPointer(0, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(0));
    gl.glEnableVertexAttribArray(0);
    gl.glVertexAttribPointer(1, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(4 * @sizeOf(f32)));
    gl.glEnableVertexAttribArray(1);
    gl.glVertexAttribPointer(2, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(8 * @sizeOf(f32)));
    gl.glEnableVertexAttribArray(2);
    gl.glVertexAttribPointer(3, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(12 * @sizeOf(f32)));
    gl.glEnableVertexAttribArray(3);
    gl.glVertexAttribPointer(4, 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(16 * @sizeOf(f32)));
    gl.glEnableVertexAttribArray(4);

    gl.glEnable(gl.GL_BLEND);
    gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA);
}

pub fn deinit() void {
    if (program != 0) gl.glDeleteProgram(program);
    if (program_subpixel != 0) gl.glDeleteProgram(program_subpixel);
    if (vao != 0) gl.glDeleteVertexArrays(1, &vao);
    if (vbo != 0) gl.glDeleteBuffers(1, &vbo);
    if (ebo != 0) gl.glDeleteBuffers(1, &ebo);
    if (curve_array != 0) gl.glDeleteTextures(1, &curve_array);
    if (band_array != 0) gl.glDeleteTextures(1, &band_array);
}

/// Build GL_TEXTURE_2D_ARRAY for curve and band data from multiple atlases.
/// Each atlas becomes one layer. Assigns gl_layer on each atlas.
pub fn buildTextureArrays(atlases: []const *const snail_mod.Atlas) void {
    // Delete old arrays
    if (curve_array != 0) gl.glDeleteTextures(1, &curve_array);
    if (band_array != 0) gl.glDeleteTextures(1, &band_array);

    const layer_count: gl.GLsizei = @intCast(atlases.len);

    // Find max dimensions (width is always 4096, height varies)
    var max_curve_h: u32 = 1;
    var max_band_h: u32 = 1;
    for (atlases) |a| {
        if (a.curve_height > max_curve_h) max_curve_h = a.curve_height;
        if (a.band_height > max_band_h) max_band_h = a.band_height;
    }

    // Create curve texture array (RGBA16F)
    gl.glGenTextures(1, &curve_array);
    gl.glActiveTexture(gl.GL_TEXTURE0);
    gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, curve_array);
    gl.glTexImage3D(
        gl.GL_TEXTURE_2D_ARRAY,
        0,
        gl.GL_RGBA16F,
        @intCast(atlases[0].curve_width),
        @intCast(max_curve_h),
        layer_count,
        0,
        gl.GL_RGBA,
        gl.GL_HALF_FLOAT,
        null, // allocate only
    );
    gl.glTexParameteri(gl.GL_TEXTURE_2D_ARRAY, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D_ARRAY, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D_ARRAY, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(gl.GL_TEXTURE_2D_ARRAY, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);

    // Create band texture array (RG16UI)
    gl.glGenTextures(1, &band_array);
    gl.glActiveTexture(gl.GL_TEXTURE1);
    gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, band_array);
    gl.glTexImage3D(
        gl.GL_TEXTURE_2D_ARRAY,
        0,
        gl.GL_RG16UI,
        @intCast(atlases[0].band_width),
        @intCast(max_band_h),
        layer_count,
        0,
        gl.GL_RG_INTEGER,
        gl.GL_UNSIGNED_SHORT,
        null,
    );
    gl.glTexParameteri(gl.GL_TEXTURE_2D_ARRAY, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D_ARRAY, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D_ARRAY, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(gl.GL_TEXTURE_2D_ARRAY, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);

    // Upload each atlas as a layer
    for (atlases, 0..) |atlas, i| {
        const a = @constCast(atlas);
        a.gl_layer = @intCast(i);

        // Upload curve data into layer i
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, curve_array);
        gl.glTexSubImage3D(
            gl.GL_TEXTURE_2D_ARRAY,
            0,
            0, 0, @intCast(i), // x, y, layer offsets
            @intCast(atlas.curve_width),
            @intCast(atlas.curve_height),
            1, // one layer
            gl.GL_RGBA,
            gl.GL_HALF_FLOAT,
            atlas.curve_data.ptr,
        );

        // Upload band data into layer i
        gl.glActiveTexture(gl.GL_TEXTURE1);
        gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, band_array);
        gl.glTexSubImage3D(
            gl.GL_TEXTURE_2D_ARRAY,
            0,
            0, 0, @intCast(i),
            @intCast(atlas.band_width),
            @intCast(atlas.band_height),
            1,
            gl.GL_RG_INTEGER,
            gl.GL_UNSIGNED_SHORT,
            atlas.band_data.ptr,
        );
    }

    // Reset state
    active_program = 0;
    frame_begun = false;
}

pub fn deleteTexture(tex: *gl.GLuint) void {
    if (tex.* != 0) {
        gl.glDeleteTextures(1, tex);
        tex.* = 0;
    }
}

// Legacy single-texture APIs (used by C API for backward compat)
pub fn createCurveTexture(data: []const u16, width: u32, height: u32) gl.GLuint {
    _ = data;
    _ = width;
    _ = height;
    return 0; // No-op — use buildTextureArrays
}

pub fn createBandTexture(data: []const u16, width: u32, height: u32) gl.GLuint {
    _ = data;
    _ = width;
    _ = height;
    return 0;
}

pub fn bindTextures(curve: gl.GLuint, band: gl.GLuint) void {
    _ = curve;
    _ = band;
    // No-op — texture arrays are always bound
}

pub fn drawText(vertices: []const f32, mvp: Mat4, viewport_w: f32, viewport_h: f32) void {
    const prog = if (subpixel_enabled) program_subpixel else program;

    if (prog != active_program or !frame_begun) {
        gl.glUseProgram(prog);
        active_program = prog;

        // Bind texture arrays
        gl.glActiveTexture(gl.GL_TEXTURE0);
        gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, curve_array);
        gl.glActiveTexture(gl.GL_TEXTURE1);
        gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, band_array);

        const u_ct = if (subpixel_enabled) sp_curve_tex_loc else curve_tex_loc;
        const u_bt = if (subpixel_enabled) sp_band_tex_loc else band_tex_loc;
        gl.glUniform1i(u_ct, 0);
        gl.glUniform1i(u_bt, 1);
        frame_begun = true;
    }

    const u_mvp = if (subpixel_enabled) sp_mvp_loc else mvp_loc;
    const u_vp = if (subpixel_enabled) sp_viewport_loc else viewport_loc;
    const u_fr = if (subpixel_enabled) sp_fill_rule_loc else fill_rule_loc;
    gl.glUniformMatrix4fv(u_mvp, 1, gl.GL_FALSE, &mvp.data);
    gl.glUniform2f(u_vp, viewport_w, viewport_h);
    gl.glUniform1i(u_fr, @intFromEnum(fill_rule));

    gl.glBufferData(
        gl.GL_ARRAY_BUFFER,
        @intCast(vertices.len * @sizeOf(f32)),
        vertices.ptr,
        gl.GL_STREAM_DRAW,
    );

    const glyph_count = vertices.len / (vertex.FLOATS_PER_VERTEX * vertex.VERTICES_PER_GLYPH);
    ensureEboCapacity(@intCast(glyph_count));
    const index_count: gl.GLsizei = @intCast(glyph_count * 6);
    gl.glDrawElements(gl.GL_TRIANGLES, index_count, gl.GL_UNSIGNED_INT, null);
}

/// Ensure the EBO has indices for at least `glyph_count` quads.
fn ensureEboCapacity(glyph_count: u32) void {
    if (glyph_count <= ebo_glyph_capacity) return;

    // Grow to at least requested, with some headroom
    const target = @max(glyph_count, ebo_glyph_capacity * 2);
    const index_count = target * 6;

    // Build index data on stack for reasonable sizes, heap otherwise
    var stack_buf: [60000]u32 = undefined;
    const indices: []u32 = if (index_count <= stack_buf.len)
        stack_buf[0..index_count]
    else
        return; // 10000 glyphs should be enough; don't allocate

    for (0..target) |i| {
        const base: u32 = @intCast(i * 4);
        const idx = i * 6;
        indices[idx + 0] = base + 0;
        indices[idx + 1] = base + 1;
        indices[idx + 2] = base + 2;
        indices[idx + 3] = base + 0;
        indices[idx + 4] = base + 2;
        indices[idx + 5] = base + 3;
    }

    gl.glBufferData(
        gl.GL_ELEMENT_ARRAY_BUFFER,
        @intCast(index_count * @sizeOf(u32)),
        indices.ptr,
        gl.GL_STATIC_DRAW,
    );
    ebo_glyph_capacity = target;
}

pub fn resetFrameState() void {
    frame_begun = false;
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
