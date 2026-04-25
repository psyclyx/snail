const std = @import("std");
const vec = @import("../math/vec.zig");
const Vec2 = vec.Vec2;
const Mat4 = vec.Mat4;
const BBox = @import("../math/bezier.zig").BBox;
const band_tex = @import("band_texture.zig");
const curve_tex = @import("curve_texture.zig");

/// Per-vertex data: 5 vec4s = 20 floats per vertex
pub const FLOATS_PER_VERTEX: usize = 20;

/// Per-glyph quad = 4 unique vertices (indexed drawing, 6 indices)
pub const VERTICES_PER_GLYPH: usize = 4;

/// Generate vertex data for a glyph quad (4 corners).
/// Paired with an index buffer (0,1,2, 0,2,3 per quad) for drawing.
/// Each vertex has 5 vec4 attributes:
///   pos: (x, y, nx, ny)        — object-space position + normal for dilation
///   tex: (em_x, em_y, gz, gw)  — em-space coords + packed glyph data
///   jac: (j00, j01, j10, j11)  — inverse Jacobian
///   bnd: (sx, sy, ox, oy)      — band transform
///   col: (r, g, b, a)          — vertex color
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
    // Object-space glyph quad corners (scaled to font_size, top-left origin)
    const x0 = x + bbox.min.x * font_size;
    const y0 = y - bbox.max.y * font_size;
    const x1 = x + bbox.max.x * font_size;
    const y1 = y - bbox.min.y * font_size;

    // Em-space corners
    const em_x0 = bbox.min.x;
    const em_y0 = bbox.min.y;
    const em_x1 = bbox.max.x;
    const em_y1 = bbox.max.y;

    // Pack glyph location into tex.zw as uint bits in float
    const gz: u32 = @as(u32, band_entry.glyph_x) | (@as(u32, band_entry.glyph_y) << 16);
    // Pack: bits 0-15 = h_band_count-1, bits 16-23 = v_band_count-1, bits 24-31 = atlas layer
    const gw: u32 = @as(u32, band_entry.h_band_count - 1) |
        (@as(u32, band_entry.v_band_count - 1) << 16) |
        (@as(u32, atlas_layer) << 24);

    const gz_f: f32 = @bitCast(gz);
    const gw_f: f32 = @bitCast(gw);

    // Inverse Jacobian: maps object-space displacement to em-space
    // Y is negated because screen Y-down is opposite to em-space Y-up
    const inv_scale = 1.0 / font_size;

    // Write 4 corners (y0 = top = ascender, y1 = bottom = descender)
    // Index buffer provides: 0,1,2, 0,2,3 (two triangles)
    const corners = [4]struct { px: f32, py: f32, nx: f32, ny: f32, ex: f32, ey: f32 }{
        .{ .px = x0, .py = y0, .nx = -1, .ny = -1, .ex = em_x0, .ey = em_y1 },
        .{ .px = x1, .py = y0, .nx = 1, .ny = -1, .ex = em_x1, .ey = em_y1 },
        .{ .px = x1, .py = y1, .nx = 1, .ny = 1, .ex = em_x1, .ey = em_y0 },
        .{ .px = x0, .py = y1, .nx = -1, .ny = 1, .ex = em_x0, .ey = em_y0 },
    };

    inline for (0..4) |vi| {
        const c = corners[vi];
        const base = vi * FLOATS_PER_VERTEX;
        buf[base + 0] = c.px;
        buf[base + 1] = c.py;
        buf[base + 2] = c.nx;
        buf[base + 3] = c.ny;
        buf[base + 4] = c.ex;
        buf[base + 5] = c.ey;
        buf[base + 6] = gz_f;
        buf[base + 7] = gw_f;
        buf[base + 8] = inv_scale;
        buf[base + 9] = 0;
        buf[base + 10] = 0;
        buf[base + 11] = -inv_scale;
        buf[base + 12] = band_entry.band_scale_x;
        buf[base + 13] = band_entry.band_scale_y;
        buf[base + 14] = band_entry.band_offset_x;
        buf[base + 15] = band_entry.band_offset_y;
        buf[base + 16] = color[0];
        buf[base + 17] = color[1];
        buf[base + 18] = color[2];
        buf[base + 19] = color[3];
    }
}

/// Generate vertex data for a glyph/path quad under a full 2D affine transform.
/// The local/em-space coordinates remain the original bbox coordinates; positions
/// and corner normals are transformed into world space, and the inverse linear
/// transform is stored in the Jacobian so fragment-space dilation still maps
/// back into the shape's local curve space.
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
    const inv_det = 1.0 / det;
    const j00 = transform.yy * inv_det;
    const j01 = -transform.xy * inv_det;
    const j10 = -transform.yx * inv_det;
    const j11 = transform.xx * inv_det;

    const gz: u32 = @as(u32, band_entry.glyph_x) | (@as(u32, band_entry.glyph_y) << 16);
    const gw: u32 = @as(u32, band_entry.h_band_count - 1) |
        (@as(u32, band_entry.v_band_count - 1) << 16) |
        (@as(u32, atlas_layer) << 24);
    const gz_f: f32 = @bitCast(gz);
    const gw_f: f32 = @bitCast(gw);

    const corners = [4]struct { px: f32, py: f32, nx: f32, ny: f32, ex: f32, ey: f32 }{
        .{ .px = bbox.min.x, .py = bbox.min.y, .nx = -1, .ny = -1, .ex = bbox.min.x, .ey = bbox.min.y },
        .{ .px = bbox.max.x, .py = bbox.min.y, .nx = 1, .ny = -1, .ex = bbox.max.x, .ey = bbox.min.y },
        .{ .px = bbox.max.x, .py = bbox.max.y, .nx = 1, .ny = 1, .ex = bbox.max.x, .ey = bbox.max.y },
        .{ .px = bbox.min.x, .py = bbox.max.y, .nx = -1, .ny = 1, .ex = bbox.min.x, .ey = bbox.max.y },
    };

    inline for (0..4) |vi| {
        const c = corners[vi];
        const world = transform.applyPoint(.{ .x = c.px, .y = c.py });
        const normal_x = transform.xx * c.nx + transform.xy * c.ny;
        const normal_y = transform.yx * c.nx + transform.yy * c.ny;
        const base = vi * FLOATS_PER_VERTEX;
        buf[base + 0] = world.x;
        buf[base + 1] = world.y;
        buf[base + 2] = normal_x;
        buf[base + 3] = normal_y;
        buf[base + 4] = c.ex;
        buf[base + 5] = c.ey;
        buf[base + 6] = gz_f;
        buf[base + 7] = gw_f;
        buf[base + 8] = j00;
        buf[base + 9] = j01;
        buf[base + 10] = j10;
        buf[base + 11] = j11;
        buf[base + 12] = band_entry.band_scale_x;
        buf[base + 13] = band_entry.band_scale_y;
        buf[base + 14] = band_entry.band_offset_x;
        buf[base + 15] = band_entry.band_offset_y;
        buf[base + 16] = color[0];
        buf[base + 17] = color[1];
        buf[base + 18] = color[2];
        buf[base + 19] = color[3];
    }
    return true;
}

/// Generate vertex data for a transformed glyph whose coverage and paint
/// parameters are fetched from the layer-info texture.
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
    const inv_det = 1.0 / det;
    const j00 = transform.yy * inv_det;
    const j01 = -transform.xy * inv_det;
    const j10 = -transform.yx * inv_det;
    const j11 = transform.xx * inv_det;

    const gz: u32 = @as(u32, info_x) | (@as(u32, info_y) << 16);
    const gw: u32 = @as(u32, layer_count) | (0xFF << 24);
    const gz_f: f32 = @bitCast(gz);
    const gw_f: f32 = @bitCast(gw);

    const corners = [4]struct { px: f32, py: f32, nx: f32, ny: f32, ex: f32, ey: f32 }{
        .{ .px = bbox.min.x, .py = bbox.min.y, .nx = -1, .ny = -1, .ex = bbox.min.x, .ey = bbox.min.y },
        .{ .px = bbox.max.x, .py = bbox.min.y, .nx = 1, .ny = -1, .ex = bbox.max.x, .ey = bbox.min.y },
        .{ .px = bbox.max.x, .py = bbox.max.y, .nx = 1, .ny = 1, .ex = bbox.max.x, .ey = bbox.max.y },
        .{ .px = bbox.min.x, .py = bbox.max.y, .nx = -1, .ny = 1, .ex = bbox.min.x, .ey = bbox.max.y },
    };

    inline for (0..4) |vi| {
        const c = corners[vi];
        const world = transform.applyPoint(.{ .x = c.px, .y = c.py });
        const normal_x = transform.xx * c.nx + transform.xy * c.ny;
        const normal_y = transform.yx * c.nx + transform.yy * c.ny;
        const base = vi * FLOATS_PER_VERTEX;
        buf[base + 0] = world.x;
        buf[base + 1] = world.y;
        buf[base + 2] = normal_x;
        buf[base + 3] = normal_y;
        buf[base + 4] = c.ex;
        buf[base + 5] = c.ey;
        buf[base + 6] = gz_f;
        buf[base + 7] = gw_f;
        buf[base + 8] = j00;
        buf[base + 9] = j01;
        buf[base + 10] = j10;
        buf[base + 11] = j11;
        buf[base + 12] = 0;
        buf[base + 13] = 0;
        buf[base + 14] = 0;
        buf[base + 15] = @floatFromInt(atlas_layer);
        buf[base + 16] = color[0];
        buf[base + 17] = color[1];
        buf[base + 18] = color[2];
        buf[base + 19] = color[3];
    }
    return true;
}

/// Generate vertex data for a multi-layer COLR glyph (single quad, all layers).
/// The fragment shader reads per-layer data from the layer info texture.
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
    const x0 = x + union_bbox.min.x * font_size;
    const y0 = y - union_bbox.max.y * font_size;
    const x1 = x + union_bbox.max.x * font_size;
    const y1 = y - union_bbox.min.y * font_size;

    const em_x0 = union_bbox.min.x;
    const em_y0 = union_bbox.min.y;
    const em_x1 = union_bbox.max.x;
    const em_y1 = union_bbox.max.y;

    // gz: layer info texture pointer (info_x | info_y << 16)
    const gz: u32 = @as(u32, info_x) | (@as(u32, info_y) << 16);
    // gw: layer_count in low 16 bits, 0xFF sentinel in atlas_layer byte (bits 24-31)
    const gw: u32 = @as(u32, layer_count) | (0xFF << 24);

    const gz_f: f32 = @bitCast(gz);
    const gw_f: f32 = @bitCast(gw);
    const inv_scale = 1.0 / font_size;

    const corners = [4]struct { px: f32, py: f32, nx: f32, ny: f32, ex: f32, ey: f32 }{
        .{ .px = x0, .py = y0, .nx = -1, .ny = -1, .ex = em_x0, .ey = em_y1 },
        .{ .px = x1, .py = y0, .nx = 1, .ny = -1, .ex = em_x1, .ey = em_y1 },
        .{ .px = x1, .py = y1, .nx = 1, .ny = 1, .ex = em_x1, .ey = em_y0 },
        .{ .px = x0, .py = y1, .nx = -1, .ny = 1, .ex = em_x0, .ey = em_y0 },
    };

    inline for (0..4) |vi| {
        const c = corners[vi];
        const base = vi * FLOATS_PER_VERTEX;
        buf[base + 0] = c.px;
        buf[base + 1] = c.py;
        buf[base + 2] = c.nx;
        buf[base + 3] = c.ny;
        buf[base + 4] = c.ex;
        buf[base + 5] = c.ey;
        buf[base + 6] = gz_f;
        buf[base + 7] = gw_f;
        buf[base + 8] = inv_scale;
        buf[base + 9] = 0;
        buf[base + 10] = 0;
        buf[base + 11] = -inv_scale;
        // Band transform: xyz zeroed (per-layer banding from layer info texture),
        // w = atlas texture array layer (needed because layer info is built before
        // gl_layer is assigned by uploadAtlases).
        buf[base + 12] = 0;
        buf[base + 13] = 0;
        buf[base + 14] = 0;
        buf[base + 15] = @floatFromInt(atlas_layer);
        // Fallback text color (for layers with palette index 0xFFFF)
        buf[base + 16] = color[0];
        buf[base + 17] = color[1];
        buf[base + 18] = color[2];
        buf[base + 19] = color[3];
    }
}

test "vertex generation produces correct count and layout" {
    const bezier_mod = @import("../math/bezier.zig");
    var buf: [FLOATS_PER_VERTEX * VERTICES_PER_GLYPH]f32 = undefined;

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

    // Check: 4 vertices * 20 floats = 80
    const expected_floats = FLOATS_PER_VERTEX * VERTICES_PER_GLYPH;
    try std.testing.expectEqual(@as(usize, 80), expected_floats);

    // First vertex (corner 0 = top-left): position
    // y0 = 200 - 0.8*24 = 180.8 (top of glyph)
    const v0_x = 100.0 + 0.0 * 24.0;
    const v0_y = 200.0 - 0.8 * 24.0;
    try std.testing.expectApproxEqAbs(v0_x, buf[0], 0.001);
    try std.testing.expectApproxEqAbs(v0_y, buf[1], 0.001);

    // Normal for top-left: (-1, -1)
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), buf[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), buf[3], 0.001);

    // Em-space coords (top = ascender = em_y1)
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), buf[4], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), buf[5], 0.001);

    // Color (last 4 floats of vertex)
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), buf[16], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), buf[17], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), buf[18], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), buf[19], 0.001);

    // Inverse Jacobian (j00=1/fs, j01=0, j10=0, j11=-1/fs)
    try std.testing.expectApproxEqAbs(1.0 / 24.0, buf[8], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), buf[9], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), buf[10], 0.0001);
    try std.testing.expectApproxEqAbs(-1.0 / 24.0, buf[11], 0.0001);
}

test "multi-layer glyph vertices preserve wide layer counts" {
    const bezier_mod = @import("../math/bezier.zig");
    var buf: [FLOATS_PER_VERTEX * VERTICES_PER_GLYPH]f32 = undefined;

    const bbox = bezier_mod.BBox{
        .min = Vec2.new(0.0, -0.2),
        .max = Vec2.new(0.5, 0.8),
    };
    const color = [4]f32{ 1.0, 1.0, 1.0, 1.0 };

    generateMultiLayerGlyphVertices(&buf, 10.0, 20.0, 24.0, bbox, 12, 34, 300, color, 7);

    const packed_bits: u32 = @bitCast(buf[7]);
    try std.testing.expectEqual(@as(u32, 300), packed_bits & 0xFFFF);
    try std.testing.expectEqual(@as(u32, 0xFF), packed_bits >> 24);
}

test "transformed glyph vertices bake affine transform and inverse jacobian" {
    var buf: [FLOATS_PER_VERTEX * VERTICES_PER_GLYPH]f32 = undefined;
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
    try std.testing.expectApproxEqAbs(@as(f32, 14.0), buf[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), buf[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -3.0), buf[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -3.0), buf[3], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), buf[4], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), buf[5], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), buf[8], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0 / 6.0), buf[9], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), buf[10], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0 / 3.0), buf[11], 0.001);
}

test "transformed multi-layer glyph vertices preserve info pointer and atlas sentinel" {
    var buf: [FLOATS_PER_VERTEX * VERTICES_PER_GLYPH]f32 = undefined;
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
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), buf[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -1.5), buf[1], 0.001);
    const packed_gz: u32 = @bitCast(buf[6]);
    const packed_gw: u32 = @bitCast(buf[7]);
    try std.testing.expectEqual(@as(u32, 12), packed_gz & 0xFFFF);
    try std.testing.expectEqual(@as(u32, 34), packed_gz >> 16);
    try std.testing.expectEqual(@as(u32, 1), packed_gw & 0xFFFF);
    try std.testing.expectEqual(@as(u32, 0xFF), packed_gw >> 24);
    try std.testing.expectApproxEqAbs(@as(f32, 9), buf[15], 0.001);
}
