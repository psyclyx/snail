const std = @import("std");
const bezier = @import("math/bezier.zig");
const ttf = @import("font/ttf.zig");
const curves_mod = @import("atlas/curves.zig");
const curve_tex = @import("render/format/curve_texture.zig");
const band_tex = @import("render/format/band_texture.zig");

pub const GlyphMetrics = ttf.GlyphMetrics;
pub const LineMetrics = ttf.LineMetrics;
pub const DecorationMetrics = ttf.DecorationMetrics;
pub const ScriptMetrics = ttf.ScriptMetrics;
pub const GlyphCache = ttf.GlyphCache;
pub const tt = struct {
    pub const exec = @import("font/truetype/exec.zig");
    pub const graphics = @import("font/truetype/graphics.zig");
    pub const outline = @import("font/truetype/outline.zig");
    pub const points = @import("font/truetype/points.zig");
    pub const tables = @import("font/truetype/tables.zig");
    pub const vm = @import("font/truetype/vm.zig");
};

test {
    _ = tt.exec.Context;
    _ = tt.graphics.GraphicsState;
    _ = tt.outline.Point;
    _ = tt.points.Zone;
    _ = tt.tables.ProgramTables;
    _ = tt.vm.Program;
}

/// A parsed TrueType font. Immutable after init.
/// Thread-safe for concurrent reads (glyphIndex, getKerning).
/// The init/deinit, unitsPerEm, glyphIndex, and advanceWidth methods are part
/// of Snail's stable public API.
pub const Font = struct {
    inner: ttf.Font,

    /// Parse a TrueType font from raw file data.
    /// The data slice must outlive the Font.
    pub fn init(data: []const u8) !Font {
        return .{ .inner = try ttf.Font.init(data) };
    }

    pub fn deinit(self: *Font) void {
        _ = self;
    }

    pub fn unitsPerEm(self: *const Font) u16 {
        return self.inner.units_per_em;
    }

    pub fn glyphIndex(self: *const Font, codepoint: u32) !u16 {
        return self.inner.glyphIndex(codepoint);
    }

    pub fn getKerning(self: *const Font, left: u16, right: u16) !i16 {
        return self.inner.getKerning(left, right);
    }

    pub fn glyphMetrics(self: *const Font, glyph_id: u16) !GlyphMetrics {
        return self.inner.glyphMetrics(glyph_id);
    }

    /// Return ascent/descent/line_gap from the font `hhea` table, in font units.
    pub fn lineMetrics(self: *const Font) !LineMetrics {
        return self.inner.lineMetrics();
    }

    pub fn advanceWidth(self: *const Font, glyph_id: u16) !i16 {
        return self.inner.advanceWidth(glyph_id);
    }

    /// Underline and strikethrough metrics from the post and OS/2 tables, in font units.
    pub fn decorationMetrics(self: *const Font) !DecorationMetrics {
        return self.inner.decorationMetrics();
    }

    /// Superscript size and offset from the OS/2 table, in font units.
    pub fn superscriptMetrics(self: *const Font) !ScriptMetrics {
        return self.inner.superscriptMetrics();
    }

    /// Subscript size and offset from the OS/2 table, in font units.
    pub fn subscriptMetrics(self: *const Font) !ScriptMetrics {
        return self.inner.subscriptMetrics();
    }

    pub fn bbox(self: *const Font, glyph_id: u16) !bezier.BBox {
        return self.inner.bbox(glyph_id);
    }

    /// Extract a glyph's outlines into the renderable `GlyphCurves` form
    /// the atlas consumes. The caller owns the returned value and must
    /// call `deinit` when done.
    ///
    /// `cache` is the compound-glyph component cache; pass a long-lived
    /// one across many `extractCurves` calls on the same font to avoid
    /// re-parsing referenced components. The returned `GlyphCurves` does
    /// not depend on the cache after the call returns.
    ///
    /// Glyphs with no contours (e.g. ASCII space) return `GlyphCurves.empty`.
    ///
    /// `allocator` owns the returned `GlyphCurves`. `scratch` holds the
    /// intermediate buffers (glyph parse, prepared/quantized curves,
    /// band scratch). For batched extraction (atlas warmup, prep
    /// passes) pass an `ArenaAllocator.allocator()` as `scratch` and
    /// reset it between glyphs; one-shot callers can pass the same
    /// allocator twice.
    pub fn extractCurves(
        self: *const Font,
        allocator: std.mem.Allocator,
        scratch: std.mem.Allocator,
        cache: *GlyphCache,
        glyph_id: u16,
    ) !curves_mod.GlyphCurves {
        return extractCurvesInner(self, allocator, scratch, cache, glyph_id);
    }

    pub const ColrLayer = ttf.Font.ColrLayer;
    pub const ColrLayerIterator = ttf.Font.ColrLayerIterator;

    /// Iterator over a COLR base glyph's layers (`(layer_glyph_id, color)`
    /// pairs). Returns an empty iterator for fonts without COLR or for
    /// glyphs that aren't COLR base glyphs.
    pub fn colrLayers(self: *const Font, base_glyph_id: u16) ColrLayerIterator {
        return self.inner.colrLayers(base_glyph_id);
    }

    pub fn colrLayerCount(self: *const Font, base_glyph_id: u16) u16 {
        return self.inner.colrLayerCount(base_glyph_id);
    }
};

const CurveSegment = bezier.CurveSegment;

fn extractCurvesInner(
    font: *const Font,
    allocator: std.mem.Allocator,
    scratch: std.mem.Allocator,
    cache: *GlyphCache,
    glyph_id: u16,
) !curves_mod.GlyphCurves {
    // `parseGlyph` keeps results in `cache` keyed by glyph id (long-lived
    // for batched extraction); using `scratch` here would be wrong since
    // the cache assumes its allocator outlives the cache.
    const glyph = try font.inner.parseGlyph(allocator, cache, glyph_id);
    if (glyph.contours.len == 0) return curves_mod.GlyphCurves.empty(allocator);

    var total_curves: usize = 0;
    for (glyph.contours) |contour| total_curves += contour.curves.len;
    if (total_curves == 0) return curves_mod.GlyphCurves.empty(allocator);

    const segs = try scratch.alloc(CurveSegment, total_curves);
    defer scratch.free(segs);

    var write_idx: usize = 0;
    for (glyph.contours) |contour| {
        for (contour.curves) |q| {
            segs[write_idx] = CurveSegment.fromQuad(q);
            write_idx += 1;
        }
    }

    // Cache analytic bboxes during prepare so glyphRenderBBox and the
    // band-build pass don't each recompute them.
    const prepared_bboxes = try scratch.alloc(bezier.BBox, segs.len);
    defer scratch.free(prepared_bboxes);
    const prepared = try curve_tex.prepareGlyphCurvesForDirectEncodingWithBBoxes(scratch, segs, .zero, prepared_bboxes);
    defer scratch.free(prepared);

    const render_bbox = glyphRenderBBoxFromBBoxes(glyph.metrics.bbox, prepared_bboxes);

    // Single-glyph direct encoding. Skip `buildCurveTexture`'s TEX_WIDTH
    // padding (which would allocate ~32 KB per glyph just to drop most of
    // it on the floor) — write the curve bytes directly into a tight
    // buffer the atlas can consume verbatim.
    const curve_count: u16 = @intCast(prepared.len);
    const curve_bytes = try curve_tex.encodeDirectSingleGlyphCurves(allocator, prepared);
    errdefer allocator.free(curve_bytes);

    const entry = curve_tex.GlyphCurveEntry{
        .start_x = 0,
        .start_y = 0,
        .count = curve_count,
        .offset = 0,
    };
    // Band data goes straight to the output allocator — no intermediate
    // dupe. Internal working buffers (curve_bboxes, sort arrays,
    // BandLists slabs) use scratch.
    const bd = try band_tex.buildGlyphBandDataWithPreparedCurves(
        allocator,
        scratch,
        segs,
        segs.len,
        render_bbox,
        entry,
        .zero,
        true,
        prepared,
        prepared_bboxes,
    );
    errdefer band_tex.freeGlyphBandData(allocator, @constCast(&bd));

    const band_bytes = bd.data;

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

fn glyphRenderBBox(metrics_bbox: bezier.BBox, prepared: []const CurveSegment) bezier.BBox {
    if (prepared.len == 0) return metrics_bbox;
    var prepared_bbox = prepared[0].boundingBox();
    for (prepared[1..]) |curve| prepared_bbox = prepared_bbox.merge(curve.boundingBox());
    return metrics_bbox.merge(prepared_bbox);
}

fn glyphRenderBBoxFromBBoxes(metrics_bbox: bezier.BBox, bboxes: []const bezier.BBox) bezier.BBox {
    if (bboxes.len == 0) return metrics_bbox;
    var prepared_bbox = bboxes[0];
    for (bboxes[1..]) |b| prepared_bbox = prepared_bbox.merge(b);
    return metrics_bbox.merge(prepared_bbox);
}

test "extractCurves returns non-empty curves for printable glyph" {
    const font_data = @import("assets").noto_sans_regular;
    var font = try Font.init(font_data);
    defer font.deinit();

    var cache = GlyphCache.init(std.testing.allocator);
    defer cache.deinit();

    const glyph_id = try font.glyphIndex('A');
    var curves = try font.extractCurves(std.testing.allocator, std.testing.allocator, &cache, glyph_id);
    defer curves.deinit();

    try std.testing.expect(curves.curve_count > 0);
    try std.testing.expect(curves.curve_bytes.len > 0);
    try std.testing.expect(curves.band_bytes.len > 0);
    try std.testing.expect(curves.h_band_count > 0);
    try std.testing.expect(curves.v_band_count > 0);
}

test "extractCurves returns empty for whitespace glyph" {
    const font_data = @import("assets").noto_sans_regular;
    var font = try Font.init(font_data);
    defer font.deinit();

    var cache = GlyphCache.init(std.testing.allocator);
    defer cache.deinit();

    const space_id = try font.glyphIndex(' ');
    var curves = try font.extractCurves(std.testing.allocator, std.testing.allocator, &cache, space_id);
    defer curves.deinit();

    try std.testing.expect(curves.isEmpty());
}

test "extractCurves matches existing curve packing path byte-for-byte" {
    // The producer reuses `buildCurveTexture` and `buildGlyphBandData` from
    // render/format. For a single-glyph input, the produced curve_bytes
    // must equal the prefix of the existing packed curve-texture data.
    const font_data = @import("assets").noto_sans_regular;
    var font = try Font.init(font_data);
    defer font.deinit();

    var cache = GlyphCache.init(std.testing.allocator);
    defer cache.deinit();

    const glyph_id = try font.glyphIndex('M');
    var curves = try font.extractCurves(std.testing.allocator, std.testing.allocator, &cache, glyph_id);
    defer curves.deinit();

    // Re-run the same packing through the format helpers directly and
    // compare. (This guards against accidental schema drift in the
    // producer.)
    const glyph = try font.inner.parseGlyph(std.testing.allocator, &cache, glyph_id);

    var segs: std.ArrayList(CurveSegment) = .empty;
    defer segs.deinit(std.testing.allocator);
    for (glyph.contours) |contour| {
        for (contour.curves) |q| try segs.append(std.testing.allocator, CurveSegment.fromQuad(q));
    }
    const prepared = try curve_tex.prepareGlyphCurvesForDirectEncoding(std.testing.allocator, segs.items, .zero);
    defer std.testing.allocator.free(prepared);
    const render_bbox = glyphRenderBBox(glyph.metrics.bbox, prepared);

    const single = [_]curve_tex.GlyphCurves{.{
        .curves = segs.items,
        .bbox = render_bbox,
        .logical_curve_count = segs.items.len,
        .prefer_direct_encoding = true,
        .prepared_curves = prepared,
    }};
    var ct = try curve_tex.buildCurveTexture(std.testing.allocator, std.testing.allocator, &single);
    defer ct.texture.deinit();
    defer std.testing.allocator.free(ct.entries);

    const used_words: usize = @as(usize, curves.curve_count) * curve_tex.SEGMENT_TEXELS * 4;
    try std.testing.expectEqualSlices(u16, ct.texture.data[0..used_words], curves.curve_bytes);
}
