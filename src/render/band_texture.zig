const std = @import("std");
const bezier_mod = @import("../math/bezier.zig");
const vec = @import("../math/vec.zig");
const CurveSegment = bezier_mod.CurveSegment;
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
    curves: []const CurveSegment,
    bbox: BBox,
    curve_entry: curve_tex.GlyphCurveEntry,
    origin: Vec2,
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
    const delta = Vec2.new(-origin.x, -origin.y);
    const max_band_count = 12;
    std.debug.assert(h_bands <= max_band_count and v_bands <= max_band_count);

    var curve_bboxes = try allocator.alloc(BBox, curves.len);
    defer allocator.free(curve_bboxes);

    var h_band_min: [max_band_count]f32 = undefined;
    var h_band_max: [max_band_count]f32 = undefined;
    var v_band_min: [max_band_count]f32 = undefined;
    var v_band_max: [max_band_count]f32 = undefined;
    var h_lists: [max_band_count]std.ArrayList(u16) = undefined;
    var v_lists: [max_band_count]std.ArrayList(u16) = undefined;
    var h_inited: usize = 0;
    var v_inited: usize = 0;
    errdefer {
        while (h_inited > 0) {
            h_inited -= 1;
            h_lists[h_inited].deinit(allocator);
        }
        while (v_inited > 0) {
            v_inited -= 1;
            v_lists[v_inited].deinit(allocator);
        }
    }

    for (0..h_bands) |bi| {
        const t0 = @as(f32, @floatFromInt(bi)) / @as(f32, @floatFromInt(h_bands));
        const t1 = @as(f32, @floatFromInt(bi + 1)) / @as(f32, @floatFromInt(h_bands));
        h_band_min[bi] = bbox.min.y + bbox_h * t0 - epsilon;
        h_band_max[bi] = bbox.min.y + bbox_h * t1 + epsilon;
        h_lists[bi] = try std.ArrayList(u16).initCapacity(allocator, curves.len);
        h_inited += 1;
    }
    for (0..v_bands) |bi| {
        const t0 = @as(f32, @floatFromInt(bi)) / @as(f32, @floatFromInt(v_bands));
        const t1 = @as(f32, @floatFromInt(bi + 1)) / @as(f32, @floatFromInt(v_bands));
        v_band_min[bi] = bbox.min.x + bbox_w * t0 - epsilon;
        v_band_max[bi] = bbox.min.x + bbox_w * t1 + epsilon;
        v_lists[bi] = try std.ArrayList(u16).initCapacity(allocator, curves.len);
        v_inited += 1;
    }

    var band_lists_ready = false;
    defer {
        if (band_lists_ready) {
            for (h_lists[0..@as(usize, h_bands)]) |*band| band.deinit(allocator);
            for (v_lists[0..@as(usize, v_bands)]) |*band| band.deinit(allocator);
        } else {
            while (h_inited > 0) {
                h_inited -= 1;
                h_lists[h_inited].deinit(allocator);
            }
            while (v_inited > 0) {
                v_inited -= 1;
                v_lists[v_inited].deinit(allocator);
            }
        }
    }
    band_lists_ready = true;

    // Record band membership once per curve and append to pre-sized lists.
    for (curves, 0..) |curve, ci| {
        const cb0 = curve.boundingBox();
        const cb = BBox{
            .min = Vec2.add(cb0.min, delta),
            .max = Vec2.add(cb0.max, delta),
        };
        curve_bboxes[ci] = cb;
        const curve_idx: u16 = @intCast(ci);
        for (0..h_bands) |bi| {
            if (cb.max.y >= h_band_min[bi] and cb.min.y <= h_band_max[bi]) {
                h_lists[bi].appendAssumeCapacity(curve_idx);
            }
        }
        for (0..v_bands) |bi| {
            if (cb.max.x >= v_band_min[bi] and cb.min.x <= v_band_max[bi]) {
                v_lists[bi].appendAssumeCapacity(curve_idx);
            }
        }
    }

    // Sort curves within bands: horizontal bands by descending max x, vertical by descending max y
    for (h_lists[0..@as(usize, h_bands)]) |band| {
        sortCurveIndicesDescendingX(band.items, curve_bboxes);
    }
    for (v_lists[0..@as(usize, v_bands)]) |band| {
        sortCurveIndicesDescendingY(band.items, curve_bboxes);
    }

    // Pack into band texture format.
    // Layout: [h_bands headers] [v_bands headers] [h_band_indices...] [v_band_indices...]
    const header_count: u32 = @as(u32, h_bands) + @as(u32, v_bands);
    var total_indices: u32 = 0;
    for (h_lists[0..@as(usize, h_bands)]) |band| total_indices += @intCast(band.items.len);
    for (v_lists[0..@as(usize, v_bands)]) |band| total_indices += @intCast(band.items.len);

    const total_texels = header_count + total_indices;
    var data = try allocator.alloc(u16, total_texels * 2);
    @memset(data, 0);

    // Write horizontal band headers
    var index_offset: u32 = header_count;
    for (0..h_bands) |bi| {
        const band = h_lists[bi];
        data[bi * 2 + 0] = @intCast(band.items.len); // curve count
        data[bi * 2 + 1] = @intCast(index_offset); // offset from glyph loc
        index_offset += @intCast(band.items.len);
    }

    // Write vertical band headers
    for (0..v_bands) |bi| {
        const off = (@as(usize, h_bands) + bi) * 2;
        const band = v_lists[bi];
        data[off + 0] = @intCast(band.items.len);
        data[off + 1] = @intCast(index_offset);
        index_offset += @intCast(band.items.len);
    }

    // Write horizontal band index entries (curveLoc in curve texture)
    var write_pos: u32 = header_count;
    for (h_lists[0..h_bands]) |band| {
        for (band.items) |curve_idx| {
            const curve_texel = @as(u32, curve_entry.offset) + @as(u32, curve_idx) * curve_tex.SEGMENT_TEXELS;
            const cx = curve_texel % TEX_WIDTH;
            const cy = curve_texel / TEX_WIDTH;
            data[write_pos * 2 + 0] = @intCast(cx);
            data[write_pos * 2 + 1] = @intCast(cy);
            write_pos += 1;
        }
    }

    // Write vertical band index entries
    for (v_lists[0..v_bands]) |band| {
        for (band.items) |curve_idx| {
            const curve_texel = @as(u32, curve_entry.offset) + @as(u32, curve_idx) * curve_tex.SEGMENT_TEXELS;
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

fn sortCurveIndicesDescendingX(indices: []u16, bboxes: []const BBox) void {
    const Context = struct {
        bboxes: []const BBox,
        pub fn lessThan(ctx: @This(), a: u16, b: u16) bool {
            const ca = ctx.bboxes[a];
            const cb = ctx.bboxes[b];
            return ca.max.x > cb.max.x;
        }
    };
    std.mem.sort(u16, indices, Context{ .bboxes = bboxes }, Context.lessThan);
}

fn sortCurveIndicesDescendingY(indices: []u16, bboxes: []const BBox) void {
    const Context = struct {
        bboxes: []const BBox,
        pub fn lessThan(ctx: @This(), a: u16, b: u16) bool {
            const ca = ctx.bboxes[a];
            const cb = ctx.bboxes[b];
            return ca.max.y > cb.max.y;
        }
    };
    std.mem.sort(u16, indices, Context{ .bboxes = bboxes }, Context.lessThan);
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

        // Copy glyph's band data into the texture.
        if (g.data.len > 0) {
            const dst_idx = texel_offset * 2;
            @memcpy(data[dst_idx .. dst_idx + g.data.len], g.data);
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
    const curves = [_]CurveSegment{
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(0, 0),
            .p1 = Vec2.new(0.5, 0.5),
            .p2 = Vec2.new(1, 0),
        },
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(1, 0),
            .p1 = Vec2.new(0.5, -0.5),
            .p2 = Vec2.new(0, 0),
        },
    };
    const bbox = BBox{ .min = Vec2.new(0, -0.5), .max = Vec2.new(1, 0.5) };
    const entry = curve_tex.GlyphCurveEntry{ .start_x = 0, .start_y = 0, .count = 2, .offset = 0 };

    var bd = try buildGlyphBandData(std.testing.allocator, &curves, bbox, entry, .zero);
    defer freeGlyphBandData(std.testing.allocator, &bd);

    try std.testing.expect(bd.h_band_count > 0);
    try std.testing.expect(bd.v_band_count > 0);
    try std.testing.expect(bd.texel_count > 0);
}

test "buildGlyphBandData rebases curves by origin" {
    const curves = [_]CurveSegment{
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(640, 960),
            .p1 = Vec2.new(660, 970),
            .p2 = Vec2.new(680, 960),
        },
    };
    const bbox = BBox{ .min = Vec2.new(0, 0), .max = Vec2.new(40, 10) };
    const entry = curve_tex.GlyphCurveEntry{ .start_x = 0, .start_y = 0, .count = 1, .offset = 0 };

    var bd = try buildGlyphBandData(std.testing.allocator, &curves, bbox, entry, Vec2.new(640, 960));
    defer freeGlyphBandData(std.testing.allocator, &bd);

    try std.testing.expectEqual(@as(u16, 1), bd.h_band_count);
    try std.testing.expectEqual(@as(u16, 1), bd.v_band_count);
    try std.testing.expectEqual(@as(u16, 4), bd.texel_count);
    try std.testing.expectApproxEqAbs(@as(f32, 0.025), bd.band_scale_x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.1), bd.band_scale_y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), bd.band_offset_x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), bd.band_offset_y, 0.0001);
}
