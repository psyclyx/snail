const std = @import("std");

const bezier = @import("math/bezier.zig");
const paint_mod = @import("paint.zig");
const path_stroke = @import("path_stroke.zig");
const target_mod = @import("target.zig");
const vec = @import("math/vec.zig");

const BBox = bezier.BBox;
const CurveSegment = bezier.CurveSegment;
const FillStyle = paint_mod.FillStyle;
const Paint = paint_mod.Paint;
const Rect = target_mod.Rect;
const StrokeJoin = paint_mod.StrokeJoin;
const StrokeStyle = paint_mod.StrokeStyle;
const Transform2D = vec.Transform2D;
const Vec2 = vec.Vec2;

// Recursion-depth caps for path subdivision. These are quality / cost
// budgets, not caller-facing limits: hitting the cap yields a slightly
// lower-fidelity tessellation rather than an error or truncation. Bumping
// them trades work for accuracy.
pub const kPathArcSplitMaxDepth: u8 = 8;
const kPathStrokeOffsetTolerance: f32 = 0.005;
pub const kPathStrokeOffsetMaxDepth: u8 = 10;

fn makePathLineCurve(p0: Vec2, p1: Vec2) bezier.QuadBezier {
    return .{
        .p0 = p0,
        .p1 = Vec2.lerp(p0, p1, 0.5),
        .p2 = p1,
    };
}

fn makePathLineSegment(p0: Vec2, p1: Vec2) CurveSegment {
    return CurveSegment.fromLine(p0, p1);
}

// Snap near-axis trig results to exact 0/±1. Without this, rounded-rect
// corner arcs (whose endpoints lie at angles that are multiples of π/2)
// land an ULP off the adjacent line endpoints, leaving a visible seam in
// the stroke at the line→arc transition.
fn snapTrig(value: f32) f32 {
    if (@abs(value) < 1e-6) return 0.0;
    if (@abs(value - 1.0) < 1e-6) return 1.0;
    if (@abs(value + 1.0) < 1e-6) return -1.0;
    return value;
}

fn cosSnap(angle: f32) f32 {
    return snapTrig(@cos(angle));
}

fn sinSnap(angle: f32) f32 {
    return snapTrig(@sin(angle));
}

fn makePathArcCurve(center: Vec2, radii: Vec2, start_angle: f32, end_angle: f32) bezier.QuadBezier {
    const cs = cosSnap(start_angle);
    const ss = sinSnap(start_angle);
    const ce = cosSnap(end_angle);
    const se = sinSnap(end_angle);
    const p0 = center.add(Vec2.new(cs * radii.x, ss * radii.y));
    const p2 = center.add(Vec2.new(ce * radii.x, se * radii.y));
    const t0 = Vec2.new(-ss * radii.x, cs * radii.y);
    const t1 = Vec2.new(-se * radii.x, ce * radii.y);
    const control = lineIntersection(p0, t0, p2, t1) orelse Vec2.lerp(p0, p2, 0.5);
    return .{
        .p0 = p0,
        .p1 = control,
        .p2 = p2,
    };
}

fn makePathArcConic(center: Vec2, radii: Vec2, start_angle: f32, end_angle: f32) CurveSegment {
    const cs = cosSnap(start_angle);
    const ss = sinSnap(start_angle);
    const ce = cosSnap(end_angle);
    const se = sinSnap(end_angle);
    const p0 = center.add(Vec2.new(cs * radii.x, ss * radii.y));
    const p2 = center.add(Vec2.new(ce * radii.x, se * radii.y));
    const t0 = Vec2.new(-ss * radii.x, cs * radii.y);
    const t1 = Vec2.new(-se * radii.x, ce * radii.y);
    const control = lineIntersection(p0, t0, p2, t1) orelse Vec2.lerp(p0, p2, 0.5);
    return CurveSegment.fromConic(.{
        .p0 = p0,
        .p1 = control,
        .p2 = p2,
        .w1 = @cos((end_angle - start_angle) * 0.5),
    });
}

pub fn appendAdaptiveArcCurve(
    path: *Path,
    center: Vec2,
    radii: Vec2,
    start_angle: f32,
    end_angle: f32,
    depth: u8,
) !void {
    const span = end_angle - start_angle;
    if (depth == 0 or @abs(span) <= std.math.pi * 0.125 + 1e-6) {
        path.band_curve_count += 1;
        try path.appendSegment(CurveSegment.fromQuad(makePathArcCurve(center, radii, start_angle, end_angle)));
        return;
    }
    const mid_angle = (start_angle + end_angle) * 0.5;
    try appendAdaptiveArcCurve(path, center, radii, start_angle, mid_angle, depth - 1);
    try appendAdaptiveArcCurve(path, center, radii, mid_angle, end_angle, depth - 1);
}

fn appendAdaptiveArcConic(
    path: *Path,
    center: Vec2,
    radii: Vec2,
    start_angle: f32,
    end_angle: f32,
) !void {
    const span = end_angle - start_angle;
    if (@abs(span) <= 1e-6) return;
    if (@abs(span) > std.math.pi * 0.5 + 1e-6) {
        const mid_angle = (start_angle + end_angle) * 0.5;
        try appendAdaptiveArcConic(path, center, radii, start_angle, mid_angle);
        try appendAdaptiveArcConic(path, center, radii, mid_angle, end_angle);
        return;
    }
    path.band_curve_count += 1;
    try path.appendSegment(makePathArcConic(center, radii, start_angle, end_angle));
}

fn pointsApproxEqual(a: Vec2, b: Vec2) bool {
    return @abs(a.x - b.x) <= 1e-4 and @abs(a.y - b.y) <= 1e-4;
}

pub fn cross2(a: Vec2, b: Vec2) f32 {
    return a.x * b.y - a.y * b.x;
}

pub fn perpLeft(v: Vec2) Vec2 {
    return .{ .x = -v.y, .y = v.x };
}

pub fn signedAngleBetween(a: Vec2, b: Vec2) f32 {
    return std.math.atan2(cross2(a, b), Vec2.dot(a, b));
}

pub fn lineIntersection(p0: Vec2, d0: Vec2, p1: Vec2, d1: Vec2) ?Vec2 {
    const denom = cross2(d0, d1);
    if (@abs(denom) <= 1e-6) return null;
    const rel = Vec2.sub(p1, p0);
    const t = cross2(rel, d1) / denom;
    return Vec2.add(p0, Vec2.scale(d0, t));
}

pub fn appendLineIfNeeded(path: *Path, point: Vec2) !void {
    if (!pointsApproxEqual(path.requireContour().?.current_point, point)) {
        try path.lineTo(point);
    }
}

pub fn reverseCurveSegment(curve: CurveSegment) CurveSegment {
    return switch (curve.kind) {
        .quadratic => .{
            .kind = .quadratic,
            .p0 = curve.p2,
            .p1 = curve.p1,
            .p2 = curve.p0,
        },
        .line => .{
            .kind = .line,
            .p0 = curve.p2,
            .p1 = curve.p1,
            .p2 = curve.p0,
        },
        .conic => .{
            .kind = .conic,
            .p0 = curve.p2,
            .p1 = curve.p1,
            .p2 = curve.p0,
            .weights = .{ curve.weights[2], curve.weights[1], curve.weights[0] },
        },
        .cubic => .{
            .kind = .cubic,
            .p0 = curve.p3,
            .p1 = curve.p2,
            .p2 = curve.p1,
            .p3 = curve.p0,
        },
    };
}

pub fn curveUnitTangent(curve: CurveSegment, t: f32) Vec2 {
    return switch (curve.kind) {
        inline else => |k| curveUnitTangentKind(k, curve, t),
    };
}

/// Comptime-specialised tangent. Used on the stroke-offset hot path
/// where the recursive descent stays on one curve kind throughout —
/// the runtime switch in `derivative`/`evaluate` was the dominant
/// inner-loop cost.
inline fn curveUnitTangentKind(comptime kind: bezier.CurveKind, curve: CurveSegment, t: f32) Vec2 {
    const deriv = curve.derivativeKind(kind, t);
    if (Vec2.length(deriv) > 1e-5) return Vec2.normalize(deriv);

    const fallback_deltas = [_]f32{ 1e-4, 1e-3, 1e-2, 5e-2 };
    for (fallback_deltas) |delta| {
        const t0 = std.math.clamp(t - delta, 0.0, 1.0);
        const t1 = std.math.clamp(t + delta, 0.0, 1.0);
        if (@abs(t1 - t0) <= 1e-6) continue;
        const diff = Vec2.sub(curve.evaluateKind(kind, t1), curve.evaluateKind(kind, t0));
        if (Vec2.length(diff) > 1e-5) return Vec2.normalize(diff);
    }

    const chord = Vec2.sub(curve.endPoint(), curve.p0);
    if (Vec2.length(chord) > 1e-5) return Vec2.normalize(chord);
    return .{ .x = 1.0, .y = 0.0 };
}

inline fn offsetPointAtKind(comptime kind: bezier.CurveKind, curve: CurveSegment, t: f32, tangent: Vec2, offset: f32) Vec2 {
    const normal = perpLeft(tangent);
    return Vec2.add(curve.evaluateKind(kind, t), Vec2.scale(normal, offset));
}

inline fn offsetCurvePointKind(comptime kind: bezier.CurveKind, curve: CurveSegment, t: f32, offset: f32) Vec2 {
    return offsetPointAtKind(kind, curve, t, curveUnitTangentKind(kind, curve, t), offset);
}

pub fn offsetCurvePoint(curve: CurveSegment, t: f32, offset: f32) Vec2 {
    return switch (curve.kind) {
        inline else => |k| offsetCurvePointKind(k, curve, t, offset),
    };
}

/// Build a quadratic that approximates the offset of `curve` between
/// the three sample points already computed at t=0, 0.5, 1.0. Callers
/// that already have the unit tangents thread them in via
/// `appendOffsetCurveApprox` to avoid recomputing on the hot path.
fn fitOffsetQuadFromPoints(p0: Vec2, pm: Vec2, p2: Vec2) CurveSegment {
    const control = Vec2.new(
        pm.x * 2.0 - (p0.x + p2.x) * 0.5,
        pm.y * 2.0 - (p0.y + p2.y) * 0.5,
    );
    return CurveSegment.fromQuad(.{ .p0 = p0, .p1 = control, .p2 = p2 });
}

fn fitOffsetCurveQuad(curve: CurveSegment, offset: f32) CurveSegment {
    const p0 = offsetCurvePoint(curve, 0.0, offset);
    const pm = offsetCurvePoint(curve, 0.5, offset);
    const p2 = offsetCurvePoint(curve, 1.0, offset);
    return fitOffsetQuadFromPoints(p0, pm, p2);
}

/// Recursive offset-quad approximation, specialised on the curve kind
/// at comptime. The runtime switches inside `curve.evaluate`,
/// `curve.derivative`, `curve.flatness`, `curve.split` resolve to a
/// single branch each, which the compiler then inlines into the
/// recursive body. Removes the dominant inner-loop cost (~50% of
/// vector-prep time was switch+dispatch on `CurveSegment.kind`).
///
/// The tangents at t=0 and t=1 are threaded from the parent so each
/// recursive level avoids recomputing them.
fn appendOffsetCurveApproxKind(
    comptime kind: bezier.CurveKind,
    path: *Path,
    curve: CurveSegment,
    offset: f32,
    depth: u8,
    tangent0: Vec2,
    tangent1: Vec2,
) !void {
    if (curve.flatnessKind(kind) <= 1e-6) {
        const contour = path.requireContour() orelse return error.PathMissingMoveTo;
        const target = offsetPointAtKind(kind, curve, 1.0, tangent1, offset);
        path.band_curve_count += 1;
        try path.appendSegmentKind(.line, makePathLineSegment(contour.current_point, target));
        return;
    }

    const tangent_mid = curveUnitTangentKind(kind, curve, 0.5);
    const p0 = offsetPointAtKind(kind, curve, 0.0, tangent0, offset);
    const pm = offsetPointAtKind(kind, curve, 0.5, tangent_mid, offset);
    const p2 = offsetPointAtKind(kind, curve, 1.0, tangent1, offset);
    const fitted_quad = fitOffsetQuadFromPoints(p0, pm, p2);

    var accept = depth == 0;
    if (!accept) {
        const approx = fitted_quad.asQuad();
        var max_error: f32 = 0.0;
        inline for ([_]f32{ 0.25, 0.75 }) |t| {
            const expected = offsetCurvePointKind(kind, curve, t, offset);
            const actual = approx.evaluate(t);
            max_error = @max(max_error, Vec2.length(Vec2.sub(expected, actual)));
        }
        accept = max_error <= kPathStrokeOffsetTolerance;
    }

    if (accept) {
        // The fitted quad's p0 was computed from `curve`'s t=0 tangent
        // independently of any previous offset segment. For consecutive
        // offset segments — whether across an input-curve join, across
        // the join inserted by `appendStrokeJoinForSide`, or across a
        // recursive midpoint split — that endpoint can drift by up to
        // ~1 ULP. Force the fitted quad to start where the path
        // currently is so the contour-continuity contract holds bit-
        // exactly through f16 quantization.
        var fitted = fitted_quad;
        const contour = path.requireContour() orelse return error.PathMissingMoveTo;
        fitted.p0 = contour.current_point;
        path.band_curve_count += 1;
        try path.appendSegmentKind(.quadratic, fitted);
        return;
    }

    const halves = curve.splitKind(kind, 0.5);
    try appendOffsetCurveApproxKind(kind, path, halves[0], offset, depth - 1, tangent0, tangent_mid);
    try appendOffsetCurveApproxKind(kind, path, halves[1], offset, depth - 1, tangent_mid, tangent1);
}

pub fn appendOffsetCurveApprox(
    path: *Path,
    curve: CurveSegment,
    offset: f32,
    depth: u8,
) !void {
    const t0 = curveUnitTangent(curve, 0.0);
    const t1 = curveUnitTangent(curve, 1.0);
    switch (curve.kind) {
        inline else => |k| try appendOffsetCurveApproxKind(k, path, curve, offset, depth, t0, t1),
    }
}

pub const Path = struct {
    allocator: std.mem.Allocator,
    curves: std.ArrayList(CurveSegment) = .empty,
    contours: std.ArrayList(Contour) = .empty,
    bbox: ?BBox = null,
    band_curve_count: usize = 0,

    const Contour = struct {
        curve_start: usize,
        curve_end: usize,
        start_point: Vec2,
        current_point: Vec2,
        closed: bool,
    };

    pub fn init(allocator: std.mem.Allocator) Path {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Path) void {
        self.curves.deinit(self.allocator);
        self.contours.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn reset(self: *Path) void {
        self.curves.clearRetainingCapacity();
        self.contours.clearRetainingCapacity();
        self.bbox = null;
        self.band_curve_count = 0;
    }

    pub fn bounds(self: *const Path) ?BBox {
        return self.bbox;
    }

    pub fn isEmpty(self: *const Path) bool {
        return self.curves.items.len == 0;
    }

    pub fn moveTo(self: *Path, point: Vec2) !void {
        if (self.contours.items.len > 0) {
            var contour = &self.contours.items[self.contours.items.len - 1];
            if (contour.curve_end == contour.curve_start and !contour.closed) {
                contour.start_point = point;
                contour.current_point = point;
                self.expandPointBBox(point);
                return;
            }
        }
        try self.contours.append(self.allocator, .{
            .curve_start = self.curves.items.len,
            .curve_end = self.curves.items.len,
            .start_point = point,
            .current_point = point,
            .closed = false,
        });
        self.expandPointBBox(point);
    }

    pub fn lineTo(self: *Path, point: Vec2) !void {
        const contour = self.requireContour() orelse return error.PathMissingMoveTo;
        self.band_curve_count += 1;
        try self.appendSegment(makePathLineSegment(contour.current_point, point));
    }

    pub fn quadTo(self: *Path, control: Vec2, point: Vec2) !void {
        const contour = self.requireContour() orelse return error.PathMissingMoveTo;
        self.band_curve_count += 1;
        try self.appendSegment(CurveSegment.fromQuad(.{
            .p0 = contour.current_point,
            .p1 = control,
            .p2 = point,
        }));
    }

    pub fn cubicTo(self: *Path, control1: Vec2, control2: Vec2, point: Vec2) !void {
        const contour = self.requireContour() orelse return error.PathMissingMoveTo;
        self.band_curve_count += 1;
        try self.appendSegment(CurveSegment.fromCubic(.{
            .p0 = contour.current_point,
            .p1 = control1,
            .p2 = control2,
            .p3 = point,
        }));
    }

    pub fn close(self: *Path) !void {
        if (self.requireContour()) |initial_contour| {
            var contour = initial_contour;
            if (contour.closed) return;
            if (contour.curve_end > contour.curve_start and !pointsApproxEqual(contour.current_point, contour.start_point)) {
                self.band_curve_count += 1;
                try self.appendSegment(makePathLineSegment(contour.current_point, contour.start_point));
                contour = self.requireContour().?;
            }
            contour.closed = true;
            contour.current_point = contour.start_point;
        }
    }

    pub fn addRect(self: *Path, rect: Rect) !void {
        const origin = Vec2.new(rect.x, rect.y);
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;
        try self.moveTo(origin);
        try self.lineTo(origin.add(Vec2.new(size.x, 0.0)));
        try self.lineTo(origin.add(size));
        try self.lineTo(origin.add(Vec2.new(0.0, size.y)));
        try self.close();
    }

    pub fn addRectReversed(self: *Path, rect: Rect) !void {
        const origin = Vec2.new(rect.x, rect.y);
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;
        try self.moveTo(origin);
        try self.lineTo(origin.add(Vec2.new(0.0, size.y)));
        try self.lineTo(origin.add(size));
        try self.lineTo(origin.add(Vec2.new(size.x, 0.0)));
        try self.close();
    }

    pub fn addRoundedRect(self: *Path, rect: Rect, corner_radius: f32) !void {
        const origin = Vec2.new(rect.x, rect.y);
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;

        const max_radius = @min(size.x, size.y) * 0.5;
        const radius = std.math.clamp(corner_radius, 0.0, max_radius);
        if (radius <= 1.0 / 65536.0) return self.addRect(rect);

        const arc = Vec2.new(radius, radius);
        const top_left = origin.add(Vec2.new(radius, radius));
        const top_right = origin.add(Vec2.new(size.x - radius, radius));
        const bottom_right = origin.add(size).sub(Vec2.new(radius, radius));
        const bottom_left = origin.add(Vec2.new(radius, size.y - radius));

        try self.moveTo(origin.add(Vec2.new(radius, 0.0)));
        try self.lineTo(origin.add(Vec2.new(size.x - radius, 0.0)));
        try appendAdaptiveArcConic(self, top_right, arc, -std.math.pi / 2.0, 0.0);
        try self.lineTo(origin.add(Vec2.new(size.x, size.y - radius)));
        try appendAdaptiveArcConic(self, bottom_right, arc, 0.0, std.math.pi / 2.0);
        try self.lineTo(origin.add(Vec2.new(radius, size.y)));
        try appendAdaptiveArcConic(self, bottom_left, arc, std.math.pi / 2.0, std.math.pi);
        try self.lineTo(origin.add(Vec2.new(0.0, radius)));
        try appendAdaptiveArcConic(self, top_left, arc, std.math.pi, std.math.pi * 1.5);
        try self.close();
    }

    pub fn addRoundedRectReversed(self: *Path, rect: Rect, corner_radius: f32) !void {
        const origin = Vec2.new(rect.x, rect.y);
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;

        const max_radius = @min(size.x, size.y) * 0.5;
        const radius = std.math.clamp(corner_radius, 0.0, max_radius);
        if (radius <= 1.0 / 65536.0) return self.addRectReversed(rect);

        const arc = Vec2.new(radius, radius);
        const top_left = origin.add(Vec2.new(radius, radius));
        const top_right = origin.add(Vec2.new(size.x - radius, radius));
        const bottom_right = origin.add(size).sub(Vec2.new(radius, radius));
        const bottom_left = origin.add(Vec2.new(radius, size.y - radius));

        try self.moveTo(origin.add(Vec2.new(0.0, radius)));
        try self.lineTo(origin.add(Vec2.new(0.0, size.y - radius)));
        try appendAdaptiveArcConic(self, bottom_left, arc, std.math.pi, std.math.pi / 2.0);
        try self.lineTo(origin.add(Vec2.new(size.x - radius, size.y)));
        try appendAdaptiveArcConic(self, bottom_right, arc, std.math.pi / 2.0, 0.0);
        try self.lineTo(origin.add(Vec2.new(size.x, radius)));
        try appendAdaptiveArcConic(self, top_right, arc, 0.0, -std.math.pi / 2.0);
        try self.lineTo(origin.add(Vec2.new(radius, 0.0)));
        try appendAdaptiveArcConic(self, top_left, arc, -std.math.pi / 2.0, -std.math.pi);
        try self.close();
    }

    pub fn addEllipse(self: *Path, rect: Rect) !void {
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;
        const center = Vec2.new(rect.x + size.x * 0.5, rect.y + size.y * 0.5);
        const radii = size.scale(0.5);
        try self.moveTo(center.add(Vec2.new(0.0, -radii.y)));
        try appendAdaptiveArcConic(self, center, radii, -std.math.pi / 2.0, 0.0);
        try appendAdaptiveArcConic(self, center, radii, 0.0, std.math.pi / 2.0);
        try appendAdaptiveArcConic(self, center, radii, std.math.pi / 2.0, std.math.pi);
        try appendAdaptiveArcConic(self, center, radii, std.math.pi, std.math.pi * 1.5);
        try self.close();
    }

    pub fn addEllipseReversed(self: *Path, rect: Rect) !void {
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;
        const center = Vec2.new(rect.x + size.x * 0.5, rect.y + size.y * 0.5);
        const radii = size.scale(0.5);
        try self.moveTo(center.add(Vec2.new(0.0, -radii.y)));
        try appendAdaptiveArcConic(self, center, radii, -std.math.pi / 2.0, -std.math.pi);
        try appendAdaptiveArcConic(self, center, radii, -std.math.pi, -std.math.pi * 1.5);
        try appendAdaptiveArcConic(self, center, radii, -std.math.pi * 1.5, -std.math.pi * 2.0);
        try appendAdaptiveArcConic(self, center, radii, -std.math.pi * 2.0, -std.math.pi * 2.5);
        try self.close();
    }

    inline fn requireContour(self: *Path) ?*Contour {
        if (self.contours.items.len == 0) return null;
        return &self.contours.items[self.contours.items.len - 1];
    }

    pub inline fn appendSegment(self: *Path, curve: CurveSegment) !void {
        switch (curve.kind) {
            inline else => |k| try self.appendSegmentKind(k, curve),
        }
    }

    /// Comptime-kind-specialised append. Skips the runtime switches inside
    /// `boundingBox` and `endPoint` when the caller already knows the
    /// curve's kind at the call site (e.g. the recursive offset-quad
    /// boundary builder).
    inline fn appendSegmentKind(self: *Path, comptime kind: bezier.CurveKind, curve: CurveSegment) !void {
        // Append to `curves` doesn't move `contours`, so the contour
        // pointer survives the append — no need to reacquire.
        const contour = self.requireContour() orelse return error.PathMissingMoveTo;
        try self.curves.append(self.allocator, curve);
        contour.curve_end = self.curves.items.len;
        contour.current_point = switch (kind) {
            .cubic => curve.p3,
            .quadratic, .conic, .line => curve.p2,
        };
        self.expandCurveBBoxKind(kind, curve);
    }

    fn expandPointBBox(self: *Path, point: Vec2) void {
        if (self.bbox) |bbox| {
            self.bbox = .{
                .min = Vec2.new(@min(bbox.min.x, point.x), @min(bbox.min.y, point.y)),
                .max = Vec2.new(@max(bbox.max.x, point.x), @max(bbox.max.y, point.y)),
            };
        } else {
            self.bbox = .{ .min = point, .max = point };
        }
    }

    fn expandCurveBBox(self: *Path, curve: CurveSegment) void {
        switch (curve.kind) {
            inline else => |k| self.expandCurveBBoxKind(k, curve),
        }
    }

    inline fn expandCurveBBoxKind(self: *Path, comptime kind: bezier.CurveKind, curve: CurveSegment) void {
        const cb = curve.boundingBoxKind(kind);
        if (self.bbox) |bbox| {
            self.bbox = bbox.merge(cb);
        } else {
            self.bbox = cb;
        }
    }

    fn unclosedContourCount(self: *const Path) usize {
        var count: usize = 0;
        for (self.contours.items) |contour| {
            if (!contour.closed and contour.curve_end > contour.curve_start and !pointsApproxEqual(contour.current_point, contour.start_point)) {
                count += 1;
            }
        }
        return count;
    }

    pub fn cloneFilledCurves(self: *const Path, allocator: std.mem.Allocator) ![]CurveSegment {
        const close_count = self.unclosedContourCount();
        const out = try allocator.alloc(CurveSegment, self.curves.items.len + close_count);
        @memcpy(out[0..self.curves.items.len], self.curves.items);
        var write = self.curves.items.len;
        for (self.contours.items) |contour| {
            if (!contour.closed and contour.curve_end > contour.curve_start and !pointsApproxEqual(contour.current_point, contour.start_point)) {
                out[write] = makePathLineSegment(contour.current_point, contour.start_point);
                write += 1;
            }
        }
        return out;
    }

    pub fn filledBandCurveCount(self: *const Path) usize {
        return self.band_curve_count + self.unclosedContourCount();
    }

    pub fn cloneStrokedCurves(
        self: *const Path,
        allocator: std.mem.Allocator,
        stroke: StrokeStyle,
    ) !?struct { curves: []CurveSegment, bbox: BBox, logical_curve_count: usize } {
        if (stroke.width <= 1e-4 or self.contours.items.len == 0) return null;

        var outline = Path.init(allocator);
        defer outline.deinit();

        for (self.contours.items) |contour| {
            if (contour.closed) {
                try path_stroke.buildClosedStrokeContours(&outline, self.curves.items[contour.curve_start..contour.curve_end], stroke);
            } else {
                try path_stroke.buildOpenStrokeContour(&outline, self.curves.items[contour.curve_start..contour.curve_end], stroke);
            }
        }

        if (outline.isEmpty()) return null;
        const bbox = outline.bounds() orelse return error.EmptyPath;
        // Take ownership of the outline's curve buffer instead of allocating
        // a final-sized slice and memcpying. Both the outline and the caller
        // hold the same `allocator`, so lifetimes match — `outline.deinit`
        // afterwards is a no-op on the now-empty curves list.
        const curves = try outline.curves.toOwnedSlice(allocator);
        return .{
            .curves = curves,
            .bbox = bbox,
            .logical_curve_count = self.filledBandCurveCount() * 2,
        };
    }

    /// Pack this path's filled outline as `GlyphCurves`. Returns an
    /// empty value for paths with no curves or unbounded extent.
    ///
    /// `allocator` owns the returned `GlyphCurves`. `scratch` holds the
    /// intermediate curve buffers (cloned segments, split-at-extrema,
    /// quantized, band scratch). For batched callers, pass an arena as
    /// `scratch` and reset it between calls; for one-shot callers, pass
    /// the same allocator twice — both have the same lifetime semantics.
    pub fn toCurves(
        self: *const Path,
        allocator: std.mem.Allocator,
        scratch: std.mem.Allocator,
    ) !@import("atlas/curves.zig").GlyphCurves {
        return @import("paths.zig").pathToCurves(allocator, scratch, self);
    }

    /// Pack this path's stroked outline as `GlyphCurves`. Returns an
    /// empty value if the stroke is degenerate (zero width, no
    /// contours). See `toCurves` for the `(allocator, scratch)`
    /// allocator convention.
    pub fn strokeToCurves(
        self: *const Path,
        allocator: std.mem.Allocator,
        scratch: std.mem.Allocator,
        stroke: StrokeStyle,
    ) !@import("atlas/curves.zig").GlyphCurves {
        return @import("paths.zig").strokeToCurves(allocator, scratch, self, stroke);
    }
};
