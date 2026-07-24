const std = @import("std");
const bezier = @import("math/bezier.zig");
const ttf = @import("font/ttf.zig");
const sfnt = @import("font/sfnt.zig");
const font_types = @import("font/types.zig");
const modern_font = @import("font/harfbuzz_font.zig");
const curves_mod = @import("atlas/curves.zig");
const curve_tex = @import("format/curve_texture.zig");
const band_tex = @import("format/band_texture.zig");

pub const GlyphMetrics = ttf.GlyphMetrics;
pub const LineMetrics = ttf.LineMetrics;
pub const DecorationMetrics = ttf.DecorationMetrics;
pub const ScriptMetrics = ttf.ScriptMetrics;
pub const OutlineFormat = ttf.OutlineFormat;
pub const Variation = font_types.Variation;
pub const VariationAxis = font_types.VariationAxis;
pub const Options = font_types.Options;
const tt = struct {
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

/// A parsed view over caller-owned bytes. Immutable after init.
/// Thread-safe for concurrent reads (glyphIndex, getKerning).
/// No deinit — the struct holds no owned resources; let it go out of scope.
pub const Font = struct {
    inner: ttf.Font,
    variations: []const Variation = &.{},

    /// Parse an OpenType font from raw file data.
    /// The data slice must outlive the Font.
    pub fn init(data: []const u8) !Font {
        return initWithOptions(data, .{});
    }

    /// Parse one zero-based face from a standalone font or TTC/OTC.
    /// The data slice must outlive the Font.
    pub fn initFace(data: []const u8, face_index: u32) !Font {
        return initWithOptions(data, .{ .face_index = face_index });
    }

    /// Parse a font face and borrow its variable-font coordinates. Both the
    /// font bytes and the variations slice must outlive the Font.
    pub fn initWithOptions(data: []const u8, options: Options) !Font {
        for (options.variations) |variation| {
            if (!std.math.isFinite(variation.value)) return error.InvalidVariation;
        }
        return .{
            .inner = try ttf.Font.initFace(data, options.face_index),
            .variations = options.variations,
        };
    }

    /// Return the number of faces in a standalone font or collection.
    pub fn faceCount(data: []const u8) !u32 {
        return sfnt.faceCount(data);
    }

    pub fn faceIndex(self: *const Font) u32 {
        return self.inner.face_index;
    }

    pub fn outlineFormat(self: *const Font) OutlineFormat {
        return self.inner.outline_format;
    }

    /// Inspect the design axes advertised by `fvar`. Caller owns the result.
    pub fn variationAxes(self: *const Font, allocator: std.mem.Allocator) ![]VariationAxis {
        return modern_font.variationAxes(allocator, self.inner.data, self.inner.face_index);
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
        if (self.requiresModernBackend()) {
            const metrics = try modern_font.glyphMetrics(
                self.inner.data,
                self.inner.face_index,
                self.inner.units_per_em,
                self.variations,
                glyph_id,
            );
            return .{
                .advance_width = std.math.cast(u16, metrics.advance_width) orelse return error.InvalidFont,
                .lsb = std.math.cast(i16, metrics.lsb) orelse return error.InvalidFont,
                .bbox = metrics.bbox,
            };
        }
        return self.inner.glyphMetrics(glyph_id);
    }

    /// Return ascent/descent/line_gap from the font `hhea` table, in font units.
    pub fn lineMetrics(self: *const Font) !LineMetrics {
        if (self.variations.len != 0) {
            const metrics = try modern_font.lineMetrics(
                self.inner.data,
                self.inner.face_index,
                self.inner.units_per_em,
                self.variations,
            );
            return .{
                .ascent = try metricI16(metrics.ascent),
                .descent = try metricI16(metrics.descent),
                .line_gap = try metricI16(metrics.line_gap),
            };
        }
        return self.inner.lineMetrics();
    }

    pub fn advanceWidth(self: *const Font, glyph_id: u16) !i16 {
        if (self.requiresModernBackend()) {
            return std.math.cast(i16, (try self.glyphMetrics(glyph_id)).advance_width) orelse error.InvalidFont;
        }
        return self.inner.advanceWidth(glyph_id);
    }

    /// Underline and strikethrough metrics from the post and OS/2 tables, in font units.
    pub fn decorationMetrics(self: *const Font) !DecorationMetrics {
        if (self.variations.len != 0) {
            return .{
                .underline_position = try self.modernMetric(.underline_offset),
                .underline_thickness = try self.modernMetric(.underline_size),
                .strikethrough_position = try self.modernMetric(.strikeout_offset),
                .strikethrough_thickness = try self.modernMetric(.strikeout_size),
            };
        }
        return self.inner.decorationMetrics();
    }

    /// Superscript size and offset from the OS/2 table, in font units.
    pub fn superscriptMetrics(self: *const Font) !ScriptMetrics {
        if (self.variations.len != 0) return self.modernScriptMetrics(true);
        return self.inner.superscriptMetrics();
    }

    /// Subscript size and offset from the OS/2 table, in font units.
    pub fn subscriptMetrics(self: *const Font) !ScriptMetrics {
        if (self.variations.len != 0) return self.modernScriptMetrics(false);
        return self.inner.subscriptMetrics();
    }

    pub fn bbox(self: *const Font, glyph_id: u16) !bezier.BBox {
        return (try self.glyphMetrics(glyph_id)).bbox;
    }

    /// Extract a glyph's outlines into the renderable `GlyphCurves` form
    /// the atlas consumes. The caller owns the returned value and must
    /// call `deinit` when done.
    ///
    /// Glyphs with no contours (e.g. ASCII space) return `GlyphCurves.empty`.
    ///
    /// `allocator` owns the returned `GlyphCurves`. `scratch` holds the
    /// intermediate buffers (glyph parse — including the in-call
    /// compound-component cache — prepared/quantized curves, band
    /// scratch). For batched extraction (atlas warmup, prep passes)
    /// pass an `ArenaAllocator.allocator()` as `scratch` and reset it
    /// between glyphs; one-shot callers can pass the same allocator
    /// twice.
    pub fn extractCurves(
        self: *const Font,
        allocator: std.mem.Allocator,
        scratch: std.mem.Allocator,
        glyph_id: u16,
    ) !curves_mod.GlyphCurves {
        return extractCurvesInner(self, allocator, scratch, glyph_id);
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

    fn requiresModernBackend(self: *const Font) bool {
        return self.inner.outline_format != .truetype or self.variations.len != 0;
    }

    fn modernMetric(self: *const Font, tag: font_types.MetricTag) !i16 {
        return metricI16(try modern_font.metricByTag(
            self.inner.data,
            self.inner.face_index,
            self.inner.units_per_em,
            self.variations,
            tag,
        ));
    }

    fn modernScriptMetrics(self: *const Font, superscript: bool) !ScriptMetrics {
        const tags: [4]font_types.MetricTag = if (superscript)
            .{ .superscript_x_size, .superscript_y_size, .superscript_x_offset, .superscript_y_offset }
        else
            .{ .subscript_x_size, .subscript_y_size, .subscript_x_offset, .subscript_y_offset };
        return .{
            .x_size = try self.modernMetric(tags[0]),
            .y_size = try self.modernMetric(tags[1]),
            .x_offset = try self.modernMetric(tags[2]),
            .y_offset = try self.modernMetric(tags[3]),
        };
    }
};

fn metricI16(value: i32) !i16 {
    return std.math.cast(i16, value) orelse error.InvalidFont;
}

const CurveSegment = bezier.CurveSegment;

fn extractCurvesInner(
    font: *const Font,
    allocator: std.mem.Allocator,
    scratch: std.mem.Allocator,
    glyph_id: u16,
) !curves_mod.GlyphCurves {
    if (font.requiresModernBackend()) {
        var instance = try modern_font.Instance.init(
            font.inner.data,
            font.inner.face_index,
            font.inner.units_per_em,
            font.variations,
        );
        defer instance.deinit();
        var outline = try instance.glyphOutline(
            scratch,
            glyph_id,
            1.0 / @as(f32, @floatFromInt(font.inner.units_per_em)),
        );
        defer outline.deinit();
        return packGlyphCurves(
            allocator,
            scratch,
            outline.segments,
            instance.glyphMetrics(font.inner.units_per_em, glyph_id).bbox,
        );
    }
    // `parseGlyph` returns contours, sub-curves, and an internal
    // component-cache hashmap all allocated on `scratch`; the data is
    // read once below and then discarded. We wrap `scratch` in a
    // per-call arena so callers can pass any allocator (one-shot or
    // pooled) without leaking the intermediate parse buffers.
    var parse_arena = std.heap.ArenaAllocator.init(scratch);
    defer parse_arena.deinit();
    const glyph = try font.inner.parseGlyph(parse_arena.allocator(), glyph_id);
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

    return packGlyphCurves(allocator, scratch, segs, glyph.metrics.bbox);
}

fn packGlyphCurves(
    allocator: std.mem.Allocator,
    scratch: std.mem.Allocator,
    segs: []const CurveSegment,
    metrics_bbox: bezier.BBox,
) !curves_mod.GlyphCurves {
    if (segs.len == 0) return curves_mod.GlyphCurves.empty(allocator);

    // Cache analytic bboxes during prepare so glyphRenderBBox and the
    // band-build pass don't each recompute them.
    const prepared_bboxes = try scratch.alloc(bezier.BBox, segs.len);
    defer scratch.free(prepared_bboxes);
    const prepared = try curve_tex.prepareGlyphCurvesForDirectEncodingWithBBoxes(scratch, segs, .zero, prepared_bboxes);
    defer scratch.free(prepared);

    const render_bbox = glyphRenderBBoxFromBBoxes(metrics_bbox, prepared_bboxes);

    // Single-glyph direct encoding. Skip `buildCurveTexture`'s TEX_WIDTH
    // padding (which would allocate ~32 KB per glyph just to drop most of
    // it on the floor) — write the curve bytes directly into a tight
    // buffer the atlas can consume verbatim.
    const curve_count = try checkedCurveCount(prepared.len);
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
        .path_curve_class = curves_mod.classifyPathCurves(segs),
        .h_band_count = bd.h_band_count,
        .v_band_count = bd.v_band_count,
        .band_scale_x = bd.band_scale_x,
        .band_scale_y = bd.band_scale_y,
        .band_offset_x = bd.band_offset_x,
        .band_offset_y = bd.band_offset_y,
        .bbox = render_bbox,
    };
}

fn checkedCurveCount(count: usize) error{ShapeTooComplex}!u16 {
    return std.math.cast(u16, count) orelse error.ShapeTooComplex;
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

    const glyph_id = try font.glyphIndex('A');
    var curves = try font.extractCurves(std.testing.allocator, std.testing.allocator, glyph_id);
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

    const space_id = try font.glyphIndex(' ');
    var curves = try font.extractCurves(std.testing.allocator, std.testing.allocator, space_id);
    defer curves.deinit();

    try std.testing.expect(curves.isEmpty());
}

test "static CFF font exposes metrics and cubic outlines" {
    const font_data = @import("assets").source_serif_cff;
    var font = try Font.init(font_data);
    try std.testing.expectEqual(OutlineFormat.cff, font.outlineFormat());

    const glyph_id = try font.glyphIndex('S');
    const metrics = try font.glyphMetrics(glyph_id);
    try std.testing.expect(metrics.advance_width > 0);
    try std.testing.expect(metrics.bbox.width() > 0);

    var curves = try font.extractCurves(std.testing.allocator, std.testing.allocator, glyph_id);
    defer curves.deinit();
    try std.testing.expect(curves.curve_count > 0);
    try std.testing.expect(curves.band_bytes.len > 0);
}

test "CFF2 variable coordinates affect axes metrics and outlines" {
    const font_data = @import("assets").source_serif_cff2_variable;
    const light_coords = [_]Variation{
        .{ .tag = "wght".*, .value = 200 },
        .{ .tag = "opsz".*, .value = 20 },
    };
    const heavy_coords = [_]Variation{
        .{ .tag = "wght".*, .value = 900 },
        .{ .tag = "opsz".*, .value = 20 },
    };
    var light = try Font.initWithOptions(font_data, .{ .variations = &light_coords });
    var heavy = try Font.initWithOptions(font_data, .{ .variations = &heavy_coords });
    try std.testing.expectEqual(OutlineFormat.cff2, light.outlineFormat());

    const axes = try light.variationAxes(std.testing.allocator);
    defer std.testing.allocator.free(axes);
    var found_weight = false;
    var found_optical_size = false;
    for (axes) |axis| {
        if (std.mem.eql(u8, &axis.tag, "wght")) found_weight = true;
        if (std.mem.eql(u8, &axis.tag, "opsz")) found_optical_size = true;
    }
    try std.testing.expect(found_weight);
    try std.testing.expect(found_optical_size);

    const glyph_id = try light.glyphIndex('m');
    const light_metrics = try light.glyphMetrics(glyph_id);
    const heavy_metrics = try heavy.glyphMetrics(glyph_id);
    try std.testing.expect(light_metrics.advance_width != heavy_metrics.advance_width);

    var light_curves = try light.extractCurves(std.testing.allocator, std.testing.allocator, glyph_id);
    defer light_curves.deinit();
    var heavy_curves = try heavy.extractCurves(std.testing.allocator, std.testing.allocator, glyph_id);
    defer heavy_curves.deinit();
    try std.testing.expect(!std.mem.eql(u16, light_curves.curve_bytes, heavy_curves.curve_bytes));
}

test "TrueType gvar coordinates affect native-format outlines" {
    const font_data = @import("assets").noto_sans_mono;
    const thin_coordinates = [_]Variation{.{ .tag = "wght".*, .value = 100 }};
    const black_coordinates = [_]Variation{.{ .tag = "wght".*, .value = 900 }};
    var thin = try Font.initWithOptions(font_data, .{ .variations = &thin_coordinates });
    var black = try Font.initWithOptions(font_data, .{ .variations = &black_coordinates });
    try std.testing.expectEqual(OutlineFormat.truetype, thin.outlineFormat());

    const glyph_id = try thin.glyphIndex('m');
    var thin_curves = try thin.extractCurves(std.testing.allocator, std.testing.allocator, glyph_id);
    defer thin_curves.deinit();
    var black_curves = try black.extractCurves(std.testing.allocator, std.testing.allocator, glyph_id);
    defer black_curves.deinit();
    try std.testing.expect(!std.mem.eql(u16, thin_curves.curve_bytes, black_curves.curve_bytes));
    const thin_bbox = try thin.bbox(glyph_id);
    const black_bbox = try black.bbox(glyph_id);
    try std.testing.expect(thin_bbox.width() != black_bbox.width() or thin_bbox.height() != black_bbox.height());
}

test "OpenType collections select CFF and varied CFF2 faces" {
    const collection = @import("assets").test_opentype_collection;
    try std.testing.expectEqual(@as(u32, 2), try Font.faceCount(collection));

    var cff = try Font.initFace(collection, 0);
    try std.testing.expectEqual(OutlineFormat.cff, cff.outlineFormat());
    var cff_curves = try cff.extractCurves(
        std.testing.allocator,
        std.testing.allocator,
        try cff.glyphIndex('A'),
    );
    defer cff_curves.deinit();
    try std.testing.expect(cff_curves.curve_count > 0);

    const coordinates = [_]Variation{.{ .tag = "wght".*, .value = 800 }};
    var cff2 = try Font.initWithOptions(collection, .{
        .face_index = 1,
        .variations = &coordinates,
    });
    try std.testing.expectEqual(@as(u32, 1), cff2.faceIndex());
    try std.testing.expectEqual(OutlineFormat.cff2, cff2.outlineFormat());
    const axes = try cff2.variationAxes(std.testing.allocator);
    defer std.testing.allocator.free(axes);
    try std.testing.expect(axes.len > 0);
    var cff2_curves = try cff2.extractCurves(
        std.testing.allocator,
        std.testing.allocator,
        try cff2.glyphIndex('S'),
    );
    defer cff2_curves.deinit();
    try std.testing.expect(cff2_curves.curve_count > 0);
    try std.testing.expectError(error.InvalidFaceIndex, Font.initFace(collection, 2));
}

test "TrueType collections use the selected native face" {
    const collection = @import("assets").test_truetype_collection;
    try std.testing.expectEqual(@as(u32, 2), try Font.faceCount(collection));
    var mono = try Font.initFace(collection, 0);
    var serif = try Font.initFace(collection, 1);
    try std.testing.expectEqual(OutlineFormat.truetype, mono.outlineFormat());
    try std.testing.expectEqual(OutlineFormat.truetype, serif.outlineFormat());

    const mono_metrics = try mono.glyphMetrics(try mono.glyphIndex('M'));
    const serif_metrics = try serif.glyphMetrics(try serif.glyphIndex('M'));
    try std.testing.expect(mono_metrics.advance_width != serif_metrics.advance_width);
    var curves = try serif.extractCurves(
        std.testing.allocator,
        std.testing.allocator,
        try serif.glyphIndex('A'),
    );
    defer curves.deinit();
    try std.testing.expect(curves.curve_count > 0);
}

test "extractCurves matches existing curve packing path byte-for-byte" {
    // The producer reuses `buildCurveTexture` and `buildGlyphBandData` from
    // render/format. For a single-glyph input, the produced curve_bytes
    // must equal the prefix of the existing packed curve-texture data.
    const font_data = @import("assets").noto_sans_regular;
    var font = try Font.init(font_data);

    const glyph_id = try font.glyphIndex('M');
    var curves = try font.extractCurves(std.testing.allocator, std.testing.allocator, glyph_id);
    defer curves.deinit();

    // Re-run the same packing through the format helpers directly and
    // compare. (This guards against accidental schema drift in the
    // producer.)
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const glyph = try font.inner.parseGlyph(arena.allocator(), glyph_id);

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
