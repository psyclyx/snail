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

// Scene and resources

pub export fn snail_scene_init(alloc_ptr: ?*const SnailAllocator, out: *?*SceneImpl) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    const impl = handleAllocator().create(SceneImpl) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.* = .{
        .inner = snail.Scene.init(allocator),
        .overrides_arena = std.heap.ArenaAllocator.init(allocator),
    };
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_scene_deinit(scene: ?*SceneImpl) void {
    if (scene) |s| {
        s.inner.deinit();
        s.overrides_arena.deinit();
        destroyHandle(s);
    }
}

pub export fn snail_scene_reset(scene: *SceneImpl) void {
    scene.inner.reset();
    _ = scene.overrides_arena.reset(.retain_capacity);
}

pub export fn snail_scene_command_count(scene: *const SceneImpl) usize {
    return scene.inner.commandCount();
}

fn stashOverride(scene: *SceneImpl, override: snail.Override) ![]const snail.Override {
    const slot = try scene.overrides_arena.allocator().alloc(snail.Override, 1);
    slot[0] = override;
    return slot;
}

pub export fn snail_scene_add_text(scene: *SceneImpl, blob: *const TextBlobImpl) c_int {
    scene.inner.addText(.{ .blob = &blob.inner }) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_scene_add_text_transformed(scene: *SceneImpl, blob: *const TextBlobImpl, transform: SnailTransform2D) c_int {
    return snail_scene_add_text_override(scene, blob, .{ .transform = transform });
}

pub export fn snail_scene_add_text_override(scene: *SceneImpl, blob: *const TextBlobImpl, override_value: SnailOverride) c_int {
    const instances = stashOverride(scene, toOverride(override_value)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    scene.inner.addText(.{
        .blob = &blob.inner,
        .instances = instances,
    }) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_scene_add_path_picture(scene: *SceneImpl, picture: *const PathPictureImpl) c_int {
    scene.inner.addPath(.{ .picture = &picture.inner }) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_scene_add_path_picture_range(scene: *SceneImpl, picture: *const PathPictureImpl, range: SnailRange) c_int {
    scene.inner.addPath(.{
        .picture = &picture.inner,
        .shapes = toRange(range),
    }) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_scene_add_path_picture_transformed(scene: *SceneImpl, picture: *const PathPictureImpl, transform: SnailTransform2D) c_int {
    return snail_scene_add_path_picture_override(scene, picture, .{ .transform = transform });
}

pub export fn snail_scene_add_path_picture_range_transformed(scene: *SceneImpl, picture: *const PathPictureImpl, range: SnailRange, transform: SnailTransform2D) c_int {
    return snail_scene_add_path_picture_range_override(scene, picture, range, .{ .transform = transform });
}

pub export fn snail_scene_add_path_picture_override(scene: *SceneImpl, picture: *const PathPictureImpl, override_value: SnailOverride) c_int {
    const instances = stashOverride(scene, toOverride(override_value)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    scene.inner.addPath(.{ .picture = &picture.inner, .instances = instances }) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_scene_add_path_picture_range_override(scene: *SceneImpl, picture: *const PathPictureImpl, range: SnailRange, override_value: SnailOverride) c_int {
    const instances = stashOverride(scene, toOverride(override_value)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    scene.inner.addPath(.{
        .picture = &picture.inner,
        .shapes = toRange(range),
        .instances = instances,
    }) catch |err| return mapError(err);
    return SNAIL_OK;
}
