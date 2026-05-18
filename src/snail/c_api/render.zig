const common = @import("common.zig");
const snail = common.snail;
const resolveAllocator = common.resolveAllocator;
const handleAllocator = common.handleAllocator;
const mapError = common.mapError;
const SnailAllocator = common.SnailAllocator;
const SNAIL_OK = common.SNAIL_OK;
const SNAIL_ERR_OUT_OF_MEMORY = common.SNAIL_ERR_OUT_OF_MEMORY;
const SNAIL_ERR_INVALID_ARGUMENT = common.SNAIL_ERR_INVALID_ARGUMENT;
const SnailDrawPass = common.SnailDrawPass;
const SnailDrawState = common.SnailDrawState;
const SnailResourceKey = common.SnailResourceKey;
const SnailResourceFootprint = common.SnailResourceFootprint;
const SnailResourceCacheStats = common.SnailResourceCacheStats;
const fromResourceFootprint = common.fromResourceFootprint;
const fromResourceCacheStats = common.fromResourceCacheStats;
const toDrawPass = common.toDrawPass;
const toDrawState = common.toDrawState;
const ResourceManifestImpl = common.ResourceManifestImpl;
const PreparedResourcesImpl = common.PreparedResourcesImpl;
const PreparedSceneImpl = common.PreparedSceneImpl;
const ResourceUploadPlanImpl = common.ResourceUploadPlanImpl;
const PendingResourceUploadImpl = common.PendingResourceUploadImpl;
const DrawListImpl = common.DrawListImpl;
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
    set: *const ResourceManifestImpl,
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
    next_set: *const ResourceManifestImpl,
    out: *?*ResourceUploadPlanImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    var erased = renderer.asRenderer();
    const plan = erased.planResourceUpload(
        allocator,
        if (current) |prepared| &prepared.inner else null,
        &next_set.inner,
    ) catch |err| return mapError(err);
    const impl = handleAllocator().create(ResourceUploadPlanImpl) catch {
        var doomed = plan;
        doomed.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = plan };
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_resource_upload_plan_deinit(plan: ?*ResourceUploadPlanImpl) void {
    if (plan) |p| {
        p.inner.deinit();
        destroyHandle(p);
    }
}

pub export fn snail_resource_upload_plan_footprint(plan: *const ResourceUploadPlanImpl) SnailResourceFootprint {
    return fromResourceFootprint(plan.inner.footprint);
}

pub export fn snail_resource_upload_plan_upload_estimate_bytes(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.upload.bytes;
}

pub export fn snail_resource_upload_plan_cache_reused_atlas_pages(plan: *const ResourceUploadPlanImpl) u32 {
    return plan.inner.cache.reused_atlas_pages;
}

pub export fn snail_resource_upload_plan_cache_missing_atlas_pages(plan: *const ResourceUploadPlanImpl) u32 {
    return plan.inner.cache.missing_atlas_pages;
}

pub export fn snail_resource_upload_plan_cache_new_atlas_banks(plan: *const ResourceUploadPlanImpl) u32 {
    return plan.inner.cache.new_atlas_banks;
}

pub export fn snail_resource_upload_plan_cache_reused_images(plan: *const ResourceUploadPlanImpl) u32 {
    return plan.inner.cache.reused_images;
}

pub export fn snail_resource_upload_plan_cache_missing_images(plan: *const ResourceUploadPlanImpl) u32 {
    return plan.inner.cache.missing_images;
}

pub export fn snail_resource_upload_plan_cache_new_image_banks(plan: *const ResourceUploadPlanImpl) u32 {
    return plan.inner.cache.new_image_banks;
}

pub export fn snail_resource_upload_plan_cache_atlas_rebuilds(plan: *const ResourceUploadPlanImpl) u32 {
    return plan.inner.cache.atlas_rebuilds;
}

pub export fn snail_resource_upload_plan_cache_image_rebuilds(plan: *const ResourceUploadPlanImpl) u32 {
    return plan.inner.cache.image_rebuilds;
}

pub export fn snail_resource_upload_plan_upload_estimate_curve_bytes(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.upload.curve_bytes;
}

pub export fn snail_resource_upload_plan_upload_estimate_band_bytes(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.upload.band_bytes;
}

pub export fn snail_resource_upload_plan_upload_estimate_layer_info_bytes(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.upload.layer_info_bytes;
}

pub export fn snail_resource_upload_plan_upload_estimate_image_bytes(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.upload.image_bytes;
}

pub export fn snail_resource_upload_plan_diff_changed_bytes(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.diff.changed_bytes;
}

pub export fn snail_resource_upload_plan_diff_changed_key_count(plan: *const ResourceUploadPlanImpl) usize {
    return plan.inner.diff.keys().len;
}

pub export fn snail_resource_upload_plan_diff_changed_key(plan: *const ResourceUploadPlanImpl, index: usize, out: *SnailResourceKey) bool {
    const keys = plan.inner.diff.keys();
    if (index >= keys.len) return false;
    out.* = keys[index].id;
    return true;
}

pub export fn snail_renderer_begin_resource_upload(
    renderer: *RendererImpl,
    alloc_ptr: ?*const SnailAllocator,
    plan: *const ResourceUploadPlanImpl,
    out: *?*PendingResourceUploadImpl,
) c_int {
    const allocator = resolveAllocator(alloc_ptr);
    var erased = renderer.asRenderer();
    const pending = erased.beginResourceUpload(.{ .persistent = allocator, .scratch = allocator }, &plan.inner) catch |err| return mapError(err);
    const impl = handleAllocator().create(PendingResourceUploadImpl) catch {
        var doomed = pending;
        doomed.deinit();
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.* = .{ .inner = pending };
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_pending_resource_upload_deinit(pending: ?*PendingResourceUploadImpl) void {
    if (pending) |p| {
        p.inner.deinit();
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
    state: SnailDrawState,
) c_int {
    var erased = renderer.asRenderer();
    erased.draw(&prepared.inner, list.inner.slice(), toDrawState(state) catch return SNAIL_ERR_INVALID_ARGUMENT) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_renderer_draw_pass(
    renderer: *RendererImpl,
    prepared: *const PreparedResourcesImpl,
    list: *const DrawListImpl,
    pass: SnailDrawPass,
) c_int {
    var erased = renderer.asRenderer();
    erased.drawPass(&prepared.inner, list.inner.slice(), toDrawPass(pass) catch return SNAIL_ERR_INVALID_ARGUMENT) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_renderer_draw_prepared(
    renderer: *RendererImpl,
    prepared: *const PreparedResourcesImpl,
    scene: *const PreparedSceneImpl,
    state: SnailDrawState,
) c_int {
    var erased = renderer.asRenderer();
    erased.drawPrepared(&prepared.inner, &scene.inner, toDrawState(state) catch return SNAIL_ERR_INVALID_ARGUMENT) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_renderer_draw_prepared_pass(
    renderer: *RendererImpl,
    prepared: *const PreparedResourcesImpl,
    scene: *const PreparedSceneImpl,
    pass: SnailDrawPass,
) c_int {
    var erased = renderer.asRenderer();
    erased.drawPreparedPass(&prepared.inner, &scene.inner, toDrawPass(pass) catch return SNAIL_ERR_INVALID_ARGUMENT) catch |err| return mapError(err);
    return SNAIL_OK;
}
