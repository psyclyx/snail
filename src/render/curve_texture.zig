const std = @import("std");
const bezier_mod = @import("../math/bezier.zig");
const QuadBezier = bezier_mod.QuadBezier;
const BBox = bezier_mod.BBox;
const Vec2 = @import("../math/vec.zig").Vec2;

pub const TEX_WIDTH: u32 = 4096;

/// Convert f32 to IEEE 754 binary16 (half-float).
pub fn f32ToF16(val: f32) u16 {
    const bits: u32 = @bitCast(val);
    const sign: u16 = @intCast((bits >> 16) & 0x8000);
    const exp_val = @as(i32, @intCast((bits >> 23) & 0xFF)) - 127;
    const mantissa = bits & 0x7FFFFF;

    if (exp_val >= 16) {
        // Overflow → infinity
        return sign | 0x7C00;
    } else if (exp_val >= -14) {
        // Normal
        const e: u16 = @intCast(exp_val + 15);
        const m: u16 = @intCast(mantissa >> 13);
        return sign | (e << 10) | m;
    } else if (exp_val >= -24) {
        // Subnormal
        const shift: u5 = @intCast(-exp_val - 14 + 10);
        const m: u16 = @intCast((mantissa | 0x800000) >> shift);
        return sign | m;
    } else {
        return sign; // zero
    }
}

/// Curve texture: RGBA16F (half-float).
/// Each curve occupies 2 texels:
///   texel 0: (p1.x, p1.y, p2.x, p2.y) as FP16
///   texel 1: (p3.x, p3.y, 0, 0) as FP16
/// Half the bandwidth of RGBA32F with sufficient precision for em-space coordinates.
pub const CurveTexture = struct {
    data: []u16,
    width: u32,
    height: u32,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *CurveTexture) void {
        self.allocator.free(self.data);
    }
};

pub const GlyphCurveEntry = struct {
    start_x: u16,
    start_y: u16,
    count: u16,
    offset: u32,
};

pub fn buildCurveTexture(
    allocator: std.mem.Allocator,
    glyphs: []const GlyphCurves,
) !struct { texture: CurveTexture, entries: []GlyphCurveEntry } {
    var total_texels: u32 = 0;
    for (glyphs) |g| total_texels += @as(u32, @intCast(g.curves.len)) * 2;

    const height = @max(1, (total_texels + TEX_WIDTH - 1) / TEX_WIDTH);
    const total = TEX_WIDTH * height;

    var data = try allocator.alloc(u16, total * 4);
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
            data[base + 0] = f32ToF16(curve.p0.x);
            data[base + 1] = f32ToF16(curve.p0.y);
            data[base + 2] = f32ToF16(curve.p1.x);
            data[base + 3] = f32ToF16(curve.p1.y);
            data[base + 4] = f32ToF16(curve.p2.x);
            data[base + 5] = f32ToF16(curve.p2.y);
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

test "f32ToF16 basic conversions" {
    // Zero
    try std.testing.expectEqual(@as(u16, 0), f32ToF16(0.0));
    // One
    try std.testing.expectEqual(@as(u16, 0x3C00), f32ToF16(1.0));
    // Half
    try std.testing.expectEqual(@as(u16, 0x3800), f32ToF16(0.5));
    // Negative
    try std.testing.expectEqual(@as(u16, 0xBC00), f32ToF16(-1.0));
}

test "buildCurveTexture packs FP16" {
    const curves = [_]QuadBezier{
        .{ .p0 = Vec2.new(0, 0), .p1 = Vec2.new(0.5, 1), .p2 = Vec2.new(1, 0) },
    };
    const glyph = GlyphCurves{
        .curves = &curves,
        .bbox = .{ .min = Vec2.new(0, 0), .max = Vec2.new(1, 1) },
    };
    const glyphs = [_]GlyphCurves{glyph};

    var result = try buildCurveTexture(std.testing.allocator, &glyphs);
    defer result.texture.deinit();
    defer std.testing.allocator.free(result.entries);

    try std.testing.expectEqual(@as(u16, 1), result.entries[0].count);
    // p0 = (0,0) → FP16 zero
    try std.testing.expectEqual(@as(u16, 0), result.texture.data[0]);
    try std.testing.expectEqual(@as(u16, 0), result.texture.data[1]);
    // p1 = (0.5, 1.0) → FP16 0x3800, 0x3C00
    try std.testing.expectEqual(@as(u16, 0x3800), result.texture.data[2]);
    try std.testing.expectEqual(@as(u16, 0x3C00), result.texture.data[3]);
}
