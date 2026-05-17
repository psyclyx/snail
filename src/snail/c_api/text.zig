const common = @import("common.zig");
const std = common.std;
const builtin = common.builtin;
const snail = common.snail;
const resource_key = common.resource_key;
const ttf = common.ttf;
const build_options = common.build_options;
const c_convert = common.c_convert;
const c_handles = common.c_handles;
const c_runtime = common.c_runtime;
const c_types = common.c_types;
const vk = common.vk;
const resolveAllocator = common.resolveAllocator;
const handleAllocator = common.handleAllocator;
const mapError = common.mapError;
const SnailAllocFn = common.SnailAllocFn;
const SnailFreeFn = common.SnailFreeFn;
const SnailAllocator = common.SnailAllocator;
const SNAIL_OK = common.SNAIL_OK;
const SNAIL_ERR_INVALID_FONT = common.SNAIL_ERR_INVALID_FONT;
const SNAIL_ERR_OUT_OF_MEMORY = common.SNAIL_ERR_OUT_OF_MEMORY;
const SNAIL_ERR_RENDERER_FAILED = common.SNAIL_ERR_RENDERER_FAILED;
const SNAIL_ERR_INVALID_ARGUMENT = common.SNAIL_ERR_INVALID_ARGUMENT;
const SNAIL_ERR_DRAW_FAILED = common.SNAIL_ERR_DRAW_FAILED;
const SnailVulkanContext = common.SnailVulkanContext;
const SnailBBox = common.SnailBBox;
const SnailGlyphMetrics = common.SnailGlyphMetrics;
const SnailLineMetrics = common.SnailLineMetrics;
const SnailDecorationMetrics = common.SnailDecorationMetrics;
const SnailScriptMetrics = common.SnailScriptMetrics;
const SnailScriptTransform = common.SnailScriptTransform;
const SnailCellMetrics = common.SnailCellMetrics;
const SnailRect = common.SnailRect;
const SnailMat4 = common.SnailMat4;
const SnailString = common.SnailString;
const SnailTransform2D = common.SnailTransform2D;
const SnailOverride = common.SnailOverride;
const SnailRange = common.SnailRange;
const SnailShapeMark = common.SnailShapeMark;
const SnailSyntheticStyle = common.SnailSyntheticStyle;
const SnailFaceSpec = common.SnailFaceSpec;
const SnailFontStyle = common.SnailFontStyle;
const SnailShapedGlyph = common.SnailShapedGlyph;
const SnailTextPlacement = common.SnailTextPlacement;
const SnailTextAppendOptions = common.SnailTextAppendOptions;
const SnailResolveTarget = common.SnailResolveTarget;
const SnailDrawOptions = common.SnailDrawOptions;
const SnailResourceKey = common.SnailResourceKey;
const SnailResourceStamp = common.SnailResourceStamp;
const SNAIL_RESOURCE_CAPACITY_GROWABLE = common.SNAIL_RESOURCE_CAPACITY_GROWABLE;
const SNAIL_RESOURCE_CAPACITY_EXACT = common.SNAIL_RESOURCE_CAPACITY_EXACT;
const SnailResourceFootprint = common.SnailResourceFootprint;
const SnailResourceCacheStats = common.SnailResourceCacheStats;
const SnailGlTextCoverageBindings = common.SnailGlTextCoverageBindings;
const SnailVulkanTextCoverageBindings = common.SnailVulkanTextCoverageBindings;
const SNAIL_PAINT_SOLID = common.SNAIL_PAINT_SOLID;
const SNAIL_PAINT_LINEAR = common.SNAIL_PAINT_LINEAR;
const SNAIL_PAINT_RADIAL = common.SNAIL_PAINT_RADIAL;
const SNAIL_PAINT_IMAGE = common.SNAIL_PAINT_IMAGE;
const SnailLinearGradient = common.SnailLinearGradient;
const SnailRadialGradient = common.SnailRadialGradient;
const SnailImagePaint = common.SnailImagePaint;
const SnailPaint = common.SnailPaint;
const SnailFillStyle = common.SnailFillStyle;
const SnailStrokeStyle = common.SnailStrokeStyle;
const wrapBBox = common.wrapBBox;
const wrapString = common.wrapString;
const wrapDecorationMetrics = common.wrapDecorationMetrics;
const wrapScriptMetrics = common.wrapScriptMetrics;
const wrapScriptTransform = common.wrapScriptTransform;
const wrapResourceStamp = common.wrapResourceStamp;
const toRect = common.toRect;
const toSnailRect = common.toSnailRect;
const fromMat4 = common.fromMat4;
const toTransform = common.toTransform;
const toOverride = common.toOverride;
const toGlCoverageBindings = common.toGlCoverageBindings;
const toVulkanCoverageBindings = common.toVulkanCoverageBindings;
const fromResourceFootprint = common.fromResourceFootprint;
const fromResourceCacheStats = common.fromResourceCacheStats;
const toResourceCapacityMode = common.toResourceCapacityMode;
const reservedResourceCapacityMode = common.reservedResourceCapacityMode;
const toRange = common.toRange;
const fromRange = common.fromRange;
const toShapeMark = common.toShapeMark;
const fromShapeMark = common.fromShapeMark;
const toSyntheticStyle = common.toSyntheticStyle;
const toFontWeight = common.toFontWeight;
const toFontStyle = common.toFontStyle;
const toDecoration = common.toDecoration;
const toTextPlacement = common.toTextPlacement;
const toDrawOptions = common.toDrawOptions;
const toPaint = common.toPaint;
const toFillStyle = common.toFillStyle;
const toStrokeStyle = common.toStrokeStyle;
const toOptFill = common.toOptFill;
const toOptStroke = common.toOptStroke;
const FontImpl = common.FontImpl;
const TextAtlasImpl = common.TextAtlasImpl;
const ShapedTextImpl = common.ShapedTextImpl;
const TextBlobImpl = common.TextBlobImpl;
const ImageImpl = common.ImageImpl;
const PathImpl = common.PathImpl;
const PathPictureBuilderImpl = common.PathPictureBuilderImpl;
const PathPictureImpl = common.PathPictureImpl;
const SceneImpl = common.SceneImpl;
const ResourceSetImpl = common.ResourceSetImpl;
const PreparedResourcesImpl = common.PreparedResourcesImpl;
const PreparedSceneImpl = common.PreparedSceneImpl;
const PreparedResourceRetirementQueueImpl = common.PreparedResourceRetirementQueueImpl;
const ResourceUploadPlanImpl = common.ResourceUploadPlanImpl;
const PendingResourceUploadImpl = common.PendingResourceUploadImpl;
const DrawListImpl = common.DrawListImpl;
const TextCoverageRecordsImpl = common.TextCoverageRecordsImpl;
const CoverageBackendImpl = common.CoverageBackendImpl;
const ThreadPoolImpl = common.ThreadPoolImpl;
const RendererImpl = common.RendererImpl;
const destroyHandle = common.destroyHandle;

// TextAtlas and shaping

pub export fn snail_text_atlas_init(
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

pub export fn snail_text_atlas_deinit(atlas: ?*TextAtlasImpl) void {
    if (atlas) |a| {
        a.inner.deinit();
        destroyHandle(a);
    }
}

pub export fn snail_text_atlas_page_count(atlas: *const TextAtlasImpl) usize {
    return atlas.inner.pageCount();
}

pub export fn snail_text_atlas_upload_footprint(atlas: *const TextAtlasImpl, out: *SnailResourceFootprint) void {
    out.* = fromResourceFootprint(atlas.inner.uploadFootprint());
}

pub export fn snail_text_atlas_texture_byte_len(atlas: *const TextAtlasImpl) usize {
    var total: usize = 0;
    for (atlas.inner.pageSlice()) |page| total += page.textureBytes();
    if (atlas.inner.layer_info_data) |data| total += data.len * @sizeOf(f32);
    return total;
}

pub export fn snail_text_atlas_units_per_em(atlas: *const TextAtlasImpl, out: *u16) c_int {
    out.* = atlas.inner.unitsPerEm() catch return SNAIL_ERR_INVALID_FONT;
    return SNAIL_OK;
}

pub export fn snail_text_atlas_line_metrics(atlas: *const TextAtlasImpl, out: *SnailLineMetrics) c_int {
    const m = atlas.inner.lineMetrics() catch return SNAIL_ERR_INVALID_FONT;
    out.* = .{ .ascent = m.ascent, .descent = m.descent, .line_gap = m.line_gap };
    return SNAIL_OK;
}

pub export fn snail_text_atlas_face_count(atlas: *const TextAtlasImpl) usize {
    return atlas.inner.faceCount();
}

pub export fn snail_text_atlas_primary_face_index(atlas: *const TextAtlasImpl, out: *u16) c_int {
    out.* = atlas.inner.primaryFaceIndex() catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_text_atlas_face_units_per_em(atlas: *const TextAtlasImpl, face_index: usize, out: *u16) c_int {
    out.* = atlas.inner.faceUnitsPerEm(face_index) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_text_atlas_face_line_metrics(atlas: *const TextAtlasImpl, face_index: usize, out: *SnailLineMetrics) c_int {
    const m = atlas.inner.faceLineMetrics(face_index) catch |err| return mapError(err);
    out.* = .{ .ascent = m.ascent, .descent = m.descent, .line_gap = m.line_gap };
    return SNAIL_OK;
}

pub export fn snail_text_atlas_glyph_index(atlas: *const TextAtlasImpl, face_index: usize, codepoint: u32, out: *u16) c_int {
    const cp = std.math.cast(u21, codepoint) orelse return SNAIL_ERR_INVALID_ARGUMENT;
    out.* = (atlas.inner.glyphIndex(face_index, cp) catch |err| return mapError(err)) orelse 0;
    return SNAIL_OK;
}

pub export fn snail_text_atlas_advance_width(atlas: *const TextAtlasImpl, face_index: usize, glyph_id: u16, out: *i16) c_int {
    out.* = atlas.inner.advanceWidth(face_index, glyph_id) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_text_atlas_cell_metrics(atlas: *const TextAtlasImpl, style: SnailFontStyle, em: f32, out: *SnailCellMetrics) c_int {
    const metrics = atlas.inner.cellMetrics(.{
        .style = toFontStyle(style) catch return SNAIL_ERR_INVALID_ARGUMENT,
        .em = em,
    }) catch |err| return mapError(err);
    out.* = .{ .cell_width = metrics.cell_width, .line_height = metrics.line_height };
    return SNAIL_OK;
}

pub export fn snail_text_atlas_measure_text(
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

pub export fn snail_text_atlas_decoration_rect(
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

pub export fn snail_text_atlas_superscript_transform(atlas: *const TextAtlasImpl, x: f32, y: f32, font_size: f32, out: *SnailScriptTransform) c_int {
    out.* = wrapScriptTransform(atlas.inner.superscriptTransform(x, y, font_size) catch |err| return mapError(err));
    return SNAIL_OK;
}

pub export fn snail_text_atlas_subscript_transform(atlas: *const TextAtlasImpl, x: f32, y: f32, font_size: f32, out: *SnailScriptTransform) c_int {
    out.* = wrapScriptTransform(atlas.inner.subscriptTransform(x, y, font_size) catch |err| return mapError(err));
    return SNAIL_OK;
}

pub export fn snail_text_atlas_shape_utf8(
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

pub export fn snail_text_atlas_ensure_text(
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

pub export fn snail_text_atlas_ensure_shaped(atlas: *const TextAtlasImpl, shaped: *const ShapedTextImpl, out: *?*TextAtlasImpl) c_int {
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

pub export fn snail_text_atlas_ensure_glyphs(
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

pub export fn snail_shaped_text_deinit(shaped: ?*ShapedTextImpl) void {
    if (shaped) |s| {
        s.inner.deinit();
        destroyHandle(s);
    }
}

pub export fn snail_shaped_text_glyph_count(shaped: *const ShapedTextImpl) usize {
    return shaped.inner.glyphs.len;
}

pub export fn snail_shaped_text_advance_x(shaped: *const ShapedTextImpl) f32 {
    return shaped.inner.advance_x;
}

pub export fn snail_shaped_text_advance_y(shaped: *const ShapedTextImpl) f32 {
    return shaped.inner.advance_y;
}

pub export fn snail_shaped_text_glyph(shaped: *const ShapedTextImpl, index: usize, out: *SnailShapedGlyph) bool {
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

pub export fn snail_shaped_text_copy_glyphs(shaped: *const ShapedTextImpl, out: [*]SnailShapedGlyph, capacity: usize) usize {
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

pub export fn snail_text_blob_init_from_shaped(
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

pub export fn snail_text_blob_init_text(
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

pub export fn snail_text_blob_deinit(blob: ?*TextBlobImpl) void {
    if (blob) |b| {
        b.inner.deinit();
        destroyHandle(b);
    }
}

pub export fn snail_text_blob_glyph_count(blob: *const TextBlobImpl) usize {
    return blob.inner.glyphCount();
}

pub export fn snail_text_blob_rebound(
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
