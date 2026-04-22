const std = @import("std");
const gl = @import("gl.zig").gl;
const shaders = @import("shaders.zig");
const vertex = @import("vertex.zig");
const vec = @import("../math/vec.zig");
const Mat4 = vec.Mat4;
const snail_mod = @import("../snail.zig");
const SubpixelOrder = @import("subpixel_order.zig").SubpixelOrder;

// ── Backend selection ──

pub const Backend = enum { gl33, gl44 };
var backend: Backend = .gl33;

pub fn getBackendName() []const u8 {
    return switch (backend) {
        .gl33 => "GL 3.3",
        .gl44 => "GL 4.4 (persistent mapped)",
    };
}

fn detectBackend() Backend {
    const ver = gl.glGetString(gl.GL_VERSION) orelse return .gl33;
    if (ver[0] < '0' or ver[0] > '9') return .gl33;
    if (ver[2] < '0' or ver[2] > '9') return .gl33;
    const major = ver[0] - '0';
    const minor = ver[2] - '0';
    if (major > 4 or (major == 4 and minor >= 4)) return .gl44;
    return .gl33;
}

// ── Shared state ──

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
var sp_subpixel_order_loc: gl.GLint = -1;
var layer_tex_loc: gl.GLint = -1;
var sp_layer_tex_loc: gl.GLint = -1;

pub var subpixel_order: SubpixelOrder = .none;
pub var fill_rule: FillRule = .non_zero;

// Legacy alias used by snail.zig's setSubpixel convenience wrapper
pub fn subpixelEnabled() bool {
    return subpixel_order != .none;
}

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

var active_program: gl.GLuint = 0;
var frame_begun: bool = false;

// ── GL 4.4 persistent mapping state ──

const RING_SEGMENTS = 3;
const RING_TOTAL_BYTES = 12 * 1024 * 1024; // 12 MB (4 MB per segment)
const RING_SEGMENT_BYTES = RING_TOTAL_BYTES / RING_SEGMENTS;
const BYTES_PER_GLYPH = vertex.FLOATS_PER_VERTEX * vertex.VERTICES_PER_GLYPH * @sizeOf(f32);
const MAX_GLYPHS_PER_SEGMENT = RING_SEGMENT_BYTES / BYTES_PER_GLYPH;

var persistent_map: ?[*]u8 = null;
var ring_fences: [RING_SEGMENTS]gl.GLsync = .{null} ** RING_SEGMENTS;
var ring_segment: u32 = 0;

const MAX_ATLASES = 64;
const MAX_PAGES_PER_ATLAS = 256;

const AtlasSlot = struct {
    atlas: ?*const snail_mod.Atlas = null,
    base_layer: u32 = 0,
    capacity_pages: u32 = 0,
    uploaded_pages: u32 = 0,
    page_ptrs: [MAX_PAGES_PER_ATLAS]?*const snail_mod.AtlasPage = .{null} ** MAX_PAGES_PER_ATLAS,
};

var atlas_slots: [MAX_ATLASES]AtlasSlot = std.mem.zeroes([MAX_ATLASES]AtlasSlot);
var atlas_slot_count: usize = 0;
var allocated_curve_height: u32 = 0;
var allocated_band_height: u32 = 0;
var allocated_layer_count: u32 = 0;

// ── Init / Deinit ──

pub fn init() !void {
    // Compile shaders (shared between backends)
    program = try linkProgram(shaders.vertex_shader, shaders.fragment_shader);
    mvp_loc = gl.glGetUniformLocation(program, "u_mvp");
    viewport_loc = gl.glGetUniformLocation(program, "u_viewport");
    curve_tex_loc = gl.glGetUniformLocation(program, "u_curve_tex");
    band_tex_loc = gl.glGetUniformLocation(program, "u_band_tex");
    fill_rule_loc = gl.glGetUniformLocation(program, "u_fill_rule");
    layer_tex_loc = gl.glGetUniformLocation(program, "u_layer_tex");

    program_subpixel = try linkProgram(shaders.vertex_shader, shaders.fragment_shader_subpixel);
    sp_mvp_loc = gl.glGetUniformLocation(program_subpixel, "u_mvp");
    sp_viewport_loc = gl.glGetUniformLocation(program_subpixel, "u_viewport");
    sp_curve_tex_loc = gl.glGetUniformLocation(program_subpixel, "u_curve_tex");
    sp_band_tex_loc = gl.glGetUniformLocation(program_subpixel, "u_band_tex");
    sp_fill_rule_loc = gl.glGetUniformLocation(program_subpixel, "u_fill_rule");
    sp_subpixel_order_loc = gl.glGetUniformLocation(program_subpixel, "u_subpixel_order");
    sp_layer_tex_loc = gl.glGetUniformLocation(program_subpixel, "u_layer_tex");

    backend = detectBackend();

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

    if (program != 0) gl.glDeleteProgram(program);
    if (program_subpixel != 0) gl.glDeleteProgram(program_subpixel);
    if (vao != 0) gl.glDeleteVertexArrays(1, &vao);
    if (vbo != 0) gl.glDeleteBuffers(1, &vbo);
    if (ebo != 0) gl.glDeleteBuffers(1, &ebo);
    destroyTextureResources();
    resetAtlasUploadState();
}

// ── Texture array management ──

fn destroyTextureResources() void {
    if (curve_array != 0) gl.glDeleteTextures(1, &curve_array);
    if (band_array != 0) gl.glDeleteTextures(1, &band_array);
    if (layer_info_tex != 0) gl.glDeleteTextures(1, &layer_info_tex);
    curve_array = 0;
    band_array = 0;
    layer_info_tex = 0;
}

pub fn buildTextureArrays(atlases: []const *const snail_mod.Atlas, out_views: []snail_mod.AtlasView) void {
    std.debug.assert(atlases.len == out_views.len);

    if (atlases.len == 0) {
        destroyTextureResources();
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
        rebuildLayerInfoTexture(atlases);
        active_program = 0;
        frame_begun = false;
    }
}

fn rebuildTextureArrays(atlases: []const *const snail_mod.Atlas, out_views: []snail_mod.AtlasView) void {
    destroyTextureResources();
    resetAtlasUploadState();

    var max_curve_h: u32 = 1;
    var max_band_h: u32 = 1;
    var total_layers: u32 = 0;

    for (atlases, 0..) |atlas, i| {
        if (i >= MAX_ATLASES) return;
        const page_count: u32 = @intCast(atlas.pageCount());
        const capacity = atlasCapacity(page_count);
        const slot = &atlas_slots[i];
        slot.* = .{
            .atlas = atlas,
            .base_layer = total_layers,
            .capacity_pages = capacity,
            .uploaded_pages = page_count,
        };
        for (0..page_count) |page_index| {
            const page = atlas.page(@intCast(page_index));
            slot.page_ptrs[page_index] = page;
            if (page.curve_height > max_curve_h) max_curve_h = page.curve_height;
            if (page.band_height > max_band_h) max_band_h = page.band_height;
        }
        total_layers += capacity;
    }

    atlas_slot_count = atlases.len;
    allocated_curve_height = heightCapacity(max_curve_h);
    allocated_band_height = heightCapacity(max_band_h);
    allocated_layer_count = total_layers;

    if (atlases.len == 0) return;

    createTextureArrays(atlases[0], allocated_layer_count, allocated_curve_height, allocated_band_height);
    uploadAllPages(atlases);
    rebuildLayerInfoTexture(atlases);
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

    for (atlases, 0..) |atlas, i| {
        const slot = &atlas_slots[i];
        const old_pages = slot.uploaded_pages;
        const new_pages: u32 = @intCast(atlas.pageCount());
        for (old_pages..new_pages) |page_index| {
            slot.page_ptrs[page_index] = atlas.page(@intCast(page_index));
        }
        slot.atlas = atlas;
        slot.uploaded_pages = new_pages;
    }

    return true;
}

fn texturesReady() bool {
    return curve_array != 0 and band_array != 0 and atlas_slot_count > 0;
}

fn atlasSlotsCompatible(atlases: []const *const snail_mod.Atlas) bool {
    if (atlases.len != atlas_slot_count) return false;
    for (atlases, 0..) |atlas, i| {
        const slot = &atlas_slots[i];
        const page_count: u32 = @intCast(atlas.pageCount());
        if (page_count < slot.uploaded_pages or page_count > slot.capacity_pages) return false;
        for (0..slot.uploaded_pages) |page_index| {
            if (slot.page_ptrs[page_index] != atlas.page(@intCast(page_index))) return false;
        }
    }
    return true;
}

fn fillAtlasViews(atlases: []const *const snail_mod.Atlas, out_views: []snail_mod.AtlasView) void {
    for (atlases, 0..) |atlas, i| {
        out_views[i] = .{
            .atlas = atlas,
            .layer_base = @intCast(atlas_slots[i].base_layer),
        };
    }
}

fn resetAtlasUploadState() void {
    atlas_slot_count = 0;
    allocated_curve_height = 0;
    allocated_band_height = 0;
    allocated_layer_count = 0;
    for (&atlas_slots) |*slot| slot.* = .{};
}

fn roundUpPowerOfTwo(value: u32) u32 {
    if (value <= 1) return 1;
    var v = value - 1;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    return v + 1;
}

fn atlasCapacity(page_count: u32) u32 {
    return @max(4, roundUpPowerOfTwo(page_count + 1));
}

fn heightCapacity(height: u32) u32 {
    return roundUpPowerOfTwo(@max(height, 1));
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

fn uploadTexturePagesGl33(atlases: []const *const snail_mod.Atlas) void {
    uploadTexturePagesGl33WithStarts(atlases, null);
}

fn uploadTexturePagesGl44(atlases: []const *const snail_mod.Atlas) void {
    uploadTexturePagesGl44WithStarts(atlases, null);
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
    for (atlases) |a| {
        if (a.layer_info_data) |lid| {
            gl.glGenTextures(1, &layer_info_tex);
            gl.glActiveTexture(gl.GL_TEXTURE2);
            gl.glBindTexture(gl.GL_TEXTURE_2D, layer_info_tex);
            gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA32F, @intCast(a.layer_info_width), @intCast(a.layer_info_height), 0, gl.GL_RGBA, gl.GL_FLOAT, @ptrCast(lid.ptr));
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_NEAREST);
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_NEAREST);
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
            gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);
            break;
        }
    }
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

// ── Legacy API stubs ──

pub fn deleteTexture(tex: *gl.GLuint) void {
    if (tex.* != 0) {
        gl.glDeleteTextures(1, tex);
        tex.* = 0;
    }
}
pub fn createCurveTexture(_: []const u16, _: u32, _: u32) gl.GLuint {
    return 0;
}
pub fn createBandTexture(_: []const u16, _: u32, _: u32) gl.GLuint {
    return 0;
}
pub fn bindTextures(_: gl.GLuint, _: gl.GLuint) void {}

// ── Draw ──

pub fn drawText(vertices: []const f32, mvp: Mat4, viewport_w: f32, viewport_h: f32) void {
    // Ensure correct VAO is bound (may have been unbound by other renderers)
    gl.glBindVertexArray(vao);
    if (backend == .gl33) {
        gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);
    }

    gl.glDisable(gl.GL_DEPTH_TEST);
    gl.glEnable(gl.GL_BLEND);
    gl.glBlendFunc(gl.GL_ONE, gl.GL_ONE_MINUS_SRC_ALPHA);

    const using_sp = subpixel_order != .none;
    const prog = if (using_sp) program_subpixel else program;

    if (prog != active_program or !frame_begun) {
        gl.glUseProgram(prog);
        active_program = prog;

        if (backend == .gl44) {
            gl.glBindTextureUnit(0, curve_array);
            gl.glBindTextureUnit(1, band_array);
            if (layer_info_tex != 0) gl.glBindTextureUnit(2, layer_info_tex);
        } else {
            gl.glActiveTexture(gl.GL_TEXTURE0);
            gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, curve_array);
            gl.glActiveTexture(gl.GL_TEXTURE1);
            gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, band_array);
            if (layer_info_tex != 0) {
                gl.glActiveTexture(gl.GL_TEXTURE2);
                gl.glBindTexture(gl.GL_TEXTURE_2D, layer_info_tex);
            }
        }

        const u_ct = if (using_sp) sp_curve_tex_loc else curve_tex_loc;
        const u_bt = if (using_sp) sp_band_tex_loc else band_tex_loc;
        const u_lt = if (using_sp) sp_layer_tex_loc else layer_tex_loc;
        gl.glUniform1i(u_ct, 0);
        gl.glUniform1i(u_bt, 1);
        gl.glUniform1i(u_lt, 2);
        frame_begun = true;
    }

    const u_mvp = if (using_sp) sp_mvp_loc else mvp_loc;
    const u_vp = if (using_sp) sp_viewport_loc else viewport_loc;
    const u_fr = if (using_sp) sp_fill_rule_loc else fill_rule_loc;
    gl.glUniformMatrix4fv(u_mvp, 1, gl.GL_FALSE, &mvp.data);
    gl.glUniform2f(u_vp, viewport_w, viewport_h);
    gl.glUniform1i(u_fr, @intFromEnum(fill_rule));
    if (using_sp) gl.glUniform1i(sp_subpixel_order_loc, @intFromEnum(subpixel_order));

    const floats_per_glyph = vertex.FLOATS_PER_VERTEX * vertex.VERTICES_PER_GLYPH;
    const total_glyphs = vertices.len / floats_per_glyph;

    // Draw in chunks that fit within EBO / ring segment capacity
    var glyphs_drawn: usize = 0;
    while (glyphs_drawn < total_glyphs) {
        const chunk: usize = @min(total_glyphs - glyphs_drawn, MAX_GLYPHS_PER_SEGMENT);
        const float_offset = glyphs_drawn * floats_per_glyph;
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
        if (len > 0) std.debug.print("Shader link error:\n{s}\n", .{buf[0..@intCast(len)]});
        return error.ShaderLinkFailed;
    }
    return prog;
}
