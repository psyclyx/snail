const std = @import("std");
const bezier_mod = @import("../math/bezier.zig");
const QuadBezier = bezier_mod.QuadBezier;
const BBox = bezier_mod.BBox;
const Vec2 = @import("../math/vec.zig").Vec2;

/// Fixed texture width matching the shader's kLogBandTextureWidth = 12
pub const TEX_WIDTH: u32 = 4096;

/// Curve texture: RGBA32F.
/// Each curve occupies 2 texels:
///   texel 0: (p1.x, p1.y, p2.x, p2.y)
///   texel 1: (p3.x, p3.y, -, -)
pub const CurveTexture = struct {
    data: []f32,
    width: u32,
    height: u32,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *CurveTexture) void {
        self.allocator.free(self.data);
    }
};

/// Location of a glyph's curves within the curve texture
pub const GlyphCurveEntry = struct {
    /// Starting texel coordinate (x,y) in the curve texture
    start_x: u16,
    start_y: u16,
    /// Number of curves
    count: u16,
    /// Linear texel offset (for band texture references)
    offset: u32,
};

/// Build curve texture from all glyph outlines.
/// Curves are stored in order, each as 2 consecutive texels.
pub fn buildCurveTexture(
    allocator: std.mem.Allocator,
    glyphs: []const GlyphCurves,
) !struct { texture: CurveTexture, entries: []GlyphCurveEntry } {
    // Count total texels needed: 2 per curve
    var total_texels: u32 = 0;
    for (glyphs) |g| total_texels += @as(u32, @intCast(g.curves.len)) * 2;

    const height = @max(1, (total_texels + TEX_WIDTH - 1) / TEX_WIDTH);
    const total = TEX_WIDTH * height;

    var data = try allocator.alloc(f32, total * 4);
    @memset(data, 0);

    var entries = try allocator.alloc(GlyphCurveEntry, glyphs.len);
    var texel_idx: u32 = 0;

    for (glyphs, 0..) |g, gi| {
        const tx = texel_idx % TEX_WIDTH;
        const ty = texel_idx / TEX_WIDTH;
        entries[gi] = .{
            .start_x = @intCast(tx),
            .start_y = @intCast(ty),
            .count = @intCast(g.curves.len),
            .offset = texel_idx,
        };

        for (g.curves) |curve| {
            const base = texel_idx * 4;
            // Texel 0: p1.x, p1.y, p2.x, p2.y
            data[base + 0] = curve.p0.x;
            data[base + 1] = curve.p0.y;
            data[base + 2] = curve.p1.x;
            data[base + 3] = curve.p1.y;
            // Texel 1: p3.x, p3.y, 0, 0
            data[base + 4] = curve.p2.x;
            data[base + 5] = curve.p2.y;
            data[base + 6] = 0;
            data[base + 7] = 0;
            texel_idx += 2;
        }
    }

    return .{
        .texture = .{
            .data = data,
            .width = TEX_WIDTH,
            .height = height,
            .allocator = allocator,
        },
        .entries = entries,
    };
}

pub const GlyphCurves = struct {
    curves: []const QuadBezier,
    bbox: BBox,
};

test "buildCurveTexture packs correctly" {
    const curves = [_]QuadBezier{
        .{ .p0 = Vec2.new(0, 0), .p1 = Vec2.new(0.5, 1), .p2 = Vec2.new(1, 0) },
        .{ .p0 = Vec2.new(1, 0), .p1 = Vec2.new(1.5, 1), .p2 = Vec2.new(2, 0) },
    };
    const glyph = GlyphCurves{
        .curves = &curves,
        .bbox = .{ .min = Vec2.new(0, 0), .max = Vec2.new(2, 1) },
    };
    const glyphs = [_]GlyphCurves{glyph};

    var result = try buildCurveTexture(std.testing.allocator, &glyphs);
    defer result.texture.deinit();
    defer std.testing.allocator.free(result.entries);

    try std.testing.expectEqual(@as(u16, 0), result.entries[0].start_x);
    try std.testing.expectEqual(@as(u16, 2), result.entries[0].count);

    // First curve, texel 0: p0
    try std.testing.expectApproxEqAbs(result.texture.data[0], 0.0, 1e-6);
    try std.testing.expectApproxEqAbs(result.texture.data[1], 0.0, 1e-6);
    // First curve, texel 0: p1
    try std.testing.expectApproxEqAbs(result.texture.data[2], 0.5, 1e-6);
    try std.testing.expectApproxEqAbs(result.texture.data[3], 1.0, 1e-6);
}
