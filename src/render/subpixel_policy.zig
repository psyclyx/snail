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

pub fn chooseTextRenderMode(
    vertices: []const f32,
    mvp: Mat4,
    allow_subpixel: bool,
    order: SubpixelOrder,
    supports_dual_source: bool,
) TextRenderMode {
    if (!allow_subpixel or order == .none) return .grayscale;
    if (!mvpPreservesScreenSubpixelAxes(mvp)) return .grayscale;
    if (!verticesPreserveScreenSubpixelAxes(vertices)) return .grayscale;
    if (supports_dual_source) return .subpixel_dual_source;
    return .grayscale;
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
    const floats_per_glyph = vertex.FLOATS_PER_VERTEX * vertex.VERTICES_PER_GLYPH;
    if (vertices.len == 0) return true;
    if (vertices.len % floats_per_glyph != 0) return false;

    var glyph_index: usize = 0;
    const glyph_count = vertices.len / floats_per_glyph;
    while (glyph_index < glyph_count) : (glyph_index += 1) {
        const base = glyph_index * floats_per_glyph;
        const j01 = vertices[base + 9];
        const j10 = vertices[base + 10];
        if (!approxZero(j01) or !approxZero(j10)) return false;
    }
    return true;
}

fn approxZero(v: f32) bool {
    return @abs(v) <= 1e-5;
}

test "LCD requires dual-source, otherwise grayscale" {
    var buf: [vertex.FLOATS_PER_VERTEX * vertex.VERTICES_PER_GLYPH]f32 = undefined;
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
        TextRenderMode.subpixel_dual_source,
        chooseTextRenderMode(&buf, Mat4.identity, true, .rgb, true),
    );
    try std.testing.expectEqual(
        TextRenderMode.grayscale,
        chooseTextRenderMode(&buf, Mat4.rotateZ(std.math.pi / 2.0), true, .rgb, true),
    );
}

test "LCD rejects transformed glyph jacobians" {
    var buf: [vertex.FLOATS_PER_VERTEX * vertex.VERTICES_PER_GLYPH]f32 = undefined;
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

    try std.testing.expect(vertex.generateGlyphVerticesTransformed(&buf, bbox, band_entry, .{ 1, 1, 1, 1 }, 0, transform));
    try std.testing.expectEqual(
        TextRenderMode.grayscale,
        chooseTextRenderMode(&buf, Mat4.identity, true, .rgb, true),
    );
}
