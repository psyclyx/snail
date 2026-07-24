//! Quadratic root-code and polynomial helpers used by the software
//! coverage evaluator.
//!
//! Functions here are pure (no PreparedAxisCurve / band-data references).
//! They implement the compact Slug-style quadratic evaluator shared by the
//! scalar and prepared CPU paths.

const std = @import("std");
const bezier = @import("snail").render.geometry;
const CurveSegment = bezier.CurveSegment;

pub const coord_eps: f32 = 1.0 / 65536.0;

pub inline fn rootCodeCoord(v: f32) f32 {
    return if (@abs(v) <= coord_eps) 0.0 else v;
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

test "root code stabilizes tiny shared-endpoint drift" {
    try std.testing.expectEqual(calcRootCode(0.0, -0.25, -0.5), calcRootCode(-coord_eps * 0.5, -0.25, -0.5));
    try std.testing.expectEqual(@as(u16, 0), calcRootCode(-coord_eps * 2.0, -0.25, -0.5));
}
