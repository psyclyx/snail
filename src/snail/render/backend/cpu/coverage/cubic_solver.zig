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
const bezier = @import("../../../../math/bezier.zig");
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
pub fn appendCurveRoot(roots: *CurveRoots, t: f32) void {
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

pub fn solveQuadraticRoots(a: f32, b: f32, c_val: f32) CurveRoots {
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

pub fn solveCubicRoots(a: f32, b: f32, c_val: f32, d: f32) CurveRoots {
    // Cardano is numerically unstable when the cubic term is small relative
    // to the lower-order terms — a t∈[0,1] root computed via the trig branch
    // can drift by O(1) when |a| < ~1% of the dominant coefficient. The
    // split-at-extrema pass occasionally produces such near-quadratic pieces
    // (e.g. one half of the leaf primitive's right cubic, where the original
    // y-coefficients nearly cancel), so fall back to the quadratic solver
    // when the cubic term contributes less than ~0.01× the rest over t∈[0,1].
    const cubic_scale = @abs(a);
    const lower_scale = @abs(b) + @abs(c_val) + @abs(d);
    if (cubic_scale < 1e-2 * @max(lower_scale, 1.0)) return solveQuadraticRoots(b, c_val, d);
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

pub fn solveSegmentHorizontalRoots(segment: CurveSegment, py: f32) CurveRoots {
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

pub fn solveSegmentVerticalRoots(segment: CurveSegment, px: f32) CurveRoots {
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

/// Tight upper bound on the curve's x-coordinate over t ∈ [0, 1].
/// For a Bezier the curve lies inside its convex hull, so the max of
/// the control points is a safe bound.
pub fn segmentMaxX(segment: CurveSegment) f32 {
    if (segment.kind == .line) return @max(segment.p0.x, segment.p2.x);
    var result = @max(@max(segment.p0.x, segment.p1.x), segment.p2.x);
    if (segment.kind == .cubic) result = @max(result, segment.p3.x);
    return result;
}

pub fn segmentMaxY(segment: CurveSegment) f32 {
    if (segment.kind == .line) return @max(segment.p0.y, segment.p2.y);
    var result = @max(@max(segment.p0.y, segment.p1.y), segment.p2.y);
    if (segment.kind == .cubic) result = @max(result, segment.p3.y);
    return result;
}

pub fn segmentMinX(segment: CurveSegment) f32 {
    if (segment.kind == .line) return @min(segment.p0.x, segment.p2.x);
    var result = @min(@min(segment.p0.x, segment.p1.x), segment.p2.x);
    if (segment.kind == .cubic) result = @min(result, segment.p3.x);
    return result;
}

pub fn segmentMinY(segment: CurveSegment) f32 {
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
pub fn calcRootCode(y1: f32, y2: f32, y3: f32) u16 {
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
pub fn solveHorizPoly(p1x: f32, p1y: f32, p2x: f32, p2y: f32, p3x: f32, p3y: f32, ppe_x: f32) [2]f32 {
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
pub fn solveVertPoly(p1x: f32, p1y: f32, p2x: f32, p2y: f32, p3x: f32, p3y: f32, ppe_y: f32) [2]f32 {
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
