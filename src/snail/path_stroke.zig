//! Stroke-contour machinery for `Path`: offset-curve fitting, joins and
//! caps, and boundary building. Split out of `path.zig` to keep that
//! file focused on curve/arc geometry helpers and the `Path` struct.
//!
//! These functions extend a caller-owned `Path` (the stroke outline) and
//! lean on the plain geometry helpers exported from `path.zig`. The
//! dependency direction is one-way: `path.zig` calls into here (from
//! `Path.cloneStrokedCurves`), and here we import `path.zig`'s types and
//! leaf helpers — never its higher-level stroke entry points.

const std = @import("std");

const bezier = @import("math/bezier.zig");
const paint_mod = @import("paint.zig");
const path_mod = @import("path.zig");
const vec = @import("math/vec.zig");

const CurveSegment = bezier.CurveSegment;
const Path = path_mod.Path;
const StrokeJoin = paint_mod.StrokeJoin;
const StrokeStyle = paint_mod.StrokeStyle;
const Vec2 = vec.Vec2;

fn appendArcSeries(path: *Path, center: Vec2, radius: f32, start_angle: f32, end_angle: f32) !void {
    if (@abs(end_angle - start_angle) <= 1e-6) return;
    try path_mod.appendAdaptiveArcCubic(path, center, Vec2.new(radius, radius), start_angle, end_angle);
}

fn appendRoundJoin(path: *Path, center: Vec2, prev_normal: Vec2, next_normal: Vec2, half_width: f32) !void {
    const start_angle = std.math.atan2(prev_normal.y, prev_normal.x);
    const delta = path_mod.signedAngleBetween(prev_normal, next_normal);
    try appendArcSeries(path, center, half_width, start_angle, start_angle + delta);
}

fn appendRoundCap(path: *Path, center: Vec2, dir: Vec2, half_width: f32, start_cap: bool) !void {
    const normal = path_mod.perpLeft(dir);
    const start_angle = if (start_cap)
        std.math.atan2(-normal.y, -normal.x)
    else
        std.math.atan2(normal.y, normal.x);
    try appendArcSeries(path, center, half_width, start_angle, start_angle - std.math.pi);
}

fn appendStrokeJoinForSide(
    path: *Path,
    center: Vec2,
    prev_dir: Vec2,
    next_dir: Vec2,
    half_width: f32,
    side: f32,
    join: StrokeJoin,
    miter_limit: f32,
) !void {
    const turn = path_mod.cross2(prev_dir, next_dir);
    const normal_prev = Vec2.scale(path_mod.perpLeft(prev_dir), side);
    const normal_next = Vec2.scale(path_mod.perpLeft(next_dir), side);
    const prev_offset = Vec2.add(center, Vec2.scale(normal_prev, half_width));
    const next_offset = Vec2.add(center, Vec2.scale(normal_next, half_width));

    if (@abs(turn) <= 1e-5) {
        try path_mod.appendLineIfNeeded(path, next_offset);
        return;
    }

    const intersection = path_mod.lineIntersection(prev_offset, prev_dir, next_offset, next_dir);
    const is_outer = turn * side > 0.0;
    if (!is_outer) {
        if (intersection) |p| {
            try path_mod.appendLineIfNeeded(path, p);
        }
        try path_mod.appendLineIfNeeded(path, next_offset);
        return;
    }

    switch (join) {
        .bevel => {
            try path_mod.appendLineIfNeeded(path, next_offset);
        },
        .round => {
            try appendRoundJoin(path, center, normal_prev, normal_next, half_width);
        },
        .miter => {
            if (intersection) |p| {
                if (Vec2.length(Vec2.sub(p, center)) <= half_width * @max(miter_limit, 1.0)) {
                    try path_mod.appendLineIfNeeded(path, p);
                    try path_mod.appendLineIfNeeded(path, next_offset);
                    return;
                }
            }
            try path_mod.appendLineIfNeeded(path, next_offset);
        },
    }
}

fn appendOffsetBoundaryCurve(
    boundary: *Path,
    curve: CurveSegment,
    side: f32,
    half_width: f32,
    tolerance: f32,
) !void {
    try path_mod.appendOffsetCurveApprox(boundary, curve, side * half_width, path_mod.kPathStrokeOffsetMaxDepth, tolerance);
}

/// Append the offset-boundary curves for one side of a stroke into
/// `dst`. The caller must have already `moveTo`'d to the boundary's
/// start point (`offsetCurvePoint(curves[0], 0.0, side * stroke.width *
/// 0.5)`), since we extend the existing contour rather than open a new
/// one. Skips the intermediate Path that the owned-return wrapper
/// allocates.
fn buildOffsetBoundaryInto(
    dst: *Path,
    curves: []const CurveSegment,
    closed: bool,
    side: f32,
    stroke: StrokeStyle,
    tolerance: f32,
) !void {
    if ((!closed and curves.len == 0) or stroke.width <= 1e-4) return;

    const half_width = stroke.width * 0.5;

    const first_curve = curves[0];
    try appendOffsetBoundaryCurve(dst, first_curve, side, half_width, tolerance);

    if (curves.len > 1) {
        for (1..curves.len) |i| {
            const prev_curve = curves[i - 1];
            const curve = curves[i];
            try appendStrokeJoinForSide(
                dst,
                prev_curve.endPoint(),
                path_mod.curveUnitTangent(prev_curve, 1.0),
                path_mod.curveUnitTangent(curve, 0.0),
                half_width,
                side,
                stroke.join,
                stroke.miter_limit,
            );
            try appendOffsetBoundaryCurve(dst, curve, side, half_width, tolerance);
        }
    }

    if (closed) {
        try appendStrokeJoinForSide(
            dst,
            curves[curves.len - 1].endPoint(),
            path_mod.curveUnitTangent(curves[curves.len - 1], 1.0),
            path_mod.curveUnitTangent(curves[0], 0.0),
            half_width,
            side,
            stroke.join,
            stroke.miter_limit,
        );
    }
}

/// Returns an owned Path containing the offset boundary. Used when the
/// caller needs the boundary buffered so it can be appended reversed
/// (eg. the right side of an open/closed stroke).
fn buildOffsetBoundary(
    allocator: std.mem.Allocator,
    curves: []const CurveSegment,
    closed: bool,
    side: f32,
    stroke: StrokeStyle,
    tolerance: f32,
) !?Path {
    if ((!closed and curves.len == 0) or stroke.width <= 1e-4) return null;

    const half_width = stroke.width * 0.5;
    var boundary = Path.init(allocator);
    errdefer boundary.deinit();
    const start_point = path_mod.offsetCurvePoint(curves[0], 0.0, side * half_width);
    try boundary.moveTo(start_point);
    try buildOffsetBoundaryInto(&boundary, curves, closed, side, stroke, tolerance);
    return boundary;
}

fn appendBoundaryCurves(dst: *Path, src: *const Path, reverse: bool) !void {
    if (!reverse) {
        for (src.curves.items) |curve| {
            try dst.appendSegment(curve);
        }
        return;
    }
    var i = src.curves.items.len;
    while (i > 0) {
        i -= 1;
        try dst.appendSegment(path_mod.reverseCurveSegment(src.curves.items[i]));
    }
}

pub fn buildOpenStrokeContour(path: *Path, curves: []const CurveSegment, stroke: StrokeStyle, tolerance: f32) !void {
    if (curves.len == 0 or stroke.width <= 1e-4) return;

    // Right side needs to be appended reversed, so we still buffer it
    // through an intermediate Path. The left side gets written straight
    // into `path` further below.
    var right = (try buildOffsetBoundary(path.allocator, curves, false, -1.0, stroke, tolerance)) orelse return;
    defer right.deinit();

    const half_width = stroke.width * 0.5;
    const start_dir = path_mod.curveUnitTangent(curves[0], 0.0);
    const end_dir = path_mod.curveUnitTangent(curves[curves.len - 1], 1.0);
    const start_center = if (stroke.cap == .square)
        Vec2.sub(curves[0].p0, Vec2.scale(start_dir, half_width))
    else
        curves[0].p0;
    const end_center = if (stroke.cap == .square)
        Vec2.add(curves[curves.len - 1].endPoint(), Vec2.scale(end_dir, half_width))
    else
        curves[curves.len - 1].endPoint();
    const start_left = Vec2.add(start_center, Vec2.scale(path_mod.perpLeft(start_dir), half_width));
    const start_right = Vec2.sub(start_center, Vec2.scale(path_mod.perpLeft(start_dir), half_width));
    const end_left = Vec2.add(end_center, Vec2.scale(path_mod.perpLeft(end_dir), half_width));
    const end_right = Vec2.sub(end_center, Vec2.scale(path_mod.perpLeft(end_dir), half_width));
    const left_start = path_mod.offsetCurvePoint(curves[0], 0.0, 1.0 * half_width);
    const right_start = right.curves.items[0].p0;
    const right_end = right.curves.items[right.curves.items.len - 1].endPoint();

    try path.moveTo(start_right);
    switch (stroke.cap) {
        .round => try appendRoundCap(path, curves[0].p0, start_dir, half_width, true),
        .butt, .square => try path_mod.appendLineIfNeeded(path, start_left),
    }
    try path_mod.appendLineIfNeeded(path, left_start);
    try buildOffsetBoundaryInto(path, curves, false, 1.0, stroke, tolerance);
    try path_mod.appendLineIfNeeded(path, end_left);
    switch (stroke.cap) {
        .round => try appendRoundCap(path, curves[curves.len - 1].endPoint(), end_dir, half_width, false),
        .butt, .square => try path_mod.appendLineIfNeeded(path, end_right),
    }
    try path_mod.appendLineIfNeeded(path, right_end);
    try appendBoundaryCurves(path, &right, true);
    try path_mod.appendLineIfNeeded(path, right_start);
    try path.close();
}

pub fn buildClosedStrokeContours(path: *Path, curves: []const CurveSegment, stroke: StrokeStyle, tolerance: f32) !void {
    if (curves.len == 0 or stroke.width <= 1e-4) return;

    const half_width = stroke.width * 0.5;
    // Left side: written straight into `path`. Saves a per-curve copy
    // through an intermediate Path.
    const left_start = path_mod.offsetCurvePoint(curves[0], 0.0, 1.0 * half_width);
    try path.moveTo(left_start);
    try buildOffsetBoundaryInto(path, curves, true, 1.0, stroke, tolerance);
    try path.close();

    // Right side still needs an intermediate so it can be appended
    // in reverse.
    var right = (try buildOffsetBoundary(path.allocator, curves, true, -1.0, stroke, tolerance)) orelse return;
    defer right.deinit();

    try path.moveTo(right.curves.items[right.curves.items.len - 1].endPoint());
    try appendBoundaryCurves(path, &right, true);
    try path.close();
}
