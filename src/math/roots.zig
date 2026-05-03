const std = @import("std");
const vec = @import("vec.zig");
const bezier_mod = @import("bezier.zig");
const Vec2 = vec.Vec2;
const QuadBezier = bezier_mod.QuadBezier;

pub const Roots = struct {
    count: u2 = 0,
    t: [2]f32 = .{ 0, 0 },
};

/// Solve at^2 + bt + c = 0 for t in [0, 1].
/// Uses discriminant clamping for numerical stability.
pub fn solveQuadratic(a: f32, b: f32, c_val: f32) Roots {
    var result = Roots{};

    if (@abs(a) < 1e-10) {
        // Linear: bt + c = 0
        if (@abs(b) < 1e-10) return result;
        const t = -c_val / b;
        if (t >= 0.0 and t <= 1.0) {
            result.t[0] = t;
            result.count = 1;
        }
        return result;
    }

    var disc = b * b - 4.0 * a * c_val;
    if (disc < 0.0) {
        // Clamp small negative discriminants (numerical noise)
        if (disc > -1e-6) {
            disc = 0.0;
        } else {
            return result;
        }
    }

    const sqrt_disc = @sqrt(disc);
    const inv_2a = 0.5 / a;

    const t0 = (-b - sqrt_disc) * inv_2a;
    const t1 = (-b + sqrt_disc) * inv_2a;

    if (t0 >= 0.0 and t0 <= 1.0) {
        result.t[result.count] = t0;
        result.count += 1;
    }
    if (t1 >= 0.0 and t1 <= 1.0 and @abs(t1 - t0) > 1e-8) {
        result.t[result.count] = t1;
        result.count += 1;
    }

    return result;
}

/// Find parameter values where a quadratic Bezier crosses y = py (horizontal ray).
/// Returns roots for: B_y(t) - py = 0
pub fn solveHorizontal(curve: QuadBezier, py: f32) Roots {
    // B_y(t) = (1-t)^2*p0.y + 2(1-t)t*p1.y + t^2*p2.y
    // Expand: (p0 - 2p1 + p2)t^2 + (-2p0 + 2p1)t + p0 - py = 0
    const a = curve.p0.y - 2.0 * curve.p1.y + curve.p2.y;
    const b = 2.0 * (curve.p1.y - curve.p0.y);
    const c_val = curve.p0.y - py;
    return solveQuadratic(a, b, c_val);
}

/// Find parameter values where a quadratic Bezier crosses x = px (vertical ray).
pub fn solveVertical(curve: QuadBezier, px: f32) Roots {
    const a = curve.p0.x - 2.0 * curve.p1.x + curve.p2.x;
    const b = 2.0 * (curve.p1.x - curve.p0.x);
    const c_val = curve.p0.x - px;
    return solveQuadratic(a, b, c_val);
}

/// Root sign classification using control point sign patterns.
/// This is the core Slug innovation: determines winding contribution
/// based on the signs of the control points relative to the ray,
/// avoiding numerical issues with tangent cases.
///
/// For a horizontal ray at y=py, we look at the signs of (p0.y-py), (p1.y-py), (p2.y-py).
/// The root contributes +1 if the curve crosses from below to above, -1 if above to below.
pub fn classifyHorizontalRoot(curve: QuadBezier, py: f32, t: f32) i2 {
    _ = t;
    // Derivative at crossing: B'_y(t) = 2(1-t)(p1.y-p0.y) + 2t(p2.y-p1.y)
    // Sign of derivative determines direction of crossing.
    // But Slug uses control point signs for robustness.
    const s0 = curve.p0.y - py;
    const s2 = curve.p2.y - py;

    // If start is below and end is above (or vice versa), simple case
    if (s0 < 0 and s2 >= 0) return 1;
    if (s0 >= 0 and s2 < 0) return -1;

    // Same side: the curve crosses twice. Determine from the control point.
    const s1 = curve.p1.y - py;
    if (s0 >= 0 and s1 < 0) return -1; // dips below then back up
    if (s0 < 0 and s1 >= 0) return 1; // rises above then back down

    return 0;
}

/// Classify vertical ray crossing
pub fn classifyVerticalRoot(curve: QuadBezier, px: f32, t: f32) i2 {
    _ = t;
    const s0 = curve.p0.x - px;
    const s2 = curve.p2.x - px;

    if (s0 < 0 and s2 >= 0) return 1;
    if (s0 >= 0 and s2 < 0) return -1;

    const s1 = curve.p1.x - px;
    if (s0 >= 0 and s1 < 0) return -1;
    if (s0 < 0 and s1 >= 0) return 1;

    return 0;
}

/// Compute winding number for a point relative to a set of curves.
/// Uses horizontal ray casting: count signed crossings where x > px.
fn windingNumber(curves: []const QuadBezier, point: Vec2) f32 {
    var winding: f32 = 0;

    for (curves) |curve| {
        const roots = solveHorizontal(curve, point.y);
        for (0..roots.count) |i| {
            const t = roots.t[i];
            // Evaluate x at this t
            const mt = 1.0 - t;
            const x = mt * mt * curve.p0.x + 2.0 * mt * t * curve.p1.x + t * t * curve.p2.x;
            if (x > point.x) {
                const sign = classifyHorizontalRoot(curve, point.y, t);
                winding += @as(f32, @floatFromInt(sign));
            }
        }
    }

    return winding;
}

/// Check if a point is inside a shape defined by curves (nonzero fill rule)
pub fn isInside(curves: []const QuadBezier, point: Vec2) bool {
    return @abs(windingNumber(curves, point)) > 0.5;
}

test "solveQuadratic basic" {
    // t^2 - 1 = 0 → t = ±1, only t=1 in [0,1]
    const r1 = solveQuadratic(1, 0, -1);
    try std.testing.expectEqual(@as(u2, 1), r1.count);
    try std.testing.expectApproxEqAbs(r1.t[0], 1.0, 1e-6);

    // t^2 - t = 0 → t(t-1) = 0 → t=0,1
    const r2 = solveQuadratic(1, -1, 0);
    try std.testing.expectEqual(@as(u2, 2), r2.count);
}

test "solveQuadratic linear fallback" {
    // 2t - 1 = 0 → t = 0.5
    const r = solveQuadratic(0, 2, -1);
    try std.testing.expectEqual(@as(u2, 1), r.count);
    try std.testing.expectApproxEqAbs(r.t[0], 0.5, 1e-6);
}

test "winding number for square" {
    // Square from (0,0) to (1,1) defined as 4 linear segments (degenerate quadratics)
    const curves = [_]QuadBezier{
        // Bottom: (0,0) → (1,0)
        .{ .p0 = Vec2.new(0, 0), .p1 = Vec2.new(0.5, 0), .p2 = Vec2.new(1, 0) },
        // Right: (1,0) → (1,1)
        .{ .p0 = Vec2.new(1, 0), .p1 = Vec2.new(1, 0.5), .p2 = Vec2.new(1, 1) },
        // Top: (1,1) → (0,1)
        .{ .p0 = Vec2.new(1, 1), .p1 = Vec2.new(0.5, 1), .p2 = Vec2.new(0, 1) },
        // Left: (0,1) → (0,0)
        .{ .p0 = Vec2.new(0, 1), .p1 = Vec2.new(0, 0.5), .p2 = Vec2.new(0, 0) },
    };

    // Center should be inside
    try std.testing.expect(isInside(&curves, Vec2.new(0.5, 0.5)));
    // Outside should not be
    try std.testing.expect(!isInside(&curves, Vec2.new(2, 0.5)));
    try std.testing.expect(!isInside(&curves, Vec2.new(-1, 0.5)));
}

test "winding number for circle approximation" {
    // Approximate circle with 4 quadratic arcs
    const r: f32 = 1.0;
    const k: f32 = 0.55228; // control point factor for circle approx
    const curves = [_]QuadBezier{
        // Right to top
        .{ .p0 = Vec2.new(r, 0), .p1 = Vec2.new(r, k), .p2 = Vec2.new(k, r) },
        // Top to left (via (0,r))
        .{ .p0 = Vec2.new(k, r), .p1 = Vec2.new(0, r), .p2 = Vec2.new(-k, r) },
        .{ .p0 = Vec2.new(-k, r), .p1 = Vec2.new(-r, k), .p2 = Vec2.new(-r, 0) },
        // Left to bottom
        .{ .p0 = Vec2.new(-r, 0), .p1 = Vec2.new(-r, -k), .p2 = Vec2.new(-k, -r) },
        .{ .p0 = Vec2.new(-k, -r), .p1 = Vec2.new(0, -r), .p2 = Vec2.new(k, -r) },
        // Bottom to right
        .{ .p0 = Vec2.new(k, -r), .p1 = Vec2.new(r, -k), .p2 = Vec2.new(r, 0) },
    };

    // Center should be inside
    try std.testing.expect(isInside(&curves, Vec2.new(0, 0)));
    // Far outside should not be
    try std.testing.expect(!isInside(&curves, Vec2.new(3, 0)));
}
