//! Adaptive cubic-to-quadratic Bézier lowering for Slug coverage.
//!
//! Slug's robust root-eligibility lookup is quadratic. Cubic outlines are
//! therefore reduced during preparation instead of carrying a cubic root
//! finder into every fragment shader. Each accepted quadratic shares the
//! cubic span's endpoints and, whenever its endpoint tangent lines have a
//! forward intersection, its control point lies on both tangent lines.
//!
//! The acceptance test is conservative: the quadratic is degree-elevated to
//! a cubic, and the convex hull of the two interior control-point differences
//! bounds the distance between the curves over the whole span.

const std = @import("std");
const bezier = @import("bezier.zig");
const vec = @import("vec.zig");

const CubicBezier = bezier.CubicBezier;
const CurveSegment = bezier.CurveSegment;
const QuadBezier = bezier.QuadBezier;
const Vec2 = vec.Vec2;

/// Prepared paths occupy roughly [-1, 1], and font outlines use em space.
/// This is one quarter of an f16 ULP at unit magnitude, matching the prepared
/// stroke-offset budget.
pub const default_tolerance: f32 = 1.0 / 8192.0;
pub const max_depth: u8 = 10;

const CriticalRoots = struct {
    values: [6]f64 = .{ 0, 0, 0, 0, 0, 0 },
    count: usize = 0,

    fn append(self: *CriticalRoots, value: f64) void {
        if (!(value > 0.0 and value < 1.0) or !std.math.isFinite(value)) return;
        for (self.values[0..self.count]) |existing| {
            if (@abs(existing - value) <= 64.0 * std.math.floatEps(f64)) return;
        }
        var at = self.count;
        while (at > 0 and self.values[at - 1] > value) : (at -= 1) {}
        var i = self.count;
        while (i > at) : (i -= 1) self.values[i] = self.values[i - 1];
        self.values[at] = value;
        self.count += 1;
    }
};

fn appendPolynomialRoots(roots: *CriticalRoots, a: f64, b: f64, c: f64) void {
    const scale = @max(@abs(a), @max(@abs(b), @abs(c)));
    if (scale == 0.0) return;
    const eps = scale * 64.0 * std.math.floatEps(f64);
    if (@abs(a) <= eps) {
        if (@abs(b) > eps) roots.append(-c / b);
        return;
    }

    var disc = b * b - 4.0 * a * c;
    const disc_eps = @max(b * b, @abs(4.0 * a * c)) * 64.0 * std.math.floatEps(f64);
    if (disc < 0.0) {
        if (disc < -disc_eps) return;
        disc = 0.0;
    }
    const sqrt_disc = @sqrt(disc);
    const q = -0.5 * (b + if (b >= 0.0) sqrt_disc else -sqrt_disc);
    if (@abs(q) <= eps) {
        roots.append(-b / (2.0 * a));
        return;
    }
    roots.append(q / a);
    roots.append(c / q);
}

fn powerCoefficients(curve: CubicBezier, comptime field: []const u8) [3]f64 {
    const p0: f64 = @field(curve.p0, field);
    const p1: f64 = @field(curve.p1, field);
    const p2: f64 = @field(curve.p2, field);
    const p3: f64 = @field(curve.p3, field);
    return .{
        -p0 + 3.0 * p1 - 3.0 * p2 + p3,
        3.0 * p0 - 6.0 * p1 + 3.0 * p2,
        -3.0 * p0 + 3.0 * p1,
    };
}

fn criticalRoots(curve: CubicBezier) CriticalRoots {
    var roots = CriticalRoots{};
    const x = powerCoefficients(curve, "x");
    const y = powerCoefficients(curve, "y");

    // Axis extrema preserve the positions at which Slug's horizontal and
    // vertical crossing topology changes.
    appendPolynomialRoots(&roots, 3.0 * x[0], 2.0 * x[1], x[2]);
    appendPolynomialRoots(&roots, 3.0 * y[0], 2.0 * y[1], y[2]);

    // Inflections satisfy cross(C'(t), C''(t)) = 0. In power basis this is
    // -6 cross(a,b)t² + 6 cross(c,a)t + 2 cross(c,b).
    const cross_ab = x[0] * y[1] - y[0] * x[1];
    const cross_ca = x[2] * y[0] - y[2] * x[0];
    const cross_cb = x[2] * y[1] - y[2] * x[1];
    appendPolynomialRoots(&roots, -6.0 * cross_ab, 6.0 * cross_ca, 2.0 * cross_cb);
    return roots;
}

fn cross(a: Vec2, b: Vec2) f64 {
    return @as(f64, a.x) * @as(f64, b.y) - @as(f64, a.y) * @as(f64, b.x);
}

fn averageDegreeReductionControl(curve: CubicBezier) Vec2 {
    // The controls obtained by matching the start and end derivatives are
    // averaged. This is the minimum-error degree reduction when tangent lines
    // are parallel or intersect behind an endpoint.
    const from_start = Vec2.scale(Vec2.sub(Vec2.scale(curve.p1, 3.0), curve.p0), 0.5);
    const from_end = Vec2.scale(Vec2.sub(Vec2.scale(curve.p2, 3.0), curve.p3), 0.5);
    return Vec2.scale(Vec2.add(from_start, from_end), 0.5);
}

fn tangentFit(curve: CubicBezier) QuadBezier {
    const start_tangent = Vec2.sub(curve.p1, curve.p0);
    const end_tangent = Vec2.sub(curve.p3, curve.p2);
    const between = Vec2.sub(curve.p3, curve.p0);
    const denom = cross(start_tangent, end_tangent);
    const scale = @as(f64, Vec2.length(start_tangent)) * @as(f64, Vec2.length(end_tangent));

    var control = averageDegreeReductionControl(curve);
    if (scale > 0.0 and @abs(denom) > scale * 64.0 * std.math.floatEps(f32)) {
        const start_distance = cross(between, end_tangent) / denom;
        const end_distance = cross(between, start_tangent) / denom;
        // p0 + s*d0 == p3 + u*d1. Forward endpoint tangents require s >= 0
        // and u <= 0 so p3-control points in d1's direction.
        if (start_distance >= 0.0 and end_distance <= 0.0) {
            control = Vec2.add(curve.p0, Vec2.scale(start_tangent, @floatCast(start_distance)));
        }
    }
    return .{ .p0 = curve.p0, .p1 = control, .p2 = curve.p3 };
}

fn fitErrorBound(curve: CubicBezier, quad: QuadBezier) f32 {
    const elevated1 = Vec2.add(Vec2.scale(quad.p0, 1.0 / 3.0), Vec2.scale(quad.p1, 2.0 / 3.0));
    const elevated2 = Vec2.add(Vec2.scale(quad.p1, 2.0 / 3.0), Vec2.scale(quad.p2, 1.0 / 3.0));
    return @max(
        Vec2.length(Vec2.sub(curve.p1, elevated1)),
        Vec2.length(Vec2.sub(curve.p2, elevated2)),
    );
}

fn appendSpan(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(CurveSegment),
    curve: CubicBezier,
    tolerance: f32,
    depth: u8,
) !void {
    const quad = tangentFit(curve);
    if (depth == 0 or fitErrorBound(curve, quad) <= tolerance) {
        try out.append(allocator, CurveSegment.fromQuad(quad));
        return;
    }
    const halves = curve.split(0.5);
    try appendSpan(allocator, out, halves[0], tolerance, depth - 1);
    try appendSpan(allocator, out, halves[1], tolerance, depth - 1);
}

fn appendCubic(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(CurveSegment),
    curve: CubicBezier,
    tolerance: f32,
) !void {
    const critical = criticalRoots(curve);
    var remaining = curve;
    var previous_t: f64 = 0.0;
    for (critical.values[0..critical.count]) |root| {
        const local_t64 = (root - previous_t) / (1.0 - previous_t);
        const local_t: f32 = @floatCast(local_t64);
        if (!(local_t > 0.0 and local_t < 1.0)) continue;
        const halves = remaining.split(local_t);
        try appendSpan(allocator, out, halves[0], tolerance, max_depth);
        remaining = halves[1];
        previous_t = root;
    }
    try appendSpan(allocator, out, remaining, tolerance, max_depth);
}

pub fn lower(
    allocator: std.mem.Allocator,
    curves: []const CurveSegment,
    tolerance: f32,
) ![]CurveSegment {
    if (!std.math.isFinite(tolerance) or tolerance <= 0.0) return error.InvalidTolerance;
    var out: std.ArrayList(CurveSegment) = .empty;
    errdefer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, curves.len);
    for (curves) |curve| {
        if (curve.kind == .cubic) {
            try appendCubic(allocator, &out, curve.asCubic(), tolerance);
        } else {
            try out.append(allocator, curve);
        }
    }
    return out.toOwnedSlice(allocator);
}

test "exact degree-elevated quadratic stays exact across critical splits" {
    const expected = QuadBezier{
        .p0 = .{ .x = 0, .y = 0 },
        .p1 = .{ .x = 1, .y = 2 },
        .p2 = .{ .x = 3, .y = 0 },
    };
    const cubic = CurveSegment.fromCubic(.{
        .p0 = expected.p0,
        .p1 = Vec2.add(Vec2.scale(expected.p0, 1.0 / 3.0), Vec2.scale(expected.p1, 2.0 / 3.0)),
        .p2 = Vec2.add(Vec2.scale(expected.p1, 2.0 / 3.0), Vec2.scale(expected.p2, 1.0 / 3.0)),
        .p3 = expected.p2,
    });
    const lowered = try lower(std.testing.allocator, &.{cubic}, default_tolerance);
    defer std.testing.allocator.free(lowered);

    try std.testing.expectEqual(@as(usize, 2), lowered.len);
    try std.testing.expectEqual(bezier.CurveKind.quadratic, lowered[0].kind);
    try std.testing.expectEqual(bezier.CurveKind.quadratic, lowered[1].kind);
    try std.testing.expectEqual(expected.p0, lowered[0].p0);
    try std.testing.expectEqual(expected.p2, lowered[1].p2);
    const expected_mid = expected.evaluate(0.5);
    try std.testing.expectApproxEqAbs(expected_mid.x, lowered[0].p2.x, 1e-5);
    try std.testing.expectApproxEqAbs(expected_mid.y, lowered[0].p2.y, 1e-5);
    try std.testing.expectEqual(lowered[0].p2, lowered[1].p0);
}

test "looping cubic lowers to a continuous quadratic chain" {
    const cubic = CurveSegment.fromCubic(.{
        .p0 = .{ .x = 0, .y = 0 },
        .p1 = .{ .x = 2, .y = 3 },
        .p2 = .{ .x = -2, .y = 3 },
        .p3 = .{ .x = 0, .y = 0.25 },
    });
    const lowered = try lower(std.testing.allocator, &.{cubic}, default_tolerance);
    defer std.testing.allocator.free(lowered);

    try std.testing.expect(lowered.len > 1);
    try std.testing.expectEqual(cubic.p0, lowered[0].p0);
    try std.testing.expectEqual(cubic.p3, lowered[lowered.len - 1].p2);
    for (lowered, 0..) |quad, i| {
        try std.testing.expectEqual(bezier.CurveKind.quadratic, quad.kind);
        if (i + 1 < lowered.len) try std.testing.expectEqual(quad.p2, lowered[i + 1].p0);
    }
}

test "lower preserves non-cubic segments" {
    const line = CurveSegment.fromLine(.zero, .{ .x = 1, .y = 2 });
    const lowered = try lower(std.testing.allocator, &.{line}, default_tolerance);
    defer std.testing.allocator.free(lowered);
    try std.testing.expectEqualSlices(CurveSegment, &.{line}, lowered);
}
