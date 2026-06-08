//! Seven-lane subpixel coverage evaluation for the CPU backend.
//!
//! `evalGlyphCoverageSubpixel` is the entry point — it samples a glyph
//! at seven colocated subpixel positions arranged along the LCD-stripe
//! axis and returns the per-channel coverage after filtering. The
//! shared-state evaluators below group lanes by band cell so curves
//! touching multiple lanes are walked once, and exploit the fact that
//! one axis is constant across all seven samples (the LCD stripe axis)
//! to solve quadratics/lines exactly once per curve.
//!
//! All numerical helpers (curve solvers, distance accumulators, etc.)
//! live in the parent `coverage.zig` and are imported back through
//! `pub` re-exports.

const std = @import("std");
const snail = @import("../../../../root.zig");
const coverage = @import("../coverage.zig");
const subpixel = @import("subpixel.zig");
const cubic = @import("cubic_solver.zig");
const texture = @import("../texture.zig");
const band_tex = @import("../../../format/band_texture.zig");

const FillRule = snail.FillRule;
const Vec2 = snail.Vec2;
const GlyphBandEntry = band_tex.GlyphBandEntry;
const CoveragePair = coverage.CoveragePair;
const PreparedAxisCurve = coverage.PreparedAxisCurve;
const PreparedAxisCurveCold = coverage.PreparedAxisCurveCold;
const SubpixelCoverage = subpixel.SubpixelCoverage;
const SubpixelCoveragePlan = subpixel.SubpixelCoveragePlan;
const lane_count = coverage.subpixel_lane_count;
const calcRootCode = cubic.calcRootCode;
const readBandTexelLinear = texture.readBandTexelLinear;

pub fn evalGlyphCoverageSubpixel(
    page: anytype,
    rc: Vec2,
    plan: SubpixelCoveragePlan,
    be: GlyphBandEntry,
    band_max_h: i32,
    band_max_v: i32,
    fill_rule: FillRule,
) SubpixelCoverage {
    if (plan.order == .none) return .{ .rgb = .{ 0.0, 0.0, 0.0 }, .alpha = 0.0 };

    const W = lane_count;
    var em_x: [W]f32 = undefined;
    var em_y: [W]f32 = undefined;
    inline for (0..W) |k| {
        const offset: f32 = @as(f32, @floatFromInt(@as(i32, @intCast(k)) - 3));
        em_x[k] = rc.x + plan.step.x * offset;
        em_y[k] = rc.y + plan.step.y * offset;
    }

    var raw: [W]f32 = undefined;
    const Page = switch (@typeInfo(@TypeOf(page))) {
        .pointer => |ptr| ptr.child,
        else => @TypeOf(page),
    };
    if (comptime @hasField(Page, "h_curves")) {
        evalPreparedSamples(page, em_x, em_y, plan, be, band_max_h, band_max_v, fill_rule, &raw);
    } else {
        inline for (0..W) |k| {
            raw[k] = coverage.evalGlyphCoverage(page, em_x[k], em_y[k], plan.ppe.x, plan.ppe.y, be, band_max_h, band_max_v, fill_rule);
        }
    }

    return subpixel.filterCoverage(
        raw[0],
        raw[1],
        raw[2],
        raw[3],
        raw[4],
        raw[5],
        raw[6],
        plan.reverse_order,
    );
}

// Shared-state evaluation of the seven subpixel samples for a *prepared*
// atlas page. Groups samples by the band cell they fall into, so curves
// shared across lanes are walked once; for the axis whose root coordinate
// is identical across all lanes (the LCD-stripe axis), the quadratic and
// line solvers run a single time and the per-lane distance is just a fused
// `(base - sample_along[i]) * ppe`.
fn evalPreparedSamples(
    page: anytype,
    em_x: [lane_count]f32,
    em_y: [lane_count]f32,
    plan: SubpixelCoveragePlan,
    be: GlyphBandEntry,
    band_max_h: i32,
    band_max_v: i32,
    fill_rule: FillRule,
    out_cov: *[lane_count]f32,
) void {
    const W = lane_count;
    var h_pairs: [W]CoveragePair = @splat(CoveragePair{ .cov = 0, .wgt = 0 });
    var v_pairs: [W]CoveragePair = @splat(CoveragePair{ .cov = 0, .wgt = 0 });

    const glyph_band_base = @as(usize, be.glyph_y) * @as(usize, page.band_width) + @as(usize, be.glyph_x);

    var h_band_idx: [W]i32 = undefined;
    var v_band_idx: [W]i32 = undefined;
    inline for (0..W) |i| {
        const bx_f = em_x[i] * be.band_scale_x + be.band_offset_x;
        const by_f = em_y[i] * be.band_scale_y + be.band_offset_y;
        v_band_idx[i] = coverage.clampInt(@as(i32, @intFromFloat(@floor(bx_f))), 0, band_max_v);
        h_band_idx[i] = coverage.clampInt(@as(i32, @intFromFloat(@floor(by_f))), 0, band_max_h);
    }

    // RGB/BGR keep em_y constant across the 7 samples (stripes run vertical);
    // VRGB/VBGR keep em_x constant. Either way, the constant axis is the
    // "root-shared" axis of one of H/V.
    const h_root_shared = plan.step.y == 0.0;
    const v_root_shared = plan.step.x == 0.0;

    evalPreparedAxis(page, em_x, em_y, h_band_idx, glyph_band_base, 0, plan.ppe.x, h_root_shared, &h_pairs, true);
    evalPreparedAxis(page, em_x, em_y, v_band_idx, glyph_band_base, band_max_h + 1, plan.ppe.y, v_root_shared, &v_pairs, false);

    inline for (0..W) |i| {
        out_cov[i] = coverage.resolveCoverage(h_pairs[i], v_pairs[i], fill_rule);
    }
}

pub fn evalPreparedAxis(
    page: anytype,
    em_x: [lane_count]f32,
    em_y: [lane_count]f32,
    band_idx: [lane_count]i32,
    glyph_band_base: usize,
    header_base: i32,
    ppe: f32,
    root_shared: bool,
    results: *[lane_count]CoveragePair,
    comptime horizontal: bool,
) void {
    const W = lane_count;

    // Partition lanes by band cell. With W=7 the worst case is 7 distinct
    // bands, but for typical text we see 1 (constant axis) or 2-3 (varying
    // axis).
    var unique_bands: [W]i32 = undefined;
    var unique_masks: [W]u8 = .{0} ** W;
    var unique_count: usize = 0;
    inline for (0..W) |i| {
        const b = band_idx[i];
        var matched: ?usize = null;
        for (unique_bands[0..unique_count], 0..) |u, j| {
            if (u == b) {
                matched = j;
                break;
            }
        }
        if (matched) |j| {
            unique_masks[j] |= @as(u8, 1) << @intCast(i);
        } else {
            unique_bands[unique_count] = b;
            unique_masks[unique_count] = @as(u8, 1) << @intCast(i);
            unique_count += 1;
        }
    }

    const curves = if (horizontal) page.h_curves else page.v_curves;
    const cold_curves = if (horizontal) page.h_cold_curves else page.v_cold_curves;

    var u: usize = 0;
    while (u < unique_count) : (u += 1) {
        const band = unique_bands[u];
        const mask = unique_masks[u];
        const header_idx: i32 = header_base + band;
        if (header_idx < 0) continue;
        const header = readBandTexelLinear(page, glyph_band_base + @as(usize, @intCast(header_idx)));
        const band_base = glyph_band_base + header[1];
        if (band_base >= curves.len) continue;
        const band_count = @min(@as(usize, header[0]), curves.len - band_base);
        const band_curves = curves[band_base..][0..band_count];

        for (band_curves) |*curve| {
            if (!curve.valid) continue;
            accumulateCurveMulti(curve, cold_curves, em_x, em_y, mask, ppe, root_shared, results, horizontal);
        }
    }
}

inline fn accumulateCurveMulti(
    curve: *const PreparedAxisCurve,
    cold_curves: []const PreparedAxisCurveCold,
    em_x: [lane_count]f32,
    em_y: [lane_count]f32,
    mask: u8,
    ppe: f32,
    root_shared: bool,
    results: *[lane_count]CoveragePair,
    comptime horizontal: bool,
) void {
    if (root_shared and curve.kind == .quadratic) {
        accumulateQuadraticSharedRoot(curve, em_x, em_y, mask, ppe, results, horizontal);
        return;
    }
    if (root_shared and curve.kind == .line) {
        accumulateLineSharedRoot(curve, em_x, em_y, mask, ppe, results, horizontal);
        return;
    }

    // Varying root, or conic/cubic: scalar fan-out across active lanes. The
    // grouped header read above still saves redundant band lookups.
    const W = lane_count;
    inline for (0..W) |i| {
        if ((mask & (@as(u8, 1) << @intCast(i))) != 0) {
            const sample_rc = Vec2.new(em_x[i], em_y[i]);
            _ = coverage.accumulatePreparedCurveCoverage(&results[i], curve, cold_curves, sample_rc, ppe, horizontal);
        }
    }
}

// Shared-root quadratic: sample_root is identical across active lanes, so
// `calcRootCode` and `solvePreparedAxisQuadratic` produce one answer reused
// for every lane. Only the per-lane distance shift remains.
fn accumulateQuadraticSharedRoot(
    curve: *const PreparedAxisCurve,
    em_x: [lane_count]f32,
    em_y: [lane_count]f32,
    mask: u8,
    ppe: f32,
    results: *[lane_count]CoveragePair,
    comptime horizontal: bool,
) void {
    if (mask == 0) return;
    const W = lane_count;
    const first_lane: usize = @ctz(mask);
    const sample_root = if (horizontal) em_y[first_lane] else em_x[first_lane];

    const p0r = curve.p0_root - sample_root;
    const p1r = curve.p1_root - sample_root;
    const p2r = curve.p2_root - sample_root;
    const code = calcRootCode(p0r, p1r, p2r);
    if (code == 0) return;

    const roots = coverage.solvePreparedAxisQuadratic(curve, curve.p0_along, p0r, 1.0);
    const t1_along = roots[0];
    const t2_along = roots[1];

    if ((code & 1) != 0) {
        const sign: f32 = if (horizontal) 1.0 else -1.0;
        inline for (0..W) |i| {
            if ((mask & (@as(u8, 1) << @intCast(i))) != 0) {
                const sample_along = if (horizontal) em_x[i] else em_y[i];
                coverage.appendCoverageContribution(&results[i], (t1_along - sample_along) * ppe, sign);
            }
        }
    }
    if (code > 1) {
        const sign: f32 = if (horizontal) -1.0 else 1.0;
        inline for (0..W) |i| {
            if ((mask & (@as(u8, 1) << @intCast(i))) != 0) {
                const sample_along = if (horizontal) em_x[i] else em_y[i];
                coverage.appendCoverageContribution(&results[i], (t2_along - sample_along) * ppe, sign);
            }
        }
    }
}

fn accumulateLineSharedRoot(
    curve: *const PreparedAxisCurve,
    em_x: [lane_count]f32,
    em_y: [lane_count]f32,
    mask: u8,
    ppe: f32,
    results: *[lane_count]CoveragePair,
    comptime horizontal: bool,
) void {
    if (mask == 0) return;
    const W = lane_count;
    const first_lane: usize = @ctz(mask);
    const sample_root = if (horizontal) em_y[first_lane] else em_x[first_lane];

    const denom = curve.a_root;
    if (@abs(denom) < 1e-10) return;
    const t_raw = -(curve.p0_root - sample_root) / denom;
    if (t_raw < -1e-5 or t_raw > 1.0 + 1e-5) return;
    const t = std.math.clamp(t_raw, 0.0, 1.0);
    if (coverage.isNearEndRoot(t) and coverage.isEndpointRootDelta(curve.p0_root + curve.a_root - sample_root)) return;

    const derivative_axis = if (horizontal) curve.a_root else -curve.a_root;
    if (@abs(derivative_axis) <= 1e-5) return;
    const sign: f32 = if (derivative_axis > 0.0) 1.0 else -1.0;
    const along_at_t = curve.p0_along + curve.a_along * t;

    inline for (0..W) |i| {
        if ((mask & (@as(u8, 1) << @intCast(i))) != 0) {
            const sample_along = if (horizontal) em_x[i] else em_y[i];
            coverage.appendCoverageContribution(&results[i], (along_at_t - sample_along) * ppe, sign);
        }
    }
}
