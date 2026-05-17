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

// Font metrics helper

pub export fn snail_font_init(data: [*]const u8, len: usize, out: *?*FontImpl) c_int {
    const font = ttf.Font.init(data[0..len]) catch return SNAIL_ERR_INVALID_FONT;
    const impl = handleAllocator().create(FontImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.* = .{ .inner = font };
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_font_deinit(font: ?*FontImpl) void {
    if (font) |f| destroyHandle(f);
}

pub export fn snail_font_units_per_em(font: *const FontImpl) u16 {
    return font.inner.units_per_em;
}

pub export fn snail_font_glyph_index(font: *const FontImpl, codepoint: u32) u16 {
    return font.inner.glyphIndex(codepoint) catch 0;
}

pub export fn snail_font_get_kerning(font: *const FontImpl, left: u16, right: u16) i16 {
    return font.inner.getKerning(left, right) catch 0;
}

pub export fn snail_font_glyph_metrics(font: *const FontImpl, glyph_id: u16, out: *SnailGlyphMetrics) c_int {
    const m = font.inner.glyphMetrics(glyph_id) catch return SNAIL_ERR_INVALID_FONT;
    out.* = .{ .advance_width = m.advance_width, .lsb = m.lsb, .bbox = wrapBBox(m.bbox) };
    return SNAIL_OK;
}

pub export fn snail_font_line_metrics(font: *const FontImpl, out: *SnailLineMetrics) c_int {
    const m = font.inner.lineMetrics() catch return SNAIL_ERR_INVALID_FONT;
    out.* = .{ .ascent = m.ascent, .descent = m.descent, .line_gap = m.line_gap };
    return SNAIL_OK;
}

pub export fn snail_font_decoration_metrics(font: *const FontImpl, out: *SnailDecorationMetrics) c_int {
    out.* = wrapDecorationMetrics(font.inner.decorationMetrics() catch return SNAIL_ERR_INVALID_FONT);
    return SNAIL_OK;
}

pub export fn snail_font_superscript_metrics(font: *const FontImpl, out: *SnailScriptMetrics) c_int {
    out.* = wrapScriptMetrics(font.inner.superscriptMetrics() catch return SNAIL_ERR_INVALID_FONT);
    return SNAIL_OK;
}

pub export fn snail_font_subscript_metrics(font: *const FontImpl, out: *SnailScriptMetrics) c_int {
    out.* = wrapScriptMetrics(font.inner.subscriptMetrics() catch return SNAIL_ERR_INVALID_FONT);
    return SNAIL_OK;
}

pub export fn snail_font_advance_width(font: *const FontImpl, glyph_id: u16, out: *i16) c_int {
    out.* = font.inner.advanceWidth(glyph_id) catch return SNAIL_ERR_INVALID_FONT;
    return SNAIL_OK;
}

pub export fn snail_font_bbox(font: *const FontImpl, glyph_id: u16, out: *SnailBBox) c_int {
    out.* = wrapBBox(font.inner.bbox(glyph_id) catch return SNAIL_ERR_INVALID_FONT);
    return SNAIL_OK;
}
