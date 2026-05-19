const common = @import("common.zig");
const std = common.std;
const snail = common.snail;
const build_options = common.build_options;
const c_runtime = common.c_runtime;
const createHandle = common.createHandle;
const allocatorForHandle = common.allocatorForHandle;
const mapError = common.mapError;
const SnailAllocator = common.SnailAllocator;
const SNAIL_OK = common.SNAIL_OK;
const SNAIL_ERR_OUT_OF_MEMORY = common.SNAIL_ERR_OUT_OF_MEMORY;
const SNAIL_ERR_INVALID_ARGUMENT = common.SNAIL_ERR_INVALID_ARGUMENT;
const SNAIL_ERR_DRAW_FAILED = common.SNAIL_ERR_DRAW_FAILED;
const SnailTransform2D = common.SnailTransform2D;
const SnailDrawState = common.SnailDrawState;
const SnailCoverageDrawState = common.SnailCoverageDrawState;
const SnailResourceKey = common.SnailResourceKey;
const SnailTextResourceKeys = common.SnailTextResourceKeys;
const SnailResourceStamp = common.SnailResourceStamp;
const SnailResourceFootprint = common.SnailResourceFootprint;
const wrapResourceStamp = common.wrapResourceStamp;
const wrapTextResourceKeys = common.wrapTextResourceKeys;
const fromCoverageDrawState = common.fromCoverageDrawState;
const toTransform = common.toTransform;
const toDrawState = common.toDrawState;
const toTextResourceKeys = common.toTextResourceKeys;
const fromResourceFootprint = common.fromResourceFootprint;
const toResourceCapacityMode = common.toResourceCapacityMode;
const reservedResourceCapacityMode = common.reservedResourceCapacityMode;
const TextAtlasImpl = common.TextAtlasImpl;
const TextBlobImpl = common.TextBlobImpl;
const ImageImpl = common.ImageImpl;
const PathPictureImpl = common.PathPictureImpl;
const SceneImpl = common.SceneImpl;
const ResourceManifestImpl = common.ResourceManifestImpl;
const PreparedResourcesImpl = common.PreparedResourcesImpl;
const PreparedSceneImpl = common.PreparedSceneImpl;
const PreparedResourceRetirementQueueImpl = common.PreparedResourceRetirementQueueImpl;
const DrawListImpl = common.DrawListImpl;
const TextCoverageRecordsImpl = common.TextCoverageRecordsImpl;
const CoverageBackendImpl = common.CoverageBackendImpl;
const RendererImpl = common.RendererImpl;
const destroyHandle = common.destroyHandle;

pub export fn snail_resource_manifest_init(alloc_ptr: ?*const SnailAllocator, capacity: usize, out: *?*ResourceManifestImpl) c_int {
    const impl = createHandle(ResourceManifestImpl, alloc_ptr) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const allocator = allocatorForHandle(impl);
    const entries = allocator.alloc(snail.ResourceManifest.Entry, capacity) catch {
        destroyHandle(impl);
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.inner = snail.ResourceManifest.init(entries);
    impl.entries = entries;
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_resource_manifest_deinit(set: ?*ResourceManifestImpl) void {
    if (set) |s| {
        allocatorForHandle(s).free(s.entries);
        destroyHandle(s);
    }
}

pub export fn snail_resource_manifest_reset(set: *ResourceManifestImpl) void {
    set.inner.reset();
}

pub export fn snail_resource_manifest_count(set: *const ResourceManifestImpl) usize {
    return set.inner.len;
}

pub export fn snail_resource_manifest_capacity(set: *const ResourceManifestImpl) usize {
    return set.inner.capacity();
}

pub export fn snail_resource_manifest_put_text_atlas(set: *ResourceManifestImpl, key: SnailResourceKey, atlas: *const TextAtlasImpl) c_int {
    set.inner.putTextAtlas(snail.ResourceKey.fromOpaque(key), &atlas.inner) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_resource_manifest_put_text_atlas_options(set: *ResourceManifestImpl, key: SnailResourceKey, atlas: *const TextAtlasImpl, atlas_capacity: c_int) c_int {
    set.inner.putTextAtlasOptions(snail.ResourceKey.fromOpaque(key), &atlas.inner, .{
        .atlas_capacity = toResourceCapacityMode(atlas_capacity) catch return SNAIL_ERR_INVALID_ARGUMENT,
    }) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_resource_manifest_put_text_atlas_reserved(set: *ResourceManifestImpl, key: SnailResourceKey, atlas: *const TextAtlasImpl, reserved_pages: u32) c_int {
    set.inner.putTextAtlasOptions(snail.ResourceKey.fromOpaque(key), &atlas.inner, .{
        .atlas_capacity = reservedResourceCapacityMode(reserved_pages),
    }) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_resource_manifest_put_text_paint(set: *ResourceManifestImpl, key: SnailResourceKey, blob: *const TextBlobImpl) c_int {
    set.inner.putTextPaint(snail.ResourceKey.fromOpaque(key), &blob.inner) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_text_blob_resource_keys(atlas_key: SnailResourceKey, blob_key: SnailResourceKey, blob: *const TextBlobImpl, out: *SnailTextResourceKeys) c_int {
    out.* = wrapTextResourceKeys(snail.ResourceManifest.textBlobResourceKeys(
        snail.ResourceKey.fromOpaque(atlas_key),
        snail.ResourceKey.fromOpaque(blob_key),
        &blob.inner,
    ));
    return SNAIL_OK;
}

pub export fn snail_resource_manifest_put_path_picture(set: *ResourceManifestImpl, key: SnailResourceKey, picture: *const PathPictureImpl) c_int {
    set.inner.putPathPicture(snail.ResourceKey.fromOpaque(key), &picture.inner) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_resource_manifest_put_path_picture_options(set: *ResourceManifestImpl, key: SnailResourceKey, picture: *const PathPictureImpl, atlas_capacity: c_int) c_int {
    set.inner.putPathPictureOptions(snail.ResourceKey.fromOpaque(key), &picture.inner, .{
        .atlas_capacity = toResourceCapacityMode(atlas_capacity) catch return SNAIL_ERR_INVALID_ARGUMENT,
    }) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_resource_manifest_put_path_picture_reserved(set: *ResourceManifestImpl, key: SnailResourceKey, picture: *const PathPictureImpl, reserved_pages: u32) c_int {
    set.inner.putPathPictureOptions(snail.ResourceKey.fromOpaque(key), &picture.inner, .{
        .atlas_capacity = reservedResourceCapacityMode(reserved_pages),
    }) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_resource_manifest_put_image(set: *ResourceManifestImpl, key: SnailResourceKey, image: *const ImageImpl) c_int {
    set.inner.putImage(snail.ResourceKey.fromOpaque(key), &image.inner) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_resource_manifest_estimate_upload_footprint(set: *const ResourceManifestImpl, out: *SnailResourceFootprint) c_int {
    out.* = fromResourceFootprint(set.inner.estimateUploadFootprint() catch |err| return mapError(err));
    return SNAIL_OK;
}

pub export fn snail_prepared_resources_deinit(prepared: ?*PreparedResourcesImpl) void {
    if (prepared) |p| {
        p.inner.deinit();
        destroyHandle(p);
    }
}

pub export fn snail_prepared_resources_stamp_for_key(prepared: *const PreparedResourcesImpl, key: SnailResourceKey, out: *SnailResourceStamp) bool {
    if (prepared.inner.stampForKey(snail.ResourceKey.fromOpaque(key))) |stamp| {
        out.* = wrapResourceStamp(stamp);
        return true;
    }
    return false;
}

pub export fn snail_prepared_scene_init(
    alloc_ptr: ?*const SnailAllocator,
    prepared: *const PreparedResourcesImpl,
    scene: *const SceneImpl,
    out: *?*PreparedSceneImpl,
) c_int {
    const impl = createHandle(PreparedSceneImpl, alloc_ptr) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const allocator = allocatorForHandle(impl);
    const prepared_scene = snail.PreparedScene.initOwned(allocator, &prepared.inner, &scene.inner) catch |err| {
        destroyHandle(impl);
        return mapError(err);
    };
    impl.inner = prepared_scene;
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_prepared_scene_deinit(scene: ?*PreparedSceneImpl) void {
    if (scene) |s| {
        s.inner.deinit();
        destroyHandle(s);
    }
}

pub export fn snail_prepared_scene_word_count(scene: *const PreparedSceneImpl) usize {
    return scene.inner.words.len;
}

pub export fn snail_prepared_scene_segment_count(scene: *const PreparedSceneImpl) usize {
    return scene.inner.segments.len;
}

pub export fn snail_prepared_resource_retirement_queue_init(alloc_ptr: ?*const SnailAllocator, out: *?*PreparedResourceRetirementQueueImpl) c_int {
    const impl = createHandle(PreparedResourceRetirementQueueImpl, alloc_ptr) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.inner = snail.PreparedResourceRetirementQueue.init(allocatorForHandle(impl));
    impl.retained_resource_allocators = .empty;
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_prepared_resource_retirement_queue_deinit(queue: ?*PreparedResourceRetirementQueueImpl) void {
    if (queue) |q| {
        q.inner.deinit();
        for (q.retained_resource_allocators.items) |allocator| c_runtime.destroyStoredAllocator(allocator);
        q.retained_resource_allocators.deinit(allocatorForHandle(q));
        destroyHandle(q);
    }
}

pub export fn snail_prepared_resource_retirement_queue_sweep(queue: *PreparedResourceRetirementQueueImpl) void {
    queue.inner.sweep();
}

fn preparedRetirementMayDelay(prepared: *const PreparedResourcesImpl) bool {
    if (comptime build_options.enable_vulkan) return prepared.inner.resident.vulkan != null;
    return false;
}

fn retainPreparedResourceAllocator(queue: *PreparedResourceRetirementQueueImpl, prepared: *PreparedResourcesImpl) !*c_runtime.StoredAllocator {
    const retained = c_runtime.retainStoredAllocator(prepared.handle_allocator);
    errdefer c_runtime.destroyStoredAllocator(retained);
    try queue.retained_resource_allocators.append(allocatorForHandle(queue), retained);
    return retained;
}

fn undoRetainedPreparedResourceAllocator(queue: *PreparedResourceRetirementQueueImpl, retained: *c_runtime.StoredAllocator) void {
    std.debug.assert(queue.retained_resource_allocators.items.len > 0);
    queue.retained_resource_allocators.items.len -= 1;
    c_runtime.destroyStoredAllocator(retained);
}

pub export fn snail_prepared_resource_retirement_queue_retire(queue: *PreparedResourceRetirementQueueImpl, prepared: *PreparedResourcesImpl) c_int {
    const retained_allocator = if (preparedRetirementMayDelay(prepared))
        retainPreparedResourceAllocator(queue, prepared) catch return SNAIL_ERR_OUT_OF_MEMORY
    else
        null;
    queue.inner.retireAfter(&prepared.inner, {}) catch |err| {
        if (retained_allocator) |retained| undoRetainedPreparedResourceAllocator(queue, retained);
        return mapError(err);
    };
    destroyHandle(prepared);
    return SNAIL_OK;
}

pub export fn snail_draw_list_estimate_word_count(scene: *const SceneImpl) usize {
    return snail.DrawList.estimate(&scene.inner);
}

pub export fn snail_draw_list_estimate_segment_count(scene: *const SceneImpl) usize {
    return snail.DrawList.estimateSegments(&scene.inner);
}

pub export fn snail_draw_list_init(alloc_ptr: ?*const SnailAllocator, word_capacity: usize, segment_capacity: usize, out: *?*DrawListImpl) c_int {
    const impl = createHandle(DrawListImpl, alloc_ptr) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const allocator = allocatorForHandle(impl);
    const words = allocator.alloc(u32, word_capacity) catch {
        destroyHandle(impl);
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    const segments = allocator.alloc(snail.DrawSegment, segment_capacity) catch {
        allocator.free(words);
        destroyHandle(impl);
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.inner = snail.DrawList.init(words, segments);
    impl.words = words;
    impl.segments = segments;
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_draw_list_deinit(list: ?*DrawListImpl) void {
    if (list) |l| {
        const allocator = allocatorForHandle(l);
        allocator.free(l.words);
        allocator.free(l.segments);
        destroyHandle(l);
    }
}

pub export fn snail_draw_list_reset(list: *DrawListImpl) void {
    list.inner.reset();
}

pub export fn snail_draw_list_word_count(list: *const DrawListImpl) usize {
    return list.inner.len;
}

pub export fn snail_draw_list_word_capacity(list: *const DrawListImpl) usize {
    return list.words.len;
}

pub export fn snail_draw_list_segment_count(list: *const DrawListImpl) usize {
    return list.inner.segment_len;
}

pub export fn snail_draw_list_segment_capacity(list: *const DrawListImpl) usize {
    return list.segments.len;
}

pub export fn snail_draw_list_words(list: *const DrawListImpl) ?[*]const u32 {
    if (list.inner.len == 0) return null;
    return list.words.ptr;
}

pub export fn snail_draw_list_add_scene(list: *DrawListImpl, prepared: *const PreparedResourcesImpl, scene: *const SceneImpl) c_int {
    list.inner.addScene(&prepared.inner, &scene.inner) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_text_coverage_records_word_capacity_for_blob(blob: *const TextBlobImpl) usize {
    return snail.coverage.TextCoverageRecords.wordCapacityForBlob(&blob.inner);
}

pub export fn snail_text_coverage_records_init(alloc_ptr: ?*const SnailAllocator, word_capacity: usize, out: *?*TextCoverageRecordsImpl) c_int {
    const impl = createHandle(TextCoverageRecordsImpl, alloc_ptr) catch return SNAIL_ERR_OUT_OF_MEMORY;
    const allocator = allocatorForHandle(impl);
    const words = allocator.alloc(u32, word_capacity) catch {
        destroyHandle(impl);
        return SNAIL_ERR_OUT_OF_MEMORY;
    };
    impl.inner = snail.coverage.TextCoverageRecords.init(words);
    impl.words = words;
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_text_coverage_records_deinit(records: ?*TextCoverageRecordsImpl) void {
    if (records) |r| {
        allocatorForHandle(r).free(r.words);
        destroyHandle(r);
    }
}

pub export fn snail_text_coverage_records_reset(records: *TextCoverageRecordsImpl) void {
    records.inner.reset();
}

pub export fn snail_text_coverage_records_word_count(records: *const TextCoverageRecordsImpl) usize {
    return records.inner.slice().len;
}

pub export fn snail_text_coverage_records_glyph_count(records: *const TextCoverageRecordsImpl) usize {
    return records.inner.glyphCount();
}

pub export fn snail_text_coverage_records_layer_window_base(records: *const TextCoverageRecordsImpl) u32 {
    return records.inner.layerWindowBase();
}

pub export fn snail_text_coverage_records_words(records: *const TextCoverageRecordsImpl) ?[*]const u32 {
    if (records.inner.len == 0) return null;
    return records.words.ptr;
}

pub export fn snail_text_coverage_records_build_local(records: *TextCoverageRecordsImpl, prepared: *const PreparedResourcesImpl, blob: *const TextBlobImpl, resources: SnailTextResourceKeys, transform: SnailTransform2D) c_int {
    records.inner.buildLocal(&prepared.inner, &blob.inner, .{
        .resources = toTextResourceKeys(resources),
        .transform = toTransform(transform),
    }) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_text_coverage_records_draw_state(records: *const TextCoverageRecordsImpl, state: SnailDrawState, out: *SnailCoverageDrawState) c_int {
    const draw_state = toDrawState(state) catch return SNAIL_ERR_INVALID_ARGUMENT;
    out.* = fromCoverageDrawState(snail.coverage.drawStateFor(&records.inner, draw_state));
    return SNAIL_OK;
}

pub export fn snail_text_coverage_records_valid_for(records: *const TextCoverageRecordsImpl, prepared: *const PreparedResourcesImpl) bool {
    return records.inner.validFor(&prepared.inner);
}

fn coverageBackendPrepared(backend: *const CoverageBackendImpl) ?*const snail.PreparedResources {
    return switch (backend.inner) {
        .gl => |gl_backend| if (comptime build_options.enable_opengl) gl_backend.prepared else null,
        .vulkan => |vk_backend| if (comptime build_options.enable_vulkan) vk_backend.prepared else null,
        .cpu => null,
    };
}

pub export fn snail_coverage_backend_init(renderer: *RendererImpl, prepared: *const PreparedResourcesImpl, out: *?*CoverageBackendImpl) c_int {
    var erased = renderer.asRenderer();
    const backend = prepared.inner.coverageBackend(&erased) orelse return SNAIL_ERR_INVALID_ARGUMENT;
    const impl = createHandle(CoverageBackendImpl, null) catch return SNAIL_ERR_OUT_OF_MEMORY;
    impl.inner = backend;
    out.* = impl;
    return SNAIL_OK;
}

pub export fn snail_coverage_backend_deinit(backend: ?*CoverageBackendImpl) void {
    if (backend) |b| destroyHandle(b);
}

pub export fn snail_coverage_backend_draw_coverage(backend: *CoverageBackendImpl, records: *const TextCoverageRecordsImpl) c_int {
    const prepared = coverageBackendPrepared(backend) orelse return SNAIL_ERR_INVALID_ARGUMENT;
    if (!records.inner.validFor(prepared)) return SNAIL_ERR_DRAW_FAILED;
    backend.inner.drawCoverage(&records.inner) catch return SNAIL_ERR_DRAW_FAILED;
    return SNAIL_OK;
}

pub export fn snail_coverage_backend_draw_words(backend: *CoverageBackendImpl, words: ?[*]const u32, word_count: usize) c_int {
    if (coverageBackendPrepared(backend) == null) return SNAIL_ERR_INVALID_ARGUMENT;
    if (word_count == 0) {
        backend.inner.drawVertices(&.{}) catch return SNAIL_ERR_DRAW_FAILED;
        return SNAIL_OK;
    }
    const word_ptr = words orelse return SNAIL_ERR_INVALID_ARGUMENT;
    backend.inner.drawVertices(word_ptr[0..word_count]) catch return SNAIL_ERR_DRAW_FAILED;
    return SNAIL_OK;
}
