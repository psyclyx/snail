//! Custom GL material renderer for the game demo, generic over the GL family
//! (gl33 / gl44 / gles30).
//!
//! This is the "custom shader" showcase: a caller-authored material shader
//! (src/demo/game/slang/game_material.slang) that imports snail's
//! `text_sample` Slang module and samples glyph coverage at arbitrary UVs,
//! lighting it over an opaque panel. The translated GL dialects are
//! generated at build time (build.zig addGameShaderGl); this file embeds
//! and binds them. The per-glyph emit words are uploaded once into the record
//! storage the shader's `ISnailTextRecords` implementation expects — a
//! `GL_TEXTURE_BUFFER` on desktop GL, a 2D `GL_R32UI` texture on GLES 3.0
//! (no buffer textures there).
//!
//! The atlas plane (curve/band arrays) is bound off the same
//! `*DeviceAtlas` the standard snail passes use, via `embed_gl.*Backend`.

const std = @import("std");
const snail = @import("snail");
const embed_gl = @import("embed_gl");
const slang_gen = @import("snail_shaders");
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
/// UBO binding point for the material parameter block.
const PARAMS_BINDING: u32 = 0;

// The shader source hardcodes the 18-word record stride
// (SNAIL_TEXT_RECORD_WORDS_PER_GLYPH in game_material.slang); keep it in
// lockstep with the library's packed instance layout.
comptime {
    std.debug.assert(snail.render.records.BYTES_PER_INSTANCE / @sizeOf(u32) == 18);
}

/// Row width (in u32 texels) of the GLES records texture; must match
/// SNAIL_TEXT_RECORDS_TEX_WIDTH in game_material.slang.
const records_width: usize = 1024;

/// std140 mirror of `GameMaterialParams` in game_material.slang (GL flavor:
/// view_proj and model ride separately so the vertex stage preserves the
/// composed catalog's exact `u_view_proj * u_model * pos` arithmetic; the
/// Vulkan flavor carries one premultiplied mvp inside its 128-byte push
/// budget). Matrices upload as the same column-major GLSL bytes the loose
/// uniforms carried.
const Params = extern struct {
    view_proj: [16]f32,
    model: [16]f32,
    base_color: [4]f32,
    light_dir: [4]f32, // xyz = fixed tangent-space light
    scene_size: [2]f32,
    glyph_count: i32,
    output_srgb: i32,
    relief: f32,
    roughness: f32,
    _pad: [2]f32 = .{ 0, 0 },
};

/// Build the material renderer type for one GL variant. Bundles the right gl
/// bindings, generated shader dialect, atlas-binding backend, cache, and
/// program descriptor so the whole family shares one implementation.
pub fn GlMaterial(comptime variant: Variant) type {
    return struct {
        const Self = @This();

        const gl = switch (variant) {
            .gl33, .gl44 => desktop_gl,
            .gles30 => gles_gl,
        };
        pub const Cache = switch (variant) {
            .gl33 => embed_gl.Gl33DeviceAtlas,
            .gl44 => embed_gl.Gl44DeviceAtlas,
            .gles30 => embed_gl.Gles30DeviceAtlas,
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
        // Generated at build time from game_material.slang and wired in as
        // anonymous imports by build.zig addGameShaderGl (snail's GL 3.3
        // and 4.4 paths share the #version 330 dialect; DSA is an API
        // concern, not a shader-dialect one).
        const vertex_src: [:0]const u8 = switch (variant) {
            .gl33, .gl44 => @embedFile("game_material.vert.glsl330"),
            .gles30 => @embedFile("game_material.vert.gles300"),
        };
        const fragment_src: [:0]const u8 = switch (variant) {
            .gl33, .gl44 => @embedFile("game_material.frag.glsl330"),
            .gles30 => @embedFile("game_material.frag.gles300"),
        };
        // Direct Slang GLSL keeps the records uniform's source-derived name
        // for both desktop's texel buffer and GLES's 2D texture.
        const records_uniform_name = switch (variant) {
            .gl33, .gl44 => slang_gen.glsl_text_sample_records_name,
            .gles30 => slang_gen.gles_text_sample_records_name,
        };

        program: gl.GLuint = 0,
        vao: gl.GLuint = 0,
        vbo: gl.GLuint = 0,
        ebo: gl.GLuint = 0,
        ubo: gl.GLuint = 0,
        // records storage: TBO (buffer + texture view) on desktop, 2D texture on ES.
        rec_buffer: gl.GLuint = 0,
        rec_texture: gl.GLuint = 0,
        glyph_count: i32 = 0,

        // uniforms
        u_records: gl.GLint = -1,
        u_curve_tex: gl.GLint = -1,
        u_band_tex: gl.GLint = -1,

        pub fn init(
            self: *Self,
            allocator: std.mem.Allocator,
            cache: *Cache,
            material_pass: anytype, // *const passes.PreparedPass
        ) !void {
            self.* = .{};
            self.program = try common.linkProgram(vertex_src, fragment_src);
            errdefer gl.glDeleteProgram(self.program);

            // One std140 block for both stages (identical definition — the
            // linker merges them), bound to a caller-owned UBO.
            const block_index = gl.glGetUniformBlockIndex(self.program, "GameMaterialParams_std140");
            if (block_index == gl.GL_INVALID_INDEX) return error.MissingUniformBlock;
            gl.glUniformBlockBinding(self.program, block_index, PARAMS_BINDING);
            gl.glGenBuffers(1, &self.ubo);

            self.u_records = gl.glGetUniformLocation(self.program, records_uniform_name);
            self.u_curve_tex = gl.glGetUniformLocation(self.program, slang_gen.glsl_curve_tex_name);
            self.u_band_tex = gl.glGetUniformLocation(self.program, slang_gen.glsl_band_tex_name);

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
                    // 2D R32UI texture, row-major at the width the ES shader
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

            const params = Params{
                .view_proj = view_proj.data,
                .model = model.data,
                .base_color = base_color,
                .light_dir = .{ light_dir[0], light_dir[1], light_dir[2], 0.0 },
                .scene_size = scene_size,
                .glyph_count = self.glyph_count,
                .output_srgb = if (output_srgb) 1 else 0,
                .relief = relief,
                .roughness = roughness,
            };
            gl.glBindBuffer(gl.GL_UNIFORM_BUFFER, self.ubo);
            gl.glBufferData(gl.GL_UNIFORM_BUFFER, @sizeOf(Params), &params, gl.GL_STREAM_DRAW);
            gl.glBindBufferBase(gl.GL_UNIFORM_BUFFER, PARAMS_BINDING, self.ubo);

            // Records plane.
            gl.glActiveTexture(@intCast(gl.GL_TEXTURE0 + RECORD_UNIT));
            switch (variant) {
                .gl33, .gl44 => gl.glBindTexture(gl.GL_TEXTURE_BUFFER, self.rec_texture),
                .gles30 => gl.glBindTexture(gl.GL_TEXTURE_2D, self.rec_texture),
            }
            gl.glUniform1i(self.u_records, RECORD_UNIT);

            // Atlas plane, bound off the shared cache via snail's contract
            // (layer_base/fill_rule live in the shader now: the emit path
            // bakes the absolute atlas layer into each glyph word).
            const program = Program{
                .curve_tex_loc = self.u_curve_tex,
                .band_tex_loc = self.u_band_tex,
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

            gl.glDrawElements(gl.GL_TRIANGLES, 6, gl.GL_UNSIGNED_INT, null);
            gl.glBindVertexArray(0);
            gl.glUseProgram(0);
        }

        pub fn deinit(self: *Self) void {
            if (self.rec_texture != 0) gl.glDeleteTextures(1, &self.rec_texture);
            if (self.rec_buffer != 0) gl.glDeleteBuffers(1, &self.rec_buffer);
            if (self.ubo != 0) gl.glDeleteBuffers(1, &self.ubo);
            if (self.ebo != 0) gl.glDeleteBuffers(1, &self.ebo);
            if (self.vbo != 0) gl.glDeleteBuffers(1, &self.vbo);
            if (self.vao != 0) gl.glDeleteVertexArrays(1, &self.vao);
            if (self.program != 0) gl.glDeleteProgram(self.program);
            self.* = .{};
        }
    };
}
