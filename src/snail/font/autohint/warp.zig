//! The `auto_light` coordinate warp: turns ppem-independent edge analysis
//! into a per-ppem, separable, monotone piecewise-linear map along the
//! y-axis, and inverts it for shader-side sampling.
//!
//! This is the single source of truth for the grid-fit math. The CPU
//! renderer calls it directly; the GLSL shader ports `inverseWarp` verbatim
//! (parity is asserted by tests). Everything is expressed in the caller's
//! position unit (FUnits in practice) with `px_per_unit` carrying the ppem —
//! so the module itself is scale-agnostic and has no per-ppem state.
//!
//! Forward warp f: base_y -> hinted_y snaps edges to the pixel grid and
//! quantises stem widths to whole pixels (min 1). The renderer needs the
//! INVERSE: given a hinted-space sample it recovers the base-outline
//! coordinate to query, plus the local inverse slope used to rescale the
//! anti-aliasing footprint (epp_base = epp_screen * inv_slope). Because the
//! map is monotone the inverse is well defined; because it's separable it
//! composes with the existing base-space coverage evaluator untouched.
//! See [[project_snail]].

const std = @import("std");

const analysis = @import("analysis.zig");
const Edge = analysis.Edge;

/// Upper bound on edges fed to the warp. Glyphs with more horizontal
/// features than this (dense CJK, ornate display faces) fall back to the
/// identity warp — they render exactly as they do unhinted, which is the
/// "don't break non-Latin" guarantee. Kept in lockstep with the shader's
/// fixed array size.
pub const max_knots: usize = 32;

/// One (base, target) control point of the warp, in the caller's unit.
pub const Knot = struct {
    /// Position on the base outline.
    base: f32,
    /// Grid-fitted position it maps to.
    target: f32,
};

/// A font-global reference height (baseline, x-height, cap-height, …) that
/// edges latch onto so the same feature lands identically across glyphs.
pub const BlueZone = struct {
    /// Flat reference position (FUnits) — where flat features (x/z/H) sit.
    ref: f32,
    /// Overshoot position (FUnits) — where round features (o/e/O) reach.
    /// Equal to `ref` when the zone has no round samples.
    shoot: f32,
};

/// Result of an inverse-warp query at one hinted-space coordinate.
pub const Sample = struct {
    /// Coordinate to sample on the base outline.
    base: f32,
    /// d(base)/d(hinted) local slope — multiply the screen AA footprint by
    /// this to get the footprint in base space. <1 near a snapped edge
    /// (space compresses -> sharper), which is the mechanism of crispness.
    inv_slope: f32,
};

/// Tuning for the grid-fit warp. Like `analysis.Params`, these heuristic
/// thresholds are exposed rather than baked in — pick explicitly per the
/// project's no-magic-thresholds rule. See [[feedback_no_magic_thresholds]].
pub const Params = struct {
    /// Fraction of the standard width within which a stem is considered "the
    /// same weight" and pulled to it. Wide enough to unify normal-weight
    /// stems, tight enough to leave genuinely bold/thin strokes on their own
    /// measured width.
    std_snap_ratio: f32 = 0.4,
    /// Below this scaled overshoot (px), round apexes collapse onto the flat
    /// reference — at small ppem a fractional-pixel overshoot just blurs the
    /// line and makes round glyphs look mis-aligned, so it's suppressed. Above
    /// it the overshoot is kept (optically correct at larger sizes).
    overshoot_min_px: f32 = 0.5,
    /// A stem is width-hinted (snapped to a whole pixel) only while its natural
    /// width is below this many pixels. Below ~here a 1px snap sharpens thin
    /// stems where AA can't; above it, snapping just over/under-thickens the
    /// stem relative to the glyph's curves, so we leave it natural. This is
    /// what makes hinting a small-size tool — it tapers off as the glyph grows.
    /// Ignored when `full_stem_hint` is set.
    stem_hint_max_px: f32 = 1.6,
    /// Width-hint EVERY stem to a whole pixel, ignoring `stem_hint_max_px`.
    /// Crisper and heavier — matches TrueType's "all stems on solid pixels".
    /// Used for the x-axis, where vertical-stem sharpness is the whole point;
    /// the y-axis stays light (thick horizontals keep natural weight).
    full_stem_hint: bool = false,
    /// Position stems RELATIVE to the first (leftmost) stem by rounding their
    /// inter-stem distance once, instead of snapping each stem's edge to the
    /// grid independently. Independent snapping double-rounds the two ends of a
    /// counter and can drift a glyph's width by a pixel (e.g. 'H' coming out a
    /// column narrow); anchoring preserves the designed proportions. For the
    /// blue-less axis (x) — assumes no blue-linked stems.
    anchor_stem_positions: bool = false,

    pub const default: Params = .{};
};

fn snap(v: f32, px_per_unit: f32) f32 {
    if (px_per_unit <= 0) return v;
    return @round(v * px_per_unit) / px_per_unit;
}

fn standardizeWidth(raw: f32, std_width: f32, std_snap_ratio: f32) f32 {
    if (std_width > 0 and @abs(raw - std_width) <= std_snap_ratio * std_width) return std_width;
    return raw;
}

/// Grid-fitted target for one edge: its own snapped position, or — when
/// blue-linked — the shared fitted reference, plus the overshoot when the
/// edge is a round apex and the overshoot survives the small-size cut-off.
fn blueTarget(e: Edge, blues: []const BlueZone, px_per_unit: f32, overshoot_min_px: f32) f32 {
    if (e.blue < 0 or @as(usize, @intCast(e.blue)) >= blues.len) return snap(e.pos, px_per_unit);
    const b = blues[@intCast(e.blue)];
    const ref_fit = snap(b.ref, px_per_unit);
    const overshoot = b.shoot - b.ref; // signed FUnits (tops +, bottoms -)
    if (e.round and @abs(overshoot * px_per_unit) >= overshoot_min_px) {
        return ref_fit + overshoot;
    }
    return ref_fit;
}

/// Build the forward-warp knots for a glyph at a given size. Returns the
/// knot count (0 if the glyph has no usable edges or exceeds `max_knots`,
/// signalling "render unwarped"). `out` must hold at least `max_knots`.
///
/// Knots come out sorted ascending in both `base` and `target` (the map is
/// monotone), which is what `inverseWarp` relies on.
pub fn buildKnots(
    edges: []const Edge,
    blues: []const BlueZone,
    px_per_unit: f32,
    std_width: f32,
    params: Params,
    out: []Knot,
) usize {
    return buildKnotsReg(edges, blues, px_per_unit, std_width, params, std.math.nan(f32), out);
}

/// `buildKnots` plus a left-edge registration for the blue-less axis (x).
///
/// Flat-left letters (H/m/b) snap their left STEM to the grid, but round-left
/// letters (a/c/e/o/g) have a curved bowl there — and curves aren't stem-hinted,
/// so the bowl stays at its sub-pixel spot while the flats march to the grid,
/// leaving the round a pixel out of the column (the "a pokes left" artefact).
/// When `left_edge` (the glyph's leftmost outline coordinate, caller's units)
/// sits clearly left of the leftmost snapped knot — i.e. there's a bowl, not a
/// stem, on the left — register it as its OWN knot so the bowl snaps to the grid
/// like a stem would. The stem knots are untouched (still crisp); only the soft
/// bowl reflows by a sub-pixel. `NaN` disables it (the plain `buildKnots` path).
pub fn buildKnotsReg(
    edges: []const Edge,
    blues: []const BlueZone,
    px_per_unit: f32,
    /// Font's dominant stem width for this axis (FUnits, 0 = disabled). Stems
    /// within `params.std_snap_ratio` of it snap to a single shared pixel width
    /// so the whole run reads as one even weight instead of some stems rounding
    /// to 1px and others to 2px.
    std_width: f32,
    /// Heuristic thresholds for the grid-fit (`.{}` = tuned Latin defaults).
    params: Params,
    left_edge: f32,
    out: []Knot,
) usize {
    const n = edges.len;
    if (n == 0 or n > max_knots or n > out.len) return 0;

    const grid = if (px_per_unit > 0) 1.0 / px_per_unit else 1.0;

    // Pass 1 — target per edge. Blue-linked edges snap to the SHARED rounded
    // reference (so every glyph's baseline/x-height agree), with overshoot for
    // round apexes; everything else snaps to its own grid line.
    var target: [max_knots]f32 = undefined;
    for (edges, 0..) |e, i| target[i] = blueTarget(e, blues, px_per_unit, params.overshoot_min_px);

    // Pass 2 — stems. Two independent grid-fits, because position and width
    // are separate concerns:
    //   * POSITION — always register the stem to the grid so its edges land on
    //     pixel boundaries instead of floating at a fractional offset (blurry,
    //     and out of phase with every other hinter). This is a pure crispness
    //     win at any size and preserves weight, so it's what "light" hinting
    //     wants even for thick stems.
    //   * WIDTH — only quantise to a whole pixel while the stem is thin enough
    //     that a 1px snap is a legibility win (small ppem). Above
    //     `stem_hint_max_px` a thick stem keeps its natural width, so it doesn't
    //     "pop" heavier than the glyph's curves; it's still position-registered.
    // `hinted` marks the survivors kept as knots.
    var hinted = [_]bool{false} ** max_knots;
    var anchor_set = false;
    var anchor_base: f32 = 0;
    var anchor_target: f32 = 0;
    for (edges, 0..) |e, i| {
        if (!e.isStem()) continue;
        const j: usize = @intCast(e.stem);
        if (j <= i) continue; // process each pair once, from its lower edge
        const nominal = standardizeWidth(e.width, std_width, params.std_snap_ratio);
        const width_units = if (params.full_stem_hint or nominal * px_per_unit < params.stem_hint_max_px)
            @max(@round(nominal * px_per_unit), 1.0) * grid // whole-pixel
        else
            e.width; // thick — natural width, position only
        if (params.anchor_stem_positions) {
            // Anchor to the first stem, then round each later stem's distance
            // from it ONCE — preserves the glyph's counter widths instead of
            // double-rounding both ends of every gap.
            if (!anchor_set) {
                target[i] = snap(e.pos, px_per_unit);
                anchor_base = e.pos;
                anchor_target = target[i];
                anchor_set = true;
            } else {
                target[i] = anchor_target + @round((e.pos - anchor_base) * px_per_unit) * grid;
            }
            target[j] = target[i] + width_units;
        } else {
            const lower_blue = edges[i].blue >= 0;
            const upper_blue = edges[j].blue >= 0;
            if (upper_blue and !lower_blue) {
                target[i] = target[j] - width_units;
            } else {
                target[j] = target[i] + width_units;
            }
        }
        hinted[i] = true;
        hinted[j] = true;
    }

    // Pass 2.5 — preserve the weight of a thin stroke that terminates on a
    // blue zone as a ROUND apex (the top of 'a'/'n'/'o', the bottom of 'o').
    // The blue edge snaps to the reference, but its inner companion is a round
    // apex that `linkStems` doesn't pair, so without help it just interpolates
    // against the nearest stem knot below and the stroke COMPRESSES — the "top
    // of a looks thinner than the bowl". Anchor the companion a whole pixel off
    // the blue target so the whole stroke translates at full weight instead.
    // Same small-size-only taper as stems: thin strokes get help, thick ones
    // (already clean under AA) stay natural.
    for (edges, 0..) |e, i| {
        if (e.blue < 0 or !e.round or hinted[i]) continue;
        const top = e.dir > 0;
        var best: isize = -1;
        var best_gap: f32 = std.math.floatMax(f32);
        for (edges, 0..) |c, k| {
            if (k == i or c.dir == e.dir) continue; // need the opposite face
            const gap = if (top) e.pos - c.pos else c.pos - e.pos;
            if (gap <= 0 or gap >= best_gap) continue; // interior side, nearest
            best_gap = gap;
            best = @intCast(k);
        }
        if (best < 0) continue;
        const j: usize = @intCast(best);
        if (hinted[j] or edges[j].blue >= 0) continue; // already an anchored knot
        if (best_gap * px_per_unit >= params.stem_hint_max_px) continue; // thick — leave natural
        const width_units = @max(@round(best_gap * px_per_unit), 1.0) * grid;
        target[j] = if (top) target[i] - width_units else target[i] + width_units;
        hinted[j] = true;
    }

    // Pass 3 — keep only genuine features as knots: WIDTH-HINTED stem edges,
    // blue-linked edges, and the weight-preserving companions from pass 2.5.
    // Un-hinted thick stems, interior curve apexes, and stray edges are NOT
    // snapped — they interpolate between the real knots (the same idea as
    // TrueType's interpolate-untouched-points). This keeps baseline/x-height
    // alignment at every size while stem-width crispness fades out as the
    // glyph grows and AA already renders stems cleanly.
    var count: usize = 0;
    for (edges, 0..) |e, i| {
        const keep = hinted[i] or e.blue >= 0;
        if (!keep) continue;
        out[count] = .{ .base = e.pos, .target = target[i] };
        count += 1;
    }

    // Pass 3.5 — round-left registration (see doc comment). Only when the glyph
    // has a bowl clearly left of its leftmost snapped stem; flats (left_edge ≈
    // first knot) and knot-less glyphs are untouched. Prepend it, snapped like a
    // stem edge, so the bowl lands on the grid with the flats.
    if (!std.math.isNan(left_edge) and count > 0 and count < out.len and
        left_edge < out[0].base - 0.5 * grid)
    {
        var m = count;
        while (m > 0) : (m -= 1) out[m] = out[m - 1];
        out[0] = .{ .base = left_edge, .target = snap(left_edge, px_per_unit) };
        count += 1;
    }

    // Pass 4 — strict monotonicity over the kept knots, so the map stays
    // invertible when small-ppem snapping would otherwise cross them.
    var i: usize = 1;
    while (i < count) : (i += 1) {
        if (out[i].target <= out[i - 1].target) {
            out[i].target = out[i - 1].target + grid;
        }
    }

    return count;
}

/// Forward warp f: base -> hinted. Piecewise-linear through the knots,
/// identity (shifted to stay continuous) outside the edge range. Used to
/// grid-fit an outline directly (e.g. the CPU preview / any point-warp
/// caller); the renderer uses `inverseWarp` instead.
pub fn forwardWarp(knots: []const Knot, base: f32) f32 {
    const n = knots.len;
    if (n == 0) return base;
    if (base <= knots[0].base) return knots[0].target + (base - knots[0].base);
    if (base >= knots[n - 1].base) return knots[n - 1].target + (base - knots[n - 1].base);

    var i: usize = 0;
    while (i + 1 < n and knots[i + 1].base < base) : (i += 1) {}
    const lo = knots[i];
    const hi = knots[i + 1];
    const db = hi.base - lo.base;
    const slope = if (@abs(db) > 1e-6) (hi.target - lo.target) / db else 1.0;
    return lo.target + (base - lo.base) * slope;
}

/// Invert the warp at `hinted`: recover the base-space coordinate and the
/// local slope. Outside the edge range the map is identity (slope 1) shifted
/// to stay continuous at the end knots, so glyph interiors past the last
/// feature aren't distorted. This is the function the fragment shader mirrors.
pub fn inverseWarp(knots: []const Knot, hinted: f32) Sample {
    const n = knots.len;
    if (n == 0) return .{ .base = hinted, .inv_slope = 1.0 };

    if (hinted <= knots[0].target) {
        return .{ .base = knots[0].base + (hinted - knots[0].target), .inv_slope = 1.0 };
    }
    if (hinted >= knots[n - 1].target) {
        return .{ .base = knots[n - 1].base + (hinted - knots[n - 1].target), .inv_slope = 1.0 };
    }

    var i: usize = 0;
    while (i + 1 < n and knots[i + 1].target < hinted) : (i += 1) {}
    const lo = knots[i];
    const hi = knots[i + 1];
    const dt = hi.target - lo.target;
    const db = hi.base - lo.base;
    const inv_slope = if (@abs(dt) > 1e-6) db / dt else 1.0;
    return .{ .base = lo.base + (hinted - lo.target) * inv_slope, .inv_slope = inv_slope };
}

// ── shader-facing packed form ──────────────────────────────────────────────
//
// The GPU needs the knots as a flat float run it can `texelFetch`. Layout per
// axis: [count, base0, target0, base1, target1, …]. `snail_autohint_warp.glsl`
// reads exactly this and mirrors `inverseWarpPacked` — the parity test below
// pins the two together so the shader can't silently drift from the CPU math.

/// Serialise `knots` into `out` as `[count, (base,target)×count]`. Returns the
/// number of floats written (`1 + 2*len`). `out` must hold that many.
pub fn packAxis(knots: []const Knot, out: []f32) usize {
    out[0] = @floatFromInt(knots.len);
    for (knots, 0..) |k, i| {
        out[1 + 2 * i] = k.base;
        out[2 + 2 * i] = k.target;
    }
    return 1 + 2 * knots.len;
}

/// Inverse warp reading the packed layout. Byte-for-byte the same arithmetic
/// as `inverseWarp`, but over the flat float run the shader sees — so this is
/// the exact reference `snail_autohint_warp.glsl` must reproduce.
pub fn inverseWarpPacked(data: []const f32, hinted: f32) Sample {
    const n: usize = @intFromFloat(data[0]);
    if (n == 0) return .{ .base = hinted, .inv_slope = 1.0 };

    const first_base = data[1];
    const first_target = data[2];
    if (hinted <= first_target) {
        return .{ .base = first_base + (hinted - first_target), .inv_slope = 1.0 };
    }
    const last_base = data[1 + 2 * (n - 1)];
    const last_target = data[2 + 2 * (n - 1)];
    if (hinted >= last_target) {
        return .{ .base = last_base + (hinted - last_target), .inv_slope = 1.0 };
    }

    var i: usize = 0;
    while (i + 1 < n and data[2 + 2 * (i + 1)] < hinted) : (i += 1) {}
    const lo_base = data[1 + 2 * i];
    const lo_target = data[2 + 2 * i];
    const hi_base = data[1 + 2 * (i + 1)];
    const hi_target = data[2 + 2 * (i + 1)];
    const dt = hi_target - lo_target;
    const db = hi_base - lo_base;
    const inv_slope = if (@abs(dt) > 1e-6) db / dt else 1.0;
    return .{ .base = lo_base + (hinted - lo_target) * inv_slope, .inv_slope = inv_slope };
}

// ── tests ────────────────────────────────────────────────────────────────

const testing = std.testing;

fn edge(pos: f32, dir: i8) Edge {
    return .{ .pos = pos, .min = 0, .max = 500, .dir = dir };
}

fn stemPair(lower: *Edge, upper: *Edge, li: usize, ui: usize, width: f32) void {
    lower.stem = @intCast(ui);
    lower.width = width;
    upper.stem = @intCast(li);
    upper.width = width;
}

test "knots snap edges to the pixel grid and stay monotone" {
    // em=1000, ppem=12 -> 0.012 px/funit, grid ~= 83.3 funits.
    const px_per_unit: f32 = 12.0 / 1000.0;
    var edges = [_]Edge{
        edge(0, -1), // baseline foot (blue-linked)
        edge(300, -1), // stem bottom
        edge(380, 1), // stem top
        edge(700, 1), // cap top (blue-linked)
    };
    edges[0].blue = 0;
    edges[3].blue = 1;
    stemPair(&edges[1], &edges[2], 1, 2, 80);
    const blues = [_]BlueZone{ .{ .ref = 0, .shoot = 0 }, .{ .ref = 700, .shoot = 700 } };

    var buf: [max_knots]Knot = undefined;
    // baseline + cap kept via blue link, stem pair kept as stems -> 4 knots.
    const count = buildKnots(&edges, &blues, px_per_unit, 0, .{}, &buf);
    try testing.expectEqual(@as(usize, 4), count);

    const knots = buf[0..count];
    // Each target lands on a pixel boundary.
    for (knots) |k| {
        const px = k.target * px_per_unit;
        try testing.expectApproxEqAbs(px, @round(px), 1e-4);
    }
    // Strictly increasing.
    for (1..count) |i| try testing.expect(knots[i].target > knots[i - 1].target);
}

test "stem width quantises to a whole pixel, minimum one" {
    const px_per_unit: f32 = 12.0 / 1000.0; // ~0.96px raw stem -> snaps to 1px
    var edges = [_]Edge{ edge(300, -1), edge(380, 1) };
    stemPair(&edges[0], &edges[1], 0, 1, 80);

    var buf: [max_knots]Knot = undefined;
    _ = buildKnots(&edges, &.{}, px_per_unit, 0, .{}, &buf);
    const width_px = (buf[1].target - buf[0].target) * px_per_unit;
    try testing.expectApproxEqAbs(@as(f32, 1.0), width_px, 1e-4);
}

test "blue-linked edges snap to the shared rounded blue position" {
    const px_per_unit: f32 = 13.0 / 1000.0;
    var a = edge(512, 1); // slightly off the blue
    a.blue = 0;
    var b = edge(505, 1);
    b.blue = 0;
    const blues = [_]BlueZone{.{ .ref = 500, .shoot = 500 }};

    var buf: [max_knots]Knot = undefined;
    var edges = [_]Edge{ a, b };
    // sort by pos so monotonic pass is well-defined (505 < 512)
    std.mem.sort(Edge, &edges, {}, struct {
        fn lt(_: void, x: Edge, y: Edge) bool {
            return x.pos < y.pos;
        }
    }.lt);
    _ = buildKnots(&edges, &blues, px_per_unit, 0, .{}, &buf);
    const shared = snap(500, px_per_unit);
    // Both latch onto the same rounded reference (monotonic pass may lift the
    // second by one grid step, so check the lower one hit it exactly).
    try testing.expectApproxEqAbs(shared, buf[0].target, 1e-4);
}

test "round apex overshoots at large ppem and flattens at small" {
    // x-height reference 500, round apex reaches 520 (20-FUnit overshoot).
    const blues = [_]BlueZone{.{ .ref = 500, .shoot = 520 }};
    var apex = edge(518, 1);
    apex.blue = 0;
    apex.round = true;

    var buf: [max_knots]Knot = undefined;

    // ppem 100 (em 1000): overshoot 20 * 0.1 = 2px >= cutoff -> kept at ref+20.
    var big = [_]Edge{apex};
    _ = buildKnots(&big, &blues, 100.0 / 1000.0, 0, .{}, &buf);
    try testing.expectApproxEqAbs(@as(f32, 520), buf[0].target, 1.0);

    // ppem 11: overshoot 20 * 0.011 = 0.22px < cutoff -> collapses to ref.
    var small = [_]Edge{apex};
    _ = buildKnots(&small, &blues, 11.0 / 1000.0, 0, .{}, &buf);
    const ref_fit = @round(500.0 * (11.0 / 1000.0)) / (11.0 / 1000.0);
    try testing.expectApproxEqAbs(ref_fit, buf[0].target, 0.5);
}

test "round apex on a blue keeps its stroke weight instead of compressing" {
    // Mimics the top arch of 'a': a crossbar stem low in the glyph, then a
    // round apex latched to the x-height blue with an inner companion edge
    // that analysis does NOT pair as a stem. Without weight preservation the
    // companion interpolates against the crossbar knot and the arch stroke
    // compresses to well under a pixel ("thin top of a"); with it the stroke
    // translates at a whole-pixel weight.
    const px_per_unit: f32 = 13.0 / 1000.0;
    var edges = [_]Edge{
        edge(274, -1), // crossbar lower
        edge(343, 1), // crossbar upper
        edge(483, -1), // arch inner (round apex, unpaired)
        edge(560, 1), // arch top (round apex, on the blue)
    };
    stemPair(&edges[0], &edges[1], 0, 1, 69);
    edges[2].round = true;
    edges[3].round = true;
    edges[3].blue = 0;
    const blues = [_]BlueZone{.{ .ref = 548, .shoot = 560 }};

    var buf: [max_knots]Knot = undefined;
    const n = buildKnots(&edges, &blues, px_per_unit, 0, .{}, &buf);

    // The companion (arch inner) is kept as its own knot ...
    try testing.expectEqual(@as(usize, 4), n);
    try testing.expectApproxEqAbs(@as(f32, 483), buf[2].base, 1e-4);
    // ... and the arch stroke lands on a whole pixel, not a compressed sliver.
    const stroke_px = (buf[3].target - buf[2].target) * px_per_unit;
    try testing.expectApproxEqAbs(@as(f32, 1.0), stroke_px, 1e-3);
}

test "inverse warp round-trips knot targets to their bases" {
    const px_per_unit: f32 = 11.0 / 1000.0;
    var edges = [_]Edge{ edge(0, -1), edge(300, -1), edge(380, 1), edge(700, 1) };
    stemPair(&edges[1], &edges[2], 1, 2, 80);
    var buf: [max_knots]Knot = undefined;
    const count = buildKnots(&edges, &.{}, px_per_unit, 0, .{}, &buf);
    const knots = buf[0..count];

    for (knots) |k| {
        const s = inverseWarp(knots, k.target);
        try testing.expectApproxEqAbs(k.base, s.base, 1e-3);
    }
}

test "packed inverse warp matches the reference across the range" {
    const px_per_unit: f32 = 13.0 / 1000.0;
    var edges = [_]Edge{ edge(0, -1), edge(300, -1), edge(380, 1), edge(700, 1) };
    edges[0].blue = 0;
    edges[3].blue = 1;
    stemPair(&edges[1], &edges[2], 1, 2, 80);
    const blues = [_]BlueZone{ .{ .ref = 0, .shoot = 0 }, .{ .ref = 700, .shoot = 700 } };
    var buf: [max_knots]Knot = undefined;
    const count = buildKnots(&edges, &blues, px_per_unit, 0, .{}, &buf);
    const knots = buf[0..count];

    var packed_buf: [1 + 2 * max_knots]f32 = undefined;
    const n = packAxis(knots, &packed_buf);
    const data = packed_buf[0..n];

    // Sweep well past both ends (identity extrapolation) and through the knots.
    var h: f32 = -200;
    while (h <= 900) : (h += 7.3) {
        const a = inverseWarp(knots, h);
        const b = inverseWarpPacked(data, h);
        try testing.expectApproxEqAbs(a.base, b.base, 1e-3);
        try testing.expectApproxEqAbs(a.inv_slope, b.inv_slope, 1e-3);
    }
}

test "inverse warp is identity outside the edge range" {
    var buf = [_]Knot{
        .{ .base = 100, .target = 120 },
        .{ .base = 700, .target = 680 },
    };
    const below = inverseWarp(&buf, 0);
    try testing.expectApproxEqAbs(@as(f32, -20), below.base, 1e-4); // 100 + (0-120)
    try testing.expectApproxEqAbs(@as(f32, 1.0), below.inv_slope, 1e-4);
    const above = inverseWarp(&buf, 800);
    try testing.expectApproxEqAbs(@as(f32, 820), above.base, 1e-4); // 700 + (800-680)
    try testing.expectApproxEqAbs(@as(f32, 1.0), above.inv_slope, 1e-4);
}

test "empty edge set yields identity" {
    var buf: [max_knots]Knot = undefined;
    try testing.expectEqual(@as(usize, 0), buildKnots(&.{}, &.{}, 0.012, 0, .{}, &buf));
    const s = inverseWarp(&.{}, 123.0);
    try testing.expectApproxEqAbs(@as(f32, 123.0), s.base, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1.0), s.inv_slope, 1e-6);
}
