const std = @import("std");
const vec = @import("../math/vec.zig");
const Vec2 = vec.Vec2;
const Mat4 = vec.Mat4;
const BBox = @import("../math/bezier.zig").BBox;
const band_tex = @import("band_texture.zig");
const curve_tex = @import("curve_texture.zig");

/// Per-instance data: 5 vec4s = 20 floats per glyph.
///   rect:  (bbox.min.x, bbox.min.y, bbox.max.x, bbox.max.y)
///   xform: (xx, xy, yx, yy) — linear part of 2D transform
///   meta:  (tx, ty, gz, gw) — translation + packed glyph data
///   bnd:   (sx, sy, ox, oy) — band transform
///   col:   (r, g, b, a)     — vertex color
pub const FLOATS_PER_INSTANCE: usize = 20;

/// One instance per glyph quad (instanced rendering).
pub const INSTANCES_PER_GLYPH: usize = 1;

// Legacy aliases used throughout the codebase.
pub const FLOATS_PER_VERTEX = FLOATS_PER_INSTANCE;
pub const VERTICES_PER_GLYPH = INSTANCES_PER_GLYPH;

/// Generate instance data for a glyph quad (non-transformed).
pub fn generateGlyphVertices(
    buf: []f32,
    x: f32,
    y: f32,
    font_size: f32,
    bbox: BBox,
    band_entry: band_tex.GlyphBandEntry,
    color: [4]f32,
    atlas_layer: u8,
) void {
    const gz: u32 = @as(u32, band_entry.glyph_x) | (@as(u32, band_entry.glyph_y) << 16);
    const gw: u32 = @as(u32, band_entry.h_band_count - 1) |
        (@as(u32, band_entry.v_band_count - 1) << 16) |
        (@as(u32, atlas_layer) << 24);

    // rect: bbox in em-space
    buf[0] = bbox.min.x;
    buf[1] = bbox.min.y;
    buf[2] = bbox.max.x;
    buf[3] = bbox.max.y;
    // xform: scale with Y flip (screen Y is down, em Y is up)
    buf[4] = font_size;
    buf[5] = 0;
    buf[6] = 0;
    buf[7] = -font_size;
    // meta: translation + packed glyph data
    buf[8] = x;
    buf[9] = y;
    buf[10] = @bitCast(gz);
    buf[11] = @bitCast(gw);
    // bnd: band transform
    buf[12] = band_entry.band_scale_x;
    buf[13] = band_entry.band_scale_y;
    buf[14] = band_entry.band_offset_x;
    buf[15] = band_entry.band_offset_y;
    // col
    buf[16] = color[0];
    buf[17] = color[1];
    buf[18] = color[2];
    buf[19] = color[3];
}

/// Generate instance data for a glyph quad under a full 2D affine transform.
pub fn generateGlyphVerticesTransformed(
    buf: []f32,
    bbox: BBox,
    band_entry: band_tex.GlyphBandEntry,
    color: [4]f32,
    atlas_layer: u8,
    transform: vec.Transform2D,
) bool {
    const det = transform.xx * transform.yy - transform.xy * transform.yx;
    if (@abs(det) < 1e-10) return false;

    const gz: u32 = @as(u32, band_entry.glyph_x) | (@as(u32, band_entry.glyph_y) << 16);
    const gw: u32 = @as(u32, band_entry.h_band_count - 1) |
        (@as(u32, band_entry.v_band_count - 1) << 16) |
        (@as(u32, atlas_layer) << 24);

    buf[0] = bbox.min.x;
    buf[1] = bbox.min.y;
    buf[2] = bbox.max.x;
    buf[3] = bbox.max.y;
    buf[4] = transform.xx;
    buf[5] = transform.xy;
    buf[6] = transform.yx;
    buf[7] = transform.yy;
    buf[8] = transform.tx;
    buf[9] = transform.ty;
    buf[10] = @bitCast(gz);
    buf[11] = @bitCast(gw);
    buf[12] = band_entry.band_scale_x;
    buf[13] = band_entry.band_scale_y;
    buf[14] = band_entry.band_offset_x;
    buf[15] = band_entry.band_offset_y;
    buf[16] = color[0];
    buf[17] = color[1];
    buf[18] = color[2];
    buf[19] = color[3];
    return true;
}

/// Generate instance data for a multi-layer COLR glyph (single quad, all layers).
pub fn generateMultiLayerGlyphVertices(
    buf: []f32,
    x: f32,
    y: f32,
    font_size: f32,
    union_bbox: BBox,
    info_x: u16,
    info_y: u16,
    layer_count: u16,
    color: [4]f32,
    atlas_layer: u8,
) void {
    const gz: u32 = @as(u32, info_x) | (@as(u32, info_y) << 16);
    const gw: u32 = @as(u32, layer_count) | (0xFF << 24);

    buf[0] = union_bbox.min.x;
    buf[1] = union_bbox.min.y;
    buf[2] = union_bbox.max.x;
    buf[3] = union_bbox.max.y;
    buf[4] = font_size;
    buf[5] = 0;
    buf[6] = 0;
    buf[7] = -font_size;
    buf[8] = x;
    buf[9] = y;
    buf[10] = @bitCast(gz);
    buf[11] = @bitCast(gw);
    // Band transform: zeroed (per-layer banding from layer info texture),
    // w = atlas texture array layer.
    buf[12] = 0;
    buf[13] = 0;
    buf[14] = 0;
    buf[15] = @floatFromInt(atlas_layer);
    buf[16] = color[0];
    buf[17] = color[1];
    buf[18] = color[2];
    buf[19] = color[3];
}

/// Generate instance data for a transformed multi-layer COLR glyph.
pub fn generateMultiLayerGlyphVerticesTransformed(
    buf: []f32,
    bbox: BBox,
    info_x: u16,
    info_y: u16,
    layer_count: u16,
    color: [4]f32,
    atlas_layer: u8,
    transform: vec.Transform2D,
) bool {
    const det = transform.xx * transform.yy - transform.xy * transform.yx;
    if (@abs(det) < 1e-10) return false;

    const gz: u32 = @as(u32, info_x) | (@as(u32, info_y) << 16);
    const gw: u32 = @as(u32, layer_count) | (0xFF << 24);

    buf[0] = bbox.min.x;
    buf[1] = bbox.min.y;
    buf[2] = bbox.max.x;
    buf[3] = bbox.max.y;
    buf[4] = transform.xx;
    buf[5] = transform.xy;
    buf[6] = transform.yx;
    buf[7] = transform.yy;
    buf[8] = transform.tx;
    buf[9] = transform.ty;
    buf[10] = @bitCast(gz);
    buf[11] = @bitCast(gw);
    buf[12] = 0;
    buf[13] = 0;
    buf[14] = 0;
    buf[15] = @floatFromInt(atlas_layer);
    buf[16] = color[0];
    buf[17] = color[1];
    buf[18] = color[2];
    buf[19] = color[3];
    return true;
}

test "instance data produces correct layout" {
    const bezier_mod = @import("../math/bezier.zig");
    var buf: [FLOATS_PER_INSTANCE]f32 = undefined;

    const bbox = bezier_mod.BBox{
        .min = Vec2.new(0.0, -0.2),
        .max = Vec2.new(0.5, 0.8),
    };
    const band_entry = band_tex.GlyphBandEntry{
        .glyph_x = 10,
        .glyph_y = 5,
        .h_band_count = 2,
        .v_band_count = 3,
        .band_scale_x = 4.0,
        .band_scale_y = 2.0,
        .band_offset_x = 0.1,
        .band_offset_y = 0.2,
    };
    const color = [4]f32{ 1.0, 0.5, 0.0, 1.0 };

    generateGlyphVertices(&buf, 100.0, 200.0, 24.0, bbox, band_entry, color, 0);

    // rect
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), buf[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -0.2), buf[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), buf[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), buf[3], 0.001);
    // xform
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), buf[4], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), buf[5], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), buf[6], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -24.0), buf[7], 0.001);
    // meta: tx, ty
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), buf[8], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 200.0), buf[9], 0.001);
    // Color (last 4 floats)
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), buf[16], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), buf[17], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), buf[18], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), buf[19], 0.001);
}

test "multi-layer glyph instance preserves wide layer counts" {
    const bezier_mod = @import("../math/bezier.zig");
    var buf: [FLOATS_PER_INSTANCE]f32 = undefined;

    const bbox = bezier_mod.BBox{
        .min = Vec2.new(0.0, -0.2),
        .max = Vec2.new(0.5, 0.8),
    };
    const color = [4]f32{ 1.0, 1.0, 1.0, 1.0 };

    generateMultiLayerGlyphVertices(&buf, 10.0, 20.0, 24.0, bbox, 12, 34, 300, color, 7);

    const packed_gw: u32 = @bitCast(buf[11]);
    try std.testing.expectEqual(@as(u32, 300), packed_gw & 0xFFFF);
    try std.testing.expectEqual(@as(u32, 0xFF), packed_gw >> 24);
}

test "transformed glyph instance stores affine transform" {
    var buf: [FLOATS_PER_INSTANCE]f32 = undefined;
    const bbox = BBox{
        .min = Vec2.new(1.0, 2.0),
        .max = Vec2.new(5.0, 8.0),
    };
    const band_entry = band_tex.GlyphBandEntry{
        .glyph_x = 7,
        .glyph_y = 3,
        .h_band_count = 2,
        .v_band_count = 2,
        .band_scale_x = 1.0,
        .band_scale_y = 1.0,
        .band_offset_x = 0.0,
        .band_offset_y = 0.0,
    };
    const transform = vec.Transform2D{
        .xx = 2.0,
        .xy = 1.0,
        .tx = 10.0,
        .yx = 0.0,
        .yy = 3.0,
        .ty = -4.0,
    };

    try std.testing.expect(generateGlyphVerticesTransformed(&buf, bbox, band_entry, .{ 1, 0.5, 0.25, 1 }, 0, transform));
    // rect
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), buf[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), buf[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), buf[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 8.0), buf[3], 0.001);
    // xform: xx, xy, yx, yy
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), buf[4], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), buf[5], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), buf[6], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), buf[7], 0.001);
    // meta: tx, ty
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), buf[8], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -4.0), buf[9], 0.001);
}

test "transformed multi-layer glyph instance preserves info pointer and atlas sentinel" {
    var buf: [FLOATS_PER_INSTANCE]f32 = undefined;
    const bbox = BBox{
        .min = Vec2.new(-2.0, 1.0),
        .max = Vec2.new(6.0, 5.0),
    };
    const transform = vec.Transform2D{
        .xx = 1.5,
        .xy = 0.0,
        .tx = 4.0,
        .yx = 0.25,
        .yy = 2.0,
        .ty = -3.0,
    };

    try std.testing.expect(generateMultiLayerGlyphVerticesTransformed(&buf, bbox, 12, 34, 1, .{ 1, 1, 1, 1 }, 9, transform));
    const packed_gz: u32 = @bitCast(buf[10]);
    const packed_gw: u32 = @bitCast(buf[11]);
    try std.testing.expectEqual(@as(u32, 12), packed_gz & 0xFFFF);
    try std.testing.expectEqual(@as(u32, 34), packed_gz >> 16);
    try std.testing.expectEqual(@as(u32, 1), packed_gw & 0xFFFF);
    try std.testing.expectEqual(@as(u32, 0xFF), packed_gw >> 24);
    try std.testing.expectApproxEqAbs(@as(f32, 9), buf[15], 0.001);
}
