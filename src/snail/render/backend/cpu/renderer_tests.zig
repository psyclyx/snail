const std = @import("std");
const snail = @import("../../../root.zig");
const cpu_color = @import("color.zig");
const cpu_renderer = @import("renderer.zig");
const cpu_texture = @import("texture.zig");
const glyph_atlas = @import("../../../text/glyph_atlas.zig");

const CpuRenderer = cpu_renderer.CpuRenderer;
const Transform2D = snail.Transform2D;
const test_api = cpu_renderer.test_api;

fn expectEqualSlicesWithinU8(expected: []const u8, actual: []const u8, max_diff: u8, max_differences: usize) !void {
    try std.testing.expectEqual(expected.len, actual.len);

    var diff_count: usize = 0;
    for (expected, actual) |lhs, rhs| {
        const diff = if (lhs > rhs) lhs - rhs else rhs - lhs;
        if (diff > max_diff) return error.TestExpectedEqual;
        if (diff != 0) diff_count += 1;
    }

    try std.testing.expect(diff_count <= max_differences);
}

test "cpu_texture.f16ToF32 roundtrip" {
    const testing = std.testing;
    try testing.expectApproxEqAbs(@as(f32, 0.0), cpu_texture.f16ToF32(0), 1e-10);
    try testing.expectApproxEqAbs(@as(f32, 1.0), cpu_texture.f16ToF32(0x3C00), 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 0.5), cpu_texture.f16ToF32(0x3800), 1e-4);
    try testing.expectApproxEqAbs(@as(f32, -1.0), cpu_texture.f16ToF32(0xBC00), 1e-4);
}

test "cpu renderer renders glyphs" {
    const testing = std.testing;
    const assets = @import("assets");
    const font_data = assets.noto_sans_regular;

    var font = try snail.Font.init(font_data);
    defer font.deinit();

    var atlas = try glyph_atlas.initAscii(testing.allocator, &font, &snail.ASCII_PRINTABLE);
    defer atlas.deinit();

    const width: u32 = 200;
    const height: u32 = 40;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    test_api.clear(&renderer, 0, 0, 0, 0);

    const font_size: f32 = 24.0;
    const white = [4]f32{ 1.0, 1.0, 1.0, 1.0 };
    const text = "Hello";

    var cursor_x: f32 = 2.0;
    const baseline_y: f32 = 30.0;

    const em_scale = font_size / @as(f32, @floatFromInt(font.unitsPerEm()));
    for (text) |ch| {
        const gid = try font.glyphIndex(@as(u32, ch));
        test_api.drawGlyphId(&renderer, &atlas, gid, cursor_x, baseline_y, font_size, white);
        const advance = try font.advanceWidth(gid);
        cursor_x += @as(f32, @floatFromInt(advance)) * em_scale;
    }

    var non_zero_count: u32 = 0;
    for (buf) |byte| {
        if (byte != 0) non_zero_count += 1;
    }
    try testing.expect(non_zero_count > 100);
}

test "cpu renderer renders path rect" {
    const testing = std.testing;

    const width: u32 = 48;
    const height: u32 = 32;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    test_api.clear(&renderer, 0, 0, 0, 0);

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addFilledRect(.{ .x = 8, .y = 6, .w = 18, .h = 12 }, .{
        .paint = .{ .solid = .{ 1, 0, 0, 1 } },
    }, .identity);

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    test_api.drawPathPicture(&renderer, &picture);

    const inside = ((12 * stride) + (16 * 4));
    try testing.expect(buf[inside + 0] > 200);
    try testing.expectEqual(@as(u8, 0), buf[inside + 1]);
    try testing.expectEqual(@as(u8, 0), buf[inside + 2]);
    try testing.expect(buf[inside + 3] > 200);

    const outside = ((2 * stride) + (2 * 4));
    try testing.expectEqual(@as(u8, 0), buf[outside + 0]);
    try testing.expectEqual(@as(u8, 0), buf[outside + 3]);
}

test "cpu renderer renders transformed path picture" {
    const testing = std.testing;

    const width: u32 = 64;
    const height: u32 = 40;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    test_api.clear(&renderer, 0, 0, 0, 0);

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addFilledRect(.{ .x = 0, .y = 0, .w = 10, .h = 8 }, .{
        .paint = .{ .solid = .{ 0, 1, 0, 1 } },
    }, .identity);

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    test_api.drawPathPictureTransformed(&renderer, &picture, .{ .tx = 20, .ty = 10 });

    const translated = ((13 * stride) + (24 * 4));
    try testing.expect(buf[translated + 1] > 200);
    try testing.expect(buf[translated + 3] > 200);

    const original = ((3 * stride) + (4 * 4));
    try testing.expectEqual(@as(u8, 0), buf[original + 1]);
    try testing.expectEqual(@as(u8, 0), buf[original + 3]);
}

test "cpu renderer matches absolute and transformed rounded rect pictures" {
    const testing = std.testing;

    const width: u32 = 160;
    const height: u32 = 120;
    const stride = width * 4;
    const absolute_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(absolute_buf);
    const transformed_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(transformed_buf);

    var absolute_renderer = CpuRenderer.init(absolute_buf.ptr, width, height, stride);
    test_api.clear(&absolute_renderer, 0, 0, 0, 0);
    var transformed_renderer = CpuRenderer.init(transformed_buf.ptr, width, height, stride);
    test_api.clear(&transformed_renderer, 0, 0, 0, 0);

    var absolute_builder = snail.PathPictureBuilder.init(testing.allocator);
    defer absolute_builder.deinit();
    try absolute_builder.addRoundedRect(
        .{ .x = 64, .y = 40, .w = 32, .h = 18 },
        .{ .paint = .{ .linear_gradient = .{
            .start = .{ .x = 64, .y = 40 },
            .end = .{ .x = 96, .y = 58 },
            .start_color = .{ 0.2, 0.8, 1.0, 1.0 },
            .end_color = .{ 0.9, 0.7, 0.3, 1.0 },
        } } },
        .{ .paint = .{ .solid = .{ 1, 1, 1, 0.5 } }, .width = 2.0, .join = .round, .placement = .inside },
        9.0,
        .identity,
    );
    var absolute_picture = try absolute_builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer absolute_picture.deinit();

    var transformed_builder = snail.PathPictureBuilder.init(testing.allocator);
    defer transformed_builder.deinit();
    try transformed_builder.addRoundedRect(
        .{ .x = 0, .y = 0, .w = 32, .h = 18 },
        .{ .paint = .{ .linear_gradient = .{
            .start = .{ .x = 0, .y = 0 },
            .end = .{ .x = 32, .y = 18 },
            .start_color = .{ 0.2, 0.8, 1.0, 1.0 },
            .end_color = .{ 0.9, 0.7, 0.3, 1.0 },
        } } },
        .{ .paint = .{ .solid = .{ 1, 1, 1, 0.5 } }, .width = 2.0, .join = .round, .placement = .inside },
        9.0,
        .{ .tx = 64, .ty = 40 },
    );
    var transformed_picture = try transformed_builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer transformed_picture.deinit();

    test_api.drawPathPicture(&absolute_renderer, &absolute_picture);
    test_api.drawPathPicture(&transformed_renderer, &transformed_picture);

    try expectEqualSlicesWithinU8(absolute_buf, transformed_buf, 1, 16);
}

test "cpu renderer keeps rounded rect cap joins opaque" {
    const testing = std.testing;

    const width: u32 = 80;
    const height: u32 = 40;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    test_api.clear(&renderer, 0, 0, 0, 0);

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addRoundedRect(
        .{ .x = 16.5, .y = 12.5, .w = 48.0, .h = 16.0 },
        .{ .paint = .{ .solid = .{ 0.2, 0.7, 0.9, 1.0 } } },
        null,
        8.0,
        .identity,
    );
    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    test_api.drawPathPicture(&renderer, &picture);

    const center_row: usize = 20;
    const seam_col: usize = 24; // sample center x = 24.5, exactly at rect.x + radius
    const inner_col: usize = 25;
    const seam_alpha = buf[center_row * stride + seam_col * 4 + 3];
    const inner_alpha = buf[center_row * stride + inner_col * 4 + 3];

    try testing.expectEqual(@as(u8, 255), inner_alpha);
    try testing.expectEqual(@as(u8, 255), seam_alpha);
}

test "cpu renderer matches huge-span and normalized curved path pictures" {
    const testing = std.testing;

    const width: u32 = 144;
    const height: u32 = 144;
    const stride = width * 4;
    const large_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(large_buf);
    const normalized_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(normalized_buf);

    var large_renderer = CpuRenderer.init(large_buf.ptr, width, height, stride);
    test_api.clear(&large_renderer, 0, 0, 0, 0);
    var normalized_renderer = CpuRenderer.init(normalized_buf.ptr, width, height, stride);
    test_api.clear(&normalized_renderer, 0, 0, 0, 0);

    var large_path = snail.Path.init(testing.allocator);
    defer large_path.deinit();
    try large_path.moveTo(.{ .x = 0, .y = 40 * 64 });
    try large_path.quadTo(.{ .x = 32 * 64, .y = 0 }, .{ .x = 64 * 64, .y = 40 * 64 });
    try large_path.quadTo(.{ .x = 32 * 64, .y = 80 * 64 }, .{ .x = 0, .y = 40 * 64 });
    try large_path.close();

    var large_builder = snail.PathPictureBuilder.init(testing.allocator);
    defer large_builder.deinit();
    try large_builder.addFilledPath(
        &large_path,
        .{ .paint = .{ .solid = .{ 0.95, 0.55, 0.15, 1.0 } } },
        Transform2D.multiply(
            Transform2D.translate(24, 28),
            Transform2D.scale(1.0 / 64.0, 1.0 / 64.0),
        ),
    );
    var large_picture = try large_builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer large_picture.deinit();

    var normalized_path = snail.Path.init(testing.allocator);
    defer normalized_path.deinit();
    try normalized_path.moveTo(.{ .x = 0, .y = 40 });
    try normalized_path.quadTo(.{ .x = 32, .y = 0 }, .{ .x = 64, .y = 40 });
    try normalized_path.quadTo(.{ .x = 32, .y = 80 }, .{ .x = 0, .y = 40 });
    try normalized_path.close();

    var normalized_builder = snail.PathPictureBuilder.init(testing.allocator);
    defer normalized_builder.deinit();
    try normalized_builder.addFilledPath(
        &normalized_path,
        .{ .paint = .{ .solid = .{ 0.95, 0.55, 0.15, 1.0 } } },
        Transform2D.translate(24, 28),
    );
    var normalized_picture = try normalized_builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer normalized_picture.deinit();

    test_api.drawPathPicture(&large_renderer, &large_picture);
    test_api.drawPathPicture(&normalized_renderer, &normalized_picture);

    try testing.expectEqualSlices(u8, large_buf, normalized_buf);
}

test "cpu renderer matches huge-span and normalized rounded rect pictures" {
    const testing = std.testing;

    const width: u32 = 224;
    const height: u32 = 112;
    const stride = width * 4;
    const large_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(large_buf);
    const normalized_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(normalized_buf);

    var large_renderer = CpuRenderer.init(large_buf.ptr, width, height, stride);
    test_api.clear(&large_renderer, 0, 0, 0, 0);
    var normalized_renderer = CpuRenderer.init(normalized_buf.ptr, width, height, stride);
    test_api.clear(&normalized_renderer, 0, 0, 0, 0);

    var large_builder = snail.PathPictureBuilder.init(testing.allocator);
    defer large_builder.deinit();
    try large_builder.addRoundedRect(
        .{ .x = 0, .y = 0, .w = 180 * 64, .h = 40 * 64 },
        .{ .paint = .{ .solid = .{ 0.33, 0.39, 0.36, 0.92 } } },
        .{ .paint = .{ .solid = .{ 0.79, 0.86, 0.78, 1.0 } }, .width = 2.0 * 64.0, .join = .round, .placement = .inside },
        20.0 * 64.0,
        Transform2D.multiply(
            Transform2D.translate(20, 24),
            Transform2D.scale(1.0 / 64.0, 1.0 / 64.0),
        ),
    );
    var large_picture = try large_builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer large_picture.deinit();

    var normalized_builder = snail.PathPictureBuilder.init(testing.allocator);
    defer normalized_builder.deinit();
    try normalized_builder.addRoundedRect(
        .{ .x = 0, .y = 0, .w = 180, .h = 40 },
        .{ .paint = .{ .solid = .{ 0.33, 0.39, 0.36, 0.92 } } },
        .{ .paint = .{ .solid = .{ 0.79, 0.86, 0.78, 1.0 } }, .width = 2.0, .join = .round, .placement = .inside },
        20.0,
        Transform2D.translate(20, 24),
    );
    var normalized_picture = try normalized_builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer normalized_picture.deinit();

    test_api.drawPathPicture(&large_renderer, &large_picture);
    test_api.drawPathPicture(&normalized_renderer, &normalized_picture);

    try expectEqualSlicesWithinU8(large_buf, normalized_buf, 1, 16);
}

test "cpu renderer renders gradient path picture" {
    const testing = std.testing;

    const width: u32 = 48;
    const height: u32 = 24;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    test_api.clear(&renderer, 0, 0, 0, 0);

    var path = snail.Path.init(testing.allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 20, .h = 10 });

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addFilledPath(&path, .{
        .paint = .{ .linear_gradient = .{
            .start = .{ .x = 0, .y = 0 },
            .end = .{ .x = 20, .y = 0 },
            .start_color = .{ 1, 0, 0, 1 },
            .end_color = .{ 0, 0, 1, 1 },
        } },
    }, .{ .tx = 10, .ty = 7 });

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    test_api.drawPathPicture(&renderer, &picture);

    const left = ((11 * stride) + (13 * 4));
    try testing.expect(buf[left + 0] > buf[left + 2]);
    try testing.expect(buf[left + 3] > 200);

    const right = ((11 * stride) + (26 * 4));
    try testing.expect(buf[right + 2] > buf[right + 0]);
    try testing.expect(buf[right + 3] > 200);
}

test "cpu renderer dithers shallow gradient path picture" {
    const testing = std.testing;

    const width: u32 = 512;
    const height: u32 = 24;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    test_api.clear(&renderer, 0, 0, 0, 0);

    var path = snail.Path.init(testing.allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 480, .h = 12 });

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addFilledPath(&path, .{
        .paint = .{ .linear_gradient = .{
            .start = .{ .x = 0, .y = 0 },
            .end = .{ .x = 480, .y = 0 },
            .start_color = .{ 0.28, 0.28, 0.28, 1.0 },
            .end_color = .{ 0.42, 0.42, 0.42, 1.0 },
        } },
    }, .{ .tx = 16, .ty = 6 });

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    test_api.drawPathPicture(&renderer, &picture);

    const row: usize = 12;
    const start_col: usize = 20;
    const end_col: usize = 492;
    var prev = buf[row * stride + start_col * 4];
    var run: usize = 1;
    var max_run: usize = 1;
    var transitions: usize = 0;

    for ((start_col + 1)..end_col) |col| {
        const value = buf[row * stride + col * 4];
        if (value == prev) {
            run += 1;
            continue;
        }
        transitions += 1;
        max_run = @max(max_run, run);
        run = 1;
        prev = value;
    }
    max_run = @max(max_run, run);

    try testing.expect(transitions > 80);
    try testing.expect(max_run < 12);
}

test "cpu renderer renders image-painted path picture" {
    const testing = std.testing;

    const width: u32 = 40;
    const height: u32 = 24;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    test_api.clear(&renderer, 0, 0, 0, 0);

    var image = try snail.Image.initSrgba8(testing.allocator, 2, 1, &.{
        255, 0, 0,   255,
        0,   0, 255, 255,
    });
    defer image.deinit();

    var path = snail.Path.init(testing.allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 20, .h = 10 });

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addFilledPath(&path, .{
        .paint = .{ .image = .{
            .image = &image,
            .uv_transform = .{ .xx = 1.0 / 20.0, .xy = 0.0, .tx = 0.0, .yx = 0.0, .yy = 1.0 / 10.0, .ty = 0.0 },
        } },
    }, .{ .tx = 8, .ty = 6 });

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    test_api.drawPathPicture(&renderer, &picture);

    const left = ((11 * stride) + (13 * 4));
    try testing.expect(buf[left + 0] > buf[left + 2]);
    try testing.expect(buf[left + 3] > 200);

    const right = ((11 * stride) + (22 * 4));
    try testing.expect(buf[right + 2] > buf[right + 0]);
    try testing.expect(buf[right + 3] > 200);

    // Same picture through the prepared / Scene path. Regression: the
    // prepared sampler used to return magenta for tag-4 (image) paints
    // because `paint_image_records` wasn't threaded into the layer-info
    // sampler.
    const prepared_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(prepared_buf);
    var prepared_renderer = CpuRenderer.init(prepared_buf.ptr, width, height, stride);
    test_api.clear(&prepared_renderer, 0, 0, 0, 0);

    var renderer_iface = prepared_renderer.asRenderer();
    var scene = snail.Scene.init(testing.allocator);
    defer scene.deinit();
    try scene.addPath(.{ .picture = &picture });

    var resource_entries: [4]snail.ResourceSet.Entry = undefined;
    var resources = snail.ResourceSet.init(&resource_entries);
    try resources.addScene(&scene);
    var prepared = try renderer_iface.uploadResourcesBlocking(.{ .persistent = testing.allocator, .scratch = testing.allocator }, &resources);
    defer prepared.deinit();

    const wf: f32 = @floatFromInt(width);
    const hf: f32 = @floatFromInt(height);
    const options = snail.DrawOptions{
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
        .target = .{ .pixel_width = wf, .pixel_height = hf, .encoding = .srgb },
    };
    const needed = snail.DrawList.estimate(&scene, options);
    const needed_segments = snail.DrawList.estimateSegments(&scene, options);
    const draw_buf = try testing.allocator.alloc(u32, needed);
    defer testing.allocator.free(draw_buf);
    const draw_segments = try testing.allocator.alloc(snail.DrawSegment, needed_segments);
    defer testing.allocator.free(draw_segments);
    var draw = snail.DrawList.init(draw_buf, draw_segments);
    try draw.addScene(&prepared, &scene, options);
    try renderer_iface.draw(&prepared, draw.slice(), options);

    try testing.expect(prepared_buf[left + 0] > prepared_buf[left + 2]);
    try testing.expect(prepared_buf[left + 3] > 200);
    try testing.expect(prepared_buf[right + 2] > prepared_buf[right + 0]);
    try testing.expect(prepared_buf[right + 3] > 200);
    // And specifically not magenta (the old missing-records placeholder).
    try testing.expect(!(prepared_buf[left + 0] > 200 and prepared_buf[left + 1] < 50 and prepared_buf[left + 2] > 200));
}

test "cpu renderer premultiplies translucent path fill" {
    const testing = std.testing;

    const width: u32 = 40;
    const height: u32 = 28;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    test_api.clear(&renderer, 0, 0, 0, 0);

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addFilledRect(.{ .x = 8, .y = 6, .w = 16, .h = 10 }, .{
        .paint = .{ .solid = .{ 1, 0, 0, 0.5 } },
    }, .identity);

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    test_api.drawPathPicture(&renderer, &picture);

    const inside = ((11 * stride) + (14 * 4));
    try testing.expect(buf[inside + 0] >= 185);
    try testing.expect(buf[inside + 0] <= 189);
    try testing.expectEqual(@as(u8, 0), buf[inside + 1]);
    try testing.expectEqual(@as(u8, 0), buf[inside + 2]);
    try testing.expect(buf[inside + 3] >= 126);
    try testing.expect(buf[inside + 3] <= 128);
}

test "cpu renderer decodes translucent sRGB solid path colors before blending" {
    const testing = std.testing;

    const width: u32 = 40;
    const height: u32 = 28;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    test_api.clear(&renderer, 0, 0, 0, 0);

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addFilledRect(.{ .x = 8, .y = 6, .w = 16, .h = 10 }, .{
        .paint = .{ .solid = .{ 0.5, 0.5, 0.5, 0.5 } },
    }, .identity);

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    test_api.drawPathPicture(&renderer, &picture);

    const inside = ((11 * stride) + (14 * 4));
    try testing.expect(buf[inside + 0] >= 91);
    try testing.expect(buf[inside + 0] <= 93);
    try testing.expectEqual(buf[inside + 0], buf[inside + 1]);
    try testing.expectEqual(buf[inside + 1], buf[inside + 2]);
    try testing.expect(buf[inside + 3] >= 126);
    try testing.expect(buf[inside + 3] <= 128);
}

test "cpu direct sRGB pixels on linear attachment blends in storage space" {
    var buf = [_]u8{ 0, 0, 0, 255 };
    var renderer = CpuRenderer.init(buf[0..].ptr, 1, 1, 4);
    renderer.setTargetEncoding(.srgb_pixels_on_linear_attachment);
    renderer.setResolve(.{ .direct = .{} });

    test_api.blendPremultipliedPixel(&renderer, 0, 0, .{ 0.5, 0.5, 0.5, 0.5 }, false);

    try std.testing.expectEqual(@as(u8, 128), buf[0]);
    try std.testing.expectEqual(@as(u8, 128), buf[1]);
    try std.testing.expectEqual(@as(u8, 128), buf[2]);
    try std.testing.expectEqual(@as(u8, 255), buf[3]);
}

test "cpu linear resolve sRGB pixels on linear attachment blends in linear space" {
    var buf = [_]u8{ 0, 0, 0, 255 };
    var renderer = CpuRenderer.init(buf[0..].ptr, 1, 1, 4);
    renderer.setTargetEncoding(.srgb_pixels_on_linear_attachment);
    renderer.setResolve(.{ .linear = .{} });

    test_api.blendPremultipliedPixel(&renderer, 0, 0, .{ 0.5, 0.5, 0.5, 0.5 }, false);

    const expected = cpu_color.linearToSrgbByte(0.5);
    try std.testing.expectEqual(expected, buf[0]);
    try std.testing.expectEqual(expected, buf[1]);
    try std.testing.expectEqual(expected, buf[2]);
    try std.testing.expectEqual(@as(u8, 255), buf[3]);
}

test "cpu linear resolve clear backdrop seeds only resolve region" {
    const width: u32 = 4;
    const height: u32 = 3;
    const stride: u32 = width * 4;
    const width_usize: usize = @intCast(width);
    const height_usize: usize = @intCast(height);
    const stride_usize: usize = @intCast(stride);
    var buf = [_]u8{9} ** (4 * 3 * 4);
    var renderer = CpuRenderer.init(buf[0..].ptr, width, height, stride);

    const linear = snail.LinearResolve{
        .backdrop = .{ .clear = .{ 1, 0, 0, 1 } },
        .region = .{ .pixel_rect = .{ .x = 1, .y = 1, .w = 2, .h = 1 } },
    };
    const target = snail.ResolveTarget{
        .pixel_width = @floatFromInt(width),
        .pixel_height = @floatFromInt(height),
        .encoding = .srgb_pixels_on_linear_attachment,
        .resolve = .{ .linear = linear },
    };

    const restore = renderer.beginLinearResolve(target, linear);
    renderer.endLinearResolve(restore);

    for (0..height_usize) |row| {
        for (0..width_usize) |col| {
            const off = row * stride_usize + col * 4;
            if (row == 1 and (col == 1 or col == 2)) {
                try std.testing.expectEqual(@as(u8, 255), buf[off + 0]);
                try std.testing.expectEqual(@as(u8, 0), buf[off + 1]);
                try std.testing.expectEqual(@as(u8, 0), buf[off + 2]);
                try std.testing.expectEqual(@as(u8, 255), buf[off + 3]);
            } else {
                try std.testing.expectEqual(@as(u8, 9), buf[off + 0]);
                try std.testing.expectEqual(@as(u8, 9), buf[off + 1]);
                try std.testing.expectEqual(@as(u8, 9), buf[off + 2]);
                try std.testing.expectEqual(@as(u8, 9), buf[off + 3]);
            }
        }
    }
}

test "cpu renderer renders collapsed inside stroke" {
    const testing = std.testing;

    const width: u32 = 32;
    const height: u32 = 32;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    test_api.clear(&renderer, 0, 0, 0, 0);

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addRect(
        .{ .x = 8, .y = 8, .w = 8, .h = 8 },
        null,
        .{ .paint = .{ .solid = .{ 0, 1, 0, 1 } }, .width = 8, .placement = .inside },
        .identity,
    );

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    test_api.drawPathPicture(&renderer, &picture);

    const center = ((12 * stride) + (12 * 4));
    try testing.expect(buf[center + 0] < 8);
    try testing.expect(buf[center + 1] > 200);
    try testing.expect(buf[center + 2] < 8);
    try testing.expect(buf[center + 3] > 200);
}

test "cpu renderer fills both demo eye stalks" {
    const testing = std.testing;

    const width: u32 = 360;
    const height: u32 = 180;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var renderer = CpuRenderer.init(buf.ptr, width, height, stride);
    test_api.clear(&renderer, 0, 0, 0, 0);

    var stalk_a = snail.Path.init(testing.allocator);
    defer stalk_a.deinit();
    try stalk_a.moveTo(.{ .x = 308.0, .y = 100.0 });
    try stalk_a.quadTo(.{ .x = 316.0, .y = 76.0 }, .{ .x = 334.0, .y = 58.0 });

    var stalk_b = snail.Path.init(testing.allocator);
    defer stalk_b.deinit();
    try stalk_b.moveTo(.{ .x = 294.0, .y = 102.0 });
    try stalk_b.quadTo(.{ .x = 298.0, .y = 80.0 }, .{ .x = 306.0, .y = 64.0 });

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addStrokedPath(&stalk_a, .{
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
        .width = 4.0,
        .cap = .round,
        .join = .round,
    }, .identity);
    try builder.addStrokedPath(&stalk_b, .{
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
        .width = 4.0,
        .cap = .round,
        .join = .round,
    }, .identity);

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    test_api.drawPathPicture(&renderer, &picture);

    const samples = [_]snail.Vec2{
        .{ .x = 318.5, .y = 77.5 },
        .{ .x = 299.0, .y = 81.5 },
    };

    for (samples) |sample| {
        const sx: i32 = @intFromFloat(@round(sample.x));
        const sy: i32 = @intFromFloat(@round(sample.y));
        var max_alpha: u8 = 0;
        var dy: i32 = -1;
        while (dy <= 1) : (dy += 1) {
            var dx: i32 = -1;
            while (dx <= 1) : (dx += 1) {
                const x = sx + dx;
                const y = sy + dy;
                if (x < 0 or y < 0 or x >= width or y >= height) continue;
                const off = @as(usize, @intCast(y)) * stride + @as(usize, @intCast(x)) * 4;
                max_alpha = @max(max_alpha, buf[off + 3]);
            }
        }
        try testing.expect(max_alpha > 180);
    }
}

test "cpu renderer threaded draw matches single-threaded byte-for-byte" {
    const testing = std.testing;

    const width: u32 = 96;
    const height: u32 = 96;
    const stride = width * 4;

    var atlas = try snail.TextAtlas.init(testing.allocator, &.{.{ .data = @import("assets").noto_sans_regular }});
    defer atlas.deinit();
    if (try atlas.ensureText(.{}, "Hello, world!")) |next| {
        atlas.deinit();
        atlas = next;
    }

    var blob_builder = snail.TextBlobBuilder.init(testing.allocator, &atlas);
    defer blob_builder.deinit();
    var shaped = try atlas.shapeText(testing.allocator, .{}, "Hello, world!");
    defer shaped.deinit();
    _ = try blob_builder.append(.{
        .shaped = &shaped,
        .placement = .{ .baseline = .{ .x = 4, .y = 32 }, .em = 16 },
        .fill = .{ .solid = .{ 1, 1, 1, 1 } },
    });
    _ = try blob_builder.append(.{
        .shaped = &shaped,
        .placement = .{ .baseline = .{ .x = 4, .y = 56 }, .em = 16 },
        .fill = .{ .solid = .{ 1, 0.4, 0.4, 1 } },
    });
    _ = try blob_builder.append(.{
        .shaped = &shaped,
        .placement = .{ .baseline = .{ .x = 4, .y = 80 }, .em = 16 },
        .fill = .{ .solid = .{ 0.4, 1, 0.4, 1 } },
    });
    var blob = try blob_builder.finish();
    defer blob.deinit();

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addRoundedRect(.{ .x = 4, .y = 4, .w = width - 8, .h = 20 }, .{
        .paint = .{ .solid = .{ 0.2, 0.4, 0.8, 0.9 } },
    }, .{ .paint = .{ .solid = .{ 1, 1, 1, 1 } }, .width = 1.5 }, 4, .identity);
    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    var scene = snail.Scene.init(testing.allocator);
    defer scene.deinit();
    try scene.addPath(.{ .picture = &picture });
    try scene.addText(.{ .blob = &blob });

    const options = snail.DrawOptions{
        .mvp = snail.Mat4.ortho(0, @floatFromInt(width), @floatFromInt(height), 0, -1, 1),
        .target = .{
            .pixel_width = @floatFromInt(width),
            .pixel_height = @floatFromInt(height),
            .subpixel_order = .rgb,
            .encoding = .srgb,
        },
    };

    const serial_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(serial_buf);
    @memset(serial_buf, 0);

    var serial_cpu = CpuRenderer.init(serial_buf.ptr, width, height, stride);
    serial_cpu.setSubpixelOrder(.rgb);
    var serial_resources = try serial_cpu.uploadResourcesBlocking(.{ .persistent = testing.allocator, .scratch = testing.allocator }, blk: {
        var entries: [4]snail.ResourceSet.Entry = undefined;
        var set = snail.ResourceSet.init(&entries);
        try set.addScene(&scene);
        break :blk &set;
    });
    defer serial_resources.deinit();
    var serial_prepared = try snail.PreparedScene.initOwned(testing.allocator, &serial_resources, &scene, options);
    defer serial_prepared.deinit();
    try serial_cpu.drawPrepared(&serial_resources, &serial_prepared, options);

    var pool: snail.ThreadPool = undefined;
    try pool.init(testing.allocator, .{ .threads = 3 });
    defer pool.deinit();

    const threaded_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(threaded_buf);
    @memset(threaded_buf, 0);

    var threaded_cpu = CpuRenderer.init(threaded_buf.ptr, width, height, stride);
    threaded_cpu.setSubpixelOrder(.rgb);
    threaded_cpu.setThreadPool(&pool);
    var threaded_resources = try threaded_cpu.uploadResourcesBlocking(.{ .persistent = testing.allocator, .scratch = testing.allocator }, blk: {
        var entries: [4]snail.ResourceSet.Entry = undefined;
        var set = snail.ResourceSet.init(&entries);
        try set.addScene(&scene);
        break :blk &set;
    });
    defer threaded_resources.deinit();
    var threaded_prepared = try snail.PreparedScene.initOwned(testing.allocator, &threaded_resources, &scene, options);
    defer threaded_prepared.deinit();
    try threaded_cpu.drawPrepared(&threaded_resources, &threaded_prepared, options);

    try testing.expectEqualSlices(u8, serial_buf, threaded_buf);
}

test "cpu renderer drawPaths batch matches drawPathPicture" {
    const testing = std.testing;

    const width: u32 = 48;
    const height: u32 = 32;
    const stride = width * 4;

    // Reference: render via drawPathPicture.
    const ref_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(ref_buf);
    var ref_renderer = CpuRenderer.init(ref_buf.ptr, width, height, stride);
    test_api.clear(&ref_renderer, 0, 0, 0, 0);
    ref_renderer.setSubpixelOrder(.rgb);

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addFilledRect(.{ .x = 8, .y = 6, .w = 18, .h = 12 }, .{
        .paint = .{ .solid = .{ 1, 0, 0, 1 } },
    }, .identity);

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    test_api.drawPathPicture(&ref_renderer, &picture);

    // Comparison: render via drawPaths batch.
    const batch_buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(batch_buf);
    var batch_renderer = CpuRenderer.init(batch_buf.ptr, width, height, stride);
    test_api.clear(&batch_renderer, 0, 0, 0, 0);
    batch_renderer.setSubpixelOrder(.rgb);

    var renderer = batch_renderer.asRenderer();
    var scene = snail.Scene.init(testing.allocator);
    defer scene.deinit();
    try scene.addPath(.{ .picture = &picture });

    var resource_entries: [4]snail.ResourceSet.Entry = undefined;
    var resources = snail.ResourceSet.init(&resource_entries);
    try resources.addScene(&scene);
    var prepared = try renderer.uploadResourcesBlocking(.{ .persistent = testing.allocator, .scratch = testing.allocator }, &resources);
    defer prepared.deinit();

    const wf: f32 = @floatFromInt(width);
    const hf: f32 = @floatFromInt(height);
    const options = snail.DrawOptions{
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
        .target = .{ .pixel_width = wf, .pixel_height = hf, .subpixel_order = .rgb, .encoding = .srgb },
    };
    const needed = snail.DrawList.estimate(&scene, options);
    const needed_segments = snail.DrawList.estimateSegments(&scene, options);
    const draw_buf = try testing.allocator.alloc(u32, needed);
    defer testing.allocator.free(draw_buf);
    const draw_segments = try testing.allocator.alloc(snail.DrawSegment, needed_segments);
    defer testing.allocator.free(draw_segments);
    var draw = snail.DrawList.init(draw_buf, draw_segments);
    try draw.addScene(&prepared, &scene, options);
    try renderer.draw(&prepared, draw.slice(), options);

    const inside = ((12 * stride) + (16 * 4));
    try testing.expect(ref_buf[inside + 0] > 200);
    try testing.expect(batch_buf[inside + 0] > 200);
    try testing.expect(batch_buf[inside + 3] > 200);

    const outside = ((2 * stride) + (2 * 4));
    try testing.expectEqual(@as(u8, 0), batch_buf[outside + 0]);
    try testing.expectEqual(@as(u8, 0), batch_buf[outside + 3]);
}

test "cpu renderer applies path draw tint in prepared batches" {
    const testing = std.testing;

    const width: u32 = 32;
    const height: u32 = 24;
    const stride = width * 4;
    const buf = try testing.allocator.alloc(u8, stride * height);
    defer testing.allocator.free(buf);

    var cpu = CpuRenderer.init(buf.ptr, width, height, stride);
    test_api.clear(&cpu, 0, 0, 0, 0);

    var builder = snail.PathPictureBuilder.init(testing.allocator);
    defer builder.deinit();
    try builder.addFilledRect(.{ .x = 6, .y = 5, .w = 16, .h = 10 }, .{
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
    }, .identity);

    var picture = try builder.freeze(.{ .persistent_allocator = testing.allocator, .scratch_allocator = testing.allocator });
    defer picture.deinit();

    const overrides = [_]snail.Override{.{ .tint = .{ 1, 0, 0, 0.5 } }};
    var scene = snail.Scene.init(testing.allocator);
    defer scene.deinit();
    try scene.addPath(.{ .picture = &picture, .instances = &overrides });

    var renderer = cpu.asRenderer();
    var resource_entries: [4]snail.ResourceSet.Entry = undefined;
    var resources = snail.ResourceSet.init(&resource_entries);
    try resources.addScene(&scene);
    var prepared = try renderer.uploadResourcesBlocking(.{ .persistent = testing.allocator, .scratch = testing.allocator }, &resources);
    defer prepared.deinit();

    const wf: f32 = @floatFromInt(width);
    const hf: f32 = @floatFromInt(height);
    const options = snail.DrawOptions{
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
        .target = .{ .pixel_width = wf, .pixel_height = hf, .subpixel_order = .none, .encoding = .srgb },
    };
    var prepared_scene = try snail.PreparedScene.initOwned(testing.allocator, &prepared, &scene, options);
    defer prepared_scene.deinit();
    try renderer.drawPrepared(&prepared, &prepared_scene, options);

    const inside = ((10 * stride) + (12 * 4));
    try testing.expect(buf[inside + 0] > 180);
    try testing.expect(buf[inside + 1] < 8);
    try testing.expect(buf[inside + 2] < 8);
    try testing.expect(buf[inside + 3] >= 126);
    try testing.expect(buf[inside + 3] <= 128);
}
