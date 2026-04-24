const std = @import("std");
const gl = @import("gl.zig").gl;
const gl_backend = @import("gl_backend.zig");
const shaders = @import("shaders.zig");
const subpixel_policy = @import("subpixel_policy.zig");
const upload_common = @import("upload_common.zig");
const vertex = @import("vertex.zig");
const vec = @import("../math/vec.zig");
const Mat4 = vec.Mat4;
const snail_mod = @import("../snail.zig");
const SubpixelMode = @import("subpixel_mode.zig").SubpixelMode;
const SubpixelOrder = @import("subpixel_order.zig").SubpixelOrder;

// ── Backend selection ──

pub const Backend = gl_backend.Backend;

// ── Shared types ──

const ProgramState = struct {
    handle: gl.GLuint = 0,
    mvp_loc: gl.GLint = -1,
    viewport_loc: gl.GLint = -1,
    curve_tex_loc: gl.GLint = -1,
    band_tex_loc: gl.GLint = -1,
    image_tex_loc: gl.GLint = -1,
    fill_rule_loc: gl.GLint = -1,
    subpixel_order_loc: gl.GLint = -1,
    subpixel_render_mode_loc: gl.GLint = -1,
    subpixel_backdrop_loc: gl.GLint = -1,
    layer_tex_loc: gl.GLint = -1,
};

pub const FillRule = enum(c_int) {
    non_zero = 0,
    even_odd = 1,
};

// ── GL 4.4 persistent mapping constants ──

const RING_SEGMENTS = 3;
const RING_TOTAL_BYTES = 12 * 1024 * 1024; // 12 MB (4 MB per segment)
const RING_SEGMENT_BYTES = RING_TOTAL_BYTES / RING_SEGMENTS;
const BYTES_PER_GLYPH = vertex.FLOATS_PER_VERTEX * vertex.VERTICES_PER_GLYPH * @sizeOf(f32);
const MAX_GLYPHS_PER_SEGMENT = RING_SEGMENT_BYTES / BYTES_PER_GLYPH;

const MAX_ATLASES = upload_common.MAX_ATLASES;
const MAX_PAGES_PER_ATLAS = upload_common.MAX_PAGES_PER_ATLAS;
const MAX_IMAGES = upload_common.MAX_IMAGES;

const AtlasSlot = upload_common.AtlasSlot(snail_mod.Atlas, snail_mod.AtlasPage, MAX_PAGES_PER_ATLAS);
const ImageSlot = upload_common.ImageSlot(snail_mod.Image);

// ── GlTextState ──

pub const GlTextState = struct {
    backend: Backend = .gl33,
    text_program: ProgramState = .{},
    text_subpixel_program: ProgramState = .{},
    text_subpixel_dual_program: ProgramState = .{},
    colr_program: ProgramState = .{},
    path_program: ProgramState = .{},
    subpixel_order: SubpixelOrder = .none,
    subpixel_mode: SubpixelMode = .safe,
    subpixel_backdrop: ?[4]f32 = null,
    fill_rule: FillRule = .non_zero,
    vao: gl.GLuint = 0,
    vbo: gl.GLuint = 0,
    ebo: gl.GLuint = 0,
    curve_array: gl.GLuint = 0,
    band_array: gl.GLuint = 0,
    layer_info_tex: gl.GLuint = 0,
    image_array: gl.GLuint = 0,
    active_program: gl.GLuint = 0,
    frame_begun: bool = false,
    supports_dual_source_blend: bool = false,
    persistent_map: ?[*]u8 = null,
    ring_fences: [RING_SEGMENTS]gl.GLsync = .{null} ** RING_SEGMENTS,
    ring_segment: u32 = 0,
    atlas_slots: [MAX_ATLASES]AtlasSlot = std.mem.zeroes([MAX_ATLASES]AtlasSlot),
    atlas_slot_count: usize = 0,
    allocated_curve_height: u32 = 0,
    allocated_band_height: u32 = 0,
    allocated_layer_count: u32 = 0,
    atlas_has_special_text_runs: bool = false,
    image_slots: [MAX_IMAGES]ImageSlot = std.mem.zeroes([MAX_IMAGES]ImageSlot),
    image_slot_count: usize = 0,
    allocated_image_width: u32 = 0,
    allocated_image_height: u32 = 0,
    allocated_image_count: u32 = 0,

    // ── Init / Deinit ──

    pub fn init(self: *GlTextState) !void {
        self.backend = gl_backend.detect(gl);
        self.supports_dual_source_blend = detectDualSourceBlendSupport();

        // Keep startup on the lightweight plain-glyph shaders. The heavier path/COLR
        // shader is linked lazily the first time sentinel runs are drawn.
        self.text_program = try loadProgramState("text", shaders.vertex_shader, shaders.fragment_shader_text, false);
        self.text_subpixel_program = try loadProgramState("text-subpixel", shaders.vertex_shader, shaders.fragment_shader_text_subpixel, false);
        if (self.supports_dual_source_blend) {
            self.text_subpixel_dual_program = try loadProgramState("text-subpixel-dual", shaders.vertex_shader, shaders.fragment_shader_text_subpixel_dual, true);
        }

        switch (self.backend) {
            .gl33 => self.initGl33(),
            .gl44 => self.initGl44(),
        }

        gl.glEnable(gl.GL_BLEND);
        // Shader outputs premultiplied alpha (frag_color = v_color * coverage),
        // so use GL_ONE for src to avoid double-multiplying coverage.
        gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);

        // Enable sRGB framebuffer so GL handles gamma correction during blending.
        // The fragment shaders output linear coverage; GL linearizes existing
        // framebuffer values before blending and applies sRGB gamma on write.
        gl.glEnable(gl.GL_FRAMEBUFFER_SRGB);
    }

    fn initGl33(self: *GlTextState) void {
        gl.glGenVertexArrays(1, &self.vao);
        gl.glGenBuffers(1, &self.vbo);
        gl.glGenBuffers(1, &self.ebo);
        gl.glBindVertexArray(self.vao);
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ebo);
        initEbo();
        setupVertexAttribs();
    }

    fn initGl44(self: *GlTextState) void {
        // DSA: create VAO, VBO, EBO without binding
        gl.glCreateVertexArrays(1, &self.vao);
        gl.glCreateBuffers(1, &self.vbo);
        gl.glCreateBuffers(1, &self.ebo);

        // Persistent mapped VBO
        const flags: gl.GLbitfield = gl.GL_MAP_WRITE_BIT | gl.GL_MAP_PERSISTENT_BIT | gl.GL_MAP_COHERENT_BIT;
        gl.glNamedBufferStorage(self.vbo, RING_TOTAL_BYTES, null, flags);
        self.persistent_map = @ptrCast(gl.glMapNamedBufferRange(self.vbo, 0, RING_TOTAL_BYTES, flags));

        if (self.persistent_map == null) {
            // Fallback to GL 3.3 if mapping fails
            std.debug.print("snail: persistent mapping failed, falling back to GL 3.3\n", .{});
            gl.glDeleteVertexArrays(1, &self.vao);
            gl.glDeleteBuffers(1, &self.vbo);
            gl.glDeleteBuffers(1, &self.ebo);
            self.backend = .gl33;
            self.initGl33();
            return;
        }

        // DSA vertex attribs
        const stride: gl.GLint = vertex.FLOATS_PER_VERTEX * @sizeOf(f32);
        gl.glVertexArrayVertexBuffer(self.vao, 0, self.vbo, 0, stride);
        gl.glVertexArrayElementBuffer(self.vao, self.ebo);

        inline for (0..5) |i| {
            const loc: u32 = @intCast(i);
            gl.glEnableVertexArrayAttrib(self.vao, loc);
            gl.glVertexArrayAttribFormat(self.vao, loc, 4, gl.GL_FLOAT, gl.GL_FALSE, @intCast(i * 4 * @sizeOf(f32)));
            gl.glVertexArrayAttribBinding(self.vao, loc, 0);
        }

        // EBO (static data, not persistently mapped)
        gl.glBindVertexArray(self.vao);
        gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, self.ebo);
        initEbo();
    }

    pub fn deinit(self: *GlTextState) void {
        if (self.backend == .gl44) {
            // Delete fences
            for (&self.ring_fences) |*f| {
                if (f.*) |fence| {
                    gl.glDeleteSync(fence);
                    f.* = null;
                }
            }
            // Unmap persistent buffer
            if (self.persistent_map != null) {
                _ = gl.glUnmapNamedBuffer(self.vbo);
                self.persistent_map = null;
            }
        }

        deleteProgramState(&self.text_program);
        deleteProgramState(&self.text_subpixel_program);
        deleteProgramState(&self.text_subpixel_dual_program);
        deleteProgramState(&self.colr_program);
        deleteProgramState(&self.path_program);
        if (self.vao != 0) gl.glDeleteVertexArrays(1, &self.vao);
        if (self.vbo != 0) gl.glDeleteBuffers(1, &self.vbo);
        if (self.ebo != 0) gl.glDeleteBuffers(1, &self.ebo);
        self.destroyAtlasTextureResources();
        self.destroyImageResources();
        self.resetAtlasUploadState();
    }

    pub fn getBackendName(self: *const GlTextState) []const u8 {
        return switch (self.backend) {
            .gl33 => "GL 3.3",
            .gl44 => "GL 4.4 (persistent mapped)",
        };
    }

    // ── Texture array management ──

    fn destroyAtlasTextureResources(self: *GlTextState) void {
        if (self.curve_array != 0) gl.glDeleteTextures(1, &self.curve_array);
        if (self.band_array != 0) gl.glDeleteTextures(1, &self.band_array);
        if (self.layer_info_tex != 0) gl.glDeleteTextures(1, &self.layer_info_tex);
        self.curve_array = 0;
        self.band_array = 0;
        self.layer_info_tex = 0;
    }

    fn destroyImageResources(self: *GlTextState) void {
        if (self.image_array != 0) gl.glDeleteTextures(1, &self.image_array);
        self.image_array = 0;
        self.image_slot_count = 0;
        self.allocated_image_width = 0;
        self.allocated_image_height = 0;
        self.allocated_image_count = 0;
        for (&self.image_slots) |*slot| slot.* = .{};
    }

    pub fn buildTextureArrays(self: *GlTextState, atlases: []const *const snail_mod.Atlas, out_views: []snail_mod.AtlasHandle) void {
        std.debug.assert(atlases.len == out_views.len);

        if (atlases.len == 0) {
            self.destroyAtlasTextureResources();
            self.resetAtlasUploadState();
            return;
        }

        const can_incremental = self.texturesReady() and self.atlasSlotsCompatible(atlases);
        if (!can_incremental) {
            self.rebuildTextureArrays(atlases, out_views);
        } else if (!self.appendTexturePages(atlases)) {
            self.rebuildTextureArrays(atlases, out_views);
        } else {
            self.fillAtlasViews(atlases, out_views);
            self.ensureAtlasImagesRegistered(atlases);
            self.rebuildLayerInfoTexture(atlases);
            self.atlas_has_special_text_runs = atlasesHaveSpecialTextRuns(atlases);
            self.active_program = 0;
            self.frame_begun = false;
        }
    }

    pub fn buildImageArray(self: *GlTextState, images: []const *const snail_mod.Image, out_views: []snail_mod.ImageHandle) void {
        std.debug.assert(images.len == out_views.len);
        self.ensureImagesRegistered(images);
        for (images, 0..) |image, i| {
            out_views[i] = self.currentImageView(image);
        }
        self.active_program = 0;
        self.frame_begun = false;
    }

    fn currentImageView(self: *const GlTextState, image: *const snail_mod.Image) snail_mod.ImageHandle {
        return upload_common.currentImageView(
            snail_mod.ImageHandle,
            self.image_slots[0..],
            self.image_slot_count,
            self.allocated_image_width,
            self.allocated_image_height,
            image,
        );
    }

    fn findImageSlot(self: *const GlTextState, image: *const snail_mod.Image) ?usize {
        return upload_common.findImageSlot(self.image_slots[0..], self.image_slot_count, image);
    }

    fn ensureAtlasImagesRegistered(self: *GlTextState, atlases: []const *const snail_mod.Atlas) void {
        var scratch: [MAX_IMAGES]*const snail_mod.Image = undefined;
        const count = upload_common.collectAtlasImages(self.image_slots[0..], self.image_slot_count, atlases, scratch[0..]);
        self.ensureImagesRegistered(scratch[0..count]);
    }

    fn ensureImagesRegistered(self: *GlTextState, images: []const *const snail_mod.Image) void {
        if (images.len == 0) return;

        var new_images: [MAX_IMAGES]*const snail_mod.Image = undefined;
        var new_count: usize = 0;
        var required_width = self.allocated_image_width;
        var required_height = self.allocated_image_height;
        for (images) |image| {
            required_width = @max(required_width, image.width);
            required_height = @max(required_height, image.height);
            if (self.findImageSlot(image) != null) continue;
            if (self.image_slot_count + new_count >= MAX_IMAGES) break;
            new_images[new_count] = image;
            new_count += 1;
        }

        if (new_count == 0 and self.image_array != 0) return;

        const required_count: u32 = @intCast(self.image_slot_count + new_count);
        const new_width = upload_common.heightCapacity(@max(required_width, 1));
        const new_height = upload_common.heightCapacity(@max(required_height, 1));
        const needs_rebuild = self.image_array == 0 or
            required_count > self.allocated_image_count or
            new_width > self.allocated_image_width or
            new_height > self.allocated_image_height;

        if (needs_rebuild) {
            for (new_images[0..new_count], 0..) |image, i| {
                self.image_slots[self.image_slot_count + i] = .{ .image = image };
            }
            self.image_slot_count += new_count;
            self.rebuildImageArray();
            return;
        }

        for (new_images[0..new_count], 0..) |image, i| {
            const slot_index = self.image_slot_count + i;
            self.image_slots[slot_index] = .{ .image = image };
            self.uploadImageLayer(image, @intCast(slot_index));
        }
        self.image_slot_count += new_count;
    }

    fn rebuildImageArray(self: *GlTextState) void {
        if (self.image_array != 0) gl.glDeleteTextures(1, &self.image_array);
        self.image_array = 0;

        if (self.image_slot_count == 0) {
            self.allocated_image_width = 0;
            self.allocated_image_height = 0;
            self.allocated_image_count = 0;
            return;
        }

        var max_width: u32 = 1;
        var max_height: u32 = 1;
        for (self.image_slots[0..self.image_slot_count]) |slot| {
            const image = slot.image orelse continue;
            max_width = @max(max_width, image.width);
            max_height = @max(max_height, image.height);
        }

        self.allocated_image_width = upload_common.heightCapacity(max_width);
        self.allocated_image_height = upload_common.heightCapacity(max_height);
        self.allocated_image_count = upload_common.atlasCapacity(@intCast(self.image_slot_count));

        switch (self.backend) {
            .gl33 => {
                gl.glGenTextures(1, &self.image_array);
                gl.glActiveTexture(gl.GL_TEXTURE3);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.image_array);
                gl.glTexImage3D(
                    gl.GL_TEXTURE_2D_ARRAY,
                    0,
                    gl.GL_SRGB8_ALPHA8,
                    @intCast(self.allocated_image_width),
                    @intCast(self.allocated_image_height),
                    @intCast(self.allocated_image_count),
                    0,
                    gl.GL_RGBA,
                    gl.GL_UNSIGNED_BYTE,
                    null,
                );
                setImageTexParams(gl.GL_TEXTURE_2D_ARRAY);
            },
            .gl44 => {
                gl.glCreateTextures(gl.GL_TEXTURE_2D_ARRAY, 1, &self.image_array);
                gl.glTextureStorage3D(
                    self.image_array,
                    1,
                    gl.GL_SRGB8_ALPHA8,
                    @intCast(self.allocated_image_width),
                    @intCast(self.allocated_image_height),
                    @intCast(self.allocated_image_count),
                );
                setImageTexParamsDSA(self.image_array);
                gl.glBindTextureUnit(3, self.image_array);
            },
        }

        for (self.image_slots[0..self.image_slot_count], 0..) |slot, i| {
            self.uploadImageLayer(slot.image.?, @intCast(i));
        }
    }

    fn uploadImageLayer(self: *const GlTextState, image: *const snail_mod.Image, layer: u32) void {
        switch (self.backend) {
            .gl33 => {
                gl.glActiveTexture(gl.GL_TEXTURE3);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.image_array);
                gl.glTexSubImage3D(
                    gl.GL_TEXTURE_2D_ARRAY,
                    0,
                    0,
                    0,
                    @intCast(layer),
                    @intCast(image.width),
                    @intCast(image.height),
                    1,
                    gl.GL_RGBA,
                    gl.GL_UNSIGNED_BYTE,
                    image.pixels.ptr,
                );
            },
            .gl44 => {
                gl.glTextureSubImage3D(
                    self.image_array,
                    0,
                    0,
                    0,
                    @intCast(layer),
                    @intCast(image.width),
                    @intCast(image.height),
                    1,
                    gl.GL_RGBA,
                    gl.GL_UNSIGNED_BYTE,
                    image.pixels.ptr,
                );
            },
        }
    }

    fn rebuildTextureArrays(self: *GlTextState, atlases: []const *const snail_mod.Atlas, out_views: []snail_mod.AtlasHandle) void {
        self.destroyAtlasTextureResources();
        self.resetAtlasUploadState();

        const slot_info = upload_common.rebuildAtlasSlots(self.atlas_slots[0..], atlases);
        self.atlas_slot_count = slot_info.atlas_slot_count;
        self.allocated_curve_height = slot_info.allocated_curve_height;
        self.allocated_band_height = slot_info.allocated_band_height;
        self.allocated_layer_count = slot_info.allocated_layer_count;

        if (atlases.len == 0) return;

        self.createTextureArrays(atlases[0], self.allocated_layer_count, self.allocated_curve_height, self.allocated_band_height);
        self.uploadAllPages(atlases);
        self.ensureAtlasImagesRegistered(atlases);
        self.rebuildLayerInfoTexture(atlases);
        self.atlas_has_special_text_runs = atlasesHaveSpecialTextRuns(atlases);
        self.fillAtlasViews(atlases, out_views);
        self.active_program = 0;
        self.frame_begun = false;
    }

    fn appendTexturePages(self: *GlTextState, atlases: []const *const snail_mod.Atlas) bool {
        var max_curve_h: u32 = self.allocated_curve_height;
        var max_band_h: u32 = self.allocated_band_height;
        var start_pages: [MAX_ATLASES]u32 = undefined;

        for (atlases, 0..) |atlas, i| {
            if (i >= self.atlas_slot_count) return false;
            const slot = &self.atlas_slots[i];
            const page_count: u32 = @intCast(atlas.pageCount());
            if (page_count < slot.uploaded_pages or page_count > slot.capacity_pages) return false;
            start_pages[i] = slot.uploaded_pages;
            for (0..slot.uploaded_pages) |page_index| {
                if (slot.page_ptrs[page_index] != atlas.page(@intCast(page_index))) return false;
            }
            for (0..page_count) |page_index| {
                const page = atlas.page(@intCast(page_index));
                if (page.curve_height > max_curve_h) max_curve_h = page.curve_height;
                if (page.band_height > max_band_h) max_band_h = page.band_height;
            }
        }

        if (atlases.len != self.atlas_slot_count) return false;
        if (max_curve_h > self.allocated_curve_height or max_band_h > self.allocated_band_height) return false;

        switch (self.backend) {
            .gl33 => self.uploadTexturePagesGl33WithStarts(atlases, start_pages[0..atlases.len]),
            .gl44 => self.uploadTexturePagesGl44WithStarts(atlases, start_pages[0..atlases.len]),
        }

        upload_common.refreshAtlasSlots(self.atlas_slots[0..], atlases);
        return true;
    }

    fn texturesReady(self: *const GlTextState) bool {
        return self.curve_array != 0 and self.band_array != 0 and self.atlas_slot_count > 0;
    }

    fn atlasSlotsCompatible(self: *const GlTextState, atlases: []const *const snail_mod.Atlas) bool {
        return upload_common.atlasSlotsCompatible(self.atlas_slots[0..], self.atlas_slot_count, atlases);
    }

    fn fillAtlasViews(self: *const GlTextState, atlases: []const *const snail_mod.Atlas, out_views: []snail_mod.AtlasHandle) void {
        upload_common.fillAtlasViews(self.atlas_slots[0..], atlases, out_views);
    }

    fn resetAtlasUploadState(self: *GlTextState) void {
        self.atlas_slot_count = 0;
        self.allocated_curve_height = 0;
        self.allocated_band_height = 0;
        self.allocated_layer_count = 0;
        self.atlas_has_special_text_runs = false;
        for (&self.atlas_slots) |*slot| slot.* = .{};
    }

    fn createTextureArrays(self: *GlTextState, first_atlas: *const snail_mod.Atlas, layer_count: u32, max_curve_h: u32, max_band_h: u32) void {
        const first_page = first_atlas.page(0);

        switch (self.backend) {
            .gl33 => {
                gl.glGenTextures(1, &self.curve_array);
                gl.glActiveTexture(gl.GL_TEXTURE0);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.curve_array);
                gl.glTexImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, gl.GL_RGBA16F, @intCast(first_page.curve_width), @intCast(max_curve_h), @intCast(layer_count), 0, gl.GL_RGBA, gl.GL_HALF_FLOAT, null);
                setTexParams(gl.GL_TEXTURE_2D_ARRAY);

                gl.glGenTextures(1, &self.band_array);
                gl.glActiveTexture(gl.GL_TEXTURE1);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.band_array);
                gl.glTexImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, gl.GL_RG16UI, @intCast(first_page.band_width), @intCast(max_band_h), @intCast(layer_count), 0, gl.GL_RG_INTEGER, gl.GL_UNSIGNED_SHORT, null);
                setTexParams(gl.GL_TEXTURE_2D_ARRAY);
            },
            .gl44 => {
                gl.glCreateTextures(gl.GL_TEXTURE_2D_ARRAY, 1, &self.curve_array);
                gl.glTextureStorage3D(self.curve_array, 1, gl.GL_RGBA16F, @intCast(first_page.curve_width), @intCast(max_curve_h), @intCast(layer_count));
                setTexParamsDSA(self.curve_array);

                gl.glCreateTextures(gl.GL_TEXTURE_2D_ARRAY, 1, &self.band_array);
                gl.glTextureStorage3D(self.band_array, 1, gl.GL_RG16UI, @intCast(first_page.band_width), @intCast(max_band_h), @intCast(layer_count));
                setTexParamsDSA(self.band_array);
                gl.glBindTextureUnit(0, self.curve_array);
                gl.glBindTextureUnit(1, self.band_array);
            },
        }
    }

    fn uploadAllPages(self: *GlTextState, atlases: []const *const snail_mod.Atlas) void {
        switch (self.backend) {
            .gl33 => self.uploadTexturePagesGl33WithStarts(atlases, null),
            .gl44 => self.uploadTexturePagesGl44WithStarts(atlases, null),
        }
    }

    fn uploadTexturePagesGl33WithStarts(self: *const GlTextState, atlases: []const *const snail_mod.Atlas, start_pages: ?[]const u32) void {
        for (atlases, 0..) |atlas, i| {
            const start_page = if (start_pages) |sp| sp[i] else 0;
            const base_layer = self.atlas_slots[i].base_layer;
            for (start_page..atlas.pageCount()) |page_index| {
                const page = atlas.page(@intCast(page_index));
                const layer = base_layer + @as(u32, @intCast(page_index));
                const layer_z: gl.GLint = @intCast(layer);
                gl.glActiveTexture(gl.GL_TEXTURE0);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.curve_array);
                gl.glTexSubImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, 0, 0, layer_z, @intCast(page.curve_width), @intCast(page.curve_height), 1, gl.GL_RGBA, gl.GL_HALF_FLOAT, page.curve_data.ptr);
                gl.glActiveTexture(gl.GL_TEXTURE1);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.band_array);
                gl.glTexSubImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, 0, 0, layer_z, @intCast(page.band_width), @intCast(page.band_height), 1, gl.GL_RG_INTEGER, gl.GL_UNSIGNED_SHORT, page.band_data.ptr);
            }
        }
    }

    fn uploadTexturePagesGl44WithStarts(self: *const GlTextState, atlases: []const *const snail_mod.Atlas, start_pages: ?[]const u32) void {
        for (atlases, 0..) |atlas, i| {
            const start_page = if (start_pages) |sp| sp[i] else 0;
            const base_layer = self.atlas_slots[i].base_layer;
            for (start_page..atlas.pageCount()) |page_index| {
                const page = atlas.page(@intCast(page_index));
                const layer = base_layer + @as(u32, @intCast(page_index));
                const layer_z: gl.GLint = @intCast(layer);
                gl.glTextureSubImage3D(self.curve_array, 0, 0, 0, layer_z, @intCast(page.curve_width), @intCast(page.curve_height), 1, gl.GL_RGBA, gl.GL_HALF_FLOAT, page.curve_data.ptr);
                gl.glTextureSubImage3D(self.band_array, 0, 0, 0, layer_z, @intCast(page.band_width), @intCast(page.band_height), 1, gl.GL_RG_INTEGER, gl.GL_UNSIGNED_SHORT, page.band_data.ptr);
            }
        }
    }

    fn rebuildLayerInfoTexture(self: *GlTextState, atlases: []const *const snail_mod.Atlas) void {
        if (self.layer_info_tex != 0) gl.glDeleteTextures(1, &self.layer_info_tex);
        self.layer_info_tex = 0;

        var total_rows: u32 = 0;
        for (atlases) |atlas| total_rows += atlas.layer_info_height;
        if (total_rows == 0) return;

        const width = snail_mod.PATH_PAINT_INFO_WIDTH;
        const total_texels = @as(usize, width) * @as(usize, total_rows) * 4;
        var data = std.heap.page_allocator.alloc(f32, total_texels) catch return;
        defer std.heap.page_allocator.free(data);
        @memset(data, 0);

        for (atlases, 0..) |atlas, i| {
            const lid = atlas.layer_info_data orelse continue;
            const row_base = self.atlas_slots[i].info_row_base;
            const row_count = atlas.layer_info_height;
            const copy_len = @as(usize, atlas.layer_info_width) * @as(usize, row_count) * 4;
            const dst_base = @as(usize, row_base) * @as(usize, width) * 4;
            @memcpy(data[dst_base .. dst_base + copy_len], lid[0..copy_len]);

            const records = atlas.paint_image_records orelse continue;
            for (records) |record| {
                const image = (record orelse continue).image;
                const view = self.currentImageView(image);
                upload_common.patchImagePaintRecord(data, width, row_base, record.?.texel_offset, view);
            }
        }

        gl.glGenTextures(1, &self.layer_info_tex);
        gl.glActiveTexture(gl.GL_TEXTURE2);
        gl.glBindTexture(gl.GL_TEXTURE_2D, self.layer_info_tex);
        gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA32F, @intCast(width), @intCast(total_rows), 0, gl.GL_RGBA, gl.GL_FLOAT, @ptrCast(data.ptr));
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
        gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
    }

    // ── Draw ──

    fn drawTextInternal(self: *GlTextState, vertices: []const f32, mvp: Mat4, viewport_w: f32, viewport_h: f32, allow_subpixel: bool) void {
        // Ensure correct VAO is bound (may have been unbound by other renderers)
        gl.glBindVertexArray(self.vao);
        if (self.backend == .gl33) {
            gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
        }

        gl.glDisable(gl.GL_DEPTH_TEST);
        const floats_per_glyph = vertex.FLOATS_PER_VERTEX * vertex.VERTICES_PER_GLYPH;
        const total_glyphs = vertices.len / floats_per_glyph;
        const render_mode = subpixel_policy.chooseTextRenderMode(
            vertices,
            mvp,
            allow_subpixel,
            self.subpixel_order,
            self.subpixel_mode,
            self.supports_dual_source_blend,
            self.subpixel_backdrop,
        );
        if (!self.atlas_has_special_text_runs) {
            setTextBlendMode(false, render_mode);
            const prog_state = switch (render_mode) {
                .grayscale => &self.text_program,
                .subpixel_legacy, .subpixel_backdrop => &self.text_subpixel_program,
                .subpixel_dual_source => &self.text_subpixel_dual_program,
            };
            self.bindProgramState(prog_state, mvp, viewport_w, viewport_h, render_mode);
            self.drawGlyphRange(vertices, 0, total_glyphs);
            return;
        }

        var run_start: usize = 0;
        while (run_start < total_glyphs) {
            const special = glyphRunIsSpecial(vertices, run_start);
            var run_end = run_start + 1;
            while (run_end < total_glyphs and glyphRunIsSpecial(vertices, run_end) == special) {
                run_end += 1;
            }

            const run_mode: subpixel_policy.TextRenderMode = if (special) .grayscale else render_mode;
            setTextBlendMode(special, run_mode);
            const prog_state = if (special)
                self.ensureColrProgram()
            else switch (run_mode) {
                .grayscale => &self.text_program,
                .subpixel_legacy, .subpixel_backdrop => &self.text_subpixel_program,
                .subpixel_dual_source => &self.text_subpixel_dual_program,
            };
            self.bindProgramState(prog_state, mvp, viewport_w, viewport_h, run_mode);
            self.drawGlyphRange(vertices, run_start, run_end - run_start);
            run_start = run_end;
        }
    }

    pub fn drawText(self: *GlTextState, vertices: []const f32, mvp: Mat4, viewport_w: f32, viewport_h: f32) void {
        self.drawTextInternal(vertices, mvp, viewport_w, viewport_h, true);
    }

    pub fn drawTextGrayscale(self: *GlTextState, vertices: []const f32, mvp: Mat4, viewport_w: f32, viewport_h: f32) void {
        const prog_state = self.ensurePathProgram();
        gl.glBindVertexArray(self.vao);
        if (self.backend == .gl33) {
            gl.glBindBuffer(gl.GL_ARRAY_BUFFER, self.vbo);
        }

        gl.glDisable(gl.GL_DEPTH_TEST);
        gl.glEnable(gl.GL_BLEND);
        gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);

        self.bindProgramState(prog_state, mvp, viewport_w, viewport_h, .grayscale);
        self.drawGlyphRange(vertices, 0, vertices.len / (vertex.FLOATS_PER_VERTEX * vertex.VERTICES_PER_GLYPH));
    }

    pub fn resetFrameState(self: *GlTextState) void {
        self.frame_begun = false;
    }

    fn ensureColrProgram(self: *GlTextState) *const ProgramState {
        if (self.colr_program.handle == 0) {
            self.colr_program = loadProgramState("text-colr", shaders.vertex_shader, shaders.fragment_shader_colr, false) catch @panic("failed to link COLR text shader");
        }
        return &self.colr_program;
    }

    fn ensurePathProgram(self: *GlTextState) *const ProgramState {
        if (self.path_program.handle == 0) {
            self.path_program = loadProgramState("path", shaders.vertex_shader, shaders.fragment_shader, false) catch @panic("failed to link path shader");
        }
        return &self.path_program;
    }

    fn bindProgramState(self: *GlTextState, prog_state: *const ProgramState, mvp: Mat4, viewport_w: f32, viewport_h: f32, render_mode: subpixel_policy.TextRenderMode) void {
        if (prog_state.handle != self.active_program or !self.frame_begun) {
            gl.glUseProgram(prog_state.handle);
            self.active_program = prog_state.handle;

            if (self.backend == .gl44) {
                gl.glBindTextureUnit(0, self.curve_array);
                gl.glBindTextureUnit(1, self.band_array);
                if (prog_state.layer_tex_loc >= 0 and self.layer_info_tex != 0) gl.glBindTextureUnit(2, self.layer_info_tex);
                if (prog_state.image_tex_loc >= 0 and self.image_array != 0) gl.glBindTextureUnit(3, self.image_array);
            } else {
                gl.glActiveTexture(gl.GL_TEXTURE0);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.curve_array);
                gl.glActiveTexture(gl.GL_TEXTURE1);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.band_array);
                if (prog_state.layer_tex_loc >= 0 and self.layer_info_tex != 0) {
                    gl.glActiveTexture(gl.GL_TEXTURE2);
                    gl.glBindTexture(gl.GL_TEXTURE_2D, self.layer_info_tex);
                }
                if (prog_state.image_tex_loc >= 0 and self.image_array != 0) {
                    gl.glActiveTexture(gl.GL_TEXTURE3);
                    gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.image_array);
                }
            }

            if (prog_state.curve_tex_loc >= 0) gl.glUniform1i(prog_state.curve_tex_loc, 0);
            if (prog_state.band_tex_loc >= 0) gl.glUniform1i(prog_state.band_tex_loc, 1);
            if (prog_state.layer_tex_loc >= 0) gl.glUniform1i(prog_state.layer_tex_loc, 2);
            if (prog_state.image_tex_loc >= 0) gl.glUniform1i(prog_state.image_tex_loc, 3);
            self.frame_begun = true;
        }

        gl.glUniformMatrix4fv(prog_state.mvp_loc, 1, gl.GL_FALSE, &mvp.data);
        gl.glUniform2f(prog_state.viewport_loc, viewport_w, viewport_h);
        gl.glUniform1i(prog_state.fill_rule_loc, @intFromEnum(self.fill_rule));
        if (render_mode != .grayscale and prog_state.subpixel_order_loc >= 0) {
            gl.glUniform1i(prog_state.subpixel_order_loc, @intFromEnum(self.subpixel_order));
        }
        if (prog_state.subpixel_render_mode_loc >= 0) {
            gl.glUniform1i(prog_state.subpixel_render_mode_loc, subpixelRenderModeUniform(render_mode));
        }
        if (prog_state.subpixel_backdrop_loc >= 0) {
            const bg = self.subpixel_backdrop orelse .{ 0, 0, 0, 0 };
            gl.glUniform4f(prog_state.subpixel_backdrop_loc, bg[0], bg[1], bg[2], bg[3]);
        }
    }

    fn drawGlyphRange(self: *GlTextState, vertices: []const f32, glyph_offset: usize, glyph_count: usize) void {
        const floats_per_glyph = vertex.FLOATS_PER_VERTEX * vertex.VERTICES_PER_GLYPH;
        var glyphs_drawn: usize = 0;
        while (glyphs_drawn < glyph_count) {
            const chunk: usize = @min(glyph_count - glyphs_drawn, MAX_GLYPHS_PER_SEGMENT);
            const float_offset = (glyph_offset + glyphs_drawn) * floats_per_glyph;
            const byte_size = chunk * BYTES_PER_GLYPH;

            switch (self.backend) {
                .gl33 => {
                    gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(byte_size), @ptrCast(vertices[float_offset..].ptr), gl.GL_STREAM_DRAW);
                },
                .gl44 => {
                    const offset = @as(usize, self.ring_segment) * RING_SEGMENT_BYTES;

                    if (self.ring_fences[self.ring_segment]) |fence| {
                        const status = gl.glClientWaitSync(fence, 0, 0);
                        if (status != gl.GL_ALREADY_SIGNALED and status != gl.GL_CONDITION_SATISFIED) {
                            _ = gl.glClientWaitSync(fence, gl.GL_SYNC_FLUSH_COMMANDS_BIT, 1_000_000_000);
                        }
                        gl.glDeleteSync(fence);
                        self.ring_fences[self.ring_segment] = null;
                    }

                    const dst = self.persistent_map.?[offset..][0..byte_size];
                    const src: [*]const u8 = @ptrCast(vertices[float_offset..].ptr);
                    @memcpy(dst, src[0..byte_size]);

                    const stride: gl.GLint = vertex.FLOATS_PER_VERTEX * @sizeOf(f32);
                    gl.glVertexArrayVertexBuffer(self.vao, 0, self.vbo, @intCast(offset), stride);
                },
            }

            const index_count: gl.GLsizei = @intCast(chunk * 6);
            gl.glDrawElements(gl.GL_TRIANGLES, index_count, gl.GL_UNSIGNED_INT, null);

            if (self.backend == .gl44) {
                self.ring_fences[self.ring_segment] = gl.glFenceSync(gl.GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
                self.ring_segment = (self.ring_segment + 1) % RING_SEGMENTS;
            }

            glyphs_drawn += chunk;
        }
    }
};

// ── Module-level state instance ──

pub var state: GlTextState = .{};

// ── Forwarding functions for backward compatibility ──

pub fn init() !void {
    return state.init();
}

pub fn deinit() void {
    state.deinit();
}

pub fn buildTextureArrays(atlases: []const *const snail_mod.Atlas, out_views: []snail_mod.AtlasHandle) void {
    state.buildTextureArrays(atlases, out_views);
}

pub fn buildImageArray(images: []const *const snail_mod.Image, out_views: []snail_mod.ImageHandle) void {
    state.buildImageArray(images, out_views);
}

pub fn drawText(vertices: []const f32, mvp: Mat4, viewport_w: f32, viewport_h: f32) void {
    state.drawText(vertices, mvp, viewport_w, viewport_h);
}

pub fn drawTextGrayscale(vertices: []const f32, mvp: Mat4, viewport_w: f32, viewport_h: f32) void {
    state.drawTextGrayscale(vertices, mvp, viewport_w, viewport_h);
}

pub fn resetFrameState() void {
    state.resetFrameState();
}

pub fn imageTextureArray() gl.GLuint {
    return state.image_array;
}

pub fn getBackendName() []const u8 {
    return state.getBackendName();
}

// ── Pure utility functions (no mutable state access) ──

fn setupVertexAttribs() void {
    const stride: gl.GLsizei = vertex.FLOATS_PER_VERTEX * @sizeOf(f32);
    inline for (0..5) |i| {
        gl.glVertexAttribPointer(@intCast(i), 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(i * 4 * @sizeOf(f32)));
        gl.glEnableVertexAttribArray(@intCast(i));
    }
}

fn initEbo() void {
    const total_indices: usize = MAX_GLYPHS_PER_SEGMENT * 6;
    const buf_size: gl.GLsizeiptr = @intCast(total_indices * @sizeOf(u32));
    gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, buf_size, null, gl.GL_STATIC_DRAW);

    // Generate the deterministic quad index pattern directly into GPU memory
    const ptr = gl.glMapBufferRange(gl.GL_ELEMENT_ARRAY_BUFFER, 0, buf_size, gl.GL_MAP_WRITE_BIT);
    if (ptr) |raw| {
        const indices: [*]u32 = @ptrCast(@alignCast(raw));
        for (0..MAX_GLYPHS_PER_SEGMENT) |i| {
            const base: u32 = @intCast(i * 4);
            const idx = i * 6;
            indices[idx + 0] = base + 0;
            indices[idx + 1] = base + 1;
            indices[idx + 2] = base + 2;
            indices[idx + 3] = base + 0;
            indices[idx + 4] = base + 2;
            indices[idx + 5] = base + 3;
        }
        _ = gl.glUnmapBuffer(gl.GL_ELEMENT_ARRAY_BUFFER);
    }
}

// ── Shader compilation ──

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

fn loadProgramState(cache_label: []const u8, vs_src: [*c]const u8, fs_src: [*c]const u8, dual_source: bool) !ProgramState {
    const handle = try linkProgram(cache_label, vs_src, fs_src, dual_source);
    return .{
        .handle = handle,
        .mvp_loc = gl.glGetUniformLocation(handle, "u_mvp"),
        .viewport_loc = gl.glGetUniformLocation(handle, "u_viewport"),
        .curve_tex_loc = gl.glGetUniformLocation(handle, "u_curve_tex"),
        .band_tex_loc = gl.glGetUniformLocation(handle, "u_band_tex"),
        .image_tex_loc = gl.glGetUniformLocation(handle, "u_image_tex"),
        .fill_rule_loc = gl.glGetUniformLocation(handle, "u_fill_rule"),
        .subpixel_order_loc = gl.glGetUniformLocation(handle, "u_subpixel_order"),
        .subpixel_render_mode_loc = gl.glGetUniformLocation(handle, "u_subpixel_render_mode"),
        .subpixel_backdrop_loc = gl.glGetUniformLocation(handle, "u_subpixel_backdrop"),
        .layer_tex_loc = gl.glGetUniformLocation(handle, "u_layer_tex"),
    };
}

fn deleteProgramState(prog_state: *ProgramState) void {
    if (prog_state.handle != 0) gl.glDeleteProgram(prog_state.handle);
    prog_state.* = .{};
}

fn linkProgram(_: []const u8, vs_src: [*c]const u8, fs_src: [*c]const u8, dual_source: bool) !gl.GLuint {
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

fn setTexParams(target: gl.GLenum) void {
    gl.glTexParameteri(target, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(target, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(target, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(target, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
}

fn setTexParamsDSA(tex: gl.GLuint) void {
    gl.glTextureParameteri(tex, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
    gl.glTextureParameteri(tex, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
    gl.glTextureParameteri(tex, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTextureParameteri(tex, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
}

fn setImageTexParams(target: gl.GLenum) void {
    gl.glTexParameteri(target, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(target, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(target, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(target, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
}

fn setImageTexParamsDSA(tex: gl.GLuint) void {
    gl.glTextureParameteri(tex, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glTextureParameteri(tex, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glTextureParameteri(tex, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTextureParameteri(tex, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
}

fn setTextBlendMode(special: bool, render_mode: subpixel_policy.TextRenderMode) void {
    if (!special) {
        switch (render_mode) {
            .subpixel_backdrop => {
                gl.glDisable(gl.GL_BLEND);
                return;
            },
            .subpixel_dual_source => {
                gl.glEnable(gl.GL_BLEND);
                gl.glBlendFuncSeparate(gl.GL_ONE, gl.GL_ONE_MINUS_SRC1_COLOR, gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
                return;
            },
            else => {},
        }
    }
    gl.glEnable(gl.GL_BLEND);
    gl.glBlendFuncSeparate(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA, gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);
}

fn glyphRunIsSpecial(vertices: []const f32, glyph_index: usize) bool {
    const float_offset = glyph_index * vertex.FLOATS_PER_VERTEX * vertex.VERTICES_PER_GLYPH;
    const gw_bits: u32 = @bitCast(vertices[float_offset + 7]);
    return (gw_bits >> 24) == 0xFF;
}

fn atlasesHaveSpecialTextRuns(atlases: []const *const snail_mod.Atlas) bool {
    for (atlases) |atlas| {
        if (atlas.colr_base_map != null) return true;
    }
    return false;
}

fn detectDualSourceBlendSupport() bool {
    var max_draw_buffers: gl.GLint = 0;
    gl.glGetIntegerv(gl.GL_MAX_DUAL_SOURCE_DRAW_BUFFERS, &max_draw_buffers);
    return max_draw_buffers >= 1;
}

fn subpixelRenderModeUniform(render_mode: subpixel_policy.TextRenderMode) gl.GLint {
    return switch (render_mode) {
        .grayscale, .subpixel_legacy => 0,
        .subpixel_backdrop => 1,
        .subpixel_dual_source => 2,
    };
}
