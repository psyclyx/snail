//! Custom GL material renderer for the game demo, generic over the GL family
//! (gl33 / gl44 / gles30).
//!
//! This is the "custom shader" showcase: a caller-authored fragment shader that
//! samples snail glyph coverage at arbitrary UVs via
//! `snail.shader.glsl` (`snail_text_sample_premul_linear`) and
//! lights it over an opaque panel. The per-glyph emit words are uploaded once
//! into the records storage the interface expects — a `GL_TEXTURE_BUFFER` on
//! desktop GL, a 2D `GL_R32UI` texture on GLES 3.0 (no buffer textures there).
//!
//! The atlas plane (curve/band arrays) is bound off the same
//! `*BackendCache` the standard snail passes use, via `embed_gl.*Backend`.

const std = @import("std");
const snail = @import("snail");
const embed_gl = @import("embed_gl");
const glsl = snail.shader.glsl;
const common = @import("common.zig");
const desktop_gl = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("GL/gl.h");
    @cInclude("GL/glext.h");
});
const gles_gl = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", "1");
    @cInclude("GLES3/gl3.h");
    @cInclude("GLES2/gl2ext.h");
});

pub const Variant = enum { gl33, gl44, gles30 };

const RECORD_UNIT: i32 = 2;
const CURVE_UNIT: i32 = 3;
const BAND_UNIT: i32 = 4;

/// Build the material renderer type for one GL variant. Bundles the right gl
/// bindings, shader-source set, atlas-binding backend, cache, and program
/// descriptor so the whole family shares one implementation.
pub fn GlMaterial(comptime variant: Variant) type {
    return struct {
        const Self = @This();

        const gl = switch (variant) {
            .gl33, .gl44 => desktop_gl,
            .gles30 => gles_gl,
        };
        pub const Cache = switch (variant) {
            .gl33 => embed_gl.Gl33BackendCache,
            .gl44 => embed_gl.Gl44BackendCache,
            .gles30 => embed_gl.Gles30BackendCache,
        };
        const Backend = switch (variant) {
            .gl33 => embed_gl.Gl33Backend,
            .gl44 => embed_gl.Gl44Backend,
            .gles30 => embed_gl.Gles30Backend,
        };
        const Program = switch (variant) {
            .gles30 => embed_gl.Gles30Program,
            else => embed_gl.GlProgram,
        };
        const version_prefix = switch (variant) {
            // snail's own GL 3.3/4.4 shaders are both #version 330 core (DSA is
            // an API concern, not a shader-dialect one), so the material matches.
            .gl33, .gl44 => "#version 330 core\n",
            .gles30 => "#version 300 es\n" ++
                "precision highp float;\n" ++
                "precision highp int;\n" ++
                "precision highp sampler2DArray;\n" ++
                "precision highp usampler2DArray;\n" ++
                "precision highp usampler2D;\n",
        };
        const records_interface = switch (variant) {
            .gl33, .gl44 => glsl.source(.text_sample_interface_gl),
            .gles30 => glsl.source(.text_sample_interface_gles),
        };
        const records_width = glsl.gles_records_texture_width;
        const record_stride = std.fmt.comptimePrint(
            "#define SNAIL_TEXT_RECORD_WORDS_PER_GLYPH {d}\n",
            .{snail.render.records.BYTES_PER_INSTANCE / @sizeOf(u32)},
        );
        const coverage_resources =
            \\uniform sampler2DArray u_curve_tex;
            \\uniform usampler2DArray u_band_tex;
            \\uniform int u_fill_rule;
            \\uniform int u_layer_base;
            \\#define SNAIL_FILL_RULE u_fill_rule
            \\
        ;

        program: gl.GLuint = 0,
        vao: gl.GLuint = 0,
        vbo: gl.GLuint = 0,
        ebo: gl.GLuint = 0,
        // records storage: TBO (buffer + texture view) on desktop, 2D texture on ES.
        rec_buffer: gl.GLuint = 0,
        rec_texture: gl.GLuint = 0,
        glyph_count: i32 = 0,

        // uniforms
        u_view_proj: gl.GLint = -1,
        u_model: gl.GLint = -1,
        u_scene_size: gl.GLint = -1,
        u_light_dir: gl.GLint = -1,
        u_relief: gl.GLint = -1,
        u_roughness: gl.GLint = -1,
        u_base_color: gl.GLint = -1,
        u_output_srgb: gl.GLint = -1,
        u_records: gl.GLint = -1,
        u_glyph_count: gl.GLint = -1,
        u_curve_tex: gl.GLint = -1,
        u_band_tex: gl.GLint = -1,
        u_fill_rule: gl.GLint = -1,
        u_layer_base: gl.GLint = -1,

        pub fn init(
            self: *Self,
            allocator: std.mem.Allocator,
            cache: *Cache,
            material_pass: anytype, // *const passes.PreparedPass
        ) !void {
            self.* = .{};
            self.program = try common.linkProgram(vertex_src, fragment_src);
            errdefer gl.glDeleteProgram(self.program);

            self.u_view_proj = gl.glGetUniformLocation(self.program, "u_view_proj");
            self.u_model = gl.glGetUniformLocation(self.program, "u_model");
            self.u_scene_size = gl.glGetUniformLocation(self.program, "u_scene_size");
            self.u_light_dir = gl.glGetUniformLocation(self.program, "u_light_dir");
            self.u_relief = gl.glGetUniformLocation(self.program, "u_relief");
            self.u_roughness = gl.glGetUniformLocation(self.program, "u_roughness");
            self.u_base_color = gl.glGetUniformLocation(self.program, "u_base_color");
            self.u_output_srgb = gl.glGetUniformLocation(self.program, "u_output_srgb");
            self.u_records = gl.glGetUniformLocation(self.program, "u_snail_text_records");
            self.u_glyph_count = gl.glGetUniformLocation(self.program, "u_snail_text_glyph_count");
            self.u_curve_tex = gl.glGetUniformLocation(self.program, "u_curve_tex");
            self.u_band_tex = gl.glGetUniformLocation(self.program, "u_band_tex");
            self.u_fill_rule = gl.glGetUniformLocation(self.program, "u_fill_rule");
            self.u_layer_base = gl.glGetUniformLocation(self.program, "u_layer_base");

            try self.initGeometry();
            try self.uploadRecords(allocator, cache, material_pass);
        }

        fn initGeometry(self: *Self) !void {
            // Unit quad in [-0.5,0.5]², uv in [0,1].
            const verts = [_]f32{
                -0.5, -0.5, 0.0, 0.0, 0.0,
                0.5,  -0.5, 0.0, 1.0, 0.0,
                0.5,  0.5,  0.0, 1.0, 1.0,
                -0.5, 0.5,  0.0, 0.0, 1.0,
            };
            const idx = [_]u32{ 1, 2, 0, 2, 3, 0 };
            gl.glGenVertexArrays(1, &self.vao);
            gl.glGenBuffers(1, &self.vbo);
            gl.glGenBuffers(1, &self.ebo);
            gl.glBindVertexArray(self.vao);
            gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
            gl.glBufferData(gl.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(verts)), &verts, gl.GL_STATIC_DRAW);
            gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ebo);
            gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(idx)), &idx, gl.GL_STATIC_DRAW);
            const stride: gl.GLsizei = 5 * @sizeOf(f32);
            gl.glEnableVertexAttribArray(0);
            gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(0));
            gl.glEnableVertexAttribArray(1);
            gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(3 * @sizeOf(f32)));
            gl.glBindVertexArray(0);
        }

        fn uploadRecords(self: *Self, allocator: std.mem.Allocator, cache: *Cache, material_pass: anytype) !void {
            // Upload the material text atlas into the shared cache, emit its
            // words (encoding the absolute atlas layer), then mirror the words
            // into the records storage the shader samples.
            var binding: [1]snail.render.records.Binding = undefined;
            try cache.upload(allocator, &.{&material_pass.text_atlas}, &binding);

            const shapes = material_pass.text_picture.shapes;
            const instances = try allocator.alloc(snail.render.records.Instance, shapes.len);
            defer allocator.free(instances);
            var segs: [4]snail.render.records.DrawBatch = undefined;
            var ilen: usize = 0;
            var blen: usize = 0;
            _ = try snail.emit.emit(instances, &segs, &ilen, &blen, binding[0], &material_pass.text_atlas, shapes, .identity, .{ 1, 1, 1, 1 });

            self.glyph_count = @intCast(ilen);
            // The sample shader reads the packed instances as R32UI texels.
            const words: []const u32 = @ptrCast(std.mem.sliceAsBytes(instances[0..ilen]));
            const wlen = words.len;

            switch (variant) {
                .gl33, .gl44 => {
                    gl.glGenBuffers(1, &self.rec_buffer);
                    gl.glGenTextures(1, &self.rec_texture);
                    gl.glBindBuffer(gl.GL_TEXTURE_BUFFER, self.rec_buffer);
                    gl.glBufferData(gl.GL_TEXTURE_BUFFER, @intCast(wlen * @sizeOf(u32)), words.ptr, gl.GL_STATIC_DRAW);
                    gl.glBindTexture(gl.GL_TEXTURE_BUFFER, self.rec_texture);
                    gl.glTexBuffer(gl.GL_TEXTURE_BUFFER, gl.GL_R32UI, self.rec_buffer);
                    gl.glBindTexture(gl.GL_TEXTURE_BUFFER, 0);
                    gl.glBindBuffer(gl.GL_TEXTURE_BUFFER, 0);
                },
                .gles30 => {
                    // 2D R32UI texture, row-major at the width the ES interface
                    // expects; pad the tail row with zeros.
                    const w: usize = records_width;
                    const rows = (wlen + w - 1) / w;
                    const padded = try allocator.alloc(u32, rows * w);
                    defer allocator.free(padded);
                    @memset(padded, 0);
                    @memcpy(padded[0..wlen], words[0..wlen]);
                    gl.glGenTextures(1, &self.rec_texture);
                    gl.glBindTexture(gl.GL_TEXTURE_2D, self.rec_texture);
                    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
                    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
                    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
                    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
                    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_R32UI, @intCast(w), @intCast(rows), 0, gl.GL_RED_INTEGER, gl.GL_UNSIGNED_INT, padded.ptr);
                    gl.glBindTexture(gl.GL_TEXTURE_2D, 0);
                },
            }
        }

        /// Draw the material quad under the demo's fixed tangent-space light.
        pub fn draw(
            self: *const Self,
            cache: *const Cache,
            view_proj: snail.Mat4,
            model: snail.Mat4,
            scene_size: [2]f32,
            base_color: [4]f32,
            light_dir: [3]f32,
            relief: f32,
            roughness: f32,
            output_srgb: bool,
        ) !void {
            gl.glUseProgram(self.program);
            gl.glBindVertexArray(self.vao);
            gl.glUniformMatrix4fv(self.u_view_proj, 1, gl.GL_FALSE, &view_proj.data[0]);
            gl.glUniformMatrix4fv(self.u_model, 1, gl.GL_FALSE, &model.data[0]);
            gl.glUniform2f(self.u_scene_size, scene_size[0], scene_size[1]);
            gl.glUniform3f(self.u_light_dir, light_dir[0], light_dir[1], light_dir[2]);
            gl.glUniform1f(self.u_relief, relief);
            gl.glUniform1f(self.u_roughness, roughness);
            gl.glUniform4f(self.u_base_color, base_color[0], base_color[1], base_color[2], base_color[3]);
            if (self.u_output_srgb >= 0) gl.glUniform1i(self.u_output_srgb, if (output_srgb) 1 else 0);

            // Records plane.
            gl.glActiveTexture(@intCast(gl.GL_TEXTURE0 + RECORD_UNIT));
            switch (variant) {
                .gl33, .gl44 => gl.glBindTexture(gl.GL_TEXTURE_BUFFER, self.rec_texture),
                .gles30 => gl.glBindTexture(gl.GL_TEXTURE_2D, self.rec_texture),
            }
            gl.glUniform1i(self.u_records, RECORD_UNIT);
            gl.glUniform1i(self.u_glyph_count, self.glyph_count);

            // Atlas plane, bound off the shared cache via snail's contract.
            const program = Program{
                .curve_tex_loc = self.u_curve_tex,
                .band_tex_loc = self.u_band_tex,
                .fill_rule_loc = self.u_fill_rule,
                .layer_base_loc = self.u_layer_base,
                .curve_tex_unit = CURVE_UNIT,
                .band_tex_unit = BAND_UNIT,
            };
            const backend = Backend.from(.{
                .curve_array = cache.curveTexHandle(),
                .band_array = cache.bandTexHandle(),
                .layer_info_tex = cache.layerInfoTexHandle(),
                .image_array_tex = cache.imageArrayHandle(),
            });
            try backend.bindProgram(program);
            // The emit path bakes the absolute atlas layer into each glyph word.
            try backend.bindDrawState(program, .{ .subpixel_order = .none, .coverage_transfer = .identity, .layer_base = 0 });

            gl.glDrawElements(gl.GL_TRIANGLES, 6, gl.GL_UNSIGNED_INT, null);
            gl.glBindVertexArray(0);
            gl.glUseProgram(0);
        }

        pub fn deinit(self: *Self) void {
            if (self.rec_texture != 0) gl.glDeleteTextures(1, &self.rec_texture);
            if (self.rec_buffer != 0) gl.glDeleteBuffers(1, &self.rec_buffer);
            if (self.ebo != 0) gl.glDeleteBuffers(1, &self.ebo);
            if (self.vbo != 0) gl.glDeleteBuffers(1, &self.vbo);
            if (self.vao != 0) gl.glDeleteVertexArrays(1, &self.vao);
            if (self.program != 0) gl.glDeleteProgram(self.program);
            self.* = .{};
        }

        // ── Shader sources ──

        const vertex_src: [:0]const u8 = version_prefix ++
            \\layout(location = 0) in vec3 a_pos;
            \\layout(location = 1) in vec2 a_uv;
            \\uniform mat4 u_view_proj;
            \\uniform mat4 u_model;
            \\out vec2 v_uv;
            \\void main() {
            \\    v_uv = a_uv;
            \\    gl_Position = u_view_proj * u_model * vec4(a_pos, 1.0);
            \\}
        ;

        const fragment_src: [:0]const u8 = version_prefix ++
            coverage_resources ++ "\n" ++
            glsl.source(.render_abi) ++ "\n" ++
            glsl.source(.coverage_common) ++ "\n" ++
            glsl.source(.color_common) ++ "\n" ++
            glsl.source(.text_coverage_body) ++ "\n" ++
            records_interface ++ "\n" ++
            record_stride ++
            glsl.source(.text_sample_body) ++ "\n" ++
            @embedFile("glsl/game_material_body.glsl") ++ "\n" ++
            \\in vec2 v_uv;
            \\uniform vec2 u_scene_size;
            \\uniform vec3 u_light_dir;
            \\uniform float u_relief;
            \\uniform float u_roughness;
            \\uniform vec4 u_base_color;
            \\uniform int u_output_srgb;
            \\out vec4 frag_color;
            \\
            \\vec3 encodeSrgb(vec3 c) {
            \\    c = clamp(c, 0.0, 1.0);
            \\    vec3 lo = c * 12.92;
            \\    vec3 hi = 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055;
            \\    return mix(hi, lo, step(c, vec3(0.0031308)));
            \\}
            \\
            \\void main() {
            \\    vec2 scene_pos = vec2(v_uv.x * u_scene_size.x, (1.0 - v_uv.y) * u_scene_size.y);
            \\    vec2 scene_dx = dFdx(scene_pos);
            \\    vec2 scene_dy = dFdy(scene_pos);
            \\    vec3 lin = snailGameMaterial(v_uv, scene_pos, scene_dx, scene_dy, u_light_dir, u_base_color, u_relief, u_roughness);
            \\    vec3 outc = (u_output_srgb == 1) ? encodeSrgb(lin) : lin;
            \\    frag_color = vec4(outc, 1.0);
            \\}
        ;
    };
}
