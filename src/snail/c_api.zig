//! C API for snail's public Zig resource model.
//! All exported functions use opaque handles and explicit ownership.

const std = @import("std");
const snail = @import("root.zig");
const resource_key = @import("resource_key.zig");
const ttf = @import("font/ttf.zig");
const build_options = @import("build_options");
const c_convert = @import("c_api/convert.zig");
const c_handles = @import("c_api/handles.zig");
const c_runtime = @import("c_api/runtime.zig");
const c_types = @import("c_api/types.zig");

const vk = c_types.vk;

const resolveAllocator = c_runtime.resolveAllocator;
const handleAllocator = c_runtime.handleAllocator;
const mapError = c_runtime.mapError;

pub const SnailAllocFn = c_types.SnailAllocFn;
pub const SnailFreeFn = c_types.SnailFreeFn;
pub const SnailAllocator = c_types.SnailAllocator;
pub const SNAIL_OK = c_types.SNAIL_OK;
pub const SNAIL_ERR_INVALID_FONT = c_types.SNAIL_ERR_INVALID_FONT;
pub const SNAIL_ERR_OUT_OF_MEMORY = c_types.SNAIL_ERR_OUT_OF_MEMORY;
pub const SNAIL_ERR_RENDERER_FAILED = c_types.SNAIL_ERR_RENDERER_FAILED;
pub const SNAIL_ERR_INVALID_ARGUMENT = c_types.SNAIL_ERR_INVALID_ARGUMENT;
pub const SNAIL_ERR_DRAW_FAILED = c_types.SNAIL_ERR_DRAW_FAILED;

pub const SnailVulkanContext = c_types.SnailVulkanContext;
pub const SnailBBox = c_types.SnailBBox;
pub const SnailGlyphMetrics = c_types.SnailGlyphMetrics;
pub const SnailLineMetrics = c_types.SnailLineMetrics;
pub const SnailDecorationMetrics = c_types.SnailDecorationMetrics;
pub const SnailScriptMetrics = c_types.SnailScriptMetrics;
pub const SnailScriptTransform = c_types.SnailScriptTransform;
pub const SnailCellMetrics = c_types.SnailCellMetrics;
pub const SnailRect = c_types.SnailRect;
pub const SnailMat4 = c_types.SnailMat4;
pub const SnailString = c_types.SnailString;
pub const SnailTransform2D = c_types.SnailTransform2D;
pub const SnailOverride = c_types.SnailOverride;
pub const SnailRange = c_types.SnailRange;
pub const SnailShapeMark = c_types.SnailShapeMark;
pub const SnailSyntheticStyle = c_types.SnailSyntheticStyle;
pub const SnailFaceSpec = c_types.SnailFaceSpec;
pub const SnailFontStyle = c_types.SnailFontStyle;
pub const SnailShapedGlyph = c_types.SnailShapedGlyph;
pub const SnailTextPlacement = c_types.SnailTextPlacement;
pub const SnailTextAppendOptions = c_types.SnailTextAppendOptions;
pub const SnailResolveTarget = c_types.SnailResolveTarget;
pub const SnailDrawOptions = c_types.SnailDrawOptions;
pub const SnailResourceKey = c_types.SnailResourceKey;
pub const SnailResourceStamp = c_types.SnailResourceStamp;
pub const SNAIL_RESOURCE_CAPACITY_GROWABLE = c_types.SNAIL_RESOURCE_CAPACITY_GROWABLE;
pub const SNAIL_RESOURCE_CAPACITY_EXACT = c_types.SNAIL_RESOURCE_CAPACITY_EXACT;
pub const SnailResourceFootprint = c_types.SnailResourceFootprint;
pub const SnailResourceCacheStats = c_types.SnailResourceCacheStats;
pub const SnailGlTextCoverageBindings = c_types.SnailGlTextCoverageBindings;
pub const SnailVulkanTextCoverageBindings = c_types.SnailVulkanTextCoverageBindings;
pub const SNAIL_PAINT_SOLID = c_types.SNAIL_PAINT_SOLID;
pub const SNAIL_PAINT_LINEAR = c_types.SNAIL_PAINT_LINEAR;
pub const SNAIL_PAINT_RADIAL = c_types.SNAIL_PAINT_RADIAL;
pub const SNAIL_PAINT_IMAGE = c_types.SNAIL_PAINT_IMAGE;
pub const SnailLinearGradient = c_types.SnailLinearGradient;
pub const SnailRadialGradient = c_types.SnailRadialGradient;
pub const SnailImagePaint = c_types.SnailImagePaint;
pub const SnailPaint = c_types.SnailPaint;
pub const SnailFillStyle = c_types.SnailFillStyle;
pub const SnailStrokeStyle = c_types.SnailStrokeStyle;

const wrapBBox = c_convert.wrapBBox;
const wrapString = c_convert.wrapString;
const wrapDecorationMetrics = c_convert.wrapDecorationMetrics;
const wrapScriptMetrics = c_convert.wrapScriptMetrics;
const wrapScriptTransform = c_convert.wrapScriptTransform;
const wrapResourceStamp = c_convert.wrapResourceStamp;
const toRect = c_convert.toRect;
const toSnailRect = c_convert.toSnailRect;
const fromMat4 = c_convert.fromMat4;
const toTransform = c_convert.toTransform;
const toOverride = c_convert.toOverride;
const toGlCoverageBindings = c_convert.toGlCoverageBindings;
const toVulkanCoverageBindings = c_convert.toVulkanCoverageBindings;
const fromResourceFootprint = c_convert.fromResourceFootprint;
const fromResourceCacheStats = c_convert.fromResourceCacheStats;
const toResourceCapacityMode = c_convert.toResourceCapacityMode;
const reservedResourceCapacityMode = c_convert.reservedResourceCapacityMode;
const toRange = c_convert.toRange;
const fromRange = c_convert.fromRange;
const toShapeMark = c_convert.toShapeMark;
const fromShapeMark = c_convert.fromShapeMark;
const toSyntheticStyle = c_convert.toSyntheticStyle;
const toFontWeight = c_convert.toFontWeight;
const toFontStyle = c_convert.toFontStyle;
const toDecoration = c_convert.toDecoration;
const toTextPlacement = c_convert.toTextPlacement;
const toDrawOptions = c_convert.toDrawOptions;
const toPaint = c_convert.toPaint;
const toFillStyle = c_convert.toFillStyle;
const toStrokeStyle = c_convert.toStrokeStyle;
const toOptFill = c_convert.toOptFill;
const toOptStroke = c_convert.toOptStroke;

// Opaque handle implementations

const FontImpl = c_handles.FontImpl;
const TextAtlasImpl = c_handles.TextAtlasImpl;
const ShapedTextImpl = c_handles.ShapedTextImpl;
const TextBlobImpl = c_handles.TextBlobImpl;
const ImageImpl = c_handles.ImageImpl;
const PathImpl = c_handles.PathImpl;
const PathPictureBuilderImpl = c_handles.PathPictureBuilderImpl;
const PathPictureImpl = c_handles.PathPictureImpl;
const SceneImpl = c_handles.SceneImpl;
const ResourceSetImpl = c_handles.ResourceSetImpl;
const PreparedResourcesImpl = c_handles.PreparedResourcesImpl;
const PreparedSceneImpl = c_handles.PreparedSceneImpl;
const PreparedResourceRetirementQueueImpl = c_handles.PreparedResourceRetirementQueueImpl;
const ResourceUploadPlanImpl = c_handles.ResourceUploadPlanImpl;
const PendingResourceUploadImpl = c_handles.PendingResourceUploadImpl;
const DrawListImpl = c_handles.DrawListImpl;
const TextCoverageRecordsImpl = c_handles.TextCoverageRecordsImpl;
const CoverageBackendImpl = c_handles.CoverageBackendImpl;
const ThreadPoolImpl = c_handles.ThreadPoolImpl;
const RendererImpl = c_handles.RendererImpl;

export fn snail_resource_footprint_used_bytes(footprint: SnailResourceFootprint) usize {
    return footprint.curve_bytes_used +
        footprint.band_bytes_used +
        footprint.layer_info_bytes_used +
        footprint.image_bytes_used;
}

export fn snail_resource_footprint_allocated_bytes(footprint: SnailResourceFootprint) usize {
    return footprint.curve_bytes_allocated +
        footprint.band_bytes_allocated +
        footprint.layer_info_bytes_allocated +
        footprint.image_bytes_allocated;
}

export fn snail_resource_key_from_bytes(data: [*]const u8, len: usize) SnailResourceKey {
    return resource_key.hashBytes(data[0..len]);
}

export fn snail_resource_key_from_cstr(data: [*:0]const u8) SnailResourceKey {
    return resource_key.hashBytes(std.mem.span(data));
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

export fn snail_font_decoration_metrics(font: *const FontImpl, out: *SnailDecorationMetrics) c_int {
    out.* = wrapDecorationMetrics(font.inner.decorationMetrics() catch return SNAIL_ERR_INVALID_FONT);
    return SNAIL_OK;
}

export fn snail_font_superscript_metrics(font: *const FontImpl, out: *SnailScriptMetrics) c_int {
    out.* = wrapScriptMetrics(font.inner.superscriptMetrics() catch return SNAIL_ERR_INVALID_FONT);
    return SNAIL_OK;
}

export fn snail_font_subscript_metrics(font: *const FontImpl, out: *SnailScriptMetrics) c_int {
    out.* = wrapScriptMetrics(font.inner.subscriptMetrics() catch return SNAIL_ERR_INVALID_FONT);
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

export fn snail_text_atlas_upload_footprint(atlas: *const TextAtlasImpl, out: *SnailResourceFootprint) void {
    out.* = fromResourceFootprint(atlas.inner.uploadFootprint());
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

export fn snail_text_atlas_face_count(atlas: *const TextAtlasImpl) usize {
    return atlas.inner.faceCount();
}

export fn snail_text_atlas_primary_face_index(atlas: *const TextAtlasImpl, out: *u16) c_int {
    out.* = atlas.inner.primaryFaceIndex() catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_text_atlas_face_units_per_em(atlas: *const TextAtlasImpl, face_index: usize, out: *u16) c_int {
    out.* = atlas.inner.faceUnitsPerEm(face_index) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_text_atlas_face_line_metrics(atlas: *const TextAtlasImpl, face_index: usize, out: *SnailLineMetrics) c_int {
    const m = atlas.inner.faceLineMetrics(face_index) catch |err| return mapError(err);
    out.* = .{ .ascent = m.ascent, .descent = m.descent, .line_gap = m.line_gap };
    return SNAIL_OK;
}

export fn snail_text_atlas_glyph_index(atlas: *const TextAtlasImpl, face_index: usize, codepoint: u32, out: *u16) c_int {
    const cp = std.math.cast(u21, codepoint) orelse return SNAIL_ERR_INVALID_ARGUMENT;
    out.* = (atlas.inner.glyphIndex(face_index, cp) catch |err| return mapError(err)) orelse 0;
    return SNAIL_OK;
}

export fn snail_text_atlas_advance_width(atlas: *const TextAtlasImpl, face_index: usize, glyph_id: u16, out: *i16) c_int {
    out.* = atlas.inner.advanceWidth(face_index, glyph_id) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_text_atlas_cell_metrics(atlas: *const TextAtlasImpl, style: SnailFontStyle, em: f32, out: *SnailCellMetrics) c_int {
    const metrics = atlas.inner.cellMetrics(.{
        .style = toFontStyle(style) catch return SNAIL_ERR_INVALID_ARGUMENT,
        .em = em,
    }) catch |err| return mapError(err);
    out.* = .{ .cell_width = metrics.cell_width, .line_height = metrics.line_height };
    return SNAIL_OK;
}

export fn snail_text_atlas_measure_text(
    atlas: *const TextAtlasImpl,
    style: SnailFontStyle,
    text: [*]const u8,
    text_len: usize,
    font_size: f32,
    out: *f32,
) c_int {
    out.* = atlas.inner.measureText(toFontStyle(style) catch return SNAIL_ERR_INVALID_ARGUMENT, text[0..text_len], font_size) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_text_atlas_decoration_rect(
    atlas: *const TextAtlasImpl,
    decoration: c_int,
    x: f32,
    y: f32,
    advance: f32,
    font_size: f32,
    out: *SnailRect,
) c_int {
    out.* = toSnailRect(atlas.inner.decorationRect(toDecoration(decoration) catch return SNAIL_ERR_INVALID_ARGUMENT, x, y, advance, font_size) catch |err| return mapError(err));
    return SNAIL_OK;
}

export fn snail_text_atlas_superscript_transform(atlas: *const TextAtlasImpl, x: f32, y: f32, font_size: f32, out: *SnailScriptTransform) c_int {
    out.* = wrapScriptTransform(atlas.inner.superscriptTransform(x, y, font_size) catch |err| return mapError(err));
    return SNAIL_OK;
}

export fn snail_text_atlas_subscript_transform(atlas: *const TextAtlasImpl, x: f32, y: f32, font_size: f32, out: *SnailScriptTransform) c_int {
    out.* = wrapScriptTransform(atlas.inner.subscriptTransform(x, y, font_size) catch |err| return mapError(err));
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

export fn snail_text_atlas_ensure_glyphs(
    atlas: *const TextAtlasImpl,
    face_index: usize,
    glyph_ids: ?[*]const u16,
    glyph_count: usize,
    out: *?*TextAtlasImpl,
) c_int {
    if (glyph_count > 0 and glyph_ids == null) return SNAIL_ERR_INVALID_ARGUMENT;
    const gids = if (glyph_count == 0) &.{} else glyph_ids.?[0..glyph_count];
    const next = atlas.inner.ensureGlyphs(face_index, gids) catch |err| return mapError(err);
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
    options: SnailTextAppendOptions,
    out: *?*TextBlobImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const blob = snail.TextBlob.init(allocator, &atlas.inner, .{
        .shaped = &shaped.inner,
        .placement = toTextPlacement(options.placement),
        .fill = toPaint(options.fill) catch return SNAIL_ERR_INVALID_ARGUMENT,
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
    options: SnailTextAppendOptions,
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

export fn snail_text_blob_rebound(
    alloc_ptr: ?*const SnailAllocator,
    blob: *const TextBlobImpl,
    atlas: *const TextAtlasImpl,
    out: *?*TextBlobImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const rebound = blob.inner.rebound(allocator, &atlas.inner) catch |err| return mapError(err);
    const impl = handleAllocator().create(TextBlobImpl) catch {
        var doomed = rebound;
        doomed.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = rebound };
    out.* = impl;
    return SNAIL_OK;
}

// Image

export fn snail_image_init_srgba8(
    alloc_ptr: ?*const SnailAllocator,
    width: u32,
    height: u32,
    pixels: ?[*]const u8,
    pixel_len: usize,
    out: *?*ImageImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const px_count = std.math.mul(usize, width, height) catch return SNAIL_ERR_INVALID_ARGUMENT;
    const byte_count = std.math.mul(usize, px_count, 4) catch return SNAIL_ERR_INVALID_ARGUMENT;
    if (pixel_len != byte_count) return SNAIL_ERR_INVALID_ARGUMENT;
    const pixel_ptr = pixels orelse return SNAIL_ERR_INVALID_ARGUMENT;
    const img = snail.Image.initSrgba8(allocator, width, height, pixel_ptr[0..pixel_len]) catch |err| return mapError(err);
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

export fn snail_image_upload_footprint(image: *const ImageImpl, out: *SnailResourceFootprint) void {
    out.* = fromResourceFootprint(image.inner.uploadFootprint());
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
    path.inner.moveTo(.{ .x = x, .y = y }) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_line_to(path: *PathImpl, x: f32, y: f32) c_int {
    path.inner.lineTo(.{ .x = x, .y = y }) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_quad_to(path: *PathImpl, cx: f32, cy: f32, x: f32, y: f32) c_int {
    path.inner.quadTo(.{ .x = cx, .y = cy }, .{ .x = x, .y = y }) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_cubic_to(path: *PathImpl, c1x: f32, c1y: f32, c2x: f32, c2y: f32, x: f32, y: f32) c_int {
    path.inner.cubicTo(.{ .x = c1x, .y = c1y }, .{ .x = c2x, .y = c2y }, .{ .x = x, .y = y }) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_close(path: *PathImpl) c_int {
    path.inner.close() catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_add_rect(path: *PathImpl, rect: SnailRect) c_int {
    path.inner.addRect(toRect(rect)) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_add_rect_reversed(path: *PathImpl, rect: SnailRect) c_int {
    path.inner.addRectReversed(toRect(rect)) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_add_rounded_rect(path: *PathImpl, rect: SnailRect, corner_radius: f32) c_int {
    path.inner.addRoundedRect(toRect(rect), corner_radius) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_add_rounded_rect_reversed(path: *PathImpl, rect: SnailRect, corner_radius: f32) c_int {
    path.inner.addRoundedRectReversed(toRect(rect), corner_radius) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_add_ellipse(path: *PathImpl, rect: SnailRect) c_int {
    path.inner.addEllipse(toRect(rect)) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_path_add_ellipse_reversed(path: *PathImpl, rect: SnailRect) c_int {
    path.inner.addEllipseReversed(toRect(rect)) catch |err| return mapError(err);
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

export fn snail_path_picture_builder_freeze(builder: *const PathPictureBuilderImpl, alloc_ptr: ?*const SnailAllocator, scratch_alloc_ptr: ?*const SnailAllocator, out: *?*PathPictureImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const scratch_allocator = resolveAllocator(scratch_alloc_ptr);
    var picture = builder.inner.freeze(.{
        .persistent_allocator = allocator,
        .scratch_allocator = scratch_allocator,
    }) catch |err| return mapError(err);
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

export fn snail_path_picture_upload_footprint(picture: *const PathPictureImpl, out: *SnailResourceFootprint) void {
    out.* = fromResourceFootprint(picture.inner.uploadFootprint());
}

export fn snail_path_picture_builder_shape_count(builder: *const PathPictureBuilderImpl) usize {
    return builder.inner.shapeCount();
}

export fn snail_path_picture_builder_mark(builder: *const PathPictureBuilderImpl) SnailShapeMark {
    return fromShapeMark(builder.inner.mark());
}

export fn snail_path_picture_builder_range_from(builder: *const PathPictureBuilderImpl, mark: SnailShapeMark, out: *SnailRange) c_int {
    out.* = fromRange(builder.inner.rangeFrom(toShapeMark(mark)) catch |err| return mapError(err));
    return SNAIL_OK;
}

export fn snail_path_picture_builder_range_between(builder: *const PathPictureBuilderImpl, start: SnailShapeMark, end: SnailShapeMark, out: *SnailRange) c_int {
    out.* = fromRange(builder.inner.rangeBetween(toShapeMark(start), toShapeMark(end)) catch |err| return mapError(err));
    return SNAIL_OK;
}

// Scene and resources

export fn snail_scene_init(alloc_ptr: ?*const SnailAllocator, out: *?*SceneImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const impl = handleAllocator().create(SceneImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.* = .{
        .inner = snail.Scene.init(allocator),
        .overrides_arena = std.heap.ArenaAllocator.init(allocator),
    };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_scene_deinit(scene: ?*SceneImpl) void {
    if (scene) |s| {
        s.inner.deinit();
        s.overrides_arena.deinit();
        destroyHandle(s);
    }
}

export fn snail_scene_reset(scene: *SceneImpl) void {
    scene.inner.reset();
    _ = scene.overrides_arena.reset(.retain_capacity);
}

export fn snail_scene_command_count(scene: *const SceneImpl) usize {
    return scene.inner.commandCount();
}

fn stashOverride(scene: *SceneImpl, override: snail.Override) ![]const snail.Override {
    const slot = try scene.overrides_arena.allocator().alloc(snail.Override, 1);
    slot[0] = override;
    return slot;
}

export fn snail_scene_add_text(scene: *SceneImpl, blob: *const TextBlobImpl) c_int {
    scene.inner.addText(.{ .blob = &blob.inner }) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_scene_add_text_transformed(scene: *SceneImpl, blob: *const TextBlobImpl, transform: SnailTransform2D) c_int {
    return snail_scene_add_text_override(scene, blob, .{ .transform = transform });
}

export fn snail_scene_add_text_override(scene: *SceneImpl, blob: *const TextBlobImpl, override_value: SnailOverride) c_int {
    const instances = stashOverride(scene, toOverride(override_value)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    scene.inner.addText(.{
        .blob = &blob.inner,
        .instances = instances,
    }) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_scene_add_path_picture(scene: *SceneImpl, picture: *const PathPictureImpl) c_int {
    scene.inner.addPath(.{ .picture = &picture.inner }) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_scene_add_path_picture_range(scene: *SceneImpl, picture: *const PathPictureImpl, range: SnailRange) c_int {
    scene.inner.addPath(.{
        .picture = &picture.inner,
        .shapes = toRange(range),
    }) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_scene_add_path_picture_transformed(scene: *SceneImpl, picture: *const PathPictureImpl, transform: SnailTransform2D) c_int {
    return snail_scene_add_path_picture_override(scene, picture, .{ .transform = transform });
}

export fn snail_scene_add_path_picture_range_transformed(scene: *SceneImpl, picture: *const PathPictureImpl, range: SnailRange, transform: SnailTransform2D) c_int {
    return snail_scene_add_path_picture_range_override(scene, picture, range, .{ .transform = transform });
}

export fn snail_scene_add_path_picture_override(scene: *SceneImpl, picture: *const PathPictureImpl, override_value: SnailOverride) c_int {
    const instances = stashOverride(scene, toOverride(override_value)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    scene.inner.addPath(.{ .picture = &picture.inner, .instances = instances }) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_scene_add_path_picture_range_override(scene: *SceneImpl, picture: *const PathPictureImpl, range: SnailRange, override_value: SnailOverride) c_int {
    const instances = stashOverride(scene, toOverride(override_value)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    scene.inner.addPath(.{
        .picture = &picture.inner,
        .shapes = toRange(range),
        .instances = instances,
    }) catch |err| return mapError(err);
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
    set.inner.putTextAtlas(snail.ResourceKey.fromId(key), &atlas.inner) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_resource_set_put_text_atlas_options(set: *ResourceSetImpl, key: SnailResourceKey, atlas: *const TextAtlasImpl, atlas_capacity: c_int) c_int {
    set.inner.putTextAtlasOptions(snail.ResourceKey.fromId(key), &atlas.inner, .{
        .atlas_capacity = toResourceCapacityMode(atlas_capacity) catch return SNAIL_ERR_INVALID_ARGUMENT,
    }) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_resource_set_put_text_atlas_reserved(set: *ResourceSetImpl, key: SnailResourceKey, atlas: *const TextAtlasImpl, reserved_pages: u32) c_int {
    set.inner.putTextAtlasOptions(snail.ResourceKey.fromId(key), &atlas.inner, .{
        .atlas_capacity = reservedResourceCapacityMode(reserved_pages),
    }) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_resource_set_put_path_picture(set: *ResourceSetImpl, key: SnailResourceKey, picture: *const PathPictureImpl) c_int {
    set.inner.putPathPicture(snail.ResourceKey.fromId(key), &picture.inner) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_resource_set_put_path_picture_options(set: *ResourceSetImpl, key: SnailResourceKey, picture: *const PathPictureImpl, atlas_capacity: c_int) c_int {
    set.inner.putPathPictureOptions(snail.ResourceKey.fromId(key), &picture.inner, .{
        .atlas_capacity = toResourceCapacityMode(atlas_capacity) catch return SNAIL_ERR_INVALID_ARGUMENT,
    }) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_resource_set_put_path_picture_reserved(set: *ResourceSetImpl, key: SnailResourceKey, picture: *const PathPictureImpl, reserved_pages: u32) c_int {
    set.inner.putPathPictureOptions(snail.ResourceKey.fromId(key), &picture.inner, .{
        .atlas_capacity = reservedResourceCapacityMode(reserved_pages),
    }) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_resource_set_put_image(set: *ResourceSetImpl, key: SnailResourceKey, image: *const ImageImpl) c_int {
    set.inner.putImage(snail.ResourceKey.fromId(key), &image.inner) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_resource_set_estimate_upload_footprint(set: *const ResourceSetImpl, out: *SnailResourceFootprint) c_int {
    out.* = fromResourceFootprint(set.inner.estimateUploadFootprint() catch |err| return mapError(err));
    return SNAIL_OK;
}

export fn snail_resource_set_add_scene(set: *ResourceSetImpl, scene: *const SceneImpl) c_int {
    set.inner.addScene(&scene.inner) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_prepared_resources_deinit(prepared: ?*PreparedResourcesImpl) void {
    if (prepared) |p| {
        p.inner.deinit();
        destroyHandle(p);
    }
}

export fn snail_prepared_resources_stamp_for_key(prepared: *const PreparedResourcesImpl, key: SnailResourceKey, out: *SnailResourceStamp) bool {
    if (prepared.inner.stampForKey(snail.ResourceKey.fromId(key))) |stamp| {
        out.* = wrapResourceStamp(stamp);
        return true;
    }
    return false;
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

export fn snail_prepared_resource_retirement_queue_init(alloc_ptr: ?*const SnailAllocator, out: *?*PreparedResourceRetirementQueueImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const impl = handleAllocator().create(PreparedResourceRetirementQueueImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.* = .{ .inner = snail.PreparedResourceRetirementQueue.init(allocator), .allocator = allocator };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_prepared_resource_retirement_queue_deinit(queue: ?*PreparedResourceRetirementQueueImpl) void {
    if (queue) |q| {
        q.inner.deinit();
        destroyHandle(q);
    }
}

export fn snail_prepared_resource_retirement_queue_sweep(queue: *PreparedResourceRetirementQueueImpl) void {
    queue.inner.sweep();
}

export fn snail_prepared_resource_retirement_queue_retire(queue: *PreparedResourceRetirementQueueImpl, prepared: *PreparedResourcesImpl) c_int {
    queue.inner.retireAfter(&prepared.inner, {}) catch |err| return mapError(err);
    destroyHandle(prepared);
    return SNAIL_OK;
}

export fn snail_draw_list_estimate_word_count(scene: *const SceneImpl, options: SnailDrawOptions) usize {
    return snail.DrawList.estimate(&scene.inner, toDrawOptions(options) catch return 0);
}

export fn snail_draw_list_estimate_segment_count(scene: *const SceneImpl, options: SnailDrawOptions) usize {
    return snail.DrawList.estimateSegments(&scene.inner, toDrawOptions(options) catch return 0);
}

export fn snail_draw_list_init(alloc_ptr: ?*const SnailAllocator, word_capacity: usize, segment_capacity: usize, out: *?*DrawListImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const words = allocator.alloc(u32, word_capacity) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const segments = allocator.alloc(snail.DrawSegment, segment_capacity) catch {
        allocator.free(words);
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    const impl = handleAllocator().create(DrawListImpl) catch {
        allocator.free(segments);
        allocator.free(words);
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{
        .inner = snail.DrawList.init(words, segments),
        .allocator = allocator,
        .words = words,
        .segments = segments,
    };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_draw_list_deinit(list: ?*DrawListImpl) void {
    if (list) |l| {
        l.allocator.free(l.words);
        l.allocator.free(l.segments);
        destroyHandle(l);
    }
}

export fn snail_draw_list_reset(list: *DrawListImpl) void {
    list.inner.reset();
}

export fn snail_draw_list_word_count(list: *const DrawListImpl) usize {
    return list.inner.len;
}

export fn snail_draw_list_word_capacity(list: *const DrawListImpl) usize {
    return list.words.len;
}

export fn snail_draw_list_segment_count(list: *const DrawListImpl) usize {
    return list.inner.segment_len;
}

export fn snail_draw_list_segment_capacity(list: *const DrawListImpl) usize {
    return list.segments.len;
}

export fn snail_draw_list_words(list: *const DrawListImpl) ?[*]const u32 {
    if (list.inner.len == 0) return null;
    return list.words.ptr;
}

export fn snail_draw_list_add_scene(list: *DrawListImpl, prepared: *const PreparedResourcesImpl, scene: *const SceneImpl, options: SnailDrawOptions) c_int {
    list.inner.addScene(&prepared.inner, &scene.inner, toDrawOptions(options) catch return SNAIL_ERR_INVALID_ARGUMENT) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_text_coverage_records_word_capacity_for_blob(blob: *const TextBlobImpl) usize {
    return snail.coverage.TextCoverageRecords.wordCapacityForBlob(&blob.inner);
}

export fn snail_text_coverage_records_init(alloc_ptr: ?*const SnailAllocator, word_capacity: usize, out: *?*TextCoverageRecordsImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const words = allocator.alloc(u32, word_capacity) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const impl = handleAllocator().create(TextCoverageRecordsImpl) catch {
        allocator.free(words);
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{
        .inner = snail.coverage.TextCoverageRecords.init(words),
        .allocator = allocator,
        .words = words,
    };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_text_coverage_records_deinit(records: ?*TextCoverageRecordsImpl) void {
    if (records) |r| {
        r.allocator.free(r.words);
        destroyHandle(r);
    }
}

export fn snail_text_coverage_records_reset(records: *TextCoverageRecordsImpl) void {
    records.inner.reset();
}

export fn snail_text_coverage_records_word_count(records: *const TextCoverageRecordsImpl) usize {
    return records.inner.slice().len;
}

export fn snail_text_coverage_records_glyph_count(records: *const TextCoverageRecordsImpl) usize {
    return records.inner.glyphCount();
}

export fn snail_text_coverage_records_words(records: *const TextCoverageRecordsImpl) ?[*]const u32 {
    if (records.inner.len == 0) return null;
    return records.words.ptr;
}

export fn snail_text_coverage_records_build_local(records: *TextCoverageRecordsImpl, prepared: *const PreparedResourcesImpl, blob: *const TextBlobImpl, transform: SnailTransform2D) c_int {
    records.inner.buildLocal(&prepared.inner, &blob.inner, .{ .transform = toTransform(transform) }) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_text_coverage_records_valid_for(records: *const TextCoverageRecordsImpl, prepared: *const PreparedResourcesImpl) bool {
    return records.inner.validFor(&prepared.inner);
}

fn coverageBackendPrepared(backend: *const CoverageBackendImpl) ?*const snail.PreparedResources {
    return switch (backend.inner) {
        .gl => |gl_backend| if (comptime build_options.enable_opengl) gl_backend.prepared else null,
        .vulkan => |vk_backend| if (comptime build_options.enable_vulkan) vk_backend.prepared else null,
        .cpu => null,
    };
}

export fn snail_coverage_backend_init(renderer: *RendererImpl, prepared: *const PreparedResourcesImpl, out: *?*CoverageBackendImpl) c_int {
    var erased = renderer.asRenderer();
    const backend = prepared.inner.coverageBackend(&erased) orelse return SNAIL_ERR_INVALID_ARGUMENT;
    const impl = handleAllocator().create(CoverageBackendImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.* = .{ .inner = backend };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_coverage_backend_deinit(backend: ?*CoverageBackendImpl) void {
    if (backend) |b| destroyHandle(b);
}

export fn snail_coverage_backend_draw_coverage(backend: *CoverageBackendImpl, records: *const TextCoverageRecordsImpl) c_int {
    const prepared = coverageBackendPrepared(backend) orelse return SNAIL_ERR_INVALID_ARGUMENT;
    if (!records.inner.validFor(prepared)) return SNAIL_ERR_DRAW_FAILED;
    backend.inner.drawCoverage(&records.inner);
    return SNAIL_OK;
}

export fn snail_coverage_backend_draw_words(backend: *CoverageBackendImpl, words: ?[*]const u32, word_count: usize) c_int {
    if (coverageBackendPrepared(backend) == null) return SNAIL_ERR_INVALID_ARGUMENT;
    if (word_count == 0) {
        backend.inner.drawVertices(&.{});
        return SNAIL_OK;
    }
    const word_ptr = words orelse return SNAIL_ERR_INVALID_ARGUMENT;
    backend.inner.drawVertices(word_ptr[0..word_count]);
    return SNAIL_OK;
}

// Renderer

fn cpuPixels(pixels: ?[*]u8, width: u32, height: u32, stride: u32) ?[*]u8 {
    const ptr = pixels orelse return null;
    if (width == 0 or height == 0) return null;
    const min_stride = std.math.mul(u32, width, 4) catch return null;
    if (stride < min_stride) return null;
    return ptr;
}

export fn snail_gl_renderer_init(out: *?*RendererImpl) c_int {
    if (comptime build_options.enable_opengl) {
        const gl = snail.GlRenderer.init(handleAllocator()) catch return SNAIL_ERR_RENDERER_FAILED;
        const impl = handleAllocator().create(RendererImpl) catch {
            var doomed = gl;
            doomed.deinit();
            return SNAIL_ERR_OUT_OF_MEMORY;
        };
        impl.* = .{ .backend = .gl, .gl = gl };
        out.* = impl;
        return SNAIL_OK;
    } else {
        return SNAIL_ERR_RENDERER_FAILED;
    }
}

export fn snail_cpu_available() bool {
    return build_options.enable_cpu;
}

fn mapThreadPoolInitError(err: anyerror) c_int {
    return switch (err) {
        error.OutOfMemory => SNAIL_ERR_OUT_OF_MEMORY,
        else => SNAIL_ERR_RENDERER_FAILED,
    };
}

fn initThreadPool(
    alloc_ptr: ?*const SnailAllocator,
    worker_count: ?usize,
    out: *?*ThreadPoolImpl,
) c_int {
    if (comptime !build_options.enable_cpu) return SNAIL_ERR_RENDERER_FAILED;
    const allocator = resolveAllocator(alloc_ptr);
    const impl = handleAllocator().create(ThreadPoolImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.inner.init(allocator, .{ .threads = worker_count }) catch |err| {
        handleAllocator().destroy(impl);
        return mapThreadPoolInitError(err);
    };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_thread_pool_init(
    alloc_ptr: ?*const SnailAllocator,
    out: *?*ThreadPoolImpl,
) c_int {
    return initThreadPool(alloc_ptr, null, out);
}

export fn snail_thread_pool_init_with_threads(
    alloc_ptr: ?*const SnailAllocator,
    worker_count: usize,
    out: *?*ThreadPoolImpl,
) c_int {
    return initThreadPool(alloc_ptr, worker_count, out);
}

export fn snail_thread_pool_deinit(pool: ?*ThreadPoolImpl) void {
    if (pool) |p| {
        p.inner.deinit();
        destroyHandle(p);
    }
}

export fn snail_thread_pool_thread_count(pool: *const ThreadPoolImpl) usize {
    return pool.inner.threadCount();
}

export fn snail_cpu_renderer_init(pixels: ?[*]u8, width: u32, height: u32, stride: u32, out: *?*RendererImpl) c_int {
    if (comptime build_options.enable_cpu) {
        const pixel_ptr = cpuPixels(pixels, width, height, stride) orelse return SNAIL_ERR_INVALID_ARGUMENT;
        const cpu = snail.CpuRenderer.init(pixel_ptr, width, height, stride);
        const impl = handleAllocator().create(RendererImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
        impl.* = .{ .backend = .cpu, .cpu = cpu };
        out.* = impl;
        return SNAIL_OK;
    } else {
        return SNAIL_ERR_RENDERER_FAILED;
    }
}

export fn snail_cpu_renderer_reinit_buffer(renderer: *RendererImpl, pixels: ?[*]u8, width: u32, height: u32, stride: u32) c_int {
    if (comptime !build_options.enable_cpu) return SNAIL_ERR_RENDERER_FAILED;
    if (renderer.backend != .cpu) return SNAIL_ERR_INVALID_ARGUMENT;
    const pixel_ptr = cpuPixels(pixels, width, height, stride) orelse return SNAIL_ERR_INVALID_ARGUMENT;
    if (renderer.cpu) |*cpu| {
        cpu.reinitBuffer(pixel_ptr, width, height, stride);
        return SNAIL_OK;
    }
    return SNAIL_ERR_INVALID_ARGUMENT;
}

export fn snail_cpu_renderer_set_thread_pool(renderer: *RendererImpl, pool: ?*ThreadPoolImpl) c_int {
    if (comptime !build_options.enable_cpu) return SNAIL_ERR_RENDERER_FAILED;
    if (renderer.backend != .cpu) return SNAIL_ERR_INVALID_ARGUMENT;
    if (renderer.cpu) |*cpu| {
        cpu.setThreadPool(if (pool) |p| &p.inner else null);
        return SNAIL_OK;
    }
    return SNAIL_ERR_INVALID_ARGUMENT;
}

export fn snail_vulkan_available() bool {
    return build_options.enable_vulkan;
}

export fn snail_vulkan_renderer_init(ctx: *const SnailVulkanContext, out: *?*RendererImpl) c_int {
    if (comptime build_options.enable_vulkan) {
        const vk_ctx = snail.VulkanContext{
            .physical_device = ctx.physical_device,
            .device = ctx.device,
            .graphics_queue = ctx.graphics_queue,
            .queue_family_index = ctx.queue_family_index,
            .render_pass = ctx.render_pass,
            .color_format = ctx.color_format,
            .supports_dual_source_blend = ctx.supports_dual_source_blend,
        };
        const vk_renderer = snail.VulkanRenderer.init(handleAllocator(), vk_ctx) catch return SNAIL_ERR_RENDERER_FAILED;
        const impl = handleAllocator().create(RendererImpl) catch {
            var doomed = vk_renderer;
            doomed.deinit();
            return SNAIL_ERR_OUT_OF_MEMORY;
        };
        impl.* = .{ .backend = .vulkan, .vulkan = vk_renderer };
        out.* = impl;
        return SNAIL_OK;
    } else {
        return SNAIL_ERR_RENDERER_FAILED;
    }
}

export fn snail_vulkan_renderer_begin_frame(renderer: *RendererImpl, command_buffer: vk.VkCommandBuffer, frame_slot: u32) c_int {
    if (comptime !build_options.enable_vulkan) return SNAIL_ERR_RENDERER_FAILED;
    if (renderer.backend != .vulkan) return SNAIL_ERR_INVALID_ARGUMENT;
    if (renderer.vulkan) |*vk_renderer| {
        vk_renderer.beginFrame(.{ .cmd = command_buffer, .frame_index = frame_slot });
        return SNAIL_OK;
    }
    return SNAIL_ERR_INVALID_ARGUMENT;
}

export fn snail_vulkan_pending_resource_upload_record(pending: *PendingResourceUploadImpl, command_buffer: vk.VkCommandBuffer, budget_bytes: usize) c_int {
    if (comptime !build_options.enable_vulkan) return SNAIL_ERR_RENDERER_FAILED;
    pending.inner.record(.{ .vulkan = command_buffer }, .{ .budget_bytes = budget_bytes }) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_vulkan_pending_resource_upload_record_checked(pending: *PendingResourceUploadImpl, command_buffer: vk.VkCommandBuffer, budget_bytes: usize, allow_cache_rebuilds: bool) c_int {
    if (comptime !build_options.enable_vulkan) return SNAIL_ERR_RENDERER_FAILED;
    pending.inner.record(.{ .vulkan = command_buffer }, .{
        .budget_bytes = budget_bytes,
        .allow_cache_rebuilds = allow_cache_rebuilds,
    }) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_vulkan_pending_resource_upload_ready_fence(pending: *PendingResourceUploadImpl, fence: vk.VkFence) bool {
    if (comptime !build_options.enable_vulkan) return false;
    return pending.inner.ready(.{ .vulkan_fence = fence });
}

export fn snail_vulkan_prepared_resource_retirement_queue_retire_after(queue: *PreparedResourceRetirementQueueImpl, prepared: *PreparedResourcesImpl, fence: vk.VkFence) c_int {
    if (comptime !build_options.enable_vulkan) return SNAIL_ERR_RENDERER_FAILED;
    queue.inner.retireAfter(&prepared.inner, fence) catch |err| return mapError(err);
    destroyHandle(prepared);
    return SNAIL_OK;
}

export fn snail_gl_coverage_shader_vertex_interface() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.vertex_interface);
}

export fn snail_gl_coverage_shader_fragment_interface() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.fragment_interface);
}

export fn snail_gl_coverage_shader_resource_interface() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.resource_interface);
}

export fn snail_gl_coverage_shader_coverage_functions() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.coverage_functions);
}

export fn snail_gl_coverage_shader_sample_interface() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.sample_interface);
}

export fn snail_gl_coverage_shader_sample_functions() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.sample_functions);
}

export fn snail_gl_coverage_shader_fragment_body() SnailString {
    if (comptime !build_options.enable_opengl) return wrapString("");
    return wrapString(snail.coverage.Shader.gl.fragment_body);
}

export fn snail_gl_coverage_backend_bind_resources(backend: *CoverageBackendImpl, bindings: SnailGlTextCoverageBindings) c_int {
    if (comptime !build_options.enable_opengl) return SNAIL_ERR_RENDERER_FAILED;
    switch (backend.inner) {
        .gl => |gl_backend| {
            gl_backend.bindResources(toGlCoverageBindings(bindings) catch return SNAIL_ERR_INVALID_ARGUMENT);
            return SNAIL_OK;
        },
        else => return SNAIL_ERR_INVALID_ARGUMENT,
    }
}

export fn snail_vulkan_coverage_shader_vertex_shader() SnailString {
    if (comptime !build_options.enable_vulkan) return wrapString("");
    return wrapString(snail.coverage.Shader.vulkan.vertex_shader);
}

export fn snail_vulkan_coverage_shader_text_fragment_shader() SnailString {
    if (comptime !build_options.enable_vulkan) return wrapString("");
    return wrapString(snail.coverage.Shader.vulkan.text_fragment_shader);
}

export fn snail_vulkan_coverage_shader_coverage_functions() SnailString {
    if (comptime !build_options.enable_vulkan) return wrapString("");
    return wrapString(snail.coverage.Shader.vulkan.coverage_functions);
}

export fn snail_vulkan_coverage_shader_descriptor_set_index() u32 {
    if (comptime !build_options.enable_vulkan) return 0;
    return snail.coverage.Shader.vulkan.descriptor_set_index;
}

export fn snail_vulkan_coverage_shader_curve_texture_binding() u32 {
    if (comptime !build_options.enable_vulkan) return 0;
    return snail.coverage.Shader.vulkan.curve_texture_binding;
}

export fn snail_vulkan_coverage_shader_band_texture_binding() u32 {
    if (comptime !build_options.enable_vulkan) return 0;
    return snail.coverage.Shader.vulkan.band_texture_binding;
}

export fn snail_vulkan_coverage_backend_descriptor_set_layout(backend: *CoverageBackendImpl) vk.VkDescriptorSetLayout {
    if (comptime !build_options.enable_vulkan) return null;
    return switch (backend.inner) {
        .vulkan => |vk_backend| vk_backend.descriptorSetLayout(),
        else => null,
    };
}

export fn snail_vulkan_coverage_backend_pipeline_layout(backend: *CoverageBackendImpl) vk.VkPipelineLayout {
    if (comptime !build_options.enable_vulkan) return null;
    return switch (backend.inner) {
        .vulkan => |vk_backend| vk_backend.pipelineLayout(),
        else => null,
    };
}

export fn snail_vulkan_coverage_backend_bind_resources(backend: *CoverageBackendImpl, bindings: SnailVulkanTextCoverageBindings) c_int {
    if (comptime !build_options.enable_vulkan) return SNAIL_ERR_RENDERER_FAILED;
    switch (backend.inner) {
        .vulkan => |vk_backend| {
            vk_backend.bindResources(toVulkanCoverageBindings(bindings));
            return SNAIL_OK;
        },
        else => return SNAIL_ERR_INVALID_ARGUMENT,
    }
}

export fn snail_renderer_deinit(renderer: ?*RendererImpl) void {
    if (renderer) |r| {
        r.deinit();
        destroyHandle(r);
    }
}

export fn snail_renderer_backend_name(renderer: *const RendererImpl) [*:0]const u8 {
    return @ptrCast(renderer.backendName().ptr);
}

export fn snail_renderer_resource_cache_stats(renderer: *RendererImpl, out: *SnailResourceCacheStats) void {
    var erased = renderer.asRenderer();
    out.* = fromResourceCacheStats(erased.resourceCacheStats());
}

export fn snail_renderer_reset_resource_cache(renderer: *RendererImpl) void {
    var erased = renderer.asRenderer();
    erased.resetResourceCache();
}

export fn snail_renderer_upload_resources_blocking(
    renderer: *RendererImpl,
    alloc_ptr: ?*const SnailAllocator,
    set: *const ResourceSetImpl,
    out: *?*PreparedResourcesImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    var erased = renderer.asRenderer();
    const prepared = erased.uploadResourcesBlocking(.{ .persistent = allocator, .scratch = allocator }, &set.inner) catch |err| return mapError(err);
    const impl = handleAllocator().create(PreparedResourcesImpl) catch {
        var doomed = prepared;
        doomed.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = prepared };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_renderer_plan_resource_upload(
    renderer: *RendererImpl,
    alloc_ptr: ?*const SnailAllocator,
    current: ?*const PreparedResourcesImpl,
    next_set: *const ResourceSetImpl,
    out: *?*ResourceUploadPlanImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const changed_keys = allocator.alloc(snail.ResourceKey, next_set.inner.slice().len) catch return SNAIL_ERR_OUT_OF_MEMORY;
    var erased = renderer.asRenderer();
    const plan = erased.planResourceUpload(
        if (current) |prepared| &prepared.inner else null,
        &next_set.inner,
        changed_keys,
    ) catch |err| {
        allocator.free(changed_keys);
        return mapError(err);
    };
    const impl = handleAllocator().create(ResourceUploadPlanImpl) catch {
        allocator.free(changed_keys);
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{
        .inner = plan,
        .allocator = allocator,
        .changed_keys = changed_keys,
    };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_resource_upload_plan_deinit(plan: ?*ResourceUploadPlanImpl) void {
    if (plan) |p| {
        p.allocator.free(p.changed_keys);
        destroyHandle(p);
    }
}

export fn snail_resource_upload_plan_footprint(plan: *const ResourceUploadPlanImpl) SnailResourceFootprint {
    return fromResourceFootprint(plan.inner.upload_footprint);
}

export fn snail_resource_upload_plan_upload_bytes(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.upload_bytes;
}

export fn snail_resource_upload_plan_reused_atlas_pages(plan: *const ResourceUploadPlanImpl) u32 {
    return plan.inner.reused_atlas_pages;
}

export fn snail_resource_upload_plan_missing_atlas_pages(plan: *const ResourceUploadPlanImpl) u32 {
    return plan.inner.missing_atlas_pages;
}

export fn snail_resource_upload_plan_reused_images(plan: *const ResourceUploadPlanImpl) u32 {
    return plan.inner.reused_images;
}

export fn snail_resource_upload_plan_missing_images(plan: *const ResourceUploadPlanImpl) u32 {
    return plan.inner.missing_images;
}

export fn snail_resource_upload_plan_atlas_cache_rebuilds(plan: *const ResourceUploadPlanImpl) u32 {
    return plan.inner.atlas_cache_rebuilds;
}

export fn snail_resource_upload_plan_image_cache_rebuilds(plan: *const ResourceUploadPlanImpl) u32 {
    return plan.inner.image_cache_rebuilds;
}

export fn snail_resource_upload_plan_curve_bytes(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.curve_bytes_upload;
}

export fn snail_resource_upload_plan_band_bytes(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.band_bytes_upload;
}

export fn snail_resource_upload_plan_layer_info_bytes(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.layer_info_bytes_upload;
}

export fn snail_resource_upload_plan_image_bytes(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.image_bytes_upload;
}

export fn snail_resource_upload_plan_changed_bytes(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.changed_bytes;
}

export fn snail_resource_upload_plan_changed_key_count(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.changed_len;
}

export fn snail_resource_upload_plan_changed_key(plan: *const ResourceUploadPlanImpl, index: usize, out: *SnailResourceKey) bool {
    if (index >= plan.inner.changed_len) return false;
    out.* = plan.inner.changed_keys[index].id;
    return true;
}

export fn snail_renderer_begin_resource_upload(
    renderer: *RendererImpl,
    alloc_ptr: ?*const SnailAllocator,
    plan: *const ResourceUploadPlanImpl,
    out: *?*PendingResourceUploadImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const changed = plan.inner.changedKeys();
    const changed_keys = allocator.alloc(snail.ResourceKey, changed.len) catch return SNAIL_ERR_OUT_OF_MEMORY;
    @memcpy(changed_keys, changed);
    var plan_copy = plan.inner;
    plan_copy.changed_keys = changed_keys;
    plan_copy.changed_len = changed.len;
    var erased = renderer.asRenderer();
    const pending = erased.beginResourceUpload(.{ .persistent = allocator, .scratch = allocator }, plan_copy) catch |err| {
        allocator.free(changed_keys);
        return mapError(err);
    };
    const impl = handleAllocator().create(PendingResourceUploadImpl) catch {
        var doomed = pending;
        doomed.deinit();
        allocator.free(changed_keys);
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{
        .inner = pending,
        .allocator = allocator,
        .changed_keys = changed_keys,
    };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_pending_resource_upload_deinit(pending: ?*PendingResourceUploadImpl) void {
    if (pending) |p| {
        p.inner.deinit();
        p.allocator.free(p.changed_keys);
        destroyHandle(p);
    }
}

export fn snail_pending_resource_upload_record(pending: *PendingResourceUploadImpl, budget_bytes: usize) c_int {
    pending.inner.record(.no_command, .{ .budget_bytes = budget_bytes }) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_pending_resource_upload_record_checked(pending: *PendingResourceUploadImpl, budget_bytes: usize, allow_cache_rebuilds: bool) c_int {
    pending.inner.record(.no_command, .{
        .budget_bytes = budget_bytes,
        .allow_cache_rebuilds = allow_cache_rebuilds,
    }) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_pending_resource_upload_ready(pending: *PendingResourceUploadImpl, ready: bool) bool {
    return pending.inner.ready(.{ .ready = ready });
}

export fn snail_pending_resource_upload_ready_now(pending: *PendingResourceUploadImpl) bool {
    return pending.inner.ready(.immediate);
}

export fn snail_pending_resource_upload_publish(pending: *PendingResourceUploadImpl, out: *?*PreparedResourcesImpl) c_int {
    const prepared = pending.inner.publish() catch |err| return mapError(err);
    const impl = handleAllocator().create(PreparedResourcesImpl) catch {
        var doomed = prepared;
        doomed.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = prepared };
    out.* = impl;
    return SNAIL_OK;
}

export fn snail_renderer_draw(
    renderer: *RendererImpl,
    prepared: *const PreparedResourcesImpl,
    list: *const DrawListImpl,
    options: SnailDrawOptions,
) c_int {
    var erased = renderer.asRenderer();
    erased.draw(&prepared.inner, list.inner.slice(), toDrawOptions(options) catch return SNAIL_ERR_INVALID_ARGUMENT) catch |err| return mapError(err);
    return SNAIL_OK;
}

export fn snail_renderer_draw_prepared(
    renderer: *RendererImpl,
    prepared: *const PreparedResourcesImpl,
    scene: *const PreparedSceneImpl,
    options: SnailDrawOptions,
) c_int {
    var erased = renderer.asRenderer();
    erased.drawPrepared(&prepared.inner, &scene.inner, toDrawOptions(options) catch return SNAIL_ERR_INVALID_ARGUMENT) catch |err| return mapError(err);
    return SNAIL_OK;
}

// Compile-time features and constants

export fn snail_harfbuzz_available() bool {
    return build_options.enable_harfbuzz;
}

export fn snail_text_words_per_glyph() usize {
    return snail.TEXT_WORDS_PER_GLYPH;
}
export fn snail_text_words_per_vertex() usize {
    return snail.TEXT_WORDS_PER_VERTEX;
}
export fn snail_text_vertices_per_glyph() usize {
    return snail.TEXT_VERTICES_PER_GLYPH;
}
export fn snail_path_words_per_shape() usize {
    return snail.PATH_WORDS_PER_SHAPE;
}
export fn snail_path_words_per_vertex() usize {
    return snail.PATH_WORDS_PER_VERTEX;
}
export fn snail_path_vertices_per_shape() usize {
    return snail.PATH_VERTICES_PER_SHAPE;
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

fn testDrawOptions(width: f32, height: f32) SnailDrawOptions {
    return .{
        .mvp = snail_mat4_identity(),
        .target = .{
            .pixel_width = width,
            .pixel_height = height,
            .attachment_encoding = 1,
            .stored_pixel_encoding = 1,
        },
    };
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

    var decoration: SnailDecorationMetrics = undefined;
    try testing.expectEqual(SNAIL_OK, snail_font_decoration_metrics(font.?, &decoration));
    try testing.expect(decoration.underline_thickness > 0);

    var script: SnailScriptMetrics = undefined;
    try testing.expectEqual(SNAIL_OK, snail_font_superscript_metrics(font.?, &script));
    try testing.expect(script.y_size > 0);
    try testing.expectEqual(SNAIL_OK, snail_font_subscript_metrics(font.?, &script));
    try testing.expect(script.y_size > 0);
}

test "c_api: text atlas metrics and ensure glyphs" {
    const atlas = try testTextAtlas();
    defer snail_text_atlas_deinit(atlas);

    try testing.expectEqual(@as(usize, 1), snail_text_atlas_face_count(atlas));

    var primary_face: u16 = undefined;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_primary_face_index(atlas, &primary_face));
    try testing.expectEqual(@as(u16, 0), primary_face);

    var upem: u16 = 0;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_face_units_per_em(atlas, primary_face, &upem));
    try testing.expect(upem > 0);

    var line_metrics: SnailLineMetrics = undefined;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_face_line_metrics(atlas, primary_face, &line_metrics));
    try testing.expect(line_metrics.ascent > 0);
    try testing.expect(line_metrics.descent < 0);

    var gid: u16 = 0;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_glyph_index(atlas, primary_face, 'A', &gid));
    try testing.expect(gid > 0);

    var advance: i16 = 0;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_advance_width(atlas, primary_face, gid, &advance));
    try testing.expect(advance > 0);

    var cell_metrics: SnailCellMetrics = undefined;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_cell_metrics(atlas, .{}, 16, &cell_metrics));
    try testing.expect(cell_metrics.cell_width > 0);
    try testing.expect(cell_metrics.line_height > cell_metrics.cell_width);

    var measured: f32 = 0;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_measure_text(atlas, .{}, "Hello", 5, 16, &measured));
    try testing.expect(measured > 0);

    var decoration_rect: SnailRect = undefined;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_decoration_rect(atlas, 0, 0, 16, measured, 16, &decoration_rect));
    try testing.expect(decoration_rect.w == measured);
    try testing.expect(decoration_rect.h >= 1);

    var script_transform: SnailScriptTransform = undefined;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_superscript_transform(atlas, 0, 16, 16, &script_transform));
    try testing.expect(script_transform.font_size > 0);
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_subscript_transform(atlas, 0, 16, 16, &script_transform));
    try testing.expect(script_transform.font_size > 0);

    var next: ?*TextAtlasImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_ensure_glyphs(atlas, primary_face, @ptrCast(&gid), 1, &next));
    try testing.expect(next != null);
    defer snail_text_atlas_deinit(next);

    var again: ?*TextAtlasImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_ensure_glyphs(next.?, primary_face, @ptrCast(&gid), 1, &again));
    try testing.expectEqual(@as(?*TextAtlasImpl, null), again);
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
        .placement = .{ .baseline_x = 10, .baseline_y = 20, .em = 24 },
        .fill = .{ .kind = SNAIL_PAINT_SOLID, .paint_solid = .{ 1, 1, 1, 1 } },
    }, &blob));
    defer snail_text_blob_deinit(blob);
    try testing.expectEqual(@as(usize, 5), snail_text_blob_glyph_count(blob.?));
}

test "c_api: text blob rebound returns a new handle" {
    var atlas = try testTextAtlas();
    defer snail_text_atlas_deinit(atlas);
    try ensureForText(&atlas, "A");

    var blob: ?*TextBlobImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_blob_init_text(null, atlas, .{}, "A", 1, .{
        .placement = .{ .baseline_x = 0, .baseline_y = 24, .em = 24 },
        .fill = .{ .kind = SNAIL_PAINT_SOLID, .paint_solid = .{ 1, 1, 1, 1 } },
    }, &blob));
    defer snail_text_blob_deinit(blob);

    var next: ?*TextAtlasImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_atlas_ensure_text(atlas, .{}, "B", 1, &next));
    try testing.expect(next != null);

    var rebound: ?*TextBlobImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_blob_rebound(null, blob.?, next.?, &rebound));
    defer snail_text_blob_deinit(rebound);
    try testing.expectEqual(snail_text_blob_glyph_count(blob.?), snail_text_blob_glyph_count(rebound.?));
    snail_text_atlas_deinit(atlas);
    atlas = next.?;
}

test "c_api: invalid caller input maps to invalid argument" {
    var path: ?*PathImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_path_init(null, &path));
    defer snail_path_deinit(path);
    try testing.expectEqual(SNAIL_ERR_INVALID_ARGUMENT, snail_path_line_to(path.?, 1, 1));

    const atlas = try testTextAtlas();
    defer snail_text_atlas_deinit(atlas);
    var resources: ?*ResourceSetImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_resource_set_init(null, 0, &resources));
    defer snail_resource_set_deinit(resources);
    try testing.expectEqual(SNAIL_ERR_INVALID_ARGUMENT, snail_resource_set_put_text_atlas(resources.?, 1, atlas));

    const pixels = [_]u8{ 255, 255, 255, 255 };
    var image: ?*ImageImpl = null;
    try testing.expectEqual(SNAIL_ERR_INVALID_ARGUMENT, snail_image_init_srgba8(null, 1, 1, &pixels, pixels.len - 1, &image));
    try testing.expectEqual(@as(?*ImageImpl, null), image);
}

test "c_api: cpu renderer and thread pool" {
    if (!build_options.enable_cpu) {
        try testing.expect(!snail_cpu_available());
        return;
    }

    try testing.expect(snail_cpu_available());

    var pixels = [_]u8{0} ** (4 * 4 * 4);
    var renderer: ?*RendererImpl = null;
    try testing.expectEqual(SNAIL_ERR_INVALID_ARGUMENT, snail_cpu_renderer_init(&pixels, 4, 4, 15, &renderer));
    try testing.expectEqual(@as(?*RendererImpl, null), renderer);
    try testing.expectEqual(SNAIL_OK, snail_cpu_renderer_init(&pixels, 4, 4, 16, &renderer));
    defer snail_renderer_deinit(renderer);
    try testing.expectEqualStrings("CPU", std.mem.span(snail_renderer_backend_name(renderer.?)));

    var pool: ?*ThreadPoolImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_thread_pool_init_with_threads(null, 0, &pool));
    defer snail_thread_pool_deinit(pool);
    try testing.expectEqual(@as(usize, 0), snail_thread_pool_thread_count(pool.?));
    try testing.expectEqual(SNAIL_OK, snail_cpu_renderer_set_thread_pool(renderer.?, pool));
    try testing.expectEqual(SNAIL_OK, snail_cpu_renderer_set_thread_pool(renderer.?, null));

    var next_pixels = [_]u8{0} ** (2 * 2 * 4);
    try testing.expectEqual(SNAIL_OK, snail_cpu_renderer_reinit_buffer(renderer.?, &next_pixels, 2, 2, 8));
}

test "c_api: scheduled upload draw list coverage records and retirement" {
    if (!build_options.enable_cpu) return;

    var atlas = try testTextAtlas();
    defer snail_text_atlas_deinit(atlas);
    try ensureForText(&atlas, "Hi");

    var blob: ?*TextBlobImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_blob_init_text(null, atlas, .{}, "Hi", 2, .{
        .placement = .{ .baseline_x = 0, .baseline_y = 24, .em = 24 },
        .fill = .{ .kind = SNAIL_PAINT_SOLID, .paint_solid = .{ 1, 1, 1, 1 } },
    }, &blob));
    defer snail_text_blob_deinit(blob);

    var scene: ?*SceneImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_scene_init(null, &scene));
    defer snail_scene_deinit(scene);
    try testing.expectEqual(SNAIL_OK, snail_scene_add_text(scene.?, blob.?));

    var resources: ?*ResourceSetImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_resource_set_init(null, 4, &resources));
    defer snail_resource_set_deinit(resources);
    try testing.expectEqual(SNAIL_OK, snail_resource_set_add_scene(resources.?, scene.?));

    var pixels = [_]u8{0} ** (64 * 64 * 4);
    var renderer: ?*RendererImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_cpu_renderer_init(&pixels, 64, 64, 64 * 4, &renderer));
    defer snail_renderer_deinit(renderer);

    var plan: ?*ResourceUploadPlanImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_renderer_plan_resource_upload(renderer.?, null, null, resources.?, &plan));
    try testing.expect(snail_resource_upload_plan_upload_bytes(plan.?) > 0);
    try testing.expect(snail_resource_upload_plan_changed_key_count(plan.?) > 0);
    var changed_key: SnailResourceKey = 0;
    try testing.expect(snail_resource_upload_plan_changed_key(plan.?, 0, &changed_key));

    var pending: ?*PendingResourceUploadImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_renderer_begin_resource_upload(renderer.?, null, plan.?, &pending));
    snail_resource_upload_plan_deinit(plan);
    plan = null;
    defer snail_pending_resource_upload_deinit(pending);

    pending.?.inner.plan.atlas_cache_rebuilds = 1;
    try testing.expectEqual(SNAIL_ERR_INVALID_ARGUMENT, snail_pending_resource_upload_record_checked(pending.?, std.math.maxInt(usize), false));
    pending.?.inner.plan.atlas_cache_rebuilds = 0;
    try testing.expectEqual(SNAIL_OK, snail_pending_resource_upload_record_checked(pending.?, std.math.maxInt(usize), false));
    try testing.expect(snail_pending_resource_upload_ready_now(pending.?));

    var prepared: ?*PreparedResourcesImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_pending_resource_upload_publish(pending.?, &prepared));

    var stamp: SnailResourceStamp = .{};
    try testing.expect(snail_prepared_resources_stamp_for_key(prepared.?, changed_key, &stamp));
    try testing.expect(stamp.identity != 0 or stamp.layout != 0 or stamp.content != 0);

    var coverage: ?*TextCoverageRecordsImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_coverage_records_init(null, snail_text_coverage_records_word_capacity_for_blob(blob.?), &coverage));
    defer snail_text_coverage_records_deinit(coverage);
    try testing.expectEqual(SNAIL_OK, snail_text_coverage_records_build_local(coverage.?, prepared.?, blob.?, .{}));
    try testing.expect(snail_text_coverage_records_valid_for(coverage.?, prepared.?));
    try testing.expect(snail_text_coverage_records_word_count(coverage.?) > 0);

    var coverage_backend: ?*CoverageBackendImpl = null;
    try testing.expectEqual(SNAIL_ERR_INVALID_ARGUMENT, snail_coverage_backend_init(renderer.?, prepared.?, &coverage_backend));
    try testing.expectEqual(@as(?*CoverageBackendImpl, null), coverage_backend);

    const options = testDrawOptions(64, 64);
    const word_capacity = snail_draw_list_estimate_word_count(scene.?, options);
    const segment_capacity = snail_draw_list_estimate_segment_count(scene.?, options);
    try testing.expect(word_capacity > 0);
    try testing.expect(segment_capacity > 0);

    var list: ?*DrawListImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_draw_list_init(null, word_capacity, segment_capacity, &list));
    defer snail_draw_list_deinit(list);
    try testing.expectEqual(SNAIL_OK, snail_draw_list_add_scene(list.?, prepared.?, scene.?, options));
    try testing.expect(snail_draw_list_word_count(list.?) > 0);
    try testing.expect(snail_draw_list_segment_count(list.?) > 0);
    try testing.expect(snail_draw_list_words(list.?) != null);
    try testing.expectEqual(SNAIL_OK, snail_renderer_draw(renderer.?, prepared.?, list.?, options));

    var queue: ?*PreparedResourceRetirementQueueImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_prepared_resource_retirement_queue_init(null, &queue));
    defer snail_prepared_resource_retirement_queue_deinit(queue);
    try testing.expectEqual(SNAIL_OK, snail_prepared_resource_retirement_queue_retire(queue.?, prepared.?));
    prepared = null;
}

test "c_api: scene and resource set follow public model" {
    var atlas = try testTextAtlas();
    defer snail_text_atlas_deinit(atlas);
    try ensureForText(&atlas, "Hi");

    var blob: ?*TextBlobImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_text_blob_init_text(null, atlas, .{}, "Hi", 2, .{
        .placement = .{ .baseline_x = 0, .baseline_y = 24, .em = 24 },
        .fill = .{ .kind = SNAIL_PAINT_SOLID, .paint_solid = .{ 1, 1, 1, 1 } },
    }, &blob));
    defer snail_text_blob_deinit(blob);

    var scene: ?*SceneImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_scene_init(null, &scene));
    defer snail_scene_deinit(scene);
    try testing.expectEqual(SNAIL_OK, snail_scene_add_text(scene.?, blob.?));
    try testing.expectEqual(SNAIL_OK, snail_scene_add_text_override(scene.?, blob.?, .{
        .tint = .{ 0.5, 0.75, 1.0, 0.5 },
    }));
    try testing.expectEqual(@as(usize, 2), snail_scene_command_count(scene.?));

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

    const fill = SnailFillStyle{ .paint = .{ .kind = SNAIL_PAINT_SOLID, .paint_solid = .{ 0.1, 0.2, 0.3, 1 } } };
    const stroke = SnailStrokeStyle{ .paint = .{ .kind = SNAIL_PAINT_SOLID, .paint_solid = .{ 1, 1, 1, 1 } }, .width = 2, .placement = 1 };
    try testing.expectEqual(SNAIL_OK, snail_path_picture_builder_add_rounded_rect(
        builder.?,
        .{ .x = 0, .y = 0, .w = 100, .h = 40 },
        &fill,
        &stroke,
        8,
        .{},
    ));
    try testing.expectEqual(@as(usize, 1), snail_path_picture_builder_shape_count(builder.?));
    const second_mark = snail_path_picture_builder_mark(builder.?);
    try testing.expectEqual(SNAIL_OK, snail_path_picture_builder_add_rect(
        builder.?,
        .{ .x = 120, .y = 0, .w = 20, .h = 20 },
        &fill,
        null,
        .{},
    ));

    var second_range: SnailRange = undefined;
    try testing.expectEqual(SNAIL_OK, snail_path_picture_builder_range_from(builder.?, second_mark, &second_range));
    try testing.expectEqual(@as(usize, 1), second_range.start);
    try testing.expectEqual(@as(usize, 1), second_range.count);
    try testing.expectEqual(SNAIL_ERR_INVALID_ARGUMENT, snail_path_picture_builder_range_between(
        builder.?,
        .{ .shape_count = 2 },
        .{ .shape_count = 1 },
        &second_range,
    ));

    var picture: ?*PathPictureImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_path_picture_builder_freeze(builder.?, null, null, &picture));
    defer snail_path_picture_deinit(picture);
    try testing.expectEqual(@as(usize, 2), snail_path_picture_shape_count(picture.?));
    var picture_footprint: SnailResourceFootprint = .{};
    snail_path_picture_upload_footprint(picture.?, &picture_footprint);
    try testing.expect(snail_resource_footprint_allocated_bytes(picture_footprint) > 0);

    var resources: ?*ResourceSetImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_resource_set_init(null, 2, &resources));
    defer snail_resource_set_deinit(resources);
    try testing.expectEqual(SNAIL_OK, snail_resource_set_put_path_picture_options(
        resources.?,
        7,
        picture.?,
        SNAIL_RESOURCE_CAPACITY_EXACT,
    ));
    try testing.expectEqual(SNAIL_ERR_INVALID_ARGUMENT, snail_resource_set_put_path_picture_options(
        resources.?,
        8,
        picture.?,
        99,
    ));
    var set_footprint: SnailResourceFootprint = .{};
    try testing.expectEqual(SNAIL_OK, snail_resource_set_estimate_upload_footprint(resources.?, &set_footprint));
    try testing.expect(snail_resource_footprint_allocated_bytes(set_footprint) >= snail_resource_footprint_allocated_bytes(picture_footprint));

    var scene: ?*SceneImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_scene_init(null, &scene));
    defer snail_scene_deinit(scene);
    try testing.expectEqual(SNAIL_OK, snail_scene_add_path_picture_range(scene.?, picture.?, second_range));
    try testing.expectEqual(SNAIL_OK, snail_scene_add_path_picture_range_override(scene.?, picture.?, second_range, .{
        .tint = .{ 1, 0.5, 0.25, 1 },
    }));
    try testing.expectEqual(@as(usize, 2), snail_scene_command_count(scene.?));
}

test "c_api: image paint init and constants" {
    var pixels = [_]u8{255} ** (4 * 4 * 4);
    var image: ?*ImageImpl = null;
    try testing.expectEqual(SNAIL_OK, snail_image_init_srgba8(null, 4, 4, &pixels, pixels.len, &image));
    defer snail_image_deinit(image);
    try testing.expectEqual(@as(u32, 4), snail_image_width(image.?));
    try testing.expectEqual(@as(u32, 4), snail_image_height(image.?));
    var footprint: SnailResourceFootprint = .{};
    snail_image_upload_footprint(image.?, &footprint);
    try testing.expectEqual(@as(usize, 4 * 4 * 4), snail_resource_footprint_used_bytes(footprint));
    try testing.expect(snail_resource_footprint_allocated_bytes(footprint) >= snail_resource_footprint_used_bytes(footprint));

    try testing.expectEqual(snail.TEXT_WORDS_PER_GLYPH, snail_text_words_per_glyph());
    try testing.expectEqual(snail.TEXT_WORDS_PER_VERTEX, snail_text_words_per_vertex());
    try testing.expectEqual(snail.TEXT_VERTICES_PER_GLYPH, snail_text_vertices_per_glyph());
    try testing.expectEqual(snail.PATH_WORDS_PER_SHAPE, snail_path_words_per_shape());
    try testing.expectEqual(snail.PATH_WORDS_PER_VERTEX, snail_path_words_per_vertex());
    try testing.expectEqual(snail.PATH_VERTICES_PER_SHAPE, snail_path_vertices_per_shape());
}
