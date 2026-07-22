//! Mutable vector-path construction and precision-safe preparation.
//!
//! Public geometry inputs must be finite. Segment-producing operations require
//! an active contour begun by `moveTo` and report `error.PathMissingMoveTo`
//! otherwise. Invalid points, rectangles, arc parameters, offsets, tolerances,
//! and rational conics report `error.InvalidGeometry`; conic weights must be
//! finite and positive so their homogeneous denominator cannot cross zero.
//! Operations whose curve/subdivision counts cannot be represented or would
//! exceed the bounded adaptive-arc budget report `error.ShapeTooComplex`.

const std = @import("std");

const bezier = @import("math/bezier.zig");
const paint_mod = @import("paint.zig");
const path_stroke = @import("path_stroke.zig");
const math_mod = @import("math.zig");
const vec = @import("math/vec.zig");

const BBox = bezier.BBox;
const CurveSegment = bezier.CurveSegment;
const Rect = math_mod.Rect;
const StrokeStyle = paint_mod.StrokeStyle;
const Vec2 = vec.Vec2;
const Transform2D = vec.Transform2D;

const StrokedCurves = struct {
    curves: []CurveSegment,
    bbox: BBox,
    logical_curve_count: usize,
};

/// Prepared fills use the full signed f16 range on each non-degenerate bbox
/// axis. The original aspect ratio is restored by the instance transform.
const PREPARED_PATH_RADIUS: f32 = 1.0;

// Recursion-depth caps for path subdivision. These are quality / cost
// budgets, not caller-facing limits: hitting the cap yields a slightly
// lower-fidelity tessellation rather than an error or truncation. Bumping
// them trades work for accuracy.
pub const kPathArcSplitMaxDepth: u8 = 8;
const kPathStrokeOffsetTolerance: f32 = 0.005;
// Prepared paths spend the full signed f16 range on each axis. Keep offset-fit
// error below roughly one quarter of a half-float ULP at |coord|=1; looser
// source-space tolerances become visible as quadratic facets under zoom.
const kPreparedStrokeOffsetTolerance: f32 = 1.0 / 8192.0;
pub const kPathStrokeOffsetMaxDepth: u8 = 10;

fn makePathLineSegment(p0: Vec2, p1: Vec2) CurveSegment {
    return CurveSegment.fromLine(p0, p1);
}

fn finiteVec(point: Vec2) bool {
    return std.math.isFinite(point.x) and std.math.isFinite(point.y);
}

fn finiteCurve(curve: CurveSegment) bool {
    if (!finiteVec(curve.p0) or !finiteVec(curve.p1) or !finiteVec(curve.p2)) return false;
    if (curve.kind == .cubic and !finiteVec(curve.p3)) return false;
    if (curve.kind == .conic) {
        // Positive rational weights keep the homogeneous denominator away
        // from zero over t in [0, 1]. Non-positive weights can introduce a
        // pole even though every input scalar is finite.
        for (curve.weights) |weight| if (!std.math.isFinite(weight) or weight <= 0) return false;
    }
    return true;
}

fn finiteRect(rect: Rect) bool {
    if (!std.math.isFinite(rect.x) or !std.math.isFinite(rect.y) or
        !std.math.isFinite(rect.w) or !std.math.isFinite(rect.h)) return false;
    const width = @max(rect.w, 0.0);
    const height = @max(rect.h, 0.0);
    return std.math.isFinite(rect.x + width) and std.math.isFinite(rect.y + height);
}

const max_adaptive_arc_segments: usize = 4096;

fn arcSubdivisionFits(span: f32, max_piece_span: f32, depth: ?u8) bool {
    if (!std.math.isFinite(span)) return false;
    var piece_span = @abs(span);
    var pieces: usize = 1;
    var remaining: usize = if (depth) |value| value else std.math.maxInt(usize);
    while (piece_span > max_piece_span + 1e-6 and remaining > 0) {
        if (pieces >= max_adaptive_arc_segments) return false;
        pieces *= 2;
        piece_span *= 0.5;
        remaining -= 1;
    }
    return true;
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

/// Append a quadratic approximation of an elliptical arc to an existing
/// contour. `depth` bounds refinement quality; requests that would exceed the
/// global 4096-segment work budget fail with `ShapeTooComplex` before appending.
/// Non-finite inputs return `InvalidGeometry` before appending.
pub fn appendAdaptiveArcCurve(
    path: *Path,
    center: Vec2,
    radii: Vec2,
    start_angle: f32,
    end_angle: f32,
    depth: u8,
) !void {
    if (!finiteVec(center) or !finiteVec(radii) or !std.math.isFinite(start_angle) or !std.math.isFinite(end_angle)) {
        return error.InvalidGeometry;
    }
    const span = end_angle - start_angle;
    if (!arcSubdivisionFits(span, std.math.pi * 0.125, depth)) return error.ShapeTooComplex;
    if (depth == 0 or @abs(span) <= std.math.pi * 0.125 + 1e-6) {
        try path.appendSegment(CurveSegment.fromQuad(makePathArcCurve(center, radii, start_angle, end_angle)));
        return;
    }
    const mid_angle = start_angle + span * 0.5;
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
        const mid_angle = start_angle + span * 0.5;
        try appendAdaptiveArcConic(path, center, radii, start_angle, mid_angle);
        try appendAdaptiveArcConic(path, center, radii, mid_angle, end_angle);
        return;
    }
    try path.appendSegment(makePathArcConic(center, radii, start_angle, end_angle));
}

/// Append a cubic approximation of an elliptical arc to an existing contour.
/// The span is split into pieces no wider than pi/2, up to the global
/// 4096-segment work budget. Excessive spans return `ShapeTooComplex`, and
/// non-finite inputs return `InvalidGeometry`, before appending.
pub fn appendAdaptiveArcCubic(
    path: *Path,
    center: Vec2,
    radii: Vec2,
    start_angle: f32,
    end_angle: f32,
) !void {
    if (!finiteVec(center) or !finiteVec(radii) or !std.math.isFinite(start_angle) or !std.math.isFinite(end_angle)) {
        return error.InvalidGeometry;
    }
    const span = end_angle - start_angle;
    if (!arcSubdivisionFits(span, std.math.pi * 0.5, null)) return error.ShapeTooComplex;
    if (@abs(span) <= 1e-6) return;
    if (@abs(span) > std.math.pi * 0.5 + 1e-6) {
        const mid_angle = start_angle + span * 0.5;
        try appendAdaptiveArcCubic(path, center, radii, start_angle, mid_angle);
        try appendAdaptiveArcCubic(path, center, radii, mid_angle, end_angle);
        return;
    }

    const cs = cosSnap(start_angle);
    const ss = sinSnap(start_angle);
    const ce = cosSnap(end_angle);
    const se = sinSnap(end_angle);
    const p0 = Vec2.add(center, .{ .x = cs * radii.x, .y = ss * radii.y });
    const p3 = Vec2.add(center, .{ .x = ce * radii.x, .y = se * radii.y });
    const handle = (4.0 / 3.0) * @tan(span * 0.25);
    const tangent0 = Vec2.new(-ss * radii.x, cs * radii.y);
    const tangent1 = Vec2.new(-se * radii.x, ce * radii.y);
    try path.appendSegment(CurveSegment.fromCubic(.{
        .p0 = p0,
        .p1 = Vec2.add(p0, Vec2.scale(tangent0, handle)),
        .p2 = Vec2.sub(p3, Vec2.scale(tangent1, handle)),
        .p3 = p3,
    }));
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

/// Tangent-constrained cubic fit of an offset span. Handles are bounded by the
/// local chord instead of using the exact offset-derivative magnitude: inner
/// offsets can pass through a cusp where that magnitude reverses and produces
/// a remote Bézier loop. Adaptive subdivision supplies positional accuracy;
/// the shared endpoint tangent directions keep adjacent spans G1-continuous.
fn fitOffsetCubic(p0: Vec2, p3: Vec2, tangent0: Vec2, tangent1: Vec2) CurveSegment {
    const handle = Vec2.length(Vec2.sub(p3, p0)) / 3.0;
    return CurveSegment.fromCubic(.{
        .p0 = p0,
        .p1 = Vec2.add(p0, Vec2.scale(tangent0, handle)),
        .p2 = Vec2.sub(p3, Vec2.scale(tangent1, handle)),
        .p3 = p3,
    });
}

/// Recursive offset-cubic approximation, specialised on the curve kind
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
    tolerance: f32,
    tangent0: Vec2,
    tangent1: Vec2,
) !void {
    if (curve.flatnessKind(kind) <= 1e-6) {
        const contour = path.requireContour() orelse return error.PathMissingMoveTo;
        const target = offsetPointAtKind(kind, curve, 1.0, tangent1, offset);
        try path.appendSegmentKind(.line, makePathLineSegment(contour.current_point, target));
        return;
    }

    const tangent_mid = curveUnitTangentKind(kind, curve, 0.5);
    const p0 = offsetPointAtKind(kind, curve, 0.0, tangent0, offset);
    const p3 = offsetPointAtKind(kind, curve, 1.0, tangent1, offset);
    const fitted_cubic = fitOffsetCubic(p0, p3, tangent0, tangent1);

    var accept = depth == 0;
    if (!accept) {
        var max_error: f32 = 0.0;
        inline for ([_]f32{ 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875 }) |t| {
            const expected = offsetCurvePointKind(kind, curve, t, offset);
            const actual = fitted_cubic.evaluateKind(.cubic, t);
            max_error = @max(max_error, Vec2.length(Vec2.sub(expected, actual)));
        }
        accept = max_error <= tolerance;
    }

    if (accept) {
        // The fitted cubic's p0 was computed from `curve`'s t=0 tangent
        // independently of any previous offset segment. For consecutive
        // offset segments — whether across an input-curve join, across
        // the join inserted by `appendStrokeJoinForSide`, or across a
        // recursive midpoint split — that endpoint can drift by up to
        // ~1 ULP. Force the fitted quad to start where the path
        // currently is so the contour-continuity contract holds bit-
        // exactly through f16 quantization.
        var fitted = fitted_cubic;
        const contour = path.requireContour() orelse return error.PathMissingMoveTo;
        const start_delta = Vec2.sub(contour.current_point, fitted.p0);
        fitted.p0 = contour.current_point;
        fitted.p1 = Vec2.add(fitted.p1, start_delta);
        try path.appendSegmentKind(.cubic, fitted);
        return;
    }

    const halves = curve.splitKind(kind, 0.5);
    try appendOffsetCurveApproxKind(kind, path, halves[0], offset, depth - 1, tolerance, tangent0, tangent_mid);
    try appendOffsetCurveApproxKind(kind, path, halves[1], offset, depth - 1, tolerance, tangent_mid, tangent1);
}

/// Append an adaptive cubic approximation of one offset curve to an existing
/// contour. Geometry, offset, and tolerance must be finite, tolerance must be
/// non-negative, and rational-conic weights must be positive; violations
/// return `InvalidGeometry`.
pub fn appendOffsetCurveApprox(
    path: *Path,
    curve: CurveSegment,
    offset: f32,
    depth: u8,
    tolerance: f32,
) !void {
    if (!finiteCurve(curve) or !std.math.isFinite(offset) or !std.math.isFinite(tolerance) or tolerance < 0) {
        return error.InvalidGeometry;
    }
    const t0 = curveUnitTangent(curve, 0.0);
    const t1 = curveUnitTangent(curve, 1.0);
    switch (curve.kind) {
        inline else => |k| try appendOffsetCurveApproxKind(k, path, curve, offset, depth, tolerance, t0, t1),
    }
}

/// Allocator-backed mutable path. A successful `moveTo` starts a contour, and
/// line/quad/cubic/segment appends require one. Individual segment appends
/// update curve accounting only after allocation succeeds; fixed-size compound
/// commands reserve their complete contour/curve capacity before mutation.
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

    fn ensureCompoundCapacity(self: *Path, curve_count: usize) !void {
        if (curve_count > std.math.maxInt(usize) - self.band_curve_count)
            return error.ShapeTooComplex;
        try self.curves.ensureUnusedCapacity(self.allocator, curve_count);
        const reuses_empty_contour = self.contours.items.len > 0 and blk: {
            const last = self.contours.items[self.contours.items.len - 1];
            break :blk !last.closed and last.curve_start == last.curve_end;
        };
        if (!reuses_empty_contour) try self.contours.ensureUnusedCapacity(self.allocator, 1);
    }

    fn clone(self: *const Path, allocator: std.mem.Allocator) !Path {
        var copy = Path.init(allocator);
        errdefer copy.deinit();
        try copy.curves.appendSlice(allocator, self.curves.items);
        try copy.contours.appendSlice(allocator, self.contours.items);
        copy.bbox = self.bbox;
        copy.band_curve_count = self.band_curve_count;
        return copy;
    }

    /// Normalize non-empty source-space geometry into a small design space
    /// near the origin before it is quantized into the f16 curve format. A
    /// uniform scale preserves authored aspect ratios and keeps native radial
    /// and conic paints exact. Geometry too small to produce a finite f32
    /// placement reports `InvalidGeometry` instead of silently disappearing.
    /// `PreparedPath.design_to_source` carries the inverse placement, and its
    /// paint/stroke helpers keep the whole shape in the same coordinate frame.
    pub fn prepare(self: *const Path, allocator: std.mem.Allocator) !PreparedPath {
        var source = try self.clone(allocator);
        errdefer source.deinit();
        var design = Path.init(allocator);
        errdefer design.deinit();

        if (self.isEmpty()) return .{
            .source = source,
            .design = design,
            .design_to_source = .identity,
            .source_to_design = .identity,
        };
        const bb = self.bounds() orelse return .{
            .source = source,
            .design = design,
            .design_to_source = .identity,
            .source_to_design = .identity,
        };
        // Do the normalization math in f64: two individually-finite f32
        // endpoints can have a difference larger than f32 and must still be
        // normalized instead of falling back to unencodable source values.
        const width = @as(f64, bb.max.x) - @as(f64, bb.min.x);
        const height = @as(f64, bb.max.y) - @as(f64, bb.min.y);
        const extent = @max(width, height);
        if (!std.math.isFinite(extent) or extent <= 0) return error.InvalidGeometry;

        const scale_64 = (2.0 * PREPARED_PATH_RADIUS) / extent;
        const center_x_64 = @as(f64, bb.min.x) + width * 0.5;
        const center_y_64 = @as(f64, bb.min.y) + height * 0.5;
        const inv_scale_64 = 1.0 / scale_64;
        const tx_64 = -center_x_64 * scale_64;
        const ty_64 = -center_y_64 * scale_64;
        const transform_values = [_]f64{
            scale_64,
            center_x_64,
            center_y_64,
            inv_scale_64,
            tx_64,
            ty_64,
        };
        for (transform_values) |value| {
            if (!std.math.isFinite(value) or @abs(value) > std.math.floatMax(f32)) return error.InvalidGeometry;
        }
        const scale: f32 = @floatCast(scale_64);
        const center_x: f32 = @floatCast(center_x_64);
        const center_y: f32 = @floatCast(center_y_64);
        const source_to_design = Transform2D{
            .xx = scale,
            .yy = scale,
            .tx = @floatCast(tx_64),
            .ty = @floatCast(ty_64),
        };
        const design_to_source = Transform2D{
            .xx = @floatCast(inv_scale_64),
            .yy = @floatCast(inv_scale_64),
            .tx = center_x,
            .ty = center_y,
        };

        for (self.contours.items) |contour| {
            try design.moveTo(source_to_design.applyPoint(contour.start_point));
            for (self.curves.items[contour.curve_start..contour.curve_end]) |curve| {
                try design.appendSegment(transformCurve(curve, source_to_design));
            }
            if (contour.closed) try design.close();
        }

        return .{
            .source = source,
            .design = design,
            .design_to_source = design_to_source,
            .source_to_design = source_to_design,
        };
    }

    /// Begin a contour at a finite point. If the current contour contains no
    /// segments and remains open, this replaces its start instead of adding a
    /// second empty contour.
    pub fn moveTo(self: *Path, point: Vec2) !void {
        if (!finiteVec(point)) return error.InvalidGeometry;
        if (self.contours.items.len > 0) {
            var contour = &self.contours.items[self.contours.items.len - 1];
            if (contour.curve_end == contour.curve_start and !contour.closed) {
                contour.start_point = point;
                contour.current_point = point;
                self.recomputeBBox();
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

    /// Append a line to a finite point, or return `PathMissingMoveTo` when no
    /// contour has been started.
    pub fn lineTo(self: *Path, point: Vec2) !void {
        const contour = self.requireContour() orelse return error.PathMissingMoveTo;
        try self.appendSegment(makePathLineSegment(contour.current_point, point));
    }

    /// Append a quadratic with finite control/end points, or return
    /// `PathMissingMoveTo` when no contour has been started.
    pub fn quadTo(self: *Path, control: Vec2, point: Vec2) !void {
        const contour = self.requireContour() orelse return error.PathMissingMoveTo;
        try self.appendSegment(CurveSegment.fromQuad(.{
            .p0 = contour.current_point,
            .p1 = control,
            .p2 = point,
        }));
    }

    /// Append a cubic with finite control/end points, or return
    /// `PathMissingMoveTo` when no contour has been started.
    pub fn cubicTo(self: *Path, control1: Vec2, control2: Vec2, point: Vec2) !void {
        const contour = self.requireContour() orelse return error.PathMissingMoveTo;
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
                try self.appendSegment(makePathLineSegment(contour.current_point, contour.start_point));
                contour = self.requireContour().?;
            }
            contour.closed = true;
            contour.current_point = contour.start_point;
        }
    }

    /// Add a rectangle. Negative dimensions clamp to zero; an empty
    /// result is a no-op. Non-finite inputs or overflowing corners return
    /// `InvalidGeometry` before mutation.
    pub fn addRect(self: *Path, rect: Rect) !void {
        if (!finiteRect(rect)) return error.InvalidGeometry;
        const origin = Vec2.new(rect.x, rect.y);
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;
        try self.ensureCompoundCapacity(4);
        try self.moveTo(origin);
        try self.lineTo(origin.add(Vec2.new(size.x, 0.0)));
        try self.lineTo(origin.add(size));
        try self.lineTo(origin.add(Vec2.new(0.0, size.y)));
        try self.close();
    }

    /// Add the rectangle with reversed winding. Validation and empty-rectangle
    /// behavior match `addRect`.
    pub fn addRectReversed(self: *Path, rect: Rect) !void {
        if (!finiteRect(rect)) return error.InvalidGeometry;
        const origin = Vec2.new(rect.x, rect.y);
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;
        try self.ensureCompoundCapacity(4);
        try self.moveTo(origin);
        try self.lineTo(origin.add(Vec2.new(0.0, size.y)));
        try self.lineTo(origin.add(size));
        try self.lineTo(origin.add(Vec2.new(size.x, 0.0)));
        try self.close();
    }

    /// Add a rounded rectangle. The finite radius is clamped to
    /// `[0, min(width, height) / 2]`; rectangle validation matches `addRect`.
    pub fn addRoundedRect(self: *Path, rect: Rect, corner_radius: f32) !void {
        if (!finiteRect(rect) or !std.math.isFinite(corner_radius)) return error.InvalidGeometry;
        const origin = Vec2.new(rect.x, rect.y);
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;

        const max_radius = @min(size.x, size.y) * 0.5;
        const radius = std.math.clamp(corner_radius, 0.0, max_radius);
        if (radius <= 1.0 / 65536.0) return self.addRect(rect);
        try self.ensureCompoundCapacity(8);

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

    /// Add the rounded rectangle with reversed winding. Validation and radius
    /// clamping match `addRoundedRect`.
    pub fn addRoundedRectReversed(self: *Path, rect: Rect, corner_radius: f32) !void {
        if (!finiteRect(rect) or !std.math.isFinite(corner_radius)) return error.InvalidGeometry;
        const origin = Vec2.new(rect.x, rect.y);
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;

        const max_radius = @min(size.x, size.y) * 0.5;
        const radius = std.math.clamp(corner_radius, 0.0, max_radius);
        if (radius <= 1.0 / 65536.0) return self.addRectReversed(rect);
        try self.ensureCompoundCapacity(8);

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

    /// Add an ellipse bounded by `rect`. Rectangle validation and
    /// empty-rectangle behavior match `addRect`.
    pub fn addEllipse(self: *Path, rect: Rect) !void {
        if (!finiteRect(rect)) return error.InvalidGeometry;
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;
        const center = Vec2.new(rect.x + size.x * 0.5, rect.y + size.y * 0.5);
        const radii = size.scale(0.5);
        try self.ensureCompoundCapacity(4);
        try self.moveTo(center.add(Vec2.new(0.0, -radii.y)));
        try appendAdaptiveArcConic(self, center, radii, -std.math.pi / 2.0, 0.0);
        try appendAdaptiveArcConic(self, center, radii, 0.0, std.math.pi / 2.0);
        try appendAdaptiveArcConic(self, center, radii, std.math.pi / 2.0, std.math.pi);
        try appendAdaptiveArcConic(self, center, radii, std.math.pi, std.math.pi * 1.5);
        try self.close();
    }

    /// Add the ellipse with reversed winding. Validation and empty-rectangle
    /// behavior match `addEllipse`.
    pub fn addEllipseReversed(self: *Path, rect: Rect) !void {
        if (!finiteRect(rect)) return error.InvalidGeometry;
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 0.0 or size.y <= 0.0) return;
        const center = Vec2.new(rect.x + size.x * 0.5, rect.y + size.y * 0.5);
        const radii = size.scale(0.5);
        try self.ensureCompoundCapacity(4);
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

    /// Append a finite low-level segment to the active contour. Rational conic
    /// weights must be finite and positive. Returns `PathMissingMoveTo`,
    /// `InvalidGeometry`, or `ShapeTooComplex` without changing curve
    /// accounting when validation/allocation fails.
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
        if (!finiteCurve(curve)) return error.InvalidGeometry;
        if (self.band_curve_count == std.math.maxInt(usize)) return error.ShapeTooComplex;
        // Append to `curves` doesn't move `contours`, so the contour
        // pointer survives the append — no need to reacquire.
        const contour = self.requireContour() orelse return error.PathMissingMoveTo;
        try self.curves.append(self.allocator, curve);
        self.band_curve_count += 1;
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

    /// Rebuild bounds after replacing a move-only contour point. Segment
    /// bounds already contain the start/end points of non-empty contours;
    /// empty contours contribute their authored move point explicitly.
    fn recomputeBBox(self: *Path) void {
        self.bbox = null;
        for (self.curves.items) |curve| {
            const curve_bbox = curve.boundingBox();
            self.bbox = if (self.bbox) |bbox| bbox.merge(curve_bbox) else curve_bbox;
        }
        for (self.contours.items) |contour| {
            if (contour.curve_start == contour.curve_end) self.expandPointBBox(contour.start_point);
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

    /// Clone the fill geometry, adding a closing line for every non-empty open
    /// contour. The caller owns the returned slice. Returns `ShapeTooComplex`
    /// if the resulting count cannot be represented.
    pub fn cloneFilledCurves(self: *const Path, allocator: std.mem.Allocator) ![]CurveSegment {
        const close_count = self.unclosedContourCount();
        const total_count = std.math.add(usize, self.curves.items.len, close_count) catch
            return error.ShapeTooComplex;
        const out = try allocator.alloc(CurveSegment, total_count);
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

    /// Curve count used for filled-path band sizing, including implicit closing
    /// lines. Returns `ShapeTooComplex` on count overflow.
    pub fn filledBandCurveCount(self: *const Path) error{ShapeTooComplex}!usize {
        return std.math.add(usize, self.band_curve_count, self.unclosedContourCount()) catch
            error.ShapeTooComplex;
    }

    /// Outline the path's stroke into caller-owned curves. Returns null when
    /// the stroke/path is effectively empty and `ShapeTooComplex` when logical
    /// curve accounting overflows; geometry/allocation errors propagate.
    pub fn cloneStrokedCurves(
        self: *const Path,
        allocator: std.mem.Allocator,
        stroke: StrokeStyle,
    ) !?StrokedCurves {
        return self.cloneStrokedCurvesWithTolerance(allocator, stroke, kPathStrokeOffsetTolerance);
    }

    fn cloneStrokedCurvesWithTolerance(
        self: *const Path,
        allocator: std.mem.Allocator,
        stroke: StrokeStyle,
        tolerance: f32,
    ) !?StrokedCurves {
        try stroke.validate();
        if (!std.math.isFinite(tolerance) or tolerance <= 0) return error.InvalidGeometry;
        if (stroke.width <= 1e-4 or self.contours.items.len == 0) return null;

        var outline = Path.init(allocator);
        defer outline.deinit();

        for (self.contours.items) |contour| {
            if (contour.closed) {
                try path_stroke.buildClosedStrokeContours(&outline, self.curves.items[contour.curve_start..contour.curve_end], stroke, tolerance);
            } else {
                try path_stroke.buildOpenStrokeContour(&outline, self.curves.items[contour.curve_start..contour.curve_end], stroke, tolerance);
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
            .logical_curve_count = std.math.mul(usize, try self.filledBandCurveCount(), 2) catch
                return error.ShapeTooComplex,
        };
    }
};

fn transformCurve(curve: CurveSegment, transform: Transform2D) CurveSegment {
    var out = curve;
    out.p0 = transform.applyPoint(curve.p0);
    out.p1 = transform.applyPoint(curve.p1);
    out.p2 = transform.applyPoint(curve.p2);
    if (curve.kind == .cubic) out.p3 = transform.applyPoint(curve.p3);
    return out;
}

/// A path expressed in Snail's precision-safe design space. Each numerically
/// maximum bbox axis spans `[-1,1]`; the other axis retains the source aspect
/// ratio. `design_to_source` restores authored coordinates when the shape is
/// drawn. Empty paths use identity transforms and an empty prepared fill.
/// Strokes are outlined in source space before normalization.
pub const PreparedPath = struct {
    source: Path,
    design: Path,
    design_to_source: Transform2D,
    source_to_design: Transform2D,

    pub fn deinit(self: *PreparedPath) void {
        self.source.deinit();
        self.design.deinit();
        self.* = undefined;
    }

    pub fn fillCurves(
        self: *const PreparedPath,
        allocator: std.mem.Allocator,
        scratch: std.mem.Allocator,
    ) !@import("atlas/curves.zig").GlyphCurves {
        return @import("path_pack.zig").pathToCurves(allocator, scratch, &self.design);
    }

    pub fn strokeCurves(
        self: *const PreparedPath,
        allocator: std.mem.Allocator,
        scratch: std.mem.Allocator,
        source_stroke: StrokeStyle,
    ) !@import("atlas/curves.zig").GlyphCurves {
        const paths = @import("path_pack.zig");
        const max_design_scale = @max(@abs(self.source_to_design.xx), @abs(self.source_to_design.yy));
        const source_tolerance = kPreparedStrokeOffsetTolerance / @max(max_design_scale, std.math.floatEps(f32));
        const result = (try self.source.cloneStrokedCurvesWithTolerance(scratch, source_stroke, source_tolerance)) orelse
            return @import("atlas/curves.zig").GlyphCurves.empty(allocator);
        defer scratch.free(result.curves);

        var design_bbox: ?BBox = null;
        for (result.curves) |*curve| {
            curve.* = transformCurve(curve.*, self.source_to_design);
            const curve_bbox = curve.boundingBox();
            design_bbox = if (design_bbox) |bbox| bbox.merge(curve_bbox) else curve_bbox;
        }
        return paths.packCurves(allocator, scratch, result.curves, design_bbox orelse return error.EmptyPath, result.logical_curve_count);
    }

    /// Re-express source-space paint parameters in the prepared design space.
    pub fn paintForDesign(self: *const PreparedPath, source_paint: paint_mod.Paint) paint_mod.PaintMapError!paint_mod.Paint {
        return paint_mod.mapToLocal(source_paint, self.design_to_source);
    }

    /// Compose an existing source/world transform with the placement needed to
    /// restore the prepared design geometry to the path's authored space.
    pub fn placedBy(self: *const PreparedPath, outer: Transform2D) Transform2D {
        return Transform2D.multiply(outer, self.design_to_source);
    }
};

test "path curve accounting changes only after a successful append" {
    var path = Path.init(std.testing.allocator);
    defer {
        path.allocator = std.testing.allocator;
        path.deinit();
    }
    try path.moveTo(.zero);

    var no_memory: [0]u8 = .{};
    var fixed = std.heap.FixedBufferAllocator.init(&no_memory);
    path.allocator = fixed.allocator();
    try std.testing.expectError(error.OutOfMemory, path.lineTo(.{ .x = 1, .y = 1 }));
    try std.testing.expectEqual(@as(usize, 0), path.band_curve_count);
    try std.testing.expectEqual(@as(usize, 0), path.curves.items.len);

    path.allocator = std.testing.allocator;
    try path.lineTo(.{ .x = 1, .y = 1 });
    try std.testing.expectEqual(@as(usize, 1), path.band_curve_count);
    try std.testing.expectEqual(@as(usize, 1), path.curves.items.len);
}

test "compound path commands fail before publishing a prefix" {
    var path = Path.init(std.testing.allocator);
    defer {
        path.allocator = std.testing.allocator;
        path.deinit();
    }

    var no_memory: [0]u8 = .{};
    var fixed = std.heap.FixedBufferAllocator.init(&no_memory);
    path.allocator = fixed.allocator();
    try std.testing.expectError(error.OutOfMemory, path.addRoundedRect(
        .{ .x = 0, .y = 0, .w = 20, .h = 10 },
        2,
    ));
    try std.testing.expectEqual(@as(usize, 0), path.contours.items.len);
    try std.testing.expectEqual(@as(usize, 0), path.curves.items.len);
    try std.testing.expectEqual(@as(usize, 0), path.band_curve_count);
    try std.testing.expectEqual(@as(?BBox, null), path.bbox);
}

test "path rejects non-finite public geometry without mutation" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();

    try std.testing.expectError(error.InvalidGeometry, path.moveTo(.{ .x = std.math.nan(f32), .y = 0 }));
    try std.testing.expectError(error.InvalidGeometry, path.addRect(.{ .x = 0, .y = 0, .w = std.math.inf(f32), .h = 1 }));
    try std.testing.expectError(error.InvalidGeometry, path.addRect(.{ .x = std.math.floatMax(f32), .y = 0, .w = std.math.floatMax(f32), .h = 1 }));
    try std.testing.expectError(error.InvalidGeometry, appendAdaptiveArcCubic(
        &path,
        .zero,
        .{ .x = 1, .y = 1 },
        0,
        std.math.nan(f32),
    ));
    try std.testing.expectEqual(@as(usize, 0), path.contours.items.len);
    try std.testing.expectEqual(@as(usize, 0), path.curves.items.len);
    try std.testing.expectEqual(@as(usize, 0), path.band_curve_count);
}

test "replacing the current move-only contour removes its stale bound" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();

    try path.moveTo(.{ .x = -100, .y = -200 });
    try path.moveTo(.{ .x = 10, .y = 20 });
    try path.lineTo(.{ .x = 12, .y = 24 });

    const bbox = path.bounds().?;
    try std.testing.expectEqual(Vec2.new(10, 20), bbox.min);
    try std.testing.expectEqual(Vec2.new(12, 24), bbox.max);
}

test "adaptive arcs reject explosive subdivision counts before mutation" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();
    try path.moveTo(.zero);

    try std.testing.expectError(error.ShapeTooComplex, appendAdaptiveArcCubic(
        &path,
        .zero,
        .{ .x = 1, .y = 1 },
        0,
        std.math.pi * @as(f32, max_adaptive_arc_segments + 1),
    ));
    try std.testing.expectEqual(@as(usize, 0), path.curves.items.len);
    try std.testing.expectEqual(@as(usize, 0), path.band_curve_count);
}

test "path preparation normalizes the full finite f32 range" {
    const limit = std.math.floatMax(f32);
    var path = Path.init(std.testing.allocator);
    defer path.deinit();
    try path.moveTo(.{ .x = -limit, .y = -limit });
    try path.lineTo(.{ .x = limit, .y = limit });

    var prepared = try path.prepare(std.testing.allocator);
    defer prepared.deinit();
    const bounds = prepared.design.bounds().?;
    try std.testing.expect(finiteVec(bounds.min));
    try std.testing.expect(finiteVec(bounds.max));
    try std.testing.expect(@abs(bounds.min.x) <= PREPARED_PATH_RADIUS);
    try std.testing.expect(@abs(bounds.max.x) <= PREPARED_PATH_RADIUS);
}

test "prepare normalizes arbitrary coordinates and preserves placement" {
    var source = Path.init(std.testing.allocator);
    defer source.deinit();
    try source.addRect(.{ .x = 5000, .y = -3000, .w = 200, .h = 100 });

    var prepared = try source.prepare(std.testing.allocator);
    defer prepared.deinit();

    const design_bounds = prepared.design.bounds().?;
    try std.testing.expectApproxEqAbs(-PREPARED_PATH_RADIUS, design_bounds.min.x, 1e-6);
    try std.testing.expectApproxEqAbs(-PREPARED_PATH_RADIUS * 0.5, design_bounds.min.y, 1e-6);
    try std.testing.expectApproxEqAbs(PREPARED_PATH_RADIUS, design_bounds.max.x, 1e-6);
    try std.testing.expectApproxEqAbs(PREPARED_PATH_RADIUS * 0.5, design_bounds.max.y, 1e-6);

    const restored_min = prepared.design_to_source.applyPoint(design_bounds.min);
    const restored_max = prepared.design_to_source.applyPoint(design_bounds.max);
    try std.testing.expectApproxEqAbs(@as(f32, 5000), restored_min.x, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, -3000), restored_min.y, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, 5200), restored_max.x, 1e-3);
    try std.testing.expectApproxEqAbs(@as(f32, -2900), restored_max.y, 1e-3);

    var stroke_curves = try prepared.strokeCurves(std.testing.allocator, std.testing.allocator, .{
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
        .width = 10,
    });
    defer stroke_curves.deinit();
    try std.testing.expectApproxEqAbs(@as(f32, -1.05), stroke_curves.bbox.min.x, 0.002);
    try std.testing.expectApproxEqAbs(@as(f32, -0.55), stroke_curves.bbox.min.y, 0.002);
    try std.testing.expectApproxEqAbs(@as(f32, 1.05), stroke_curves.bbox.max.x, 0.002);
    try std.testing.expectApproxEqAbs(@as(f32, 0.55), stroke_curves.bbox.max.y, 0.002);
}

test "prepare preserves finite paths smaller than the old cutoff" {
    var source = Path.init(std.testing.allocator);
    defer source.deinit();
    try source.addRect(.{ .x = 1e-5, .y = -2e-5, .w = 1e-7, .h = 5e-8 });

    var prepared = try source.prepare(std.testing.allocator);
    defer prepared.deinit();
    try std.testing.expect(!prepared.design.isEmpty());
    const design_bounds = prepared.design.bounds().?;
    try std.testing.expectApproxEqAbs(@as(f32, 2), design_bounds.width(), 2e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 1), design_bounds.height(), 2e-5);
}

test "prepared radial paint mapping stays exact on a non-square path" {
    var source = Path.init(std.testing.allocator);
    defer source.deinit();
    try source.addRect(.{ .x = 100, .y = 200, .w = 80, .h = 20 });
    var prepared = try source.prepare(std.testing.allocator);
    defer prepared.deinit();

    const mapped = (try prepared.paintForDesign(.{ .radial_gradient = .{
        .center = .{ .x = 140, .y = 210 },
        .radius = 10,
        .inner_color = .{ 0, 0, 0, 1 },
        .outer_color = .{ 1, 1, 1, 1 },
    } })).radial_gradient;
    try std.testing.expectApproxEqAbs(@as(f32, 0), mapped.center.x, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0), mapped.center.y, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, 0.25), mapped.radius, 1e-5);
}

test "cubic stroke outline keeps adaptive span joins tangent-continuous" {
    var source = Path.init(std.testing.allocator);
    defer source.deinit();
    try source.moveTo(.{ .x = 0.08, .y = 0.7 });
    try source.cubicTo(
        .{ .x = 0.3, .y = -0.1 },
        .{ .x = 0.7, .y = 1.1 },
        .{ .x = 0.92, .y = 0.3 },
    );

    const outline = (try source.cloneStrokedCurvesWithTolerance(std.testing.allocator, .{
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
        .width = 0.08,
        .cap = .round,
        .join = .round,
    }, 1.0 / 16384.0)).?;
    defer std.testing.allocator.free(outline.curves);

    // A fit handle must never escape the local swept region. The exact-
    // derivative Hermite experiment produced a detached island far to the
    // left when the inner offset crossed a curvature cusp.
    try std.testing.expect(outline.bbox.min.x >= 0.03);
    try std.testing.expect(outline.bbox.max.x <= 0.97);
    try std.testing.expect(outline.bbox.min.y >= -0.15);
    try std.testing.expect(outline.bbox.max.y <= 1.15);
    const detached_probe = BBox{
        .min = .{ .x = 0.035, .y = 0.27 },
        .max = .{ .x = 0.125, .y = 0.33 },
    };
    for (outline.curves, 0..) |curve, i| {
        if (!curve.boundingBox().intersects(detached_probe)) continue;
        std.debug.print("unexpected stroke curve {d} ({s}) intersects detached-island probe\n", .{ i, @tagName(curve.kind) });
        return error.DetachedStrokeGeometry;
    }

    var cubic_joins: usize = 0;
    for (outline.curves[0 .. outline.curves.len - 1], outline.curves[1..]) |left, right| {
        if (left.kind != .cubic or right.kind != .cubic) continue;
        const left_tangent = Vec2.normalize(left.derivative(1.0));
        const right_tangent = Vec2.normalize(right.derivative(0.0));
        try std.testing.expect(Vec2.dot(left_tangent, right_tangent) > 0.9999);
        try std.testing.expect(@abs(cross2(left_tangent, right_tangent)) < 0.001);
        cubic_joins += 1;
    }
    try std.testing.expect(cubic_joins > 0);
}

test "semicircular stroke cap uses two tangent-continuous cubic arcs" {
    var cap = Path.init(std.testing.allocator);
    defer cap.deinit();
    try cap.moveTo(.{ .x = 1, .y = 0 });
    try appendAdaptiveArcCubic(&cap, .zero, .{ .x = 1, .y = 1 }, 0, std.math.pi);
    try std.testing.expectEqual(@as(usize, 2), cap.curves.items.len);
    try std.testing.expectEqual(bezier.CurveKind.cubic, cap.curves.items[0].kind);
    try std.testing.expectEqual(bezier.CurveKind.cubic, cap.curves.items[1].kind);
    const left_tangent = Vec2.normalize(cap.curves.items[0].derivative(1));
    const right_tangent = Vec2.normalize(cap.curves.items[1].derivative(0));
    try std.testing.expect(Vec2.dot(left_tangent, right_tangent) > 0.9999);
}
