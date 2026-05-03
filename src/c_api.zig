//! C API for snail's public Zig resource model.
//! All exported functions use opaque handles and explicit ownership.

const std = @import("std");
const snail = @import("snail.zig");
const ttf = @import("font/ttf.zig");

const build_options = @import("build_options");

// Allocator bridge

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
    return @ptrCast(std.c.malloc(size) orelse return null);
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

fn handleAllocator() std.mem.Allocator {
    return std.heap.smp_allocator;
}

// Error codes

pub const SNAIL_OK: c_int = 0;
pub const SNAIL_ERR_INVALID_FONT: c_int = -1;
pub const SNAIL_ERR_OUT_OF_MEMORY: c_int = -2;
pub const SNAIL_ERR_RENDERER_FAILED: c_int = -3;
pub const SNAIL_ERR_INVALID_ARGUMENT: c_int = -4;
pub const SNAIL_ERR_DRAW_FAILED: c_int = -5;

fn mapError(err: anyerror) c_int {
    return switch (err) {
        error.OutOfMemory => SNAIL_ERR_OUT_OF_MEMORY,
        error.InvalidFont, error.NoFaces => SNAIL_ERR_INVALID_FONT,
        error.InvalidEnum, error.InvalidArgument => SNAIL_ERR_INVALID_ARGUMENT,
        else => SNAIL_ERR_DRAW_FAILED,
    };
}

// C-compatible value types

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

pub const SnailMat4 = extern struct {
    data: [16]f32,
};

pub const SnailTransform2D = extern struct {
    xx: f32 = 1,
    xy: f32 = 0,
    tx: f32 = 0,
    yx: f32 = 0,
    yy: f32 = 1,
    ty: f32 = 0,
};

pub const SnailSyntheticStyle = extern struct {
    embolden: f32 = 0,
    skew_x: f32 = 0,
};

pub const SnailFaceSpec = extern struct {
    data: [*]const u8,
    len: usize,
    weight: c_int = 4,
    italic: bool = false,
    fallback: bool = false,
    synthetic: SnailSyntheticStyle = .{},
};

pub const SnailFontStyle = extern struct {
    weight: c_int = 4,
    italic: bool = false,
};

pub const SnailShapedGlyph = extern struct {
    face_index: u16,
    glyph_id: u16,
    x_offset: f32,
    y_offset: f32,
    x_advance: f32,
    y_advance: f32,
    source_start: u32,
    source_end: u32,
};

pub const SnailTextBlobOptions = extern struct {
    x: f32,
    y: f32,
    size: f32,
    color: [4]f32,
};

pub const SnailTextResolveOptions = extern struct {
    hinting: c_int = 0,
};

pub const SnailResolveTarget = extern struct {
    pixel_width: f32,
    pixel_height: f32,
    subpixel_order: c_int = 0,
    fill_rule: c_int = 0,
    is_final_composite: bool = true,
    opaque_backdrop: bool = true,
    will_resample: bool = false,
};

pub const SnailDrawOptions = extern struct {
    mvp: SnailMat4,
    target: SnailResolveTarget,
};

pub const SnailResourceKey = u64;

// Paint / style types

pub const SNAIL_PAINT_SOLID: c_int = 0;
pub const SNAIL_PAINT_LINEAR: c_int = 1;
pub const SNAIL_PAINT_RADIAL: c_int = 2;
pub const SNAIL_PAINT_IMAGE: c_int = 3;

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

pub const SnailImagePaint = extern struct {
    image: ?*const ImageImpl = null,
    uv_transform: SnailTransform2D = .{},
    tint: [4]f32 = .{ 1, 1, 1, 1 },
    extend_x: c_int = 0,
    extend_y: c_int = 0,
    filter: c_int = 0,
};

pub const SnailFillStyle = extern struct {
    color: [4]f32 = .{ 0, 0, 0, 1 },
    paint_kind: c_int = -1,
    paint_solid: [4]f32 = .{ 0, 0, 0, 0 },
    paint_linear: SnailLinearGradient = std.mem.zeroes(SnailLinearGradient),
    paint_radial: SnailRadialGradient = std.mem.zeroes(SnailRadialGradient),
    paint_image: SnailImagePaint = .{},
};

pub const SnailStrokeStyle = extern struct {
    color: [4]f32 = .{ 0, 0, 0, 1 },
    paint_kind: c_int = -1,
    paint_solid: [4]f32 = .{ 0, 0, 0, 0 },
    paint_linear: SnailLinearGradient = std.mem.zeroes(SnailLinearGradient),
    paint_radial: SnailRadialGradient = std.mem.zeroes(SnailRadialGradient),
    paint_image: SnailImagePaint = .{},
    width: f32 = 1,
    cap: c_int = 0,
    join: c_int = 0,
    miter_limit: f32 = 4,
    placement: c_int = 0,
};

// Opaque handle implementations

const FontImpl = struct { inner: ttf.Font };
const TextAtlasImpl = struct { inner: snail.TextAtlas, allocator: std.mem.Allocator };
const ShapedTextImpl = struct { inner: snail.ShapedText };
const TextBlobImpl = struct { inner: snail.TextBlob };
const ImageImpl = struct { inner: snail.Image };
const PathImpl = struct { inner: snail.Path };
const PathPictureBuilderImpl = struct { inner: snail.PathPictureBuilder };
const PathPictureImpl = struct { inner: snail.PathPicture };
const SceneImpl = struct { inner: snail.Scene };
const ResourceSetImpl = struct {
    inner: snail.ResourceSet,
    entries: []snail.ResourceSet.Entry,
    allocator: std.mem.Allocator,
};
const PreparedResourcesImpl = struct { inner: snail.PreparedResources };
const PreparedSceneImpl = struct { inner: snail.PreparedScene };
const RendererImpl = struct { inner: snail.Renderer };

// Conversion helpers

fn wrapBBox(bbox: snail.BBox) SnailBBox {
    return .{ .min_x = bbox.min.x, .min_y = bbox.min.y, .max_x = bbox.max.x, .max_y = bbox.max.y };
}

fn toRect(r: SnailRect) snail.Rect {
    return .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
}

fn toMat4(m: SnailMat4) snail.Mat4 {
    return .{ .data = m.data };
}

fn fromMat4(m: snail.Mat4) SnailMat4 {
    return .{ .data = m.data };
}

fn toTransform(t: SnailTransform2D) snail.Transform2D {
    return .{ .xx = t.xx, .xy = t.xy, .tx = t.tx, .yx = t.yx, .yy = t.yy, .ty = t.ty };
}

fn toSyntheticStyle(s: SnailSyntheticStyle) snail.SyntheticStyle {
    return .{ .embolden = s.embolden, .skew_x = s.skew_x };
}

fn toFontWeight(v: c_int) !snail.FontWeight {
    return switch (v) {
        1 => .thin,
        2 => .extra_light,
        3 => .light,
        4 => .regular,
        5 => .medium,
        6 => .semi_bold,
        7 => .bold,
        8 => .extra_bold,
        9 => .black,
        else => error.InvalidEnum,
    };
}

fn toFontStyle(style: SnailFontStyle) !snail.FontStyle {
    return .{ .weight = try toFontWeight(style.weight), .italic = style.italic };
}

fn toPaintExtend(v: c_int) !snail.PaintExtend {
    return switch (v) {
        0 => .clamp,
        1 => .repeat,
        2 => .reflect,
        else => error.InvalidEnum,
    };
}

fn toImageFilter(v: c_int) !snail.ImageFilter {
    return switch (v) {
        0 => .linear,
        1 => .nearest,
        else => error.InvalidEnum,
    };
}

fn toStrokeCap(v: c_int) !snail.StrokeCap {
    return switch (v) {
        0 => .butt,
        1 => .square,
        2 => .round,
        else => error.InvalidEnum,
    };
}

fn toStrokeJoin(v: c_int) !snail.StrokeJoin {
    return switch (v) {
        0 => .miter,
        1 => .bevel,
        2 => .round,
        else => error.InvalidEnum,
    };
}

fn toStrokePlacement(v: c_int) !snail.StrokePlacement {
    return switch (v) {
        0 => .center,
        1 => .inside,
        else => error.InvalidEnum,
    };
}

fn toSubpixelOrder(v: c_int) !snail.SubpixelOrder {
    return switch (v) {
        0 => .none,
        1 => .rgb,
        2 => .bgr,
        3 => .vrgb,
        4 => .vbgr,
        else => error.InvalidEnum,
    };
}

fn toFillRule(v: c_int) !snail.FillRule {
    return switch (v) {
        0 => .non_zero,
        1 => .even_odd,
        else => error.InvalidEnum,
    };
}

fn toTextHinting(v: c_int) !snail.TextHinting {
    return switch (v) {
        0 => .none,
        1 => .phase,
        2 => .metrics,
        else => error.InvalidEnum,
    };
}

fn toTextResolveOptions(options: SnailTextResolveOptions) !snail.TextResolveOptions {
    return .{ .hinting = try toTextHinting(options.hinting) };
}

fn toResolveTarget(target: SnailResolveTarget) !snail.ResolveTarget {
    return .{
        .pixel_width = target.pixel_width,
        .pixel_height = target.pixel_height,
        .subpixel_order = try toSubpixelOrder(target.subpixel_order),
        .fill_rule = try toFillRule(target.fill_rule),
        .is_final_composite = target.is_final_composite,
        .opaque_backdrop = target.opaque_backdrop,
        .will_resample = target.will_resample,
    };
}

fn toDrawOptions(options: SnailDrawOptions) !snail.DrawOptions {
    return .{ .mvp = toMat4(options.mvp), .target = try toResolveTarget(options.target) };
}

fn toPaint(kind: c_int, solid: [4]f32, linear: SnailLinearGradient, radial: SnailRadialGradient, image: SnailImagePaint) !?snail.Paint {
    return switch (kind) {
        -1 => null,
        SNAIL_PAINT_SOLID => .{ .solid = solid },
        SNAIL_PAINT_LINEAR => .{ .linear_gradient = .{
            .start = .{ .x = linear.start_x, .y = linear.start_y },
            .end = .{ .x = linear.end_x, .y = linear.end_y },
            .start_color = linear.start_color,
            .end_color = linear.end_color,
            .extend = try toPaintExtend(linear.extend),
        } },
        SNAIL_PAINT_RADIAL => .{ .radial_gradient = .{
            .center = .{ .x = radial.center_x, .y = radial.center_y },
            .radius = radial.radius,
            .inner_color = radial.inner_color,
            .outer_color = radial.outer_color,
            .extend = try toPaintExtend(radial.extend),
        } },
        SNAIL_PAINT_IMAGE => blk: {
            const img = image.image orelse return error.InvalidArgument;
            break :blk .{ .image = .{
                .image = &img.inner,
                .uv_transform = toTransform(image.uv_transform),
                .tint = image.tint,
                .extend_x = try toPaintExtend(image.extend_x),
                .extend_y = try toPaintExtend(image.extend_y),
                .filter = try toImageFilter(image.filter),
            } };
        },
        else => error.InvalidEnum,
    };
}

fn toFillStyle(s: SnailFillStyle) !snail.FillStyle {
    return .{
        .color = s.color,
        .paint = try toPaint(s.paint_kind, s.paint_solid, s.paint_linear, s.paint_radial, s.paint_image),
    };
}

fn toStrokeStyle(s: SnailStrokeStyle) !snail.StrokeStyle {
    return .{
        .color = s.color,
        .paint = try toPaint(s.paint_kind, s.paint_solid, s.paint_linear, s.paint_radial, s.paint_image),
        .width = s.width,
        .cap = try toStrokeCap(s.cap),
        .join = try toStrokeJoin(s.join),
        .miter_limit = s.miter_limit,
        .placement = try toStrokePlacement(s.placement),
    };
}

fn toOptFill(ptr: ?*const SnailFillStyle) !?snail.FillStyle {
    if (ptr) |s| return try toFillStyle(s.*);
    return null;
}

fn toOptStroke(ptr: ?*const SnailStrokeStyle) !?snail.StrokeStyle {
    if (ptr) |s| return try toStrokeStyle(s.*);
    return null;
}

fn destroyHandle(ptr: anytype) void {
    handleAllocator().destroy(ptr);
}

// Font metrics helper

export fn snail_font_init(data: [*]const u8, len: usize, out: *?*FontImpl) c_int {
    const font = ttf.Font.init(data[0..len]) catch return SNAIL_ERR_INVALID_FONT;
    const impl = handleAllocator().create(FontImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.* = .{ .inner = font };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_font_deinit(font: ?*FontImpl) void {
    if (font) |f| destroyHandle(f);
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

// TextAtlas and shaping

export fn snail_text_atlas_init(
    alloc_ptr: ?*const SnailAllocator,
    specs: [*]const SnailFaceSpec,
    spec_count: usize,
    out: *?*TextAtlasImpl,
) c_int {
    if (spec_count == 0) return SNAIL_ERR_INVALID_ARGUMENT;
    const allocator = resolveAllocator(alloc_ptr);
    const zig_specs = allocator.alloc(snail.FaceSpec, spec_count) catch return SNAIL_ERR_OUT_OF_MEMORY;
    defer allocator.free(zig_specs);

    for (specs[0..spec_count], 0..) |spec, i| {
        zig_specs[i] = .{
            .data = spec.data[0..spec.len],
            .weight = toFontWeight(spec.weight) catch return SNAIL_ERR_INVALID_ARGUMENT,
            .italic = spec.italic,
            .fallback = spec.fallback,
            .synthetic = toSyntheticStyle(spec.synthetic),
        };
    }

    const atlas = snail.TextAtlas.init(allocator, zig_specs) catch |err| return mapError(err);
    const impl = handleAllocator().create(TextAtlasImpl) catch {
        var doomed = atlas;
        doomed.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = atlas, .allocator = allocator };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_text_atlas_deinit(atlas: ?*TextAtlasImpl) void {
    if (atlas) |a| {
        a.inner.deinit();
        destroyHandle(a);
    }
}

export fn snail_text_atlas_page_count(atlas: *const TextAtlasImpl) usize {
    return atlas.inner.pageCount();
}

export fn snail_text_atlas_texture_byte_len(atlas: *const TextAtlasImpl) usize {
    var total: usize = 0;
    for (atlas.inner.pageSlice()) |page| total += page.textureBytes();
    if (atlas.inner.layer_info_data) |data| total += data.len * @sizeOf(f32);
    return total;
}

export fn snail_text_atlas_units_per_em(atlas: *const TextAtlasImpl, out: *u16) c_int {
    out.* = atlas.inner.unitsPerEm() catch return SNAIL_ERR_INVALID_FONT;
    return SNAIL_OK;
}

export fn snail_text_atlas_line_metrics(atlas: *const TextAtlasImpl, out: *SnailLineMetrics) c_int {
    const m = atlas.inner.lineMetrics() catch return SNAIL_ERR_INVALID_FONT;
    out.* = .{ .ascent = m.ascent, .descent = m.descent, .line_gap = m.line_gap };
    return SNAIL_OK;
}

export fn snail_text_atlas_shape_utf8(
    atlas: *const TextAtlasImpl,
    style: SnailFontStyle,
    text: [*]const u8,
    text_len: usize,
    out: *?*ShapedTextImpl,
) c_int {
    const shaped = atlas.inner.shapeText(atlas.allocator, toFontStyle(style) catch return SNAIL_ERR_INVALID_ARGUMENT, text[0..text_len]) catch |err| return mapError(err);
    const impl = handleAllocator().create(ShapedTextImpl) catch {
        var doomed = shaped;
        doomed.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = shaped };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_text_atlas_ensure_text(
    atlas: *const TextAtlasImpl,
    style: SnailFontStyle,
    text: [*]const u8,
    text_len: usize,
    out: *?*TextAtlasImpl,
) c_int {
    const next = atlas.inner.ensureText(toFontStyle(style) catch return SNAIL_ERR_INVALID_ARGUMENT, text[0..text_len]) catch |err| return mapError(err);
    if (next) |new_atlas| {
        const impl = handleAllocator().create(TextAtlasImpl) catch {
            var doomed = new_atlas;
            doomed.deinit();
            return SNAIL_ERR_OUT_OF_MEMORY;
        };
        impl.* = .{ .inner = new_atlas, .allocator = atlas.allocator };
        out.* = impl;
    } else {
        out.* = null;
    }
    return SNAIL_OK;
}

export fn snail_text_atlas_ensure_shaped(atlas: *const TextAtlasImpl, shaped: *const ShapedTextImpl, out: *?*TextAtlasImpl) c_int {
    const next = atlas.inner.ensureShaped(&shaped.inner) catch |err| return mapError(err);
    if (next) |new_atlas| {
        const impl = handleAllocator().create(TextAtlasImpl) catch {
            var doomed = new_atlas;
            doomed.deinit();
            return SNAIL_ERR_OUT_OF_MEMORY;
        };
        impl.* = .{ .inner = new_atlas, .allocator = atlas.allocator };
        out.* = impl;
    } else {
        out.* = null;
    }
    return SNAIL_OK;
}

export fn snail_shaped_text_deinit(shaped: ?*ShapedTextImpl) void {
    if (shaped) |s| {
        s.inner.deinit();
        destroyHandle(s);
    }
}

export fn snail_shaped_text_glyph_count(shaped: *const ShapedTextImpl) usize {
    return shaped.inner.glyphs.len;
}

export fn snail_shaped_text_advance_x(shaped: *const ShapedTextImpl) f32 {
    return shaped.inner.advance_x;
}

export fn snail_shaped_text_advance_y(shaped: *const ShapedTextImpl) f32 {
    return shaped.inner.advance_y;
}

export fn snail_shaped_text_glyph(shaped: *const ShapedTextImpl, index: usize, out: *SnailShapedGlyph) bool {
    if (index >= shaped.inner.glyphs.len) return false;
    const g = shaped.inner.glyphs[index];
    out.* = .{
        .face_index = g.face_index,
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

export fn snail_shaped_text_copy_glyphs(shaped: *const ShapedTextImpl, out: [*]SnailShapedGlyph, capacity: usize) usize {
    const count = @min(shaped.inner.glyphs.len, capacity);
    for (shaped.inner.glyphs[0..count], 0..) |g, i| {
        out[i] = .{
            .face_index = g.face_index,
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

export fn snail_text_blob_init_from_shaped(
    alloc_ptr: ?*const SnailAllocator,
    atlas: *const TextAtlasImpl,
    shaped: *const ShapedTextImpl,
    options: SnailTextBlobOptions,
    out: *?*TextBlobImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const blob = snail.TextBlob.fromShaped(allocator, &atlas.inner, &shaped.inner, .{
        .x = options.x,
        .y = options.y,
        .size = options.size,
        .color = options.color,
    }) catch |err| return mapError(err);
    const impl = handleAllocator().create(TextBlobImpl) catch {
        var doomed = blob;
        doomed.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = blob };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_text_blob_init_text(
    alloc_ptr: ?*const SnailAllocator,
    atlas: *const TextAtlasImpl,
    style: SnailFontStyle,
    text: [*]const u8,
    text_len: usize,
    options: SnailTextBlobOptions,
    out: *?*TextBlobImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    var shaped = atlas.inner.shapeText(allocator, toFontStyle(style) catch return SNAIL_ERR_INVALID_ARGUMENT, text[0..text_len]) catch |err| return mapError(err);
    defer shaped.deinit();
    return snail_text_blob_init_from_shaped(alloc_ptr, atlas, &.{ .inner = shaped }, options, out);
}

export fn snail_text_blob_deinit(blob: ?*TextBlobImpl) void {
    if (blob) |b| {
        b.inner.deinit();
        destroyHandle(b);
    }
}

export fn snail_text_blob_glyph_count(blob: *const TextBlobImpl) usize {
    return blob.inner.glyphCount();
}

// Image

export fn snail_image_init_srgba8(
    alloc_ptr: ?*const SnailAllocator,
    width: u32,
    height: u32,
    pixels: [*]const u8,
    out: *?*ImageImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const img = snail.Image.initSrgba8(allocator, width, height, pixels[0 .. width * height * 4]) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const impl = handleAllocator().create(ImageImpl) catch {
        var doomed = img;
        doomed.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = img };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_image_deinit(image: ?*ImageImpl) void {
    if (image) |img| {
        img.inner.deinit();
        destroyHandle(img);
    }
}

export fn snail_image_width(image: *const ImageImpl) u32 {
    return image.inner.width;
}

export fn snail_image_height(image: *const ImageImpl) u32 {
    return image.inner.height;
}

// Paths and path pictures

export fn snail_path_init(alloc_ptr: ?*const SnailAllocator, out: *?*PathImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const impl = handleAllocator().create(PathImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.* = .{ .inner = snail.Path.init(allocator) };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_path_deinit(path: ?*PathImpl) void {
    if (path) |p| {
        p.inner.deinit();
        destroyHandle(p);
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

export fn snail_path_picture_builder_init(alloc_ptr: ?*const SnailAllocator, out: *?*PathPictureBuilderImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const impl = handleAllocator().create(PathPictureBuilderImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.* = .{ .inner = snail.PathPictureBuilder.init(allocator) };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_path_picture_builder_deinit(builder: ?*PathPictureBuilderImpl) void {
    if (builder) |b| {
        b.inner.deinit();
        destroyHandle(b);
    }
}

export fn snail_path_picture_builder_add_path(
    builder: *PathPictureBuilderImpl,
    path: *const PathImpl,
    fill: ?*const SnailFillStyle,
    stroke: ?*const SnailStrokeStyle,
    transform: SnailTransform2D,
) c_int {
    builder.inner.addPath(&path.inner, toOptFill(fill) catch return SNAIL_ERR_INVALID_ARGUMENT, toOptStroke(stroke) catch return SNAIL_ERR_INVALID_ARGUMENT, toTransform(transform)) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_picture_builder_add_filled_path(
    builder: *PathPictureBuilderImpl,
    path: *const PathImpl,
    fill: SnailFillStyle,
    transform: SnailTransform2D,
) c_int {
    builder.inner.addFilledPath(&path.inner, toFillStyle(fill) catch return SNAIL_ERR_INVALID_ARGUMENT, toTransform(transform)) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_picture_builder_add_stroked_path(
    builder: *PathPictureBuilderImpl,
    path: *const PathImpl,
    stroke: SnailStrokeStyle,
    transform: SnailTransform2D,
) c_int {
    builder.inner.addStrokedPath(&path.inner, toStrokeStyle(stroke) catch return SNAIL_ERR_INVALID_ARGUMENT, toTransform(transform)) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_picture_builder_add_rect(builder: *PathPictureBuilderImpl, rect: SnailRect, fill: ?*const SnailFillStyle, stroke: ?*const SnailStrokeStyle, transform: SnailTransform2D) c_int {
    builder.inner.addRect(toRect(rect), toOptFill(fill) catch return SNAIL_ERR_INVALID_ARGUMENT, toOptStroke(stroke) catch return SNAIL_ERR_INVALID_ARGUMENT, toTransform(transform)) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_picture_builder_add_rounded_rect(builder: *PathPictureBuilderImpl, rect: SnailRect, fill: ?*const SnailFillStyle, stroke: ?*const SnailStrokeStyle, corner_radius: f32, transform: SnailTransform2D) c_int {
    builder.inner.addRoundedRect(toRect(rect), toOptFill(fill) catch return SNAIL_ERR_INVALID_ARGUMENT, toOptStroke(stroke) catch return SNAIL_ERR_INVALID_ARGUMENT, corner_radius, toTransform(transform)) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_picture_builder_add_ellipse(builder: *PathPictureBuilderImpl, rect: SnailRect, fill: ?*const SnailFillStyle, stroke: ?*const SnailStrokeStyle, transform: SnailTransform2D) c_int {
    builder.inner.addEllipse(toRect(rect), toOptFill(fill) catch return SNAIL_ERR_INVALID_ARGUMENT, toOptStroke(stroke) catch return SNAIL_ERR_INVALID_ARGUMENT, toTransform(transform)) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_picture_builder_freeze(builder: *const PathPictureBuilderImpl, alloc_ptr: ?*const SnailAllocator, out: *?*PathPictureImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    var picture = builder.inner.freeze(allocator) catch |err| return mapError(err);
    const impl = handleAllocator().create(PathPictureImpl) catch {
        picture.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = picture };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_path_picture_deinit(picture: ?*PathPictureImpl) void {
    if (picture) |p| {
        p.inner.deinit();
        destroyHandle(p);
    }
}

export fn snail_path_picture_shape_count(picture: *const PathPictureImpl) usize {
    return picture.inner.shapeCount();
}

// Scene and resources

export fn snail_scene_init(alloc_ptr: ?*const SnailAllocator, out: *?*SceneImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const impl = handleAllocator().create(SceneImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.* = .{ .inner = snail.Scene.init(allocator) };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_scene_deinit(scene: ?*SceneImpl) void {
    if (scene) |s| {
        s.inner.deinit();
        destroyHandle(s);
    }
}

export fn snail_scene_reset(scene: *SceneImpl) void {
    scene.inner.reset();
}

export fn snail_scene_command_count(scene: *const SceneImpl) usize {
    return scene.inner.commandCount();
}

export fn snail_scene_add_text(scene: *SceneImpl, blob: *const TextBlobImpl) c_int {
    scene.inner.addText(&blob.inner) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_scene_add_text_options(scene: *SceneImpl, blob: *const TextBlobImpl, transform: SnailTransform2D, resolve: SnailTextResolveOptions) c_int {
    scene.inner.addTextTransformedOptions(&blob.inner, toTransform(transform), toTextResolveOptions(resolve) catch return SNAIL_ERR_INVALID_ARGUMENT) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_scene_add_path_picture(scene: *SceneImpl, picture: *const PathPictureImpl) c_int {
    scene.inner.addPathPicture(&picture.inner) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_scene_add_path_picture_transformed(scene: *SceneImpl, picture: *const PathPictureImpl, transform: SnailTransform2D) c_int {
    scene.inner.addPathPictureTransformed(&picture.inner, toTransform(transform)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_resource_set_init(alloc_ptr: ?*const SnailAllocator, capacity: usize, out: *?*ResourceSetImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const entries = allocator.alloc(snail.ResourceSet.Entry, capacity) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const impl = handleAllocator().create(ResourceSetImpl) catch {
        allocator.free(entries);
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = snail.ResourceSet.init(entries), .entries = entries, .allocator = allocator };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_resource_set_deinit(set: ?*ResourceSetImpl) void {
    if (set) |s| {
        s.allocator.free(s.entries);
        destroyHandle(s);
    }
}

export fn snail_resource_set_reset(set: *ResourceSetImpl) void {
    set.inner.reset();
}

export fn snail_resource_set_count(set: *const ResourceSetImpl) usize {
    return set.inner.len;
}

export fn snail_resource_set_capacity(set: *const ResourceSetImpl) usize {
    return set.inner.capacity();
}

export fn snail_resource_set_put_text_atlas(set: *ResourceSetImpl, key: SnailResourceKey, atlas: *const TextAtlasImpl) c_int {
    set.inner.putTextAtlas(snail.ResourceKey.fromId(key), &atlas.inner) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_resource_set_put_path_picture(set: *ResourceSetImpl, key: SnailResourceKey, picture: *const PathPictureImpl) c_int {
    set.inner.putPathPicture(snail.ResourceKey.fromId(key), &picture.inner) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_resource_set_put_image(set: *ResourceSetImpl, key: SnailResourceKey, image: *const ImageImpl) c_int {
    set.inner.putImage(snail.ResourceKey.fromId(key), &image.inner) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_resource_set_add_scene(set: *ResourceSetImpl, scene: *const SceneImpl) c_int {
    set.inner.addScene(&scene.inner) catch return SNAIL_ERR_OUT_OF_MEMORY;
    return SNAIL_OK;
}

export fn snail_prepared_resources_deinit(prepared: ?*PreparedResourcesImpl) void {
    if (prepared) |p| {
        p.inner.deinit();
        destroyHandle(p);
    }
}

export fn snail_prepared_scene_init(
    alloc_ptr: ?*const SnailAllocator,
    prepared: *const PreparedResourcesImpl,
    scene: *const SceneImpl,
    options: SnailDrawOptions,
    out: *?*PreparedSceneImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const zig_options = toDrawOptions(options) catch return SNAIL_ERR_INVALID_ARGUMENT;
    const prepared_scene = snail.PreparedScene.initOwned(allocator, &prepared.inner, &scene.inner, zig_options) catch |err| return mapError(err);
    const impl = handleAllocator().create(PreparedSceneImpl) catch {
        var doomed = prepared_scene;
        doomed.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = prepared_scene };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_prepared_scene_deinit(scene: ?*PreparedSceneImpl) void {
    if (scene) |s| {
        s.inner.deinit();
        destroyHandle(s);
    }
}

export fn snail_prepared_scene_word_count(scene: *const PreparedSceneImpl) usize {
    return scene.inner.words.len;
}

export fn snail_prepared_scene_segment_count(scene: *const PreparedSceneImpl) usize {
    return scene.inner.segments.len;
}

// Renderer

export fn snail_renderer_init(out: *?*RendererImpl) c_int {
    const renderer = snail.Renderer.init() catch return SNAIL_ERR_RENDERER_FAILED;
    const impl = handleAllocator().create(RendererImpl) catch {
        var doomed = renderer;
        doomed.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = renderer };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_renderer_deinit(renderer: ?*RendererImpl) void {
    if (renderer) |r| {
        r.inner.deinit();
        destroyHandle(r);
    }
}

export fn snail_renderer_begin_frame(renderer: *RendererImpl) void {
    renderer.inner.beginFrame();
}

export fn snail_renderer_set_subpixel_order(renderer: *RendererImpl, order: c_int) c_int {
    renderer.inner.setSubpixelOrder(toSubpixelOrder(order) catch return SNAIL_ERR_INVALID_ARGUMENT);
    return SNAIL_OK;
}

export fn snail_renderer_subpixel_order(renderer: *const RendererImpl) c_int {
    return @intFromEnum(renderer.inner.subpixelOrder());
}

export fn snail_renderer_set_fill_rule(renderer: *RendererImpl, rule: c_int) c_int {
    renderer.inner.setFillRule(toFillRule(rule) catch return SNAIL_ERR_INVALID_ARGUMENT);
    return SNAIL_OK;
}

export fn snail_renderer_fill_rule(renderer: *const RendererImpl) c_int {
    return @intFromEnum(renderer.inner.fillRule());
}

export fn snail_renderer_backend_name(renderer: *const RendererImpl) [*:0]const u8 {
    return @ptrCast(renderer.inner.backendName().ptr);
}

export fn snail_renderer_upload_resources_blocking(
    renderer: *RendererImpl,
    alloc_ptr: ?*const SnailAllocator,
    set: *const ResourceSetImpl,
    out: *?*PreparedResourcesImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const prepared = renderer.inner.uploadResourcesBlocking(allocator, &set.inner) catch |err| return mapError(err);
    const impl = handleAllocator().create(PreparedResourcesImpl) catch {
        var doomed = prepared;
        doomed.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = prepared };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_renderer_draw_prepared(
    renderer: *RendererImpl,
    prepared: *const PreparedResourcesImpl,
    scene: *const PreparedSceneImpl,
    options: SnailDrawOptions,
) c_int {
    renderer.inner.drawPrepared(&prepared.inner, &scene.inner, toDrawOptions(options) catch return SNAIL_ERR_INVALID_ARGUMENT) catch |err| return mapError(err);
    return SNAIL_OK;
}

// Compile-time features and constants

export fn snail_harfbuzz_available() bool {
    return build_options.enable_harfbuzz;
}

export fn snail_text_words_per_glyph() usize {
    return snail.lowlevel.TEXT_WORDS_PER_GLYPH;
}
export fn snail_text_words_per_vertex() usize {
    return snail.lowlevel.TEXT_WORDS_PER_VERTEX;
}
export fn snail_text_vertices_per_glyph() usize {
    return snail.lowlevel.TEXT_VERTICES_PER_GLYPH;
}
export fn snail_path_words_per_shape() usize {
    return snail.lowlevel.PATH_WORDS_PER_SHAPE;
}
export fn snail_path_words_per_vertex() usize {
    return snail.lowlevel.PATH_WORDS_PER_VERTEX;
}
export fn snail_path_vertices_per_shape() usize {
    return snail.lowlevel.PATH_VERTICES_PER_SHAPE;
}

export fn snail_mat4_identity() SnailMat4 {
    return fromMat4(snail.Mat4.identity);
}

// Tests

const testing = std.testing;

fn testTextAtlas() !*TextAtlasImpl {
    const assets = @import("assets");
    var atlas: ?*TextAtlasImpl = null;
    const spec = SnailFaceSpec{
        .data = assets.noto_sans_regular.ptr,
        .len = assets.noto_sans_regular.len,
    };
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_init(null, @ptrCast(&spec), 1, &atlas));
    return atlas.?;
}

fn ensureForText(atlas_ptr: **TextAtlasImpl, text: []const u8) !void {
    var next: ?*TextAtlasImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_ensure_text(atlas_ptr.*, .{}, text.ptr, text.len, &next));
    if (next) |replacement| {
        snail_text_atlas_deinit(atlas_ptr.*);
        atlas_ptr.* = replacement;
    }
}

test "c_api: font metrics helper" {
    const assets = @import("assets");
    var font: ?*FontImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_font_init(assets.noto_sans_regular.ptr, assets.noto_sans_regular.len, &font));
    defer snail_font_deinit(font);

    try testing.expect(snail_font_units_per_em(font.?) > 0);
    const gid = snail_font_glyph_index(font.?, 'A');
    try testing.expect(gid > 0);

    var metrics: SnailGlyphMetrics = undefined;
    try testing.expectEqual(SNAIL_OK, snail_font_glyph_metrics(font.?, gid, &metrics));
    try testing.expect(metrics.advance_width > 0);
}

test "c_api: text atlas shape ensure and blob" {
    var atlas = try testTextAtlas();
    defer snail_text_atlas_deinit(atlas);

    const text = "Hello";
    var shaped: ?*ShapedTextImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_shape_utf8(atlas, .{}, text.ptr, text.len, &shaped));
    defer snail_shaped_text_deinit(shaped);
    try testing.expectEqual(@as(usize, 5), snail_shaped_text_glyph_count(shaped.?));
    try testing.expect(snail_shaped_text_advance_x(shaped.?) > 0);

    var replacement: ?*TextAtlasImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_ensure_shaped(atlas, shaped.?, &replacement));
    if (replacement) |next| {
        snail_text_atlas_deinit(atlas);
        atlas = next;
    }

    var blob: ?*TextBlobImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_blob_init_from_shaped(null, atlas, shaped.?, .{
        .x = 10,
        .y = 20,
        .size = 24,
        .color = .{ 1, 1, 1, 1 },
    }, &blob));
    defer snail_text_blob_deinit(blob);
    try testing.expectEqual(@as(usize, 5), snail_text_blob_glyph_count(blob.?));
}

test "c_api: scene and resource set follow public model" {
    var atlas = try testTextAtlas();
    defer snail_text_atlas_deinit(atlas);
    try ensureForText(&atlas, "Hi");

    var blob: ?*TextBlobImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_blob_init_text(null, atlas, .{}, "Hi", 2, .{
        .x = 0,
        .y = 24,
        .size = 24,
        .color = .{ 1, 1, 1, 1 },
    }, &blob));
    defer snail_text_blob_deinit(blob);

    var scene: ?*SceneImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_scene_init(null, &scene));
    defer snail_scene_deinit(scene);
    try testing.expectEqual(SNAIL_OK, snail_scene_add_text(scene.?, blob.?));
    try testing.expectEqual(@as(usize, 1), snail_scene_command_count(scene.?));

    var resources: ?*ResourceSetImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_resource_set_init(null, 4, &resources));
    defer snail_resource_set_deinit(resources);
    try testing.expectEqual(SNAIL_OK, snail_resource_set_add_scene(resources.?, scene.?));
    try testing.expectEqual(@as(usize, 1), snail_resource_set_count(resources.?));
}

test "c_api: path picture builder" {
    var builder: ?*PathPictureBuilderImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_path_picture_builder_init(null, &builder));
    defer snail_path_picture_builder_deinit(builder);

    const fill = SnailFillStyle{ .color = .{ 0.1, 0.2, 0.3, 1 } };
    const stroke = SnailStrokeStyle{ .color = .{ 1, 1, 1, 1 }, .width = 2, .placement = 1 };
    try testing.expectEqual(SNAIL_OK, snail_path_picture_builder_add_rounded_rect(
        builder.?,
        .{ .x = 0, .y = 0, .w = 100, .h = 40 },
        &fill,
        &stroke,
        8,
        .{},
    ));

    var picture: ?*PathPictureImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_path_picture_builder_freeze(builder.?, null, &picture));
    defer snail_path_picture_deinit(picture);
    try testing.expectEqual(@as(usize, 1), snail_path_picture_shape_count(picture.?));
}

test "c_api: image paint init and constants" {
    var pixels = [_]u8{255} ** (4 * 4 * 4);
    var image: ?*ImageImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_image_init_srgba8(null, 4, 4, &pixels, &image));
    defer snail_image_deinit(image);
    try testing.expectEqual(@as(u32, 4), snail_image_width(image.?));
    try testing.expectEqual(@as(u32, 4), snail_image_height(image.?));

    try testing.expectEqual(snail.lowlevel.TEXT_WORDS_PER_GLYPH, snail_text_words_per_glyph());
    try testing.expectEqual(snail.lowlevel.TEXT_WORDS_PER_VERTEX, snail_text_words_per_vertex());
    try testing.expectEqual(snail.lowlevel.TEXT_VERTICES_PER_GLYPH, snail_text_vertices_per_glyph());
    try testing.expectEqual(snail.lowlevel.PATH_WORDS_PER_SHAPE, snail_path_words_per_shape());
    try testing.expectEqual(snail.lowlevel.PATH_WORDS_PER_VERTEX, snail_path_words_per_vertex());
    try testing.expectEqual(snail.lowlevel.PATH_VERTICES_PER_SHAPE, snail_path_vertices_per_shape());
}
