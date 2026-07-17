//! Bezier root-finding and polynomial helpers used by the CPU
//! coverage evaluator.
//!
//! Functions here are pure (no PreparedAxisCurve / band-data
//! references). They take Bezier segments (lines, quadratics, conics,
//! cubics) or raw polynomial coefficients and return roots / extrema /
//! intersection points. The coverage evaluator wraps these in caching
//! and band-walk logic; the math itself is split out so future
//! tweaks (e.g. tighter discriminant tolerances) don't have to wade
//! through 2000 lines of evaluator state.

const std = @import("std");
const bezier = @import("snail_core").files.math_bezier;
const CurveSegment = bezier.CurveSegment;

/// Up to three real roots from a polynomial solve, sorted ascending.
pub const CurveRoots = struct {
    count: u8 = 0,
    t: [3]f32 = .{ 0, 0, 0 },
};

/// Tolerance on root-coordinate sign tests. Anything within this band
/// is treated as "on the line" by `rootCodeCoord`.
pub const root_code_eps: f32 = 1.0 / 65536.0;

/// Treat exact-edge float drift as the mathematical contour sample. The
/// half-open segment convention still comes from the root ordering at
/// the call site.
pub inline fn rootCodeCoord(v: f32) f32 {
    return if (@abs(v) <= root_code_eps) 0.0 else v;
}

/// Insert `t` into `roots` if it's in [0, 1] and not already present,
/// preserving ascending order.
pub inline fn appendCurveRoot(roots: *CurveRoots, t: f32) void {
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

pub inline fn solveQuadraticRoots(a: f32, b: f32, c_val: f32) CurveRoots {
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

fn solveCubicRootsBracketed(a: f32, b: f32, c_val: f32, d: f32, end_delta: f32) CurveRoots {
    // `splitCubicsAtExtrema` (paths.zig) makes every uploaded cubic monotonic
    // on both sampling axes, so along either axis a cubic piece contributes at
    // most one root in [0, 1]. Solve it the same way the GPU does
    // (`solveMonotonicCubicRoot` in snail_path_frag_body.glsl): a fixed 16-step
    // Newton-bracketed-by-bisection from the endpoint sign bracket.
    //
    // The previous analytic (Cardano) solve drifted for the near-quadratic
    // pieces the split produces, and its quadratic fallback returned *no* roots
    // when the sample sat within ~ε of a piece's endpoint x/y (a near-tangent
    // whose discriminant goes slightly negative). That dropped the crossing in
    // a hair-thin band next to any endpoint two halves share on the sampling
    // axis — e.g. the leaf primitive, whose cubics meet at (0.5, 0)/(0.5, 1) —
    // collapsing one axis's winding to 0 and painting a 1px seam straight down
    // the shape on the CPU while the GPU stayed correct.
    //
    // The loop is a flat 16 iterations, matching the GPU bit-for-bit. Newton
    // converges in ~11 here, but a data-dependent early-exit measured *slower*
    // than the unrolled fixed loop (branch mispredict > the few cheap
    // iterations saved), so the count stays fixed.
    var roots = CurveRoots{};
    const f0 = d; // f(0) = curve_root(0) - sample
    const f1 = end_delta; // Exact p3 - sample; do not reconstruct through a+b+c+d.
    // No sign change across [0,1] (both strictly outside the ±ε contour band)
    // means the monotonic curve never reaches the sample line here.
    if ((f0 < -root_code_eps and f1 < -root_code_eps) or (f0 > root_code_eps and f1 > root_code_eps)) return roots;

    var lo: f32 = 0.0;
    var hi: f32 = 1.0;
    var t: f32 = 0.5;
    const increasing = f1 >= f0;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        const f = ((a * t + b) * t + c_val) * t + d;
        if ((increasing and f < 0.0) or (!increasing and f > 0.0)) {
            lo = t;
        } else {
            hi = t;
        }
        const deriv = (3.0 * a * t + 2.0 * b) * t + c_val;
        var next = (lo + hi) * 0.5;
        if (@abs(deriv) >= 1e-6) {
            const newton = t - f / deriv;
            if (newton > lo and newton < hi) next = newton;
        }
        t = next;
    }
    appendCurveRoot(&roots, t);
    return roots;
}

pub fn solveCubicRoots(a: f32, b: f32, c_val: f32, d: f32) CurveRoots {
    return solveCubicRootsBracketed(a, b, c_val, d, ((a + b) + c_val) + d);
}

/// Solve the single crossing of a cubic that has already been split into a
/// monotonic span. Endpoint signs use the same +0 convention as Slug's
/// quadratic root code: a shared vertex is owned by exactly one adjacent
/// span, independent of polynomial-reconstruction error at t=1.
pub fn solveMonotonicCubicCrossing(a: f32, b: f32, c_val: f32, start_delta: f32, end_delta: f32) CurveRoots {
    var roots = CurveRoots{};
    const start_side = rootCodeCoord(start_delta) < 0.0;
    const end_side = rootCodeCoord(end_delta) < 0.0;
    if (start_side == end_side) return roots;

    // Use a shared endpoint exactly when it lies in the coordinate epsilon
    // band. Reconstructing f(1) as a+b+c+d can otherwise move the solved root
    // across the half-open ownership threshold after a transform.
    if (@abs(start_delta) <= root_code_eps) {
        appendCurveRoot(&roots, 0.0);
        return roots;
    }
    if (@abs(end_delta) <= root_code_eps) {
        appendCurveRoot(&roots, 1.0);
        return roots;
    }
    return solveCubicRootsBracketed(a, b, c_val, start_delta, end_delta);
}

pub inline fn solveSegmentHorizontalRoots(segment: CurveSegment, py: f32) CurveRoots {
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
            break :blk solveMonotonicCubicCrossing(a, b, c0, segment.p0.y - py, segment.p3.y - py);
        },
    };
}

pub inline fn solveSegmentVerticalRoots(segment: CurveSegment, px: f32) CurveRoots {
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
            break :blk solveMonotonicCubicCrossing(a, b, c0, segment.p0.x - px, segment.p3.x - px);
        },
    };
}

/// Tight upper bound on the curve's x-coordinate over t ∈ [0, 1].
/// For a Bezier the curve lies inside its convex hull, so the max of
/// the control points is a safe bound.
pub inline fn segmentMaxX(segment: CurveSegment) f32 {
    if (segment.kind == .line) return @max(segment.p0.x, segment.p2.x);
    var result = @max(@max(segment.p0.x, segment.p1.x), segment.p2.x);
    if (segment.kind == .cubic) result = @max(result, segment.p3.x);
    return result;
}

pub inline fn segmentMaxY(segment: CurveSegment) f32 {
    if (segment.kind == .line) return @max(segment.p0.y, segment.p2.y);
    var result = @max(@max(segment.p0.y, segment.p1.y), segment.p2.y);
    if (segment.kind == .cubic) result = @max(result, segment.p3.y);
    return result;
}

pub inline fn segmentMinX(segment: CurveSegment) f32 {
    if (segment.kind == .line) return @min(segment.p0.x, segment.p2.x);
    var result = @min(@min(segment.p0.x, segment.p1.x), segment.p2.x);
    if (segment.kind == .cubic) result = @min(result, segment.p3.x);
    return result;
}

pub inline fn segmentMinY(segment: CurveSegment) f32 {
    if (segment.kind == .line) return @min(segment.p0.y, segment.p2.y);
    var result = @min(@min(segment.p0.y, segment.p1.y), segment.p2.y);
    if (segment.kind == .cubic) result = @min(result, segment.p3.y);
    return result;
}

/// Snap a near-zero discriminant to exactly 0 to avoid the canceling
/// ±-signed contributions that bleed coverage onto pixels that should
/// be cleanly outside (or inside) the shape. See the long comment in
/// the original site for the FP-noise budget reasoning.
pub inline fn snapNearTangentSqrt(disc: f32, b: f32, ac: f32) f32 {
    const tol = @max(b * b, @abs(ac)) * 3.0e-6;
    if (disc <= tol) return 0.0;
    return @sqrt(disc);
}

/// Root code from sign bits of the three y-coordinates (relative to ray).
/// Encodes whether 0, 1, or 2 roots contribute to coverage.
/// Returns: 0 = no roots, 1 = first root only, 0x0100 = second root only, 0x0101 = both.
pub inline fn calcRootCode(y1: f32, y2: f32, y3: f32) u16 {
    const s1: u32 = @as(u32, @bitCast(rootCodeCoord(y1))) >> 31;
    const s2: u32 = @as(u32, @bitCast(rootCodeCoord(y2))) >> 30;
    const s3: u32 = @as(u32, @bitCast(rootCodeCoord(y3))) >> 29;

    // Replicate the GLSL bit manipulation
    const shift_a: u32 = (s2 & 2) | (s1 & ~@as(u32, 2));
    const shift: u32 = (s3 & 4) | (shift_a & ~@as(u32, 4));

    return @as(u16, @intCast((@as(u32, 0x2E74) >> @as(u5, @intCast(shift & 0x1F))) & 0x0101));
}

/// Solve horizontal polynomial: find x-intersections for a horizontal ray.
/// p12 = (p1.x, p1.y, p2.x, p2.y), p3 = (p3.x, p3.y), all relative to pixel.
/// Returns two x-distances scaled by ppe_x.
pub inline fn solveHorizPoly(p1x: f32, p1y: f32, p2x: f32, p2y: f32, p3x: f32, p3y: f32, ppe_x: f32) [2]f32 {
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
        const sq = snapNearTangentSqrt(by * by - ay * p1y, by, ay * p1y);
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
pub inline fn solveVertPoly(p1x: f32, p1y: f32, p2x: f32, p2y: f32, p3x: f32, p3y: f32, ppe_y: f32) [2]f32 {
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
        const sq = snapNearTangentSqrt(bx * bx - ax * p1x, bx, ax * p1x);
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

test "monotonic cubic crossing gives a shared endpoint to one span" {
    const no_start_crossing = solveMonotonicCubicCrossing(0, 0, 1, 0, 1);
    try std.testing.expectEqual(@as(u8, 0), no_start_crossing.count);

    const owned_end = solveMonotonicCubicCrossing(0, 0, 1, -1, 0);
    try std.testing.expectEqual(@as(u8, 1), owned_end.count);
    try std.testing.expectEqual(@as(f32, 1), owned_end.t[0]);

    const owned_start = solveMonotonicCubicCrossing(0, 0, -1, 0, -1);
    try std.testing.expectEqual(@as(u8, 1), owned_start.count);
    try std.testing.expectEqual(@as(f32, 0), owned_start.t[0]);

    const no_end_crossing = solveMonotonicCubicCrossing(0, 0, -1, 1, 0);
    try std.testing.expectEqual(@as(u8, 0), no_end_crossing.count);
}
