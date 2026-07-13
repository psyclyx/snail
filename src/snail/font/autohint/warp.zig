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
const policy_mod = @import("policy.zig");
const Vec2 = @import("../../math/vec.zig").Vec2;
const Edge = analysis.Edge;
const FeatureEdge = analysis.FeatureEdge;

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
    /// Keep each stem's analyzed width instead of quantizing it.
    natural_stem_width: bool = false,
    /// Register stem positions to the grid. When false, width fitting is
    /// composed around the natural lower edge.
    align_stem_positions: bool = true,

    pub const default: Params = .{};
};

fn AxisPolicy(comptime axis: analysis.Axis) type {
    return switch (axis) {
        .x => policy_mod.XPolicy,
        .y => policy_mod.YPolicy,
    };
}

pub const AxisKnots = struct {
    x: []Knot,
    y: []Knot,
};

/// Derive one axis's transient normalized warp from immutable feature facts.
/// `font` is a `FontFeatures` value; it is structural here to avoid a module
/// cycle with the producer that owns that record type.
pub fn fitAxis(
    features: []const FeatureEdge,
    font: anytype,
    comptime axis: analysis.Axis,
    axis_policy: AxisPolicy(axis),
    pixels_per_em: f32,
    left: f32,
    out: []Knot,
) []Knot {
    if (!std.math.isFinite(pixels_per_em) or pixels_per_em <= 0 or
        features.len == 0 or features.len > max_knots or features.len > out.len or
        font.blues.len > max_knots or
        !std.math.isFinite(font.std_x) or font.std_x < 0 or
        !std.math.isFinite(font.std_y) or font.std_y < 0)
    {
        return out[0..0];
    }
    for (font.blues) |zone| {
        if (!std.math.isFinite(zone.ref) or !std.math.isFinite(zone.shoot)) return out[0..0];
    }
    for (features, 0..) |feature, i| {
        if (!std.math.isFinite(feature.pos) or !std.math.isFinite(feature.width) or feature.width < 0 or
            feature.stem < -1 or feature.blue < -1 or
            (feature.blue >= 0 and @as(usize, @intCast(feature.blue)) >= font.blues.len))
        {
            return out[0..0];
        }
        if (feature.stem >= 0) {
            const partner_index: usize = @intCast(feature.stem);
            if (partner_index >= features.len or partner_index == i) return out[0..0];
            const partner = features[partner_index];
            if (partner.stem != @as(i16, @intCast(i)) or
                !std.math.isFinite(partner.pos) or partner.pos == feature.pos or
                !std.math.isFinite(partner.width) or partner.width != feature.width)
            {
                return out[0..0];
            }
        }
    }

    var params: Params = .{};
    var use_blues = false;
    var left_edge = std.math.nan(f32);
    switch (axis) {
        .x => {
            if (axis_policy.@"align" == .none and axis_policy.stem_width == .natural and
                axis_policy.positioning == .independent and axis_policy.registration == .none)
            {
                return out[0..0];
            }
            params.align_stem_positions = axis_policy.@"align" == .grid;
            params.anchor_stem_positions = axis_policy.positioning == .relative;
            if (axis_policy.registration == .left_round_outline and !std.math.isFinite(left)) return out[0..0];
            left_edge = if (axis_policy.registration == .left_round_outline) left else std.math.nan(f32);
        },
        .y => {
            if (axis_policy.@"align" == .none and axis_policy.stem_width == .natural and
                axis_policy.overshoot == .preserve)
            {
                return out[0..0];
            }
            params.align_stem_positions = axis_policy.@"align" != .none;
            use_blues = axis_policy.@"align" == .blue_zones;
            params.overshoot_min_px = switch (axis_policy.overshoot) {
                .preserve => 0,
                .suppress_below_px => |threshold| threshold: {
                    if (!std.math.isFinite(threshold) or threshold < 0) return out[0..0];
                    break :threshold threshold;
                },
            };
        },
    }
    switch (axis_policy.stem_width) {
        .natural => params.natural_stem_width = true,
        .light => |light| {
            if (!std.math.isFinite(light.std_snap_ratio) or !std.math.isFinite(light.max_px) or
                light.std_snap_ratio < 0 or light.max_px < 0) return out[0..0];
            params.std_snap_ratio = light.std_snap_ratio;
            params.stem_hint_max_px = light.max_px;
        },
        .full => |full| {
            if (!std.math.isFinite(full.std_snap_ratio) or full.std_snap_ratio < 0) return out[0..0];
            params.std_snap_ratio = full.std_snap_ratio;
            params.full_stem_hint = true;
        },
    }

    var edges: [max_knots]Edge = undefined;
    var zones: [max_knots]BlueZone = undefined;
    if (use_blues) {
        for (font.blues, 0..) |zone, i| zones[i] = .{ .ref = zone.ref, .shoot = zone.shoot };
    }
    for (features, 0..) |feature, i| {
        const partner_above = feature.stem >= 0 and @as(usize, @intCast(feature.stem)) < features.len and
            features[@intCast(feature.stem)].pos > feature.pos;
        const valid_blue = use_blues and feature.blue >= 0 and @as(usize, @intCast(feature.blue)) < font.blues.len;
        const bottom_blue = valid_blue and font.blues[@intCast(feature.blue)].shoot < font.blues[@intCast(feature.blue)].ref;
        var companion_dir: i8 = 1;
        if (feature.stem < 0 and !valid_blue and use_blues) {
            var nearest_gap = std.math.inf(f32);
            for (features) |candidate| {
                if (candidate.blue < 0 or @as(usize, @intCast(candidate.blue)) >= font.blues.len) continue;
                const gap = @abs(candidate.pos - feature.pos);
                if (gap >= nearest_gap) continue;
                nearest_gap = gap;
                const candidate_zone = font.blues[@intCast(candidate.blue)];
                companion_dir = if (candidate_zone.shoot < candidate_zone.ref) 1 else -1;
            }
        }
        edges[i] = .{
            .pos = feature.pos,
            .min = 0,
            .max = 0,
            .dir = if (partner_above or bottom_blue) -1 else companion_dir,
            .stem = feature.stem,
            .width = feature.width,
            .blue = if (use_blues) feature.blue else if (axis_policy.@"align" != .none) feature.blue else -1,
            .round = feature.flags.round,
        };
    }

    const std_width = if (axis == .x) font.std_x else font.std_y;
    const count = buildKnotsReg(edges[0..features.len], if (use_blues) zones[0..font.blues.len] else &.{}, pixels_per_em, std_width, params, left_edge, out);
    for (out[0..count]) |knot| {
        if (!std.math.isFinite(knot.base) or !std.math.isFinite(knot.target)) return out[0..0];
    }
    return out[0..count];
}

/// Fit both axes at draw time. The returned knot slices borrow caller-owned
/// scratch buffers and must never be stored in an atlas record.
pub fn fitGlyph(features: anytype, font: anytype, policy: policy_mod.AutohintPolicy, scale: Vec2, x_out: []Knot, y_out: []Knot) AxisKnots {
    return .{
        .x = fitAxis(features.x, font, .x, policy.x, scale.x, features.left, x_out),
        .y = fitAxis(features.y, font, .y, policy.y, scale.y, 0, y_out),
    };
}

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
        const width_units = if (params.natural_stem_width)
            e.width
        else if (params.full_stem_hint or nominal * px_per_unit < params.stem_hint_max_px)
            @max(@round(nominal * px_per_unit), 1.0) * grid // whole-pixel
        else
            e.width; // thick — natural width, position only
        if (params.anchor_stem_positions) {
            // Position each stem by rounding its PITCH — the inner-edge-to-
            // inner-edge distance from the previous stem — exactly once, and
            // accumulate. One round folds this stem's width and counter together
            // (no double-rounding, so a 2-stem glyph like 'H' keeps its width),
            // while accumulating rounded pitches keeps a 3-leg glyph like 'm'/'w'
            // evenly spaced (round-from-the-first-stem would round 2·pitch and
            // split it into a 1px + 2px counter).
            if (anchor_set) {
                target[i] = anchor_target + @round((e.pos - anchor_base) * px_per_unit) * grid;
            } else {
                target[i] = snap(e.pos, px_per_unit);
                anchor_set = true;
            }
            target[j] = target[i] + width_units;
            anchor_base = e.pos; // this stem's INNER edge → base for the next pitch
            anchor_target = target[i];
        } else {
            const lower_blue = edges[i].blue >= 0;
            const upper_blue = edges[j].blue >= 0;
            if (!params.align_stem_positions) target[i] = e.pos;
            if (upper_blue and !lower_blue and params.align_stem_positions) {
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

const TestFontFeatures = struct {
    blues: []const BlueZone = &.{},
    std_x: f32 = 0,
    std_y: f32 = 0,
};

fn testFeature(pos: f32) FeatureEdge {
    return .{ .pos = pos, .width = 0, .stem = -1, .blue = -1, .flags = .{ .round = false } };
}

fn featureStemPair(lower: *FeatureEdge, upper: *FeatureEdge, li: usize, ui: usize, width: f32) void {
    lower.stem = @intCast(ui);
    lower.width = width;
    upper.stem = @intCast(li);
    upper.width = width;
}

// Independent host translation of snailDecodeAutohintPolicy +
// snailFitAutohintAxis. This oracle does not call CPU decoding or fitting helpers.
const GlslHostPolicy = struct {
    x_align: u32,
    x_stem: u32,
    x_positioning: u32,
    x_registration: u32,
    y_align: u32,
    y_stem: u32,
    y_overshoot: u32,
    x_ratio: f32,
    x_max_px: f32,
    y_ratio: f32,
    y_max_px: f32,
    overshoot_min_px: f32,
};

fn glslHostDecodePolicy(words: [7]u32) ?GlslHostPolicy {
    if (words[0] & ~@as(u32, 0xff) != 0 or words[1] & ~@as(u32, 0x3f) != 0) return null;
    const p: GlslHostPolicy = .{
        .x_align = words[0] & 3,
        .x_stem = (words[0] >> 2) & 3,
        .x_positioning = (words[0] >> 4) & 3,
        .x_registration = (words[0] >> 6) & 3,
        .y_align = words[1] & 3,
        .y_stem = (words[1] >> 2) & 3,
        .y_overshoot = (words[1] >> 4) & 3,
        .x_ratio = @bitCast(words[2]),
        .x_max_px = @bitCast(words[3]),
        .y_ratio = @bitCast(words[4]),
        .y_max_px = @bitCast(words[5]),
        .overshoot_min_px = @bitCast(words[6]),
    };
    if (p.x_align > 1 or p.x_stem > 2 or p.x_positioning > 1 or p.x_registration > 1 or
        p.y_align > 2 or p.y_stem > 2 or p.y_overshoot > 1 or
        (p.x_stem != 0 and (!std.math.isFinite(p.x_ratio) or p.x_ratio < 0)) or
        (p.x_stem == 1 and (!std.math.isFinite(p.x_max_px) or p.x_max_px < 0)) or
        (p.y_stem != 0 and (!std.math.isFinite(p.y_ratio) or p.y_ratio < 0)) or
        (p.y_stem == 1 and (!std.math.isFinite(p.y_max_px) or p.y_max_px < 0)) or
        (p.y_overshoot == 1 and (!std.math.isFinite(p.overshoot_min_px) or p.overshoot_min_px < 0)) or
        (p.x_positioning == 1 and p.x_align == 0) or (p.y_overshoot == 1 and p.y_align != 2)) return null;
    return p;
}

fn glslHostSnap(value: f32, scale: f32) f32 {
    return @round(value * scale) / scale;
}

fn glslHostFitAxis(features: []const FeatureEdge, font: TestFontFeatures, comptime axis: analysis.Axis, words: [7]u32, scale: f32, left: f32, out: []Knot) []Knot {
    const policy = glslHostDecodePolicy(words) orelse return out[0..0];
    if (!std.math.isFinite(font.std_x) or font.std_x < 0 or !std.math.isFinite(font.std_y) or font.std_y < 0 or
        !std.math.isFinite(scale) or scale <= 0 or features.len == 0 or features.len > max_knots or
        features.len > out.len or font.blues.len > max_knots) return out[0..0];
    const use_blues = axis == .y and policy.y_align == 2;
    if ((axis == .x and policy.x_align == 0 and policy.x_stem == 0 and policy.x_positioning == 0 and policy.x_registration == 0) or
        (axis == .y and policy.y_align == 0 and policy.y_stem == 0 and policy.y_overshoot == 0)) return out[0..0];
    if (axis == .x and policy.x_registration == 1 and !std.math.isFinite(left)) return out[0..0];
    for (font.blues) |zone| if (!std.math.isFinite(zone.ref) or !std.math.isFinite(zone.shoot)) return out[0..0];
    for (features, 0..) |feature, i| {
        if (!std.math.isFinite(feature.pos) or !std.math.isFinite(feature.width) or feature.width < 0 or
            feature.stem < -1 or feature.blue < -1 or
            (feature.blue >= 0 and @as(usize, @intCast(feature.blue)) >= font.blues.len)) return out[0..0];
        if (feature.stem >= 0) {
            const j: usize = @intCast(feature.stem);
            if (j >= features.len or j == i or features[j].stem != @as(i16, @intCast(i)) or
                !std.math.isFinite(features[j].pos) or features[j].pos == feature.pos or
                !std.math.isFinite(features[j].width) or features[j].width != feature.width) return out[0..0];
        }
    }

    var targets: [max_knots]f32 = undefined;
    var dirs: [max_knots]i8 = undefined;
    var hinted = [_]bool{false} ** max_knots;
    const overshoot_limit = if (axis == .y and policy.y_overshoot == 1) policy.overshoot_min_px else 0;
    for (features, 0..) |feature, i| {
        const partner_above = feature.stem >= 0 and features[@intCast(feature.stem)].pos > feature.pos;
        const valid_blue = use_blues and feature.blue >= 0;
        const bottom_blue = valid_blue and font.blues[@intCast(feature.blue)].shoot < font.blues[@intCast(feature.blue)].ref;
        var companion_dir: i8 = 1;
        if (feature.stem < 0 and !valid_blue and use_blues) {
            var nearest = std.math.floatMax(f32);
            for (features) |candidate| {
                if (candidate.blue < 0) continue;
                const gap = @abs(candidate.pos - feature.pos);
                if (gap >= nearest) continue;
                nearest = gap;
                const zone = font.blues[@intCast(candidate.blue)];
                companion_dir = if (zone.shoot < zone.ref) 1 else -1;
            }
        }
        dirs[i] = if (partner_above or bottom_blue) -1 else companion_dir;
        if (valid_blue) {
            const zone = font.blues[@intCast(feature.blue)];
            targets[i] = glslHostSnap(zone.ref, scale);
            if (feature.flags.round and @abs((zone.shoot - zone.ref) * scale) >= overshoot_limit) targets[i] += zone.shoot - zone.ref;
        } else targets[i] = glslHostSnap(feature.pos, scale);
    }

    const grid = 1.0 / scale;
    const stem_mode = if (axis == .x) policy.x_stem else policy.y_stem;
    const ratio = if (axis == .x) policy.x_ratio else policy.y_ratio;
    const max_px = if (axis == .x) policy.x_max_px else policy.y_max_px;
    const align_positions = if (axis == .x) policy.x_align == 1 else policy.y_align != 0;
    const relative = axis == .x and policy.x_positioning == 1;
    const standard_width = if (axis == .x) font.std_x else font.std_y;
    var anchor_set = false;
    var anchor_base: f32 = 0;
    var anchor_target: f32 = 0;
    for (features, 0..) |feature, i| {
        if (feature.stem < 0) continue;
        const j: usize = @intCast(feature.stem);
        if (j <= i) continue;
        const nominal = if (standard_width > 0 and @abs(feature.width - standard_width) <= ratio * standard_width) standard_width else feature.width;
        var width_units = feature.width;
        if (stem_mode == 2 or (stem_mode == 1 and nominal * scale < max_px)) width_units = @max(@round(nominal * scale), 1.0) * grid;
        if (relative) {
            if (anchor_set) targets[i] = anchor_target + @round((feature.pos - anchor_base) * scale) * grid else {
                targets[i] = glslHostSnap(feature.pos, scale);
                anchor_set = true;
            }
            targets[j] = targets[i] + width_units;
            anchor_base = feature.pos;
            anchor_target = targets[i];
        } else {
            // Retain decoded blue indices for y-grid, exactly as the shader does.
            const lower_blue = feature.blue >= 0;
            const upper_blue = features[j].blue >= 0;
            if (!align_positions) targets[i] = feature.pos;
            if (upper_blue and !lower_blue and align_positions) targets[i] = targets[j] - width_units else targets[j] = targets[i] + width_units;
        }
        hinted[i] = true;
        hinted[j] = true;
    }

    const companion_max = if (stem_mode == 1) max_px else 1.6;
    for (features, 0..) |feature, i| {
        const axis_aligned = if (axis == .x) policy.x_align != 0 else policy.y_align != 0;
        if (!axis_aligned or feature.blue < 0 or !feature.flags.round or hinted[i]) continue;
        const top = dirs[i] > 0;
        var best: ?usize = null;
        var best_gap = std.math.floatMax(f32);
        for (features, 0..) |candidate, k| {
            if (k == i or dirs[k] == dirs[i]) continue;
            const gap = if (top) feature.pos - candidate.pos else candidate.pos - feature.pos;
            if (gap <= 0 or gap >= best_gap) continue;
            best_gap = gap;
            best = k;
        }
        const j = best orelse continue;
        if (hinted[j] or features[j].blue >= 0 or best_gap * scale >= companion_max) continue;
        const width_units = @max(@round(best_gap * scale), 1.0) * grid;
        targets[j] = if (top) targets[i] - width_units else targets[i] + width_units;
        hinted[j] = true;
    }

    var count: usize = 0;
    for (features, 0..) |feature, i| {
        const axis_aligned = if (axis == .x) policy.x_align != 0 else policy.y_align != 0;
        if (!hinted[i] and !(axis_aligned and feature.blue >= 0)) continue;
        out[count] = .{ .base = feature.pos, .target = targets[i] };
        count += 1;
    }
    if (axis == .x and policy.x_registration == 1 and count > 0 and count < max_knots and count < out.len and
        left < out[0].base - 0.5 * grid)
    {
        var i = count;
        while (i > 0) : (i -= 1) out[i] = out[i - 1];
        out[0] = .{ .base = left, .target = glslHostSnap(left, scale) };
        count += 1;
    }
    var i: usize = 1;
    while (i < count) : (i += 1) {
        if (out[i].target <= out[i - 1].target) out[i].target = out[i - 1].target + grid;
    }
    for (out[0..count]) |knot| {
        if (!std.math.isFinite(knot.base) or !std.math.isFinite(knot.target)) return out[0..0];
    }
    return out[0..count];
}

fn expectGlslFixtureAxis(expected: []const Knot, actual: []const Knot, probes: []const f32) !void {
    try testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |cpu, gpu| {
        try testing.expectApproxEqAbs(cpu.base, gpu.base, 1e-5);
        try testing.expectApproxEqAbs(cpu.target, gpu.target, 1e-5);
    }
    var packed_data: [1 + 2 * max_knots]f32 = undefined;
    const packed_len = packAxis(actual, &packed_data);
    for (probes) |hinted| {
        const cpu = inverseWarp(expected, hinted);
        const gpu = inverseWarpPacked(packed_data[0..packed_len], hinted);
        try testing.expectApproxEqAbs(cpu.base, gpu.base, 1e-5);
        try testing.expectApproxEqAbs(cpu.inv_slope, gpu.inv_slope, 1e-5);
    }
}

test "CPU-generated policy fixtures match host GLSL evaluator targets and inverse slopes" {
    const probes = [_]f32{ -0.1, 0.0, 0.19, 0.25, 0.5, 0.8 };

    // Identity x.
    var identity_features = [_]FeatureEdge{ testFeature(0.3), testFeature(0.38) };
    featureStemPair(&identity_features[0], &identity_features[1], 0, 1, 0.08);
    const identity_policy: policy_mod.AutohintPolicy = .{};
    var cpu_buf: [max_knots]Knot = undefined;
    var glsl_buf: [max_knots]Knot = undefined;
    const identity_cpu = fitAxis(&identity_features, TestFontFeatures{ .std_x = 0.08 }, .x, identity_policy.x, 13, 0, &cpu_buf);
    const identity_glsl = glslHostFitAxis(&identity_features, TestFontFeatures{ .std_x = 0.08 }, .x, identity_policy.pack(), 13, 0, &glsl_buf);
    try expectGlslFixtureAxis(identity_cpu, identity_glsl, &probes);

    // Blue y, including preserved and suppressed round overshoot.
    const zones = [_]BlueZone{.{ .ref = 0.5, .shoot = 0.52 }};
    var blue_features = [_]FeatureEdge{testFeature(0.52)};
    blue_features[0].blue = 0;
    blue_features[0].flags.round = true;
    const blue_font = TestFontFeatures{ .blues = &zones, .std_y = 0.08 };
    const preserve_policy: policy_mod.AutohintPolicy = .{ .y = .{ .@"align" = .blue_zones } };
    const suppress_policy: policy_mod.AutohintPolicy = .{ .y = .{
        .@"align" = .blue_zones,
        .overshoot = .{ .suppress_below_px = 0.5 },
    } };
    inline for (.{ preserve_policy, suppress_policy }) |fixture_policy| {
        const cpu = fitAxis(&blue_features, blue_font, .y, fixture_policy.y, 13, 0, &cpu_buf);
        const gpu = glslHostFitAxis(&blue_features, blue_font, .y, fixture_policy.pack(), 13, 0, &glsl_buf);
        try expectGlslFixtureAxis(cpu, gpu, &probes);
    }

    // Y-grid retains blue indices for knot selection and stem anchoring even
    // though it does not use blue-zone reference targets.
    const y_grid_policy: policy_mod.AutohintPolicy = .{ .y = .{ .@"align" = .grid } };
    const y_grid_cpu = fitAxis(&blue_features, blue_font, .y, y_grid_policy.y, 13, 0, &cpu_buf);
    const y_grid_glsl = glslHostFitAxis(&blue_features, blue_font, .y, y_grid_policy.pack(), 13, 0, &glsl_buf);
    try expectGlslFixtureAxis(y_grid_cpu, y_grid_glsl, &probes);

    // Full-width relative x with multiple stems and left registration.
    var full_features = [_]FeatureEdge{ testFeature(0.10), testFeature(0.18), testFeature(0.29), testFeature(0.37) };
    featureStemPair(&full_features[0], &full_features[1], 0, 1, 0.08);
    featureStemPair(&full_features[2], &full_features[3], 2, 3, 0.08);
    const full_policy: policy_mod.AutohintPolicy = .{ .x = .{
        .@"align" = .grid,
        .stem_width = .{ .full = .{ .std_snap_ratio = 0.4 } },
        .positioning = .relative,
        .registration = .left_round_outline,
    } };
    const full_font = TestFontFeatures{ .std_x = 0.08 };
    const full_cpu = fitAxis(&full_features, full_font, .x, full_policy.x, 13, 0.01, &cpu_buf);
    const full_glsl = glslHostFitAxis(&full_features, full_font, .x, full_policy.pack(), 13, 0.01, &glsl_buf);
    try expectGlslFixtureAxis(full_cpu, full_glsl, &probes);

    // Degenerate scale and malformed either-axis metrics select identity.
    const malformed_fonts = [_]TestFontFeatures{
        .{ .blues = &zones, .std_x = std.math.nan(f32), .std_y = 0.08 },
        .{ .blues = &zones, .std_x = 0.08, .std_y = -0.1 },
    };
    for (malformed_fonts) |font| {
        const cpu_x = fitAxis(&full_features, font, .x, full_policy.x, 13, 0.01, &cpu_buf);
        const glsl_x = glslHostFitAxis(&full_features, font, .x, full_policy.pack(), 13, 0.01, &glsl_buf);
        try expectGlslFixtureAxis(cpu_x, glsl_x, &probes);
        const cpu_y = fitAxis(&blue_features, font, .y, preserve_policy.y, 13, 0, &cpu_buf);
        const glsl_y = glslHostFitAxis(&blue_features, font, .y, preserve_policy.pack(), 13, 0, &glsl_buf);
        try expectGlslFixtureAxis(cpu_y, glsl_y, &probes);
    }
    const scale_cpu = fitAxis(&full_features, full_font, .x, full_policy.x, 0, 0.01, &cpu_buf);
    const scale_glsl = glslHostFitAxis(&full_features, full_font, .x, full_policy.pack(), 0, 0.01, &glsl_buf);
    try expectGlslFixtureAxis(scale_cpu, scale_glsl, &probes);
}

test "identity x policy emits no knots" {
    var features = [_]FeatureEdge{ testFeature(0.3), testFeature(0.38) };
    featureStemPair(&features[0], &features[1], 0, 1, 0.08);
    var out: [max_knots]Knot = undefined;
    const knots = fitAxis(&features, TestFontFeatures{ .std_x = 0.08 }, .x, .{}, 13.0, 0, &out);
    try testing.expectEqual(@as(usize, 0), knots.len);
}

test "light y policy leaves thick stem width natural" {
    var features = [_]FeatureEdge{ testFeature(0.2), testFeature(0.4) };
    featureStemPair(&features[0], &features[1], 0, 1, 0.2);
    var out: [max_knots]Knot = undefined;
    const knots = fitAxis(&features, TestFontFeatures{ .std_y = 0.08 }, .y, .{
        .@"align" = .blue_zones,
        .stem_width = .{ .light = .{ .std_snap_ratio = 0.4, .max_px = 1.6 } },
        .overshoot = .{ .suppress_below_px = 0.5 },
    }, 13.0, 0, &out);
    try testing.expectEqual(@as(usize, 2), knots.len);
    try testing.expectApproxEqAbs(@as(f32, 0.2), knots[1].target - knots[0].target, 1e-5);
}

test "strong x composition matches prior fitting" {
    var features = [_]FeatureEdge{ testFeature(0.12), testFeature(0.20) };
    featureStemPair(&features[0], &features[1], 0, 1, 0.08);
    var out: [max_knots]Knot = undefined;
    const knots = fitAxis(&features, TestFontFeatures{ .std_x = 0.08 }, .x, .{
        .@"align" = .grid,
        .stem_width = .{ .full = .{ .std_snap_ratio = 0.4 } },
        .positioning = .relative,
        .registration = .left_round_outline,
    }, 13.0, 0.02, &out);
    try testing.expectEqual(@as(usize, 3), knots.len);
    const expected = [_]Knot{
        .{ .base = 0.02, .target = 0 },
        .{ .base = 0.12, .target = 2.0 / 13.0 },
        .{ .base = 0.20, .target = 3.0 / 13.0 },
    };
    for (expected, knots) |want, got| {
        try testing.expectApproxEqAbs(want.base, got.base, 1e-5);
        try testing.expectApproxEqAbs(want.target, got.target, 1e-5);
    }
}

test "fitAxis short feature slices ignore poisoned reused output scratch" {
    var features = [_]FeatureEdge{ testFeature(0.12), testFeature(0.20) };
    featureStemPair(&features[0], &features[1], 0, 1, 0.08);
    const policy: policy_mod.XPolicy = .{
        .@"align" = .grid,
        .stem_width = .{ .full = .{ .std_snap_ratio = 0.4 } },
    };

    var first_out = [_]Knot{.{ .base = std.math.nan(f32), .target = std.math.inf(f32) }} ** max_knots;
    const first = fitAxis(&features, TestFontFeatures{ .std_x = 0.08 }, .x, policy, 13, 0, &first_out);
    var expected: [max_knots]Knot = undefined;
    @memcpy(expected[0..first.len], first);
    const expected_len = first.len;

    @memset(&first_out, .{ .base = -1234, .target = 5678 });
    const second = fitAxis(&features, TestFontFeatures{ .std_x = 0.08 }, .x, policy, 13, 0, &first_out);
    try testing.expectEqual(expected_len, second.len);
    try testing.expectEqual(@as(usize, 2), second.len);
    for (expected[0..expected_len], second) |want, got| {
        try testing.expectEqual(want.base, got.base);
        try testing.expectEqual(want.target, got.target);
    }
}

test "fitAxis rejects zero NaN scale and feature overflow" {
    var one = [_]FeatureEdge{testFeature(0.2)};
    var too_many = [_]FeatureEdge{testFeature(0)} ** (max_knots + 1);
    var out: [max_knots]Knot = undefined;
    const policy: policy_mod.XPolicy = .{ .@"align" = .grid };
    try testing.expectEqual(@as(usize, 0), fitAxis(&one, TestFontFeatures{}, .x, policy, 0, 0, &out).len);
    try testing.expectEqual(@as(usize, 0), fitAxis(&one, TestFontFeatures{}, .x, policy, std.math.nan(f32), 0, &out).len);
    try testing.expectEqual(@as(usize, 0), fitAxis(&too_many, TestFontFeatures{}, .x, policy, 13, 0, &out).len);
}

test "fitAxis rejects invalid overshoot suppression thresholds" {
    var feature = [_]FeatureEdge{testFeature(0.2)};
    var out: [max_knots]Knot = undefined;

    try testing.expectEqual(@as(usize, 0), fitAxis(&feature, TestFontFeatures{}, .y, .{
        .@"align" = .grid,
        .overshoot = .{ .suppress_below_px = std.math.nan(f32) },
    }, 13, 0, &out).len);
    try testing.expectEqual(@as(usize, 0), fitAxis(&feature, TestFontFeatures{}, .y, .{
        .@"align" = .grid,
        .overshoot = .{ .suppress_below_px = std.math.inf(f32) },
    }, 13, 0, &out).len);
    try testing.expectEqual(@as(usize, 0), fitAxis(&feature, TestFontFeatures{}, .y, .{
        .@"align" = .grid,
        .overshoot = .{ .suppress_below_px = -0.1 },
    }, 13, 0, &out).len);
}

test "fitAxis rejects malformed feature and font records" {
    const x_policy: policy_mod.XPolicy = .{
        .@"align" = .grid,
        .stem_width = .{ .full = .{ .std_snap_ratio = 0.4 } },
        .registration = .left_round_outline,
    };
    var out: [max_knots]Knot = undefined;

    var bad_stem = [_]FeatureEdge{testFeature(0.2)};
    bad_stem[0].stem = 1;
    try testing.expectEqual(@as(usize, 0), fitAxis(&bad_stem, TestFontFeatures{}, .x, x_policy, 13, 0, &out).len);

    var nonreciprocal = [_]FeatureEdge{ testFeature(0.2), testFeature(0.3) };
    nonreciprocal[0].stem = 1;
    try testing.expectEqual(@as(usize, 0), fitAxis(&nonreciprocal, TestFontFeatures{}, .x, x_policy, 13, 0, &out).len);

    var bad_feature = [_]FeatureEdge{testFeature(std.math.nan(f32))};
    try testing.expectEqual(@as(usize, 0), fitAxis(&bad_feature, TestFontFeatures{}, .x, x_policy, 13, 0, &out).len);
    bad_feature[0] = testFeature(0.2);
    bad_feature[0].width = std.math.inf(f32);
    try testing.expectEqual(@as(usize, 0), fitAxis(&bad_feature, TestFontFeatures{}, .x, x_policy, 13, 0, &out).len);
    bad_feature[0] = testFeature(0.2);
    bad_feature[0].blue = 0;
    try testing.expectEqual(@as(usize, 0), fitAxis(&bad_feature, TestFontFeatures{}, .x, x_policy, 13, 0, &out).len);
    var overflowing = [_]FeatureEdge{ testFeature(std.math.floatMax(f32) / 2), testFeature(std.math.floatMax(f32)) };
    featureStemPair(&overflowing[0], &overflowing[1], 0, 1, 1);
    try testing.expectEqual(@as(usize, 0), fitAxis(&overflowing, TestFontFeatures{}, .x, x_policy, std.math.floatMax(f32), 0, &out).len);

    try testing.expectEqual(@as(usize, 0), fitAxis(&[_]FeatureEdge{testFeature(0.2)}, TestFontFeatures{ .std_x = std.math.nan(f32) }, .x, x_policy, 13, 0, &out).len);
    try testing.expectEqual(@as(usize, 0), fitAxis(&[_]FeatureEdge{testFeature(0.2)}, TestFontFeatures{ .std_y = -0.1 }, .x, x_policy, 13, 0, &out).len);
    try testing.expectEqual(@as(usize, 0), fitAxis(&[_]FeatureEdge{testFeature(0.2)}, TestFontFeatures{}, .x, x_policy, 13, std.math.inf(f32), &out).len);

    const bad_zones = [_]BlueZone{.{ .ref = 0, .shoot = std.math.nan(f32) }};
    var blue_feature = [_]FeatureEdge{testFeature(0.2)};
    blue_feature[0].blue = 0;
    try testing.expectEqual(@as(usize, 0), fitAxis(&blue_feature, TestFontFeatures{ .blues = &bad_zones }, .y, .{ .@"align" = .blue_zones }, 13, 0, &out).len);
}

test "independent and relative positioning compose separately" {
    var features = [_]FeatureEdge{ testFeature(0.10), testFeature(0.18), testFeature(0.29), testFeature(0.37) };
    featureStemPair(&features[0], &features[1], 0, 1, 0.08);
    featureStemPair(&features[2], &features[3], 2, 3, 0.08);
    const font = TestFontFeatures{ .std_x = 0.08 };
    var independent_out: [max_knots]Knot = undefined;
    var relative_out: [max_knots]Knot = undefined;
    const independent = fitAxis(&features, font, .x, .{
        .@"align" = .grid,
        .stem_width = .{ .full = .{ .std_snap_ratio = 0.4 } },
    }, 13, 0, &independent_out);
    const relative = fitAxis(&features, font, .x, .{
        .@"align" = .grid,
        .stem_width = .{ .full = .{ .std_snap_ratio = 0.4 } },
        .positioning = .relative,
    }, 13, 0, &relative_out);
    try testing.expectApproxEqAbs(@as(f32, 4.0 / 13.0), independent[2].target, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 3.0 / 13.0), relative[2].target, 1e-5);
}

test "natural stem width is preserved while its position aligns" {
    var features = [_]FeatureEdge{ testFeature(0.21), testFeature(0.29) };
    featureStemPair(&features[0], &features[1], 0, 1, 0.08);
    var out: [max_knots]Knot = undefined;
    const knots = fitAxis(&features, TestFontFeatures{ .std_x = 0.08 }, .x, .{
        .@"align" = .grid,
        .stem_width = .natural,
    }, 13, 0, &out);
    try testing.expectApproxEqAbs(@as(f32, 0.08), knots[1].target - knots[0].target, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 3.0 / 13.0), knots[0].target, 1e-5);
}

test "blue-zone overshoot can be preserved or suppressed" {
    const zones = [_]BlueZone{.{ .ref = 0.5, .shoot = 0.52 }};
    var features = [_]FeatureEdge{testFeature(0.52)};
    features[0].blue = 0;
    features[0].flags.round = true;
    const font = TestFontFeatures{ .blues = &zones };
    var preserve_out: [max_knots]Knot = undefined;
    var suppress_out: [max_knots]Knot = undefined;
    const preserved = fitAxis(&features, font, .y, .{ .@"align" = .blue_zones }, 13, 0, &preserve_out);
    const suppressed = fitAxis(&features, font, .y, .{
        .@"align" = .blue_zones,
        .overshoot = .{ .suppress_below_px = 0.5 },
    }, 13, 0, &suppress_out);
    try testing.expectApproxEqAbs(@as(f32, 7.0 / 13.0 + 0.02), preserved[0].target, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 7.0 / 13.0), suppressed[0].target, 1e-5);
}

test "fitGlyph scales axes independently" {
    var x = [_]FeatureEdge{testFeature(0.2)};
    var y = [_]FeatureEdge{testFeature(0.5)};
    x[0].blue = 0;
    y[0].blue = 0;
    const zones = [_]BlueZone{.{ .ref = 0.5, .shoot = 0.5 }};
    const glyph = .{ .x = x[0..], .y = y[0..], .left = @as(f32, 0) };
    var x_out: [max_knots]Knot = undefined;
    var y_out: [max_knots]Knot = undefined;
    const knots = fitGlyph(glyph, TestFontFeatures{ .blues = &zones }, .{
        .x = .{ .@"align" = .grid },
        .y = .{ .@"align" = .blue_zones },
    }, .{ .x = 0, .y = 13 }, &x_out, &y_out);
    try testing.expectEqual(@as(usize, 0), knots.x.len);
    try testing.expectEqual(@as(usize, 1), knots.y.len);
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
