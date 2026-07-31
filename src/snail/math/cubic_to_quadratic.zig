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
//! bounds the distance between the curves over the whole span. Every f64
//! subdivision operation carries an absolute roundoff enclosure into that
//! certificate; the final emitted f32 control points are certified directly.

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
/// Cap on the analytic piece count for one critical-root span before the
/// bisection fallback takes over. Spans are extrema/inflection-free after the
/// critical split, so a handful is the norm; this only bounds pathological
/// curvature. The fallback preserves the tolerance guarantee regardless.
pub const max_pieces: u32 = 32;
const max_bisect_depth: u8 = 96;
const max_output_segments: usize = std.math.maxInt(u16);

const Vec2d = struct {
    x: f64,
    y: f64,
    err_x: f64 = 0,
    err_y: f64 = 0,

    fn from(point: Vec2) Vec2d {
        return .{ .x = point.x, .y = point.y };
    }

    fn add(a: Vec2d, b: Vec2d) Vec2d {
        return .{
            .x = a.x + b.x,
            .y = a.y + b.y,
            .err_x = a.err_x + b.err_x + arithmeticSlack(@abs(a.x) + @abs(b.x)),
            .err_y = a.err_y + b.err_y + arithmeticSlack(@abs(a.y) + @abs(b.y)),
        };
    }

    fn sub(a: Vec2d, b: Vec2d) Vec2d {
        return .{
            .x = a.x - b.x,
            .y = a.y - b.y,
            .err_x = a.err_x + b.err_x + arithmeticSlack(@abs(a.x) + @abs(b.x)),
            .err_y = a.err_y + b.err_y + arithmeticSlack(@abs(a.y) + @abs(b.y)),
        };
    }

    fn scale(a: Vec2d, scalar: f64) Vec2d {
        return .{
            .x = a.x * scalar,
            .y = a.y * scalar,
            .err_x = @abs(scalar) * a.err_x + arithmeticSlack(@abs(a.x * scalar)),
            .err_y = @abs(scalar) * a.err_y + arithmeticSlack(@abs(a.y * scalar)),
        };
    }

    fn divide(a: Vec2d, divisor: f64) Vec2d {
        return .{
            .x = a.x / divisor,
            .y = a.y / divisor,
            .err_x = a.err_x / @abs(divisor) + arithmeticSlack(@abs(a.x / divisor)),
            .err_y = a.err_y / @abs(divisor) + arithmeticSlack(@abs(a.y / divisor)),
        };
    }
};

fn arithmeticSlack(magnitude: f64) f64 {
    return magnitude * (2.0 * std.math.floatEps(f64)) +
        2.0 * std.math.floatTrueMin(f64);
}

/// f64 working curve derived directly from the authored f32 cubic. All
/// subdivision remains in this domain and carries roundoff enclosures.
const Cubic64 = struct {
    p0: Vec2d,
    p1: Vec2d,
    p2: Vec2d,
    p3: Vec2d,

    fn from(curve: CubicBezier) Cubic64 {
        return .{
            .p0 = Vec2d.from(curve.p0),
            .p1 = Vec2d.from(curve.p1),
            .p2 = Vec2d.from(curve.p2),
            .p3 = Vec2d.from(curve.p3),
        };
    }

    fn split(self: Cubic64, t: f64) [2]Cubic64 {
        const p01 = lerp64(self.p0, self.p1, t);
        const p12 = lerp64(self.p1, self.p2, t);
        const p23 = lerp64(self.p2, self.p3, t);
        const p012 = lerp64(p01, p12, t);
        const p123 = lerp64(p12, p23, t);
        const p = lerp64(p012, p123, t);
        return .{
            .{ .p0 = self.p0, .p1 = p01, .p2 = p012, .p3 = p },
            .{ .p0 = p, .p1 = p123, .p2 = p23, .p3 = self.p3 },
        };
    }
};

fn lerp64(a: Vec2d, b: Vec2d, t: f64) Vec2d {
    return Vec2d.add(a, Vec2d.scale(Vec2d.sub(b, a), t));
}

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

fn cross64(a: Vec2d, b: Vec2d) f64 {
    return a.x * b.y - a.y * b.x;
}

fn averageDegreeReductionControl(curve: Cubic64) Vec2d {
    // The controls obtained by matching the start and end derivatives are
    // averaged. This is the minimum-error degree reduction when tangent lines
    // are parallel or intersect behind an endpoint.
    const from_start = Vec2d.scale(Vec2d.sub(Vec2d.scale(curve.p1, 3.0), curve.p0), 0.5);
    const from_end = Vec2d.scale(Vec2d.sub(Vec2d.scale(curve.p2, 3.0), curve.p3), 0.5);
    return Vec2d.scale(Vec2d.add(from_start, from_end), 0.5);
}

fn castPoint(point: Vec2d) error{ToleranceUnrepresentable}!Vec2 {
    const limit = std.math.floatMax(f32);
    if (!std.math.isFinite(point.x) or !std.math.isFinite(point.y) or
        @abs(point.x) > limit or @abs(point.y) > limit)
    {
        return error.ToleranceUnrepresentable;
    }
    return .{ .x = @floatCast(point.x), .y = @floatCast(point.y) };
}

fn tangentFit(curve: Cubic64) error{ToleranceUnrepresentable}!QuadBezier {
    const start_tangent = Vec2d.sub(curve.p1, curve.p0);
    const end_tangent = Vec2d.sub(curve.p3, curve.p2);
    const between = Vec2d.sub(curve.p3, curve.p0);
    const denom = cross64(start_tangent, end_tangent);
    const start_length = @sqrt(start_tangent.x * start_tangent.x + start_tangent.y * start_tangent.y);
    const end_length = @sqrt(end_tangent.x * end_tangent.x + end_tangent.y * end_tangent.y);
    const scale = start_length * end_length;

    var control = averageDegreeReductionControl(curve);
    if (scale > 0.0 and @abs(denom) > scale * 64.0 * std.math.floatEps(f64)) {
        const start_distance = cross64(between, end_tangent) / denom;
        const end_distance = cross64(between, start_tangent) / denom;
        // p0 + s*d0 == p3 + u*d1. Forward endpoint tangents require s >= 0
        // and u <= 0 so p3-control points in d1's direction.
        if (start_distance >= 0.0 and end_distance <= 0.0) {
            control = Vec2d.add(curve.p0, Vec2d.scale(start_tangent, start_distance));
        }
    }
    return .{
        .p0 = try castPoint(curve.p0),
        .p1 = try castPoint(control),
        .p2 = try castPoint(curve.p3),
    };
}

fn distanceUpper(a: Vec2d, b: Vec2d) f64 {
    const delta = Vec2d.sub(a, b);
    const measured = @sqrt(delta.x * delta.x + delta.y * delta.y);
    // Triangle inequality carries the coordinate enclosures. The final term
    // encloses multiply/add/sqrt rounding in the measured norm.
    return measured + delta.err_x + delta.err_y +
        arithmeticSlack(8.0 * (@abs(delta.x) + @abs(delta.y)));
}

fn fitErrorBound(curve: Cubic64, quad: QuadBezier) f64 {
    const q0 = Vec2d.from(quad.p0);
    const q1 = Vec2d.from(quad.p1);
    const q2 = Vec2d.from(quad.p2);
    const elevated1 = Vec2d.divide(Vec2d.add(q0, Vec2d.scale(q1, 2.0)), 3.0);
    const elevated2 = Vec2d.divide(Vec2d.add(Vec2d.scale(q1, 2.0), q2), 3.0);
    return @max(
        @max(distanceUpper(curve.p0, q0), distanceUpper(curve.p1, elevated1)),
        @max(distanceUpper(curve.p2, elevated2), distanceUpper(curve.p3, q2)),
    );
}

fn appendCertified(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(CurveSegment),
    quad: QuadBezier,
) !void {
    if (out.items.len >= max_output_segments) return error.ShapeTooComplex;
    try out.append(allocator, CurveSegment.fromQuad(quad));
}

fn appendSpan(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(CurveSegment),
    curve: Cubic64,
    tolerance: f32,
) !void {
    const quad = try tangentFit(curve);
    const err = fitErrorBound(curve, quad);
    const tolerance64: f64 = tolerance;
    if (err <= tolerance64) {
        try appendCertified(allocator, out, quad);
        return;
    }
    // The degree-reduction error scales as 1/n^3 under uniform subdivision (a
    // sub-cubic on a length-1/n interval has leading coefficient a/n^3), so the
    // piece count follows directly from the whole-span error — no need to
    // bisect and re-fit every internal node, and no rounding up to a power of
    // two. Each piece is verified; the rare one the estimate under-splits falls
    // back to bounded bisection so the tolerance guarantee is exact.
    const estimate = @ceil(std.math.cbrt(err / tolerance64));
    const n: u32 = if (!std.math.isFinite(estimate) or estimate >= max_pieces)
        max_pieces
    else
        @max(2, @as(u32, @intFromFloat(estimate)));
    var remaining = curve;
    var i: u32 = 0;
    while (i + 1 < n) : (i += 1) {
        const local_t = 1.0 / @as(f64, @floatFromInt(n - i));
        const halves = remaining.split(local_t);
        try appendPiece(allocator, out, halves[0], tolerance);
        remaining = halves[1];
    }
    try appendPiece(allocator, out, remaining, tolerance);
}

/// Fit one uniform sub-piece; bisect (bounded) only if the analytic estimate
/// left it over tolerance.
fn appendPiece(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(CurveSegment),
    curve: Cubic64,
    tolerance: f32,
) !void {
    const quad = try tangentFit(curve);
    if (fitErrorBound(curve, quad) <= @as(f64, tolerance)) {
        try appendCertified(allocator, out, quad);
        return;
    }
    try appendSpanBisect(allocator, out, curve, tolerance, max_bisect_depth);
}

fn appendSpanBisect(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(CurveSegment),
    curve: Cubic64,
    tolerance: f32,
    depth: u8,
) !void {
    const quad = try tangentFit(curve);
    if (fitErrorBound(curve, quad) <= @as(f64, tolerance)) {
        try appendCertified(allocator, out, quad);
        return;
    }
    if (depth == 0) return error.ToleranceUnrepresentable;
    const halves = curve.split(0.5);
    try appendSpanBisect(allocator, out, halves[0], tolerance, depth - 1);
    try appendSpanBisect(allocator, out, halves[1], tolerance, depth - 1);
}

fn appendCubic(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(CurveSegment),
    curve: CubicBezier,
    tolerance: f32,
) !void {
    const critical = criticalRoots(curve);
    var remaining = Cubic64.from(curve);
    var previous_t: f64 = 0.0;
    for (critical.values[0..critical.count]) |root| {
        const local_t = (root - previous_t) / (1.0 - previous_t);
        if (!(local_t > 0.0 and local_t < 1.0)) continue;
        const halves = remaining.split(local_t);
        try appendSpan(allocator, out, halves[0], tolerance);
        remaining = halves[1];
        previous_t = root;
    }
    try appendSpan(allocator, out, remaining, tolerance);
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
            if (out.items.len >= max_output_segments) return error.ShapeTooComplex;
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

test "unrepresentable tolerance fails instead of accepting an uncertified fit" {
    const cubic = CurveSegment.fromCubic(.{
        .p0 = .{ .x = 0.125, .y = -0.25 },
        .p1 = .{ .x = 1.0, .y = 2.0 },
        .p2 = .{ .x = -1.0, .y = 2.0 },
        .p3 = .{ .x = 0.375, .y = 0.25 },
    });
    try std.testing.expectError(
        error.ToleranceUnrepresentable,
        lower(std.testing.allocator, &.{cubic}, 1.0e-20),
    );
}

test "lower preserves non-cubic segments" {
    const line = CurveSegment.fromLine(.zero, .{ .x = 1, .y = 2 });
    const lowered = try lower(std.testing.allocator, &.{line}, default_tolerance);
    defer std.testing.allocator.free(lowered);
    try std.testing.expectEqualSlices(CurveSegment, &.{line}, lowered);
}
