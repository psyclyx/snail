//! PPEM-independent autohint feature producer.
//!
//! `AutohintAnalyzer` flattens each outline and emits stable, em-normalized
//! edge facts. Pixel-size and policy-specific fitting happens later; this
//! module retains no fitted targets. A private knot adapter remains only for
//! parity coverage while pre-feature-record callers migrate.

const std = @import("std");

const analysis = @import("analysis.zig");
const blue_mod = @import("blue.zig");
const warp = @import("warp.zig");
const outline = @import("../truetype/outline.zig");
const vm = @import("../truetype/vm.zig");
const ttf = @import("../ttf.zig");

const Allocator = std.mem.Allocator;
const Vec2 = @import("../../math/vec.zig").Vec2;

/// Owns the ppem-independent analysis inputs for one font: the parsed
/// program (outlines) and the derived blue zones. Cheap to keep alongside a
/// font; not thread-safe (mirrors `HintVm`).
pub const FeatureEdge = analysis.FeatureEdge;

pub const GlyphFeatures = struct {
    x: []const FeatureEdge,
    y: []const FeatureEdge,
    left: f32,
};

pub const FontFeatures = struct {
    blues: []const blue_mod.FeatureZone,
    std_x: f32,
    std_y: f32,
};

pub const AutohintAnalyzer = struct {
    allocator: Allocator,
    program: vm.Program,
    font: ttf.Font,
    blues: blue_mod.Blues,
    normalized_blues: []blue_mod.FeatureZone,
    params: analysis.Params = .default,
    blue_tol_em: f32 = 1.0 / 24.0,
    std_x: f32 = 0,
    std_y: f32 = 0,

    pub fn init(allocator: Allocator, font_data: []const u8) !AutohintAnalyzer {
        const program = try vm.Program.init(font_data);
        const font = try ttf.Font.init(font_data);
        var blues = try blue_mod.deriveLatin(allocator, &program, &font, .{});
        errdefer blues.deinit();
        var self: AutohintAnalyzer = .{
            .allocator = allocator,
            .program = program,
            .font = font,
            .blues = blues,
            .normalized_blues = &.{},
        };
        self.std_x = self.deriveStandardWidth(.x, "Hnmurbdpq");
        self.std_y = self.deriveStandardWidth(.y, "EFHTLZ");
        self.normalized_blues = try self.blues.normalized(allocator);
        return self;
    }

    fn deriveStandardWidth(self: *AutohintAnalyzer, axis: analysis.Axis, ref: []const u8) f32 {
        var widths: std.ArrayList(f32) = .empty;
        defer widths.deinit(self.allocator);
        for (ref) |ch| {
            const gid = self.font.glyphIndex(ch) catch continue;
            if (gid == 0) continue;
            var topo = self.program.loadGlyphTopology(self.allocator, gid) catch continue;
            defer topo.deinit();
            const simple = switch (topo) {
                .simple => |simple| simple,
                else => continue,
            };
            var result = analysis.analyzeGlyph(self.allocator, simple.points, simple.contours, self.font.units_per_em, self.params, axis) catch continue;
            defer result.deinit();
            for (result.edges, 0..) |edge, i| {
                if (edge.isStem() and edge.stem > i) widths.append(self.allocator, edge.width) catch {};
            }
        }
        if (widths.items.len == 0) return 0;
        std.mem.sort(f32, widths.items, {}, std.sort.asc(f32));
        return widths.items[widths.items.len / 2];
    }

    pub fn deinit(self: *AutohintAnalyzer) void {
        self.allocator.free(self.normalized_blues);
        self.blues.deinit();
        self.* = undefined;
    }

    pub fn fontFeatures(self: *const AutohintAnalyzer) FontFeatures {
        const upm: f32 = @floatFromInt(self.font.units_per_em);
        return .{
            .blues = self.normalized_blues,
            .std_x = self.std_x / upm,
            .std_y = self.std_y / upm,
        };
    }

    /// Analyze a glyph once into immutable, em-normalized edge facts.
    pub fn analyzeGlyph(
        self: *AutohintAnalyzer,
        scratch: Allocator,
        glyph_id: u16,
        x_buf: []FeatureEdge,
        y_buf: []FeatureEdge,
    ) !GlyphFeatures {
        var pts: std.ArrayList(outline.Point) = .empty;
        defer pts.deinit(scratch);
        var contours: std.ArrayList(outline.ContourRange) = .empty;
        defer contours.deinit(scratch);
        try flattenGlyph(scratch, &self.program, glyph_id, &pts, &contours, 0);

        const upm: f32 = @floatFromInt(self.font.units_per_em);
        if (pts.items.len == 0 or upm <= 0) return .{ .x = x_buf[0..0], .y = y_buf[0..0], .left = 0 };

        var min_x: f32 = std.math.inf(f32);
        for (pts.items) |point| min_x = @min(min_x, @as(f32, @floatFromInt(point.x)));

        var y_analysis = try analysis.analyzeGlyph(scratch, pts.items, contours.items, self.font.units_per_em, self.params, .y);
        defer y_analysis.deinit();
        self.blues.assignEdges(y_analysis.edges, self.blue_tol_em);
        const y = convertEdges(y_analysis.edges, upm, y_buf);

        var x_analysis = try analysis.analyzeGlyph(scratch, pts.items, contours.items, self.font.units_per_em, self.params, .x);
        defer x_analysis.deinit();
        const x = convertEdges(x_analysis.edges, upm, x_buf);

        return .{ .x = x, .y = y, .left = min_x / upm };
    }

    /// Test-only migration bridge. This is deliberately private so the
    /// root-exported producer API cannot produce per-PPEM results.
    fn legacyGlyphKnots(
        self: *AutohintAnalyzer,
        scratch: Allocator,
        glyph_id: u16,
        ppem_26_6: u32,
        x_buf: []warp.Knot,
        y_buf: []warp.Knot,
    ) !AxisKnots {
        var x_features: [warp.max_knots]FeatureEdge = undefined;
        var y_features: [warp.max_knots]FeatureEdge = undefined;
        const glyph = try self.analyzeGlyph(scratch, glyph_id, &x_features, &y_features);
        const ppem = @as(f32, @floatFromInt(ppem_26_6)) / 64.0;
        const font_features = self.fontFeatures();

        var x_edges: [warp.max_knots]analysis.Edge = undefined;
        var y_edges: [warp.max_knots]analysis.Edge = undefined;
        featureEdgesForFitter(glyph.x, font_features.blues, &x_edges);
        featureEdgesForFitter(glyph.y, font_features.blues, &y_edges);
        var zones: [warp.max_knots]warp.BlueZone = undefined;
        for (font_features.blues, 0..) |zone, i| zones[i] = .{ .ref = zone.ref, .shoot = zone.shoot };

        const nx = warp.buildKnotsReg(x_edges[0..glyph.x.len], &.{}, ppem, font_features.std_x, .{
            .full_stem_hint = true,
            .anchor_stem_positions = true,
        }, glyph.left, x_buf);
        const ny = warp.buildKnots(y_edges[0..glyph.y.len], zones[0..font_features.blues.len], ppem, font_features.std_y, .{}, y_buf);
        return .{ .x = x_buf[0..nx], .y = y_buf[0..ny] };
    }
};

const AxisKnots = struct {
    x: []const warp.Knot,
    y: []const warp.Knot,
};

fn convertEdges(edges: []const analysis.Edge, upm: f32, out: []FeatureEdge) []const FeatureEdge {
    if (edges.len > warp.max_knots or edges.len > out.len) return out[0..0];
    for (edges, out[0..edges.len]) |edge, *feature| {
        feature.* = .{
            .pos = edge.pos / upm,
            .width = edge.width / upm,
            .stem = edge.stem,
            .blue = edge.blue,
            .flags = .{ .round = edge.round },
        };
    }
    return out[0..edges.len];
}

fn featureEdgesForFitter(features: []const FeatureEdge, zones: []const blue_mod.FeatureZone, out: []analysis.Edge) void {
    for (features, out[0..features.len]) |feature, *edge| {
        const partner_above = feature.stem >= 0 and @as(usize, @intCast(feature.stem)) < features.len and
            features[@intCast(feature.stem)].pos > feature.pos;
        // A blue zone's overshoot is outside its reference: below for bottom
        // zones and above for top zones. This preserves the transient edge
        // direction needed by the old round-apex companion heuristic without
        // adding direction to the stable feature record.
        const bottom_blue = feature.blue >= 0 and @as(usize, @intCast(feature.blue)) < zones.len and
            zones[@intCast(feature.blue)].shoot < zones[@intCast(feature.blue)].ref;
        var companion_dir: i2 = 1;
        if (feature.stem < 0 and feature.blue < 0) {
            var nearest_gap = std.math.inf(f32);
            for (features) |candidate| {
                if (candidate.blue < 0 or @as(usize, @intCast(candidate.blue)) >= zones.len) continue;
                const gap = @abs(candidate.pos - feature.pos);
                if (gap >= nearest_gap) continue;
                nearest_gap = gap;
                const candidate_is_bottom = zones[@intCast(candidate.blue)].shoot < zones[@intCast(candidate.blue)].ref;
                companion_dir = if (candidate_is_bottom) 1 else -1;
            }
        }
        edge.* = .{
            .pos = feature.pos,
            .min = 0,
            .max = 0,
            .dir = if (partner_above or bottom_blue) -1 else companion_dir,
            .stem = feature.stem,
            .width = feature.width,
            .blue = feature.blue,
            .round = feature.flags.round,
        };
    }
}

fn directGlyphKnotsForTest(
    self: *AutohintAnalyzer,
    scratch: Allocator,
    glyph_id: u16,
    ppem_26_6: u32,
    x_buf: []warp.Knot,
    y_buf: []warp.Knot,
) !AxisKnots {
    var pts: std.ArrayList(outline.Point) = .empty;
    defer pts.deinit(scratch);
    var contours: std.ArrayList(outline.ContourRange) = .empty;
    defer contours.deinit(scratch);
    try flattenGlyph(scratch, &self.program, glyph_id, &pts, &contours, 0);

    const upm: f32 = @floatFromInt(self.font.units_per_em);
    if (pts.items.len == 0 or upm <= 0) return .{ .x = x_buf[0..0], .y = y_buf[0..0] };
    const px_per_unit = (@as(f32, @floatFromInt(ppem_26_6)) / 64.0) / upm;

    var ay = try analysis.analyzeGlyph(scratch, pts.items, contours.items, self.font.units_per_em, self.params, .y);
    defer ay.deinit();
    self.blues.assignEdges(ay.edges, self.blue_tol_em);
    var zones: [warp.max_knots]warp.BlueZone = undefined;
    const ny = warp.buildKnots(ay.edges, self.blues.warpZones(&zones), px_per_unit, self.std_y, .{}, y_buf);

    var ax = try analysis.analyzeGlyph(scratch, pts.items, contours.items, self.font.units_per_em, self.params, .x);
    defer ax.deinit();
    var min_x: f32 = std.math.inf(f32);
    for (pts.items) |point| min_x = @min(min_x, @as(f32, @floatFromInt(point.x)));
    const nx = warp.buildKnotsReg(ax.edges, &.{}, px_per_unit, self.std_x, .{
        .full_stem_hint = true,
        .anchor_stem_positions = true,
    }, min_x, x_buf);
    for (x_buf[0..nx]) |*knot| {
        knot.base /= upm;
        knot.target /= upm;
    }
    for (y_buf[0..ny]) |*knot| {
        knot.base /= upm;
        knot.target /= upm;
    }
    return .{ .x = x_buf[0..nx], .y = y_buf[0..ny] };
}

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

// ── tests ────────────────────────────────────────────────────────────────

const testing = std.testing;
const assets = @import("assets");

test "glyph analysis contains features but no fitted targets" {
    const test_font = assets.dejavu_sans_mono;
    var analyzer = try AutohintAnalyzer.init(testing.allocator, test_font);
    defer analyzer.deinit();
    const glyph_h = try analyzer.font.glyphIndex('H');
    var xb: [warp.max_knots]FeatureEdge = undefined;
    var yb: [warp.max_knots]FeatureEdge = undefined;
    const a = try analyzer.analyzeGlyph(testing.allocator, glyph_h, &xb, &yb);
    try testing.expect(a.x.len > 0);
    try testing.expect(a.y.len > 0);
    try testing.expect(@hasField(FeatureEdge, "pos"));
    try testing.expect(!@hasField(FeatureEdge, "target"));
}

test "font analysis is normalized once" {
    var analyzer = try AutohintAnalyzer.init(testing.allocator, assets.dejavu_sans_mono);
    defer analyzer.deinit();
    const features = analyzer.fontFeatures();
    try testing.expect(features.blues.len > 0);
    try testing.expect(features.std_x > 0 and features.std_x < 1);
    try testing.expect(features.std_y > 0 and features.std_y < 1);
    for (features.blues) |zone| {
        try testing.expect(@abs(zone.ref) < 2);
        try testing.expect(@abs(zone.shoot) < 2);
    }
}

test "repeated analysis has one result independent of size" {
    const test_font = assets.dejavu_sans_mono;
    var analyzer = try AutohintAnalyzer.init(testing.allocator, test_font);
    defer analyzer.deinit();
    const glyph_h = try analyzer.font.glyphIndex('H');
    var xb: [warp.max_knots]FeatureEdge = undefined;
    var yb: [warp.max_knots]FeatureEdge = undefined;
    var xb2: [warp.max_knots]FeatureEdge = undefined;
    var yb2: [warp.max_knots]FeatureEdge = undefined;
    const a = try analyzer.analyzeGlyph(testing.allocator, glyph_h, &xb, &yb);
    const b = try analyzer.analyzeGlyph(testing.allocator, glyph_h, &xb2, &yb2);
    try testing.expectEqualSlices(FeatureEdge, a.x, b.x);
    try testing.expectEqualSlices(FeatureEdge, a.y, b.y);
}

test "private legacy fitting preserves round bottom direction" {
    var analyzer = try AutohintAnalyzer.init(testing.allocator, assets.dejavu_sans_mono);
    defer analyzer.deinit();
    const glyph_o = try analyzer.font.glyphIndex('o');

    var feature_x: [warp.max_knots]FeatureEdge = undefined;
    var feature_y: [warp.max_knots]FeatureEdge = undefined;
    const glyph = try analyzer.analyzeGlyph(testing.allocator, glyph_o, &feature_x, &feature_y);
    const zones = analyzer.fontFeatures().blues;
    var saw_round_bottom = false;
    for (glyph.y) |edge| {
        if (edge.flags.round and edge.blue >= 0 and zones[@intCast(edge.blue)].shoot < zones[@intCast(edge.blue)].ref) {
            saw_round_bottom = true;
        }
    }
    try testing.expect(saw_round_bottom);

    for ([_]u32{ 9, 12, 16, 28 }) |ppem| {
        var legacy_x: [warp.max_knots]warp.Knot = undefined;
        var legacy_y: [warp.max_knots]warp.Knot = undefined;
        var direct_x: [warp.max_knots]warp.Knot = undefined;
        var direct_y: [warp.max_knots]warp.Knot = undefined;
        const legacy = try analyzer.legacyGlyphKnots(testing.allocator, glyph_o, ppem * 64, &legacy_x, &legacy_y);
        const direct = try directGlyphKnotsForTest(&analyzer, testing.allocator, glyph_o, ppem * 64, &direct_x, &direct_y);
        try testing.expectEqual(direct.x.len, legacy.x.len);
        try testing.expectEqual(direct.y.len, legacy.y.len);
        for (direct.x, legacy.x) |expected, actual| {
            try testing.expectApproxEqAbs(expected.base, actual.base, 0.000001);
            try testing.expectApproxEqAbs(expected.target, actual.target, 0.000001);
        }
        for (direct.y, legacy.y) |expected, actual| {
            try testing.expectApproxEqAbs(expected.base, actual.base, 0.000001);
            try testing.expectApproxEqAbs(expected.target, actual.target, 0.000001);
        }
    }
}
