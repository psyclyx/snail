//! C API for snail font rendering library.
//! All functions are extern "C" and use opaque pointers.

const std = @import("std");
const snail = @import("snail.zig");
const ttf = @import("font/ttf.zig");
const pipeline = @import("render/pipeline.zig");

// ── Allocator bridge ──

pub const SnailAllocFn = *const fn (ctx: ?*anyopaque, size: usize, alignment: usize) callconv(.c) ?[*]u8;
pub const SnailFreeFn = *const fn (ctx: ?*anyopaque, ptr: ?[*]u8, size: usize) callconv(.c) void;

pub const SnailAllocator = extern struct {
    alloc_fn: SnailAllocFn,
    free_fn: SnailFreeFn,
    ctx: ?*anyopaque,
};

fn toZigAllocator(ca: *const SnailAllocator) std.mem.Allocator {
    const S = struct {
        fn alloc(ctx_ptr: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
            const ca_inner: *const SnailAllocator = @ptrCast(@alignCast(ctx_ptr));
            return ca_inner.alloc_fn(ca_inner.ctx, len, alignment.toByteUnits());
        }
        fn free(ctx_ptr: *anyopaque, buf: []u8, _: std.mem.Alignment, _: usize) void {
            const ca_inner: *const SnailAllocator = @ptrCast(@alignCast(ctx_ptr));
            ca_inner.free_fn(ca_inner.ctx, buf.ptr, buf.len);
        }
        fn resize(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) bool {
            return false;
        }
        fn remap(_: *anyopaque, _: []u8, _: std.mem.Alignment, _: usize, _: usize) ?[*]u8 {
            return null;
        }
    };
    return .{
        .ptr = @constCast(@ptrCast(ca)),
        .vtable = &.{ .alloc = S.alloc, .resize = S.resize, .remap = S.remap, .free = S.free },
    };
}

// Default: libc malloc/free
fn libcAlloc(_: ?*anyopaque, size: usize, _: usize) callconv(.c) ?[*]u8 {
    const ptr = std.c.malloc(size) orelse return null;
    return @ptrCast(ptr);
}
fn libcFree(_: ?*anyopaque, ptr: ?[*]u8, _: usize) callconv(.c) void {
    if (ptr) |p| std.c.free(p);
}

const default_c_allocator = SnailAllocator{
    .alloc_fn = &libcAlloc,
    .free_fn = &libcFree,
    .ctx = null,
};

fn resolveAllocator(ca: ?*const SnailAllocator) std.mem.Allocator {
    if (ca) |a| return toZigAllocator(a);
    return toZigAllocator(&default_c_allocator);
}

// ── Error codes ──

pub const SNAIL_OK: c_int = 0;
pub const SNAIL_ERR_INVALID_FONT: c_int = -1;
pub const SNAIL_ERR_OUT_OF_MEMORY: c_int = -2;
pub const SNAIL_ERR_GL_FAILED: c_int = -3;

// ── Opaque types ──

const FontImpl = struct { inner: ttf.Font };
const AtlasImpl = struct { inner: snail.Atlas, allocator: std.mem.Allocator };

// ── Font ──

export fn snail_font_init(data: [*]const u8, len: usize, out: *?*FontImpl) c_int {
    const d = data[0..len];
    const font = ttf.Font.init(d) catch return SNAIL_ERR_INVALID_FONT;
    const alloc = std.heap.smp_allocator;
    const impl = alloc.create(FontImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.* = .{ .inner = font };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_font_deinit(font: ?*FontImpl) void {
    if (font) |f| std.heap.smp_allocator.destroy(f);
}

export fn snail_font_units_per_em(font: *const FontImpl) u16 {
    return font.inner.units_per_em;
}

export fn snail_font_glyph_index(font: *const FontImpl, codepoint: u32) u16 {
    return font.inner.glyphIndex(codepoint) catch 0;
}

export fn snail_font_get_kerning(font: *const FontImpl, left: u16, right: u16) i16 {
    return font.inner.getKerning(left, right) catch 0;
}

// ── Atlas ──

export fn snail_atlas_init(
    alloc_ptr: ?*const SnailAllocator,
    font: *const FontImpl,
    codepoints: [*]const u32,
    num_codepoints: usize,
    out: *?*AtlasImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const cp_slice = codepoints[0..num_codepoints];
    const wrapped = snail.Font{ .inner = font.inner };
    var atlas = snail.Atlas.init(allocator, &wrapped, cp_slice) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const impl = std.heap.smp_allocator.create(AtlasImpl) catch {
        atlas.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = atlas, .allocator = allocator };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_atlas_add_codepoints(
    atlas: *AtlasImpl,
    codepoints: [*]const u32,
    num_codepoints: usize,
    added: *bool,
) c_int {
    const cp_slice = codepoints[0..num_codepoints];
    added.* = atlas.inner.addCodepoints(cp_slice) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_atlas_deinit(atlas: ?*AtlasImpl) void {
    if (atlas) |a| {
        a.inner.deinit();
        std.heap.smp_allocator.destroy(a);
    }
}

// ── Renderer ──

export fn snail_renderer_init() c_int {
    pipeline.init() catch return SNAIL_ERR_GL_FAILED;
    return SNAIL_OK;
}

export fn snail_renderer_deinit() void {
    pipeline.deinit();
}

export fn snail_renderer_upload_atlas(atlas: *const AtlasImpl) void {
    pipeline.uploadCurveTexture(atlas.inner.curve_data, atlas.inner.curve_width, atlas.inner.curve_height);
    pipeline.uploadBandTexture(atlas.inner.band_data, atlas.inner.band_width, atlas.inner.band_height);
}

export fn snail_renderer_set_subpixel(enabled: bool) void {
    pipeline.subpixel_enabled = enabled;
}

export fn snail_renderer_set_fill_rule(rule: c_int) void {
    pipeline.fill_rule = @enumFromInt(rule);
}

export fn snail_renderer_draw(vertices: [*]const f32, num_floats: usize, mvp: [*]const f32, viewport_w: f32, viewport_h: f32) void {
    const mat = snail.Mat4{ .data = mvp[0..16].* };
    pipeline.drawText(vertices[0..num_floats], mat, viewport_w, viewport_h);
}

// ── Batch ──

export fn snail_batch_add_string(
    buf: [*]f32,
    buf_capacity: usize,
    buf_len: *usize,
    atlas: *const AtlasImpl,
    font: *const FontImpl,
    text: [*]const u8,
    text_len: usize,
    x: f32,
    y: f32,
    font_size: f32,
    color: [*]const f32,
) f32 {
    var batch = snail.Batch.init(buf[buf_len.*..buf_capacity]);
    const wrapped_font = snail.Font{ .inner = font.inner };
    const advance = batch.addString(&atlas.inner, &wrapped_font, text[0..text_len], x, y, font_size, color[0..4].*);
    buf_len.* += batch.len;
    return advance;
}

export fn snail_batch_add_shaped(
    buf: [*]f32,
    buf_capacity: usize,
    buf_len: *usize,
    atlas: *const AtlasImpl,
    glyph_ids: [*]const u16,
    x_offsets: [*]const f32,
    y_offsets: [*]const f32,
    num_glyphs: usize,
    x: f32,
    y: f32,
    font_size: f32,
    color: [*]const f32,
) usize {
    var batch = snail.Batch.init(buf[buf_len.*..buf_capacity]);
    var shaped_buf: [1024]snail.Batch.ShapedGlyph = undefined;
    const count = @min(num_glyphs, shaped_buf.len);
    for (0..count) |i| {
        shaped_buf[i] = .{
            .glyph_id = glyph_ids[i],
            .x_offset = x_offsets[i],
            .y_offset = y_offsets[i],
        };
    }
    const added = batch.addShaped(&atlas.inner, shaped_buf[0..count], x, y, font_size, color[0..4].*);
    buf_len.* += batch.len;
    return added;
}

export fn snail_batch_add_string_wrapped(
    buf: [*]f32,
    buf_capacity: usize,
    buf_len: *usize,
    atlas: *const AtlasImpl,
    font: *const FontImpl,
    text: [*]const u8,
    text_len: usize,
    x: f32,
    y: f32,
    font_size: f32,
    max_width: f32,
    line_height: f32,
    color: [*]const f32,
) f32 {
    var batch = snail.Batch.init(buf[buf_len.*..buf_capacity]);
    const wrapped_font = snail.Font{ .inner = font.inner };
    const height = batch.addStringWrapped(&atlas.inner, &wrapped_font, text[0..text_len], x, y, font_size, max_width, line_height, color[0..4].*);
    buf_len.* += batch.len;
    return height;
}

// ── HarfBuzz ──

const build_options = @import("build_options");

export fn snail_harfbuzz_available() bool {
    return build_options.enable_harfbuzz;
}

export fn snail_atlas_add_glyphs_for_text(
    atlas: *AtlasImpl,
    text: [*]const u8,
    text_len: usize,
    added: *bool,
) c_int {
    added.* = atlas.inner.addGlyphsForText(text[0..text_len]) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

// ── Constants ──

export fn snail_floats_per_glyph() usize {
    return snail.FLOATS_PER_GLYPH;
}
