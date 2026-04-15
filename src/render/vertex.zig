const std = @import("std");
const vec = @import("../math/vec.zig");
const Vec2 = vec.Vec2;
const Mat4 = vec.Mat4;
const BBox = @import("../math/bezier.zig").BBox;
const band_tex = @import("band_texture.zig");
const curve_tex = @import("curve_texture.zig");

/// Per-vertex data: 5 vec4s = 20 floats per vertex
pub const FLOATS_PER_VERTEX: usize = 20;

/// Per-glyph quad = 6 vertices (2 triangles)
pub const VERTICES_PER_GLYPH: usize = 6;

/// Generate vertex data for a glyph quad.
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
    // Object-space glyph quad corners (scaled to font_size)
    const x0 = x + bbox.min.x * font_size;
    const y0 = y + bbox.min.y * font_size;
    const x1 = x + bbox.max.x * font_size;
    const y1 = y + bbox.max.y * font_size;

    // Em-space corners
    const em_x0 = bbox.min.x;
    const em_y0 = bbox.min.y;
    const em_x1 = bbox.max.x;
    const em_y1 = bbox.max.y;

    // Pack glyph location into tex.z as uint bits in a float
    const gz: u32 = @as(u32, band_entry.glyph_x) | (@as(u32, band_entry.glyph_y) << 16);
    // Pack: bits 0-15 = h_band_count-1, bits 16-23 = v_band_count-1, bits 24-31 = atlas layer
    const gw: u32 = @as(u32, band_entry.h_band_count - 1) |
        (@as(u32, band_entry.v_band_count - 1) << 16) |
        (@as(u32, atlas_layer) << 24);

    const gz_f: f32 = @bitCast(gz);
    const gw_f: f32 = @bitCast(gw);

    // Inverse Jacobian: maps object-space displacement to em-space
    // For axis-aligned rendering: j = (1/font_size, 0, 0, 1/font_size)
    const inv_scale = 1.0 / font_size;
    const j00 = inv_scale;
    const j01: f32 = 0;
    const j10: f32 = 0;
    const j11 = inv_scale;

    // Band transform
    const bnd = [4]f32{
        band_entry.band_scale_x,
        band_entry.band_scale_y,
        band_entry.band_offset_x,
        band_entry.band_offset_y,
    };

    // Corner normals (pointing outward from quad center for dilation)
    const corners = [4]struct { x: f32, y: f32, nx: f32, ny: f32, em_x: f32, em_y: f32 }{
        .{ .x = x0, .y = y0, .nx = -1, .ny = -1, .em_x = em_x0, .em_y = em_y0 }, // bottom-left
        .{ .x = x1, .y = y0, .nx = 1, .ny = -1, .em_x = em_x1, .em_y = em_y0 }, // bottom-right
        .{ .x = x1, .y = y1, .nx = 1, .ny = 1, .em_x = em_x1, .em_y = em_y1 }, // top-right
        .{ .x = x0, .y = y1, .nx = -1, .ny = 1, .em_x = em_x0, .em_y = em_y1 }, // top-left
    };

    // Two triangles: 0-1-2, 0-2-3
    const indices = [6]u8{ 0, 1, 2, 0, 2, 3 };

    for (indices, 0..) |ci, vi| {
        const c = corners[ci];
        const base = vi * FLOATS_PER_VERTEX;
        // pos
        buf[base + 0] = c.x;
        buf[base + 1] = c.y;
        buf[base + 2] = c.nx;
        buf[base + 3] = c.ny;
        // tex
        buf[base + 4] = c.em_x;
        buf[base + 5] = c.em_y;
        buf[base + 6] = gz_f;
        buf[base + 7] = gw_f;
        // jac
        buf[base + 8] = j00;
        buf[base + 9] = j01;
        buf[base + 10] = j10;
        buf[base + 11] = j11;
        // bnd
        buf[base + 12] = bnd[0];
        buf[base + 13] = bnd[1];
        buf[base + 14] = bnd[2];
        buf[base + 15] = bnd[3];
        // col
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

    // Check vertex count: 6 vertices * 20 floats
    const expected_floats = FLOATS_PER_VERTEX * VERTICES_PER_GLYPH;
    try std.testing.expectEqual(@as(usize, 120), expected_floats);

    // First vertex (corner 0 = bottom-left): position
    const v0_x = 100.0 + 0.0 * 24.0; // x + bbox.min.x * font_size
    const v0_y = 200.0 + (-0.2) * 24.0;
    try std.testing.expectApproxEqAbs(v0_x, buf[0], 0.001);
    try std.testing.expectApproxEqAbs(v0_y, buf[1], 0.001);

    // Normal for bottom-left: (-1, -1)
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), buf[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), buf[3], 0.001);

    // Em-space coords
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), buf[4], 0.001); // bbox.min.x
    try std.testing.expectApproxEqAbs(@as(f32, -0.2), buf[5], 0.001); // bbox.min.y

    // Color (last 4 floats of vertex)
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), buf[16], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), buf[17], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), buf[18], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), buf[19], 0.001);

    // Inverse Jacobian (1/font_size diagonal)
    try std.testing.expectApproxEqAbs(1.0 / 24.0, buf[8], 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), buf[9], 0.0001);
}
