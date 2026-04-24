const std = @import("std");
const vec = @import("vec.zig");
const Vec2 = vec.Vec2;

fn bboxFromPoints(points: []const Vec2) BBox {
    std.debug.assert(points.len > 0);
    var min = points[0];
    var max = points[0];
    for (points[1..]) |point| {
        min = .{
            .x = @min(min.x, point.x),
            .y = @min(min.y, point.y),
        };
        max = .{
            .x = @max(max.x, point.x),
            .y = @max(max.y, point.y),
        };
    }
    return .{ .min = min, .max = max };
}

fn pointLineDistance(p: Vec2, a: Vec2, b: Vec2) f32 {
    const chord = Vec2.sub(b, a);
    const len = Vec2.length(chord);
    if (len < 1e-10) return Vec2.length(Vec2.sub(p, a));
    const normal = Vec2.new(-chord.y, chord.x);
    return @abs(Vec2.dot(Vec2.sub(p, a), normal)) / len;
}

pub const QuadBezier = struct {
    p0: Vec2,
    p1: Vec2,
    p2: Vec2,

    pub fn evaluate(self: QuadBezier, t: f32) Vec2 {
        const mt = 1.0 - t;
        return .{
            .x = mt * mt * self.p0.x + 2.0 * mt * t * self.p1.x + t * t * self.p2.x,
            .y = mt * mt * self.p0.y + 2.0 * mt * t * self.p1.y + t * t * self.p2.y,
        };
    }

    /// De Casteljau split at parameter t
    pub fn split(self: QuadBezier, t: f32) [2]QuadBezier {
        const mid01 = Vec2.lerp(self.p0, self.p1, t);
        const mid12 = Vec2.lerp(self.p1, self.p2, t);
        const mid = Vec2.lerp(mid01, mid12, t);
        return .{
            .{ .p0 = self.p0, .p1 = mid01, .p2 = mid },
            .{ .p0 = mid, .p1 = mid12, .p2 = self.p2 },
        };
    }

    /// Analytic bounding box (not just control point hull — includes extrema)
    pub fn boundingBox(self: QuadBezier) BBox {
        var min_x = @min(self.p0.x, self.p2.x);
        var max_x = @max(self.p0.x, self.p2.x);
        var min_y = @min(self.p0.y, self.p2.y);
        var max_y = @max(self.p0.y, self.p2.y);

        // Check extrema: derivative = 0 → t = (p0 - p1) / (p0 - 2*p1 + p2)
        inline for (.{ "x", "y" }) |axis| {
            const a = @field(self.p0, axis);
            const b = @field(self.p1, axis);
            const c = @field(self.p2, axis);
            const denom = a - 2.0 * b + c;
            if (@abs(denom) > 1e-10) {
                const t = (a - b) / denom;
                if (t > 0.0 and t < 1.0) {
                    const val = self.evaluateComponent(axis, t);
                    if (comptime std.mem.eql(u8, axis, "x")) {
                        min_x = @min(min_x, val);
                        max_x = @max(max_x, val);
                    } else {
                        min_y = @min(min_y, val);
                        max_y = @max(max_y, val);
                    }
                }
            }
        }

        return .{ .min = Vec2.new(min_x, min_y), .max = Vec2.new(max_x, max_y) };
    }

    fn evaluateComponent(self: QuadBezier, comptime axis: []const u8, t: f32) f32 {
        const mt = 1.0 - t;
        const a = @field(self.p0, axis);
        const b = @field(self.p1, axis);
        const c = @field(self.p2, axis);
        return mt * mt * a + 2.0 * mt * t * b + t * t * c;
    }

    /// Maximum deviation of control point from the chord p0-p2
    pub fn flatness(self: QuadBezier) f32 {
        return pointLineDistance(self.p1, self.p0, self.p2);
    }
};

pub const ConicBezier = struct {
    p0: Vec2,
    p1: Vec2,
    p2: Vec2,
    w0: f32 = 1.0,
    w1: f32,
    w2: f32 = 1.0,

    const HVec3 = struct {
        x: f32,
        y: f32,
        w: f32,

        fn lerp(a: HVec3, b: HVec3, t: f32) HVec3 {
            return .{
                .x = a.x + (b.x - a.x) * t,
                .y = a.y + (b.y - a.y) * t,
                .w = a.w + (b.w - a.w) * t,
            };
        }

        fn project(self: HVec3) struct { point: Vec2, weight: f32 } {
            const inv_w = 1.0 / @max(@abs(self.w), 1e-10);
            return .{
                .point = .{ .x = self.x * inv_w, .y = self.y * inv_w },
                .weight = self.w,
            };
        }
    };

    fn coeffs(t: f32) struct { b0: f32, b1: f32, b2: f32 } {
        const mt = 1.0 - t;
        return .{
            .b0 = mt * mt,
            .b1 = 2.0 * mt * t,
            .b2 = t * t,
        };
    }

    pub fn evaluate(self: ConicBezier, t: f32) Vec2 {
        const b = coeffs(t);
        const bw0 = b.b0 * self.w0;
        const bw1 = b.b1 * self.w1;
        const bw2 = b.b2 * self.w2;
        const denom = @max(bw0 + bw1 + bw2, 1e-10);
        return .{
            .x = (self.p0.x * bw0 + self.p1.x * bw1 + self.p2.x * bw2) / denom,
            .y = (self.p0.y * bw0 + self.p1.y * bw1 + self.p2.y * bw2) / denom,
        };
    }

    pub fn derivative(self: ConicBezier, t: f32) Vec2 {
        const mt = 1.0 - t;
        const b0 = mt * mt;
        const b1 = 2.0 * mt * t;
        const b2 = t * t;
        const db0 = -2.0 * mt;
        const db1 = 2.0 - 4.0 * t;
        const db2 = 2.0 * t;
        const bw0 = b0 * self.w0;
        const bw1 = b1 * self.w1;
        const bw2 = b2 * self.w2;
        const dbw0 = db0 * self.w0;
        const dbw1 = db1 * self.w1;
        const dbw2 = db2 * self.w2;
        const denom = @max(bw0 + bw1 + bw2, 1e-10);
        const denom_prime = dbw0 + dbw1 + dbw2;
        const nx = self.p0.x * bw0 + self.p1.x * bw1 + self.p2.x * bw2;
        const ny = self.p0.y * bw0 + self.p1.y * bw1 + self.p2.y * bw2;
        const nx_prime = self.p0.x * dbw0 + self.p1.x * dbw1 + self.p2.x * dbw2;
        const ny_prime = self.p0.y * dbw0 + self.p1.y * dbw1 + self.p2.y * dbw2;
        const inv = 1.0 / (denom * denom);
        return .{
            .x = (nx_prime * denom - nx * denom_prime) * inv,
            .y = (ny_prime * denom - ny * denom_prime) * inv,
        };
    }

    pub fn split(self: ConicBezier, t: f32) [2]ConicBezier {
        const h0 = HVec3{ .x = self.p0.x * self.w0, .y = self.p0.y * self.w0, .w = self.w0 };
        const h1 = HVec3{ .x = self.p1.x * self.w1, .y = self.p1.y * self.w1, .w = self.w1 };
        const h2 = HVec3{ .x = self.p2.x * self.w2, .y = self.p2.y * self.w2, .w = self.w2 };
        const h01 = HVec3.lerp(h0, h1, t);
        const h12 = HVec3.lerp(h1, h2, t);
        const h012 = HVec3.lerp(h01, h12, t);

        const left_p0 = h0.project();
        const left_p1 = h01.project();
        const left_p2 = h012.project();
        const right_p0 = h012.project();
        const right_p1 = h12.project();
        const right_p2 = h2.project();

        return .{
            .{
                .p0 = left_p0.point,
                .p1 = left_p1.point,
                .p2 = left_p2.point,
                .w0 = left_p0.weight,
                .w1 = left_p1.weight,
                .w2 = left_p2.weight,
            },
            .{
                .p0 = right_p0.point,
                .p1 = right_p1.point,
                .p2 = right_p2.point,
                .w0 = right_p0.weight,
                .w1 = right_p1.weight,
                .w2 = right_p2.weight,
            },
        };
    }

    pub fn boundingBox(self: ConicBezier) BBox {
        return bboxFromPoints(&.{ self.p0, self.p1, self.p2 });
    }

    pub fn flatness(self: ConicBezier) f32 {
        return pointLineDistance(self.p1, self.p0, self.p2);
    }
};

pub const CubicBezier = struct {
    p0: Vec2,
    p1: Vec2,
    p2: Vec2,
    p3: Vec2,

    pub fn evaluate(self: CubicBezier, t: f32) Vec2 {
        const mt = 1.0 - t;
        return .{
            .x = mt * mt * mt * self.p0.x + 3.0 * mt * mt * t * self.p1.x + 3.0 * mt * t * t * self.p2.x + t * t * t * self.p3.x,
            .y = mt * mt * mt * self.p0.y + 3.0 * mt * mt * t * self.p1.y + 3.0 * mt * t * t * self.p2.y + t * t * t * self.p3.y,
        };
    }

    pub fn derivative(self: CubicBezier, t: f32) Vec2 {
        const mt = 1.0 - t;
        return .{
            .x = 3.0 * mt * mt * (self.p1.x - self.p0.x) + 6.0 * mt * t * (self.p2.x - self.p1.x) + 3.0 * t * t * (self.p3.x - self.p2.x),
            .y = 3.0 * mt * mt * (self.p1.y - self.p0.y) + 6.0 * mt * t * (self.p2.y - self.p1.y) + 3.0 * t * t * (self.p3.y - self.p2.y),
        };
    }

    pub fn split(self: CubicBezier, t: f32) [2]CubicBezier {
        const p01 = Vec2.lerp(self.p0, self.p1, t);
        const p12 = Vec2.lerp(self.p1, self.p2, t);
        const p23 = Vec2.lerp(self.p2, self.p3, t);
        const p012 = Vec2.lerp(p01, p12, t);
        const p123 = Vec2.lerp(p12, p23, t);
        const p0123 = Vec2.lerp(p012, p123, t);
        return .{
            .{ .p0 = self.p0, .p1 = p01, .p2 = p012, .p3 = p0123 },
            .{ .p0 = p0123, .p1 = p123, .p2 = p23, .p3 = self.p3 },
        };
    }

    pub fn boundingBox(self: CubicBezier) BBox {
        return bboxFromPoints(&.{ self.p0, self.p1, self.p2, self.p3 });
    }

    pub fn flatness(self: CubicBezier) f32 {
        return @max(pointLineDistance(self.p1, self.p0, self.p3), pointLineDistance(self.p2, self.p0, self.p3));
    }
};

pub const CurveKind = enum(u16) {
    quadratic = 0,
    conic = 1,
    cubic = 2,
    line = 3,
};

pub const CurveSegment = struct {
    kind: CurveKind,
    p0: Vec2,
    p1: Vec2,
    p2: Vec2,
    p3: Vec2 = .zero,
    weights: [3]f32 = .{ 1.0, 1.0, 1.0 },

    pub fn fromQuad(curve: QuadBezier) CurveSegment {
        return .{
            .kind = .quadratic,
            .p0 = curve.p0,
            .p1 = curve.p1,
            .p2 = curve.p2,
        };
    }

    pub fn fromLine(p0: Vec2, p2: Vec2) CurveSegment {
        return .{
            .kind = .line,
            .p0 = p0,
            .p1 = Vec2.lerp(p0, p2, 0.5),
            .p2 = p2,
        };
    }

    pub fn fromConic(curve: ConicBezier) CurveSegment {
        return .{
            .kind = .conic,
            .p0 = curve.p0,
            .p1 = curve.p1,
            .p2 = curve.p2,
            .weights = .{ curve.w0, curve.w1, curve.w2 },
        };
    }

    pub fn fromCubic(curve: CubicBezier) CurveSegment {
        return .{
            .kind = .cubic,
            .p0 = curve.p0,
            .p1 = curve.p1,
            .p2 = curve.p2,
            .p3 = curve.p3,
        };
    }

    pub fn asQuad(self: CurveSegment) QuadBezier {
        std.debug.assert(self.kind == .quadratic);
        return .{ .p0 = self.p0, .p1 = self.p1, .p2 = self.p2 };
    }

    pub fn asConic(self: CurveSegment) ConicBezier {
        std.debug.assert(self.kind == .conic);
        return .{
            .p0 = self.p0,
            .p1 = self.p1,
            .p2 = self.p2,
            .w0 = self.weights[0],
            .w1 = self.weights[1],
            .w2 = self.weights[2],
        };
    }

    pub fn asCubic(self: CurveSegment) CubicBezier {
        std.debug.assert(self.kind == .cubic);
        return .{
            .p0 = self.p0,
            .p1 = self.p1,
            .p2 = self.p2,
            .p3 = self.p3,
        };
    }

    pub fn evaluate(self: CurveSegment, t: f32) Vec2 {
        return switch (self.kind) {
            .quadratic => self.asQuad().evaluate(t),
            .conic => self.asConic().evaluate(t),
            .cubic => self.asCubic().evaluate(t),
            .line => Vec2.lerp(self.p0, self.p2, t),
        };
    }

    pub fn derivative(self: CurveSegment, t: f32) Vec2 {
        return switch (self.kind) {
            .quadratic => blk: {
                const mt = 1.0 - t;
                break :blk .{
                    .x = 2.0 * mt * (self.p1.x - self.p0.x) + 2.0 * t * (self.p2.x - self.p1.x),
                    .y = 2.0 * mt * (self.p1.y - self.p0.y) + 2.0 * t * (self.p2.y - self.p1.y),
                };
            },
            .conic => self.asConic().derivative(t),
            .cubic => self.asCubic().derivative(t),
            .line => Vec2.sub(self.p2, self.p0),
        };
    }

    pub fn split(self: CurveSegment, t: f32) [2]CurveSegment {
        return switch (self.kind) {
            .quadratic => blk: {
                const halves = self.asQuad().split(t);
                break :blk .{ CurveSegment.fromQuad(halves[0]), CurveSegment.fromQuad(halves[1]) };
            },
            .conic => blk: {
                const halves = self.asConic().split(t);
                break :blk .{ CurveSegment.fromConic(halves[0]), CurveSegment.fromConic(halves[1]) };
            },
            .cubic => blk: {
                const halves = self.asCubic().split(t);
                break :blk .{ CurveSegment.fromCubic(halves[0]), CurveSegment.fromCubic(halves[1]) };
            },
            .line => blk: {
                const mid = Vec2.lerp(self.p0, self.p2, t);
                break :blk .{ CurveSegment.fromLine(self.p0, mid), CurveSegment.fromLine(mid, self.p2) };
            },
        };
    }

    pub fn boundingBox(self: CurveSegment) BBox {
        return switch (self.kind) {
            .quadratic => self.asQuad().boundingBox(),
            .conic => self.asConic().boundingBox(),
            .cubic => self.asCubic().boundingBox(),
            .line => bboxFromPoints(&.{ self.p0, self.p2 }),
        };
    }

    pub fn flatness(self: CurveSegment) f32 {
        return switch (self.kind) {
            .quadratic => self.asQuad().flatness(),
            .conic => self.asConic().flatness(),
            .cubic => self.asCubic().flatness(),
            .line => 0.0,
        };
    }

    pub fn endPoint(self: CurveSegment) Vec2 {
        return switch (self.kind) {
            .cubic => self.p3,
            .quadratic, .conic, .line => self.p2,
        };
    }
};

pub const BBox = struct {
    min: Vec2,
    max: Vec2,

    pub fn width(self: BBox) f32 {
        return self.max.x - self.min.x;
    }

    pub fn height(self: BBox) f32 {
        return self.max.y - self.min.y;
    }

    pub fn contains(self: BBox, p: Vec2) bool {
        return p.x >= self.min.x and p.x <= self.max.x and
            p.y >= self.min.y and p.y <= self.max.y;
    }

    pub fn intersects(self: BBox, other: BBox) bool {
        return self.min.x <= other.max.x and self.max.x >= other.min.x and
            self.min.y <= other.max.y and self.max.y >= other.min.y;
    }

    pub fn merge(self: BBox, other: BBox) BBox {
        return .{
            .min = Vec2.new(@min(self.min.x, other.min.x), @min(self.min.y, other.min.y)),
            .max = Vec2.new(@max(self.max.x, other.max.x), @max(self.max.y, other.max.y)),
        };
    }
};

test "QuadBezier evaluate endpoints" {
    const q = QuadBezier{
        .p0 = Vec2.new(0, 0),
        .p1 = Vec2.new(0.5, 1),
        .p2 = Vec2.new(1, 0),
    };
    const start = q.evaluate(0);
    try std.testing.expectApproxEqAbs(start.x, 0.0, 1e-6);
    try std.testing.expectApproxEqAbs(start.y, 0.0, 1e-6);
    const end = q.evaluate(1);
    try std.testing.expectApproxEqAbs(end.x, 1.0, 1e-6);
    try std.testing.expectApproxEqAbs(end.y, 0.0, 1e-6);
}

test "QuadBezier split preserves curve" {
    const q = QuadBezier{
        .p0 = Vec2.new(0, 0),
        .p1 = Vec2.new(0.5, 1),
        .p2 = Vec2.new(1, 0),
    };
    const halves = q.split(0.5);
    // The split point should match evaluate(0.5)
    const mid = q.evaluate(0.5);
    try std.testing.expectApproxEqAbs(halves[0].p2.x, mid.x, 1e-6);
    try std.testing.expectApproxEqAbs(halves[0].p2.y, mid.y, 1e-6);
    // Evaluating the second half at t=1 should give the original endpoint
    const end = halves[1].evaluate(1.0);
    try std.testing.expectApproxEqAbs(end.x, 1.0, 1e-6);
    try std.testing.expectApproxEqAbs(end.y, 0.0, 1e-6);
}

test "QuadBezier bounding box includes extrema" {
    // Arch: control point above endpoints
    const q = QuadBezier{
        .p0 = Vec2.new(0, 0),
        .p1 = Vec2.new(0.5, 2),
        .p2 = Vec2.new(1, 0),
    };
    const bb = q.boundingBox();
    // Y extremum is at t=0.5: y = 0.25*0 + 0.5*2 + 0.25*0 = 1.0
    try std.testing.expectApproxEqAbs(bb.max.y, 1.0, 1e-5);
    try std.testing.expectApproxEqAbs(bb.min.y, 0.0, 1e-5);
}

test "ConicBezier evaluate endpoints" {
    const c = ConicBezier{
        .p0 = Vec2.new(1, 0),
        .p1 = Vec2.new(1, 1),
        .p2 = Vec2.new(0, 1),
        .w1 = std.math.sqrt1_2,
    };
    const start = c.evaluate(0.0);
    const end = c.evaluate(1.0);
    try std.testing.expectApproxEqAbs(start.x, 1.0, 1e-6);
    try std.testing.expectApproxEqAbs(start.y, 0.0, 1e-6);
    try std.testing.expectApproxEqAbs(end.x, 0.0, 1e-6);
    try std.testing.expectApproxEqAbs(end.y, 1.0, 1e-6);
}

test "CurveSegment split preserves conic midpoint" {
    const segment = CurveSegment.fromConic(.{
        .p0 = Vec2.new(1, 0),
        .p1 = Vec2.new(1, 1),
        .p2 = Vec2.new(0, 1),
        .w1 = std.math.sqrt1_2,
    });
    const halves = segment.split(0.5);
    const mid = segment.evaluate(0.5);
    try std.testing.expectApproxEqAbs(halves[0].endPoint().x, mid.x, 1e-5);
    try std.testing.expectApproxEqAbs(halves[0].endPoint().y, mid.y, 1e-5);
}
