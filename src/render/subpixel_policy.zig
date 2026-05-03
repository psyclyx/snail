const std = @import("std");
const band_tex = @import("band_texture.zig");
const BBox = @import("../math/bezier.zig").BBox;
const Vec2 = @import("../math/vec.zig").Vec2;
const vertex = @import("vertex.zig");
const Mat4 = @import("../math/vec.zig").Mat4;
const Transform2D = @import("../math/vec.zig").Transform2D;
const SubpixelOrder = @import("subpixel_order.zig").SubpixelOrder;

pub const TextRenderMode = enum {
    grayscale,
    subpixel_dual_source,
};

pub fn chooseBaseTextRenderMode(
    mvp: Mat4,
    allow_subpixel: bool,
    order: SubpixelOrder,
    supports_dual_source: bool,
) TextRenderMode {
    if (!allow_subpixel or order == .none) return .grayscale;
    if (!mvpPreservesScreenSubpixelAxes(mvp)) return .grayscale;
    if (supports_dual_source) return .subpixel_dual_source;
    return .grayscale;
}

pub fn chooseTextRenderMode(
    vertices: []const f32,
    mvp: Mat4,
    allow_subpixel: bool,
    order: SubpixelOrder,
    supports_dual_source: bool,
) TextRenderMode {
    if (!verticesPreserveScreenSubpixelAxes(vertices)) return .grayscale;
    return chooseBaseTextRenderMode(mvp, allow_subpixel, order, supports_dual_source);
}

pub fn chooseTextRenderModeRange(
    vertices: []const f32,
    glyph_start: usize,
    glyph_count: usize,
    mvp: Mat4,
    allow_subpixel: bool,
    order: SubpixelOrder,
    supports_dual_source: bool,
) TextRenderMode {
    if (!verticesPreserveScreenSubpixelAxesRange(vertices, glyph_start, glyph_count)) return .grayscale;
    return chooseBaseTextRenderMode(mvp, allow_subpixel, order, supports_dual_source);
}

pub fn glyphRunIsSpecial(vertices: []const f32, glyph_index: usize) bool {
    std.debug.assert(vertices.len % vertex.FLOATS_PER_INSTANCE == 0);
    const float_offset = glyph_index * vertex.FLOATS_PER_INSTANCE;
    const gw_bits: u32 = @bitCast(vertices[float_offset + 11]);
    return (gw_bits >> 24) == 0xFF;
}

pub fn specialRunEnd(vertices: []const f32, glyph_start: usize, special: bool) usize {
    std.debug.assert(vertices.len % vertex.FLOATS_PER_INSTANCE == 0);
    const total_glyphs = vertices.len / vertex.FLOATS_PER_INSTANCE;
    std.debug.assert(glyph_start < total_glyphs);

    var run_end = glyph_start + 1;
    while (run_end < total_glyphs and glyphRunIsSpecial(vertices, run_end) == special) : (run_end += 1) {}
    return run_end;
}

pub fn atlasesHaveSpecialTextRuns(atlases: anytype) bool {
    for (atlases) |atlas| {
        if (atlas.colr_base_map != null) return true;
    }
    return false;
}

pub fn mvpPreservesScreenSubpixelAxes(mvp: Mat4) bool {
    const d = mvp.data;
    return approxZero(d[1]) and
        approxZero(d[3]) and
        approxZero(d[4]) and
        approxZero(d[7]) and
        @abs(d[0]) > 1e-6 and
        @abs(d[5]) > 1e-6 and
        @abs(d[15]) > 1e-6;
}

pub fn verticesPreserveScreenSubpixelAxes(vertices: []const f32) bool {
    if (vertices.len == 0) return true;
    if (vertices.len % vertex.FLOATS_PER_INSTANCE != 0) return false;
    return verticesPreserveScreenSubpixelAxesRange(vertices, 0, vertices.len / vertex.FLOATS_PER_INSTANCE);
}

pub fn verticesPreserveScreenSubpixelAxesRange(vertices: []const f32, glyph_start: usize, glyph_count: usize) bool {
    if (vertices.len % vertex.FLOATS_PER_INSTANCE != 0) return false;

    const total_glyphs = vertices.len / vertex.FLOATS_PER_INSTANCE;
    if (glyph_start > total_glyphs or glyph_count > total_glyphs - glyph_start) return false;

    var glyph_index = glyph_start;
    const glyph_end = glyph_start + glyph_count;
    while (glyph_index < glyph_end) : (glyph_index += 1) {
        if (!glyphPreservesScreenSubpixelAxes(vertices, glyph_index)) return false;
    }
    return true;
}

pub fn glyphPreservesScreenSubpixelAxes(vertices: []const f32, glyph_index: usize) bool {
    if (vertices.len % vertex.FLOATS_PER_INSTANCE != 0) return false;

    const base = glyph_index * vertex.FLOATS_PER_INSTANCE;
    if (base + vertex.FLOATS_PER_INSTANCE > vertices.len) return false;

    // xform xy (off-diagonal) at offset 5, yx at offset 6
    const xy = vertices[base + 5];
    const yx = vertices[base + 6];
    return approxZero(xy) and approxZero(yx);
}

fn approxZero(v: f32) bool {
    return @abs(v) <= 1e-5;
}

test "LCD requires dual-source, otherwise grayscale" {
    var buf: [vertex.FLOATS_PER_INSTANCE]f32 = undefined;
    const bbox = BBox{
        .min = Vec2.new(0.0, -0.2),
        .max = Vec2.new(0.5, 0.8),
    };
    const band_entry = band_tex.GlyphBandEntry{
        .glyph_x = 0,
        .glyph_y = 0,
        .h_band_count = 1,
        .v_band_count = 1,
        .band_scale_x = 1.0,
        .band_scale_y = 1.0,
        .band_offset_x = 0.0,
        .band_offset_y = 0.0,
    };

    vertex.generateGlyphVertices(&buf, 10.0, 20.0, 24.0, bbox, band_entry, .{ 1, 1, 1, 1 }, 0, .{});

    try std.testing.expectEqual(
        TextRenderMode.grayscale,
        chooseTextRenderMode(&buf, Mat4.identity, true, .rgb, false),
    );
    try std.testing.expectEqual(
        TextRenderMode.grayscale,
        chooseBaseTextRenderMode(Mat4.identity, true, .rgb, false),
    );
    try std.testing.expectEqual(
        TextRenderMode.subpixel_dual_source,
        chooseTextRenderMode(&buf, Mat4.identity, true, .rgb, true),
    );
    try std.testing.expectEqual(
        TextRenderMode.subpixel_dual_source,
        chooseBaseTextRenderMode(Mat4.identity, true, .rgb, true),
    );
    try std.testing.expectEqual(
        TextRenderMode.grayscale,
        chooseTextRenderMode(&buf, Mat4.rotateZ(std.math.pi / 2.0), true, .rgb, true),
    );
    try std.testing.expectEqual(
        TextRenderMode.grayscale,
        chooseBaseTextRenderMode(Mat4.rotateZ(std.math.pi / 2.0), true, .rgb, true),
    );
}

test "LCD rejects transformed glyph jacobians" {
    var buf: [vertex.FLOATS_PER_INSTANCE]f32 = undefined;
    const bbox = BBox{
        .min = Vec2.new(1.0, 2.0),
        .max = Vec2.new(5.0, 8.0),
    };
    const band_entry = band_tex.GlyphBandEntry{
        .glyph_x = 0,
        .glyph_y = 0,
        .h_band_count = 1,
        .v_band_count = 1,
        .band_scale_x = 1.0,
        .band_scale_y = 1.0,
        .band_offset_x = 0.0,
        .band_offset_y = 0.0,
    };
    const transform = Transform2D{
        .xx = 2.0,
        .xy = 1.0,
        .tx = 10.0,
        .yx = 0.0,
        .yy = 3.0,
        .ty = -4.0,
    };

    try std.testing.expect(vertex.generateGlyphVerticesTransformed(&buf, bbox, band_entry, .{ 1, 1, 1, 1 }, 0, transform, .{}));
    try std.testing.expectEqual(
        TextRenderMode.grayscale,
        chooseTextRenderMode(&buf, Mat4.identity, true, .rgb, true),
    );
}

test "LCD range mode isolates transformed glyphs" {
    var buf: [vertex.FLOATS_PER_INSTANCE * 2]f32 = undefined;
    const bbox = BBox{
        .min = Vec2.new(0.0, -0.2),
        .max = Vec2.new(0.5, 0.8),
    };
    const band_entry = band_tex.GlyphBandEntry{
        .glyph_x = 0,
        .glyph_y = 0,
        .h_band_count = 1,
        .v_band_count = 1,
        .band_scale_x = 1.0,
        .band_scale_y = 1.0,
        .band_offset_x = 0.0,
        .band_offset_y = 0.0,
    };
    const transform = Transform2D{
        .xx = 1.0,
        .xy = 0.2,
        .tx = 12.0,
        .yx = 0.0,
        .yy = -1.0,
        .ty = 24.0,
    };

    vertex.generateGlyphVertices(buf[0..vertex.FLOATS_PER_INSTANCE], 10.0, 20.0, 24.0, bbox, band_entry, .{ 1, 1, 1, 1 }, 0, .{});
    try std.testing.expect(vertex.generateGlyphVerticesTransformed(buf[vertex.FLOATS_PER_INSTANCE..], bbox, band_entry, .{ 1, 1, 1, 1 }, 0, transform, .{}));

    try std.testing.expectEqual(
        TextRenderMode.subpixel_dual_source,
        chooseTextRenderModeRange(&buf, 0, 1, Mat4.identity, true, .rgb, true),
    );
    try std.testing.expectEqual(
        TextRenderMode.grayscale,
        chooseTextRenderModeRange(&buf, 1, 1, Mat4.identity, true, .rgb, true),
    );
}

test "LCD helper isolates transformed glyphs" {
    var buf: [vertex.FLOATS_PER_INSTANCE * 2]f32 = undefined;
    const bbox = BBox{
        .min = Vec2.new(0.0, -0.2),
        .max = Vec2.new(0.5, 0.8),
    };
    const band_entry = band_tex.GlyphBandEntry{
        .glyph_x = 0,
        .glyph_y = 0,
        .h_band_count = 1,
        .v_band_count = 1,
        .band_scale_x = 1.0,
        .band_scale_y = 1.0,
        .band_offset_x = 0.0,
        .band_offset_y = 0.0,
    };
    const transform = Transform2D{
        .xx = 1.0,
        .xy = 0.2,
        .tx = 12.0,
        .yx = 0.0,
        .yy = -1.0,
        .ty = 24.0,
    };

    vertex.generateGlyphVertices(buf[0..vertex.FLOATS_PER_INSTANCE], 10.0, 20.0, 24.0, bbox, band_entry, .{ 1, 1, 1, 1 }, 0, .{});
    try std.testing.expect(vertex.generateGlyphVerticesTransformed(buf[vertex.FLOATS_PER_INSTANCE..], bbox, band_entry, .{ 1, 1, 1, 1 }, 0, transform, .{}));

    try std.testing.expect(glyphPreservesScreenSubpixelAxes(&buf, 0));
    try std.testing.expect(!glyphPreservesScreenSubpixelAxes(&buf, 1));
    try std.testing.expect(verticesPreserveScreenSubpixelAxesRange(&buf, 0, 1));
    try std.testing.expect(!verticesPreserveScreenSubpixelAxesRange(&buf, 1, 1));
    try std.testing.expect(!verticesPreserveScreenSubpixelAxes(&buf));
}

test "special text run helpers split sentinel runs" {
    var buf = [_]f32{0} ** (vertex.FLOATS_PER_INSTANCE * 3);

    buf[vertex.FLOATS_PER_INSTANCE + 11] = @bitCast(@as(u32, 0xFF00_0000));
    buf[vertex.FLOATS_PER_INSTANCE * 2 + 11] = @bitCast(@as(u32, 0xFF00_0000));

    try std.testing.expect(!glyphRunIsSpecial(&buf, 0));
    try std.testing.expect(glyphRunIsSpecial(&buf, 1));
    try std.testing.expect(glyphRunIsSpecial(&buf, 2));
    try std.testing.expectEqual(@as(usize, 1), specialRunEnd(&buf, 0, false));
    try std.testing.expectEqual(@as(usize, 3), specialRunEnd(&buf, 1, true));
}
