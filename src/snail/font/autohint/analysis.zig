//! Resolution-independent outline analysis for composable autohinting.
//!
//! This is the ppem-INDEPENDENT half of autohinting: it looks at a glyph
//! outline once (in font units) and finds the features a coordinate warp will
//! later snap to the pixel grid — stem edges, and the reference edges that
//! blue zones latch onto. Nothing here depends on the rendering size; the
//! result is cached per glyph and drives the warp at every ppem.
//!
//! Works on either axis (`analyzeGlyph(.., axis)`): `.y` finds horizontal
//! features (baseline/x-height/crossbars/stem tops), `.x` finds vertical
//! stems. Each axis stays a separable, monotone, invertible coordinate warp.
//! A font with no clean stem structure (much non-Latin text) simply yields
//! few/no edges and renders unwarped (identity), which is the non-breaking
//! guarantee. See [[project_snail]].
//!
//! Input is a flattened simple outline (`outline.Point` in FUnits +
//! `ContourRange`); it is outline-format agnostic, so a CFF front-end that
//! produces the same point/contour shape can feed it too.

const std = @import("std");

const bezier = @import("../../math/bezier.zig");
const outline = @import("../truetype/outline.zig");
const vec = @import("../../math/vec.zig");

const Allocator = std.mem.Allocator;
const ContourRange = outline.ContourRange;
const Point = outline.Point;
const QuadBezier = bezier.QuadBezier;
const Vec2 = vec.Vec2;

/// Tuning for feature detection. All distances are em fractions so the
/// analysis is font- and resolution-independent; they are converted to
/// FUnits with `units_per_em` at call time. Defaults are tuned for Latin
/// text but are exposed rather than baked in — pick explicitly per the
/// project's no-magic-thresholds rule. See [[feedback_no_magic_thresholds]].
pub const Params = struct {
    /// A segment is a candidate y-edge when |dy| <= flat_ratio * |dx|. Kept
    /// loose because crossbars/arms legitimately slant a little.
    flat_ratio: f32 = 0.30,
    /// A segment is a candidate x-edge (vertical stem side) when
    /// |dx| <= flat_ratio_x * |dy|. MUCH tighter than the y ratio: a real
    /// stem is near-vertical, whereas diagonal strokes (W, V, A, Λ, ξ, and
    /// many Cyrillic/Greek forms) are ~15-25° off vertical. A loose ratio
    /// mis-reads those diagonals as stems and x-warps them, distorting and
    /// widening the glyph. ~7° keeps genuine stems, drops diagonals.
    flat_ratio_x: f32 = 0.12,
    /// Number of line segments each quadratic is flattened into. Higher
    /// resolves round apexes (overshoots) more precisely at more cost.
    curve_steps: u32 = 8,
    /// Horizontal runs shorter than this (em fraction) are noise, dropped.
    min_len_em: f32 = 1.0 / 64.0,
    /// Segments whose y differ by <= this (em fraction) collapse to one edge.
    merge_em: f32 = 1.0 / 32.0,
    /// Minimum x-overlap (em fraction) to pair two edges into a stem.
    min_overlap_em: f32 = 1.0 / 16.0,
    /// Largest y-gap (em fraction) a real horizontal stem can span.
    max_stem_em: f32 = 0.30,

    pub const default: Params = .{};
};

/// Which axis is being analysed. `.y` finds horizontal edges (constant-y
/// features: baselines, x-height, crossbars, stem tops/bottoms) that a
/// y-warp snaps. `.x` finds vertical edges (the sides of vertical stems)
/// that an x-warp snaps for crisp mono/Latin stems. Same machinery, swapped
/// coordinates.
pub const Axis = enum { y, x };

/// Stable, serializable edge facts produced by outline analysis. Positions and
/// widths are expressed as em fractions by the producer; fitting adds targets
/// later without mutating these facts.
pub const FeatureEdge = struct {
    pos: f32,
    width: f32,
    stem: i16,
    blue: i16,
    flags: packed struct(u16) { round: bool, synthetic_apex: bool = false, _reserved: u14 = 0 },
};

/// A near-axis-aligned run of the outline: a candidate contribution to an
/// edge. Coordinates are stored generically: `pos` is the position along the
/// snapped axis, `min`/`max` the extent along the other axis.
pub const Segment = struct {
    /// y position in FUnits.
    pos: f32,
    /// x extent in FUnits.
    min: f32,
    max: f32,
    /// Travel direction along the contour: +1 rightward, -1 leftward.
    /// Top and bottom edges of a stem traverse in opposite directions
    /// (a winding-agnostic signal used to pair them), so this is how we
    /// tell a stem's two sides apart without a global winding decision.
    dir: i8,
    /// True when this run came from a curved quad (a round apex, e.g. the
    /// top of o/e) rather than a straight edge. Round extremes overshoot
    /// their blue zone; flat ones sit on the reference.
    round: bool,
    /// Analytic zero-span endpoint added only because sampled runs were too
    /// short. It can preserve a blue-adjacent stroke but must keep its natural
    /// width rather than masquerading as a full measured edge.
    synthetic_apex: bool = false,

    fn len(self: Segment) f32 {
        return self.max - self.min;
    }
};

/// A horizontal feature of the glyph: the merged extent of every segment at
/// roughly one height. Sorted ascending by `pos` within a `GlyphAnalysis`.
pub const Edge = struct {
    pos: f32,
    min: f32,
    max: f32,
    dir: i8,
    /// Index of the partner edge this one forms a stem with, or -1. When
    /// set, `width` is the stem thickness in FUnits.
    stem: i16 = -1,
    width: f32 = 0,
    /// Index into the font's blue-zone table this edge latches onto, or -1.
    /// Populated by blue-zone assignment (see blue.zig); consumed by the warp
    /// so the feature snaps to a shared, rounded reference height.
    blue: i16 = -1,
    /// True when the edge is a round apex (overshoots its blue zone) rather
    /// than a flat feature sitting on the reference line.
    round: bool = false,
    /// Apex recovered from an analytic endpoint tangent rather than a sampled
    /// run. Used only as a natural-width companion during fitting.
    synthetic_apex: bool = false,

    pub fn isStem(self: Edge) bool {
        return self.stem >= 0;
    }
};

pub const GlyphAnalysis = struct {
    allocator: Allocator,
    units_per_em: u16,
    /// Horizontal edges, ascending by `pos` (FUnits).
    edges: []Edge,

    pub fn deinit(self: *GlyphAnalysis) void {
        self.allocator.free(self.edges);
        self.* = undefined;
    }

    /// Count of edges that are one side of a detected stem.
    pub fn stemEdgeCount(self: GlyphAnalysis) usize {
        var n: usize = 0;
        for (self.edges) |e| {
            if (e.isStem()) n += 1;
        }
        return n;
    }
};

/// Analyse a glyph's edges along `axis`. `allocator` owns the returned edges;
/// a private arena holds all intermediate work and is freed here.
pub fn analyzeGlyph(
    allocator: Allocator,
    points: []const Point,
    contours: []const ContourRange,
    units_per_em: u16,
    params: Params,
    axis: Axis,
) !GlyphAnalysis {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const em: f32 = @floatFromInt(units_per_em);
    const min_len = params.min_len_em * em;
    const merge_dist = params.merge_em * em;
    const min_overlap = params.min_overlap_em * em;
    const max_stem = params.max_stem_em * em;

    var segments: std.ArrayList(Segment) = .empty;
    for (contours) |c| {
        if (c.end <= c.start) continue;
        try collectContourSegments(arena, points[c.start..c.end], params, units_per_em, min_len, merge_dist, axis, &segments);
    }

    const edges = try mergeSegments(allocator, arena, segments.items, merge_dist);
    errdefer allocator.free(edges);
    linkStems(edges, min_overlap, max_stem);

    return .{ .allocator = allocator, .units_per_em = units_per_em, .edges = edges };
}

/// Emit near-axis-aligned segments of one contour. `contourToCurves` places
/// p1 exactly at the midpoint for straight runs, so a small "bow" flags a
/// genuine curve.
///
/// Straight quads are emitted whole — a stem or crossbar is one straight run,
/// so it stays a single segment rather than being chopped below min_len.
/// Curved quads are handled per axis:
///   - `.y`: subdivided, so a round apex surfaces as a short horizontal run
///     that latches onto a blue zone.
///   - `.x`: SKIPPED entirely. A round bowl's vertical tangent is not a stem;
///     detecting it there would snap the bowl to the grid and distort the
///     curve (lopsided o/e/0). x-hinting only ever acts on straight stems.
fn collectContourSegments(
    arena: Allocator,
    contour_points: []const Point,
    params: Params,
    em_units: u16,
    min_len: f32,
    merge_dist: f32,
    axis: Axis,
    out: *std.ArrayList(Segment),
) !void {
    const curves = try outline.contourToCurves(arena, contour_points, 1.0);
    if (curves.len == 0) return;

    const straight_eps = 1e-3 * @as(f32, @floatFromInt(em_units));

    for (curves) |q| {
        const mid = Vec2.lerp(q.p0, q.p2, 0.5);
        const straight = Vec2.length(Vec2.sub(q.p1, mid)) <= straight_eps;
        const flat_ratio = if (axis == .x) params.flat_ratio_x else params.flat_ratio;
        if (straight) {
            if (segmentFor(q.p0, q.p2, axis, flat_ratio, min_len, false)) |seg| try out.append(arena, seg);
        } else if (axis == .y) {
            var prev = q.p0;
            var step: u32 = 1;
            while (step <= params.curve_steps) : (step += 1) {
                const t = @as(f32, @floatFromInt(step)) / @as(f32, @floatFromInt(params.curve_steps));
                const p = evalQuad(q, t);
                if (segmentFor(prev, p, .y, params.flat_ratio, min_len, true)) |seg| try out.append(arena, seg);
                prev = p;
            }
        }
    }

    if (axis == .y) {
        // Add analytic endpoint tangents only where sampling found no nearby
        // edge. A tight inner curve can turn exactly at an on-curve endpoint
        // while both adjacent sampled runs remain shorter than `min_len`.
        // Avoiding duplicates keeps ordinary sampled edge positions unchanged.
        for (curves, 0..) |incoming, i| {
            const outgoing = curves[(i + 1) % curves.len];
            if (yEndpointExtremumSegment(incoming, outgoing, params.flat_ratio)) |seg| {
                if (!hasNearbySegment(out.items, seg.pos, merge_dist)) try out.append(arena, seg);
            }
        }
    }
}

fn hasNearbySegment(segments: []const Segment, pos: f32, tolerance: f32) bool {
    for (segments) |segment| {
        if (@abs(segment.pos - pos) <= tolerance) return true;
    }
    return false;
}

/// Classify a polyline edge as a near-axis-aligned segment, or null. For `.y`
/// the run must be near-horizontal (small dy over a long dx); for `.x`
/// near-vertical. The travel sign along the extent axis becomes `dir`.
fn segmentFor(a: Vec2, b: Vec2, axis: Axis, flat_ratio: f32, min_len: f32, round: bool) ?Segment {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    switch (axis) {
        .y => {
            const run = @abs(dx);
            if (run < min_len or @abs(dy) > flat_ratio * run) return null;
            return .{ .pos = (a.y + b.y) * 0.5, .min = @min(a.x, b.x), .max = @max(a.x, b.x), .dir = if (dx >= 0) 1 else -1, .round = round };
        },
        .x => {
            const run = @abs(dy);
            if (run < min_len or @abs(dx) > flat_ratio * run) return null;
            return .{ .pos = (a.x + b.x) * 0.5, .min = @min(a.y, b.y), .max = @max(a.y, b.y), .dir = if (dy >= 0) 1 else -1, .round = round };
        },
    }
}

fn evalQuad(q: QuadBezier, t: f32) Vec2 {
    const mt = 1.0 - t;
    const w0 = mt * mt;
    const w1 = 2.0 * mt * t;
    const w2 = t * t;
    return .{
        .x = w0 * q.p0.x + w1 * q.p1.x + w2 * q.p2.x,
        .y = w0 * q.p0.y + w1 * q.p1.y + w2 * q.p2.y,
    };
}

fn yEndpointExtremumSegment(incoming: QuadBezier, outgoing: QuadBezier, flat_ratio: f32) ?Segment {
    const point = incoming.p2;
    if (Vec2.length(Vec2.sub(point, outgoing.p0)) > 1e-4) return null;

    const in_tangent = Vec2.sub(point, incoming.p1);
    const out_tangent = Vec2.sub(outgoing.p1, point);
    if (@abs(in_tangent.x) <= 1e-6 or @abs(out_tangent.x) <= 1e-6 or
        @abs(in_tangent.y) > flat_ratio * @abs(in_tangent.x) or
        @abs(out_tangent.y) > flat_ratio * @abs(out_tangent.x)) return null;

    const before = incoming.p0.y;
    const after = outgoing.p2.y;
    const is_max = point.y >= before and point.y >= after and (point.y > before or point.y > after);
    const is_min = point.y <= before and point.y <= after and (point.y < before or point.y < after);
    if (!is_max and !is_min) return null;

    return .{
        .pos = point.y,
        .min = point.x,
        .max = point.x,
        .dir = if (in_tangent.x >= 0) 1 else -1,
        .round = true,
        .synthetic_apex = true,
    };
}

const Cluster = struct {
    weighted_pos: f32 = 0,
    weight: f32 = 0,
    min: f32 = std.math.inf(f32),
    max: f32 = -std.math.inf(f32),
    dir_len: [2]f32 = .{ 0, 0 }, // signed direction vote by length: [-1, +1]
    round_len: f32 = 0, // length that came from curved (round) runs
    synthetic_len: f32 = 0,

    fn add(self: *Cluster, s: Segment) void {
        const w = @max(s.len(), 1.0);
        self.weighted_pos += s.pos * w;
        self.weight += w;
        self.min = @min(self.min, s.min);
        self.max = @max(self.max, s.max);
        self.dir_len[if (s.dir >= 0) 1 else 0] += w;
        if (s.round) self.round_len += w;
        if (s.synthetic_apex) self.synthetic_len += w;
    }

    fn finish(self: Cluster) Edge {
        return .{
            .pos = self.weighted_pos / @max(self.weight, 1.0),
            .min = self.min,
            .max = self.max,
            .dir = if (self.dir_len[1] >= self.dir_len[0]) 1 else -1,
            .round = self.round_len * 2.0 >= self.weight, // majority round
            .synthetic_apex = self.synthetic_len * 2.0 >= self.weight,
        };
    }
};

/// Cluster segments at ~equal height into edges. Segments are sorted by y and
/// swept: any within `merge_dist` of the running cluster mean join it.
fn mergeSegments(
    allocator: Allocator,
    arena: Allocator,
    segments: []Segment,
    merge_dist: f32,
) ![]Edge {
    if (segments.len == 0) return allocator.alloc(Edge, 0);

    std.mem.sort(Segment, segments, {}, struct {
        fn lt(_: void, a: Segment, b: Segment) bool {
            return a.pos < b.pos;
        }
    }.lt);

    var edges: std.ArrayList(Edge) = .empty;
    defer edges.deinit(arena);

    var cluster: Cluster = .{};
    cluster.add(segments[0]);
    for (segments[1..]) |s| {
        const mean = cluster.weighted_pos / @max(cluster.weight, 1.0);
        if (s.pos - mean <= merge_dist) {
            cluster.add(s);
        } else {
            try edges.append(arena, cluster.finish());
            cluster = .{};
            cluster.add(s);
        }
    }
    try edges.append(arena, cluster.finish());

    return allocator.dupe(Edge, edges.items);
}

/// Pair edges into stems: opposite travel directions, overlapping x, and a
/// y-gap within stem range. Each edge takes its nearest valid partner.
/// Pair edges into stems, **smallest gap first**. A per-edge nearest search is
/// order-dependent and lets a wide span (a digit's serif/flag, e.g. `1`) grab
/// a stem's edge before the real, tighter stem can claim it. Assigning the
/// globally smallest valid gap each round makes genuine stems win. n is small
/// (< max_knots edges per glyph), so the O(n³) sweep is free.
fn linkStems(edges: []Edge, min_overlap: f32, max_stem: f32) void {
    while (true) {
        var best_gap: f32 = max_stem + 1.0;
        var best_lo: ?usize = null;
        var best_hi: usize = 0;
        for (edges, 0..) |a, i| {
            if (a.isStem()) continue;
            for (edges[i + 1 ..], i + 1..) |b, j| {
                if (b.isStem()) continue;
                if (a.dir == b.dir) continue;
                const gap = b.pos - a.pos;
                if (gap <= 0 or gap > max_stem) continue;
                if (overlap(a, b) < min_overlap) continue;
                if (gap < best_gap) {
                    best_gap = gap;
                    best_lo = i;
                    best_hi = j;
                }
            }
        }
        const lo = best_lo orelse break;
        edges[lo].stem = @intCast(best_hi);
        edges[lo].width = best_gap;
        edges[best_hi].stem = @intCast(lo);
        edges[best_hi].width = best_gap;
    }
}

fn overlap(a: Edge, b: Edge) f32 {
    return @min(a.max, b.max) - @max(a.min, b.min);
}

// ── tests ────────────────────────────────────────────────────────────────

const testing = std.testing;
const assets = @import("assets");
const Program = @import("../truetype/vm.zig").Program;
const Font = @import("../ttf.zig").Font;

const TestGlyph = struct {
    topology: @import("../truetype/vm.zig").GlyphTopology,

    fn deinit(self: *TestGlyph) void {
        self.topology.deinit();
    }
};

fn analyzeChar(allocator: Allocator, program: *const Program, font: *const Font, ch: u21) !GlyphAnalysis {
    const gid = try font.glyphIndex(ch);
    var topo = try program.loadGlyphTopology(allocator, gid);
    defer topo.deinit();
    const simple = switch (topo) {
        .simple => |s| s,
        else => return error.NotSimpleGlyph,
    };
    return analyzeGlyph(allocator, simple.points, simple.contours, font.units_per_em, .default, .y);
}

test "analytic endpoint extremum recovers an undersampled inner apex" {
    const incoming: QuadBezier = .{
        .p0 = .{ .x = 0, .y = 0 },
        .p1 = .{ .x = 1, .y = 1 },
        .p2 = .{ .x = 2, .y = 1 },
    };
    const outgoing: QuadBezier = .{
        .p0 = .{ .x = 2, .y = 1 },
        .p1 = .{ .x = 3, .y = 1 },
        .p2 = .{ .x = 4, .y = 0 },
    };
    const apex = yEndpointExtremumSegment(incoming, outgoing, 0.3).?;
    try testing.expect(apex.round);
    try testing.expect(apex.synthetic_apex);
    try testing.expectApproxEqAbs(@as(f32, 1), apex.pos, 1e-6);
}

test "analyze detects baseline and cap edges of H" {
    const program = try Program.init(assets.noto_sans_regular);
    const font = try Font.init(assets.noto_sans_regular);

    var a = try analyzeChar(testing.allocator, &program, &font, 'H');
    defer a.deinit();

    const em: f32 = @floatFromInt(a.units_per_em);
    try testing.expect(a.edges.len >= 3);

    // Lowest edge sits on the baseline (~0), highest near cap height.
    try testing.expect(@abs(a.edges[0].pos) < 0.10 * em);
    try testing.expect(a.edges[a.edges.len - 1].pos > 0.55 * em);

    // H has exactly one horizontal crossbar -> at least one stem pair.
    try testing.expect(a.stemEdgeCount() >= 2);
}

test "analyze finds three crossbars of E" {
    const program = try Program.init(assets.noto_sans_regular);
    const font = try Font.init(assets.noto_sans_regular);

    var a = try analyzeChar(testing.allocator, &program, &font, 'E');
    defer a.deinit();

    // Top arm, middle arm, bottom arm — three horizontal stems.
    try testing.expect(a.stemEdgeCount() >= 6);
}

test "analyze o spans baseline to x-height with overshoot" {
    const program = try Program.init(assets.noto_sans_regular);
    const font = try Font.init(assets.noto_sans_regular);

    var a = try analyzeChar(testing.allocator, &program, &font, 'o');
    defer a.deinit();

    const em: f32 = @floatFromInt(a.units_per_em);
    try testing.expect(a.edges.len >= 2);
    // Round top/bottom apexes are caught as short horizontal runs.
    try testing.expect(a.edges[0].pos < 0.10 * em); // bottom near/below baseline
    try testing.expect(a.edges[a.edges.len - 1].pos > 0.40 * em); // top near x-height
}

test "analyze x-axis finds the two vertical stems of H" {
    const program = try Program.init(assets.noto_sans_regular);
    const font = try Font.init(assets.noto_sans_regular);

    const gid = try font.glyphIndex('H');
    var topo = try program.loadGlyphTopology(testing.allocator, gid);
    defer topo.deinit();
    const simple = switch (topo) {
        .simple => |s| s,
        else => return error.NotSimpleGlyph,
    };

    var a = try analyzeGlyph(testing.allocator, simple.points, simple.contours, font.units_per_em, .default, .x);
    defer a.deinit();

    // Two vertical stems (left + right uprights) -> two stem pairs.
    try testing.expect(a.stemEdgeCount() >= 4);
}

test "edges are sorted ascending" {
    const program = try Program.init(assets.noto_sans_regular);
    const font = try Font.init(assets.noto_sans_regular);

    var a = try analyzeChar(testing.allocator, &program, &font, 'B');
    defer a.deinit();

    for (1..a.edges.len) |i| {
        try testing.expect(a.edges[i - 1].pos <= a.edges[i].pos);
    }
}
