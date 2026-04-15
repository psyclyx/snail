const std = @import("std");
const vec = @import("vec.zig");
const Vec2 = vec.Vec2;

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
        // Distance from p1 to line p0-p2
        const d = Vec2.sub(self.p2, self.p0);
        const len = Vec2.length(d);
        if (len < 1e-10) return Vec2.length(Vec2.sub(self.p1, self.p0));
        const n = Vec2.new(-d.y, d.x); // perpendicular
        const v = Vec2.sub(self.p1, self.p0);
        return @abs(Vec2.dot(v, n)) / len;
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
