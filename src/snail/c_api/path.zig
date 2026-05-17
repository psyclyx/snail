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

// Paths and path pictures

pub export fn snail_path_init(alloc_ptr: ?*const SnailAllocator, out: *?*PathImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const impl = handleAllocator().create(PathImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.* = .{ .inner = snail.Path.init(allocator) };
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_path_deinit(path: ?*PathImpl) void {
    if (path) |p| {
        p.inner.deinit();
        destroyHandle(p);
    }
}

pub export fn snail_path_reset(path: *PathImpl) void {
    path.inner.reset();
}

pub export fn snail_path_is_empty(path: *const PathImpl) bool {
    return path.inner.isEmpty();
}

pub export fn snail_path_bounds(path: *const PathImpl, out: *SnailBBox) bool {
    if (path.inner.bounds()) |b| {
        out.* = wrapBBox(b);
        return true;
    }
    return false;
}

pub export fn snail_path_move_to(path: *PathImpl, x: f32, y: f32) c_int {
    path.inner.moveTo(.{ .x = x, .y = y }) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_path_line_to(path: *PathImpl, x: f32, y: f32) c_int {
    path.inner.lineTo(.{ .x = x, .y = y }) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_path_quad_to(path: *PathImpl, cx: f32, cy: f32, x: f32, y: f32) c_int {
    path.inner.quadTo(.{ .x = cx, .y = cy }, .{ .x = x, .y = y }) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_path_cubic_to(path: *PathImpl, c1x: f32, c1y: f32, c2x: f32, c2y: f32, x: f32, y: f32) c_int {
    path.inner.cubicTo(.{ .x = c1x, .y = c1y }, .{ .x = c2x, .y = c2y }, .{ .x = x, .y = y }) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_path_close(path: *PathImpl) c_int {
    path.inner.close() catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_path_add_rect(path: *PathImpl, rect: SnailRect) c_int {
    path.inner.addRect(toRect(rect)) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_path_add_rect_reversed(path: *PathImpl, rect: SnailRect) c_int {
    path.inner.addRectReversed(toRect(rect)) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_path_add_rounded_rect(path: *PathImpl, rect: SnailRect, corner_radius: f32) c_int {
    path.inner.addRoundedRect(toRect(rect), corner_radius) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_path_add_rounded_rect_reversed(path: *PathImpl, rect: SnailRect, corner_radius: f32) c_int {
    path.inner.addRoundedRectReversed(toRect(rect), corner_radius) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_path_add_ellipse(path: *PathImpl, rect: SnailRect) c_int {
    path.inner.addEllipse(toRect(rect)) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_path_add_ellipse_reversed(path: *PathImpl, rect: SnailRect) c_int {
    path.inner.addEllipseReversed(toRect(rect)) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_path_picture_builder_init(alloc_ptr: ?*const SnailAllocator, out: *?*PathPictureBuilderImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const impl = handleAllocator().create(PathPictureBuilderImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.* = .{ .inner = snail.PathPictureBuilder.init(allocator) };
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_path_picture_builder_deinit(builder: ?*PathPictureBuilderImpl) void {
    if (builder) |b| {
        b.inner.deinit();
        destroyHandle(b);
    }
}

pub export fn snail_path_picture_builder_add_path(
    builder: *PathPictureBuilderImpl,
    path: *const PathImpl,
    fill: ?*const SnailFillStyle,
    stroke: ?*const SnailStrokeStyle,
    transform: SnailTransform2D,
) c_int {
    builder.inner.addPath(&path.inner, toOptFill(fill) catch return SNAIL_ERR_INVALID_ARGUMENT, toOptStroke(stroke) catch return SNAIL_ERR_INVALID_ARGUMENT, toTransform(transform)) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_path_picture_builder_add_filled_path(
    builder: *PathPictureBuilderImpl,
    path: *const PathImpl,
    fill: SnailFillStyle,
    transform: SnailTransform2D,
) c_int {
    builder.inner.addFilledPath(&path.inner, toFillStyle(fill) catch return SNAIL_ERR_INVALID_ARGUMENT, toTransform(transform)) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_path_picture_builder_add_stroked_path(
    builder: *PathPictureBuilderImpl,
    path: *const PathImpl,
    stroke: SnailStrokeStyle,
    transform: SnailTransform2D,
) c_int {
    builder.inner.addStrokedPath(&path.inner, toStrokeStyle(stroke) catch return SNAIL_ERR_INVALID_ARGUMENT, toTransform(transform)) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_path_picture_builder_add_rect(builder: *PathPictureBuilderImpl, rect: SnailRect, fill: ?*const SnailFillStyle, stroke: ?*const SnailStrokeStyle, transform: SnailTransform2D) c_int {
    builder.inner.addRect(toRect(rect), toOptFill(fill) catch return SNAIL_ERR_INVALID_ARGUMENT, toOptStroke(stroke) catch return SNAIL_ERR_INVALID_ARGUMENT, toTransform(transform)) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_path_picture_builder_add_rounded_rect(builder: *PathPictureBuilderImpl, rect: SnailRect, fill: ?*const SnailFillStyle, stroke: ?*const SnailStrokeStyle, corner_radius: f32, transform: SnailTransform2D) c_int {
    builder.inner.addRoundedRect(toRect(rect), toOptFill(fill) catch return SNAIL_ERR_INVALID_ARGUMENT, toOptStroke(stroke) catch return SNAIL_ERR_INVALID_ARGUMENT, corner_radius, toTransform(transform)) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_path_picture_builder_add_ellipse(builder: *PathPictureBuilderImpl, rect: SnailRect, fill: ?*const SnailFillStyle, stroke: ?*const SnailStrokeStyle, transform: SnailTransform2D) c_int {
    builder.inner.addEllipse(toRect(rect), toOptFill(fill) catch return SNAIL_ERR_INVALID_ARGUMENT, toOptStroke(stroke) catch return SNAIL_ERR_INVALID_ARGUMENT, toTransform(transform)) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_path_picture_builder_freeze(builder: *const PathPictureBuilderImpl, alloc_ptr: ?*const SnailAllocator, scratch_alloc_ptr: ?*const SnailAllocator, out: *?*PathPictureImpl) c_int {
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

pub export fn snail_path_picture_deinit(picture: ?*PathPictureImpl) void {
    if (picture) |p| {
        p.inner.deinit();
        destroyHandle(p);
    }
}

pub export fn snail_path_picture_shape_count(picture: *const PathPictureImpl) usize {
    return picture.inner.shapeCount();
}

pub export fn snail_path_picture_upload_footprint(picture: *const PathPictureImpl, out: *SnailResourceFootprint) void {
    out.* = fromResourceFootprint(picture.inner.uploadFootprint());
}

pub export fn snail_path_picture_builder_shape_count(builder: *const PathPictureBuilderImpl) usize {
    return builder.inner.shapeCount();
}

pub export fn snail_path_picture_builder_mark(builder: *const PathPictureBuilderImpl) SnailShapeMark {
    return fromShapeMark(builder.inner.mark());
}

pub export fn snail_path_picture_builder_range_from(builder: *const PathPictureBuilderImpl, mark: SnailShapeMark, out: *SnailRange) c_int {
    out.* = fromRange(builder.inner.rangeFrom(toShapeMark(mark)) catch |err| return mapError(err));
    return SNAIL_OK;
}

pub export fn snail_path_picture_builder_range_between(builder: *const PathPictureBuilderImpl, start: SnailShapeMark, end: SnailShapeMark, out: *SnailRange) c_int {
    out.* = fromRange(builder.inner.rangeBetween(toShapeMark(start), toShapeMark(end)) catch |err| return mapError(err));
    return SNAIL_OK;
}
