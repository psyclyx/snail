const std = @import("std");
const bezier_mod = @import("../math/bezier.zig");
const vec = @import("../math/vec.zig");
const QuadBezier = bezier_mod.QuadBezier;
const BBox = bezier_mod.BBox;
const Vec2 = vec.Vec2;
const curve_tex = @import("curve_texture.zig");

pub const TEX_WIDTH: u32 = curve_tex.TEX_WIDTH;

/// Result of building band data for a single glyph.
/// Band texture layout for one glyph (all at row glyphLoc.y, starting at column glyphLoc.x):
///
///   [hband0] [hband1] ... [hbandN-1]  [vband0] [vband1] ... [vbandN-1]  [hband_indices...] [vband_indices...]
///
/// Each hband/vband entry: RG16UI = (curve_count, index_offset_from_glyphLoc)
/// Each index entry: RG16UI = (curveLoc.x, curveLoc.y) in the curve texture
pub const GlyphBandData = struct {
    /// All u16 pairs (RG) for this glyph's band texture row
    data: []u16,
    /// Total number of texels used
    texel_count: u32,
    h_band_count: u16,
    v_band_count: u16,
    /// Band transform params for the vertex shader
    band_scale_x: f32,
    band_scale_y: f32,
    band_offset_x: f32,
    band_offset_y: f32,
};

/// Determine optimal band count for a glyph
fn bandCount(num_curves: usize) u16 {
    if (num_curves <= 2) return 1;
    if (num_curves <= 6) return 2;
    if (num_curves <= 12) return 4;
    if (num_curves <= 24) return 6;
    if (num_curves <= 48) return 8;
    return 12;
}

/// Build band data for a single glyph, referencing the curve texture.
pub fn buildGlyphBandData(
    allocator: std.mem.Allocator,
    curves: []const QuadBezier,
    bbox: BBox,
    curve_entry: curve_tex.GlyphCurveEntry,
) !GlyphBandData {
    if (curves.len == 0) {
        return .{
            .data = &.{},
            .texel_count = 0,
            .h_band_count = 0,
            .v_band_count = 0,
            .band_scale_x = 0,
            .band_scale_y = 0,
            .band_offset_x = 0,
            .band_offset_y = 0,
        };
    }

    const h_bands = bandCount(curves.len);
    const v_bands = bandCount(curves.len);
    const epsilon: f32 = 1.0 / 1024.0;
    const bbox_w = bbox.max.x - bbox.min.x;
    const bbox_h = bbox.max.y - bbox.min.y;

    // Assign curves to horizontal bands
    var h_lists: std.ArrayList(std.ArrayList(u16)) = .empty;
    defer {
        for (h_lists.items) |*l| l.deinit(allocator);
        h_lists.deinit(allocator);
    }
    for (0..h_bands) |_| {
        var l: std.ArrayList(u16) = .empty;
        try h_lists.append(allocator, l);
        _ = &l;
    }

    for (curves, 0..) |curve, ci| {
        const cb = curve.boundingBox();
        for (0..h_bands) |bi| {
            const t0 = @as(f32, @floatFromInt(bi)) / @as(f32, @floatFromInt(h_bands));
            const t1 = @as(f32, @floatFromInt(bi + 1)) / @as(f32, @floatFromInt(h_bands));
            const band_min = bbox.min.y + bbox_h * t0 - epsilon;
            const band_max = bbox.min.y + bbox_h * t1 + epsilon;
            if (cb.max.y >= band_min and cb.min.y <= band_max) {
                try h_lists.items[bi].append(allocator, @intCast(ci));
            }
        }
    }

    // Assign curves to vertical bands
    var v_lists: std.ArrayList(std.ArrayList(u16)) = .empty;
    defer {
        for (v_lists.items) |*l| l.deinit(allocator);
        v_lists.deinit(allocator);
    }
    for (0..v_bands) |_| {
        var l: std.ArrayList(u16) = .empty;
        try v_lists.append(allocator, l);
        _ = &l;
    }

    for (curves, 0..) |curve, ci| {
        const cb = curve.boundingBox();
        for (0..v_bands) |bi| {
            const t0 = @as(f32, @floatFromInt(bi)) / @as(f32, @floatFromInt(v_bands));
            const t1 = @as(f32, @floatFromInt(bi + 1)) / @as(f32, @floatFromInt(v_bands));
            const band_min = bbox.min.x + bbox_w * t0 - epsilon;
            const band_max = bbox.min.x + bbox_w * t1 + epsilon;
            if (cb.max.x >= band_min and cb.min.x <= band_max) {
                try v_lists.items[bi].append(allocator, @intCast(ci));
            }
        }
    }

    // Sort curves within bands: horizontal bands by descending max x, vertical by descending max y
    for (h_lists.items) |*band| {
        sortCurveIndicesDescendingX(band.items, curves);
    }
    for (v_lists.items) |*band| {
        sortCurveIndicesDescendingY(band.items, curves);
    }

    // Pack into band texture format
    // Layout: [h_bands headers] [v_bands headers] [h_band_indices...] [v_band_indices...]
    const header_count: u32 = @as(u32, h_bands) + @as(u32, v_bands);
    var total_indices: u32 = 0;
    for (h_lists.items) |band| total_indices += @intCast(band.items.len);
    for (v_lists.items) |band| total_indices += @intCast(band.items.len);

    const total_texels = header_count + total_indices;
    var data = try allocator.alloc(u16, total_texels * 2);
    @memset(data, 0);

    // Write horizontal band headers
    var index_offset: u32 = header_count;
    for (0..h_bands) |bi| {
        const band = h_lists.items[bi];
        data[bi * 2 + 0] = @intCast(band.items.len); // curve count
        data[bi * 2 + 1] = @intCast(index_offset); // offset from glyph loc
        index_offset += @intCast(band.items.len);
    }

    // Write vertical band headers
    for (0..v_bands) |bi| {
        const off = (@as(usize, h_bands) + bi) * 2;
        const band = v_lists.items[bi];
        data[off + 0] = @intCast(band.items.len);
        data[off + 1] = @intCast(index_offset);
        index_offset += @intCast(band.items.len);
    }

    // Write horizontal band index entries (curveLoc in curve texture)
    var write_pos: u32 = header_count;
    for (h_lists.items) |band| {
        for (band.items) |curve_idx| {
            // Each curve occupies 2 texels in curve texture starting at curve_entry.start
            const curve_texel = @as(u32, curve_entry.offset) + @as(u32, curve_idx) * 2;
            const cx = curve_texel % TEX_WIDTH;
            const cy = curve_texel / TEX_WIDTH;
            data[write_pos * 2 + 0] = @intCast(cx);
            data[write_pos * 2 + 1] = @intCast(cy);
            write_pos += 1;
        }
    }

    // Write vertical band index entries
    for (v_lists.items) |band| {
        for (band.items) |curve_idx| {
            const curve_texel = @as(u32, curve_entry.offset) + @as(u32, curve_idx) * 2;
            const cx = curve_texel % TEX_WIDTH;
            const cy = curve_texel / TEX_WIDTH;
            data[write_pos * 2 + 0] = @intCast(cx);
            data[write_pos * 2 + 1] = @intCast(cy);
            write_pos += 1;
        }
    }

    // Band transform: maps em-space coords to band indices
    const band_scale_x = @as(f32, @floatFromInt(v_bands)) / @max(bbox_w, 1e-10);
    const band_scale_y = @as(f32, @floatFromInt(h_bands)) / @max(bbox_h, 1e-10);
    const band_offset_x = -bbox.min.x * band_scale_x;
    const band_offset_y = -bbox.min.y * band_scale_y;

    return .{
        .data = data,
        .texel_count = total_texels,
        .h_band_count = h_bands,
        .v_band_count = v_bands,
        .band_scale_x = band_scale_x,
        .band_scale_y = band_scale_y,
        .band_offset_x = band_offset_x,
        .band_offset_y = band_offset_y,
    };
}

fn sortCurveIndicesDescendingX(indices: []u16, curves: []const QuadBezier) void {
    const Context = struct {
        curves: []const QuadBezier,
        pub fn lessThan(ctx: @This(), a: u16, b: u16) bool {
            const ca = ctx.curves[a].boundingBox();
            const cb = ctx.curves[b].boundingBox();
            return ca.max.x > cb.max.x;
        }
    };
    std.mem.sort(u16, indices, Context{ .curves = curves }, Context.lessThan);
}

fn sortCurveIndicesDescendingY(indices: []u16, curves: []const QuadBezier) void {
    const Context = struct {
        curves: []const QuadBezier,
        pub fn lessThan(ctx: @This(), a: u16, b: u16) bool {
            const ca = ctx.curves[a].boundingBox();
            const cb = ctx.curves[b].boundingBox();
            return ca.max.y > cb.max.y;
        }
    };
    std.mem.sort(u16, indices, Context{ .curves = curves }, Context.lessThan);
}

/// Pack all glyph band data into a single band texture
pub const BandTexture = struct {
    data: []u16,
    width: u32,
    height: u32,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *BandTexture) void {
        self.allocator.free(self.data);
    }
};

pub const GlyphBandEntry = struct {
    glyph_x: u16,
    glyph_y: u16,
    h_band_count: u16,
    v_band_count: u16,
    band_scale_x: f32,
    band_scale_y: f32,
    band_offset_x: f32,
    band_offset_y: f32,
};

pub fn buildBandTexture(
    allocator: std.mem.Allocator,
    glyph_band_data: []const GlyphBandData,
) !struct { texture: BandTexture, entries: []GlyphBandEntry } {
    var total_texels: u32 = 0;
    for (glyph_band_data) |g| total_texels += g.texel_count;

    const height = @max(1, (total_texels + TEX_WIDTH - 1) / TEX_WIDTH);
    const padded = TEX_WIDTH * height;

    var data = try allocator.alloc(u16, padded * 2);
    @memset(data, 0);

    var entries = try allocator.alloc(GlyphBandEntry, glyph_band_data.len);
    var texel_offset: u32 = 0;

    for (glyph_band_data, 0..) |g, gi| {
        const gx = texel_offset % TEX_WIDTH;
        const gy = texel_offset / TEX_WIDTH;
        entries[gi] = .{
            .glyph_x = @intCast(gx),
            .glyph_y = @intCast(gy),
            .h_band_count = g.h_band_count,
            .v_band_count = g.v_band_count,
            .band_scale_x = g.band_scale_x,
            .band_scale_y = g.band_scale_y,
            .band_offset_x = g.band_offset_x,
            .band_offset_y = g.band_offset_y,
        };

        // Copy glyph's band data into the texture
        const src = g.data;
        for (0..g.texel_count) |ti| {
            const dst_texel = texel_offset + @as(u32, @intCast(ti));
            const dst_idx = dst_texel * 2;
            data[dst_idx + 0] = src[ti * 2 + 0];
            data[dst_idx + 1] = src[ti * 2 + 1];
        }
        texel_offset += g.texel_count;
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

pub fn freeGlyphBandData(allocator: std.mem.Allocator, band_data: *GlyphBandData) void {
    if (band_data.data.len > 0) allocator.free(band_data.data);
}

test "bandCount heuristic" {
    try std.testing.expectEqual(@as(u16, 1), bandCount(1));
    try std.testing.expectEqual(@as(u16, 1), bandCount(2));
    try std.testing.expectEqual(@as(u16, 4), bandCount(8));
    try std.testing.expectEqual(@as(u16, 8), bandCount(32));
}

test "buildGlyphBandData basic" {
    const curves = [_]QuadBezier{
        .{ .p0 = Vec2.new(0, 0), .p1 = Vec2.new(0.5, 0.5), .p2 = Vec2.new(1, 0) },
        .{ .p0 = Vec2.new(1, 0), .p1 = Vec2.new(0.5, -0.5), .p2 = Vec2.new(0, 0) },
    };
    const bbox = BBox{ .min = Vec2.new(0, -0.5), .max = Vec2.new(1, 0.5) };
    const entry = curve_tex.GlyphCurveEntry{ .start_x = 0, .start_y = 0, .count = 2, .offset = 0 };

    var bd = try buildGlyphBandData(std.testing.allocator, &curves, bbox, entry);
    defer freeGlyphBandData(std.testing.allocator, &bd);

    try std.testing.expect(bd.h_band_count > 0);
    try std.testing.expect(bd.v_band_count > 0);
    try std.testing.expect(bd.texel_count > 0);
}
