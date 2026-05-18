const common = @import("common.zig");
const std = common.std;
const snail = common.snail;
const resolveAllocator = common.resolveAllocator;
const handleAllocator = common.handleAllocator;
const mapError = common.mapError;
const SnailAllocator = common.SnailAllocator;
const SNAIL_OK = common.SNAIL_OK;
const SNAIL_ERR_OUT_OF_MEMORY = common.SNAIL_ERR_OUT_OF_MEMORY;
const SNAIL_ERR_INVALID_ARGUMENT = common.SNAIL_ERR_INVALID_ARGUMENT;
const SnailTextDraw = common.SnailTextDraw;
const SnailPathPictureDraw = common.SnailPathPictureDraw;
const toOverride = common.toOverride;
const toRange = common.toRange;
const toTextResourceKeys = common.toTextResourceKeys;
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

pub export fn snail_scene_add_text_draw(scene: *SceneImpl, draw: SnailTextDraw) c_int {
    const blob = draw.blob orelse return SNAIL_ERR_INVALID_ARGUMENT;
    var text_draw = snail.TextDraw{
        .blob = &blob.inner,
        .resources = toTextResourceKeys(draw.resources),
    };
    if (draw.has_override) {
        text_draw.instances = stashOverride(scene, toOverride(draw.override_value)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    }
    scene.inner.addText(text_draw) catch |err| return mapError(err);
    return SNAIL_OK;
}

pub export fn snail_scene_add_path_picture_draw(scene: *SceneImpl, draw: SnailPathPictureDraw) c_int {
    const picture = draw.picture orelse return SNAIL_ERR_INVALID_ARGUMENT;
    var path_draw = snail.PathDraw{
        .picture = &picture.inner,
        .resource_key = snail.ResourceKey.fromOpaque(draw.key),
    };
    if (draw.has_range) path_draw.shapes = toRange(draw.range);
    if (draw.has_override) {
        path_draw.instances = stashOverride(scene, toOverride(draw.override_value)) catch return SNAIL_ERR_OUT_OF_MEMORY;
    }
    scene.inner.addPath(path_draw) catch |err| return mapError(err);
    return SNAIL_OK;
}
