//! `auto_light` GlyphCurves producer — the CPU-baked path.
//!
//! Analogue of `HintVm.hintGlyph`: given a glyph and a ppem it returns a
//! standard `GlyphCurves` (pixel-space, translate-only render), so it drops
//! straight into the existing hinted text pipeline — same atlas key
//! namespace, same `hintedShapedRunPicture` builder, same shaders. The only
//! difference from the TrueType path is HOW the outline is grid-fitted: this
//! runs the resolution-independent edge analysis + warp instead of the TT
//! bytecode VM, so it works on any outline (incl. unhinted / CFF) uniformly.
//!
//! This is the "validate the look through the real pipeline" path from the
//! de-risking plan. It re-warps per ppem (the analysis is cached, the warp is
//! cheap); the eventual shipping path moves the warp into the shader so no
//! per-ppem curves are baked at all. Same warp math (`warp.zig`), so what you
//! see here is what the shader targets. See [[project_snail]].

const std = @import("std");

const analysis = @import("analysis.zig");
const blue_mod = @import("blue.zig");
const warp = @import("warp.zig");
const outline = @import("../truetype/outline.zig");
const vm = @import("../truetype/vm.zig");
const ttf = @import("../ttf.zig");
const bezier = @import("../../math/bezier.zig");
const curves_mod = @import("../../atlas/curves.zig");
const curve_tex = @import("../../render/format/curve_texture.zig");
const band_tex = @import("../../render/format/band_texture.zig");

const Allocator = std.mem.Allocator;
const Vec2 = @import("../../math/vec.zig").Vec2;
const CurveSegment = bezier.CurveSegment;
const BBox = bezier.BBox;
const GlyphCurves = curves_mod.GlyphCurves;

/// Owns the ppem-independent analysis inputs for one font: the parsed
/// program (outlines) and the derived blue zones. Cheap to keep alongside a
/// font; not thread-safe (mirrors `HintVm`).
pub const AutoLight = struct {
    allocator: Allocator,
    program: vm.Program,
    font: ttf.Font,
    blues: blue_mod.Blues,
    params: analysis.Params = .default,
    /// Blue-assignment tolerance as an em fraction.
    blue_tol_em: f32 = 1.0 / 24.0,
    /// Dominant vertical- and horizontal-stem widths (FUnits), derived once
    /// from reference glyphs so every stem of that weight snaps to the same
    /// pixel width — an even colour instead of mixed 1px/2px stems.
    std_x: f32 = 0,
    std_y: f32 = 0,

    pub fn init(allocator: Allocator, font_data: []const u8) !AutoLight {
        const program = try vm.Program.init(font_data);
        const font = try ttf.Font.init(font_data);
        const blues = try blue_mod.deriveLatin(allocator, &program, &font);
        var self: AutoLight = .{ .allocator = allocator, .program = program, .font = font, .blues = blues };
        self.std_x = self.deriveStandardWidth(.x, "Hnmurbdpq");
        self.std_y = self.deriveStandardWidth(.y, "EFHTLZ");
        return self;
    }

    /// Median stem width (FUnits) along `axis` across reference letters, or 0
    /// if none found. Median is robust to the odd serif/thin stroke.
    fn deriveStandardWidth(self: *AutoLight, axis: analysis.Axis, ref: []const u8) f32 {
        var widths: std.ArrayList(f32) = .empty;
        defer widths.deinit(self.allocator);

        for (ref) |ch| {
            const gid = self.font.glyphIndex(ch) catch continue;
            if (gid == 0) continue;
            var topo = self.program.loadGlyphTopology(self.allocator, gid) catch continue;
            defer topo.deinit();
            const simple = switch (topo) {
                .simple => |s| s,
                else => continue,
            };
            var a = analysis.analyzeGlyph(self.allocator, simple.points, simple.contours, self.font.units_per_em, self.params, axis) catch continue;
            defer a.deinit();
            for (a.edges, 0..) |e, i| {
                if (e.isStem() and e.stem > i) widths.append(self.allocator, e.width) catch {};
            }
        }

        if (widths.items.len == 0) return 0;
        std.mem.sort(f32, widths.items, {}, std.sort.asc(f32));
        return widths.items[widths.items.len / 2];
    }

    pub fn deinit(self: *AutoLight) void {
        self.blues.deinit();
        self.* = undefined;
    }

    /// Produce grid-fitted curves for `glyph_id` at `ppem_26_6` (26.6 px).
    /// `allocator` owns the result; `scratch` holds intermediates. Empty
    /// glyphs return `GlyphCurves.empty`.
    pub fn produce(
        self: *AutoLight,
        allocator: Allocator,
        scratch: Allocator,
        glyph_id: u16,
        ppem_26_6: u32,
    ) !GlyphCurves {
        const ppem_px = @as(f32, @floatFromInt(ppem_26_6)) / 64.0;
        const upm: f32 = @floatFromInt(self.font.units_per_em);
        const px_per_unit = if (upm > 0) ppem_px / upm else 0;

        // Resolve the glyph to a single flat outline: a compound (accented
        // letters like é/ñ, which reference a base glyph + a mark glyph) is
        // composed into one point/contour set; a simple glyph flattens to
        // itself. Analysis and the warp then treat every glyph uniformly.
        var pts: std.ArrayList(outline.Point) = .empty;
        defer pts.deinit(scratch);
        var contours: std.ArrayList(outline.ContourRange) = .empty;
        defer contours.deinit(scratch);
        try flattenGlyph(scratch, &self.program, glyph_id, &pts, &contours, 0);
        if (pts.items.len == 0) return GlyphCurves.empty(allocator);

        // Build the warp knots for both axes. y latches horizontal features
        // onto blue zones; x snaps vertical stems to the grid (no blues — x
        // has no reference heights).
        var y_buf: [warp.max_knots]warp.Knot = undefined;
        var x_buf: [warp.max_knots]warp.Knot = undefined;
        var y_knots: ?[]const warp.Knot = null;
        var x_knots: ?[]const warp.Knot = null;
        {
            var ay = try analysis.analyzeGlyph(scratch, pts.items, contours.items, self.font.units_per_em, self.params, .y);
            defer ay.deinit();
            self.blues.assignEdges(ay.edges, self.blue_tol_em);
            var zbuf: [warp.max_knots]warp.BlueZone = undefined;
            const zones = self.blues.warpZones(&zbuf);
            const ny = warp.buildKnots(ay.edges, zones, px_per_unit, self.std_y, &y_buf);
            if (ny > 0) y_knots = y_buf[0..ny];

            var ax = try analysis.analyzeGlyph(scratch, pts.items, contours.items, self.font.units_per_em, self.params, .x);
            defer ax.deinit();
            const nx = warp.buildKnots(ax.edges, &.{}, px_per_unit, self.std_x, &x_buf);
            if (nx > 0) x_knots = x_buf[0..nx];
        }

        // Flatten every contour to pixel-space segments, warping first.
        var segs: std.ArrayList(CurveSegment) = .empty;
        defer segs.deinit(scratch);
        var bbox = BBox{ .min = .{ .x = 0, .y = 0 }, .max = .{ .x = 0, .y = 0 } };
        var have_bbox = false;

        for (contours.items) |c| {
            if (c.end <= c.start) continue;
            const quads = try outline.contourToCurves(scratch, pts.items[c.start..c.end], 1.0);
            defer scratch.free(quads);
            for (quads) |q| {
                const pq = bezier.QuadBezier{
                    .p0 = warpScale(q.p0, x_knots, y_knots, px_per_unit),
                    .p1 = warpScale(q.p1, x_knots, y_knots, px_per_unit),
                    .p2 = warpScale(q.p2, x_knots, y_knots, px_per_unit),
                };
                accumBBox(&bbox, &have_bbox, pq);
                try segs.append(scratch, CurveSegment.fromQuad(pq));
            }
        }

        if (segs.items.len == 0) return GlyphCurves.empty(allocator);

        const prepared = try curve_tex.prepareGlyphCurvesForDirectEncoding(scratch, segs.items, .zero);
        defer scratch.free(prepared);
        const curve_count: u16 = @intCast(prepared.len);
        const curve_bytes = try curve_tex.encodeDirectSingleGlyphCurves(allocator, prepared);
        errdefer allocator.free(curve_bytes);

        const entry = curve_tex.GlyphCurveEntry{ .start_x = 0, .start_y = 0, .count = curve_count, .offset = 0 };
        const bd = try band_tex.buildGlyphBandDataWithPreparedCurves(
            allocator,
            scratch,
            segs.items,
            segs.items.len,
            bbox,
            entry,
            .zero,
            true,
            prepared,
            null,
        );
        errdefer band_tex.freeGlyphBandData(allocator, @constCast(&bd));

        return .{
            .allocator = allocator,
            .curve_bytes = curve_bytes,
            .band_bytes = bd.data,
            .curve_count = curve_count,
            .h_band_count = bd.h_band_count,
            .v_band_count = bd.v_band_count,
            .band_scale_x = bd.band_scale_x,
            .band_scale_y = bd.band_scale_y,
            .band_offset_x = bd.band_offset_x,
            .band_offset_y = bd.band_offset_y,
            .bbox = bbox,
        };
    }
};

/// Resolve `glyph_id` (simple or compound) into a single flat point/contour
/// set in FUnits, appending to `pts`/`contours`. Compound components are
/// composed recursively with their transform + offset — this is pure geometry
/// (no hinting), just enough to give the analyser a whole outline. Depth is
/// bounded against malformed self-referential fonts.
fn flattenGlyph(
    allocator: Allocator,
    program: *const vm.Program,
    glyph_id: u16,
    pts: *std.ArrayList(outline.Point),
    contours: *std.ArrayList(outline.ContourRange),
    depth: u8,
) !void {
    if (depth > 8) return;
    var topo = try program.loadGlyphTopology(allocator, glyph_id);
    defer topo.deinit();
    switch (topo) {
        .empty => {},
        .simple => |s| try appendSimple(allocator, s, .{}, Vec2.zero, pts, contours),
        .compound => |cmp| {
            for (cmp.components) |comp| {
                // Point-matching components (args are point indices, not x/y)
                // are rare and mostly non-Latin; skip rather than mis-place.
                if (!comp.args_are_xy) continue;
                const raw = Vec2{ .x = @floatFromInt(comp.arg1), .y = @floatFromInt(comp.arg2) };
                try flattenComponent(allocator, program, comp.glyph_id, comp.transform, raw, pts, contours, depth);
            }
        },
    }
}

fn flattenComponent(
    allocator: Allocator,
    program: *const vm.Program,
    glyph_id: u16,
    transform: outline.ComponentTransform,
    offset: Vec2,
    pts: *std.ArrayList(outline.Point),
    contours: *std.ArrayList(outline.ContourRange),
    depth: u8,
) !void {
    if (depth > 8) return;
    var topo = try program.loadGlyphTopology(allocator, glyph_id);
    defer topo.deinit();
    switch (topo) {
        .empty => {},
        .simple => |s| try appendSimple(allocator, s, transform, offset, pts, contours),
        .compound => |cmp| {
            for (cmp.components) |comp| {
                if (!comp.args_are_xy) continue;
                const raw = Vec2{ .x = @floatFromInt(comp.arg1), .y = @floatFromInt(comp.arg2) };
                const child_offset = Vec2.add(offset, transform.apply(raw));
                try flattenComponent(allocator, program, comp.glyph_id, transform.concat(comp.transform), child_offset, pts, contours, depth + 1);
            }
        },
    }
}

fn appendSimple(
    allocator: Allocator,
    s: outline.SimpleGlyph,
    transform: outline.ComponentTransform,
    offset: Vec2,
    pts: *std.ArrayList(outline.Point),
    contours: *std.ArrayList(outline.ContourRange),
) !void {
    const base: u32 = @intCast(pts.items.len);
    for (s.contours) |c| try contours.append(allocator, .{ .start = base + c.start, .end = base + c.end });
    for (s.points) |p| {
        const v = Vec2.add(transform.apply(.{ .x = @floatFromInt(p.x), .y = @floatFromInt(p.y) }), offset);
        try pts.append(allocator, .{
            .x = @intFromFloat(@round(v.x)),
            .y = @intFromFloat(@round(v.y)),
            .on_curve = p.on_curve,
        });
    }
}

fn warpScale(p: Vec2, x_knots: ?[]const warp.Knot, y_knots: ?[]const warp.Knot, px_per_unit: f32) Vec2 {
    const x = if (x_knots) |k| warp.forwardWarp(k, p.x) else p.x;
    const y = if (y_knots) |k| warp.forwardWarp(k, p.y) else p.y;
    return .{ .x = x * px_per_unit, .y = y * px_per_unit };
}

fn accumBBox(bbox: *BBox, have: *bool, q: bezier.QuadBezier) void {
    inline for (.{ q.p0, q.p1, q.p2 }) |p| {
        if (!have.*) {
            bbox.* = .{ .min = p, .max = p };
            have.* = true;
        } else {
            bbox.min = .{ .x = @min(bbox.min.x, p.x), .y = @min(bbox.min.y, p.y) };
            bbox.max = .{ .x = @max(bbox.max.x, p.x), .y = @max(bbox.max.y, p.y) };
        }
    }
}

// ── tests ────────────────────────────────────────────────────────────────

const testing = std.testing;
const assets = @import("assets");

test "auto-light produces non-empty curves that round-trip through an atlas" {
    const atlas_mod = @import("../../atlas.zig");
    const record_key_mod = @import("../../atlas/record_key.zig");

    var al = try AutoLight.init(testing.allocator, assets.dejavu_sans_mono);
    defer al.deinit();

    const ppem_26_6: u32 = 13 * 64;
    const gid = try al.font.glyphIndex('e');

    var curves = try al.produce(testing.allocator, testing.allocator, gid, ppem_26_6);
    defer curves.deinit();

    try testing.expect(curves.curve_count > 0);
    try testing.expect(curves.curve_bytes.len > 0);
    try testing.expect(curves.band_bytes.len > 0);
    try testing.expect(curves.h_band_count > 0);

    var pool = try atlas_mod.PagePool.init(testing.allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    const key = record_key_mod.hintedGlyph(0, gid, ppem_26_6);
    var atlas = try atlas_mod.Atlas.from(testing.allocator, pool, &.{.{ .key = key, .curves = curves }});
    defer atlas.deinit();

    const rec = atlas.lookupRecord(key) orelse return error.MissingRecord;
    try testing.expect(rec.curve_count == curves.curve_count);
}

test "auto-light renders compound (accented) glyphs, not blank" {
    var al = try AutoLight.init(testing.allocator, assets.dejavu_sans_mono);
    defer al.deinit();

    // é/ñ are compound glyphs (base letter + accent). They must flatten and
    // produce curves rather than falling through to empty.
    for ([_]u21{ 0x00E9, 0x00F1 }) |cp| {
        const gid = try al.font.glyphIndex(cp);
        var topo = try al.program.loadGlyphTopology(testing.allocator, gid);
        const is_compound = topo == .compound;
        topo.deinit();
        try testing.expect(is_compound);

        var curves = try al.produce(testing.allocator, testing.allocator, gid, 14 * 64);
        defer curves.deinit();
        // Base letter + accent -> more curves than the bare base 'e' (21).
        try testing.expect(curves.curve_count > 21);
    }
}

test "auto-light derives non-zero standard stem widths" {
    var al = try AutoLight.init(testing.allocator, assets.dejavu_sans_mono);
    defer al.deinit();
    try testing.expect(al.std_x > 0);
    try testing.expect(al.std_y > 0);
}

test "auto-light grid-fits the x-height flat top to a pixel boundary" {
    var al = try AutoLight.init(testing.allocator, assets.dejavu_sans_mono);
    defer al.deinit();

    // At 13px the top of a flat lowercase should sit on (or within a hair
    // of) an integer pixel row once warped. Compare bbox top of 'x'.
    const ppem_26_6: u32 = 13 * 64;
    const gid = try al.font.glyphIndex('x');
    var curves = try al.produce(testing.allocator, testing.allocator, gid, ppem_26_6);
    defer curves.deinit();

    const top_px = curves.bbox.max.y; // pixel space
    const frac = @abs(top_px - @round(top_px));
    try testing.expect(frac < 0.12);
}
