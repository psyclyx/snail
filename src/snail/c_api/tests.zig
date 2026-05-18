const std = @import("std");
const build_options = @import("build_options");
const snail = @import("../root.zig");
const c_api = @import("../c_api.zig");
const c = c_api.common;
const c_constants = c_api.constants;
const c_font = c_api.font;
const c_image = c_api.image;
const c_misc = c_api.misc;
const c_path = c_api.path;
const c_render = c_api.render;
const c_render_backends = c_api.render_backends;
const c_resources = c_api.resources;
const c_scene = c_api.scene;
const c_text = c_api.text;

const testing = std.testing;

fn testTextAtlas() !*c.test_api.TextAtlasImpl {
    const assets = @import("assets");
    var atlas: ?*c.test_api.TextAtlasImpl = null;
    const spec = c.SnailFaceSpec{
        .data = assets.noto_sans_regular.ptr,
        .len = assets.noto_sans_regular.len,
    };
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_atlas_init(null, @ptrCast(&spec), 1, &atlas));
    return atlas.?;
}

fn ensureForText(atlas_ptr: **c.test_api.TextAtlasImpl, text: []const u8) !void {
    var next: ?*c.test_api.TextAtlasImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_atlas_ensure_text(atlas_ptr.*, .{}, text.ptr, text.len, &next));
    if (next) |replacement| {
        c_text.snail_text_atlas_deinit(atlas_ptr.*);
        atlas_ptr.* = replacement;
    }
}

fn testDrawState(width: f32, height: f32) c.SnailDrawState {
    return .{
        .mvp = c_constants.snail_mat4_identity(),
        .surface = .{
            .pixel_width = width,
            .pixel_height = height,
            .attachment_encoding = 1,
            .stored_pixel_encoding = 1,
        },
    };
}

test "c_api: font metrics helper" {
    const assets = @import("assets");
    var font: ?*c.test_api.FontImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_font.snail_font_init(assets.noto_sans_regular.ptr, assets.noto_sans_regular.len, &font));
    defer c_font.snail_font_deinit(font);

    try testing.expect(c_font.snail_font_units_per_em(font.?) > 0);
    const gid = c_font.snail_font_glyph_index(font.?, 'A');
    try testing.expect(gid > 0);

    var metrics: c.SnailGlyphMetrics = undefined;
    try testing.expectEqual(c.SNAIL_OK, c_font.snail_font_glyph_metrics(font.?, gid, &metrics));
    try testing.expect(metrics.advance_width > 0);

    var decoration: c.SnailDecorationMetrics = undefined;
    try testing.expectEqual(c.SNAIL_OK, c_font.snail_font_decoration_metrics(font.?, &decoration));
    try testing.expect(decoration.underline_thickness > 0);

    var script: c.SnailScriptMetrics = undefined;
    try testing.expectEqual(c.SNAIL_OK, c_font.snail_font_superscript_metrics(font.?, &script));
    try testing.expect(script.y_size > 0);
    try testing.expectEqual(c.SNAIL_OK, c_font.snail_font_subscript_metrics(font.?, &script));
    try testing.expect(script.y_size > 0);
}

test "c_api: text atlas metrics and ensure glyphs" {
    const atlas = try testTextAtlas();
    defer c_text.snail_text_atlas_deinit(atlas);

    try testing.expectEqual(@as(usize, 1), c_text.snail_text_atlas_face_count(atlas));

    var primary_face: u16 = undefined;
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_atlas_primary_face_index(atlas, &primary_face));
    try testing.expectEqual(@as(u16, 0), primary_face);

    var upem: u16 = 0;
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_atlas_face_units_per_em(atlas, primary_face, &upem));
    try testing.expect(upem > 0);

    var line_metrics: c.SnailLineMetrics = undefined;
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_atlas_face_line_metrics(atlas, primary_face, &line_metrics));
    try testing.expect(line_metrics.ascent > 0);
    try testing.expect(line_metrics.descent < 0);

    var gid: u16 = 0;
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_atlas_glyph_index(atlas, primary_face, 'A', &gid));
    try testing.expect(gid > 0);

    var advance: i16 = 0;
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_atlas_advance_width(atlas, primary_face, gid, &advance));
    try testing.expect(advance > 0);

    var cell_metrics: c.SnailCellMetrics = undefined;
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_atlas_cell_metrics(atlas, .{}, 16, &cell_metrics));
    try testing.expect(cell_metrics.cell_width > 0);
    try testing.expect(cell_metrics.line_height > cell_metrics.cell_width);

    var measured: f32 = 0;
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_atlas_measure_text(atlas, .{}, "Hello", 5, 16, &measured));
    try testing.expect(measured > 0);

    var decoration_rect: c.SnailRect = undefined;
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_atlas_decoration_rect(atlas, 0, 0, 16, measured, 16, &decoration_rect));
    try testing.expect(decoration_rect.w == measured);
    try testing.expect(decoration_rect.h >= 1);

    var script_transform: c.SnailScriptTransform = undefined;
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_atlas_superscript_transform(atlas, 0, 16, 16, &script_transform));
    try testing.expect(script_transform.font_size > 0);
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_atlas_subscript_transform(atlas, 0, 16, 16, &script_transform));
    try testing.expect(script_transform.font_size > 0);

    var next: ?*c.test_api.TextAtlasImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_atlas_ensure_glyphs(atlas, primary_face, @ptrCast(&gid), 1, &next));
    try testing.expect(next != null);
    defer c_text.snail_text_atlas_deinit(next);

    var again: ?*c.test_api.TextAtlasImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_atlas_ensure_glyphs(next.?, primary_face, @ptrCast(&gid), 1, &again));
    try testing.expectEqual(@as(?*c.test_api.TextAtlasImpl, null), again);
}

test "c_api: text atlas shape ensure and blob" {
    var atlas = try testTextAtlas();
    defer c_text.snail_text_atlas_deinit(atlas);

    const text = "Hello";
    var shaped: ?*c.test_api.ShapedTextImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_atlas_shape_utf8(atlas, .{}, text.ptr, text.len, &shaped));
    defer c_text.snail_shaped_text_deinit(shaped);
    try testing.expectEqual(@as(usize, 5), c_text.snail_shaped_text_glyph_count(shaped.?));
    try testing.expect(c_text.snail_shaped_text_advance_x(shaped.?) > 0);

    var replacement: ?*c.test_api.TextAtlasImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_atlas_ensure_shaped(atlas, shaped.?, &replacement));
    if (replacement) |next| {
        c_text.snail_text_atlas_deinit(atlas);
        atlas = next;
    }

    var blob: ?*c.test_api.TextBlobImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_blob_init_from_shaped(null, atlas, shaped.?, .{
        .placement = .{ .baseline_x = 10, .baseline_y = 20, .em = 24 },
        .fill = .{ .kind = c.SNAIL_PAINT_SOLID, .paint_solid = .{ 1, 1, 1, 1 } },
    }, &blob));
    defer c_text.snail_text_blob_deinit(blob);
    try testing.expectEqual(@as(usize, 5), c_text.snail_text_blob_glyph_count(blob.?));
}

test "c_api: text blob rebound returns a new handle" {
    var atlas = try testTextAtlas();
    defer c_text.snail_text_atlas_deinit(atlas);
    try ensureForText(&atlas, "A");

    var blob: ?*c.test_api.TextBlobImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_blob_init_text(null, atlas, .{}, "A", 1, .{
        .placement = .{ .baseline_x = 0, .baseline_y = 24, .em = 24 },
        .fill = .{ .kind = c.SNAIL_PAINT_SOLID, .paint_solid = .{ 1, 1, 1, 1 } },
    }, &blob));
    defer c_text.snail_text_blob_deinit(blob);

    var next: ?*c.test_api.TextAtlasImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_atlas_ensure_text(atlas, .{}, "B", 1, &next));
    try testing.expect(next != null);

    var rebound: ?*c.test_api.TextBlobImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_blob_rebound(null, blob.?, next.?, &rebound));
    defer c_text.snail_text_blob_deinit(rebound);
    try testing.expectEqual(c_text.snail_text_blob_glyph_count(blob.?), c_text.snail_text_blob_glyph_count(rebound.?));
    c_text.snail_text_atlas_deinit(atlas);
    atlas = next.?;
}

test "c_api: invalid caller input maps to invalid argument" {
    var path: ?*c.test_api.PathImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_path.snail_path_init(null, &path));
    defer c_path.snail_path_deinit(path);
    try testing.expectEqual(c.SNAIL_ERR_INVALID_ARGUMENT, c_path.snail_path_line_to(path.?, 1, 1));

    const atlas = try testTextAtlas();
    defer c_text.snail_text_atlas_deinit(atlas);
    var resources: ?*c.test_api.ResourceSetImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_resources.snail_resource_set_init(null, 0, &resources));
    defer c_resources.snail_resource_set_deinit(resources);
    try testing.expectEqual(c.SNAIL_ERR_INVALID_ARGUMENT, c_resources.snail_resource_set_put_text_atlas(resources.?, 1, atlas));

    const pixels = [_]u8{ 255, 255, 255, 255 };
    var image: ?*c.test_api.ImageImpl = null;
    try testing.expectEqual(c.SNAIL_ERR_INVALID_ARGUMENT, c_image.snail_image_init_srgba8(null, 1, 1, &pixels, pixels.len - 1, &image));
    try testing.expectEqual(@as(?*c.test_api.ImageImpl, null), image);
}

test "c_api: cpu renderer and thread pool" {
    if (!build_options.enable_cpu) {
        try testing.expect(!c_render_backends.snail_cpu_available());
        return;
    }

    try testing.expect(c_render_backends.snail_cpu_available());

    var pixels = [_]u8{0} ** (4 * 4 * 4);
    var renderer: ?*c.test_api.RendererImpl = null;
    try testing.expectEqual(c.SNAIL_ERR_INVALID_ARGUMENT, c_render_backends.snail_cpu_renderer_init(&pixels, 4, 4, 15, &renderer));
    try testing.expectEqual(@as(?*c.test_api.RendererImpl, null), renderer);
    try testing.expectEqual(c.SNAIL_OK, c_render_backends.snail_cpu_renderer_init(&pixels, 4, 4, 16, &renderer));
    defer c_render.snail_renderer_deinit(renderer);
    try testing.expectEqualStrings("CPU", std.mem.span(c_render.snail_renderer_backend_name(renderer.?)));

    var pool: ?*c.test_api.ThreadPoolImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_render_backends.snail_thread_pool_init_with_threads(null, 0, &pool));
    defer c_render_backends.snail_thread_pool_deinit(pool);
    try testing.expectEqual(@as(usize, 0), c_render_backends.snail_thread_pool_thread_count(pool.?));
    try testing.expectEqual(c.SNAIL_OK, c_render_backends.snail_cpu_renderer_set_thread_pool(renderer.?, pool));
    try testing.expectEqual(c.SNAIL_OK, c_render_backends.snail_cpu_renderer_set_thread_pool(renderer.?, null));

    var next_pixels = [_]u8{0} ** (2 * 2 * 4);
    try testing.expectEqual(c.SNAIL_OK, c_render_backends.snail_cpu_renderer_reinit_buffer(renderer.?, &next_pixels, 2, 2, 8));
}

test "c_api: scheduled upload draw list coverage records and retirement" {
    if (!build_options.enable_cpu) return;

    var atlas = try testTextAtlas();
    defer c_text.snail_text_atlas_deinit(atlas);
    try ensureForText(&atlas, "Hi");

    var blob: ?*c.test_api.TextBlobImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_blob_init_text(null, atlas, .{}, "Hi", 2, .{
        .placement = .{ .baseline_x = 0, .baseline_y = 24, .em = 24 },
        .fill = .{ .kind = c.SNAIL_PAINT_SOLID, .paint_solid = .{ 1, 1, 1, 1 } },
    }, &blob));
    defer c_text.snail_text_blob_deinit(blob);

    var scene: ?*c.test_api.SceneImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_scene.snail_scene_init(null, &scene));
    defer c_scene.snail_scene_deinit(scene);
    try testing.expectEqual(c.SNAIL_OK, c_scene.snail_scene_add_text(scene.?, blob.?));

    var resources: ?*c.test_api.ResourceSetImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_resources.snail_resource_set_init(null, 4, &resources));
    defer c_resources.snail_resource_set_deinit(resources);
    try testing.expectEqual(c.SNAIL_OK, c_resources.snail_resource_set_add_scene(resources.?, scene.?));

    var pixels = [_]u8{0} ** (64 * 64 * 4);
    var renderer: ?*c.test_api.RendererImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_render_backends.snail_cpu_renderer_init(&pixels, 64, 64, 64 * 4, &renderer));
    defer c_render.snail_renderer_deinit(renderer);

    var plan: ?*c.test_api.ResourceUploadPlanImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_render.snail_renderer_plan_resource_upload(renderer.?, null, null, resources.?, &plan));
    try testing.expect(c_render.snail_resource_upload_plan_upload_bytes(plan.?) > 0);
    try testing.expect(c_render.snail_resource_upload_plan_changed_key_count(plan.?) > 0);
    var changed_key: c.SnailResourceKey = 0;
    try testing.expect(c_render.snail_resource_upload_plan_changed_key(plan.?, 0, &changed_key));

    var pending: ?*c.test_api.PendingResourceUploadImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_render.snail_renderer_begin_resource_upload(renderer.?, null, plan.?, &pending));
    c_render.snail_resource_upload_plan_deinit(plan);
    plan = null;
    defer c_render.snail_pending_resource_upload_deinit(pending);

    pending.?.inner.plan.atlas_cache_rebuilds = 1;
    try testing.expectEqual(c.SNAIL_ERR_INVALID_ARGUMENT, c_render.snail_pending_resource_upload_record_checked(pending.?, std.math.maxInt(usize), false));
    pending.?.inner.plan.atlas_cache_rebuilds = 0;
    try testing.expectEqual(c.SNAIL_OK, c_render.snail_pending_resource_upload_record_checked(pending.?, std.math.maxInt(usize), false));
    try testing.expect(c_render.snail_pending_resource_upload_ready_now(pending.?));

    var prepared: ?*c.test_api.PreparedResourcesImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_render.snail_pending_resource_upload_publish(pending.?, &prepared));

    var stamp: c.SnailResourceStamp = .{};
    try testing.expect(c_resources.snail_prepared_resources_stamp_for_key(prepared.?, changed_key, &stamp));
    try testing.expect(stamp.identity != 0 or stamp.layout != 0 or stamp.content != 0);

    var coverage: ?*c.test_api.TextCoverageRecordsImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_resources.snail_text_coverage_records_init(null, c_resources.snail_text_coverage_records_word_capacity_for_blob(blob.?), &coverage));
    defer c_resources.snail_text_coverage_records_deinit(coverage);
    try testing.expectEqual(c.SNAIL_OK, c_resources.snail_text_coverage_records_build_local(coverage.?, prepared.?, blob.?, .{}));
    try testing.expect(c_resources.snail_text_coverage_records_valid_for(coverage.?, prepared.?));
    try testing.expect(c_resources.snail_text_coverage_records_word_count(coverage.?) > 0);
    try testing.expectEqual(@as(u32, 0), c_resources.snail_text_coverage_records_layer_window_base(coverage.?));

    var coverage_backend: ?*c.test_api.CoverageBackendImpl = null;
    try testing.expectEqual(c.SNAIL_ERR_INVALID_ARGUMENT, c_resources.snail_coverage_backend_init(renderer.?, prepared.?, &coverage_backend));
    try testing.expectEqual(@as(?*c.test_api.CoverageBackendImpl, null), coverage_backend);

    const state = testDrawState(64, 64);
    const word_capacity = c_resources.snail_draw_list_estimate_word_count(scene.?);
    const segment_capacity = c_resources.snail_draw_list_estimate_segment_count(scene.?);
    try testing.expect(word_capacity > 0);
    try testing.expect(segment_capacity > 0);

    var list: ?*c.test_api.DrawListImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_resources.snail_draw_list_init(null, word_capacity, segment_capacity, &list));
    defer c_resources.snail_draw_list_deinit(list);
    try testing.expectEqual(c.SNAIL_OK, c_resources.snail_draw_list_add_scene(list.?, prepared.?, scene.?));
    try testing.expect(c_resources.snail_draw_list_word_count(list.?) > 0);
    try testing.expect(c_resources.snail_draw_list_segment_count(list.?) > 0);
    try testing.expect(c_resources.snail_draw_list_words(list.?) != null);
    try testing.expectEqual(c.SNAIL_OK, c_render.snail_renderer_draw(renderer.?, prepared.?, list.?, state));

    var queue: ?*c.test_api.PreparedResourceRetirementQueueImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_resources.snail_prepared_resource_retirement_queue_init(null, &queue));
    defer c_resources.snail_prepared_resource_retirement_queue_deinit(queue);
    try testing.expectEqual(c.SNAIL_OK, c_resources.snail_prepared_resource_retirement_queue_retire(queue.?, prepared.?));
    prepared = null;
}

test "c_api: scene and resource set follow public model" {
    var atlas = try testTextAtlas();
    defer c_text.snail_text_atlas_deinit(atlas);
    try ensureForText(&atlas, "Hi");

    var blob: ?*c.test_api.TextBlobImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_text.snail_text_blob_init_text(null, atlas, .{}, "Hi", 2, .{
        .placement = .{ .baseline_x = 0, .baseline_y = 24, .em = 24 },
        .fill = .{ .kind = c.SNAIL_PAINT_SOLID, .paint_solid = .{ 1, 1, 1, 1 } },
    }, &blob));
    defer c_text.snail_text_blob_deinit(blob);

    var scene: ?*c.test_api.SceneImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_scene.snail_scene_init(null, &scene));
    defer c_scene.snail_scene_deinit(scene);
    try testing.expectEqual(c.SNAIL_OK, c_scene.snail_scene_add_text(scene.?, blob.?));
    try testing.expectEqual(c.SNAIL_OK, c_scene.snail_scene_add_text_override(scene.?, blob.?, .{
        .tint = .{ 0.5, 0.75, 1.0, 0.5 },
    }));
    try testing.expectEqual(@as(usize, 2), c_scene.snail_scene_command_count(scene.?));

    var resources: ?*c.test_api.ResourceSetImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_resources.snail_resource_set_init(null, 4, &resources));
    defer c_resources.snail_resource_set_deinit(resources);
    try testing.expectEqual(c.SNAIL_OK, c_resources.snail_resource_set_add_scene(resources.?, scene.?));
    try testing.expectEqual(@as(usize, 1), c_resources.snail_resource_set_count(resources.?));
}

test "c_api: path picture builder" {
    var builder: ?*c.test_api.PathPictureBuilderImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_path.snail_path_picture_builder_init(null, &builder));
    defer c_path.snail_path_picture_builder_deinit(builder);

    const fill = c.SnailFillStyle{ .paint = .{ .kind = c.SNAIL_PAINT_SOLID, .paint_solid = .{ 0.1, 0.2, 0.3, 1 } } };
    const stroke = c.SnailStrokeStyle{ .paint = .{ .kind = c.SNAIL_PAINT_SOLID, .paint_solid = .{ 1, 1, 1, 1 } }, .width = 2, .placement = 1 };
    try testing.expectEqual(c.SNAIL_OK, c_path.snail_path_picture_builder_add_rounded_rect(
        builder.?,
        .{ .x = 0, .y = 0, .w = 100, .h = 40 },
        &fill,
        &stroke,
        8,
        .{},
    ));
    try testing.expectEqual(@as(usize, 1), c_path.snail_path_picture_builder_shape_count(builder.?));
    const second_mark = c_path.snail_path_picture_builder_mark(builder.?);
    try testing.expectEqual(c.SNAIL_OK, c_path.snail_path_picture_builder_add_rect(
        builder.?,
        .{ .x = 120, .y = 0, .w = 20, .h = 20 },
        &fill,
        null,
        .{},
    ));

    var second_range: c.SnailRange = undefined;
    try testing.expectEqual(c.SNAIL_OK, c_path.snail_path_picture_builder_range_from(builder.?, second_mark, &second_range));
    try testing.expectEqual(@as(usize, 1), second_range.start);
    try testing.expectEqual(@as(usize, 1), second_range.count);
    try testing.expectEqual(c.SNAIL_ERR_INVALID_ARGUMENT, c_path.snail_path_picture_builder_range_between(
        builder.?,
        .{ .shape_count = 2 },
        .{ .shape_count = 1 },
        &second_range,
    ));

    var picture: ?*c.test_api.PathPictureImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_path.snail_path_picture_builder_freeze(builder.?, null, null, &picture));
    defer c_path.snail_path_picture_deinit(picture);
    try testing.expectEqual(@as(usize, 2), c_path.snail_path_picture_shape_count(picture.?));
    var picture_footprint: c.SnailResourceFootprint = .{};
    c_path.snail_path_picture_upload_footprint(picture.?, &picture_footprint);
    try testing.expect(c_misc.snail_resource_footprint_allocated_bytes(picture_footprint) > 0);

    var resources: ?*c.test_api.ResourceSetImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_resources.snail_resource_set_init(null, 2, &resources));
    defer c_resources.snail_resource_set_deinit(resources);
    try testing.expectEqual(c.SNAIL_OK, c_resources.snail_resource_set_put_path_picture_options(
        resources.?,
        7,
        picture.?,
        c.SNAIL_RESOURCE_CAPACITY_EXACT,
    ));
    try testing.expectEqual(c.SNAIL_ERR_INVALID_ARGUMENT, c_resources.snail_resource_set_put_path_picture_options(
        resources.?,
        8,
        picture.?,
        99,
    ));
    var set_footprint: c.SnailResourceFootprint = .{};
    try testing.expectEqual(c.SNAIL_OK, c_resources.snail_resource_set_estimate_upload_footprint(resources.?, &set_footprint));
    try testing.expect(c_misc.snail_resource_footprint_allocated_bytes(set_footprint) >= c_misc.snail_resource_footprint_allocated_bytes(picture_footprint));

    var scene: ?*c.test_api.SceneImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_scene.snail_scene_init(null, &scene));
    defer c_scene.snail_scene_deinit(scene);
    try testing.expectEqual(c.SNAIL_OK, c_scene.snail_scene_add_path_picture_range(scene.?, picture.?, second_range));
    try testing.expectEqual(c.SNAIL_OK, c_scene.snail_scene_add_path_picture_range_override(scene.?, picture.?, second_range, .{
        .tint = .{ 1, 0.5, 0.25, 1 },
    }));
    try testing.expectEqual(@as(usize, 2), c_scene.snail_scene_command_count(scene.?));
}

test "c_api: image paint init and constants" {
    var pixels = [_]u8{255} ** (4 * 4 * 4);
    var image: ?*c.test_api.ImageImpl = null;
    try testing.expectEqual(c.SNAIL_OK, c_image.snail_image_init_srgba8(null, 4, 4, &pixels, pixels.len, &image));
    defer c_image.snail_image_deinit(image);
    try testing.expectEqual(@as(u32, 4), c_image.snail_image_width(image.?));
    try testing.expectEqual(@as(u32, 4), c_image.snail_image_height(image.?));
    var footprint: c.SnailResourceFootprint = .{};
    c_image.snail_image_upload_footprint(image.?, &footprint);
    try testing.expectEqual(@as(usize, 4 * 4 * 4), c_misc.snail_resource_footprint_used_bytes(footprint));
    try testing.expect(c_misc.snail_resource_footprint_allocated_bytes(footprint) >= c_misc.snail_resource_footprint_used_bytes(footprint));

    try testing.expectEqual(snail.TEXT_WORDS_PER_GLYPH, c_constants.snail_text_words_per_glyph());
    try testing.expectEqual(snail.TEXT_WORDS_PER_VERTEX, c_constants.snail_text_words_per_vertex());
    try testing.expectEqual(snail.TEXT_VERTICES_PER_GLYPH, c_constants.snail_text_vertices_per_glyph());
    try testing.expectEqual(snail.PATH_WORDS_PER_SHAPE, c_constants.snail_path_words_per_shape());
    try testing.expectEqual(snail.PATH_WORDS_PER_VERTEX, c_constants.snail_path_words_per_vertex());
    try testing.expectEqual(snail.PATH_VERTICES_PER_SHAPE, c_constants.snail_path_vertices_per_shape());
}
