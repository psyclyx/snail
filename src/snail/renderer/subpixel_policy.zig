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
    // Transform shape is handled by the fragment derivatives used for coverage.
    _ = mvp;
    if (!allow_subpixel or order == .none) return .grayscale;
    if (supports_dual_source) return .subpixel_dual_source;
    return .grayscale;
}

pub fn chooseTextRenderMode(
    vertices: []const u32,
    mvp: Mat4,
    allow_subpixel: bool,
    order: SubpixelOrder,
    supports_dual_source: bool,
) TextRenderMode {
    if (vertices.len % vertex.WORDS_PER_INSTANCE != 0) return .grayscale;
    return chooseBaseTextRenderMode(mvp, allow_subpixel, order, supports_dual_source);
}

pub fn chooseTextRenderModeRange(
    vertices: []const u32,
    glyph_start: usize,
    glyph_count: usize,
    mvp: Mat4,
    allow_subpixel: bool,
    order: SubpixelOrder,
    supports_dual_source: bool,
) TextRenderMode {
    if (vertices.len % vertex.WORDS_PER_INSTANCE != 0) return .grayscale;
    const total_glyphs = vertices.len / vertex.WORDS_PER_INSTANCE;
    if (glyph_start > total_glyphs or glyph_count > total_glyphs - glyph_start) return .grayscale;
    return chooseBaseTextRenderMode(mvp, allow_subpixel, order, supports_dual_source);
}

pub fn glyphRunIsSpecial(vertices: []const u32, glyph_index: usize) bool {
    std.debug.assert(vertices.len % vertex.WORDS_PER_INSTANCE == 0);
    return (vertex.instanceAt(vertices, glyph_index).glyph[1] >> 24) == 0xFF;
}

pub fn specialRunEnd(vertices: []const u32, glyph_start: usize, special: bool) usize {
    std.debug.assert(vertices.len % vertex.WORDS_PER_INSTANCE == 0);
    const total_glyphs = vertices.len / vertex.WORDS_PER_INSTANCE;
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

test "LCD requires an order and dual-source, not axis-aligned transforms" {
    var buf: [vertex.WORDS_PER_INSTANCE]u32 = undefined;
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

    vertex.generateGlyphVertices(&buf, 10.0, 20.0, 24.0, bbox, band_entry, .{ 1, 1, 1, 1 }, 0);

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
        TextRenderMode.subpixel_dual_source,
        chooseTextRenderMode(&buf, Mat4.rotateZ(std.math.pi / 2.0), true, .rgb, true),
    );
    try std.testing.expectEqual(
        TextRenderMode.subpixel_dual_source,
        chooseBaseTextRenderMode(Mat4.rotateZ(std.math.pi / 2.0), true, .rgb, true),
    );
    try std.testing.expectEqual(
        TextRenderMode.grayscale,
        chooseTextRenderMode(&buf, Mat4.identity, false, .rgb, true),
    );
    try std.testing.expectEqual(
        TextRenderMode.grayscale,
        chooseTextRenderMode(&buf, Mat4.identity, true, .none, true),
    );
}

test "LCD accepts transformed glyph jacobians" {
    var buf: [vertex.WORDS_PER_INSTANCE]u32 = undefined;
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
        .xy = 0.0,
        .tx = 10.0,
        .yx = 0.25,
        .yy = 3.0,
        .ty = -4.0,
    };

    try std.testing.expect(vertex.generateGlyphVerticesTransformed(&buf, bbox, band_entry, .{ 1, 1, 1, 1 }, 0, transform));
    try std.testing.expectEqual(
        TextRenderMode.subpixel_dual_source,
        chooseTextRenderMode(&buf, Mat4.identity, true, .rgb, true),
    );
}

test "LCD accepts italic shear for any physical subpixel axis" {
    var buf: [vertex.WORDS_PER_INSTANCE]u32 = undefined;
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
    const italic = Transform2D{
        .xx = 2.0,
        .xy = 0.3,
        .tx = 10.0,
        .yx = 0.0,
        .yy = 3.0,
        .ty = -4.0,
    };

    try std.testing.expect(vertex.generateGlyphVerticesTransformed(&buf, bbox, band_entry, .{ 1, 1, 1, 1 }, 0, italic));
    try std.testing.expectEqual(
        TextRenderMode.subpixel_dual_source,
        chooseTextRenderMode(&buf, Mat4.identity, true, .rgb, true),
    );
    try std.testing.expectEqual(
        TextRenderMode.subpixel_dual_source,
        chooseTextRenderMode(&buf, Mat4.identity, true, .vrgb, true),
    );
}

test "LCD range mode accepts transformed glyphs" {
    var buf: [vertex.WORDS_PER_INSTANCE * 2]u32 = undefined;
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
        .xy = 0.0,
        .tx = 12.0,
        .yx = 0.2,
        .yy = -1.0,
        .ty = 24.0,
    };

    vertex.generateGlyphVertices(buf[0..vertex.WORDS_PER_INSTANCE], 10.0, 20.0, 24.0, bbox, band_entry, .{ 1, 1, 1, 1 }, 0);
    try std.testing.expect(vertex.generateGlyphVerticesTransformed(buf[vertex.WORDS_PER_INSTANCE..], bbox, band_entry, .{ 1, 1, 1, 1 }, 0, transform));

    try std.testing.expectEqual(
        TextRenderMode.subpixel_dual_source,
        chooseTextRenderModeRange(&buf, 0, 1, Mat4.identity, true, .rgb, true),
    );
    try std.testing.expectEqual(
        TextRenderMode.subpixel_dual_source,
        chooseTextRenderModeRange(&buf, 1, 1, Mat4.identity, true, .rgb, true),
    );
}

test "special text run helpers split sentinel runs" {
    var buf = [_]u32{0} ** (vertex.WORDS_PER_INSTANCE * 3);

    vertex.instanceAtMut(&buf, 1).glyph[1] = 0xFF00_0000;
    vertex.instanceAtMut(&buf, 2).glyph[1] = 0xFF00_0000;

    try std.testing.expect(!glyphRunIsSpecial(&buf, 0));
    try std.testing.expect(glyphRunIsSpecial(&buf, 1));
    try std.testing.expect(glyphRunIsSpecial(&buf, 2));
    try std.testing.expectEqual(@as(usize, 1), specialRunEnd(&buf, 0, false));
    try std.testing.expectEqual(@as(usize, 3), specialRunEnd(&buf, 1, true));
}
