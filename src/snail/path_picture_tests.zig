const std = @import("std");
const snail = @import("root.zig");
const assets = @import("assets");
const bezier = @import("math/bezier.zig");
const curve_tex = @import("render/format/curve_texture.zig");
const paint_records = @import("paint_records.zig");

fn layerInfoOffset(width: u32, x: u16, y: u16) usize {
    return @as(usize, y) * @as(usize, width) + @as(usize, x);
}

fn readTexel(data: []const f32, width: u32, x: u16, y: u16) [4]f32 {
    return paint_records.readTexel(data, width, @intCast(layerInfoOffset(width, x, y)));
}

test "inside-aligned path stroke groups fill and stroke on one instance" {
    var path = snail.Path.init(std.testing.allocator);
    defer path.deinit();
    try path.addRoundedRect(.{ .x = 10, .y = 20, .w = 40, .h = 18 }, 6.0);

    var builder = snail.PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addPath(
        &path,
        .{ .paint = .{ .solid = .{ 0.1, 0.2, 0.3, 0.4 } } },
        .{ .paint = .{ .solid = .{ 0.8, 0.7, 0.6, 1.0 } }, .width = 2.0, .join = .round, .placement = .inside },
        .identity,
    );

    var picture = try builder.freeze(.{ .persistent_allocator = std.testing.allocator, .scratch_allocator = std.testing.allocator });
    defer picture.deinit();

    try std.testing.expectEqual(@as(usize, 1), picture.shapeCount());
    try std.testing.expectEqual(@as(u16, 2), picture.shapes[0].layer_count);
    const fill_info = picture.atlas.getGlyph(picture.shapes[0].glyph_id) orelse return error.TestExpectedEqual;
    const stroke_info = picture.atlas.getGlyph(picture.shapes[0].glyph_id + 1) orelse return error.TestExpectedEqual;
    try std.testing.expect(stroke_info.bbox.min.x < fill_info.bbox.min.x);
    try std.testing.expect(stroke_info.bbox.max.x > fill_info.bbox.max.x);

    const lid = picture.atlas.layer_info_data orelse return error.TestExpectedEqual;
    try std.testing.expectApproxEqAbs(snail.PATH_PAINT_TAG_COMPOSITE_GROUP, lid[3], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), lid[1], 0.001);
}

test "styled path builder emits fill and stroke records" {
    var path = snail.Path.init(std.testing.allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 4, .y = 6, .w = 20, .h = 10 });

    var builder = snail.PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addPath(
        &path,
        .{ .paint = .{ .solid = .{ 0.2, 0.4, 0.8, 1.0 } } },
        .{ .paint = .{ .solid = .{ 0.9, 0.8, 0.2, 1.0 } }, .width = 4.0, .join = .round },
        .identity,
    );

    var picture = try builder.freeze(.{ .persistent_allocator = std.testing.allocator, .scratch_allocator = std.testing.allocator });
    defer picture.deinit();
    try std.testing.expectEqual(@as(usize, 1), picture.shapeCount());
    try std.testing.expectEqual(@as(u16, 2), picture.shapes[0].layer_count);
    const lid = picture.atlas.layer_info_data orelse return error.TestExpectedEqual;
    try std.testing.expectApproxEqAbs(snail.PATH_PAINT_TAG_COMPOSITE_GROUP, lid[3], 0.001);
    try std.testing.expectApproxEqAbs(snail.PATH_PAINT_TAG_SOLID, lid[7], 0.001);
}

test "round caps and primitive arcs keep expected geometry" {
    var stroked = snail.Path.init(std.testing.allocator);
    defer stroked.deinit();
    try stroked.moveTo(.{ .x = 0, .y = 0 });
    try stroked.lineTo(.{ .x = 12, .y = 0 });

    var builder = snail.PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addStrokedPath(&stroked, .{
        .paint = .{ .solid = .{ 1.0, 1.0, 1.0, 1.0 } },
        .width = 6.0,
        .cap = .round,
        .join = .round,
    }, .identity);
    var picture = try builder.freeze(.{ .persistent_allocator = std.testing.allocator, .scratch_allocator = std.testing.allocator });
    defer picture.deinit();
    const stroke_info = picture.atlas.getGlyph(picture.shapes[0].glyph_id) orelse return error.TestExpectedEqual;
    try std.testing.expectApproxEqAbs(@as(f32, -9), stroke_info.bbox.min.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 9), stroke_info.bbox.max.x, 0.05);

    var rounded = snail.Path.init(std.testing.allocator);
    defer rounded.deinit();
    try rounded.addRoundedRect(.{ .x = 0, .y = 0, .w = 200, .h = 200 }, 40);
    try std.testing.expectEqual(@as(usize, 8), rounded.curves.items.len);

    var ellipse = snail.Path.init(std.testing.allocator);
    defer ellipse.deinit();
    try ellipse.addEllipse(.{ .x = 0, .y = 0, .w = 100, .h = 60 });
    try std.testing.expectEqual(@as(usize, 4), ellipse.curves.items.len);
}

test "path picture records roles and builds bounds overlays" {
    var builder = snail.PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addFilledRect(.{ .x = 0, .y = 0, .w = 20, .h = 10 }, .{ .paint = .{ .solid = .{ 1, 1, 1, 1 } } }, .identity);
    try builder.addStrokedRect(
        .{ .x = 30, .y = 0, .w = 20, .h = 10 },
        .{ .paint = .{ .solid = .{ 1, 0, 0, 1 } }, .width = 2.0, .join = .miter },
        .identity,
    );

    var picture = try builder.freeze(.{ .persistent_allocator = std.testing.allocator, .scratch_allocator = std.testing.allocator });
    defer picture.deinit();
    try std.testing.expectEqual(snail.PathPicture.LayerRole.fill, picture.layer_roles[0]);
    try std.testing.expectEqual(snail.PathPicture.LayerRole.stroke, picture.layer_roles[1]);

    var overlay = try picture.buildBoundsOverlay(std.testing.allocator, .{ .stroke_width = 2.0, .origin_size = 4.0 });
    defer overlay.deinit();
    try std.testing.expect(overlay.shapeCount() >= picture.shapeCount());
}

test "path picture freeze stores large coordinates as direct local curves" {
    var absolute_builder = snail.PathPictureBuilder.init(std.testing.allocator);
    defer absolute_builder.deinit();
    try absolute_builder.addRoundedRect(
        .{ .x = 640, .y = 960, .w = 40, .h = 18 },
        .{ .paint = .{ .solid = .{ 1, 1, 1, 1 } } },
        null,
        9.0,
        .identity,
    );
    var absolute_picture = try absolute_builder.freeze(.{ .persistent_allocator = std.testing.allocator, .scratch_allocator = std.testing.allocator });
    defer absolute_picture.deinit();

    const page = absolute_picture.atlas.page(0);
    const decode = struct {
        fn f16ToF32(bits: u16) f32 {
            return @as(f32, @floatCast(@as(f16, @bitCast(bits))));
        }
    }.f16ToF32;
    try std.testing.expectApproxEqAbs(@as(f32, -11.0), decode(page.curve_data[0]), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -9.0), decode(page.curve_data[1]), 0.001);
    try std.testing.expectEqual(
        curve_tex.f32ToF16(curve_tex.DIRECT_ENCODING_KIND_BIAS + @as(f32, @floatFromInt(@intFromEnum(bezier.CurveKind.line)))),
        page.curve_data[10],
    );
}

test "large rounded rectangles use generic curve packing" {
    inline for (.{ true, false }) |inside| {
        var builder = snail.PathPictureBuilder.init(std.testing.allocator);
        defer builder.deinit();
        const stroke = if (inside)
            snail.StrokeStyle{ .paint = .{ .solid = .{ 0, 0, 0, 1 } }, .width = 2.0, .join = .round, .placement = .inside }
        else
            snail.StrokeStyle{ .paint = .{ .solid = .{ 0, 0, 0, 1 } }, .width = 6.0, .join = .round };
        try builder.addRoundedRect(
            .{ .x = 0, .y = 0, .w = 1600, .h = 48 },
            .{ .paint = .{ .solid = .{ 1, 1, 1, 1 } } },
            stroke,
            24.0,
            .identity,
        );

        var picture = try builder.freeze(.{ .persistent_allocator = std.testing.allocator, .scratch_allocator = std.testing.allocator });
        defer picture.deinit();
        try std.testing.expectEqual(@as(usize, 1), picture.shapeCount());
    }
}

test "path picture gradient and image paint records encode metadata" {
    var image = try snail.Image.initSrgba8(std.testing.allocator, 2, 2, &.{
        255, 0,   0,   255,
        0,   255, 0,   255,
        0,   0,   255, 255,
        255, 255, 255, 255,
    });
    defer image.deinit();

    var path = snail.Path.init(std.testing.allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 20, .h = 10 });

    var builder = snail.PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addPath(&path, .{
        .paint = .{ .linear_gradient = .{
            .start = .{ .x = 0, .y = 0 },
            .end = .{ .x = 20, .y = 0 },
            .start_color = .{ 1, 0, 0, 1 },
            .end_color = .{ 0, 0, 1, 1 },
            .extend = .reflect,
        } },
    }, .{
        .paint = .{ .image = .{
            .image = &image,
            .uv_transform = .{ .xx = 0.5, .xy = 0.0, .tx = 0.25, .yx = 0.0, .yy = 1.0, .ty = 0.0 },
            .filter = .nearest,
        } },
        .width = 2,
    }, .identity);

    var picture = try builder.freeze(.{ .persistent_allocator = std.testing.allocator, .scratch_allocator = std.testing.allocator });
    defer picture.deinit();

    const lid = picture.atlas.layer_info_data orelse return error.TestExpectedEqual;
    const base = layerInfoOffset(picture.atlas.layer_info_width, picture.shapes[0].info_x, picture.shapes[0].info_y);
    try std.testing.expectApproxEqAbs(snail.PATH_PAINT_TAG_COMPOSITE_GROUP, lid[base * 4 + 3], 0.001);
    try std.testing.expectApproxEqAbs(snail.PATH_PAINT_TAG_LINEAR_GRADIENT, lid[(base + 1) * 4 + 3], 0.001);
    try std.testing.expectApproxEqAbs(snail.PATH_PAINT_TAG_IMAGE, lid[(base + 1 + snail.PATH_PAINT_TEXELS_PER_RECORD) * 4 + 3], 0.001);

    const records = picture.atlas.paint_image_records orelse return error.TestExpectedEqual;
    try std.testing.expect(records[1] != null);
    try std.testing.expect(records[1].?.image == &image);
    _ = readTexel(lid, picture.atlas.layer_info_width, picture.shapes[0].info_x, picture.shapes[0].info_y);
}

test "Font.lineMetrics forwards parser metrics" {
    var font = try snail.Font.init(assets.noto_sans_regular);
    const metrics = try font.lineMetrics();

    try std.testing.expect(metrics.ascent > 0);
    try std.testing.expect(metrics.descent < 0);
    try std.testing.expect(metrics.line_gap >= 0);
}
