const std = @import("std");
const snail = @import("../../../root.zig");
const color_mod = @import("color.zig");
const subpixel = @import("coverage/subpixel.zig");
const texture = @import("texture.zig");
const atlas_curve_mod = @import("../../format/atlas/curve.zig");
const render_abi = @import("../../format/abi.zig");

const bezier = @import("../../../math/bezier.zig");
const curve_tex = @import("../../format/curve_texture.zig");
const CurveSegment = bezier.CurveSegment;
const FillRule = snail.FillRule;
const GlyphBandEntry = std.meta.fieldInfo(atlas_curve_mod.CurveAtlas.GlyphInfo, .band_entry).type;
const SubpixelOrder = snail.SubpixelOrder;
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
    cubic_a_along: f32 = 0.0,
    cubic_b_along: f32 = 0.0,
    cubic_c_along: f32 = 0.0,
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
            .cubic_a_along = -p0_along + 3.0 * p1_along - 3.0 * p2_along + p3_along,
            .cubic_b_along = 3.0 * p0_along - 6.0 * p1_along + 3.0 * p2_along,
            .cubic_c_along = -3.0 * p0_along + 3.0 * p1_along,
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

const CurveRoots = struct {
    count: u8 = 0,
    t: [3]f32 = .{ 0, 0, 0 },
};

fn applyFillRule(fill_rule: FillRule, winding: f32) f32 {
    if (fill_rule == .even_odd) {
        const x = winding * 0.5;
        const frac = x - @floor(x);
        return 1.0 - @abs(frac * 2.0 - 1.0);
    }
    return @abs(winding);
}

fn resolveCoverage(horiz: CoveragePair, vert: CoveragePair, fill_rule: FillRule) f32 {
    const wsum = horiz.wgt + vert.wgt;
    const blended = horiz.cov * horiz.wgt + vert.cov * vert.wgt;
    const cov = @max(
        applyFillRule(fill_rule, blended / @max(wsum, 1.0 / 65536.0)),
        @min(applyFillRule(fill_rule, horiz.cov), applyFillRule(fill_rule, vert.cov)),
    );
    return clamp01(cov);
}

fn blendSubpixelSample(cw_s: CoveragePair, cw_o: CoveragePair, fill_rule: FillRule) f32 {
    const wsum = cw_s.wgt + cw_o.wgt;
    const blended = cw_s.cov * cw_s.wgt + cw_o.cov * cw_o.wgt;
    return clamp01(@max(
        applyFillRule(fill_rule, blended / @max(wsum, 1.0 / 65536.0)),
        @min(applyFillRule(fill_rule, cw_s.cov), applyFillRule(fill_rule, cw_o.cov)),
    ));
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

fn appendCurveRoot(roots: *CurveRoots, t: f32) void {
    if (t < -1e-5 or t > 1.0 + 1e-5) return;
    const clamped = std.math.clamp(t, 0.0, 1.0);
    for (roots.t[0..roots.count]) |existing| {
        if (@abs(existing - clamped) <= 1e-5) return;
    }
    var insert_at: usize = roots.count;
    while (insert_at > 0 and roots.t[insert_at - 1] > clamped) : (insert_at -= 1) {}
    var i = roots.count;
    while (i > insert_at) : (i -= 1) roots.t[i] = roots.t[i - 1];
    roots.t[insert_at] = clamped;
    roots.count += 1;
}

fn solveQuadraticRoots(a: f32, b: f32, c_val: f32) CurveRoots {
    var roots = CurveRoots{};
    if (@abs(a) < 1e-10) {
        if (@abs(b) < 1e-10) return roots;
        appendCurveRoot(&roots, -c_val / b);
        return roots;
    }
    var disc = b * b - 4.0 * a * c_val;
    if (disc < 0.0) {
        if (disc > -1e-6) disc = 0.0 else return roots;
    }
    // Stable form: q = -0.5 * (b + sign(b) * sqrt(disc)); roots are q/a and c/q.
    const sq = @sqrt(disc);
    const q = -0.5 * (b + (if (b >= 0.0) sq else -sq));
    if (@abs(q) < 1e-10) {
        appendCurveRoot(&roots, 0.0);
        return roots;
    }
    appendCurveRoot(&roots, q / a);
    appendCurveRoot(&roots, c_val / q);
    return roots;
}

fn cbrtSigned(v: f32) f32 {
    if (v == 0.0) return 0.0;
    return std.math.sign(v) * std.math.pow(f32, @abs(v), 1.0 / 3.0);
}

fn solveCubicRoots(a: f32, b: f32, c_val: f32, d: f32) CurveRoots {
    if (@abs(a) < 1e-10) return solveQuadraticRoots(b, c_val, d);

    var roots = CurveRoots{};
    const inv_a = 1.0 / a;
    const aa = b * inv_a;
    const bb = c_val * inv_a;
    const cc = d * inv_a;
    const third = 1.0 / 3.0;
    const p = bb - aa * aa * third;
    const q = (2.0 * aa * aa * aa) / 27.0 - (aa * bb) * third + cc;
    const half_q = q * 0.5;
    const third_p = p * third;
    const disc = half_q * half_q + third_p * third_p * third_p;
    const offset = aa * third;

    if (disc > 1e-8) {
        const sqrt_disc = @sqrt(disc);
        const u = cbrtSigned(-half_q + sqrt_disc);
        const v = cbrtSigned(-half_q - sqrt_disc);
        appendCurveRoot(&roots, u + v - offset);
        return roots;
    }

    if (disc >= -1e-8) {
        const u = cbrtSigned(-half_q);
        appendCurveRoot(&roots, 2.0 * u - offset);
        appendCurveRoot(&roots, -u - offset);
        return roots;
    }

    const r = @sqrt(-third_p);
    const phi = std.math.acos(std.math.clamp(-half_q / (r * r * r), -1.0, 1.0));
    const two_r = 2.0 * r;
    appendCurveRoot(&roots, two_r * @cos(phi * third) - offset);
    appendCurveRoot(&roots, two_r * @cos((phi + 2.0 * std.math.pi) * third) - offset);
    appendCurveRoot(&roots, two_r * @cos((phi + 4.0 * std.math.pi) * third) - offset);
    return roots;
}

fn solveSegmentHorizontalRoots(segment: CurveSegment, py: f32) CurveRoots {
    return switch (segment.kind) {
        .line => solveQuadraticRoots(0.0, segment.p2.y - segment.p0.y, segment.p0.y - py),
        .quadratic => blk: {
            const a = segment.p0.y - 2.0 * segment.p1.y + segment.p2.y;
            const b = 2.0 * (segment.p1.y - segment.p0.y);
            break :blk solveQuadraticRoots(a, b, segment.p0.y - py);
        },
        .conic => blk: {
            const c0 = segment.weights[0] * (segment.p0.y - py);
            const c1 = segment.weights[1] * (segment.p1.y - py);
            const c2 = segment.weights[2] * (segment.p2.y - py);
            break :blk solveQuadraticRoots(c0 - 2.0 * c1 + c2, 2.0 * (c1 - c0), c0);
        },
        .cubic => blk: {
            const a = -segment.p0.y + 3.0 * segment.p1.y - 3.0 * segment.p2.y + segment.p3.y;
            const b = 3.0 * segment.p0.y - 6.0 * segment.p1.y + 3.0 * segment.p2.y;
            const c0 = -3.0 * segment.p0.y + 3.0 * segment.p1.y;
            const d = segment.p0.y - py;
            break :blk solveCubicRoots(a, b, c0, d);
        },
    };
}

fn solveSegmentVerticalRoots(segment: CurveSegment, px: f32) CurveRoots {
    return switch (segment.kind) {
        .line => solveQuadraticRoots(0.0, segment.p2.x - segment.p0.x, segment.p0.x - px),
        .quadratic => blk: {
            const a = segment.p0.x - 2.0 * segment.p1.x + segment.p2.x;
            const b = 2.0 * (segment.p1.x - segment.p0.x);
            break :blk solveQuadraticRoots(a, b, segment.p0.x - px);
        },
        .conic => blk: {
            const c0 = segment.weights[0] * (segment.p0.x - px);
            const c1 = segment.weights[1] * (segment.p1.x - px);
            const c2 = segment.weights[2] * (segment.p2.x - px);
            break :blk solveQuadraticRoots(c0 - 2.0 * c1 + c2, 2.0 * (c1 - c0), c0);
        },
        .cubic => blk: {
            const a = -segment.p0.x + 3.0 * segment.p1.x - 3.0 * segment.p2.x + segment.p3.x;
            const b = 3.0 * segment.p0.x - 6.0 * segment.p1.x + 3.0 * segment.p2.x;
            const c0 = -3.0 * segment.p0.x + 3.0 * segment.p1.x;
            const d = segment.p0.x - px;
            break :blk solveCubicRoots(a, b, c0, d);
        },
    };
}

fn segmentMaxX(segment: CurveSegment) f32 {
    if (segment.kind == .line) return @max(segment.p0.x, segment.p2.x);
    var result = @max(@max(segment.p0.x, segment.p1.x), segment.p2.x);
    if (segment.kind == .cubic) result = @max(result, segment.p3.x);
    return result;
}

fn segmentMaxY(segment: CurveSegment) f32 {
    if (segment.kind == .line) return @max(segment.p0.y, segment.p2.y);
    var result = @max(@max(segment.p0.y, segment.p1.y), segment.p2.y);
    if (segment.kind == .cubic) result = @max(result, segment.p3.y);
    return result;
}

fn appendCoverageContribution(result: *CoveragePair, distance: f32, sign: f32) void {
    result.cov += sign * clamp01(distance + 0.5);
    result.wgt = @max(result.wgt, clamp01(1.0 - @abs(distance) * 2.0));
}

const root_code_eps: f32 = 1.0 / 65536.0;

// Treat exact-edge float drift as the mathematical contour sample. The
// half-open segment convention still comes from the root ordering below.
inline fn rootCodeCoord(v: f32) f32 {
    return if (@abs(v) <= root_code_eps) 0.0 else v;
}

inline fn isNearEndRoot(t: f32) bool {
    return t >= 1.0 - 1e-5;
}

inline fn isEndpointRootDelta(end_root_delta: f32) bool {
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
        if (isNearEndRoot(t)) {
            const end_root_delta = switch (segment.kind) {
                .conic, .quadratic, .line => if (horizontal) segment.p2.y - sample_rc.y else segment.p2.x - sample_rc.x,
                .cubic => if (horizontal) segment.p3.y - sample_rc.y else segment.p3.x - sample_rc.x,
            };
            if (isEndpointRootDelta(end_root_delta)) continue;
        }
        const point = segment.evaluate(t);
        const deriv = segment.derivative(t);
        const derivative_axis = if (horizontal) deriv.y else -deriv.x;
        if (@abs(derivative_axis) <= 1e-5) continue;
        const distance = if (horizontal)
            (point.x - sample_rc.x) * ppe
        else
            (point.y - sample_rc.y) * ppe;
        appendCoverageContribution(result, distance, if (derivative_axis > 0.0) 1.0 else -1.0);
    }
    return .continue_scan;
}

inline fn solvePreparedAxisQuadratic(curve: *const PreparedAxisCurve, p0_along: f32, p0_root: f32, ppe: f32) [2]f32 {
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
        const sq = @sqrt(@max(by * by - ay * p0_root, 0.0));
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
    return solveCubicRoots(
        cold.cubic_a_root,
        cold.cubic_b_root,
        cold.cubic_c_root,
        curve.p0_root - sample_root,
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
    return ((cold.cubic_a_along * t + cold.cubic_b_along) * t + cold.cubic_c_along) * t + curve.p0_along;
}

inline fn derivativePreparedCubicRoot(cold: *const PreparedAxisCurveCold, t: f32) f32 {
    return (3.0 * cold.cubic_a_root * t + 2.0 * cold.cubic_b_root) * t + cold.cubic_c_root;
}

fn preparedCurveCold(curve: *const PreparedAxisCurve, cold_curves: []const PreparedAxisCurveCold) *const PreparedAxisCurveCold {
    if (curve.cold_index >= cold_curves.len) {
        @panic("prepared conic/cubic curve is missing cold coefficient data");
    }
    return &cold_curves[curve.cold_index];
}

inline fn accumulatePreparedCurveCoverage(
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

    if (curve.kind == .quadratic) {
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
        const p3_root = cold.cubic_a_root + cold.cubic_b_root + cold.cubic_c_root + curve.p0_root;
        if (!rootHullCanCross4(curve.p0_root, curve.p1_root, curve.p2_root, p3_root, sample_root)) return .continue_scan;
    }

    const roots = switch (curve.kind) {
        .conic => solvePreparedConicRoots(cold, sample_root),
        .cubic => solvePreparedCubicRoots(curve, cold, sample_root),
        .quadratic, .line => unreachable,
    };
    for (roots.t[0..roots.count]) |t| {
        if (isNearEndRoot(t)) {
            const end_root = switch (curve.kind) {
                .conic => curve.p2_root,
                .cubic => cold.cubic_a_root + cold.cubic_b_root + cold.cubic_c_root + curve.p0_root,
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
            .cubic => derivativePreparedCubicRoot(cold, t),
            .quadratic, .line => unreachable,
        };
        const derivative_axis = if (horizontal) root_deriv else -root_deriv;
        if (@abs(derivative_axis) <= 1e-5) continue;
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

fn evalGlyphCoverageAxisBandSpan(
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
    return resolveCoverage(
        evalGlyphCoverageAxisBandSpan(page, sample_rc, ppe_x, glyph_band_base, 0, h_span, true),
        evalGlyphCoverageAxisBandSpan(page, sample_rc, ppe_y, glyph_band_base, band_max_h + 1, v_span, false),
        fill_rule,
    );
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
const subpixel_lane_count: usize = 7;

// Per-curve solve cache for the row-batched H-axis path. One slot per H
// curve in the row's band; populated once per row, used by every pixel.
pub const RowHorizCurveSolve = struct {
    along_t1: f32,
    along_t2: f32,
    sign1: f32, // 0 => no contribution from t1
    sign2: f32, // 0 => no contribution from t2
};

const max_row_horiz_curves: usize = 32;

pub const RowHorizState = struct {
    curves: [max_row_horiz_curves]RowHorizCurveSolve,
    count: usize,
    valid: bool, // false => caller must fall back to per-pixel evaluation
};

inline fn solveRowHorizCurve(curve: *const PreparedAxisCurve, sample_root: f32) ?RowHorizCurveSolve {
    switch (curve.kind) {
        .quadratic => {
            const p0r = curve.p0_root - sample_root;
            const p1r = curve.p1_root - sample_root;
            const p2r = curve.p2_root - sample_root;
            const code = calcRootCode(p0r, p1r, p2r);
            if (code == 0) {
                return .{ .along_t1 = 0, .along_t2 = 0, .sign1 = 0, .sign2 = 0 };
            }
            const roots = solvePreparedAxisQuadratic(curve, curve.p0_along, p0r, 1.0);
            return .{
                .along_t1 = roots[0],
                .along_t2 = roots[1],
                .sign1 = if ((code & 1) != 0) 1.0 else 0.0,
                .sign2 = if (code > 1) -1.0 else 0.0,
            };
        },
        .line => {
            const denom = curve.a_root;
            var entry = RowHorizCurveSolve{ .along_t1 = 0, .along_t2 = 0, .sign1 = 0, .sign2 = 0 };
            if (@abs(denom) >= 1e-10) {
                const t_raw = -(curve.p0_root - sample_root) / denom;
                if (t_raw >= -1e-5 and t_raw <= 1.0 + 1e-5) {
                    const t = std.math.clamp(t_raw, 0.0, 1.0);
                    const is_endpoint = isNearEndRoot(t) and isEndpointRootDelta(curve.p0_root + curve.a_root - sample_root);
                    if (!is_endpoint and @abs(denom) > 1e-5) {
                        entry.along_t1 = curve.p0_along + curve.a_along * t;
                        entry.sign1 = if (denom > 0.0) 1.0 else -1.0;
                    }
                }
            }
            return entry;
        },
        .conic, .cubic => return null,
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
            state.curves[state.count] = .{ .along_t1 = 0, .along_t2 = 0, .sign1 = 0, .sign2 = 0 };
            state.count += 1;
            continue;
        }
        const solved = solveRowHorizCurve(curve, em_y_row) orelse {
            // conic/cubic: refuse fast path, caller falls back to per-pixel.
            return state;
        };
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
            const solved = solveRowHorizCurve(curve, em_y_row) orelse return state;
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
        if (entry.sign1 != 0.0) {
            appendCoverageContribution(h_pair, (entry.along_t1 - em_x_pixel) * ppe_x, entry.sign1);
        }
        if (entry.sign2 != 0.0) {
            appendCoverageContribution(h_pair, (entry.along_t2 - em_x_pixel) * ppe_x, entry.sign2);
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
        if (entry.sign1 != 0.0) {
            inline for (0..W) |s| {
                appendCoverageContribution(&h_pairs[s], (entry.along_t1 - sample_along[s]) * ppe_x, entry.sign1);
            }
        }
        if (entry.sign2 != 0.0) {
            inline for (0..W) |s| {
                appendCoverageContribution(&h_pairs[s], (entry.along_t2 - sample_along[s]) * ppe_x, entry.sign2);
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
    evalPreparedSubpixelAxis(page, em_x, em_y, v_band_idx, glyph_band_base, @as(i32, @intCast(@as(u32, be.h_band_count))), plan.ppe.y, false, &v_pairs, false);

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

    const W = subpixel_lane_count;
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
        evalPreparedSubpixelSamples(page, em_x, em_y, plan, be, band_max_h, band_max_v, fill_rule, &raw);
    } else {
        inline for (0..W) |k| {
            raw[k] = evalGlyphCoverage(page, em_x[k], em_y[k], plan.ppe.x, plan.ppe.y, be, band_max_h, band_max_v, fill_rule);
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
fn evalPreparedSubpixelSamples(
    page: anytype,
    em_x: [subpixel_lane_count]f32,
    em_y: [subpixel_lane_count]f32,
    plan: SubpixelCoveragePlan,
    be: GlyphBandEntry,
    band_max_h: i32,
    band_max_v: i32,
    fill_rule: FillRule,
    out_cov: *[subpixel_lane_count]f32,
) void {
    const W = subpixel_lane_count;
    var h_pairs: [W]CoveragePair = @splat(CoveragePair{ .cov = 0, .wgt = 0 });
    var v_pairs: [W]CoveragePair = @splat(CoveragePair{ .cov = 0, .wgt = 0 });

    const glyph_band_base = @as(usize, be.glyph_y) * @as(usize, page.band_width) + @as(usize, be.glyph_x);

    var h_band_idx: [W]i32 = undefined;
    var v_band_idx: [W]i32 = undefined;
    inline for (0..W) |i| {
        const bx_f = em_x[i] * be.band_scale_x + be.band_offset_x;
        const by_f = em_y[i] * be.band_scale_y + be.band_offset_y;
        v_band_idx[i] = clampInt(@as(i32, @intFromFloat(@floor(bx_f))), 0, band_max_v);
        h_band_idx[i] = clampInt(@as(i32, @intFromFloat(@floor(by_f))), 0, band_max_h);
    }

    // RGB/BGR keep em_y constant across the 7 samples (stripes run vertical);
    // VRGB/VBGR keep em_x constant. Either way, the constant axis is the
    // "root-shared" axis of one of H/V.
    const h_root_shared = plan.step.y == 0.0;
    const v_root_shared = plan.step.x == 0.0;

    evalPreparedSubpixelAxis(page, em_x, em_y, h_band_idx, glyph_band_base, 0, plan.ppe.x, h_root_shared, &h_pairs, true);
    evalPreparedSubpixelAxis(page, em_x, em_y, v_band_idx, glyph_band_base, band_max_h + 1, plan.ppe.y, v_root_shared, &v_pairs, false);

    inline for (0..W) |i| {
        out_cov[i] = resolveCoverage(h_pairs[i], v_pairs[i], fill_rule);
    }
}

fn evalPreparedSubpixelAxis(
    page: anytype,
    em_x: [subpixel_lane_count]f32,
    em_y: [subpixel_lane_count]f32,
    band_idx: [subpixel_lane_count]i32,
    glyph_band_base: usize,
    header_base: i32,
    ppe: f32,
    root_shared: bool,
    results: *[subpixel_lane_count]CoveragePair,
    comptime horizontal: bool,
) void {
    const W = subpixel_lane_count;

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
            accumulateSubpixelCurveMulti(curve, cold_curves, em_x, em_y, mask, ppe, root_shared, results, horizontal);
        }
    }
}

inline fn accumulateSubpixelCurveMulti(
    curve: *const PreparedAxisCurve,
    cold_curves: []const PreparedAxisCurveCold,
    em_x: [subpixel_lane_count]f32,
    em_y: [subpixel_lane_count]f32,
    mask: u8,
    ppe: f32,
    root_shared: bool,
    results: *[subpixel_lane_count]CoveragePair,
    comptime horizontal: bool,
) void {
    if (root_shared and curve.kind == .quadratic) {
        accumulateSubpixelQuadraticSharedRoot(curve, em_x, em_y, mask, ppe, results, horizontal);
        return;
    }
    if (root_shared and curve.kind == .line) {
        accumulateSubpixelLineSharedRoot(curve, em_x, em_y, mask, ppe, results, horizontal);
        return;
    }

    // Varying root, or conic/cubic: scalar fan-out across active lanes. The
    // grouped header read above still saves redundant band lookups.
    const W = subpixel_lane_count;
    inline for (0..W) |i| {
        if ((mask & (@as(u8, 1) << @intCast(i))) != 0) {
            const sample_rc = Vec2.new(em_x[i], em_y[i]);
            _ = accumulatePreparedCurveCoverage(&results[i], curve, cold_curves, sample_rc, ppe, horizontal);
        }
    }
}

// Shared-root quadratic: sample_root is identical across active lanes, so
// `calcRootCode` and `solvePreparedAxisQuadratic` produce one answer reused
// for every lane. Only the per-lane distance shift remains.
fn accumulateSubpixelQuadraticSharedRoot(
    curve: *const PreparedAxisCurve,
    em_x: [subpixel_lane_count]f32,
    em_y: [subpixel_lane_count]f32,
    mask: u8,
    ppe: f32,
    results: *[subpixel_lane_count]CoveragePair,
    comptime horizontal: bool,
) void {
    if (mask == 0) return;
    const W = subpixel_lane_count;
    const first_lane: usize = @ctz(mask);
    const sample_root = if (horizontal) em_y[first_lane] else em_x[first_lane];

    const p0r = curve.p0_root - sample_root;
    const p1r = curve.p1_root - sample_root;
    const p2r = curve.p2_root - sample_root;
    const code = calcRootCode(p0r, p1r, p2r);
    if (code == 0) return;

    const roots = solvePreparedAxisQuadratic(curve, curve.p0_along, p0r, 1.0);
    const t1_along = roots[0];
    const t2_along = roots[1];

    if ((code & 1) != 0) {
        const sign: f32 = if (horizontal) 1.0 else -1.0;
        inline for (0..W) |i| {
            if ((mask & (@as(u8, 1) << @intCast(i))) != 0) {
                const sample_along = if (horizontal) em_x[i] else em_y[i];
                appendCoverageContribution(&results[i], (t1_along - sample_along) * ppe, sign);
            }
        }
    }
    if (code > 1) {
        const sign: f32 = if (horizontal) -1.0 else 1.0;
        inline for (0..W) |i| {
            if ((mask & (@as(u8, 1) << @intCast(i))) != 0) {
                const sample_along = if (horizontal) em_x[i] else em_y[i];
                appendCoverageContribution(&results[i], (t2_along - sample_along) * ppe, sign);
            }
        }
    }
}

fn accumulateSubpixelLineSharedRoot(
    curve: *const PreparedAxisCurve,
    em_x: [subpixel_lane_count]f32,
    em_y: [subpixel_lane_count]f32,
    mask: u8,
    ppe: f32,
    results: *[subpixel_lane_count]CoveragePair,
    comptime horizontal: bool,
) void {
    if (mask == 0) return;
    const W = subpixel_lane_count;
    const first_lane: usize = @ctz(mask);
    const sample_root = if (horizontal) em_y[first_lane] else em_x[first_lane];

    const denom = curve.a_root;
    if (@abs(denom) < 1e-10) return;
    const t_raw = -(curve.p0_root - sample_root) / denom;
    if (t_raw < -1e-5 or t_raw > 1.0 + 1e-5) return;
    const t = std.math.clamp(t_raw, 0.0, 1.0);
    if (isNearEndRoot(t) and isEndpointRootDelta(curve.p0_root + curve.a_root - sample_root)) return;

    const derivative_axis = if (horizontal) curve.a_root else -curve.a_root;
    if (@abs(derivative_axis) <= 1e-5) return;
    const sign: f32 = if (derivative_axis > 0.0) 1.0 else -1.0;
    const along_at_t = curve.p0_along + curve.a_along * t;

    inline for (0..W) |i| {
        if ((mask & (@as(u8, 1) << @intCast(i))) != 0) {
            const sample_along = if (horizontal) em_x[i] else em_y[i];
            appendCoverageContribution(&results[i], (along_at_t - sample_along) * ppe, sign);
        }
    }
}

// ---------------------------------------------------------------------------
// Slug math helpers (ported from GLSL)
// ---------------------------------------------------------------------------

/// Root code from sign bits of the three y-coordinates (relative to ray).
/// Encodes whether 0, 1, or 2 roots contribute to coverage.
/// Returns: 0 = no roots, 1 = first root only, 0x0100 = second root only, 0x0101 = both.
fn calcRootCode(y1: f32, y2: f32, y3: f32) u16 {
    const s1: u32 = @as(u32, @bitCast(rootCodeCoord(y1))) >> 31;
    const s2: u32 = @as(u32, @bitCast(rootCodeCoord(y2))) >> 30;
    const s3: u32 = @as(u32, @bitCast(rootCodeCoord(y3))) >> 29;

    // Replicate the GLSL bit manipulation
    const shift_a: u32 = (s2 & 2) | (s1 & ~@as(u32, 2));
    const shift: u32 = (s3 & 4) | (shift_a & ~@as(u32, 4));

    return @as(u16, @intCast((@as(u32, 0x2E74) >> @as(u5, @intCast(shift & 0x1F))) & 0x0101));
    // The GLSL uses 0x0101 mask on a u16 shift result. We want the low byte.
}

/// Solve horizontal polynomial: find x-intersections for a horizontal ray.
/// p12 = (p1.x, p1.y, p2.x, p2.y), p3 = (p3.x, p3.y), all relative to pixel.
/// Returns two x-distances scaled by ppe_x.
fn solveHorizPoly(p1x: f32, p1y: f32, p2x: f32, p2y: f32, p3x: f32, p3y: f32, ppe_x: f32) [2]f32 {
    const ax = p1x - p2x * 2.0 + p3x;
    const ay = p1y - p2y * 2.0 + p3y;
    const bx = p1x - p2x;
    const by = p1y - p2y;
    const eps: f32 = 1.0 / 65536.0;

    var t1: f32 = undefined;
    var t2: f32 = undefined;

    if (@abs(ay) < eps) {
        t1 = if (@abs(by) < eps) 0.0 else p1y * 0.5 / by;
        t2 = t1;
    } else {
        const sq = @sqrt(@max(by * by - ay * p1y, 0.0));
        if (by >= 0.0) {
            const q = by + sq;
            t2 = q / ay;
            t1 = if (@abs(q) < eps) 0.0 else p1y / q;
        } else {
            const q = by - sq;
            t1 = q / ay;
            t2 = if (@abs(q) < eps) 0.0 else p1y / q;
        }
    }

    const x1 = (ax * t1 - bx * 2.0) * t1 + p1x;
    const x2 = (ax * t2 - bx * 2.0) * t2 + p1x;
    return .{ x1 * ppe_x, x2 * ppe_x };
}

/// Solve vertical polynomial: find y-intersections for a vertical ray.
fn solveVertPoly(p1x: f32, p1y: f32, p2x: f32, p2y: f32, p3x: f32, p3y: f32, ppe_y: f32) [2]f32 {
    const ax = p1x - p2x * 2.0 + p3x;
    const ay = p1y - p2y * 2.0 + p3y;
    const bx = p1x - p2x;
    const by = p1y - p2y;
    const eps: f32 = 1.0 / 65536.0;

    var t1: f32 = undefined;
    var t2: f32 = undefined;

    if (@abs(ax) < eps) {
        t1 = if (@abs(bx) < eps) 0.0 else p1x * 0.5 / bx;
        t2 = t1;
    } else {
        const sq = @sqrt(@max(bx * bx - ax * p1x, 0.0));
        if (bx >= 0.0) {
            const q = bx + sq;
            t2 = q / ax;
            t1 = if (@abs(q) < eps) 0.0 else p1x / q;
        } else {
            const q = bx - sq;
            t1 = q / ax;
            t2 = if (@abs(q) < eps) 0.0 else p1x / q;
        }
    }

    const y1 = (ay * t1 - by * 2.0) * t1 + p1y;
    const y2 = (ay * t2 - by * 2.0) * t2 + p1y;
    return .{ y1 * ppe_y, y2 * ppe_y };
}

test "root code treats tiny exact-edge drift as zero" {
    try std.testing.expectEqual(calcRootCode(0.0, -0.25, -0.5), calcRootCode(-root_code_eps * 0.5, -0.25, -0.5));
    try std.testing.expectEqual(@as(u16, 0), calcRootCode(-root_code_eps * 2.0, -0.25, -0.5));
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

fn clampInt(v: i32, lo: i32, hi: i32) i32 {
    return @max(lo, @min(hi, v));
}
