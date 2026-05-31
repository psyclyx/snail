//! Path-based curves producers. `pathToCurves` packs a fill; `strokeToCurves`
//! packs the offset outline of a stroke. Both return the unified `GlyphCurves`
//! the atlas consumes, in the same format as `Font.extractCurves`.

const std = @import("std");
const bezier = @import("math/bezier.zig");
const curves_mod = @import("atlas/curves.zig");
const curve_tex = @import("render/format/curve_texture.zig");
const band_tex = @import("render/format/band_texture.zig");
const path_mod = @import("path.zig");
const paint = @import("paint.zig");

pub const Path = path_mod.Path;
pub const StrokeStyle = paint.StrokeStyle;
const CurveSegment = bezier.CurveSegment;
const BBox = bezier.BBox;

/// Pack a path's filled outline as `GlyphCurves`. Returns an empty value
/// for paths with no curves or unbounded extent.
pub fn pathToCurves(
    allocator: std.mem.Allocator,
    path: *const Path,
) !curves_mod.GlyphCurves {
    if (path.isEmpty()) return curves_mod.GlyphCurves.empty(allocator);
    const bb = path.bounds() orelse return curves_mod.GlyphCurves.empty(allocator);

    const segs = try path.cloneFilledCurves(allocator);
    defer allocator.free(segs);
    if (segs.len == 0) return curves_mod.GlyphCurves.empty(allocator);

    return packCurves(allocator, segs, bb, path.filledBandCurveCount());
}

/// Pack a path's stroked outline as `GlyphCurves`. Returns an empty value
/// if the stroke is degenerate (zero width, no contours).
pub fn strokeToCurves(
    allocator: std.mem.Allocator,
    path: *const Path,
    stroke: StrokeStyle,
) !curves_mod.GlyphCurves {
    const result = (try path.cloneStrokedCurves(allocator, stroke)) orelse
        return curves_mod.GlyphCurves.empty(allocator);
    defer allocator.free(result.curves);

    return packCurves(allocator, result.curves, result.bbox, result.logical_curve_count);
}

fn packCurves(
    allocator: std.mem.Allocator,
    segs: []const CurveSegment,
    fill_bbox: BBox,
    logical_curve_count: usize,
) !curves_mod.GlyphCurves {
    // The GL/Vulkan path shader assumes each uploaded cubic is monotonic
    // along both sampling axes (see `solveMonotonicCubicRoot` in
    // snail_path_frag_body.glsl). Split cubics at their x/y extrema before
    // packing so the GPU coverage evaluator sees only monotonic pieces.
    // Conics and quadratics are unaffected.
    const split = try curve_tex.splitCubicsAtExtrema(allocator, segs);
    defer allocator.free(split);

    // Direct-encoding (one f16 quantize per point) instead of packed
    // (anchor chunk+frac decode + relative deltas). The packed encode
    // path makes `p0` go through `decodeAnchor(quantize(chunk),
    // quantize(frac))` while control points use `anchor + quantize(rel)`.
    // For extremum-split cubic joins, the LEFT half's `p3` and the RIGHT
    // half's `p0` then quantize asymmetrically — leaving ~1 ULP residual
    // at the join that defeats `splitCubicsAtExtrema`'s zero-tangent
    // snap. Direct encoding quantizes every point with the same
    // `quantizeVec2F16`, so the join is bit-exact on both sides.
    const prepared = try curve_tex.prepareGlyphCurvesForDirectEncoding(allocator, split, .zero);
    defer allocator.free(prepared);

    const render_bbox = mergeBBoxWithCurves(fill_bbox, prepared);

    // Single-shape direct encoding: skip `buildCurveTexture`'s TEX_WIDTH
    // padding (~32 KB per shape allocated to drop most of it on the
    // floor). Same fix as the font extractor uses.
    const curve_count: u16 = @intCast(prepared.len);
    const curve_bytes = try curve_tex.encodeDirectSingleGlyphCurves(allocator, prepared);
    errdefer allocator.free(curve_bytes);

    const entry = curve_tex.GlyphCurveEntry{
        .start_x = 0,
        .start_y = 0,
        .count = curve_count,
        .offset = 0,
    };
    var bd = try band_tex.buildGlyphBandDataWithPreparedCurves(
        allocator,
        split,
        logical_curve_count,
        render_bbox,
        entry,
        .zero,
        false,
        prepared,
    );
    defer band_tex.freeGlyphBandData(allocator, &bd);

    const band_bytes = try allocator.dupe(u16, bd.data);

    return .{
        .allocator = allocator,
        .curve_bytes = curve_bytes,
        .band_bytes = band_bytes,
        .curve_count = curve_count,
        .h_band_count = bd.h_band_count,
        .v_band_count = bd.v_band_count,
        .band_scale_x = bd.band_scale_x,
        .band_scale_y = bd.band_scale_y,
        .band_offset_x = bd.band_offset_x,
        .band_offset_y = bd.band_offset_y,
        .bbox = render_bbox,
    };
}

fn mergeBBoxWithCurves(base: BBox, curves: []const CurveSegment) BBox {
    if (curves.len == 0) return base;
    var merged = base;
    for (curves) |c| merged = merged.merge(c.boundingBox());
    return merged;
}

const testing = std.testing;
const Vec2 = @import("math/vec.zig").Vec2;
const Rect = @import("target.zig").Rect;

test "pathToCurves packs a rectangle fill" {
    var path = Path.init(testing.allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 100, .h = 50 });

    var curves = try pathToCurves(testing.allocator, &path);
    defer curves.deinit();

    try testing.expect(curves.curve_count > 0);
    try testing.expect(curves.curve_bytes.len > 0);
    try testing.expect(curves.h_band_count > 0);
    try testing.expect(curves.v_band_count > 0);
    try testing.expect(curves.bbox.max.x >= 100.0);
}

test "pathToCurves returns empty for empty path" {
    var path = Path.init(testing.allocator);
    defer path.deinit();

    var curves = try pathToCurves(testing.allocator, &path);
    defer curves.deinit();

    try testing.expect(curves.isEmpty());
}

test "strokeToCurves packs a stroked rectangle outline" {
    var path = Path.init(testing.allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 100, .h = 50 });

    var curves = try strokeToCurves(testing.allocator, &path, .{
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
        .width = 2.0,
    });
    defer curves.deinit();

    try testing.expect(curves.curve_count > 0);
    try testing.expect(curves.h_band_count > 0);
    try testing.expect(curves.v_band_count > 0);
}

test "strokeToCurves returns empty for zero-width stroke" {
    var path = Path.init(testing.allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 100, .h = 50 });

    var curves = try strokeToCurves(testing.allocator, &path, .{
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
        .width = 0.0,
    });
    defer curves.deinit();

    try testing.expect(curves.isEmpty());
}

test "pathToCurves: round-trip into atlas" {
    const atlas_mod = @import("atlas.zig");
    const record_key_mod = @import("atlas/record_key.zig");

    var path = Path.init(testing.allocator);
    defer path.deinit();
    try path.addRoundedRect(.{ .x = 10, .y = 10, .w = 200, .h = 100 }, 8);

    var curves = try pathToCurves(testing.allocator, &path);
    defer curves.deinit();

    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 12,
    });
    defer pool.deinit();

    const key = record_key_mod.RecordKey{
        .namespace = record_key_mod.ns.path_fill,
        .a = 0,
        .b = 1,
    };
    var atlas = try atlas_mod.Atlas.from(testing.allocator, pool, &.{
        .{ .key = key, .curves = curves },
    });
    defer atlas.deinit();

    const rec = atlas.lookupRecord(key) orelse return error.MissingRecord;
    try testing.expect(rec.curve_count == curves.curve_count);
}
