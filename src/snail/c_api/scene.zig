const common = @import("common.zig");
const std = common.std;
const snail = common.snail;
const resolveAllocator = common.resolveAllocator;
const handleAllocator = common.handleAllocator;
const mapError = common.mapError;
const SnailAllocator = common.SnailAllocator;
const SNAIL_OK = common.SNAIL_OK;
const SNAIL_ERR_OUT_OF_MEMORY = common.SNAIL_ERR_OUT_OF_MEMORY;
const SnailTransform2D = common.SnailTransform2D;
const SnailOverride = common.SnailOverride;
const SnailRange = common.SnailRange;
const toOverride = common.toOverride;
const toRange = common.toRange;
const TextBlobImpl = common.TextBlobImpl;
const PathPictureImpl = common.PathPictureImpl;
const SceneImpl = common.SceneImpl;
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
