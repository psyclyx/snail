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

pub export fn snail_renderer_deinit(renderer: ?*RendererImpl) void {
    if (renderer) |r| {
        r.deinit();
        destroyHandle(r);
    }
}

pub export fn snail_renderer_backend_name(renderer: *const RendererImpl) [*:0]const u8 {
    return @ptrCast(renderer.backendName().ptr);
}

pub export fn snail_renderer_resource_cache_stats(renderer: *RendererImpl, out: *SnailResourceCacheStats) void {
    var erased = renderer.asRenderer();
    out.* = fromResourceCacheStats(erased.resourceCacheStats());
}

pub export fn snail_renderer_reset_resource_cache(renderer: *RendererImpl) void {
    var erased = renderer.asRenderer();
    erased.resetResourceCache();
}

pub export fn snail_renderer_upload_resources_blocking(
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

pub export fn snail_renderer_plan_resource_upload(
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

pub export fn snail_resource_upload_plan_deinit(plan: ?*ResourceUploadPlanImpl) void {
    if (plan) |p| {
        p.allocator.free(p.changed_keys);
        destroyHandle(p);
    }
}

pub export fn snail_resource_upload_plan_footprint(plan: *const ResourceUploadPlanImpl) SnailResourceFootprint {
    return fromResourceFootprint(plan.inner.upload_footprint);
}

pub export fn snail_resource_upload_plan_upload_bytes(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.upload_bytes;
}

pub export fn snail_resource_upload_plan_reused_atlas_pages(plan: *const ResourceUploadPlanImpl) u32 {
    return plan.inner.reused_atlas_pages;
}

pub export fn snail_resource_upload_plan_missing_atlas_pages(plan: *const ResourceUploadPlanImpl) u32 {
    return plan.inner.missing_atlas_pages;
}

pub export fn snail_resource_upload_plan_reused_images(plan: *const ResourceUploadPlanImpl) u32 {
    return plan.inner.reused_images;
}

pub export fn snail_resource_upload_plan_missing_images(plan: *const ResourceUploadPlanImpl) u32 {
    return plan.inner.missing_images;
}

pub export fn snail_resource_upload_plan_atlas_cache_rebuilds(plan: *const ResourceUploadPlanImpl) u32 {
    return plan.inner.atlas_cache_rebuilds;
}

pub export fn snail_resource_upload_plan_image_cache_rebuilds(plan: *const ResourceUploadPlanImpl) u32 {
    return plan.inner.image_cache_rebuilds;
}

pub export fn snail_resource_upload_plan_curve_bytes(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.curve_bytes_upload;
}

pub export fn snail_resource_upload_plan_band_bytes(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.band_bytes_upload;
}

pub export fn snail_resource_upload_plan_layer_info_bytes(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.layer_info_bytes_upload;
}

pub export fn snail_resource_upload_plan_image_bytes(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.image_bytes_upload;
}

pub export fn snail_resource_upload_plan_changed_bytes(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.changed_bytes;
}

pub export fn snail_resource_upload_plan_changed_key_count(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.changed_len;
}

pub export fn snail_resource_upload_plan_changed_key(plan: *const ResourceUploadPlanImpl, index: usize, out: *SnailResourceKey) bool {
    if (index >= plan.inner.changed_len) return false;
    out.* = plan.inner.changed_keys[index].id;
    return true;
}

pub export fn snail_renderer_begin_resource_upload(
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

pub export fn snail_pending_resource_upload_deinit(pending: ?*PendingResourceUploadImpl) void {
    if (pending) |p| {
        p.inner.deinit();
        p.allocator.free(p.changed_keys);
        destroyHandle(p);
    }
}

pub export fn snail_pending_resource_upload_record(pending: *PendingResourceUploadImpl, budget_bytes: usize) c_int {
    pending.inner.record(.no_command, .{ .budget_bytes = budget_bytes }) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_pending_resource_upload_record_checked(pending: *PendingResourceUploadImpl, budget_bytes: usize, allow_cache_rebuilds: bool) c_int {
    pending.inner.record(.no_command, .{
        .budget_bytes = budget_bytes,
        .allow_cache_rebuilds = allow_cache_rebuilds,
    }) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_pending_resource_upload_ready(pending: *PendingResourceUploadImpl, ready: bool) bool {
    return pending.inner.ready(.{ .ready = ready });
}

pub export fn snail_pending_resource_upload_ready_now(pending: *PendingResourceUploadImpl) bool {
    return pending.inner.ready(.immediate);
}

pub export fn snail_pending_resource_upload_publish(pending: *PendingResourceUploadImpl, out: *?*PreparedResourcesImpl) c_int {
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

pub export fn snail_renderer_draw(
    renderer: *RendererImpl,
    prepared: *const PreparedResourcesImpl,
    list: *const DrawListImpl,
    options: SnailDrawOptions,
) c_int {
    var erased = renderer.asRenderer();
    erased.draw(&prepared.inner, list.inner.slice(), toDrawOptions(options) catch return SNAIL_ERR_INVALID_ARGUMENT) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_renderer_draw_prepared(
    renderer: *RendererImpl,
    prepared: *const PreparedResourcesImpl,
    scene: *const PreparedSceneImpl,
    options: SnailDrawOptions,
) c_int {
    var erased = renderer.asRenderer();
    erased.drawPrepared(&prepared.inner, &scene.inner, toDrawOptions(options) catch return SNAIL_ERR_INVALID_ARGUMENT) catch |err| return mapError(err);
    return SNAIL_OK;
}
