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
var backend: Backend = .gl33;

pub fn getBackendName() []const u8 {
    return switch (backend) {
        .gl33 => "GL 3.3",
        .gl44 => "GL 4.4 (persistent mapped)",
    };
}

// ── Shared state ──

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

var text_program = ProgramState{};
var text_subpixel_program = ProgramState{};
var text_subpixel_dual_program = ProgramState{};
var colr_program = ProgramState{};
var path_program = ProgramState{};

pub var subpixel_order: SubpixelOrder = .none;
pub var subpixel_mode: SubpixelMode = .safe;
pub var subpixel_backdrop: ?[4]f32 = null;
pub var fill_rule: FillRule = .non_zero;

pub const FillRule = enum(c_int) {
    non_zero = 0,
    even_odd = 1,
};

var vao: gl.GLuint = 0;
var vbo: gl.GLuint = 0;
var ebo: gl.GLuint = 0;

var curve_array: gl.GLuint = 0;
var band_array: gl.GLuint = 0;
var layer_info_tex: gl.GLuint = 0;
var image_array: gl.GLuint = 0;

var active_program: gl.GLuint = 0;
var frame_begun: bool = false;
var supports_dual_source_blend: bool = false;

// ── GL 4.4 persistent mapping state ──

const RING_SEGMENTS = 3;
const RING_TOTAL_BYTES = 12 * 1024 * 1024; // 12 MB (4 MB per segment)
const RING_SEGMENT_BYTES = RING_TOTAL_BYTES / RING_SEGMENTS;
const BYTES_PER_GLYPH = vertex.FLOATS_PER_VERTEX * vertex.VERTICES_PER_GLYPH * @sizeOf(f32);
const MAX_GLYPHS_PER_SEGMENT = RING_SEGMENT_BYTES / BYTES_PER_GLYPH;

var persistent_map: ?[*]u8 = null;
var ring_fences: [RING_SEGMENTS]gl.GLsync = .{null} ** RING_SEGMENTS;
var ring_segment: u32 = 0;

const MAX_ATLASES = upload_common.MAX_ATLASES;
const MAX_PAGES_PER_ATLAS = upload_common.MAX_PAGES_PER_ATLAS;
const MAX_IMAGES = upload_common.MAX_IMAGES;

const AtlasSlot = upload_common.AtlasSlot(snail_mod.Atlas, snail_mod.AtlasPage, MAX_PAGES_PER_ATLAS);
const ImageSlot = upload_common.ImageSlot(snail_mod.Image);

var atlas_slots: [MAX_ATLASES]AtlasSlot = std.mem.zeroes([MAX_ATLASES]AtlasSlot);
var atlas_slot_count: usize = 0;
var allocated_curve_height: u32 = 0;
var allocated_band_height: u32 = 0;
var allocated_layer_count: u32 = 0;
var atlas_has_special_text_runs: bool = false;
var image_slots: [MAX_IMAGES]ImageSlot = std.mem.zeroes([MAX_IMAGES]ImageSlot);
var image_slot_count: usize = 0;
var allocated_image_width: u32 = 0;
var allocated_image_height: u32 = 0;
var allocated_image_count: u32 = 0;

// ── Init / Deinit ──

pub fn init() !void {
    backend = gl_backend.detect(gl);
    supports_dual_source_blend = detectDualSourceBlendSupport();

    // Keep startup on the lightweight plain-glyph shaders. The heavier path/COLR
    // shader is linked lazily the first time sentinel runs are drawn.
    text_program = try loadProgramState("text", shaders.vertex_shader, shaders.fragment_shader_text, false);
    text_subpixel_program = try loadProgramState("text-subpixel", shaders.vertex_shader, shaders.fragment_shader_text_subpixel, false);
    if (supports_dual_source_blend) {
        text_subpixel_dual_program = try loadProgramState("text-subpixel-dual", shaders.vertex_shader, shaders.fragment_shader_text_subpixel_dual, true);
    }

    switch (backend) {
        .gl33 => initGl33(),
        .gl44 => initGl44(),
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

fn initGl33() void {
    gl.glGenVertexArrays(1, &vao);
    gl.glGenBuffers(1, &vbo);
    gl.glGenBuffers(1, &ebo);
    gl.glBindVertexArray(vao);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);
    gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, ebo);
    initEbo();
    setupVertexAttribs();
}

fn initGl44() void {
    // DSA: create VAO, VBO, EBO without binding
    gl.glCreateVertexArrays(1, &vao);
    gl.glCreateBuffers(1, &vbo);
    gl.glCreateBuffers(1, &ebo);

    // Persistent mapped VBO
    const flags: gl.GLbitfield = gl.GL_MAP_WRITE_BIT | gl.GL_MAP_PERSISTENT_BIT | gl.GL_MAP_COHERENT_BIT;
    gl.glNamedBufferStorage(vbo, RING_TOTAL_BYTES, null, flags);
    persistent_map = @ptrCast(gl.glMapNamedBufferRange(vbo, 0, RING_TOTAL_BYTES, flags));

    if (persistent_map == null) {
        // Fallback to GL 3.3 if mapping fails
        std.debug.print("snail: persistent mapping failed, falling back to GL 3.3\n", .{});
        gl.glDeleteVertexArrays(1, &vao);
        gl.glDeleteBuffers(1, &vbo);
        gl.glDeleteBuffers(1, &ebo);
        backend = .gl33;
        initGl33();
        return;
    }

    // DSA vertex attribs
    const stride: gl.GLint = vertex.FLOATS_PER_VERTEX * @sizeOf(f32);
    gl.glVertexArrayVertexBuffer(vao, 0, vbo, 0, stride);
    gl.glVertexArrayElementBuffer(vao, ebo);

    inline for (0..5) |i| {
        const loc: u32 = @intCast(i);
        gl.glEnableVertexArrayAttrib(vao, loc);
        gl.glVertexArrayAttribFormat(vao, loc, 4, gl.GL_FLOAT, gl.GL_FALSE, @intCast(i * 4 * @sizeOf(f32)));
        gl.glVertexArrayAttribBinding(vao, loc, 0);
    }

    // EBO (static data, not persistently mapped)
    gl.glBindVertexArray(vao);
    gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, ebo);
    initEbo();
}

fn setupVertexAttribs() void {
    const stride: gl.GLsizei = vertex.FLOATS_PER_VERTEX * @sizeOf(f32);
    inline for (0..5) |i| {
        gl.glVertexAttribPointer(@intCast(i), 4, gl.GL_FLOAT, gl.GL_FALSE, stride, @ptrFromInt(i * 4 * @sizeOf(f32)));
        gl.glEnableVertexAttribArray(@intCast(i));
    }
}

pub fn deinit() void {
    if (backend == .gl44) {
        // Delete fences
        for (&ring_fences) |*f| {
            if (f.*) |fence| {
                gl.glDeleteSync(fence);
                f.* = null;
            }
        }
        // Unmap persistent buffer
        if (persistent_map != null) {
            _ = gl.glUnmapNamedBuffer(vbo);
            persistent_map = null;
        }
    }

    deleteProgramState(&text_program);
    deleteProgramState(&text_subpixel_program);
    deleteProgramState(&text_subpixel_dual_program);
    deleteProgramState(&colr_program);
    deleteProgramState(&path_program);
    if (vao != 0) gl.glDeleteVertexArrays(1, &vao);
    if (vbo != 0) gl.glDeleteBuffers(1, &vbo);
    if (ebo != 0) gl.glDeleteBuffers(1, &ebo);
    destroyAtlasTextureResources();
    destroyImageResources();
    resetAtlasUploadState();
}

// ── Texture array management ──

fn destroyAtlasTextureResources() void {
    if (curve_array != 0) gl.glDeleteTextures(1, &curve_array);
    if (band_array != 0) gl.glDeleteTextures(1, &band_array);
    if (layer_info_tex != 0) gl.glDeleteTextures(1, &layer_info_tex);
    curve_array = 0;
    band_array = 0;
    layer_info_tex = 0;
}

fn destroyImageResources() void {
    if (image_array != 0) gl.glDeleteTextures(1, &image_array);
    image_array = 0;
    image_slot_count = 0;
    allocated_image_width = 0;
    allocated_image_height = 0;
    allocated_image_count = 0;
    for (&image_slots) |*slot| slot.* = .{};
}

pub fn buildTextureArrays(atlases: []const *const snail_mod.Atlas, out_views: []snail_mod.AtlasView) void {
    std.debug.assert(atlases.len == out_views.len);

    if (atlases.len == 0) {
        destroyAtlasTextureResources();
        resetAtlasUploadState();
        return;
    }

    const can_incremental = texturesReady() and atlasSlotsCompatible(atlases);
    if (!can_incremental) {
        rebuildTextureArrays(atlases, out_views);
    } else if (!appendTexturePages(atlases)) {
        rebuildTextureArrays(atlases, out_views);
    } else {
        fillAtlasViews(atlases, out_views);
        ensureAtlasImagesRegistered(atlases);
        rebuildLayerInfoTexture(atlases);
        atlas_has_special_text_runs = atlasesHaveSpecialTextRuns(atlases);
        active_program = 0;
        frame_begun = false;
    }
}

pub fn buildImageArray(images: []const *const snail_mod.Image, out_views: []snail_mod.ImageView) void {
    std.debug.assert(images.len == out_views.len);
    ensureImagesRegistered(images);
    for (images, 0..) |image, i| {
        out_views[i] = currentImageView(image);
    }
    active_program = 0;
    frame_begun = false;
}

pub fn imageTextureArray() gl.GLuint {
    return image_array;
}

fn currentImageView(image: *const snail_mod.Image) snail_mod.ImageView {
    return upload_common.currentImageView(
        snail_mod.ImageView,
        image_slots[0..],
        image_slot_count,
        allocated_image_width,
        allocated_image_height,
        image,
    );
}

fn findImageSlot(image: *const snail_mod.Image) ?usize {
    return upload_common.findImageSlot(image_slots[0..], image_slot_count, image);
}

fn ensureAtlasImagesRegistered(atlases: []const *const snail_mod.Atlas) void {
    var scratch: [MAX_IMAGES]*const snail_mod.Image = undefined;
    const count = upload_common.collectAtlasImages(image_slots[0..], image_slot_count, atlases, scratch[0..]);
    ensureImagesRegistered(scratch[0..count]);
}

fn ensureImagesRegistered(images: []const *const snail_mod.Image) void {
    if (images.len == 0) return;

    var new_images: [MAX_IMAGES]*const snail_mod.Image = undefined;
    var new_count: usize = 0;
    var required_width = allocated_image_width;
    var required_height = allocated_image_height;
    for (images) |image| {
        required_width = @max(required_width, image.width);
        required_height = @max(required_height, image.height);
        if (findImageSlot(image) != null) continue;
        if (image_slot_count + new_count >= MAX_IMAGES) break;
        new_images[new_count] = image;
        new_count += 1;
    }

    if (new_count == 0 and image_array != 0) return;

    const required_count: u32 = @intCast(image_slot_count + new_count);
    const new_width = upload_common.heightCapacity(@max(required_width, 1));
    const new_height = upload_common.heightCapacity(@max(required_height, 1));
    const needs_rebuild = image_array == 0 or
        required_count > allocated_image_count or
        new_width > allocated_image_width or
        new_height > allocated_image_height;

    if (needs_rebuild) {
        for (new_images[0..new_count], 0..) |image, i| {
            image_slots[image_slot_count + i] = .{ .image = image };
        }
        image_slot_count += new_count;
        rebuildImageArray();
        return;
    }

    for (new_images[0..new_count], 0..) |image, i| {
        const slot_index = image_slot_count + i;
        image_slots[slot_index] = .{ .image = image };
        uploadImageLayer(image, @intCast(slot_index));
    }
    image_slot_count += new_count;
}

fn rebuildImageArray() void {
    if (image_array != 0) gl.glDeleteTextures(1, &image_array);
    image_array = 0;

    if (image_slot_count == 0) {
        allocated_image_width = 0;
        allocated_image_height = 0;
        allocated_image_count = 0;
        return;
    }

    var max_width: u32 = 1;
    var max_height: u32 = 1;
    for (image_slots[0..image_slot_count]) |slot| {
        const image = slot.image orelse continue;
        max_width = @max(max_width, image.width);
        max_height = @max(max_height, image.height);
    }

    allocated_image_width = upload_common.heightCapacity(max_width);
    allocated_image_height = upload_common.heightCapacity(max_height);
    allocated_image_count = upload_common.atlasCapacity(@intCast(image_slot_count));

    switch (backend) {
        .gl33 => {
            gl.glGenTextures(1, &image_array);
            gl.glActiveTexture(gl.GL_TEXTURE3);
            gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, image_array);
            gl.glTexImage3D(
                gl.GL_TEXTURE_2D_ARRAY,
                0,
                gl.GL_SRGB8_ALPHA8,
                @intCast(allocated_image_width),
                @intCast(allocated_image_height),
                @intCast(allocated_image_count),
                0,
                gl.GL_RGBA,
                gl.GL_UNSIGNED_BYTE,
                null,
            );
            setImageTexParams(gl.GL_TEXTURE_2D_ARRAY);
        },
        .gl44 => {
            gl.glCreateTextures(gl.GL_TEXTURE_2D_ARRAY, 1, &image_array);
            gl.glTextureStorage3D(
                image_array,
                1,
                gl.GL_SRGB8_ALPHA8,
                @intCast(allocated_image_width),
                @intCast(allocated_image_height),
                @intCast(allocated_image_count),
            );
            setImageTexParamsDSA(image_array);
            gl.glBindTextureUnit(3, image_array);
        },
    }

    for (image_slots[0..image_slot_count], 0..) |slot, i| {
        uploadImageLayer(slot.image.?, @intCast(i));
    }
}

fn uploadImageLayer(image: *const snail_mod.Image, layer: u32) void {
    switch (backend) {
        .gl33 => {
            gl.glActiveTexture(gl.GL_TEXTURE3);
            gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, image_array);
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
                image_array,
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

fn rebuildTextureArrays(atlases: []const *const snail_mod.Atlas, out_views: []snail_mod.AtlasView) void {
    destroyAtlasTextureResources();
    resetAtlasUploadState();

    const slot_info = upload_common.rebuildAtlasSlots(atlas_slots[0..], atlases);
    atlas_slot_count = slot_info.atlas_slot_count;
    allocated_curve_height = slot_info.allocated_curve_height;
    allocated_band_height = slot_info.allocated_band_height;
    allocated_layer_count = slot_info.allocated_layer_count;

    if (atlases.len == 0) return;

    createTextureArrays(atlases[0], allocated_layer_count, allocated_curve_height, allocated_band_height);
    uploadAllPages(atlases);
    ensureAtlasImagesRegistered(atlases);
    rebuildLayerInfoTexture(atlases);
    atlas_has_special_text_runs = atlasesHaveSpecialTextRuns(atlases);
    fillAtlasViews(atlases, out_views);
    active_program = 0;
    frame_begun = false;
}

fn appendTexturePages(atlases: []const *const snail_mod.Atlas) bool {
    var max_curve_h: u32 = allocated_curve_height;
    var max_band_h: u32 = allocated_band_height;
    var start_pages: [MAX_ATLASES]u32 = undefined;

    for (atlases, 0..) |atlas, i| {
        if (i >= atlas_slot_count) return false;
        const slot = &atlas_slots[i];
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

    if (atlases.len != atlas_slot_count) return false;
    if (max_curve_h > allocated_curve_height or max_band_h > allocated_band_height) return false;

    switch (backend) {
        .gl33 => uploadTexturePagesGl33WithStarts(atlases, start_pages[0..atlases.len]),
        .gl44 => uploadTexturePagesGl44WithStarts(atlases, start_pages[0..atlases.len]),
    }

    upload_common.refreshAtlasSlots(atlas_slots[0..], atlases);
    return true;
}

fn texturesReady() bool {
    return curve_array != 0 and band_array != 0 and atlas_slot_count > 0;
}

fn atlasSlotsCompatible(atlases: []const *const snail_mod.Atlas) bool {
    return upload_common.atlasSlotsCompatible(atlas_slots[0..], atlas_slot_count, atlases);
}

fn fillAtlasViews(atlases: []const *const snail_mod.Atlas, out_views: []snail_mod.AtlasView) void {
    upload_common.fillAtlasViews(atlas_slots[0..], atlases, out_views);
}

fn resetAtlasUploadState() void {
    atlas_slot_count = 0;
    allocated_curve_height = 0;
    allocated_band_height = 0;
    allocated_layer_count = 0;
    atlas_has_special_text_runs = false;
    for (&atlas_slots) |*slot| slot.* = .{};
}

fn atlasesHaveSpecialTextRuns(atlases: []const *const snail_mod.Atlas) bool {
    for (atlases) |atlas| {
        if (atlas.colr_base_map != null) return true;
    }
    return false;
}

fn createTextureArrays(first_atlas: *const snail_mod.Atlas, layer_count: u32, max_curve_h: u32, max_band_h: u32) void {
    const first_page = first_atlas.page(0);

    switch (backend) {
        .gl33 => {
            gl.glGenTextures(1, &curve_array);
            gl.glActiveTexture(gl.GL_TEXTURE0);
            gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, curve_array);
            gl.glTexImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, gl.GL_RGBA16F, @intCast(first_page.curve_width), @intCast(max_curve_h), @intCast(layer_count), 0, gl.GL_RGBA, gl.GL_HALF_FLOAT, null);
            setTexParams(gl.GL_TEXTURE_2D_ARRAY);

            gl.glGenTextures(1, &band_array);
            gl.glActiveTexture(gl.GL_TEXTURE1);
            gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, band_array);
            gl.glTexImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, gl.GL_RG16UI, @intCast(first_page.band_width), @intCast(max_band_h), @intCast(layer_count), 0, gl.GL_RG_INTEGER, gl.GL_UNSIGNED_SHORT, null);
            setTexParams(gl.GL_TEXTURE_2D_ARRAY);
        },
        .gl44 => {
            gl.glCreateTextures(gl.GL_TEXTURE_2D_ARRAY, 1, &curve_array);
            gl.glTextureStorage3D(curve_array, 1, gl.GL_RGBA16F, @intCast(first_page.curve_width), @intCast(max_curve_h), @intCast(layer_count));
            setTexParamsDSA(curve_array);

            gl.glCreateTextures(gl.GL_TEXTURE_2D_ARRAY, 1, &band_array);
            gl.glTextureStorage3D(band_array, 1, gl.GL_RG16UI, @intCast(first_page.band_width), @intCast(max_band_h), @intCast(layer_count));
            setTexParamsDSA(band_array);
            gl.glBindTextureUnit(0, curve_array);
            gl.glBindTextureUnit(1, band_array);
        },
    }
}

fn uploadAllPages(atlases: []const *const snail_mod.Atlas) void {
    switch (backend) {
        .gl33 => uploadTexturePagesGl33WithStarts(atlases, null),
        .gl44 => uploadTexturePagesGl44WithStarts(atlases, null),
    }
}

fn uploadTexturePagesGl33WithStarts(atlases: []const *const snail_mod.Atlas, start_pages: ?[]const u32) void {
    for (atlases, 0..) |atlas, i| {
        const start_page = if (start_pages) |sp| sp[i] else 0;
        const base_layer = atlas_slots[i].base_layer;
        for (start_page..atlas.pageCount()) |page_index| {
            const page = atlas.page(@intCast(page_index));
            const layer = base_layer + @as(u32, @intCast(page_index));
            const layer_z: gl.GLint = @intCast(layer);
            gl.glActiveTexture(gl.GL_TEXTURE0);
            gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, curve_array);
            gl.glTexSubImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, 0, 0, layer_z, @intCast(page.curve_width), @intCast(page.curve_height), 1, gl.GL_RGBA, gl.GL_HALF_FLOAT, page.curve_data.ptr);
            gl.glActiveTexture(gl.GL_TEXTURE1);
            gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, band_array);
            gl.glTexSubImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, 0, 0, layer_z, @intCast(page.band_width), @intCast(page.band_height), 1, gl.GL_RG_INTEGER, gl.GL_UNSIGNED_SHORT, page.band_data.ptr);
        }
    }
}

fn uploadTexturePagesGl44WithStarts(atlases: []const *const snail_mod.Atlas, start_pages: ?[]const u32) void {
    for (atlases, 0..) |atlas, i| {
        const start_page = if (start_pages) |sp| sp[i] else 0;
        const base_layer = atlas_slots[i].base_layer;
        for (start_page..atlas.pageCount()) |page_index| {
            const page = atlas.page(@intCast(page_index));
            const layer = base_layer + @as(u32, @intCast(page_index));
            const layer_z: gl.GLint = @intCast(layer);
            gl.glTextureSubImage3D(curve_array, 0, 0, 0, layer_z, @intCast(page.curve_width), @intCast(page.curve_height), 1, gl.GL_RGBA, gl.GL_HALF_FLOAT, page.curve_data.ptr);
            gl.glTextureSubImage3D(band_array, 0, 0, 0, layer_z, @intCast(page.band_width), @intCast(page.band_height), 1, gl.GL_RG_INTEGER, gl.GL_UNSIGNED_SHORT, page.band_data.ptr);
        }
    }
}

fn rebuildLayerInfoTexture(atlases: []const *const snail_mod.Atlas) void {
    if (layer_info_tex != 0) gl.glDeleteTextures(1, &layer_info_tex);
    layer_info_tex = 0;

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
        const row_base = atlas_slots[i].info_row_base;
        const row_count = atlas.layer_info_height;
        const copy_len = @as(usize, atlas.layer_info_width) * @as(usize, row_count) * 4;
        const dst_base = @as(usize, row_base) * @as(usize, width) * 4;
        @memcpy(data[dst_base .. dst_base + copy_len], lid[0..copy_len]);

        const records = atlas.paint_image_records orelse continue;
        for (records) |record| {
            const image = (record orelse continue).image;
            const view = currentImageView(image);
            upload_common.patchImagePaintRecord(data, width, row_base, record.?.texel_offset, view);
        }
    }

    gl.glGenTextures(1, &layer_info_tex);
    gl.glActiveTexture(gl.GL_TEXTURE2);
    gl.glBindTexture(gl.GL_TEXTURE_2D, layer_info_tex);
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA32F, @intCast(width), @intCast(total_rows), 0, gl.GL_RGBA, gl.GL_FLOAT, @ptrCast(data.ptr));
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
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

// ── Draw ──

fn drawTextInternal(vertices: []const f32, mvp: Mat4, viewport_w: f32, viewport_h: f32, allow_subpixel: bool) void {
    // Ensure correct VAO is bound (may have been unbound by other renderers)
    gl.glBindVertexArray(vao);
    if (backend == .gl33) {
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);
    }

    gl.glDisable(gl.GL_DEPTH_TEST);
    const floats_per_glyph = vertex.FLOATS_PER_VERTEX * vertex.VERTICES_PER_GLYPH;
    const total_glyphs = vertices.len / floats_per_glyph;
    const render_mode = subpixel_policy.chooseTextRenderMode(
        vertices,
        mvp,
        allow_subpixel,
        subpixel_order,
        subpixel_mode,
        supports_dual_source_blend,
        subpixel_backdrop,
    );
    if (!atlas_has_special_text_runs) {
        setTextBlendMode(false, render_mode);
        const state = switch (render_mode) {
            .grayscale => &text_program,
            .subpixel_legacy, .subpixel_backdrop => &text_subpixel_program,
            .subpixel_dual_source => &text_subpixel_dual_program,
        };
        bindProgramState(state, mvp, viewport_w, viewport_h, render_mode);
        drawGlyphRange(vertices, 0, total_glyphs);
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
        const state = if (special)
            ensureColrProgram()
        else switch (run_mode) {
            .grayscale => &text_program,
            .subpixel_legacy, .subpixel_backdrop => &text_subpixel_program,
            .subpixel_dual_source => &text_subpixel_dual_program,
        };
        bindProgramState(state, mvp, viewport_w, viewport_h, run_mode);
        drawGlyphRange(vertices, run_start, run_end - run_start);
        run_start = run_end;
    }
}

pub fn drawText(vertices: []const f32, mvp: Mat4, viewport_w: f32, viewport_h: f32) void {
    drawTextInternal(vertices, mvp, viewport_w, viewport_h, true);
}

pub fn drawTextGrayscale(vertices: []const f32, mvp: Mat4, viewport_w: f32, viewport_h: f32) void {
    const state = ensurePathProgram();
    gl.glBindVertexArray(vao);
    if (backend == .gl33) {
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);
    }

    gl.glDisable(gl.GL_DEPTH_TEST);
    gl.glEnable(gl.GL_BLEND);
    gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);

    bindProgramState(state, mvp, viewport_w, viewport_h, .grayscale);
    drawGlyphRange(vertices, 0, vertices.len / (vertex.FLOATS_PER_VERTEX * vertex.VERTICES_PER_GLYPH));
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

pub fn resetFrameState() void {
    frame_begun = false;
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

fn deleteProgramState(state: *ProgramState) void {
    if (state.handle != 0) gl.glDeleteProgram(state.handle);
    state.* = .{};
}

fn ensureColrProgram() *const ProgramState {
    if (colr_program.handle == 0) {
        colr_program = loadProgramState("text-colr", shaders.vertex_shader, shaders.fragment_shader_colr, false) catch @panic("failed to link COLR text shader");
    }
    return &colr_program;
}

fn ensurePathProgram() *const ProgramState {
    if (path_program.handle == 0) {
        path_program = loadProgramState("path", shaders.vertex_shader, shaders.fragment_shader, false) catch @panic("failed to link path shader");
    }
    return &path_program;
}

fn bindProgramState(state: *const ProgramState, mvp: Mat4, viewport_w: f32, viewport_h: f32, render_mode: subpixel_policy.TextRenderMode) void {
    if (state.handle != active_program or !frame_begun) {
        gl.glUseProgram(state.handle);
        active_program = state.handle;

        if (backend == .gl44) {
            gl.glBindTextureUnit(0, curve_array);
            gl.glBindTextureUnit(1, band_array);
            if (state.layer_tex_loc >= 0 and layer_info_tex != 0) gl.glBindTextureUnit(2, layer_info_tex);
            if (state.image_tex_loc >= 0 and image_array != 0) gl.glBindTextureUnit(3, image_array);
        } else {
            gl.glActiveTexture(gl.GL_TEXTURE0);
            gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, curve_array);
            gl.glActiveTexture(gl.GL_TEXTURE1);
            gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, band_array);
            if (state.layer_tex_loc >= 0 and layer_info_tex != 0) {
                gl.glActiveTexture(gl.GL_TEXTURE2);
                gl.glBindTexture(gl.GL_TEXTURE_2D, layer_info_tex);
            }
            if (state.image_tex_loc >= 0 and image_array != 0) {
                gl.glActiveTexture(gl.GL_TEXTURE3);
                gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, image_array);
            }
        }

        if (state.curve_tex_loc >= 0) gl.glUniform1i(state.curve_tex_loc, 0);
        if (state.band_tex_loc >= 0) gl.glUniform1i(state.band_tex_loc, 1);
        if (state.layer_tex_loc >= 0) gl.glUniform1i(state.layer_tex_loc, 2);
        if (state.image_tex_loc >= 0) gl.glUniform1i(state.image_tex_loc, 3);
        frame_begun = true;
    }

    gl.glUniformMatrix4fv(state.mvp_loc, 1, gl.GL_FALSE, &mvp.data);
    gl.glUniform2f(state.viewport_loc, viewport_w, viewport_h);
    gl.glUniform1i(state.fill_rule_loc, @intFromEnum(fill_rule));
    if (render_mode != .grayscale and state.subpixel_order_loc >= 0) {
        gl.glUniform1i(state.subpixel_order_loc, @intFromEnum(subpixel_order));
    }
    if (state.subpixel_render_mode_loc >= 0) {
        gl.glUniform1i(state.subpixel_render_mode_loc, subpixelRenderModeUniform(render_mode));
    }
    if (state.subpixel_backdrop_loc >= 0) {
        const bg = subpixel_backdrop orelse .{ 0, 0, 0, 0 };
        gl.glUniform4f(state.subpixel_backdrop_loc, bg[0], bg[1], bg[2], bg[3]);
    }
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

fn drawGlyphRange(vertices: []const f32, glyph_offset: usize, glyph_count: usize) void {
    const floats_per_glyph = vertex.FLOATS_PER_VERTEX * vertex.VERTICES_PER_GLYPH;
    var glyphs_drawn: usize = 0;
    while (glyphs_drawn < glyph_count) {
        const chunk: usize = @min(glyph_count - glyphs_drawn, MAX_GLYPHS_PER_SEGMENT);
        const float_offset = (glyph_offset + glyphs_drawn) * floats_per_glyph;
        const byte_size = chunk * BYTES_PER_GLYPH;

        switch (backend) {
            .gl33 => {
                gl.glBufferData(gl.GL_ARRAY_BUFFER, @intCast(byte_size), @ptrCast(vertices[float_offset..].ptr), gl.GL_STREAM_DRAW);
            },
            .gl44 => {
                const offset = @as(usize, ring_segment) * RING_SEGMENT_BYTES;

                if (ring_fences[ring_segment]) |fence| {
                    const status = gl.glClientWaitSync(fence, 0, 0);
                    if (status != gl.GL_ALREADY_SIGNALED and status != gl.GL_CONDITION_SATISFIED) {
                        _ = gl.glClientWaitSync(fence, gl.GL_SYNC_FLUSH_COMMANDS_BIT, 1_000_000_000);
                    }
                    gl.glDeleteSync(fence);
                    ring_fences[ring_segment] = null;
                }

                const dst = persistent_map.?[offset..][0..byte_size];
                const src: [*]const u8 = @ptrCast(vertices[float_offset..].ptr);
                @memcpy(dst, src[0..byte_size]);

                const stride: gl.GLint = vertex.FLOATS_PER_VERTEX * @sizeOf(f32);
                gl.glVertexArrayVertexBuffer(vao, 0, vbo, @intCast(offset), stride);
            },
        }

        const index_count: gl.GLsizei = @intCast(chunk * 6);
        gl.glDrawElements(gl.GL_TRIANGLES, index_count, gl.GL_UNSIGNED_INT, null);

        if (backend == .gl44) {
            ring_fences[ring_segment] = gl.glFenceSync(gl.GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
            ring_segment = (ring_segment + 1) % RING_SEGMENTS;
        }

        glyphs_drawn += chunk;
    }
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
