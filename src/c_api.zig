//! C API for snail font rendering library.
//! All functions are extern "C" and use opaque pointers.

const std = @import("std");
const snail = @import("snail.zig");
const ttf = @import("font/ttf.zig");

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
        .ptr = @ptrCast(@constCast(ca)),
        .vtable = &.{ .alloc = S.alloc, .resize = S.resize, .remap = S.remap, .free = S.free },
    };
}

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

// ── C-compatible struct types ──

pub const SnailBBox = extern struct {
    min_x: f32,
    min_y: f32,
    max_x: f32,
    max_y: f32,
};

pub const SnailGlyphMetrics = extern struct {
    advance_width: u16,
    lsb: i16,
    bbox: SnailBBox,
};

pub const SnailLineMetrics = extern struct {
    ascent: i16,
    descent: i16,
    line_gap: i16,
};

pub const SnailRect = extern struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

pub const SnailTransform2D = extern struct {
    xx: f32 = 1,
    xy: f32 = 0,
    tx: f32 = 0,
    yx: f32 = 0,
    yy: f32 = 1,
    ty: f32 = 0,
};

pub const SnailGlyphPlacement = extern struct {
    glyph_id: u16,
    x_offset: f32,
    y_offset: f32,
    x_advance: f32,
    y_advance: f32,
    source_start: u32,
    source_end: u32,
};

pub const SnailLinearGradient = extern struct {
    start_x: f32,
    start_y: f32,
    end_x: f32,
    end_y: f32,
    start_color: [4]f32,
    end_color: [4]f32,
    extend: c_int = 0,
};

pub const SnailRadialGradient = extern struct {
    center_x: f32,
    center_y: f32,
    radius: f32,
    inner_color: [4]f32,
    outer_color: [4]f32,
    extend: c_int = 0,
};

pub const SNAIL_PAINT_SOLID: c_int = 0;
pub const SNAIL_PAINT_LINEAR: c_int = 1;
pub const SNAIL_PAINT_RADIAL: c_int = 2;

pub const SnailFillStyle = extern struct {
    color: [4]f32 = .{ 0, 0, 0, 1 },
    paint_kind: c_int = -1, // -1 = use color, 0 = solid, 1 = linear, 2 = radial
    paint_solid: [4]f32 = .{ 0, 0, 0, 0 },
    paint_linear: SnailLinearGradient = std.mem.zeroes(SnailLinearGradient),
    paint_radial: SnailRadialGradient = std.mem.zeroes(SnailRadialGradient),
};

pub const SNAIL_CAP_BUTT: c_int = 0;
pub const SNAIL_CAP_SQUARE: c_int = 1;
pub const SNAIL_CAP_ROUND: c_int = 2;

pub const SNAIL_JOIN_MITER: c_int = 0;
pub const SNAIL_JOIN_BEVEL: c_int = 1;
pub const SNAIL_JOIN_ROUND: c_int = 2;

pub const SNAIL_STROKE_CENTER: c_int = 0;
pub const SNAIL_STROKE_INSIDE: c_int = 1;

pub const SnailStrokeStyle = extern struct {
    color: [4]f32 = .{ 0, 0, 0, 1 },
    paint_kind: c_int = -1,
    paint_solid: [4]f32 = .{ 0, 0, 0, 0 },
    paint_linear: SnailLinearGradient = std.mem.zeroes(SnailLinearGradient),
    paint_radial: SnailRadialGradient = std.mem.zeroes(SnailRadialGradient),
    width: f32 = 1,
    cap: c_int = SNAIL_CAP_BUTT,
    join: c_int = SNAIL_JOIN_MITER,
    miter_limit: f32 = 4,
    placement: c_int = SNAIL_STROKE_CENTER,
};

pub const SnailSpriteUvRect = extern struct {
    u0: f32 = 0,
    v0: f32 = 0,
    u1: f32 = 1,
    v1: f32 = 1,
};

pub const SnailSpriteAnchor = extern struct {
    x: f32 = 0.5,
    y: f32 = 0.5,
};

// ── Opaque types ──

const FontImpl = struct { inner: ttf.Font };
const AtlasImpl = struct { inner: snail.Atlas, allocator: std.mem.Allocator };
const ImageImpl = struct { inner: snail.Image };
const PathImpl = struct { inner: snail.Path };
const PathPictureBuilderImpl = struct { inner: snail.PathPictureBuilder };
const PathPictureImpl = struct { inner: snail.PathPicture };

// Shaped run wrapper: owns the allocated glyphs slice.
const ShapedRunImpl = struct {
    glyphs: []const snail.GlyphPlacement,
    advance_x: f32,
    advance_y: f32,
    allocator: std.mem.Allocator,
};

// ── Conversion helpers ──

fn wrapBBox(bbox: snail.BBox) SnailBBox {
    return .{ .min_x = bbox.min.x, .min_y = bbox.min.y, .max_x = bbox.max.x, .max_y = bbox.max.y };
}

fn wrapAtlas(atlas: snail.Atlas, allocator: std.mem.Allocator, out: *?*AtlasImpl) c_int {
    const impl = std.heap.smp_allocator.create(AtlasImpl) catch {
        var doomed = atlas;
        doomed.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = atlas, .allocator = allocator };
    out.* = impl;
    return SNAIL_OK;
}

fn toRect(r: SnailRect) snail.Rect {
    return .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
}

fn toTransform(t: SnailTransform2D) snail.Transform2D {
    return .{ .xx = t.xx, .xy = t.xy, .tx = t.tx, .yx = t.yx, .yy = t.yy, .ty = t.ty };
}

fn toPaint(kind: c_int, solid: [4]f32, linear: SnailLinearGradient, radial: SnailRadialGradient) ?snail.Paint {
    return switch (kind) {
        SNAIL_PAINT_SOLID => .{ .solid = solid },
        SNAIL_PAINT_LINEAR => .{ .linear_gradient = .{
            .start = .{ .x = linear.start_x, .y = linear.start_y },
            .end = .{ .x = linear.end_x, .y = linear.end_y },
            .start_color = linear.start_color,
            .end_color = linear.end_color,
            .extend = @enumFromInt(@as(u8, @intCast(linear.extend))),
        } },
        SNAIL_PAINT_RADIAL => .{ .radial_gradient = .{
            .center = .{ .x = radial.center_x, .y = radial.center_y },
            .radius = radial.radius,
            .inner_color = radial.inner_color,
            .outer_color = radial.outer_color,
            .extend = @enumFromInt(@as(u8, @intCast(radial.extend))),
        } },
        else => null,
    };
}

fn toFillStyle(s: SnailFillStyle) snail.FillStyle {
    return .{ .color = s.color, .paint = toPaint(s.paint_kind, s.paint_solid, s.paint_linear, s.paint_radial) };
}

fn toStrokeStyle(s: SnailStrokeStyle) snail.StrokeStyle {
    return .{
        .color = s.color,
        .paint = toPaint(s.paint_kind, s.paint_solid, s.paint_linear, s.paint_radial),
        .width = s.width,
        .cap = @enumFromInt(@as(u2, @intCast(s.cap))),
        .join = @enumFromInt(@as(u2, @intCast(s.join))),
        .miter_limit = s.miter_limit,
        .placement = @enumFromInt(@as(u1, @intCast(s.placement))),
    };
}

fn toOptFill(ptr: ?*const SnailFillStyle) ?snail.FillStyle {
    if (ptr) |s| return toFillStyle(s.*);
    return null;
}

fn toOptStroke(ptr: ?*const SnailStrokeStyle) ?snail.StrokeStyle {
    if (ptr) |s| return toStrokeStyle(s.*);
    return null;
}

// ── Font ──

export fn snail_font_init(data: [*]const u8, len: usize, out: *?*FontImpl) c_int {
    const font = ttf.Font.init(data[0..len]) catch return SNAIL_ERR_INVALID_FONT;
    const impl = std.heap.smp_allocator.create(FontImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
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

export fn snail_font_glyph_metrics(font: *const FontImpl, glyph_id: u16, out: *SnailGlyphMetrics) c_int {
    const m = font.inner.glyphMetrics(glyph_id) catch return SNAIL_ERR_INVALID_FONT;
    out.* = .{ .advance_width = m.advance_width, .lsb = m.lsb, .bbox = wrapBBox(m.bbox) };
    return SNAIL_OK;
}

export fn snail_font_line_metrics(font: *const FontImpl, out: *SnailLineMetrics) c_int {
    const m = font.inner.lineMetrics() catch return SNAIL_ERR_INVALID_FONT;
    out.* = .{ .ascent = m.ascent, .descent = m.descent, .line_gap = m.line_gap };
    return SNAIL_OK;
}

export fn snail_font_advance_width(font: *const FontImpl, glyph_id: u16, out: *i16) c_int {
    out.* = font.inner.advanceWidth(glyph_id) catch return SNAIL_ERR_INVALID_FONT;
    return SNAIL_OK;
}

export fn snail_font_bbox(font: *const FontImpl, glyph_id: u16, out: *SnailBBox) c_int {
    out.* = wrapBBox(font.inner.bbox(glyph_id) catch return SNAIL_ERR_INVALID_FONT);
    return SNAIL_OK;
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
    const wrapped = snail.Font{ .inner = font.inner };
    const atlas = snail.Atlas.init(allocator, &wrapped, codepoints[0..num_codepoints]) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return wrapAtlas(atlas, allocator, out);
}

export fn snail_atlas_init_ascii(
    alloc_ptr: ?*const SnailAllocator,
    font: *const FontImpl,
    out: *?*AtlasImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const wrapped = snail.Font{ .inner = font.inner };
    const atlas = snail.Atlas.initAscii(allocator, &wrapped, &snail.ASCII_PRINTABLE) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return wrapAtlas(atlas, allocator, out);
}

export fn snail_atlas_extend_codepoints(
    atlas: *const AtlasImpl,
    codepoints: [*]const u32,
    num_codepoints: usize,
    out: *?*AtlasImpl,
) c_int {
    const next = atlas.inner.extendCodepoints(codepoints[0..num_codepoints]) catch return SNAIL_ERR_OUT_OF_MEMORY;
    if (next) |new_atlas| return wrapAtlas(new_atlas, atlas.allocator, out);
    out.* = null;
    return SNAIL_OK;
}

export fn snail_atlas_extend_glyph_ids(
    atlas: *const AtlasImpl,
    glyph_ids: [*]const u16,
    num_glyph_ids: usize,
    out: *?*AtlasImpl,
) c_int {
    const next = atlas.inner.extendGlyphIds(glyph_ids[0..num_glyph_ids]) catch return SNAIL_ERR_OUT_OF_MEMORY;
    if (next) |new_atlas| return wrapAtlas(new_atlas, atlas.allocator, out);
    out.* = null;
    return SNAIL_OK;
}

export fn snail_atlas_extend_text(atlas: *const AtlasImpl, text: [*]const u8, text_len: usize, out: *?*AtlasImpl) c_int {
    const next = atlas.inner.extendText(text[0..text_len]) catch return SNAIL_ERR_OUT_OF_MEMORY;
    if (next) |new_atlas| return wrapAtlas(new_atlas, atlas.allocator, out);
    out.* = null;
    return SNAIL_OK;
}

export fn snail_atlas_extend_run(atlas: *const AtlasImpl, run: *const ShapedRunImpl, out: *?*AtlasImpl) c_int {
    const zig_run = snail.ShapedRun{ .glyphs = run.glyphs, .advance_x = run.advance_x, .advance_y = run.advance_y };
    const next = atlas.inner.extendRun(&zig_run) catch return SNAIL_ERR_OUT_OF_MEMORY;
    if (next) |new_atlas| return wrapAtlas(new_atlas, atlas.allocator, out);
    out.* = null;
    return SNAIL_OK;
}

export fn snail_atlas_compact(atlas: *const AtlasImpl, out: *?*AtlasImpl) c_int {
    const compacted = atlas.inner.compact() catch return SNAIL_ERR_OUT_OF_MEMORY;
    return wrapAtlas(compacted, atlas.allocator, out);
}

export fn snail_atlas_add_codepoints(atlas: *AtlasImpl, codepoints: [*]const u32, num_codepoints: usize, added: *bool) c_int {
    const next = atlas.inner.extendCodepoints(codepoints[0..num_codepoints]) catch return SNAIL_ERR_OUT_OF_MEMORY;
    if (next) |new_atlas| {
        atlas.inner.deinit();
        atlas.inner = new_atlas;
        added.* = true;
    } else {
        added.* = false;
    }
    return SNAIL_OK;
}

export fn snail_atlas_deinit(atlas: ?*AtlasImpl) void {
    if (atlas) |a| {
        a.inner.deinit();
        std.heap.smp_allocator.destroy(a);
    }
}

export fn snail_atlas_page_count(atlas: *const AtlasImpl) usize {
    return atlas.inner.pageCount();
}

export fn snail_atlas_texture_byte_len(atlas: *const AtlasImpl) usize {
    return atlas.inner.textureByteLen();
}

// ── Shaping ──

export fn snail_atlas_shape_utf8(
    atlas: *const AtlasImpl,
    font: *const FontImpl,
    text: [*]const u8,
    text_len: usize,
    font_size: f32,
    out: *?*ShapedRunImpl,
) c_int {
    const wrapped = snail.Font{ .inner = font.inner };
    const run = atlas.inner.shapeUtf8(&wrapped, text[0..text_len], font_size, atlas.allocator) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const impl = std.heap.smp_allocator.create(ShapedRunImpl) catch {
        if (run.glyphs.len > 0) atlas.allocator.free(run.glyphs);
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .glyphs = run.glyphs, .advance_x = run.advance_x, .advance_y = run.advance_y, .allocator = atlas.allocator };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_shaped_run_glyph_count(run: *const ShapedRunImpl) usize {
    return run.glyphs.len;
}

export fn snail_shaped_run_glyph(run: *const ShapedRunImpl, index: usize, out: *SnailGlyphPlacement) bool {
    if (index >= run.glyphs.len) return false;
    const g = run.glyphs[index];
    out.* = .{
        .glyph_id = g.glyph_id,
        .x_offset = g.x_offset,
        .y_offset = g.y_offset,
        .x_advance = g.x_advance,
        .y_advance = g.y_advance,
        .source_start = g.source_start,
        .source_end = g.source_end,
    };
    return true;
}

export fn snail_shaped_run_copy_glyphs(run: *const ShapedRunImpl, out: [*]SnailGlyphPlacement, capacity: usize) usize {
    const count = @min(run.glyphs.len, capacity);
    for (run.glyphs[0..count], 0..) |g, i| {
        out[i] = .{
            .glyph_id = g.glyph_id,
            .x_offset = g.x_offset,
            .y_offset = g.y_offset,
            .x_advance = g.x_advance,
            .y_advance = g.y_advance,
            .source_start = g.source_start,
            .source_end = g.source_end,
        };
    }
    return count;
}

export fn snail_shaped_run_advance_x(run: *const ShapedRunImpl) f32 {
    return run.advance_x;
}

export fn snail_shaped_run_advance_y(run: *const ShapedRunImpl) f32 {
    return run.advance_y;
}

export fn snail_shaped_run_deinit(run: ?*ShapedRunImpl) void {
    if (run) |r| {
        if (r.glyphs.len > 0) r.allocator.free(r.glyphs);
        std.heap.smp_allocator.destroy(r);
    }
}

export fn snail_atlas_collect_missing_glyph_ids(
    atlas: *const AtlasImpl,
    run: *const ShapedRunImpl,
    out_ids: [*]u16,
    out_capacity: usize,
) usize {
    const zig_run = snail.ShapedRun{ .glyphs = run.glyphs, .advance_x = run.advance_x, .advance_y = run.advance_y };
    return atlas.inner.collectMissingGlyphIds(&zig_run, out_ids[0..out_capacity]);
}

// ── Image ──

export fn snail_image_init_rgba8(
    alloc_ptr: ?*const SnailAllocator,
    width: u32,
    height: u32,
    pixels: [*]const u8,
    out: *?*ImageImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const img = snail.Image.initRgba8(allocator, width, height, pixels[0 .. width * height * 4]) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const impl = std.heap.smp_allocator.create(ImageImpl) catch {
        var doomed = img;
        @constCast(&doomed).deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = img };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_image_deinit(image: ?*ImageImpl) void {
    if (image) |img| {
        img.inner.deinit();
        std.heap.smp_allocator.destroy(img);
    }
}

export fn snail_image_width(image: *const ImageImpl) u32 {
    return image.inner.width;
}

export fn snail_image_height(image: *const ImageImpl) u32 {
    return image.inner.height;
}

// ── Renderer ──

var c_renderer: ?snail.Renderer = null;

fn getRenderer() *snail.Renderer {
    return &(c_renderer orelse @panic("snail_renderer_init not called"));
}

export fn snail_renderer_init() c_int {
    c_renderer = snail.Renderer.init() catch return SNAIL_ERR_GL_FAILED;
    return SNAIL_OK;
}

export fn snail_renderer_deinit() void {
    if (c_renderer) |*r| r.deinit();
    c_renderer = null;
}

export fn snail_renderer_upload_atlas(atlas: *AtlasImpl) void {
    _ = getRenderer().uploadAtlas(&atlas.inner);
}

export fn snail_renderer_upload_image(image: *ImageImpl) void {
    _ = getRenderer().uploadImage(&image.inner);
}

export fn snail_renderer_upload_path_picture(picture: *PathPictureImpl) void {
    _ = getRenderer().uploadPathPicture(&picture.inner);
}

export fn snail_renderer_begin_frame() void {
    getRenderer().beginFrame();
}

export fn snail_renderer_set_subpixel_order(order: c_int) void {
    getRenderer().setSubpixelOrder(@enumFromInt(order));
}

export fn snail_renderer_set_subpixel_mode(mode: c_int) void {
    getRenderer().setSubpixelMode(@enumFromInt(mode));
}

export fn snail_renderer_set_subpixel_backdrop(rgba_or_null: ?[*]const f32) void {
    getRenderer().setSubpixelBackdrop(if (rgba_or_null) |rgba| .{ rgba[0], rgba[1], rgba[2], rgba[3] } else null);
}

export fn snail_renderer_set_subpixel(enabled: bool) void {
    getRenderer().setSubpixel(enabled);
}

export fn snail_renderer_set_fill_rule(rule: c_int) void {
    getRenderer().setFillRule(@enumFromInt(rule));
}

export fn snail_renderer_subpixel_order() c_int {
    return @intFromEnum(getRenderer().subpixelOrder());
}

export fn snail_renderer_subpixel_mode() c_int {
    return @intFromEnum(getRenderer().subpixelMode());
}

export fn snail_renderer_fill_rule() c_int {
    return @intFromEnum(getRenderer().fillRule());
}

export fn snail_renderer_backend_name() [*:0]const u8 {
    return @ptrCast(getRenderer().backendName().ptr);
}

export fn snail_renderer_draw_text(vertices: [*]const f32, num_floats: usize, mvp: [*]const f32, viewport_w: f32, viewport_h: f32) void {
    const mat = snail.Mat4{ .data = mvp[0..16].* };
    getRenderer().drawText(vertices[0..num_floats], mat, viewport_w, viewport_h);
}

export fn snail_renderer_draw_paths(vertices: [*]const f32, num_floats: usize, mvp: [*]const f32, viewport_w: f32, viewport_h: f32) void {
    const mat = snail.Mat4{ .data = mvp[0..16].* };
    getRenderer().drawPaths(vertices[0..num_floats], mat, viewport_w, viewport_h);
}

export fn snail_renderer_draw_sprites(vertices: [*]const f32, num_floats: usize, mvp: [*]const f32, viewport_w: f32, viewport_h: f32) void {
    const mat = snail.Mat4{ .data = mvp[0..16].* };
    getRenderer().drawSprites(vertices[0..num_floats], mat, viewport_w, viewport_h);
}

// ── TextBatch ──

export fn snail_batch_add_text(
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
    var batch = snail.TextBatch.init(buf[buf_len.*..buf_capacity]);
    const wrapped_font = snail.Font{ .inner = font.inner };
    const view = snail.AtlasHandle{ .atlas = &atlas.inner, .layer_base = 0 };
    const advance = batch.addText(&view, &wrapped_font, text[0..text_len], x, y, font_size, color[0..4].*);
    buf_len.* += batch.len;
    return advance;
}

export fn snail_batch_add_run(
    buf: [*]f32,
    buf_capacity: usize,
    buf_len: *usize,
    atlas: *const AtlasImpl,
    run: *const ShapedRunImpl,
    x: f32,
    y: f32,
    font_size: f32,
    color: [*]const f32,
) usize {
    var batch = snail.TextBatch.init(buf[buf_len.*..buf_capacity]);
    const view = snail.AtlasHandle{ .atlas = &atlas.inner, .layer_base = 0 };
    const zig_run = snail.ShapedRun{ .glyphs = run.glyphs, .advance_x = run.advance_x, .advance_y = run.advance_y };
    const added = batch.addRun(&view, &zig_run, x, y, font_size, color[0..4].*);
    buf_len.* += batch.len;
    return added;
}

export fn snail_batch_glyph_count(buf_len: usize) usize {
    return buf_len / snail.TEXT_FLOATS_PER_GLYPH;
}

// ── SpriteBatch ──

export fn snail_sprite_batch_add_sprite(
    buf: [*]f32,
    buf_capacity: usize,
    buf_len: *usize,
    image: *const ImageImpl,
    pos_x: f32,
    pos_y: f32,
    size_x: f32,
    size_y: f32,
    tint: [*]const f32,
) bool {
    var batch = snail.SpriteBatch.init(buf[buf_len.*..buf_capacity]);
    const view = snail.ImageHandle{ .image = &image.inner };
    const ok = batch.addSprite(view, .{ .x = pos_x, .y = pos_y }, .{ .x = size_x, .y = size_y }, tint[0..4].*);
    buf_len.* += batch.len;
    return ok;
}

export fn snail_sprite_batch_add_sprite_rect(
    buf: [*]f32,
    buf_capacity: usize,
    buf_len: *usize,
    image: *const ImageImpl,
    rect: SnailRect,
    tint: [*]const f32,
    uv: SnailSpriteUvRect,
    filter: c_int,
) bool {
    var batch = snail.SpriteBatch.init(buf[buf_len.*..buf_capacity]);
    const view = snail.ImageHandle{ .image = &image.inner };
    const ok = batch.addSpriteRect(view, toRect(rect), tint[0..4].*, .{
        .u0 = uv.u0,
        .v0 = uv.v0,
        .u1 = uv.u1,
        .v1 = uv.v1,
    }, @enumFromInt(@as(u1, @intCast(filter))));
    buf_len.* += batch.len;
    return ok;
}

export fn snail_sprite_batch_add_sprite_transformed(
    buf: [*]f32,
    buf_capacity: usize,
    buf_len: *usize,
    image: *const ImageImpl,
    size_x: f32,
    size_y: f32,
    tint: [*]const f32,
    uv: SnailSpriteUvRect,
    filter: c_int,
    anchor: SnailSpriteAnchor,
    transform: SnailTransform2D,
) bool {
    var batch = snail.SpriteBatch.init(buf[buf_len.*..buf_capacity]);
    const view = snail.ImageHandle{ .image = &image.inner };
    const ok = batch.addSpriteTransformed(view, .{ .x = size_x, .y = size_y }, tint[0..4].*, .{
        .u0 = uv.u0,
        .v0 = uv.v0,
        .u1 = uv.u1,
        .v1 = uv.v1,
    }, @enumFromInt(@as(u1, @intCast(filter))), .{ .x = anchor.x, .y = anchor.y }, toTransform(transform));
    buf_len.* += batch.len;
    return ok;
}

// ── Path ──

export fn snail_path_init(alloc_ptr: ?*const SnailAllocator, out: *?*PathImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const impl = std.heap.smp_allocator.create(PathImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.* = .{ .inner = snail.Path.init(allocator) };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_path_deinit(path: ?*PathImpl) void {
    if (path) |p| {
        p.inner.deinit();
        std.heap.smp_allocator.destroy(p);
    }
}

export fn snail_path_reset(path: *PathImpl) void {
    path.inner.reset();
}

export fn snail_path_is_empty(path: *const PathImpl) bool {
    return path.inner.isEmpty();
}

export fn snail_path_bounds(path: *const PathImpl, out: *SnailBBox) bool {
    if (path.inner.bounds()) |b| {
        out.* = wrapBBox(b);
        return true;
    }
    return false;
}

export fn snail_path_move_to(path: *PathImpl, x: f32, y: f32) c_int {
    path.inner.moveTo(.{ .x = x, .y = y }) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_line_to(path: *PathImpl, x: f32, y: f32) c_int {
    path.inner.lineTo(.{ .x = x, .y = y }) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_quad_to(path: *PathImpl, cx: f32, cy: f32, x: f32, y: f32) c_int {
    path.inner.quadTo(.{ .x = cx, .y = cy }, .{ .x = x, .y = y }) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_cubic_to(path: *PathImpl, c1x: f32, c1y: f32, c2x: f32, c2y: f32, x: f32, y: f32) c_int {
    path.inner.cubicTo(.{ .x = c1x, .y = c1y }, .{ .x = c2x, .y = c2y }, .{ .x = x, .y = y }) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_close(path: *PathImpl) c_int {
    path.inner.close() catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_add_rect(path: *PathImpl, rect: SnailRect) c_int {
    path.inner.addRect(toRect(rect)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_add_rounded_rect(path: *PathImpl, rect: SnailRect, corner_radius: f32) c_int {
    path.inner.addRoundedRect(toRect(rect), corner_radius) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_add_ellipse(path: *PathImpl, rect: SnailRect) c_int {
    path.inner.addEllipse(toRect(rect)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

// ── PathPictureBuilder ──

export fn snail_path_picture_builder_init(alloc_ptr: ?*const SnailAllocator, out: *?*PathPictureBuilderImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const impl = std.heap.smp_allocator.create(PathPictureBuilderImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.* = .{ .inner = snail.PathPictureBuilder.init(allocator) };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_path_picture_builder_deinit(builder: ?*PathPictureBuilderImpl) void {
    if (builder) |b| {
        b.inner.deinit();
        std.heap.smp_allocator.destroy(b);
    }
}

export fn snail_path_picture_builder_add_path(
    builder: *PathPictureBuilderImpl,
    path: *const PathImpl,
    fill: ?*const SnailFillStyle,
    stroke: ?*const SnailStrokeStyle,
    transform: SnailTransform2D,
) c_int {
    builder.inner.addPath(&path.inner, toOptFill(fill), toOptStroke(stroke), toTransform(transform)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_picture_builder_add_filled_path(
    builder: *PathPictureBuilderImpl,
    path: *const PathImpl,
    fill: SnailFillStyle,
    transform: SnailTransform2D,
) c_int {
    builder.inner.addFilledPath(&path.inner, toFillStyle(fill), toTransform(transform)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_picture_builder_add_stroked_path(
    builder: *PathPictureBuilderImpl,
    path: *const PathImpl,
    stroke: SnailStrokeStyle,
    transform: SnailTransform2D,
) c_int {
    builder.inner.addStrokedPath(&path.inner, toStrokeStyle(stroke), toTransform(transform)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_picture_builder_add_rect(builder: *PathPictureBuilderImpl, rect: SnailRect, fill: ?*const SnailFillStyle, stroke: ?*const SnailStrokeStyle, transform: SnailTransform2D) c_int {
    builder.inner.addRect(toRect(rect), toOptFill(fill), toOptStroke(stroke), toTransform(transform)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_picture_builder_add_rounded_rect(builder: *PathPictureBuilderImpl, rect: SnailRect, fill: ?*const SnailFillStyle, stroke: ?*const SnailStrokeStyle, corner_radius: f32, transform: SnailTransform2D) c_int {
    builder.inner.addRoundedRect(toRect(rect), toOptFill(fill), toOptStroke(stroke), corner_radius, toTransform(transform)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_picture_builder_add_ellipse(builder: *PathPictureBuilderImpl, rect: SnailRect, fill: ?*const SnailFillStyle, stroke: ?*const SnailStrokeStyle, transform: SnailTransform2D) c_int {
    builder.inner.addEllipse(toRect(rect), toOptFill(fill), toOptStroke(stroke), toTransform(transform)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_path_picture_builder_freeze(builder: *const PathPictureBuilderImpl, alloc_ptr: ?*const SnailAllocator, out: *?*PathPictureImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    var picture = builder.inner.freeze(allocator) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const impl = std.heap.smp_allocator.create(PathPictureImpl) catch {
        picture.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = picture };
    out.* = impl;
    return SNAIL_OK;
}

// ── PathPicture ──

export fn snail_path_picture_deinit(picture: ?*PathPictureImpl) void {
    if (picture) |p| {
        p.inner.deinit();
        std.heap.smp_allocator.destroy(p);
    }
}

export fn snail_path_picture_shape_count(picture: *const PathPictureImpl) usize {
    return picture.inner.shapeCount();
}

// ── PathBatch ──

export fn snail_path_batch_add_picture(
    buf: [*]f32,
    buf_capacity: usize,
    buf_len: *usize,
    picture: *const PathPictureImpl,
) usize {
    var batch = snail.PathBatch.init(buf[buf_len.*..buf_capacity]);
    const view = snail.AtlasHandle{ .atlas = &picture.inner.atlas, .layer_base = 0 };
    const count = batch.addPicture(&view, &picture.inner);
    buf_len.* += batch.len;
    return count;
}

export fn snail_path_batch_add_picture_transformed(
    buf: [*]f32,
    buf_capacity: usize,
    buf_len: *usize,
    picture: *const PathPictureImpl,
    transform: SnailTransform2D,
) usize {
    var batch = snail.PathBatch.init(buf[buf_len.*..buf_capacity]);
    const view = snail.AtlasHandle{ .atlas = &picture.inner.atlas, .layer_base = 0 };
    const count = batch.addPictureTransformed(&view, &picture.inner, toTransform(transform));
    buf_len.* += batch.len;
    return count;
}

// ── HarfBuzz ──

const build_options = @import("build_options");

export fn snail_harfbuzz_available() bool {
    return build_options.enable_harfbuzz;
}

export fn snail_atlas_add_glyphs_for_text(atlas: *AtlasImpl, text: [*]const u8, text_len: usize, added: *bool) c_int {
    const next = atlas.inner.extendGlyphsForText(text[0..text_len]) catch return SNAIL_ERR_OUT_OF_MEMORY;
    if (next) |new_atlas| {
        atlas.inner.deinit();
        atlas.inner = new_atlas;
        added.* = true;
    } else {
        added.* = false;
    }
    return SNAIL_OK;
}

export fn snail_atlas_extend_glyphs_for_text(atlas: *const AtlasImpl, text: [*]const u8, text_len: usize, out: *?*AtlasImpl) c_int {
    const next = atlas.inner.extendGlyphsForText(text[0..text_len]) catch return SNAIL_ERR_OUT_OF_MEMORY;
    if (next) |new_atlas| return wrapAtlas(new_atlas, atlas.allocator, out);
    out.* = null;
    return SNAIL_OK;
}

// ── Constants ──

export fn snail_text_floats_per_glyph() usize {
    return snail.TEXT_FLOATS_PER_GLYPH;
}
export fn snail_text_floats_per_vertex() usize {
    return snail.TEXT_FLOATS_PER_VERTEX;
}
export fn snail_text_vertices_per_glyph() usize {
    return snail.TEXT_VERTICES_PER_GLYPH;
}
export fn snail_path_floats_per_shape() usize {
    return snail.PATH_FLOATS_PER_SHAPE;
}
export fn snail_sprite_floats_per_sprite() usize {
    return snail.SPRITE_FLOATS_PER_SPRITE;
}
// Keep old name as alias for backward compat
export fn snail_floats_per_glyph() usize {
    return snail.TEXT_FLOATS_PER_GLYPH;
}

// ── Tests ──

const testing = std.testing;

test "c_api: font init, metrics, and deinit" {
    const assets = @import("assets");
    var font: ?*FontImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_font_init(assets.noto_sans_regular.ptr, assets.noto_sans_regular.len, &font));
    try testing.expect(font != null);
    defer snail_font_deinit(font);

    const em = snail_font_units_per_em(font.?);
    try testing.expect(em > 0);

    const gid = snail_font_glyph_index(font.?, 'A');
    try testing.expect(gid > 0);

    var metrics: SnailGlyphMetrics = undefined;
    try testing.expectEqual(SNAIL_OK, snail_font_glyph_metrics(font.?, gid, &metrics));
    try testing.expect(metrics.advance_width > 0);

    var line_metrics: SnailLineMetrics = undefined;
    try testing.expectEqual(SNAIL_OK, snail_font_line_metrics(font.?, &line_metrics));
    try testing.expect(line_metrics.ascent > 0);
}

test "c_api: atlas init, page count, texture size" {
    const assets = @import("assets");
    var font: ?*FontImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_font_init(assets.noto_sans_regular.ptr, assets.noto_sans_regular.len, &font));
    defer snail_font_deinit(font);

    var atlas: ?*AtlasImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_atlas_init_ascii(null, font.?, &atlas));
    try testing.expect(atlas != null);
    defer snail_atlas_deinit(atlas);

    try testing.expect(snail_atlas_page_count(atlas.?) > 0);
    try testing.expect(snail_atlas_texture_byte_len(atlas.?) > 0);
}

test "c_api: shape utf8 and shaped run access" {
    const assets = @import("assets");
    var font: ?*FontImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_font_init(assets.noto_sans_regular.ptr, assets.noto_sans_regular.len, &font));
    defer snail_font_deinit(font);

    var atlas: ?*AtlasImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_atlas_init_ascii(null, font.?, &atlas));
    defer snail_atlas_deinit(atlas);

    var run: ?*ShapedRunImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_atlas_shape_utf8(atlas.?, font.?, "Hello", 5, 24.0, &run));
    try testing.expect(run != null);
    defer snail_shaped_run_deinit(run);

    try testing.expectEqual(@as(usize, 5), snail_shaped_run_glyph_count(run.?));
    try testing.expect(snail_shaped_run_advance_x(run.?) > 0);

    var g0: SnailGlyphPlacement = undefined;
    try testing.expect(snail_shaped_run_glyph(run.?, 0, &g0));
    try testing.expect(g0.glyph_id > 0);
    try testing.expect(g0.source_end > g0.source_start);
}

test "c_api: collect missing glyph ids" {
    const assets = @import("assets");
    var font: ?*FontImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_font_init(assets.noto_sans_regular.ptr, assets.noto_sans_regular.len, &font));
    defer snail_font_deinit(font);

    // Build atlas with ASCII only
    var atlas: ?*AtlasImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_atlas_init_ascii(null, font.?, &atlas));
    defer snail_atlas_deinit(atlas);

    // Shape text containing non-ASCII (é)
    var run: ?*ShapedRunImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_atlas_shape_utf8(atlas.?, font.?, "\xc3\xa9", 2, 24.0, &run));
    defer snail_shaped_run_deinit(run);

    // Should find the missing glyph
    var missing: [16]u16 = undefined;
    const count = snail_atlas_collect_missing_glyph_ids(atlas.?, run.?, &missing, 16);
    try testing.expect(count > 0);
}

test "c_api: atlas extend run" {
    const assets = @import("assets");
    var font: ?*FontImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_font_init(assets.noto_sans_regular.ptr, assets.noto_sans_regular.len, &font));
    defer snail_font_deinit(font);

    var atlas: ?*AtlasImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_atlas_init_ascii(null, font.?, &atlas));
    defer snail_atlas_deinit(atlas);

    // Shape non-ASCII text
    var run: ?*ShapedRunImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_atlas_shape_utf8(atlas.?, font.?, "\xc3\xa9", 2, 24.0, &run));
    defer snail_shaped_run_deinit(run);

    // Extend atlas with the run
    var extended: ?*AtlasImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_atlas_extend_run(atlas.?, run.?, &extended));
    if (extended) |ext| snail_atlas_deinit(ext);
}

test "c_api: atlas extend text" {
    const assets = @import("assets");
    var font: ?*FontImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_font_init(assets.noto_sans_regular.ptr, assets.noto_sans_regular.len, &font));
    defer snail_font_deinit(font);

    var atlas: ?*AtlasImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_atlas_init_ascii(null, font.?, &atlas));
    defer snail_atlas_deinit(atlas);

    var extended: ?*AtlasImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_atlas_extend_text(atlas.?, "\xc3\xa9\xc3\xb1", 4, &extended));
    if (extended) |ext| snail_atlas_deinit(ext);
}

test "c_api: text batch add_text produces vertices" {
    const assets = @import("assets");
    var font: ?*FontImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_font_init(assets.noto_sans_regular.ptr, assets.noto_sans_regular.len, &font));
    defer snail_font_deinit(font);

    var atlas: ?*AtlasImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_atlas_init_ascii(null, font.?, &atlas));
    defer snail_atlas_deinit(atlas);

    var buf: [512 * snail.TEXT_FLOATS_PER_GLYPH]f32 = undefined;
    var buf_len: usize = 0;
    const color = [4]f32{ 1, 1, 1, 1 };
    const advance = snail_batch_add_text(&buf, buf.len, &buf_len, atlas.?, font.?, "Hi", 2, 0, 0, 24, &color);
    try testing.expect(advance > 0);
    try testing.expect(buf_len > 0);
    try testing.expectEqual(@as(usize, 2), snail_batch_glyph_count(buf_len));
}

test "c_api: text batch add_run matches add_text" {
    const assets = @import("assets");
    var font: ?*FontImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_font_init(assets.noto_sans_regular.ptr, assets.noto_sans_regular.len, &font));
    defer snail_font_deinit(font);

    var atlas: ?*AtlasImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_atlas_init_ascii(null, font.?, &atlas));
    defer snail_atlas_deinit(atlas);

    // Shape and add via run
    var run: ?*ShapedRunImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_atlas_shape_utf8(atlas.?, font.?, "AB", 2, 24.0, &run));
    defer snail_shaped_run_deinit(run);

    var buf: [512 * snail.TEXT_FLOATS_PER_GLYPH]f32 = undefined;
    var buf_len: usize = 0;
    const color = [4]f32{ 1, 1, 1, 1 };
    const count = snail_batch_add_run(&buf, buf.len, &buf_len, atlas.?, run.?, 0, 0, 24, &color);
    try testing.expectEqual(@as(usize, 2), count);
    try testing.expect(buf_len > 0);
}

test "c_api: path build triangle and freeze" {
    var path: ?*PathImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_path_init(null, &path));
    defer snail_path_deinit(path);

    try testing.expect(snail_path_is_empty(path.?));

    try testing.expectEqual(SNAIL_OK, snail_path_move_to(path.?, 0, 0));
    try testing.expectEqual(SNAIL_OK, snail_path_line_to(path.?, 10, 0));
    try testing.expectEqual(SNAIL_OK, snail_path_line_to(path.?, 5, 8));
    try testing.expectEqual(SNAIL_OK, snail_path_close(path.?));

    try testing.expect(!snail_path_is_empty(path.?));

    var bbox: SnailBBox = undefined;
    try testing.expect(snail_path_bounds(path.?, &bbox));
    try testing.expect(bbox.max_x > bbox.min_x);
    try testing.expect(bbox.max_y > bbox.min_y);

    // Freeze into a path picture
    var builder: ?*PathPictureBuilderImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_path_picture_builder_init(null, &builder));
    defer snail_path_picture_builder_deinit(builder);

    const fill = SnailFillStyle{ .color = .{ 1, 0, 0, 1 } };
    const identity = SnailTransform2D{};
    try testing.expectEqual(SNAIL_OK, snail_path_picture_builder_add_filled_path(builder.?, path.?, fill, identity));

    var picture: ?*PathPictureImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_path_picture_builder_freeze(builder.?, null, &picture));
    try testing.expect(picture != null);
    defer snail_path_picture_deinit(picture);

    try testing.expectEqual(@as(usize, 1), snail_path_picture_shape_count(picture.?));

    // Add to path batch
    var pbuf: [snail.PATH_FLOATS_PER_SHAPE * 4]f32 = undefined;
    var pbuf_len: usize = 0;
    const shapes = snail_path_batch_add_picture(&pbuf, pbuf.len, &pbuf_len, picture.?);
    try testing.expectEqual(@as(usize, 1), shapes);
    try testing.expect(pbuf_len > 0);
}

test "c_api: path picture builder add_rect with stroke" {
    var builder: ?*PathPictureBuilderImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_path_picture_builder_init(null, &builder));
    defer snail_path_picture_builder_deinit(builder);

    const fill = SnailFillStyle{ .color = .{ 0.2, 0.4, 0.8, 1 } };
    const stroke = SnailStrokeStyle{ .color = .{ 1, 1, 1, 1 }, .width = 2, .join = SNAIL_JOIN_ROUND };
    const rect = SnailRect{ .x = 10, .y = 10, .w = 100, .h = 50 };
    try testing.expectEqual(SNAIL_OK, snail_path_picture_builder_add_rect(builder.?, rect, &fill, &stroke, .{}));

    var picture: ?*PathPictureImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_path_picture_builder_freeze(builder.?, null, &picture));
    defer snail_path_picture_deinit(picture);

    try testing.expectEqual(@as(usize, 1), snail_path_picture_shape_count(picture.?));
}

test "c_api: constants are consistent" {
    try testing.expectEqual(snail.TEXT_FLOATS_PER_GLYPH, snail_text_floats_per_glyph());
    try testing.expectEqual(snail.TEXT_FLOATS_PER_VERTEX, snail_text_floats_per_vertex());
    try testing.expectEqual(snail.TEXT_VERTICES_PER_GLYPH, snail_text_vertices_per_glyph());
    try testing.expectEqual(snail.PATH_FLOATS_PER_SHAPE, snail_path_floats_per_shape());
    try testing.expectEqual(snail.SPRITE_FLOATS_PER_SPRITE, snail_sprite_floats_per_sprite());
    try testing.expectEqual(snail_text_floats_per_glyph(), snail_floats_per_glyph());
}

test "c_api: image init and deinit" {
    var pixels: [4 * 4 * 4]u8 = undefined;
    @memset(&pixels, 0xFF);

    var image: ?*ImageImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_image_init_rgba8(null, 4, 4, &pixels, &image));
    try testing.expect(image != null);
    defer snail_image_deinit(image);

    try testing.expectEqual(@as(u32, 4), snail_image_width(image.?));
    try testing.expectEqual(@as(u32, 4), snail_image_height(image.?));
}
