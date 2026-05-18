const std = @import("std");

const bezier = @import("../math/bezier.zig");
const curve_tex = @import("../render/format/curve_texture.zig");
const draw_mod = @import("../draw.zig");
const image_mod = @import("../image.zig");
const path_mod = @import("../path.zig");
const resources_view = @import("../resources/view.zig");
const resource_manifest_mod = @import("../resources/manifest.zig");
const resource_key_mod = @import("../resource_key.zig");
const roots = @import("../math/roots.zig");
const scene_mod = @import("../scene.zig");
const vertex_mod = @import("../render/format/vertex.zig");
const vec = @import("../math/vec.zig");

const DrawList = draw_mod.DrawList;
const DrawState = draw_mod.DrawState;
const Image = image_mod.Image;
const Mat4 = vec.Mat4;
const Path = path_mod.Path;
const PathBatch = path_mod.PathBatch;
const PathPictureBuilder = path_mod.PathPictureBuilder;
const PATH_WORDS_PER_SHAPE = path_mod.PATH_WORDS_PER_SHAPE;
const PreparedAtlasView = resources_view.PreparedAtlasView;
const ResourceManifest = resource_manifest_mod.ResourceManifest;
const ResourceKey = resource_key_mod.ResourceKey;
const Scene = scene_mod.Scene;
const Vec2 = vec.Vec2;
const kPaintTexelsPerRecord = path_mod.PATH_PAINT_TEXELS_PER_RECORD;
const textureLayerLocal = @import("../render/format/texture_layers.zig").local;

test "vector path band count tracks source cubic commands" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();

    try path.moveTo(.{ .x = 0, .y = 0 });
    try path.cubicTo(.{ .x = 8, .y = 20 }, .{ .x = 16, .y = -20 }, .{ .x = 24, .y = 0 });
    try path.close();

    const filled = try path.cloneFilledCurves(std.testing.allocator);
    defer std.testing.allocator.free(filled);

    try std.testing.expectEqual(@as(usize, 2), filled.len);
    try std.testing.expectEqual(bezier.CurveKind.cubic, filled[0].kind);
    try std.testing.expectEqual(bezier.CurveKind.line, filled[1].kind);
    try std.testing.expectEqual(@as(usize, 2), path.filledBandCurveCount());
}

test "path picture band heuristic uses source segment count for cubic fills" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();

    try path.moveTo(.{ .x = 0, .y = 0 });
    try path.cubicTo(.{ .x = 8, .y = 20 }, .{ .x = 16, .y = -20 }, .{ .x = 24, .y = 0 });
    try path.close();

    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addFilledPath(&path, .{ .paint = .{ .solid = .{ 0.8, 0.2, 0.1, 1.0 } } }, .identity);

    var compiled_picture = try builder.freeze(.{ .persistent_allocator = std.testing.allocator, .scratch_allocator = std.testing.allocator });
    defer compiled_picture.deinit();

    const info = compiled_picture.atlas.getGlyph(compiled_picture.shapes[0].glyph_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(u16, 1), info.band_entry.h_band_count);
    try std.testing.expectEqual(@as(u16, 1), info.band_entry.v_band_count);
}

test "path picture layers use direct local curve encoding" {
    var body = Path.init(std.testing.allocator);
    defer body.deinit();
    try body.moveTo(.{ .x = 28.0, .y = 155.0 });
    try body.cubicTo(.{ .x = 62.0, .y = 132.0 }, .{ .x = 106.0, .y = 121.0 }, .{ .x = 142.0, .y = 127.0 });
    try body.cubicTo(.{ .x = 179.0, .y = 133.0 }, .{ .x = 210.0, .y = 151.0 }, .{ .x = 246.0, .y = 151.0 });
    try body.cubicTo(.{ .x = 288.0, .y = 151.0 }, .{ .x = 317.0, .y = 145.0 }, .{ .x = 332.0, .y = 131.0 });
    try body.cubicTo(.{ .x = 346.0, .y = 119.0 }, .{ .x = 345.0, .y = 104.0 }, .{ .x = 327.0, .y = 100.0 });
    try body.cubicTo(.{ .x = 307.0, .y = 96.0 }, .{ .x = 286.0, .y = 105.0 }, .{ .x = 278.0, .y = 119.0 });
    try body.cubicTo(.{ .x = 269.0, .y = 132.0 }, .{ .x = 252.0, .y = 136.0 }, .{ .x = 233.0, .y = 132.0 });
    try body.cubicTo(.{ .x = 210.0, .y = 126.0 }, .{ .x = 189.0, .y = 105.0 }, .{ .x = 166.0, .y = 92.0 });
    try body.cubicTo(.{ .x = 142.0, .y = 79.0 }, .{ .x = 106.0, .y = 84.0 }, .{ .x = 82.0, .y = 106.0 });
    try body.cubicTo(.{ .x = 58.0, .y = 127.0 }, .{ .x = 42.0, .y = 149.0 }, .{ .x = 28.0, .y = 155.0 });
    try body.close();

    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addPath(&body, .{ .paint = .{ .linear_gradient = .{
        .start = .{ .x = 48.0, .y = 102.0 },
        .end = .{ .x = 320.0, .y = 158.0 },
        .start_color = .{ 0.90, 0.87, 0.78, 0.98 },
        .end_color = .{ 0.58, 0.66, 0.57, 0.98 },
    } } }, .{
        .paint = .{ .solid = .{ 0.92, 0.92, 0.86, 0.42 } },
        .width = 2.0,
        .join = .round,
    }, .identity);

    var compiled_picture = try builder.freeze(.{ .persistent_allocator = std.testing.allocator, .scratch_allocator = std.testing.allocator });
    defer compiled_picture.deinit();

    const fill_info = compiled_picture.atlas.getGlyph(compiled_picture.shapes[0].glyph_id) orelse return error.TestExpectedEqual;
    const stroke_info = compiled_picture.atlas.getGlyph(compiled_picture.shapes[0].glyph_id + 1) orelse return error.TestExpectedEqual;
    try std.testing.expect(fill_info.band_entry.h_band_count > 0);
    try std.testing.expect(stroke_info.band_entry.h_band_count > 0);
    try std.testing.expectEqual(
        curve_tex.f32ToF16(curve_tex.DIRECT_ENCODING_KIND_BIAS + @as(f32, @floatFromInt(@intFromEnum(bezier.CurveKind.cubic)))),
        compiled_picture.atlas.page(0).curve_data[10],
    );
}

test "path picture freeze compiles atlas and transformed batch vertices" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();
    try path.moveTo(.{ .x = 0, .y = 0 });
    try path.lineTo(.{ .x = 16, .y = 0 });
    try path.lineTo(.{ .x = 8, .y = 12 });

    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addFilledPath(&path, .{ .paint = .{ .solid = .{ 0.8, 0.2, 0.1, 1.0 } } }, .{
        .xx = 1,
        .xy = 0,
        .tx = 20,
        .yx = 0,
        .yy = 1,
        .ty = 30,
    });

    var compiled_picture = try builder.freeze(.{ .persistent_allocator = std.testing.allocator, .scratch_allocator = std.testing.allocator });
    defer compiled_picture.deinit();
    try std.testing.expectEqual(@as(usize, 1), compiled_picture.shapeCount());
    try std.testing.expectEqual(@as(usize, 1), compiled_picture.atlas.pageCount());
    try std.testing.expectEqual(@as(u32, kPaintTexelsPerRecord), compiled_picture.atlas.layer_info_width);
    try std.testing.expectEqual(@as(u32, 1), compiled_picture.atlas.layer_info_height);
    try std.testing.expectEqual(@as(usize, kPaintTexelsPerRecord * 4), compiled_picture.atlas.layer_info_data.?.len);

    var vertex_buf: [PATH_WORDS_PER_SHAPE]u32 = undefined;
    var path_batch = PathBatch.init(&vertex_buf);
    const view = PreparedAtlasView{ .atlas = &compiled_picture.atlas };
    const result = try path_batch.addDraw(&view, .{ .picture = &compiled_picture, .resource_key = ResourceKey.named("compiled_picture") }, 0, 0);
    try std.testing.expectEqual(@as(usize, 1), result.emitted);
    try std.testing.expect(result.completed);
    try std.testing.expectEqual(@as(usize, PATH_WORDS_PER_SHAPE), path_batch.slice().len);
    // Verify that the min corner world position equals the intended translation.
    const s = vertex_mod.decodeInstance(path_batch.slice());
    const world_x = s.xform[0] * s.rect[0] + s.xform[1] * s.rect[1] + s.origin[0];
    const world_y = s.xform[2] * s.rect[0] + s.xform[3] * s.rect[1] + s.origin[1];
    try std.testing.expectApproxEqAbs(@as(f32, 20), world_x, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 30), world_y, 0.5);
    const packed_gw = s.glyph[1];
    try std.testing.expectEqual(@as(u32, 0xFF), packed_gw >> 24);
    try std.testing.expectEqual(@as(u32, @intFromEnum(vertex_mod.SpecialGlyphKind.path)), (packed_gw >> 16) & 0xFF);
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.band[3], 0.001);
}

test "resource upload footprints are allocation-free and policy-aware" {
    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addFilledRect(.{ .x = 0, .y = 0, .w = 10, .h = 8 }, .{ .paint = .{ .solid = .{ 1, 0, 0, 1 } } }, .identity);

    var compiled_picture = try builder.freeze(.{ .persistent_allocator = std.testing.allocator, .scratch_allocator = std.testing.allocator });
    defer compiled_picture.deinit();

    const picture_fp = compiled_picture.uploadFootprint();
    try std.testing.expectEqual(@as(usize, kPaintTexelsPerRecord * 4 * @sizeOf(f32)), picture_fp.layer_info_bytes_used);
    try std.testing.expectEqual(picture_fp.layer_info_bytes_used, picture_fp.layer_info_bytes_allocated);
    try std.testing.expect(picture_fp.curve_bytes_allocated >= picture_fp.curve_bytes_used);
    try std.testing.expect(picture_fp.band_bytes_allocated >= picture_fp.band_bytes_used);

    var pixels = [_]u8{ 255, 0, 0, 255 };
    var image = try Image.initSrgba8(std.testing.allocator, 1, 1, &pixels);
    defer image.deinit();
    const image_fp = image.uploadFootprint();
    try std.testing.expectEqual(@as(usize, 4), image_fp.image_bytes_used);
    try std.testing.expectEqual(@as(usize, 4), image_fp.image_bytes_allocated);

    var entries: [2]ResourceManifest.Entry = undefined;
    var set = ResourceManifest.init(&entries);
    try set.putPathPicture(.shape, &compiled_picture);
    try set.putImage(.image, &image);
    const set_fp = try set.estimateUploadFootprint();
    try std.testing.expectEqual(picture_fp.layer_info_bytes_used, set_fp.layer_info_bytes_used);
    try std.testing.expectEqual(@as(usize, 4), set_fp.image_bytes_used);
    try std.testing.expectEqual(@as(usize, 4), set_fp.image_bytes_allocated);

    var growable_entries: [1]ResourceManifest.Entry = undefined;
    var growable_set = ResourceManifest.init(&growable_entries);
    try growable_set.putPathPictureOptions(.shape, &compiled_picture, .{ .atlas_capacity = .growable });
    const growable_fp = try growable_set.estimateUploadFootprint();
    try std.testing.expect(growable_fp.curve_bytes_allocated > set_fp.curve_bytes_allocated);
}

test "path picture ranges emit selected shapes" {
    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    const first_mark = builder.mark();
    try builder.addFilledRect(.{ .x = 0, .y = 0, .w = 20, .h = 10 }, .{ .paint = .{ .solid = .{ 0.8, 0.2, 0.1, 1.0 } } }, .identity);
    const second_mark = builder.mark();
    try builder.addFilledRect(.{ .x = 40, .y = 0, .w = 20, .h = 10 }, .{ .paint = .{ .solid = .{ 0.1, 0.4, 0.8, 1.0 } } }, .identity);
    try std.testing.expectEqual(@as(usize, 2), builder.shapeCount());
    const first_range = try builder.rangeBetween(first_mark, second_mark);
    try std.testing.expectEqual(@as(usize, 0), first_range.start);
    try std.testing.expectEqual(@as(usize, 1), first_range.count);
    const second_range = try builder.rangeFrom(second_mark);
    try std.testing.expectEqual(@as(usize, 1), second_range.start);
    try std.testing.expectEqual(@as(usize, 1), second_range.count);
    const full_range = try builder.rangeFrom(first_mark);
    try std.testing.expectEqual(@as(usize, 0), full_range.start);
    try std.testing.expectEqual(@as(usize, 2), full_range.count);
    try std.testing.expectError(error.InvalidShapeMark, builder.rangeFrom(.{ .shape_count = 3 }));
    try std.testing.expectError(error.InvalidShapeRange, builder.rangeBetween(second_mark, first_mark));

    var compiled_picture = try builder.freeze(.{ .persistent_allocator = std.testing.allocator, .scratch_allocator = std.testing.allocator });
    defer compiled_picture.deinit();

    var vertex_buf: [PATH_WORDS_PER_SHAPE]u32 = undefined;
    var path_batch = PathBatch.init(&vertex_buf);
    const view = PreparedAtlasView{ .atlas = &compiled_picture.atlas };
    const result = try path_batch.addDraw(&view, .{
        .picture = &compiled_picture,
        .resource_key = ResourceKey.named("compiled_picture"),
        .shapes = second_range,
    }, 0, 0);
    try std.testing.expectEqual(@as(usize, 1), result.emitted);
    try std.testing.expect(result.completed);
    try std.testing.expectEqual(@as(usize, PATH_WORDS_PER_SHAPE), path_batch.slice().len);

    var scene = Scene.init(std.testing.allocator);
    defer scene.deinit();
    try scene.addPath(.{ .picture = &compiled_picture, .resource_key = ResourceKey.named("compiled_picture"), .shapes = second_range });
    try std.testing.expectEqual(@as(usize, PATH_WORDS_PER_SHAPE), DrawList.estimate(&scene));
    try std.testing.expectEqual(@as(usize, 1), DrawList.estimateSegments(&scene));
}

test "path picture freeze separates persistent and scratch allocators" {
    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addFilledRect(.{ .x = 0, .y = 0, .w = 20, .h = 10 }, .{ .paint = .{ .solid = .{ 0.2, 0.6, 0.9, 1.0 } } }, .identity);

    var scratch_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    var compiled_picture = try builder.freeze(.{
        .persistent_allocator = std.testing.allocator,
        .scratch_allocator = scratch_arena.allocator(),
    });
    _ = scratch_arena.reset(.free_all);
    scratch_arena.deinit();
    defer compiled_picture.deinit();

    try std.testing.expectEqual(@as(usize, 1), compiled_picture.shapeCount());
    try std.testing.expect(compiled_picture.uploadFootprint().allocatedBytes() > 0);

    var vertex_buf: [PATH_WORDS_PER_SHAPE]u32 = undefined;
    var path_batch = PathBatch.init(&vertex_buf);
    const view = PreparedAtlasView{ .atlas = &compiled_picture.atlas };
    const result = try path_batch.addDraw(&view, .{ .picture = &compiled_picture, .resource_key = ResourceKey.named("compiled_picture") }, 0, 0);
    try std.testing.expectEqual(@as(usize, 1), result.emitted);
    try std.testing.expect(result.completed);
}

test "path batch offsets layer info rows through atlas views" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 20, .h = 10 });

    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addFilledPath(&path, .{ .paint = .{ .solid = .{ 0.4, 0.7, 0.9, 1.0 } } }, .identity);

    var compiled_picture = try builder.freeze(.{ .persistent_allocator = std.testing.allocator, .scratch_allocator = std.testing.allocator });
    defer compiled_picture.deinit();

    var vertex_buf: [PATH_WORDS_PER_SHAPE]u32 = undefined;
    var path_batch = PathBatch.init(&vertex_buf);
    const offset_view = PreparedAtlasView{
        .atlas = &compiled_picture.atlas,
        .layer_base = 3,
        .info_row_base = 17,
    };
    {
        const r = try path_batch.addDraw(&offset_view, .{ .picture = &compiled_picture, .resource_key = ResourceKey.named("compiled_picture") }, 0, 0);
        try std.testing.expectEqual(@as(usize, 1), r.emitted);
    }
    const s = vertex_mod.decodeInstance(path_batch.slice());
    const packed_gz = s.glyph[0];
    try std.testing.expectEqual(@as(u32, compiled_picture.shapes[0].info_x), packed_gz & 0xFFFF);
    try std.testing.expectEqual(@as(u32, offset_view.info_row_base + compiled_picture.shapes[0].info_y), packed_gz >> 16);
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(try textureLayerLocal(offset_view.glyphLayer(0)))), s.band[3], 0.001);
}

test "square-capped stroked path extends beyond endpoints" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();
    try path.moveTo(.{ .x = 0, .y = 0 });
    try path.lineTo(.{ .x = 12, .y = 0 });

    const stroke_geom = (try path.cloneStrokedCurves(std.testing.allocator, .{
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
        .width = 6.0,
        .cap = .square,
        .join = .miter,
    })) orelse return error.TestExpectedEqual;
    defer std.testing.allocator.free(stroke_geom.curves);

    try std.testing.expectApproxEqAbs(@as(f32, -3.0), stroke_geom.bbox.min.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 15.0), stroke_geom.bbox.max.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, -3.0), stroke_geom.bbox.min.y, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), stroke_geom.bbox.max.y, 0.05);
}

test "elliptical stroke outline stays curved without degenerate joins" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();
    try path.addEllipse(.{ .x = 0, .y = 0, .w = 100, .h = 60 });

    const stroke_geom = (try path.cloneStrokedCurves(std.testing.allocator, .{
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
        .width = 8.0,
        .join = .round,
    })) orelse return error.TestExpectedEqual;
    defer std.testing.allocator.free(stroke_geom.curves);

    var curved_count: usize = 0;
    for (stroke_geom.curves) |curve| {
        try std.testing.expect(Vec2.length(Vec2.sub(curve.endPoint(), curve.p0)) > 1e-4);
        const chord_mid = Vec2.lerp(curve.p0, curve.endPoint(), 0.5);
        const curve_mid = curve.evaluate(0.5);
        if (Vec2.length(Vec2.sub(curve_mid, chord_mid)) > 1e-3) curved_count += 1;
    }
    try std.testing.expect(curved_count >= 8);
}

test "quadratic stroked eye stalk contains its centerline midpoint" {
    const cases = [_]struct {
        start: Vec2,
        control: Vec2,
        end: Vec2,
    }{
        .{
            .start = .{ .x = 308.0, .y = 100.0 },
            .control = .{ .x = 316.0, .y = 76.0 },
            .end = .{ .x = 334.0, .y = 58.0 },
        },
        .{
            .start = .{ .x = 294.0, .y = 102.0 },
            .control = .{ .x = 298.0, .y = 80.0 },
            .end = .{ .x = 306.0, .y = 64.0 },
        },
    };

    for (cases) |case| {
        var path = Path.init(std.testing.allocator);
        defer path.deinit();
        try path.moveTo(case.start);
        try path.quadTo(case.control, case.end);

        const stroke_geom = (try path.cloneStrokedCurves(std.testing.allocator, .{
            .paint = .{ .solid = .{ 1, 1, 1, 1 } },
            .width = 4.0,
            .cap = .round,
            .join = .round,
        })) orelse return error.TestExpectedEqual;
        defer std.testing.allocator.free(stroke_geom.curves);

        const quads = try std.testing.allocator.alloc(bezier.QuadBezier, stroke_geom.curves.len);
        defer std.testing.allocator.free(quads);
        for (stroke_geom.curves, 0..) |curve, i| quads[i] = curve.asQuad();

        const midpoint = (bezier.QuadBezier{
            .p0 = case.start,
            .p1 = case.control,
            .p2 = case.end,
        }).evaluate(0.5);
        try std.testing.expect(roots.isInside(quads, midpoint));
    }
}
