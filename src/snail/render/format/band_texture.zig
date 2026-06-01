const std = @import("std");
const bezier_mod = @import("../../math/bezier.zig");
const vec = @import("../../math/vec.zig");
const CurveSegment = bezier_mod.CurveSegment;
const BBox = bezier_mod.BBox;
const Vec2 = vec.Vec2;
const curve_tex = @import("curve_texture.zig");

const BandGeometry = struct {
    bbox: BBox,
    width: f32,
    height: f32,
    epsilon: f32,
};

const max_band_count = 12;
const sentinel_band = std.math.maxInt(u16);

/// Per-band curve index lists, backed by a single flat slab per axis
/// instead of `max_band_count` separate `ArrayList`s. Each band's slot
/// in the slab is fixed-size `curve_count`; the per-band length counter
/// tracks how many slots are populated.
///
/// Old layout cost: `2 * band_count = 32` small allocations per glyph,
/// plus 2 for `*_first_member`. New layout cost: 4 allocations per
/// glyph regardless of band count (h_slab, v_slab, h_first_member,
/// v_first_member).
const BandLists = struct {
    h_band_count: u16,
    v_band_count: u16,
    h_band_min: [max_band_count]f32 = undefined,
    h_band_max: [max_band_count]f32 = undefined,
    v_band_min: [max_band_count]f32 = undefined,
    v_band_max: [max_band_count]f32 = undefined,
    h_first_member: []u16,
    v_first_member: []u16,
    /// Flat backing slab for h-band lists: band `bi` owns
    /// `h_slab[bi * h_stride..][0..h_lens[bi]]`.
    h_slab: []u16,
    v_slab: []u16,
    h_stride: usize,
    v_stride: usize,
    h_lens: [max_band_count]u16 = .{0} ** max_band_count,
    v_lens: [max_band_count]u16 = .{0} ** max_band_count,

    fn init(allocator: std.mem.Allocator, curve_count: usize, geometry: BandGeometry, h_bands: u16, v_bands: u16) !BandLists {
        var out = BandLists{
            .h_band_count = h_bands,
            .v_band_count = v_bands,
            .h_first_member = try allocator.alloc(u16, curve_count),
            .v_first_member = undefined,
            .h_slab = undefined,
            .v_slab = undefined,
            .h_stride = curve_count,
            .v_stride = curve_count,
        };
        errdefer allocator.free(out.h_first_member);
        out.v_first_member = try allocator.alloc(u16, curve_count);
        errdefer allocator.free(out.v_first_member);
        out.h_slab = try allocator.alloc(u16, curve_count * @as(usize, h_bands));
        errdefer allocator.free(out.h_slab);
        out.v_slab = try allocator.alloc(u16, curve_count * @as(usize, v_bands));
        errdefer allocator.free(out.v_slab);

        for (0..h_bands) |bi| {
            const t0 = @as(f32, @floatFromInt(bi)) / @as(f32, @floatFromInt(h_bands));
            const t1 = @as(f32, @floatFromInt(bi + 1)) / @as(f32, @floatFromInt(h_bands));
            out.h_band_min[bi] = geometry.bbox.min.y + geometry.height * t0 - geometry.epsilon;
            out.h_band_max[bi] = geometry.bbox.min.y + geometry.height * t1 + geometry.epsilon;
        }
        for (0..v_bands) |bi| {
            const t0 = @as(f32, @floatFromInt(bi)) / @as(f32, @floatFromInt(v_bands));
            const t1 = @as(f32, @floatFromInt(bi + 1)) / @as(f32, @floatFromInt(v_bands));
            out.v_band_min[bi] = geometry.bbox.min.x + geometry.width * t0 - geometry.epsilon;
            out.v_band_max[bi] = geometry.bbox.min.x + geometry.width * t1 + geometry.epsilon;
        }

        @memset(out.h_first_member, sentinel_band);
        @memset(out.v_first_member, sentinel_band);
        return out;
    }

    fn deinit(self: *BandLists, allocator: std.mem.Allocator) void {
        allocator.free(self.h_slab);
        allocator.free(self.v_slab);
        allocator.free(self.h_first_member);
        allocator.free(self.v_first_member);
    }

    fn hBand(self: *const BandLists, bi: usize) []const u16 {
        return self.h_slab[bi * self.h_stride ..][0..self.h_lens[bi]];
    }

    fn vBand(self: *const BandLists, bi: usize) []const u16 {
        return self.v_slab[bi * self.v_stride ..][0..self.v_lens[bi]];
    }

    fn hBandMut(self: *BandLists, bi: usize) []u16 {
        return self.h_slab[bi * self.h_stride ..][0..self.h_lens[bi]];
    }

    fn vBandMut(self: *BandLists, bi: usize) []u16 {
        return self.v_slab[bi * self.v_stride ..][0..self.v_lens[bi]];
    }

    fn recordMembership(self: *BandLists, curve_bboxes: []const BBox) void {
        for (curve_bboxes, 0..) |cb, ci| {
            const curve_idx: u16 = @intCast(ci);
            for (0..self.h_band_count) |bi| {
                if (cb.max.y >= self.h_band_min[bi] and cb.min.y <= self.h_band_max[bi]) {
                    if (self.h_first_member[ci] == sentinel_band) self.h_first_member[ci] = @intCast(bi);
                    const slot = self.h_lens[bi];
                    self.h_slab[bi * self.h_stride + slot] = curve_idx;
                    self.h_lens[bi] = slot + 1;
                }
            }
            for (0..self.v_band_count) |bi| {
                if (cb.max.x >= self.v_band_min[bi] and cb.min.x <= self.v_band_max[bi]) {
                    if (self.v_first_member[ci] == sentinel_band) self.v_first_member[ci] = @intCast(bi);
                    const slot = self.v_lens[bi];
                    self.v_slab[bi * self.v_stride + slot] = curve_idx;
                    self.v_lens[bi] = slot + 1;
                }
            }
        }
    }

    fn sortMembership(self: *BandLists, curve_sort_max_x: []const f32, curve_sort_max_y: []const f32) void {
        for (0..@as(usize, self.h_band_count)) |bi| {
            sortCurveIndicesDescending(self.hBandMut(bi), curve_sort_max_y);
        }
        for (0..@as(usize, self.v_band_count)) |bi| {
            sortCurveIndicesDescending(self.vBandMut(bi), curve_sort_max_x);
        }
    }
};

const PackedBandData = struct {
    data: []u16,
    texel_count: u32,
};

fn curveControlMaxX(curve: CurveSegment) f32 {
    var result = @max(curve.p0.x, @max(curve.p1.x, curve.p2.x));
    if (curve.kind == .cubic) result = @max(result, curve.p3.x);
    return result;
}

fn curveControlMaxY(curve: CurveSegment) f32 {
    var result = @max(curve.p0.y, @max(curve.p1.y, curve.p2.y));
    if (curve.kind == .cubic) result = @max(result, curve.p3.y);
    return result;
}

fn localizeCurve(curve: CurveSegment, origin: Vec2) CurveSegment {
    const delta = Vec2.new(-origin.x, -origin.y);
    return .{
        .kind = curve.kind,
        .p0 = Vec2.add(curve.p0, delta),
        .p1 = Vec2.add(curve.p1, delta),
        .p2 = Vec2.add(curve.p2, delta),
        .p3 = if (curve.kind == .cubic) Vec2.add(curve.p3, delta) else curve.p3,
        .weights = curve.weights,
    };
}

fn curvePointMaxDelta(original: CurveSegment, quantized: CurveSegment) f32 {
    var max_delta = @max(
        @max(@abs(original.p0.x - quantized.p0.x), @abs(original.p0.y - quantized.p0.y)),
        @max(@abs(original.p1.x - quantized.p1.x), @abs(original.p1.y - quantized.p1.y)),
    );
    max_delta = @max(
        max_delta,
        @max(@abs(original.p2.x - quantized.p2.x), @abs(original.p2.y - quantized.p2.y)),
    );
    if (original.kind == .cubic) {
        max_delta = @max(
            max_delta,
            @max(@abs(original.p3.x - quantized.p3.x), @abs(original.p3.y - quantized.p3.y)),
        );
    }
    return max_delta;
}

fn directEncodingBandOverlap(curves: []const CurveSegment, prepared_curves: []const CurveSegment, origin: Vec2) f32 {
    var max_delta: f32 = 1.0 / 1024.0;
    for (curves, prepared_curves) |curve, prepared_curve| {
        max_delta = @max(max_delta, curvePointMaxDelta(localizeCurve(curve, origin), prepared_curve));
    }
    return max_delta * 2.0 + 1.0 / 1024.0;
}

pub const TEX_WIDTH: u32 = curve_tex.TEX_WIDTH;

/// Result of building band data for a single glyph.
/// Band texture layout for one glyph (all at row glyphLoc.y, starting at column glyphLoc.x):
///
///   [hband0] [hband1] ... [hbandN-1]  [vband0] [vband1] ... [vbandN-1]  [hband_indices...] [vband_indices...]
///
/// Each hband/vband entry: RG16UI = (curve_count, index_offset_from_glyphLoc)
/// Each index entry: RG16UI = ((first_member_band << 12) | curveLoc.x, curveLoc.y)
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

const curve_loc_x_bits = 12;
const curve_loc_x_limit: u32 = 1 << curve_loc_x_bits;
const curve_loc_x_mask: u16 = (1 << curve_loc_x_bits) - 1;

comptime {
    if (TEX_WIDTH > curve_loc_x_limit) {
        @compileError("band curve refs pack curveLoc.x into 12 bits");
    }
}

fn packBandCurveRef(curve_texel: u32, first_member_band: u16) [2]u16 {
    const cx = curve_texel % TEX_WIDTH;
    const cy = curve_texel / TEX_WIDTH;
    std.debug.assert(cx <= curve_loc_x_mask);
    std.debug.assert(first_member_band < (1 << (16 - curve_loc_x_bits)));
    return .{
        @as(u16, @intCast(cx)) | (first_member_band << curve_loc_x_bits),
        @intCast(cy),
    };
}

fn emptyGlyphBandData() GlyphBandData {
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

fn collectPreparedCurveMetrics(
    prepared_curves: []const CurveSegment,
    curve_bboxes: []BBox,
    curve_sort_max_x: []f32,
    curve_sort_max_y: []f32,
) BBox {
    // The first curve was previously computed twice (once to seed
    // `prepared_bbox`, once inside the loop). Hoist the first-curve case
    // out so each curve's boundingBox runs exactly once.
    const first = prepared_curves[0];
    var prepared_bbox = first.boundingBox();
    curve_bboxes[0] = prepared_bbox;
    curve_sort_max_x[0] = curveControlMaxX(first);
    curve_sort_max_y[0] = curveControlMaxY(first);
    for (prepared_curves[1..], 1..) |curve, ci| {
        const cb = curve.boundingBox();
        curve_bboxes[ci] = cb;
        curve_sort_max_x[ci] = curveControlMaxX(curve);
        curve_sort_max_y[ci] = curveControlMaxY(curve);
        prepared_bbox = prepared_bbox.merge(cb);
    }
    return prepared_bbox;
}

fn collectBandGeometry(
    curves: []const CurveSegment,
    bbox: BBox,
    origin: Vec2,
    prefer_direct_encoding: bool,
    prepared_curves: []const CurveSegment,
    curve_bboxes: []BBox,
    curve_sort_max_x: []f32,
    curve_sort_max_y: []f32,
) BandGeometry {
    const prepared_bbox = collectPreparedCurveMetrics(
        prepared_curves,
        curve_bboxes,
        curve_sort_max_x,
        curve_sort_max_y,
    );
    if (prefer_direct_encoding) {
        const delta = Vec2.new(-origin.x, -origin.y);
        const direct_bbox = BBox{
            .min = Vec2.add(bbox.min, delta),
            .max = Vec2.add(bbox.max, delta),
        };
        const geometry_bbox = direct_bbox.merge(prepared_bbox);
        return .{
            .bbox = geometry_bbox,
            .width = geometry_bbox.max.x - geometry_bbox.min.x,
            .height = geometry_bbox.max.y - geometry_bbox.min.y,
            .epsilon = directEncodingBandOverlap(curves, prepared_curves, origin),
        };
    }
    return .{
        .bbox = prepared_bbox,
        .width = prepared_bbox.max.x - prepared_bbox.min.x,
        .height = prepared_bbox.max.y - prepared_bbox.min.y,
        .epsilon = @max(@as(f32, 1.0 / 1024.0), curve_tex.PACKED_BAND_DILATION),
    };
}

fn packBandLists(
    allocator: std.mem.Allocator,
    curve_entry: curve_tex.GlyphCurveEntry,
    lists: *const BandLists,
) !PackedBandData {
    const h_bands = @as(usize, lists.h_band_count);
    const v_bands = @as(usize, lists.v_band_count);
    const header_count: u32 = @as(u32, lists.h_band_count) + @as(u32, lists.v_band_count);
    var total_indices: u32 = 0;
    for (0..h_bands) |bi| total_indices += lists.h_lens[bi];
    for (0..v_bands) |bi| total_indices += lists.v_lens[bi];

    const total_texels = header_count + total_indices;
    var data = try allocator.alloc(u16, total_texels * 2);
    // No @memset — the header + ref-list loops below write every word
    // in the buffer. Sufficient texels are allocated for exactly
    // header_count + total_indices texels (`total_texels * 2` words).

    var index_offset: u32 = header_count;
    for (0..h_bands) |bi| {
        const band_len = lists.h_lens[bi];
        data[bi * 2 + 0] = band_len;
        data[bi * 2 + 1] = @intCast(index_offset);
        index_offset += band_len;
    }

    for (0..v_bands) |bi| {
        const off = (h_bands + bi) * 2;
        const band_len = lists.v_lens[bi];
        data[off + 0] = band_len;
        data[off + 1] = @intCast(index_offset);
        index_offset += band_len;
    }

    var write_pos: u32 = header_count;
    for (0..h_bands) |bi| {
        for (lists.hBand(bi)) |curve_idx| {
            const curve_texel = @as(u32, curve_entry.offset) + @as(u32, curve_idx) * curve_tex.SEGMENT_TEXELS;
            const encoded = packBandCurveRef(curve_texel, lists.h_first_member[@intCast(curve_idx)]);
            data[write_pos * 2 + 0] = encoded[0];
            data[write_pos * 2 + 1] = encoded[1];
            write_pos += 1;
        }
    }

    for (0..v_bands) |bi| {
        for (lists.vBand(bi)) |curve_idx| {
            const curve_texel = @as(u32, curve_entry.offset) + @as(u32, curve_idx) * curve_tex.SEGMENT_TEXELS;
            const encoded = packBandCurveRef(curve_texel, lists.v_first_member[@intCast(curve_idx)]);
            data[write_pos * 2 + 0] = encoded[0];
            data[write_pos * 2 + 1] = encoded[1];
            write_pos += 1;
        }
    }

    return .{
        .data = data,
        .texel_count = total_texels,
    };
}

pub fn buildGlyphBandDataForGlyph(
    allocator: std.mem.Allocator,
    scratch: std.mem.Allocator,
    glyph: curve_tex.GlyphCurves,
    curve_entry: curve_tex.GlyphCurveEntry,
) !GlyphBandData {
    if (glyph.prepared_curves) |prepared_curves| {
        return buildGlyphBandDataWithPreparedCurves(
            allocator,
            scratch,
            glyph.curves,
            glyph.logical_curve_count,
            glyph.bbox,
            curve_entry,
            glyph.origin,
            glyph.prefer_direct_encoding,
            prepared_curves,
        );
    }
    return buildGlyphBandData(
        allocator,
        scratch,
        glyph.curves,
        glyph.logical_curve_count,
        glyph.bbox,
        curve_entry,
        glyph.origin,
        glyph.prefer_direct_encoding,
    );
}

/// Build band data for a single glyph, referencing the curve texture.
/// `allocator` owns the returned band data; `scratch` holds the
/// intermediate prepared curves + working buffers.
pub fn buildGlyphBandData(
    allocator: std.mem.Allocator,
    scratch: std.mem.Allocator,
    curves: []const CurveSegment,
    logical_curve_count: usize,
    bbox: BBox,
    curve_entry: curve_tex.GlyphCurveEntry,
    origin: Vec2,
    prefer_direct_encoding: bool,
) !GlyphBandData {
    if (curves.len == 0) return emptyGlyphBandData();

    const prepared_curves = if (prefer_direct_encoding)
        try curve_tex.prepareGlyphCurvesForDirectEncoding(scratch, curves, origin)
    else
        try curve_tex.prepareGlyphCurvesForPacking(scratch, curves, origin);
    defer scratch.free(prepared_curves);

    return buildGlyphBandDataWithPreparedCurves(
        allocator,
        scratch,
        curves,
        logical_curve_count,
        bbox,
        curve_entry,
        origin,
        prefer_direct_encoding,
        prepared_curves,
    );
}

pub fn buildGlyphBandDataWithPreparedCurves(
    allocator: std.mem.Allocator,
    scratch: std.mem.Allocator,
    curves: []const CurveSegment,
    logical_curve_count: usize,
    bbox: BBox,
    curve_entry: curve_tex.GlyphCurveEntry,
    origin: Vec2,
    prefer_direct_encoding: bool,
    prepared_curves: []const CurveSegment,
) !GlyphBandData {
    if (curves.len == 0) {
        std.debug.assert(prepared_curves.len == 0);
        return emptyGlyphBandData();
    }
    std.debug.assert(prepared_curves.len == curves.len);

    const band_curve_count = if (logical_curve_count == 0) curves.len else logical_curve_count;
    const h_bands = bandCount(band_curve_count);
    const v_bands = bandCount(band_curve_count);
    std.debug.assert(h_bands <= max_band_count and v_bands <= max_band_count);

    // Bounded-by-curve-count working arrays come off scratch — they
    // die at function return or sooner.
    const curve_bboxes = try scratch.alloc(BBox, prepared_curves.len);
    defer scratch.free(curve_bboxes);
    const curve_sort_max_x = try scratch.alloc(f32, prepared_curves.len);
    defer scratch.free(curve_sort_max_x);
    const curve_sort_max_y = try scratch.alloc(f32, prepared_curves.len);
    defer scratch.free(curve_sort_max_y);
    const geometry = collectBandGeometry(
        curves,
        bbox,
        origin,
        prefer_direct_encoding,
        prepared_curves,
        curve_bboxes,
        curve_sort_max_x,
        curve_sort_max_y,
    );

    var lists = try BandLists.init(scratch, prepared_curves.len, geometry, h_bands, v_bands);
    defer lists.deinit(scratch);
    lists.recordMembership(curve_bboxes);
    lists.sortMembership(curve_sort_max_x, curve_sort_max_y);
    // The packed band data is the returned output — owned by the
    // caller's `allocator`.
    const packed_data = try packBandLists(allocator, curve_entry, &lists);

    // Band transform: maps em-space coords to band indices
    const band_scale_x = @as(f32, @floatFromInt(v_bands)) / @max(geometry.width, 1e-10);
    const band_scale_y = @as(f32, @floatFromInt(h_bands)) / @max(geometry.height, 1e-10);
    const band_offset_x = -geometry.bbox.min.x * band_scale_x;
    const band_offset_y = -geometry.bbox.min.y * band_scale_y;

    return .{
        .data = packed_data.data,
        .texel_count = packed_data.texel_count,
        .h_band_count = h_bands,
        .v_band_count = v_bands,
        .band_scale_x = band_scale_x,
        .band_scale_y = band_scale_y,
        .band_offset_x = band_offset_x,
        .band_offset_y = band_offset_y,
    };
}

fn sortCurveIndicesDescending(indices: []u16, sort_keys: []const f32) void {
    // Per-band curve lists are tiny (typically 1-8 entries; sortMembership
    // runs per band, of which there are at most 12 per axis). std.mem.sort
    // uses block-sort which carries setup overhead that dwarfs the actual
    // comparison work for inputs this small. Insertion sort is ~10x faster
    // in the hot path for the realistic n<=16 case.
    if (indices.len <= 1) return;
    var i: usize = 1;
    while (i < indices.len) : (i += 1) {
        const v = indices[i];
        const key = sort_keys[v];
        var j: usize = i;
        while (j > 0 and sort_keys[indices[j - 1]] < key) : (j -= 1) {
            indices[j] = indices[j - 1];
        }
        indices[j] = v;
    }
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

/// Builds persistent band texture data plus scratch glyph entries.
/// `texture.data` is owned by `data_allocator`; `entries` is owned by
/// `scratch_allocator` and is only needed while building dependent metadata.
pub fn buildBandTexture(
    data_allocator: std.mem.Allocator,
    scratch_allocator: std.mem.Allocator,
    glyph_band_data: []const GlyphBandData,
) !struct { texture: BandTexture, entries: []GlyphBandEntry } {
    var total_texels: u32 = 0;
    for (glyph_band_data) |g| total_texels += g.texel_count;

    const height = @max(1, (total_texels + TEX_WIDTH - 1) / TEX_WIDTH);
    const padded = TEX_WIDTH * height;

    var data = try data_allocator.alloc(u16, padded * 2);
    errdefer data_allocator.free(data);
    @memset(data, 0);

    var entries = try scratch_allocator.alloc(GlyphBandEntry, glyph_band_data.len);
    errdefer scratch_allocator.free(entries);
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
            .allocator = data_allocator,
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

    var bd = try buildGlyphBandData(std.testing.allocator, std.testing.allocator, &curves, curves.len, bbox, entry, .zero, false);
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
    const prepared = try curve_tex.prepareGlyphCurvesForPacking(std.testing.allocator, &curves, Vec2.new(640, 960));
    defer std.testing.allocator.free(prepared);
    const prepared_bbox = prepared[0].boundingBox();

    var bd = try buildGlyphBandData(std.testing.allocator, std.testing.allocator, &curves, curves.len, bbox, entry, Vec2.new(640, 960), false);
    defer freeGlyphBandData(std.testing.allocator, &bd);

    try std.testing.expectEqual(@as(u16, 1), bd.h_band_count);
    try std.testing.expectEqual(@as(u16, 1), bd.v_band_count);
    try std.testing.expectEqual(@as(u16, 4), bd.texel_count);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0) / prepared_bbox.width(), bd.band_scale_x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0) / prepared_bbox.height(), bd.band_scale_y, 0.0001);
    try std.testing.expectApproxEqAbs(-prepared_bbox.min.x * bd.band_scale_x, bd.band_offset_x, 0.0001);
    try std.testing.expectApproxEqAbs(-prepared_bbox.min.y * bd.band_scale_y, bd.band_offset_y, 0.0001);
}

test "buildGlyphBandData derives band transform from prepared curve bbox" {
    const origin = Vec2.new(4096.25, 8192.5);
    const curves = [_]CurveSegment{
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(4096.375, 8192.625),
            .p1 = Vec2.new(4128.1875, 8207.3125),
            .p2 = Vec2.new(4160.4375, 8192.875),
        },
    };
    const entry = curve_tex.GlyphCurveEntry{ .start_x = 0, .start_y = 0, .count = 1, .offset = 0 };
    const prepared = try curve_tex.prepareGlyphCurvesForPacking(std.testing.allocator, &curves, origin);
    defer std.testing.allocator.free(prepared);
    const prepared_bbox = prepared[0].boundingBox();

    var bd = try buildGlyphBandData(
        std.testing.allocator,
        std.testing.allocator,
        &curves,
        curves.len,
        .{ .min = Vec2.new(-100, -100), .max = Vec2.new(100, 100) },
        entry,
        origin,
        false,
    );
    defer freeGlyphBandData(std.testing.allocator, &bd);

    try std.testing.expectApproxEqAbs(@as(f32, 1.0) / prepared_bbox.width(), bd.band_scale_x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0) / prepared_bbox.height(), bd.band_scale_y, 0.0001);
    try std.testing.expectApproxEqAbs(-prepared_bbox.min.x * bd.band_scale_x, bd.band_offset_x, 0.0001);
    try std.testing.expectApproxEqAbs(-prepared_bbox.min.y * bd.band_scale_y, bd.band_offset_y, 0.0001);
}

test "buildGlyphBandData uses logical curve count for band count" {
    const curves = [_]CurveSegment{
        .{ .kind = .quadratic, .p0 = Vec2.new(0, 0), .p1 = Vec2.new(32, 8), .p2 = Vec2.new(64, 0) },
        .{ .kind = .quadratic, .p0 = Vec2.new(64, 0), .p1 = Vec2.new(96, -8), .p2 = Vec2.new(128, 0) },
        .{ .kind = .quadratic, .p0 = Vec2.new(128, 0), .p1 = Vec2.new(160, 8), .p2 = Vec2.new(192, 0) },
        .{ .kind = .quadratic, .p0 = Vec2.new(192, 0), .p1 = Vec2.new(224, -8), .p2 = Vec2.new(256, 0) },
        .{ .kind = .quadratic, .p0 = Vec2.new(256, 0), .p1 = Vec2.new(288, 8), .p2 = Vec2.new(320, 0) },
        .{ .kind = .quadratic, .p0 = Vec2.new(320, 0), .p1 = Vec2.new(352, -8), .p2 = Vec2.new(384, 0) },
        .{ .kind = .quadratic, .p0 = Vec2.new(384, 0), .p1 = Vec2.new(416, 8), .p2 = Vec2.new(448, 0) },
    };
    const entry = curve_tex.GlyphCurveEntry{ .start_x = 0, .start_y = 0, .count = @intCast(curves.len), .offset = 0 };
    var bd = try buildGlyphBandData(
        std.testing.allocator,
        std.testing.allocator,
        &curves,
        2,
        .{ .min = Vec2.new(0, -8), .max = Vec2.new(448, 8) },
        entry,
        .zero,
        false,
    );
    defer freeGlyphBandData(std.testing.allocator, &bd);

    try std.testing.expectEqual(@as(u16, 1), bd.h_band_count);
    try std.testing.expectEqual(@as(u16, 1), bd.v_band_count);
}

test "buildGlyphBandData keeps direct encoded font bbox semantics" {
    const origin = Vec2.new(640, 960);
    const curves = [_]CurveSegment{
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(640.1, 960.1),
            .p1 = Vec2.new(659.9, 972.2),
            .p2 = Vec2.new(680.4, 960.4),
        },
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(680.4, 960.4),
            .p1 = Vec2.new(699.7, 948.8),
            .p2 = Vec2.new(720.2, 960.2),
        },
    };
    const entry = curve_tex.GlyphCurveEntry{ .start_x = 0, .start_y = 0, .count = @intCast(curves.len), .offset = 0 };
    const bbox = BBox{
        .min = Vec2.new(640.0, 948.0),
        .max = Vec2.new(721.0, 973.0),
    };
    const delta = Vec2.new(-origin.x, -origin.y);
    const local_bbox = BBox{
        .min = Vec2.add(bbox.min, delta),
        .max = Vec2.add(bbox.max, delta),
    };

    var bd = try buildGlyphBandData(
        std.testing.allocator,
        std.testing.allocator,
        &curves,
        curves.len,
        bbox,
        entry,
        origin,
        true,
    );
    defer freeGlyphBandData(std.testing.allocator, &bd);

    try std.testing.expectApproxEqAbs(@as(f32, 1.0) / local_bbox.width(), bd.band_scale_x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0) / local_bbox.height(), bd.band_scale_y, 0.0001);
    try std.testing.expectApproxEqAbs(-local_bbox.min.x * bd.band_scale_x, bd.band_offset_x, 0.0001);
    try std.testing.expectApproxEqAbs(-local_bbox.min.y * bd.band_scale_y, bd.band_offset_y, 0.0001);
}

test "direct encoded band overlap tracks coordinate quantization" {
    const curves = [_]CurveSegment{
        CurveSegment.fromLine(Vec2.new(10.03, 26.47), Vec2.new(90.11, 26.47)),
        CurveSegment.fromLine(Vec2.new(10.03, 60.19), Vec2.new(90.11, 60.19)),
    };
    const prepared = try curve_tex.prepareGlyphCurvesForDirectEncoding(std.testing.allocator, &curves, .zero);
    defer std.testing.allocator.free(prepared);

    const overlap = directEncodingBandOverlap(&curves, prepared, .zero);
    try std.testing.expect(overlap >= 1.0 / 1024.0);
    try std.testing.expect(overlap < 0.1);
}

test "buildGlyphBandData sorts horizontal curves by shader max x" {
    const curves = [_]CurveSegment{
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(0, 0),
            .p1 = Vec2.new(100, 10),
            .p2 = Vec2.new(0, 20),
        },
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(0, 0),
            .p1 = Vec2.new(40, 10),
            .p2 = Vec2.new(80, 20),
        },
    };
    const entry = curve_tex.GlyphCurveEntry{ .start_x = 0, .start_y = 0, .count = @intCast(curves.len), .offset = 0 };

    var bd = try buildGlyphBandData(
        std.testing.allocator,
        std.testing.allocator,
        &curves,
        curves.len,
        .{ .min = Vec2.new(0, 0), .max = Vec2.new(80, 20) },
        entry,
        .zero,
        false,
    );
    defer freeGlyphBandData(std.testing.allocator, &bd);

    try std.testing.expectEqual(@as(u16, 0), bd.data[4]);
    try std.testing.expectEqual(@as(u16, 4), bd.data[6]);
}

test "buildGlyphBandData direct encoding preserves local bbox semantics" {
    const origin = Vec2.new(1000.0, 2000.0);
    const curves = [_]CurveSegment{
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(1000.3, 2000.2),
            .p1 = Vec2.new(1048.6, 2000.2),
            .p2 = Vec2.new(1096.9, 2000.2),
        },
        .{
            .kind = .quadratic,
            .p0 = Vec2.new(1096.9, 2000.2),
            .p1 = Vec2.new(1145.2, 2000.2),
            .p2 = Vec2.new(1193.5, 2000.2),
        },
    };
    const bbox = BBox{
        .min = Vec2.new(1000.3, 2000.2),
        .max = Vec2.new(1193.5, 2000.2),
    };
    const local_bbox = BBox{
        .min = Vec2.new(0.3, 0.2),
        .max = Vec2.new(193.5, 0.2),
    };
    const entry = curve_tex.GlyphCurveEntry{ .start_x = 0, .start_y = 0, .count = @intCast(curves.len), .offset = 0 };

    var bd = try buildGlyphBandData(
        std.testing.allocator,
        std.testing.allocator,
        &curves,
        curves.len,
        bbox,
        entry,
        origin,
        true,
    );
    defer freeGlyphBandData(std.testing.allocator, &bd);

    try std.testing.expectApproxEqAbs(@as(f32, 1.0) / local_bbox.width(), bd.band_scale_x, 0.0001);
    try std.testing.expectApproxEqAbs(-local_bbox.min.x * bd.band_scale_x, bd.band_offset_x, 0.0001);
}
