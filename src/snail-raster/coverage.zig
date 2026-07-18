//! Curve coverage evaluation for the software rasterizer.

const std = @import("std");
const snail = @import("snail").core;
const color_mod = @import("color.zig");
const subpixel = @import("coverage/subpixel.zig");
const cubic = @import("coverage/cubic_solver.zig");
const texture = @import("texture.zig");
const band_tex = @import("snail").core.files.format_band_texture;
const render_abi = @import("snail").core.files.format_abi;

const bezier = @import("snail").core.files.math_bezier;
const curve_tex = @import("snail").core.files.format_curve_texture;
const CurveSegment = bezier.CurveSegment;
const FillRule = snail.FillRule;
const GlyphBandEntry = band_tex.GlyphBandEntry;
const Vec2 = snail.Vec2;
const clamp01 = color_mod.clamp01;
const decodeCurveSegment = texture.decodeCurveSegment;
const readBandCurveRef = texture.readBandCurveRef;
const readBandTexelLinear = texture.readBandTexelLinear;
const readCurveTexelF32Base = texture.readCurveTexelF32Base;

const invalid_prepared_cold = std.math.maxInt(u32);

// Coefficients only touched after the hot record identifies a curve as conic or cubic.
pub const PreparedAxisCurveCold = struct {
    cubic_a_root: f32 = 0.0,
    cubic_b_root: f32 = 0.0,
    cubic_c_root: f32 = 0.0,
    cubic_p3_root: f32 = 0.0,
    cubic_a_along: f32 = 0.0,
    cubic_b_along: f32 = 0.0,
    cubic_c_along: f32 = 0.0,
    cubic_p3_along: f32 = 0.0,
    conic_num_a_root: f32 = 0.0,
    conic_num_b_root: f32 = 0.0,
    conic_num_c_root: f32 = 0.0,
    conic_num_a_along: f32 = 0.0,
    conic_num_b_along: f32 = 0.0,
    conic_num_c_along: f32 = 0.0,
    conic_den_a: f32 = 0.0,
    conic_den_b: f32 = 0.0,
    conic_den_c: f32 = 0.0,

    fn fromSegment(segment: CurveSegment, comptime horizontal: bool) PreparedAxisCurveCold {
        const p0_root = if (horizontal) segment.p0.y else segment.p0.x;
        const p1_root = if (horizontal) segment.p1.y else segment.p1.x;
        const p2_root = if (horizontal) segment.p2.y else segment.p2.x;
        const p3_root = if (horizontal) segment.p3.y else segment.p3.x;
        const p0_along = if (horizontal) segment.p0.x else segment.p0.y;
        const p1_along = if (horizontal) segment.p1.x else segment.p1.y;
        const p2_along = if (horizontal) segment.p2.x else segment.p2.y;
        const p3_along = if (horizontal) segment.p3.x else segment.p3.y;

        const w0 = segment.weights[0];
        const w1 = segment.weights[1];
        const w2 = segment.weights[2];
        const p0_root_w = p0_root * w0;
        const p1_root_w = p1_root * w1;
        const p2_root_w = p2_root * w2;
        const p0_along_w = p0_along * w0;
        const p1_along_w = p1_along * w1;
        const p2_along_w = p2_along * w2;

        return .{
            .cubic_a_root = -p0_root + 3.0 * p1_root - 3.0 * p2_root + p3_root,
            .cubic_b_root = 3.0 * p0_root - 6.0 * p1_root + 3.0 * p2_root,
            .cubic_c_root = -3.0 * p0_root + 3.0 * p1_root,
            .cubic_p3_root = p3_root,
            .cubic_a_along = -p0_along + 3.0 * p1_along - 3.0 * p2_along + p3_along,
            .cubic_b_along = 3.0 * p0_along - 6.0 * p1_along + 3.0 * p2_along,
            .cubic_c_along = -3.0 * p0_along + 3.0 * p1_along,
            .cubic_p3_along = p3_along,
            .conic_num_a_root = p0_root_w - 2.0 * p1_root_w + p2_root_w,
            .conic_num_b_root = 2.0 * (p1_root_w - p0_root_w),
            .conic_num_c_root = p0_root_w,
            .conic_num_a_along = p0_along_w - 2.0 * p1_along_w + p2_along_w,
            .conic_num_b_along = 2.0 * (p1_along_w - p0_along_w),
            .conic_num_c_along = p0_along_w,
            .conic_den_a = w0 - 2.0 * w1 + w2,
            .conic_den_b = 2.0 * (w1 - w0),
            .conic_den_c = w0,
        };
    }
};

// Hot per-axis eval record laid out for scanline walking. Quadratic and line
// coverage use only this record; conic/cubic coefficients are indexed
// separately via cold_index. Numeric fields are at the front so a single
// loaded line covers every operand the hot solver touches.
pub const PreparedAxisCurve = struct {
    max_axis: f32 = 0.0,
    min_axis: f32 = 0.0,
    p0_root: f32 = 0.0,
    p1_root: f32 = 0.0,
    p2_root: f32 = 0.0,
    p0_along: f32 = 0.0,
    a_root: f32 = 0.0,
    b_root: f32 = 0.0,
    a_along: f32 = 0.0,
    b_along: f32 = 0.0,
    cold_index: u32 = invalid_prepared_cold,
    first_member_band: u16 = 0,
    valid: bool = false,
    kind: bezier.CurveKind = .quadratic,

    fn fromSegment(segment: CurveSegment, comptime horizontal: bool) PreparedAxisCurve {
        const p0_root = if (horizontal) segment.p0.y else segment.p0.x;
        const p1_root = if (horizontal) segment.p1.y else segment.p1.x;
        const p2_root = if (horizontal) segment.p2.y else segment.p2.x;
        const p0_along = if (horizontal) segment.p0.x else segment.p0.y;
        const p1_along = if (horizontal) segment.p1.x else segment.p1.y;
        const p2_along = if (horizontal) segment.p2.x else segment.p2.y;

        return .{
            .valid = true,
            .kind = segment.kind,
            .max_axis = if (horizontal) segmentMaxX(segment) else segmentMaxY(segment),
            .min_axis = if (horizontal) segmentMinX(segment) else segmentMinY(segment),
            .p0_root = p0_root,
            .p1_root = p1_root,
            .p2_root = p2_root,
            .p0_along = p0_along,
            .a_root = if (segment.kind == .line) p2_root - p0_root else p0_root - 2.0 * p1_root + p2_root,
            .b_root = p0_root - p1_root,
            .a_along = if (segment.kind == .line) p2_along - p0_along else p0_along - 2.0 * p1_along + p2_along,
            .b_along = p0_along - p1_along,
        };
    }
};

inline fn preparedAxisCurveNeedsCold(kind: bezier.CurveKind) bool {
    return kind == .conic or kind == .cubic;
}

pub fn prepareAxisCurve(
    allocator: std.mem.Allocator,
    cold_records: *std.ArrayList(PreparedAxisCurveCold),
    segment: CurveSegment,
    comptime horizontal: bool,
) !PreparedAxisCurve {
    var curve = PreparedAxisCurve.fromSegment(segment, horizontal);
    if (preparedAxisCurveNeedsCold(segment.kind)) {
        curve.cold_index = @intCast(cold_records.items.len);
        try cold_records.append(allocator, PreparedAxisCurveCold.fromSegment(segment, horizontal));
    }
    return curve;
}

// ---------------------------------------------------------------------------
// Slug algorithm: CPU port of evalGlyphCoverage from shaders.zig
// ---------------------------------------------------------------------------

pub const CoveragePair = struct {
    cov: f32,
    wgt: f32,
};

pub const HintedTextRecord = struct {
    data: []const f32,
    width: u32,
    info_x: u16,
    info_y: u16,
    base_curve_texel: u32,
    curve_count: u16,
    flags: u16 = 0,
    h_band_pad: u16 = 0,
    v_band_pad: u16 = 0,

    fn hasExpandedBands(self: HintedTextRecord) bool {
        return (self.flags & render_abi.hint_record_flag_expanded_bands) != 0;
    }

    fn hasUnorderedBands(self: HintedTextRecord) bool {
        return (self.flags & render_abi.hint_record_flag_unordered_bands) != 0;
    }
};

const GlyphBandState = struct {
    h_base: usize,
    h_count: u32,
    v_base: usize,
    v_count: u32,
};

pub const SubpixelCoverage = subpixel.SubpixelCoverage;
pub const SubpixelCoveragePlan = subpixel.SubpixelCoveragePlan;

const CurveRoots = cubic.CurveRoots;

fn applyFillRule(fill_rule: FillRule, winding: f32) f32 {
    if (fill_rule == .even_odd) {
        const x = winding * 0.5;
        const frac = x - @floor(x);
        return 1.0 - @abs(frac * 2.0 - 1.0);
    }
    return @abs(winding);
}

pub fn resolveCoverage(horiz: CoveragePair, vert: CoveragePair, fill_rule: FillRule) f32 {
    const wsum = horiz.wgt + vert.wgt;
    const blended = horiz.cov * horiz.wgt + vert.cov * vert.wgt;
    const cov = @max(
        applyFillRule(fill_rule, blended / @max(wsum, 1.0 / 65536.0)),
        @min(applyFillRule(fill_rule, horiz.cov), applyFillRule(fill_rule, vert.cov)),
    );
    return clamp01(cov);
}

pub fn premultiplyCoverage(color: [4]f32, cov: f32) [4]f32 {
    const alpha = color[3] * cov;
    return .{
        color[0] * alpha,
        color[1] * alpha,
        color[2] * alpha,
        alpha,
    };
}

pub const premultiplySubpixelCoverage = subpixel.premultiplySubpixelCoverage;
pub const subpixelBlendCoverage = subpixel.subpixelBlendCoverage;
pub const compositeSubpixelOver = subpixel.compositeSubpixelOver;

fn initGlyphBandState(
    page: anytype,
    em_x: f32,
    em_y: f32,
    be: GlyphBandEntry,
    band_max_h: i32,
    band_max_v: i32,
) GlyphBandState {
    const band_idx_x_f = em_x * be.band_scale_x + be.band_offset_x;
    const band_idx_y_f = em_y * be.band_scale_y + be.band_offset_y;
    const band_idx_x = clampInt(@as(i32, @intFromFloat(@floor(band_idx_x_f))), 0, band_max_v);
    const band_idx_y = clampInt(@as(i32, @intFromFloat(@floor(band_idx_y_f))), 0, band_max_h);
    const glyph_x = @as(u32, be.glyph_x);
    const glyph_y = @as(u32, be.glyph_y);
    const glyph_band_base = @as(usize, glyph_y) * @as(usize, page.band_width) + @as(usize, glyph_x);

    const h_header = readBandTexelLinear(page, glyph_band_base + @as(usize, @intCast(band_idx_y)));
    const v_header = readBandTexelLinear(page, glyph_band_base + @as(usize, @intCast(band_max_h)) + 1 + @as(usize, @intCast(band_idx_x)));
    return .{
        .h_base = glyph_band_base + h_header[1],
        .h_count = h_header[0],
        .v_base = glyph_band_base + v_header[1],
        .v_count = v_header[0],
    };
}

const solveQuadraticRoots = cubic.solveQuadraticRoots;
const solveMonotonicCubicCrossing = cubic.solveMonotonicCubicCrossing;
const solveSegmentHorizontalRoots = cubic.solveSegmentHorizontalRoots;
const solveSegmentVerticalRoots = cubic.solveSegmentVerticalRoots;
const segmentMaxX = cubic.segmentMaxX;
const segmentMaxY = cubic.segmentMaxY;
const segmentMinX = cubic.segmentMinX;
const segmentMinY = cubic.segmentMinY;

pub fn appendCoverageContribution(result: *CoveragePair, distance: f32, sign: f32) void {
    result.cov += sign * clamp01(distance + 0.5);
    result.wgt = @max(result.wgt, clamp01(1.0 - @abs(distance) * 2.0));
}

const root_code_eps = cubic.root_code_eps;
const snapNearTangentSqrt = cubic.snapNearTangentSqrt;
const calcRootCode = cubic.calcRootCode;
const solveHorizPoly = cubic.solveHorizPoly;
const solveVertPoly = cubic.solveVertPoly;

pub inline fn isNearEndRoot(t: f32) bool {
    return t >= 1.0 - 1e-5;
}

pub inline fn isEndpointRootDelta(end_root_delta: f32) bool {
    return @abs(end_root_delta) <= root_code_eps;
}

inline fn isHalfOpenEndpointRoot(t: f32, end_root_delta: f32) bool {
    return isNearEndRoot(t) and isEndpointRootDelta(end_root_delta);
}

inline fn rootHullCanCross3(p0: f32, p1: f32, p2: f32, sample_root: f32) bool {
    const min_root = @min(@min(p0, p1), p2);
    const max_root = @max(@max(p0, p1), p2);
    return min_root - sample_root <= root_code_eps and max_root - sample_root >= -root_code_eps;
}

inline fn rootHullCanCross4(p0: f32, p1: f32, p2: f32, p3: f32, sample_root: f32) bool {
    const min_root = @min(@min(p0, p1), @min(p2, p3));
    const max_root = @max(@max(p0, p1), @max(p2, p3));
    return min_root - sample_root <= root_code_eps and max_root - sample_root >= -root_code_eps;
}

test "half-open endpoint guard preserves near-end interior roots" {
    try std.testing.expect(isHalfOpenEndpointRoot(1.0, 0.0));
    try std.testing.expect(isHalfOpenEndpointRoot(1.0 - 5e-6, root_code_eps * 0.5));
    try std.testing.expect(!isHalfOpenEndpointRoot(1.0 - 5e-6, root_code_eps * 2.0));
    try std.testing.expect(!isHalfOpenEndpointRoot(1.0 - 2e-5, 0.0));
}

const CoverageScan = enum {
    continue_scan,
    stop_scan,
};

inline fn accumulateQuadraticCoverage(
    result: *CoveragePair,
    p0x: f32,
    p0y: f32,
    p1x: f32,
    p1y: f32,
    p2x: f32,
    p2y: f32,
    ppe: f32,
    comptime horizontal: bool,
) void {
    const code = if (horizontal)
        calcRootCode(p0y, p1y, p2y)
    else
        calcRootCode(p0x, p1x, p2x);
    if (code == 0) return;

    const roots = if (horizontal)
        solveHorizPoly(p0x, p0y, p1x, p1y, p2x, p2y, ppe)
    else
        solveVertPoly(p0x, p0y, p1x, p1y, p2x, p2y, ppe);

    if ((code & 1) != 0) {
        appendCoverageContribution(result, roots[0], if (horizontal) 1.0 else -1.0);
    }
    if (code > 1) {
        appendCoverageContribution(result, roots[1], if (horizontal) -1.0 else 1.0);
    }
}

inline fn accumulateLineCoverage(
    result: *CoveragePair,
    p0x: f32,
    p0y: f32,
    p2x: f32,
    p2y: f32,
    ppe: f32,
    comptime horizontal: bool,
) void {
    const root_axis0 = if (horizontal) p0y else p0x;
    const root_axis2 = if (horizontal) p2y else p2x;
    const denom = root_axis2 - root_axis0;
    if (@abs(denom) < 1e-10) return;

    const t_raw = -root_axis0 / denom;
    if (t_raw < -1e-5 or t_raw > 1.0 + 1e-5) return;
    const t = std.math.clamp(t_raw, 0.0, 1.0);
    if (isNearEndRoot(t) and isEndpointRootDelta(root_axis2)) return;

    const derivative_axis = if (horizontal) p2y - p0y else p0x - p2x;
    if (@abs(derivative_axis) <= 1e-5) return;

    const distance = if (horizontal)
        (p0x + (p2x - p0x) * t) * ppe
    else
        (p0y + (p2y - p0y) * t) * ppe;
    appendCoverageContribution(result, distance, if (derivative_axis > 0.0) 1.0 else -1.0);
}

inline fn accumulateGlyphCoverageSegment(
    result: *CoveragePair,
    segment: CurveSegment,
    sample_rc: Vec2,
    ppe: f32,
    comptime horizontal: bool,
) CoverageScan {
    const max_x = segmentMaxX(segment);
    const max_y = segmentMaxY(segment);
    const max_coord = if (horizontal) max_x - sample_rc.x else max_y - sample_rc.y;
    if (max_coord * ppe < -0.5) return .stop_scan;

    if (segment.kind == .quadratic) {
        const p0x = segment.p0.x - sample_rc.x;
        const p0y = segment.p0.y - sample_rc.y;
        const p1x = segment.p1.x - sample_rc.x;
        const p1y = segment.p1.y - sample_rc.y;
        const p2x = segment.p2.x - sample_rc.x;
        const p2y = segment.p2.y - sample_rc.y;
        accumulateQuadraticCoverage(result, p0x, p0y, p1x, p1y, p2x, p2y, ppe, horizontal);
        return .continue_scan;
    }

    if (segment.kind == .line) {
        accumulateLineCoverage(
            result,
            segment.p0.x - sample_rc.x,
            segment.p0.y - sample_rc.y,
            segment.p2.x - sample_rc.x,
            segment.p2.y - sample_rc.y,
            ppe,
            horizontal,
        );
        return .continue_scan;
    }

    switch (segment.kind) {
        .conic => {
            const p0 = if (horizontal) segment.p0.y else segment.p0.x;
            const p1 = if (horizontal) segment.p1.y else segment.p1.x;
            const p2 = if (horizontal) segment.p2.y else segment.p2.x;
            const sample_root = if (horizontal) sample_rc.y else sample_rc.x;
            if (!rootHullCanCross3(p0, p1, p2, sample_root)) return .continue_scan;
        },
        .cubic => {
            const p0 = if (horizontal) segment.p0.y else segment.p0.x;
            const p1 = if (horizontal) segment.p1.y else segment.p1.x;
            const p2 = if (horizontal) segment.p2.y else segment.p2.x;
            const p3 = if (horizontal) segment.p3.y else segment.p3.x;
            const sample_root = if (horizontal) sample_rc.y else sample_rc.x;
            if (!rootHullCanCross4(p0, p1, p2, p3, sample_root)) return .continue_scan;
        },
        .quadratic, .line => unreachable,
    }

    const roots = if (horizontal)
        solveSegmentHorizontalRoots(segment, sample_rc.y)
    else
        solveSegmentVerticalRoots(segment, sample_rc.x);

    for (roots.t[0..roots.count]) |t| {
        if (segment.kind != .cubic and isNearEndRoot(t)) {
            const end_root_delta = switch (segment.kind) {
                .conic, .quadratic, .line => if (horizontal) segment.p2.y - sample_rc.y else segment.p2.x - sample_rc.x,
                .cubic => unreachable,
            };
            if (isEndpointRootDelta(end_root_delta)) continue;
        }
        const point = if (segment.kind == .cubic and t == 1.0) segment.p3 else segment.evaluate(t);
        const derivative_axis = if (segment.kind == .cubic) blk: {
            // Packed cubics are split into monotonic spans.  Their winding
            // direction is therefore determined by the span endpoints, even
            // when the crossing is a stationary inflection (or merely has a
            // very small derivative after path normalization).  A fixed
            // derivative epsilon is coordinate-scale dependent and used to
            // drop these valid crossings.
            break :blk if (horizontal)
                segment.p3.y - segment.p0.y
            else
                segment.p0.x - segment.p3.x;
        } else blk: {
            const deriv = segment.derivative(t);
            break :blk if (horizontal) deriv.y else -deriv.x;
        };
        if (segment.kind != .cubic and @abs(derivative_axis) <= 1e-5) continue;
        const distance = if (horizontal)
            (point.x - sample_rc.x) * ppe
        else
            (point.y - sample_rc.y) * ppe;
        appendCoverageContribution(result, distance, if (derivative_axis > 0.0) 1.0 else -1.0);
    }
    return .continue_scan;
}

pub inline fn solvePreparedAxisQuadratic(curve: *const PreparedAxisCurve, p0_along: f32, p0_root: f32, ppe: f32) [2]f32 {
    const ax = curve.a_along;
    const ay = curve.a_root;
    const bx = curve.b_along;
    const by = curve.b_root;
    const eps: f32 = 1.0 / 65536.0;

    var t1: f32 = undefined;
    var t2: f32 = undefined;

    if (@abs(ay) < eps) {
        t1 = if (@abs(by) < eps) 0.0 else p0_root * 0.5 / by;
        t2 = t1;
    } else {
        const sq = snapNearTangentSqrt(by * by - ay * p0_root, by, ay * p0_root);
        if (by >= 0.0) {
            const q = by + sq;
            t2 = q / ay;
            t1 = if (@abs(q) < eps) 0.0 else p0_root / q;
        } else {
            const q = by - sq;
            t1 = q / ay;
            t2 = if (@abs(q) < eps) 0.0 else p0_root / q;
        }
    }

    const d1 = (ax * t1 - bx * 2.0) * t1 + p0_along;
    const d2 = (ax * t2 - bx * 2.0) * t2 + p0_along;
    return .{ d1 * ppe, d2 * ppe };
}

inline fn accumulatePreparedQuadraticCoverage(
    result: *CoveragePair,
    curve: *const PreparedAxisCurve,
    sample_root: f32,
    sample_along: f32,
    ppe: f32,
    comptime horizontal: bool,
) void {
    const p0_root = curve.p0_root - sample_root;
    const p1_root = curve.p1_root - sample_root;
    const p2_root = curve.p2_root - sample_root;
    const code = calcRootCode(p0_root, p1_root, p2_root);
    if (code == 0) return;

    const roots = solvePreparedAxisQuadratic(curve, curve.p0_along - sample_along, p0_root, ppe);

    if ((code & 1) != 0) {
        appendCoverageContribution(result, roots[0], if (horizontal) 1.0 else -1.0);
    }
    if (code > 1) {
        appendCoverageContribution(result, roots[1], if (horizontal) -1.0 else 1.0);
    }
}

inline fn accumulatePreparedLineCoverage(
    result: *CoveragePair,
    curve: *const PreparedAxisCurve,
    sample_root: f32,
    sample_along: f32,
    ppe: f32,
    comptime horizontal: bool,
) void {
    const denom = curve.a_root;
    if (@abs(denom) < 1e-10) return;

    const t_raw = -(curve.p0_root - sample_root) / denom;
    if (t_raw < -1e-5 or t_raw > 1.0 + 1e-5) return;
    const t = std.math.clamp(t_raw, 0.0, 1.0);
    if (isNearEndRoot(t) and isEndpointRootDelta(curve.p0_root + curve.a_root - sample_root)) return;

    const derivative_axis = if (horizontal) curve.a_root else -curve.a_root;
    if (@abs(derivative_axis) <= 1e-5) return;

    const distance = (curve.p0_along - sample_along + curve.a_along * t) * ppe;
    appendCoverageContribution(result, distance, if (derivative_axis > 0.0) 1.0 else -1.0);
}

inline fn solvePreparedConicRoots(cold: *const PreparedAxisCurveCold, sample_root: f32) CurveRoots {
    return solveQuadraticRoots(
        cold.conic_num_a_root - sample_root * cold.conic_den_a,
        cold.conic_num_b_root - sample_root * cold.conic_den_b,
        cold.conic_num_c_root - sample_root * cold.conic_den_c,
    );
}

inline fn solvePreparedCubicRoots(curve: *const PreparedAxisCurve, cold: *const PreparedAxisCurveCold, sample_root: f32) CurveRoots {
    return solveMonotonicCubicCrossing(
        cold.cubic_a_root,
        cold.cubic_b_root,
        cold.cubic_c_root,
        curve.p0_root - sample_root,
        cold.cubic_p3_root - sample_root,
    );
}

inline fn evaluatePreparedConicAlong(cold: *const PreparedAxisCurveCold, t: f32) f32 {
    const denom = @max((cold.conic_den_a * t + cold.conic_den_b) * t + cold.conic_den_c, 1.0 / 65536.0);
    return ((cold.conic_num_a_along * t + cold.conic_num_b_along) * t + cold.conic_num_c_along) / denom;
}

inline fn derivativePreparedConicRoot(cold: *const PreparedAxisCurveCold, t: f32) f32 {
    const denom = @max((cold.conic_den_a * t + cold.conic_den_b) * t + cold.conic_den_c, 1.0 / 65536.0);
    const denom_prime = 2.0 * cold.conic_den_a * t + cold.conic_den_b;
    const n = (cold.conic_num_a_root * t + cold.conic_num_b_root) * t + cold.conic_num_c_root;
    const n_prime = 2.0 * cold.conic_num_a_root * t + cold.conic_num_b_root;
    const inv = 1.0 / (denom * denom);
    return (n_prime * denom - n * denom_prime) * inv;
}

inline fn evaluatePreparedCubicAlong(curve: *const PreparedAxisCurve, cold: *const PreparedAxisCurveCold, t: f32) f32 {
    if (t == 1.0) return cold.cubic_p3_along;
    return ((cold.cubic_a_along * t + cold.cubic_b_along) * t + cold.cubic_c_along) * t + curve.p0_along;
}

fn preparedCurveCold(curve: *const PreparedAxisCurve, cold_curves: []const PreparedAxisCurveCold) *const PreparedAxisCurveCold {
    if (curve.cold_index >= cold_curves.len) {
        @panic("prepared conic/cubic curve is missing cold coefficient data");
    }
    return &cold_curves[curve.cold_index];
}

pub inline fn accumulatePreparedCurveCoverage(
    result: *CoveragePair,
    curve: *const PreparedAxisCurve,
    cold_curves: []const PreparedAxisCurveCold,
    sample_rc: Vec2,
    ppe: f32,
    comptime horizontal: bool,
) CoverageScan {
    const sample_root = if (horizontal) sample_rc.y else sample_rc.x;
    const sample_along = if (horizontal) sample_rc.x else sample_rc.y;
    const max_coord = curve.max_axis - sample_along;
    if (max_coord * ppe < -0.5) return .stop_scan;

    // Saturated-above fast path: when the whole curve sits at least 0.5/ppe
    // past the sample along its along-axis, every crossing's distance is > 0.5
    // and `clamp01(distance + 0.5)` returns 1; `appendCoverageContribution`
    // would then just add ±1 to result.cov and leave wgt alone. Skip the sqrt
    // and divisions; we only need to know whether each potential root lies in
    // [0, 1] (calcRootCode does that with three sign-bit extracts).
    const min_coord = curve.min_axis - sample_along;
    const above = min_coord * ppe > 0.5;

    if (curve.kind == .quadratic) {
        if (above) {
            const p0r = curve.p0_root - sample_root;
            const p1r = curve.p1_root - sample_root;
            const p2r = curve.p2_root - sample_root;
            const code = calcRootCode(p0r, p1r, p2r);
            if (code == 0) return .continue_scan;
            const sign_first: f32 = if (horizontal) 1.0 else -1.0;
            const sign_second: f32 = if (horizontal) -1.0 else 1.0;
            if ((code & 1) != 0) result.cov += sign_first;
            if (code > 1) result.cov += sign_second;
            return .continue_scan;
        }
        accumulatePreparedQuadraticCoverage(result, curve, sample_root, sample_along, ppe, horizontal);
        return .continue_scan;
    }

    if (curve.kind == .line) {
        accumulatePreparedLineCoverage(
            result,
            curve,
            sample_root,
            sample_along,
            ppe,
            horizontal,
        );
        return .continue_scan;
    }

    if (curve.kind == .conic and !rootHullCanCross3(curve.p0_root, curve.p1_root, curve.p2_root, sample_root)) {
        return .continue_scan;
    }

    const cold = preparedCurveCold(curve, cold_curves);
    if (curve.kind == .cubic) {
        if (!rootHullCanCross4(curve.p0_root, curve.p1_root, curve.p2_root, cold.cubic_p3_root, sample_root)) return .continue_scan;
    }

    const roots = switch (curve.kind) {
        .conic => solvePreparedConicRoots(cold, sample_root),
        .cubic => solvePreparedCubicRoots(curve, cold, sample_root),
        .quadratic, .line => unreachable,
    };
    for (roots.t[0..roots.count]) |t| {
        if (curve.kind != .cubic and isNearEndRoot(t)) {
            const end_root = switch (curve.kind) {
                .conic => curve.p2_root,
                .cubic => unreachable,
                .quadratic, .line => unreachable,
            };
            if (isEndpointRootDelta(end_root - sample_root)) continue;
        }
        const along = switch (curve.kind) {
            .conic => evaluatePreparedConicAlong(cold, t),
            .cubic => evaluatePreparedCubicAlong(curve, cold, t),
            .quadratic, .line => unreachable,
        };
        const root_deriv = switch (curve.kind) {
            .conic => derivativePreparedConicRoot(cold, t),
            // Cubics are monotonic spans, so endpoint direction is the
            // scale-invariant winding sign.  Do not reject a valid crossing
            // because normalization made its local derivative tiny.
            .cubic => cold.cubic_p3_root - curve.p0_root,
            .quadratic, .line => unreachable,
        };
        const derivative_axis = if (horizontal) root_deriv else -root_deriv;
        if (curve.kind != .cubic and @abs(derivative_axis) <= 1e-5) continue;
        const distance = (along - sample_along) * ppe;
        appendCoverageContribution(result, distance, if (derivative_axis > 0.0) 1.0 else -1.0);
    }
    return .continue_scan;
}

fn evalPreparedGlyphCoverageAxisFromBand(page: anytype, sample_rc: Vec2, ppe: f32, band_base: usize, count: u32, comptime horizontal: bool) CoveragePair {
    var result = CoveragePair{ .cov = 0.0, .wgt = 0.0 };
    const curves = if (horizontal) page.h_curves else page.v_curves;
    const cold_curves = if (horizontal) page.h_cold_curves else page.v_cold_curves;
    if (band_base >= curves.len) return result;
    const band_count = @min(@as(usize, count), curves.len - band_base);
    const band_curves = curves[band_base..][0..band_count];

    var i: usize = 0;
    while (i < band_count) : (i += 1) {
        const curve = &band_curves[i];
        if (!curve.valid) continue;
        if (accumulatePreparedCurveCoverage(&result, curve, cold_curves, sample_rc, ppe, horizontal) == .stop_scan) break;
    }
    return result;
}

fn evalGlyphCoverageAxis(page: anytype, sample_rc: Vec2, ppe: f32, band_base: usize, count: u32, comptime horizontal: bool) CoveragePair {
    const Page = switch (@typeInfo(@TypeOf(page))) {
        .pointer => |ptr| ptr.child,
        else => @TypeOf(page),
    };
    if (comptime @hasField(Page, "h_curves")) {
        return evalPreparedGlyphCoverageAxisFromBand(page, sample_rc, ppe, band_base, count, horizontal);
    }
    return evalGenericGlyphCoverageAxisFromBand(page, sample_rc, ppe, band_base, count, horizontal);
}

fn evalGenericGlyphCoverageAxisFromBand(page: anytype, sample_rc: Vec2, ppe: f32, band_base: usize, count: u32, comptime horizontal: bool) CoveragePair {
    var result = CoveragePair{ .cov = 0.0, .wgt = 0.0 };
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        const curve_ref = readBandCurveRef(page, band_base + i) orelse continue;
        if (accumulateGenericCurveCoverage(&result, page, curve_ref.base, sample_rc, ppe, horizontal) == .stop_scan) break;
    }
    return result;
}

fn accumulateGenericCurveCoverage(result: *CoveragePair, page: anytype, curve_base: usize, sample_rc: Vec2, ppe: f32, comptime horizontal: bool) CoverageScan {
    const tex0 = readCurveTexelF32Base(page, curve_base);
    const tex1 = readCurveTexelF32Base(page, curve_base + 4);
    const tex2 = readCurveTexelF32Base(page, curve_base + 8);
    const stored_kind = tex2[2];

    const direct_quadratic = stored_kind >= curve_tex.DIRECT_ENCODING_KIND_BIAS - 0.5 and
        stored_kind < curve_tex.DIRECT_ENCODING_KIND_BIAS + 0.5;
    if (stored_kind < 0.5 or direct_quadratic) {
        return accumulateEncodedQuadraticCoverage(result, tex0, tex1, sample_rc, ppe, direct_quadratic, horizontal);
    }

    const direct_line = stored_kind >= curve_tex.DIRECT_ENCODING_KIND_BIAS + 2.5 and
        stored_kind < curve_tex.DIRECT_ENCODING_KIND_BIAS + 3.5;
    if ((stored_kind >= 2.5 and stored_kind < 3.5) or direct_line) {
        return accumulateEncodedLineCoverage(result, tex0, tex1, sample_rc, ppe, direct_line, horizontal);
    }

    const meta = readCurveTexelF32Base(page, curve_base + 12);
    return accumulateGlyphCoverageSegment(result, decodeCurveSegment(tex0, tex1, tex2, meta), sample_rc, ppe, horizontal);
}

fn hintedCurveIndex(record: HintedTextRecord, curve_base: usize) ?u32 {
    const curve_texel = @as(u32, @intCast(curve_base / 4));
    if (curve_texel < record.base_curve_texel) return null;
    const delta = curve_texel - record.base_curve_texel;
    if (delta % curve_tex.SEGMENT_TEXELS != 0) return null;
    const index = delta / curve_tex.SEGMENT_TEXELS;
    if (index >= record.curve_count) return null;
    return index;
}

fn hintedLayerTexel(record: HintedTextRecord, offset: u32) [4]f32 {
    if (record.width == 0) return .{ 0, 0, 0, 0 };
    const texel = @as(u32, record.info_y) * record.width + @as(u32, record.info_x) + offset;
    const base = @as(usize, texel) * 4;
    if (base + 3 >= record.data.len) return .{ 0, 0, 0, 0 };
    return .{
        record.data[base + 0],
        record.data[base + 1],
        record.data[base + 2],
        record.data[base + 3],
    };
}

// Read absolute hinted control points for the curve at this index out of
// the snapshot's layer-info slab. Matches `fetchHintedQuadratic` in the
// GPU hinted shader: no base-outline fetch, two texels per curve, p3 is
// retained for parity with `CurveSegment` but always zero for quadratics.
fn hintedSegment(record: HintedTextRecord, curve_base: usize) CurveSegment {
    var out = CurveSegment{
        .kind = .quadratic,
        .p0 = .zero,
        .p1 = .zero,
        .p2 = .zero,
        .p3 = .zero,
    };
    const curve_index = hintedCurveIndex(record, curve_base) orelse return out;
    const point_offset = 3 + curve_index * 2;
    const pts0 = hintedLayerTexel(record, point_offset);
    const pts1 = hintedLayerTexel(record, point_offset + 1);
    out.p0 = .{ .x = pts0[0], .y = pts0[1] };
    out.p1 = .{ .x = pts0[2], .y = pts0[3] };
    out.p2 = .{ .x = pts1[0], .y = pts1[1] };
    out.p3 = .{ .x = pts1[2], .y = pts1[3] };
    return out;
}

fn accumulateHintedCurveCoverage(
    result: *CoveragePair,
    record: HintedTextRecord,
    curve_base: usize,
    sample_rc: Vec2,
    ppe: f32,
    comptime horizontal: bool,
) CoverageScan {
    return accumulateGlyphCoverageSegment(result, hintedSegment(record, curve_base), sample_rc, ppe, horizontal);
}

fn accumulateEncodedQuadraticCoverage(result: *CoveragePair, tex0: [4]f32, tex1: [4]f32, sample_rc: Vec2, ppe: f32, direct: bool, comptime horizontal: bool) CoverageScan {
    const p0_abs = if (direct)
        Vec2.new(tex0[0], tex0[1])
    else
        Vec2.new(
            tex0[0] * curve_tex.PACKED_ANCHOR_CHUNK_EXTENT + tex0[2],
            tex0[1] * curve_tex.PACKED_ANCHOR_CHUNK_EXTENT + tex0[3],
        );
    const p1_abs = if (direct) Vec2.new(tex0[2], tex0[3]) else Vec2.new(p0_abs.x + tex1[0], p0_abs.y + tex1[1]);
    const p2_abs = if (direct) Vec2.new(tex1[0], tex1[1]) else Vec2.new(p0_abs.x + tex1[2], p0_abs.y + tex1[3]);
    const p0x = p0_abs.x - sample_rc.x;
    const p0y = p0_abs.y - sample_rc.y;
    const p1x = p1_abs.x - sample_rc.x;
    const p1y = p1_abs.y - sample_rc.y;
    const p2x = p2_abs.x - sample_rc.x;
    const p2y = p2_abs.y - sample_rc.y;
    const max_coord = if (horizontal) @max(@max(p0x, p1x), p2x) else @max(@max(p0y, p1y), p2y);
    if (max_coord * ppe < -0.5) return .stop_scan;
    accumulateQuadraticCoverage(result, p0x, p0y, p1x, p1y, p2x, p2y, ppe, horizontal);
    return .continue_scan;
}

fn accumulateEncodedLineCoverage(result: *CoveragePair, tex0: [4]f32, tex1: [4]f32, sample_rc: Vec2, ppe: f32, direct: bool, comptime horizontal: bool) CoverageScan {
    const p0_abs = if (direct)
        Vec2.new(tex0[0], tex0[1])
    else
        Vec2.new(
            tex0[0] * curve_tex.PACKED_ANCHOR_CHUNK_EXTENT + tex0[2],
            tex0[1] * curve_tex.PACKED_ANCHOR_CHUNK_EXTENT + tex0[3],
        );
    const p2_abs = if (direct) Vec2.new(tex1[0], tex1[1]) else Vec2.new(p0_abs.x + tex1[2], p0_abs.y + tex1[3]);
    const p0x = p0_abs.x - sample_rc.x;
    const p0y = p0_abs.y - sample_rc.y;
    const p2x = p2_abs.x - sample_rc.x;
    const p2y = p2_abs.y - sample_rc.y;
    const max_coord = if (horizontal) @max(p0x, p2x) else @max(p0y, p2y);
    if (max_coord * ppe < -0.5) return .stop_scan;
    accumulateLineCoverage(result, p0x, p0y, p2x, p2y, ppe, horizontal);
    return .continue_scan;
}

const BandSpan = struct {
    first: i32,
    last: i32,
};

fn coverageBandSpan(coord: f32, epp_axis: f32, band_scale: f32, band_offset: f32, band_max: i32) BandSpan {
    if (band_max < 0) return .{ .first = 0, .last = -1 };
    const center = coord * band_scale + band_offset;
    // Match the path shader: evaluate every band touched by the pixel
    // footprint, then de-duplicate curve records across the span.
    const half_width = @max(@abs(epp_axis * band_scale) * 0.5, 1e-5);
    const first = clampInt(@as(i32, @intFromFloat(@floor(center - half_width))), 0, band_max);
    const last = clampInt(@as(i32, @intFromFloat(@floor(center + half_width))), 0, band_max);
    return .{ .first = first, .last = @max(first, last) };
}

fn expandBandSpan(span: BandSpan, pad: u16, band_max: i32) BandSpan {
    if (span.first > span.last or band_max < 0) return span;
    const pad_i: i32 = @intCast(pad);
    return .{
        .first = clampInt(span.first - pad_i, 0, band_max),
        .last = clampInt(span.last + pad_i, 0, band_max),
    };
}

fn isBandSpanOwner(first_member: u32, band: i32, first_span_band: i32) bool {
    const first_member_band: i32 = @intCast(first_member);
    return band == @max(first_member_band, first_span_band);
}

fn evalPreparedGlyphCoverageAxisBandSpan(
    page: anytype,
    sample_rc: Vec2,
    ppe: f32,
    glyph_band_base: usize,
    header_base: i32,
    span: BandSpan,
    comptime horizontal: bool,
) CoveragePair {
    var result = CoveragePair{ .cov = 0.0, .wgt = 0.0 };
    if (span.first > span.last) return result;
    const curves = if (horizontal) page.h_curves else page.v_curves;
    const cold_curves = if (horizontal) page.h_cold_curves else page.v_cold_curves;
    const dedup = span.first != span.last;

    var band = span.first;
    while (band <= span.last) : (band += 1) {
        const header = readBandTexelLinear(page, glyph_band_base + @as(usize, @intCast(header_base + band)));
        const band_base = glyph_band_base + header[1];
        if (band_base >= curves.len) continue;
        const band_count = @min(@as(usize, header[0]), curves.len - band_base);
        const band_curves = curves[band_base..][0..band_count];

        var i: usize = 0;
        while (i < band_count) : (i += 1) {
            const curve = &band_curves[i];
            if (!curve.valid) continue;
            if (dedup and !isBandSpanOwner(curve.first_member_band, band, span.first)) continue;
            if (accumulatePreparedCurveCoverage(&result, curve, cold_curves, sample_rc, ppe, horizontal) == .stop_scan) break;
        }
    }
    return result;
}

fn evalGenericGlyphCoverageAxisBandSpan(
    page: anytype,
    sample_rc: Vec2,
    ppe: f32,
    glyph_band_base: usize,
    header_base: i32,
    span: BandSpan,
    comptime horizontal: bool,
) CoveragePair {
    var result = CoveragePair{ .cov = 0.0, .wgt = 0.0 };
    if (span.first > span.last) return result;
    const dedup = span.first != span.last;

    var band = span.first;
    while (band <= span.last) : (band += 1) {
        const header = readBandTexelLinear(page, glyph_band_base + @as(usize, @intCast(header_base + band)));
        const band_base = glyph_band_base + header[1];
        var i: u32 = 0;
        while (i < header[0]) : (i += 1) {
            const curve_ref = readBandCurveRef(page, band_base + i) orelse continue;
            if (dedup and !isBandSpanOwner(curve_ref.first_member_band, band, span.first)) continue;

            const tex0 = readCurveTexelF32Base(page, curve_ref.base);
            const tex1 = readCurveTexelF32Base(page, curve_ref.base + 4);
            const tex2 = readCurveTexelF32Base(page, curve_ref.base + 8);
            const meta = readCurveTexelF32Base(page, curve_ref.base + 12);
            const segment = decodeCurveSegment(tex0, tex1, tex2, meta);
            if (accumulateGlyphCoverageSegment(&result, segment, sample_rc, ppe, horizontal) == .stop_scan) break;
        }
    }
    return result;
}

fn evalHintedTextCoverageAxisBandSpan(
    page: anytype,
    record: HintedTextRecord,
    sample_rc: Vec2,
    ppe: f32,
    glyph_band_base: usize,
    header_base: i32,
    span: BandSpan,
    comptime horizontal: bool,
) CoveragePair {
    var result = CoveragePair{ .cov = 0.0, .wgt = 0.0 };
    if (span.first > span.last) return result;
    const dedup = span.first != span.last;
    const ordered = !record.hasUnorderedBands();

    var band = span.first;
    while (band <= span.last) : (band += 1) {
        const header = readBandTexelLinear(page, glyph_band_base + @as(usize, @intCast(header_base + band)));
        const band_base = glyph_band_base + header[1];
        var i: u32 = 0;
        while (i < header[0]) : (i += 1) {
            const curve_ref = readBandCurveRef(page, band_base + i) orelse continue;
            if (dedup and !isBandSpanOwner(curve_ref.first_member_band, band, span.first)) continue;
            if (accumulateHintedCurveCoverage(&result, record, curve_ref.base, sample_rc, ppe, horizontal) == .stop_scan and ordered) break;
        }
    }
    return result;
}

inline fn evalGlyphCoverageAxisBandSpan(
    page: anytype,
    sample_rc: Vec2,
    ppe: f32,
    glyph_band_base: usize,
    header_base: i32,
    span: BandSpan,
    comptime horizontal: bool,
) CoveragePair {
    const Page = switch (@typeInfo(@TypeOf(page))) {
        .pointer => |ptr| ptr.child,
        else => @TypeOf(page),
    };
    if (comptime @hasField(Page, "h_curves")) {
        return evalPreparedGlyphCoverageAxisBandSpan(page, sample_rc, ppe, glyph_band_base, header_base, span, horizontal);
    }
    return evalGenericGlyphCoverageAxisBandSpan(page, sample_rc, ppe, glyph_band_base, header_base, span, horizontal);
}

fn evalGlyphHorizCoverage(page: anytype, rc: Vec2, x_offset: f32, ppe_x: f32, state: GlyphBandState) CoveragePair {
    return evalGlyphCoverageAxis(page, Vec2.new(rc.x + x_offset, rc.y), ppe_x, state.h_base, state.h_count, true);
}

fn evalGlyphVertCoverage(page: anytype, rc: Vec2, y_offset: f32, ppe_y: f32, state: GlyphBandState) CoveragePair {
    return evalGlyphCoverageAxis(page, Vec2.new(rc.x, rc.y + y_offset), ppe_y, state.v_base, state.v_count, false);
}

pub fn evalGlyphCoverage(
    page: anytype,
    em_x: f32,
    em_y: f32,
    ppe_x: f32,
    ppe_y: f32,
    be: GlyphBandEntry,
    band_max_h: i32,
    band_max_v: i32,
    fill_rule: FillRule,
) f32 {
    const state = initGlyphBandState(page, em_x, em_y, be, band_max_h, band_max_v);
    return resolveCoverage(
        evalGlyphHorizCoverage(page, Vec2.new(em_x, em_y), 0.0, ppe_x, state),
        evalGlyphVertCoverage(page, Vec2.new(em_x, em_y), 0.0, ppe_y, state),
        fill_rule,
    );
}

pub fn evalGlyphCoverageBandSpan(
    page: anytype,
    em_x: f32,
    em_y: f32,
    epp_x: f32,
    epp_y: f32,
    ppe_x: f32,
    ppe_y: f32,
    be: GlyphBandEntry,
    band_max_h: i32,
    band_max_v: i32,
    fill_rule: FillRule,
) f32 {
    const glyph_band_base = @as(usize, be.glyph_y) * @as(usize, page.band_width) + @as(usize, be.glyph_x);
    const sample_rc = Vec2.new(em_x, em_y);
    const h_span = coverageBandSpan(em_y, epp_y, be.band_scale_y, be.band_offset_y, band_max_h);
    const v_span = coverageBandSpan(em_x, epp_x, be.band_scale_x, be.band_offset_x, band_max_v);
    const h_pair = evalGlyphCoverageAxisBandSpan(page, sample_rc, ppe_x, glyph_band_base, 0, h_span, true);
    const v_pair = evalGlyphCoverageAxisBandSpan(page, sample_rc, ppe_y, glyph_band_base, band_max_h + 1, v_span, false);
    return resolveCoverage(h_pair, v_pair, fill_rule);
}

pub fn evalHintedTextCoverageBandSpan(
    page: anytype,
    record: HintedTextRecord,
    em_x: f32,
    em_y: f32,
    epp_x: f32,
    epp_y: f32,
    ppe_x: f32,
    ppe_y: f32,
    be: GlyphBandEntry,
    band_max_h: i32,
    band_max_v: i32,
    fill_rule: FillRule,
) f32 {
    const glyph_band_base = @as(usize, be.glyph_y) * @as(usize, page.band_width) + @as(usize, be.glyph_x);
    const sample_rc = Vec2.new(em_x, em_y);
    var h_span = coverageBandSpan(em_y, epp_y, be.band_scale_y, be.band_offset_y, band_max_h);
    var v_span = coverageBandSpan(em_x, epp_x, be.band_scale_x, be.band_offset_x, band_max_v);
    if (record.hasExpandedBands()) {
        h_span = expandBandSpan(h_span, record.h_band_pad, band_max_h);
        v_span = expandBandSpan(v_span, record.v_band_pad, band_max_v);
    }
    return resolveCoverage(
        evalHintedTextCoverageAxisBandSpan(page, record, sample_rc, ppe_x, glyph_band_base, 0, h_span, true),
        evalHintedTextCoverageAxisBandSpan(page, record, sample_rc, ppe_y, glyph_band_base, band_max_h + 1, v_span, false),
        fill_rule,
    );
}

// Subpixel rendering evaluates analytic coverage at seven colocated sample
// points and then runs the result through `subpixel.filterCoverage`. Lane
// count is fixed at 7; layout helpers above produce the offsets.
pub const subpixel_lane_count: usize = 7;

// Per-curve solve cache for the row-batched H-axis path. One slot per H
// curve in the row's band; populated once per row, used by every pixel.
// Up to 3 sub-contributions per curve so cubic roots fit without spilling.
pub const RowHorizCurveSolve = struct {
    along: [3]f32 = .{ 0, 0, 0 },
    sign: [3]f32 = .{ 0, 0, 0 }, // 0 => no contribution from this slot
};

const max_row_horiz_curves: usize = 128;

pub const RowHorizState = struct {
    curves: [max_row_horiz_curves]RowHorizCurveSolve,
    count: usize,
    valid: bool, // false => caller must fall back to per-pixel evaluation
};

inline fn solveRowHorizCurve(curve: *const PreparedAxisCurve, cold_curves: []const PreparedAxisCurveCold, sample_root: f32) ?RowHorizCurveSolve {
    var entry = RowHorizCurveSolve{};
    switch (curve.kind) {
        .quadratic => {
            const p0r = curve.p0_root - sample_root;
            const p1r = curve.p1_root - sample_root;
            const p2r = curve.p2_root - sample_root;
            const code = calcRootCode(p0r, p1r, p2r);
            if (code != 0) {
                const roots = solvePreparedAxisQuadratic(curve, curve.p0_along, p0r, 1.0);
                entry.along[0] = roots[0];
                entry.along[1] = roots[1];
                entry.sign[0] = if ((code & 1) != 0) 1.0 else 0.0;
                entry.sign[1] = if (code > 1) -1.0 else 0.0;
            }
            return entry;
        },
        .line => {
            const denom = curve.a_root;
            if (@abs(denom) >= 1e-10) {
                const t_raw = -(curve.p0_root - sample_root) / denom;
                if (t_raw >= -1e-5 and t_raw <= 1.0 + 1e-5) {
                    const t = std.math.clamp(t_raw, 0.0, 1.0);
                    const is_endpoint = isNearEndRoot(t) and isEndpointRootDelta(curve.p0_root + curve.a_root - sample_root);
                    if (!is_endpoint and @abs(denom) > 1e-5) {
                        entry.along[0] = curve.p0_along + curve.a_along * t;
                        entry.sign[0] = if (denom > 0.0) 1.0 else -1.0;
                    }
                }
            }
            return entry;
        },
        .conic => {
            if (!rootHullCanCross3(curve.p0_root, curve.p1_root, curve.p2_root, sample_root)) return entry;
            if (curve.cold_index >= cold_curves.len) return null;
            const cold = &cold_curves[curve.cold_index];
            const roots = solvePreparedConicRoots(cold, sample_root);
            for (roots.t[0..roots.count], 0..) |t, idx| {
                if (idx >= 3) break;
                if (isNearEndRoot(t) and isEndpointRootDelta(curve.p2_root - sample_root)) continue;
                const root_deriv = derivativePreparedConicRoot(cold, t);
                if (@abs(root_deriv) <= 1e-5) continue;
                entry.along[idx] = evaluatePreparedConicAlong(cold, t);
                entry.sign[idx] = if (root_deriv > 0.0) 1.0 else -1.0;
            }
            return entry;
        },
        .cubic => {
            if (curve.cold_index >= cold_curves.len) return null;
            const cold = &cold_curves[curve.cold_index];
            if (!rootHullCanCross4(curve.p0_root, curve.p1_root, curve.p2_root, cold.cubic_p3_root, sample_root)) return entry;
            const roots = solvePreparedCubicRoots(curve, cold, sample_root);
            for (roots.t[0..roots.count], 0..) |t, idx| {
                if (idx >= 3) break;
                const root_deriv = cold.cubic_p3_root - curve.p0_root;
                entry.along[idx] = evaluatePreparedCubicAlong(curve, cold, t);
                entry.sign[idx] = if (root_deriv > 0.0) 1.0 else -1.0;
            }
            return entry;
        },
    }
}

// Precompute the row's H-axis curve solves. `em_y_row` is the row's em-space
// y coordinate (shared across every pixel in the row); this is only valid
// for axis-aligned + RGB/BGR-stripe subpixel orders, where `plan.step.y` is
// zero and `em_y` is therefore identical across all 7 subpixel samples in
// every pixel of the row.
pub fn prepareRowHorizState(
    page: anytype,
    em_y_row: f32,
    be: GlyphBandEntry,
    band_max_h: i32,
) RowHorizState {
    var state: RowHorizState = .{
        .curves = undefined,
        .count = 0,
        .valid = false,
    };

    const band_idx_y_f = em_y_row * be.band_scale_y + be.band_offset_y;
    const band_idx_y = clampInt(@as(i32, @intFromFloat(@floor(band_idx_y_f))), 0, band_max_h);

    const glyph_band_base = @as(usize, be.glyph_y) * @as(usize, page.band_width) + @as(usize, be.glyph_x);
    const header = readBandTexelLinear(page, glyph_band_base + @as(usize, @intCast(band_idx_y)));
    const band_base = glyph_band_base + header[1];
    if (band_base >= page.h_curves.len) {
        state.valid = true;
        return state;
    }
    const band_count = @min(@as(usize, header[0]), page.h_curves.len - band_base);
    if (band_count > max_row_horiz_curves) return state;

    const band_curves = page.h_curves[band_base..][0..band_count];
    for (band_curves) |*curve| {
        if (!curve.valid) {
            state.curves[state.count] = .{};
            state.count += 1;
            continue;
        }
        const solved = solveRowHorizCurve(curve, page.h_cold_curves, em_y_row) orelse return state;
        state.curves[state.count] = solved;
        state.count += 1;
    }
    state.valid = true;
    return state;
}

// Span-aware variant: walks every band the pixel footprint touches (matches
// the GPU `*BandSpan` path) and pre-solves H-axis contributions across the
// whole span. Same RowHorizState shape; per-pixel apply is identical.
pub fn prepareRowHorizSpanState(
    page: anytype,
    em_y_row: f32,
    epp_y: f32,
    be: GlyphBandEntry,
    band_max_h: i32,
) RowHorizState {
    var state: RowHorizState = .{
        .curves = undefined,
        .count = 0,
        .valid = false,
    };

    const span = coverageBandSpan(em_y_row, epp_y, be.band_scale_y, be.band_offset_y, band_max_h);
    if (span.first > span.last) {
        state.valid = true;
        return state;
    }
    const glyph_band_base = @as(usize, be.glyph_y) * @as(usize, page.band_width) + @as(usize, be.glyph_x);
    const dedup = span.first != span.last;

    var band = span.first;
    while (band <= span.last) : (band += 1) {
        const header = readBandTexelLinear(page, glyph_band_base + @as(usize, @intCast(band)));
        const band_base = glyph_band_base + header[1];
        if (band_base >= page.h_curves.len) continue;
        const band_count = @min(@as(usize, header[0]), page.h_curves.len - band_base);
        const band_curves = page.h_curves[band_base..][0..band_count];
        for (band_curves) |*curve| {
            if (!curve.valid) continue;
            if (dedup and !isBandSpanOwner(curve.first_member_band, band, span.first)) continue;
            if (state.count >= max_row_horiz_curves) return state;
            const solved = solveRowHorizCurve(curve, page.h_cold_curves, em_y_row) orelse return state;
            state.curves[state.count] = solved;
            state.count += 1;
        }
    }
    state.valid = true;
    return state;
}

// Single-sample H accumulator: same row state, but one sample per pixel
// (used by the non-subpixel/grayscale path).
fn applyRowHorizStateToScalar(
    state: *const RowHorizState,
    em_x_pixel: f32,
    ppe_x: f32,
    h_pair: *CoveragePair,
) void {
    var c: usize = 0;
    while (c < state.count) : (c += 1) {
        const entry = state.curves[c];
        inline for (0..3) |s| {
            if (entry.sign[s] != 0.0) {
                appendCoverageContribution(h_pair, (entry.along[s] - em_x_pixel) * ppe_x, entry.sign[s]);
            }
        }
    }
}

// Per-pixel H-axis accumulator using a precomputed row state. Each of the 7
// subpixel samples for this pixel has its own sample_along = em_x_pixel +
// step.x * (s - 3); the H contribution is just the cached `along_t` minus
// that, scaled by ppe.
fn applyRowHorizStateToPixel(
    state: *const RowHorizState,
    em_x_pixel: f32,
    step_x: f32,
    ppe_x: f32,
    h_pairs: *[subpixel_lane_count]CoveragePair,
) void {
    const W = subpixel_lane_count;
    var sample_along: [W]f32 = undefined;
    inline for (0..W) |s| {
        const offset: f32 = @as(f32, @floatFromInt(@as(i32, @intCast(s)) - 3));
        sample_along[s] = em_x_pixel + step_x * offset;
    }

    var c: usize = 0;
    while (c < state.count) : (c += 1) {
        const entry = state.curves[c];
        inline for (0..3) |slot| {
            if (entry.sign[slot] != 0.0) {
                inline for (0..W) |s| {
                    appendCoverageContribution(&h_pairs[s], (entry.along[slot] - sample_along[s]) * ppe_x, entry.sign[slot]);
                }
            }
        }
    }
}

// Single-sample band-span coverage using row-cached H solves. The H span
// (and therefore the curve set after dedup) is identical across the row;
// the V axis is still evaluated fresh per pixel using the band-span path.
pub fn evalGlyphCoverageBandSpanRowH(
    page: anytype,
    em_x_pixel: f32,
    em_y_row: f32,
    row_state: *const RowHorizState,
    epp_x: f32,
    ppe_x: f32,
    ppe_y: f32,
    be: GlyphBandEntry,
    band_max_h: i32,
    band_max_v: i32,
    fill_rule: FillRule,
) f32 {
    var h_pair: CoveragePair = .{ .cov = 0, .wgt = 0 };
    applyRowHorizStateToScalar(row_state, em_x_pixel, ppe_x, &h_pair);

    const sample_rc = Vec2.new(em_x_pixel, em_y_row);
    const v_span = coverageBandSpan(em_x_pixel, epp_x, be.band_scale_x, be.band_offset_x, band_max_v);
    const glyph_band_base = @as(usize, be.glyph_y) * @as(usize, page.band_width) + @as(usize, be.glyph_x);
    const v_pair = evalGlyphCoverageAxisBandSpan(page, sample_rc, ppe_y, glyph_band_base, band_max_h + 1, v_span, false);
    return resolveCoverage(h_pair, v_pair, fill_rule);
}

// ---------------------------------------------------------------------------
// Saturated V-axis row state
// ---------------------------------------------------------------------------
//
// Slug V-axis at a pixel sums per-curve contributions = sign * clamp01(distance + 0.5)
// where distance = (curve.y(V_t) - em_y_row) * ppe_y and V_t solves curve.x(V_t) = em_x.
// For curves whose y-extent is entirely below the sample (min_y > em_y_row +
// 0.5/ppe_y) any V-ray crossing produces distance > 0.5 and the contribution
// collapses to just `sign`. For curves entirely above the sample the
// contribution is 0. We pre-classify each V-curve per row into:
//
//   below      — saturated, contributes ±sign for pixels where em_x is in
//                the curve's x-extent (axis-extent winding).
//   above      — contributes nothing; skipped.
//   transition — y-extent straddles em_y_row ± 0.5/ppe_y, OR curve is not
//                monotonic on x (so sign isn't constant); per-pixel Slug V
//                eval is needed for pixels in the curve's x-extent.
//
// Per pixel we sum saturated `sign` values, and if em_x lies in any
// transition x-extent we fall back to evalGlyphCoverageAxisBandSpan. This
// reproduces Slug's V cov for monotonic curves while skipping the per-pixel
// sqrt + divisions on the saturated-and-far common case.

const max_sat_curves: usize = 48;

pub const SaturatedBelowEntry = struct {
    x_lo: f32,
    x_hi: f32,
    sign: f32,
};

pub const TransitionXRange = struct {
    x_lo: f32,
    x_hi: f32,
};

pub const SaturatedRowState = struct {
    below: [max_sat_curves]SaturatedBelowEntry,
    below_count: u32,
    transition: [max_sat_curves]TransitionXRange,
    transition_count: u32,
    valid: bool,
};

fn curveVAxisXExtent(curve: *const PreparedAxisCurve, cold_curves: []const PreparedAxisCurveCold) struct { lo: f32, hi: f32 } {
    var lo = curve.p0_root;
    var hi = curve.p0_root;
    switch (curve.kind) {
        .line => {
            const p2 = curve.p0_root + curve.a_root;
            lo = @min(lo, p2);
            hi = @max(hi, p2);
        },
        .quadratic, .conic => {
            lo = @min(@min(lo, curve.p1_root), curve.p2_root);
            hi = @max(@max(hi, curve.p1_root), curve.p2_root);
        },
        .cubic => {
            lo = @min(@min(lo, curve.p1_root), curve.p2_root);
            hi = @max(@max(hi, curve.p1_root), curve.p2_root);
            if (curve.cold_index < cold_curves.len) {
                const cold = &cold_curves[curve.cold_index];
                const p3 = cold.cubic_p3_root;
                lo = @min(lo, p3);
                hi = @max(hi, p3);
            }
        },
    }
    return .{ .lo = lo, .hi = hi };
}

// Returns the saturated-below entry for a curve, or null if the curve is not
// monotonic on x (would have multiple V-ray crossings with potentially
// different signs).
fn classifySaturatedBelow(curve: *const PreparedAxisCurve, cold_curves: []const PreparedAxisCurveCold) ?SaturatedBelowEntry {
    switch (curve.kind) {
        .line => {
            const p2 = curve.p0_root + curve.a_root;
            const sign: f32 = if (curve.a_root < 0.0) 1.0 else -1.0;
            return .{ .x_lo = @min(curve.p0_root, p2), .x_hi = @max(curve.p0_root, p2), .sign = sign };
        },
        .quadratic => {
            // dx/dt = 2*(a_root*t - b_root). Zero at t = b_root / a_root.
            // If that critical t is in (0, 1) the curve doubles back in x.
            if (@abs(curve.a_root) > 1e-10) {
                const t_crit = curve.b_root / curve.a_root;
                if (t_crit > 1e-5 and t_crit < 1.0 - 1e-5) return null;
            }
            if (@abs(curve.p2_root - curve.p0_root) < 1e-10) return null;
            const sign: f32 = if (curve.p2_root < curve.p0_root) 1.0 else -1.0;
            return .{ .x_lo = @min(curve.p0_root, curve.p2_root), .x_hi = @max(curve.p0_root, curve.p2_root), .sign = sign };
        },
        .conic => {
            // Conservative monotonic-on-x check: p1 is between p0 and p2.
            // (Not strictly sufficient — a conic with weight imbalance can
            // bend within the convex hull — but covers the common rounded-
            // rect / ellipse arc case. Non-monotonic cases fall through to
            // the transition path which is exact.)
            const min_p = @min(curve.p0_root, curve.p2_root);
            const max_p = @max(curve.p0_root, curve.p2_root);
            if (curve.p1_root < min_p - 1e-5 or curve.p1_root > max_p + 1e-5) return null;
            const sign: f32 = if (curve.p2_root < curve.p0_root) 1.0 else -1.0;
            return .{ .x_lo = min_p, .x_hi = max_p, .sign = sign };
        },
        .cubic => {
            // Cubics are pre-split at extrema so each piece is monotonic on
            // both axes (see path/picture_compile.zig: splitCubicsAtExtrema).
            if (curve.cold_index >= cold_curves.len) return null;
            const cold = &cold_curves[curve.cold_index];
            const p3 = cold.cubic_p3_root;
            // For a monotonic cubic, dx/dt has constant sign across t ∈ [0,1].
            // derivative_axis = -dx/dt, so its sign matches sign(p0 - p3).
            if (@abs(p3 - curve.p0_root) < 1e-10) return null;
            const sign: f32 = if (p3 < curve.p0_root) 1.0 else -1.0;
            return .{ .x_lo = @min(curve.p0_root, p3), .x_hi = @max(curve.p0_root, p3), .sign = sign };
        },
    }
}

pub fn prepareSaturatedRowState(
    page: anytype,
    em_y_row: f32,
    ppe_y: f32,
    be: GlyphBandEntry,
    band_max_v: i32,
) SaturatedRowState {
    var state: SaturatedRowState = .{
        .below = undefined,
        .below_count = 0,
        .transition = undefined,
        .transition_count = 0,
        .valid = false,
    };

    const threshold = 0.5 / @max(ppe_y, 1e-6);
    const above_thresh = em_y_row - threshold;
    const below_thresh = em_y_row + threshold;
    const glyph_band_base = @as(usize, be.glyph_y) * @as(usize, page.band_width) + @as(usize, be.glyph_x);
    const header_base: i32 = @as(i32, @intCast(@as(u32, be.h_band_count)));

    var band: i32 = 0;
    while (band <= band_max_v) : (band += 1) {
        const header = readBandTexelLinear(page, glyph_band_base + @as(usize, @intCast(header_base + band)));
        const band_base = glyph_band_base + header[1];
        if (band_base >= page.v_curves.len) continue;
        const band_count = @min(@as(usize, header[0]), page.v_curves.len - band_base);
        const band_curves = page.v_curves[band_base..][0..band_count];

        for (band_curves) |*curve| {
            if (!curve.valid) continue;
            // Process each curve only in its first_member_band, so curves
            // present in multiple bands aren't counted twice.
            if (@as(i32, @intCast(curve.first_member_band)) != band) continue;

            const min_y = curve.min_axis;
            const max_y = curve.max_axis;

            // Above sample: saturated to 0, skip.
            if (max_y < above_thresh) continue;

            // Below sample: saturated contributes ±sign.
            if (min_y > below_thresh) {
                if (classifySaturatedBelow(curve, page.v_cold_curves)) |entry| {
                    if (state.below_count >= max_sat_curves) {
                        state.valid = false;
                        return state;
                    }
                    state.below[state.below_count] = entry;
                    state.below_count += 1;
                    continue;
                }
                // Non-monotonic curve below sample — fall through to treat
                // as transition (Slug V handles its multiple roots).
            }

            // Transition: curve straddles em_y_row's fringe (or is non-
            // monotonic). Per-pixel Slug needed for pixels in its x-extent.
            const xe = curveVAxisXExtent(curve, page.v_cold_curves);
            if (state.transition_count >= max_sat_curves) {
                state.valid = false;
                return state;
            }
            state.transition[state.transition_count] = .{ .x_lo = xe.lo, .x_hi = xe.hi };
            state.transition_count += 1;
        }
    }

    state.valid = true;
    return state;
}

inline fn pixelInVTransition(state: *const SaturatedRowState, em_x: f32) bool {
    var i: usize = 0;
    while (i < state.transition_count) : (i += 1) {
        if (em_x >= state.transition[i].x_lo and em_x <= state.transition[i].x_hi) return true;
    }
    return false;
}

inline fn saturatedBelowSum(state: *const SaturatedRowState, em_x: f32) f32 {
    var sum: f32 = 0;
    var i: usize = 0;
    while (i < state.below_count) : (i += 1) {
        const entry = state.below[i];
        if (em_x >= entry.x_lo and em_x <= entry.x_hi) {
            sum += entry.sign;
        }
    }
    return sum;
}

pub fn evalGlyphCoverageSaturatedRowH(
    page: anytype,
    em_x_pixel: f32,
    em_y_row: f32,
    row_state: *const RowHorizState,
    saturated_state: *const SaturatedRowState,
    epp_x: f32,
    ppe_x: f32,
    ppe_y: f32,
    be: GlyphBandEntry,
    band_max_h: i32,
    band_max_v: i32,
    fill_rule: FillRule,
) f32 {
    var h_pair: CoveragePair = .{ .cov = 0, .wgt = 0 };
    applyRowHorizStateToScalar(row_state, em_x_pixel, ppe_x, &h_pair);

    var v_pair: CoveragePair = .{ .cov = 0, .wgt = 0 };
    var was_transition: u8 = 0;
    if (pixelInVTransition(saturated_state, em_x_pixel)) {
        was_transition = 1;
        const sample_rc = Vec2.new(em_x_pixel, em_y_row);
        const v_span = coverageBandSpan(em_x_pixel, epp_x, be.band_scale_x, be.band_offset_x, band_max_v);
        const glyph_band_base = @as(usize, be.glyph_y) * @as(usize, page.band_width) + @as(usize, be.glyph_x);
        v_pair = evalGlyphCoverageAxisBandSpan(page, sample_rc, ppe_y, glyph_band_base, band_max_h + 1, v_span, false);
    } else {
        v_pair.cov = saturatedBelowSum(saturated_state, em_x_pixel);
        v_pair.wgt = 0;
    }

    return resolveCoverage(h_pair, v_pair, fill_rule);
}

// Single-sample, single-call grayscale coverage using row-cached H solves.
// Per pixel: V-axis is the only place that touches the curve solver; the
// H-axis is just two cheap MAD + clamp per cached curve.
pub fn evalGlyphCoverageRowH(
    page: anytype,
    em_x_pixel: f32,
    em_y_row: f32,
    row_state: *const RowHorizState,
    ppe_x: f32,
    ppe_y: f32,
    be: GlyphBandEntry,
    band_max_h: i32,
    band_max_v: i32,
    fill_rule: FillRule,
) f32 {
    var h_pair: CoveragePair = .{ .cov = 0, .wgt = 0 };
    applyRowHorizStateToScalar(row_state, em_x_pixel, ppe_x, &h_pair);

    // V-axis: a single sample per pixel, identical to the V half of
    // initGlyphBandState + evalGlyphVertCoverage.
    const band_idx_x_f = em_x_pixel * be.band_scale_x + be.band_offset_x;
    const band_idx_x = clampInt(@as(i32, @intFromFloat(@floor(band_idx_x_f))), 0, band_max_v);
    const glyph_band_base = @as(usize, be.glyph_y) * @as(usize, page.band_width) + @as(usize, be.glyph_x);
    const v_header = readBandTexelLinear(page, glyph_band_base + @as(usize, @intCast(band_max_h)) + 1 + @as(usize, @intCast(band_idx_x)));
    const v_state = GlyphBandState{
        .h_base = 0,
        .h_count = 0,
        .v_base = glyph_band_base + v_header[1],
        .v_count = v_header[0],
    };
    const v_pair = evalGlyphVertCoverage(page, Vec2.new(em_x_pixel, em_y_row), 0.0, ppe_y, v_state);
    return resolveCoverage(h_pair, v_pair, fill_rule);
}

// Single-call row-batched subpixel coverage. Uses a row-precomputed H-axis
// state and evaluates the V axis fresh; for axis-aligned + RGB/BGR text
// this collapses the per-pixel H-axis solve work into the row-level
// prepare step.
pub fn evalGlyphCoverageSubpixelRowH(
    page: anytype,
    em_x_pixel: f32,
    em_y_row: f32,
    row_state: *const RowHorizState,
    plan: SubpixelCoveragePlan,
    be: GlyphBandEntry,
    band_max_v: i32,
    fill_rule: FillRule,
) SubpixelCoverage {
    const W = subpixel_lane_count;
    var h_pairs: [W]CoveragePair = @splat(CoveragePair{ .cov = 0, .wgt = 0 });
    applyRowHorizStateToPixel(row_state, em_x_pixel, plan.step.x, plan.ppe.x, &h_pairs);

    var em_x: [W]f32 = undefined;
    inline for (0..W) |k| {
        const offset: f32 = @as(f32, @floatFromInt(@as(i32, @intCast(k)) - 3));
        em_x[k] = em_x_pixel + plan.step.x * offset;
    }
    const em_y: [W]f32 = @splat(em_y_row);

    var v_band_idx: [W]i32 = undefined;
    inline for (0..W) |i| {
        const bx_f = em_x[i] * be.band_scale_x + be.band_offset_x;
        v_band_idx[i] = clampInt(@as(i32, @intFromFloat(@floor(bx_f))), 0, band_max_v);
    }

    var v_pairs: [W]CoveragePair = @splat(CoveragePair{ .cov = 0, .wgt = 0 });
    const glyph_band_base = @as(usize, be.glyph_y) * @as(usize, page.band_width) + @as(usize, be.glyph_x);
    // V root varies (em_x changes per subpixel sample); pass root_shared=false.
    subpixel_eval.evalPreparedAxis(page, em_x, em_y, v_band_idx, glyph_band_base, @as(i32, @intCast(@as(u32, be.h_band_count))), plan.ppe.y, false, &v_pairs, false);

    var raw: [W]f32 = undefined;
    inline for (0..W) |i| {
        raw[i] = resolveCoverage(h_pairs[i], v_pairs[i], fill_rule);
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

const subpixel_eval = @import("coverage/subpixel_eval.zig");
pub const evalGlyphCoverageSubpixel = subpixel_eval.evalGlyphCoverageSubpixel;

test "monotonic cubic winding is invariant under path normalization" {
    // y(t) = (t - 0.5)^3 + epsilon * (t - 0.5).  It crosses y=0 at
    // t=0.5 with a small but non-zero derivative.  Scaling the same curve
    // into the canonical design frame must not change whether that crossing
    // exists.
    const epsilon: f32 = 1e-4;
    const scales = [_]f32{ 1.0, 1.0 / 304.0 };

    for (scales) |scale| {
        const segment = CurveSegment.fromCubic(.{
            .p0 = .{ .x = scale, .y = (-0.125 - 0.5 * epsilon) * scale },
            .p1 = .{ .x = scale, .y = (0.125 - epsilon / 6.0) * scale },
            .p2 = .{ .x = scale, .y = (-0.125 + epsilon / 6.0) * scale },
            .p3 = .{ .x = scale, .y = (0.125 + 0.5 * epsilon) * scale },
        });
        var pair = CoveragePair{ .cov = 0.0, .wgt = 0.0 };
        _ = accumulateGlyphCoverageSegment(
            &pair,
            segment,
            .zero,
            1.0 / scale,
            true,
        );
        try std.testing.expectApproxEqAbs(@as(f32, 1.0), pair.cov, 1e-6);
    }
}

test "hinted segment decodes absolute layer-info control points" {
    // Snapshot layer-info slab holds absolute hinted positions directly;
    // the base curve atlas is never consulted on a hinted lookup.
    const layer_info = [_]f32{
        0,    0,   0,   0,
        0,    0,   0,   0,
        0,    1,   0,   0,
        0.25, 0.0, 0.0, 0.5,
        0.75, 0.5, 0.0, 0.0,
    };
    const record = HintedTextRecord{
        .data = &layer_info,
        .width = 5,
        .info_x = 0,
        .info_y = 0,
        .base_curve_texel = 0,
        .curve_count = 1,
    };

    const segment = hintedSegment(record, 0);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), segment.p0.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), segment.p1.y, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.75), segment.p2.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), segment.p2.y, 0.001);
}

pub fn clampInt(v: i32, lo: i32, hi: i32) i32 {
    return @max(lo, @min(hi, v));
}
