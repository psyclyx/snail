const std = @import("std");

const band_tex = @import("renderer/band_texture.zig");
const bezier = @import("math/bezier.zig");
const curve_tex = @import("renderer/curve_texture.zig");
const draw_mod = @import("draw.zig");
const image_mod = @import("image.zig");
const lowlevel_mod = @import("lowlevel.zig");
const paint_api = @import("paint.zig");
const paint_mod = @import("paint.zig");
const paint_records = @import("paint_records.zig");
const resource_footprint_mod = @import("resources/footprint.zig");
const resource_set_mod = @import("resources/set.zig");
const roots = @import("math/roots.zig");
const scene_mod = @import("scene.zig");
const target_mod = @import("target.zig");
const upload_mod = @import("upload.zig");
const vertex_mod = @import("renderer/vertex.zig");
const vec = @import("math/vec.zig");

const Atlas = lowlevel_mod.Atlas;
const AtlasPage = lowlevel_mod.AtlasPage;
const BBox = bezier.BBox;
const CurveSegment = bezier.CurveSegment;
const DrawList = draw_mod.DrawList;
const DrawOptions = draw_mod.DrawOptions;
const FillStyle = paint_api.FillStyle;
const Image = image_mod.Image;
const Mat4 = vec.Mat4;
const Paint = paint_api.Paint;
const PathDraw = scene_mod.PathDraw;
const PreparedAtlasView = lowlevel_mod.PreparedAtlasView;
const Range = scene_mod.Range;
const Rect = target_mod.Rect;
const ResourceFootprint = upload_mod.ResourceFootprint;
const ResourceSet = resource_set_mod.ResourceSet;
const Scene = scene_mod.Scene;
const StrokeJoin = paint_api.StrokeJoin;
const StrokeStyle = paint_api.StrokeStyle;
const Transform2D = vec.Transform2D;
const Vec2 = vec.Vec2;
const curveAtlasFootprint = resource_footprint_mod.curveAtlasFootprint;
const textureLayerLocal = lowlevel_mod.textureLayerLocal;
const textureLayerWindowBase = lowlevel_mod.textureLayerWindowBase;

pub const PATH_PAINT_INFO_WIDTH: u32 = paint_records.info_width;
pub const PATH_PAINT_TEXELS_PER_RECORD: u32 = paint_records.texels_per_record;
pub const PATH_PAINT_TAG_SOLID: f32 = paint_records.tag_solid;
pub const PATH_PAINT_TAG_LINEAR_GRADIENT: f32 = paint_records.tag_linear_gradient;
pub const PATH_PAINT_TAG_RADIAL_GRADIENT: f32 = paint_records.tag_radial_gradient;
pub const PATH_PAINT_TAG_IMAGE: f32 = paint_records.tag_image;
pub const PATH_PAINT_TAG_COMPOSITE_GROUP: f32 = paint_records.tag_composite_group;

pub const PathPictureDebugView = enum(u8) {
    normal,
    fill_mask,
    stroke_mask,
    layer_tint,
};

pub const PathPictureBoundsOverlayOptions = struct {
    stroke_color: [4]f32 = .{ 1.0, 0.36, 0.24, 0.95 },
    stroke_width: f32 = 1.0,
    origin_color: [4]f32 = .{ 1.0, 0.78, 0.22, 0.95 },
    origin_size: f32 = 6.0,
};

pub const PATH_WORDS_PER_VERTEX = vertex_mod.WORDS_PER_VERTEX;
pub const PATH_VERTICES_PER_SHAPE = vertex_mod.VERTICES_PER_GLYPH;
pub const PATH_WORDS_PER_SHAPE = PATH_WORDS_PER_VERTEX * PATH_VERTICES_PER_SHAPE;

// Recursion-depth caps for path subdivision. These are quality / cost
// budgets, not caller-facing limits: hitting the cap yields a slightly
// lower-fidelity tessellation rather than an error or truncation. Bumping
// them trades work for accuracy.
const kPathArcSplitMaxDepth: u8 = 8;
const kPathStrokeOffsetTolerance: f32 = 0.005;
const kPathStrokeOffsetMaxDepth: u8 = 10;
const kPathCurveApproxTolerance: f32 = 0.005;
const kPathCurveApproxMaxDepth: u8 = 10;
const kPathLargePrimitiveTileExtent: f32 = 512.0;

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

fn appendAdaptiveArcCurve(
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

fn cross2(a: Vec2, b: Vec2) f32 {
    return a.x * b.y - a.y * b.x;
}

fn perpLeft(v: Vec2) Vec2 {
    return .{ .x = -v.y, .y = v.x };
}

fn signedAngleBetween(a: Vec2, b: Vec2) f32 {
    return std.math.atan2(cross2(a, b), Vec2.dot(a, b));
}

fn lineIntersection(p0: Vec2, d0: Vec2, p1: Vec2, d1: Vec2) ?Vec2 {
    const denom = cross2(d0, d1);
    if (@abs(denom) <= 1e-6) return null;
    const rel = Vec2.sub(p1, p0);
    const t = cross2(rel, d1) / denom;
    return Vec2.add(p0, Vec2.scale(d0, t));
}

fn appendLineIfNeeded(path: *Path, point: Vec2) !void {
    if (!pointsApproxEqual(path.requireContour().?.current_point, point)) {
        try path.lineTo(point);
    }
}

fn translateBBox(bbox: BBox, delta: Vec2) BBox {
    return .{
        .min = Vec2.add(bbox.min, delta),
        .max = Vec2.add(bbox.max, delta),
    };
}

fn bboxCenter(bbox: BBox) Vec2 {
    return .{
        .x = (bbox.min.x + bbox.max.x) * 0.5,
        .y = (bbox.min.y + bbox.max.y) * 0.5,
    };
}

fn translatePaint(paint: Paint, delta: Vec2) Paint {
    return paint_mod.mapToLocal(paint, Transform2D.translate(-delta.x, -delta.y)).?;
}

fn fillStyleForStroke(style: StrokeStyle) FillStyle {
    return .{
        .paint = style.paint,
    };
}

fn reverseCurveSegment(curve: CurveSegment) CurveSegment {
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

fn curveUnitTangent(curve: CurveSegment, t: f32) Vec2 {
    const deriv = curve.derivative(t);
    if (Vec2.length(deriv) > 1e-5) return Vec2.normalize(deriv);

    const fallback_deltas = [_]f32{ 1e-4, 1e-3, 1e-2, 5e-2 };
    for (fallback_deltas) |delta| {
        const t0 = std.math.clamp(t - delta, 0.0, 1.0);
        const t1 = std.math.clamp(t + delta, 0.0, 1.0);
        if (@abs(t1 - t0) <= 1e-6) continue;
        const diff = Vec2.sub(curve.evaluate(t1), curve.evaluate(t0));
        if (Vec2.length(diff) > 1e-5) return Vec2.normalize(diff);
    }

    const chord = Vec2.sub(curve.endPoint(), curve.p0);
    if (Vec2.length(chord) > 1e-5) return Vec2.normalize(chord);
    return .{ .x = 1.0, .y = 0.0 };
}

fn offsetCurvePoint(curve: CurveSegment, t: f32, offset: f32) Vec2 {
    const tangent = curveUnitTangent(curve, t);
    const normal = perpLeft(tangent);
    return Vec2.add(curve.evaluate(t), Vec2.scale(normal, offset));
}

fn fitOffsetCurveQuad(curve: CurveSegment, offset: f32) CurveSegment {
    const p0 = offsetCurvePoint(curve, 0.0, offset);
    const pm = offsetCurvePoint(curve, 0.5, offset);
    const p2 = offsetCurvePoint(curve, 1.0, offset);
    const control = Vec2.new(
        pm.x * 2.0 - (p0.x + p2.x) * 0.5,
        pm.y * 2.0 - (p0.y + p2.y) * 0.5,
    );
    return CurveSegment.fromQuad(.{
        .p0 = p0,
        .p1 = control,
        .p2 = p2,
    });
}

fn fitCurveQuadratic(curve: CurveSegment) CurveSegment {
    if (curve.kind == .quadratic) return curve;
    const p0 = curve.evaluate(0.0);
    const pm = curve.evaluate(0.5);
    const p2 = curve.evaluate(1.0);
    const control = Vec2.new(
        pm.x * 2.0 - (p0.x + p2.x) * 0.5,
        pm.y * 2.0 - (p0.y + p2.y) * 0.5,
    );
    return CurveSegment.fromQuad(.{
        .p0 = p0,
        .p1 = control,
        .p2 = p2,
    });
}

fn curveQuadraticApproxError(curve: CurveSegment) f32 {
    if (curve.kind == .quadratic) return 0.0;
    const approx = fitCurveQuadratic(curve).asQuad();
    var max_error: f32 = 0.0;
    inline for ([_]f32{ 0.25, 0.75 }) |t| {
        const expected = curve.evaluate(t);
        const actual = approx.evaluate(t);
        max_error = @max(max_error, Vec2.length(Vec2.sub(expected, actual)));
    }
    return max_error;
}

fn appendAdaptiveQuadraticApprox(
    path: *Path,
    curve: CurveSegment,
    depth: u8,
) !void {
    if (curve.kind == .quadratic) {
        try path.appendSegment(curve);
        return;
    }

    if (depth == 0 or curveQuadraticApproxError(curve) <= kPathCurveApproxTolerance) {
        try path.appendSegment(fitCurveQuadratic(curve));
        return;
    }

    const halves = curve.split(0.5);
    try appendAdaptiveQuadraticApprox(path, halves[0], depth - 1);
    try appendAdaptiveQuadraticApprox(path, halves[1], depth - 1);
}

fn offsetCurveApproxError(curve: CurveSegment, offset: f32) f32 {
    const approx = fitOffsetCurveQuad(curve, offset).asQuad();
    var max_error: f32 = 0.0;
    inline for ([_]f32{ 0.25, 0.75 }) |t| {
        const expected = offsetCurvePoint(curve, t, offset);
        const actual = approx.evaluate(t);
        max_error = @max(max_error, Vec2.length(Vec2.sub(expected, actual)));
    }
    return max_error;
}

fn appendOffsetCurveApprox(
    path: *Path,
    curve: CurveSegment,
    offset: f32,
    depth: u8,
) !void {
    if (curve.flatness() <= 1e-6) {
        try path.lineTo(offsetCurvePoint(curve, 1.0, offset));
        return;
    }

    if (depth == 0 or offsetCurveApproxError(curve, offset) <= kPathStrokeOffsetTolerance) {
        path.band_curve_count += 1;
        try path.appendSegment(fitOffsetCurveQuad(curve, offset));
        return;
    }

    const halves = curve.split(0.5);
    try appendOffsetCurveApprox(path, halves[0], offset, depth - 1);
    try appendOffsetCurveApprox(path, halves[1], offset, depth - 1);
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
        try appendAdaptiveQuadraticApprox(self, CurveSegment.fromCubic(.{
            .p0 = contour.current_point,
            .p1 = control1,
            .p2 = control2,
            .p3 = point,
        }), kPathCurveApproxMaxDepth);
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

    fn requireContour(self: *Path) ?*Contour {
        if (self.contours.items.len == 0) return null;
        return &self.contours.items[self.contours.items.len - 1];
    }

    fn appendSegment(self: *Path, curve: CurveSegment) !void {
        var contour = self.requireContour() orelse return error.PathMissingMoveTo;
        try self.curves.append(self.allocator, curve);
        contour = self.requireContour().?;
        contour.curve_end = self.curves.items.len;
        contour.current_point = curve.endPoint();
        self.expandCurveBBox(curve);
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
        const cb = curve.boundingBox();
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

    fn cloneFilledCurves(self: *const Path, allocator: std.mem.Allocator) ![]CurveSegment {
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

    fn filledBandCurveCount(self: *const Path) usize {
        return self.band_curve_count + self.unclosedContourCount();
    }

    fn cloneStrokedCurves(
        self: *const Path,
        allocator: std.mem.Allocator,
        stroke: StrokeStyle,
    ) !?struct { curves: []CurveSegment, bbox: BBox, logical_curve_count: usize } {
        if (stroke.width <= 1e-4 or self.contours.items.len == 0) return null;

        var outline = Path.init(allocator);
        defer outline.deinit();

        for (self.contours.items) |contour| {
            if (contour.closed) {
                try buildClosedStrokeContours(&outline, self.curves.items[contour.curve_start..contour.curve_end], stroke);
            } else {
                try buildOpenStrokeContour(&outline, self.curves.items[contour.curve_start..contour.curve_end], stroke);
            }
        }

        if (outline.isEmpty()) return null;
        const curves = try allocator.alloc(CurveSegment, outline.curves.items.len);
        @memcpy(curves, outline.curves.items);
        return .{
            .curves = curves,
            .bbox = outline.bounds() orelse return error.EmptyPath,
            .logical_curve_count = self.filledBandCurveCount() * 2,
        };
    }
};

fn appendArcSeries(path: *Path, center: Vec2, radius: f32, start_angle: f32, end_angle: f32) !void {
    if (@abs(end_angle - start_angle) <= 1e-6) return;
    try appendAdaptiveArcCurve(path, center, Vec2.new(radius, radius), start_angle, end_angle, kPathArcSplitMaxDepth);
}

fn appendRoundJoin(path: *Path, center: Vec2, prev_normal: Vec2, next_normal: Vec2, half_width: f32) !void {
    const start_angle = std.math.atan2(prev_normal.y, prev_normal.x);
    const delta = signedAngleBetween(prev_normal, next_normal);
    try appendArcSeries(path, center, half_width, start_angle, start_angle + delta);
}

fn appendRoundCap(path: *Path, center: Vec2, dir: Vec2, half_width: f32, start_cap: bool) !void {
    const normal = perpLeft(dir);
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
    const turn = cross2(prev_dir, next_dir);
    const normal_prev = Vec2.scale(perpLeft(prev_dir), side);
    const normal_next = Vec2.scale(perpLeft(next_dir), side);
    const prev_offset = Vec2.add(center, Vec2.scale(normal_prev, half_width));
    const next_offset = Vec2.add(center, Vec2.scale(normal_next, half_width));

    if (@abs(turn) <= 1e-5) {
        try appendLineIfNeeded(path, next_offset);
        return;
    }

    const intersection = lineIntersection(prev_offset, prev_dir, next_offset, next_dir);
    const is_outer = turn * side > 0.0;
    if (!is_outer) {
        if (intersection) |p| {
            try appendLineIfNeeded(path, p);
        }
        try appendLineIfNeeded(path, next_offset);
        return;
    }

    switch (join) {
        .bevel => {
            try appendLineIfNeeded(path, next_offset);
        },
        .round => {
            try appendRoundJoin(path, center, normal_prev, normal_next, half_width);
        },
        .miter => {
            if (intersection) |p| {
                if (Vec2.length(Vec2.sub(p, center)) <= half_width * @max(miter_limit, 1.0)) {
                    try appendLineIfNeeded(path, p);
                    try appendLineIfNeeded(path, next_offset);
                    return;
                }
            }
            try appendLineIfNeeded(path, next_offset);
        },
    }
}

fn appendOffsetBoundaryCurve(
    boundary: *Path,
    curve: CurveSegment,
    side: f32,
    half_width: f32,
) !void {
    try appendOffsetCurveApprox(boundary, curve, side * half_width, kPathStrokeOffsetMaxDepth);
}

fn buildOffsetBoundary(
    allocator: std.mem.Allocator,
    curves: []const CurveSegment,
    closed: bool,
    side: f32,
    stroke: StrokeStyle,
) !?Path {
    if ((!closed and curves.len == 0) or stroke.width <= 1e-4) return null;

    const half_width = stroke.width * 0.5;
    var boundary = Path.init(allocator);
    errdefer boundary.deinit();

    const first_curve = curves[0];
    const start_point = offsetCurvePoint(first_curve, 0.0, side * half_width);
    try boundary.moveTo(start_point);
    try appendOffsetBoundaryCurve(&boundary, first_curve, side, half_width);

    if (curves.len > 1) {
        for (1..curves.len) |i| {
            const prev_curve = curves[i - 1];
            const curve = curves[i];
            try appendStrokeJoinForSide(
                &boundary,
                prev_curve.endPoint(),
                curveUnitTangent(prev_curve, 1.0),
                curveUnitTangent(curve, 0.0),
                half_width,
                side,
                stroke.join,
                stroke.miter_limit,
            );
            try appendOffsetBoundaryCurve(&boundary, curve, side, half_width);
        }
    }

    if (closed) {
        try appendStrokeJoinForSide(
            &boundary,
            curves[curves.len - 1].endPoint(),
            curveUnitTangent(curves[curves.len - 1], 1.0),
            curveUnitTangent(curves[0], 0.0),
            half_width,
            side,
            stroke.join,
            stroke.miter_limit,
        );
    }

    return boundary;
}

fn appendBoundaryCurves(dst: *Path, src: *const Path, reverse: bool) !void {
    if (!reverse) {
        for (src.curves.items) |curve| {
            dst.band_curve_count += 1;
            try dst.appendSegment(curve);
        }
        return;
    }
    var i = src.curves.items.len;
    while (i > 0) {
        i -= 1;
        dst.band_curve_count += 1;
        try dst.appendSegment(reverseCurveSegment(src.curves.items[i]));
    }
}

fn buildOpenStrokeContour(path: *Path, curves: []const CurveSegment, stroke: StrokeStyle) !void {
    if (curves.len == 0 or stroke.width <= 1e-4) return;

    var left = (try buildOffsetBoundary(path.allocator, curves, false, 1.0, stroke)) orelse return;
    defer left.deinit();
    var right = (try buildOffsetBoundary(path.allocator, curves, false, -1.0, stroke)) orelse return;
    defer right.deinit();

    const half_width = stroke.width * 0.5;
    const start_dir = curveUnitTangent(curves[0], 0.0);
    const end_dir = curveUnitTangent(curves[curves.len - 1], 1.0);
    const start_center = if (stroke.cap == .square)
        Vec2.sub(curves[0].p0, Vec2.scale(start_dir, half_width))
    else
        curves[0].p0;
    const end_center = if (stroke.cap == .square)
        Vec2.add(curves[curves.len - 1].endPoint(), Vec2.scale(end_dir, half_width))
    else
        curves[curves.len - 1].endPoint();
    const start_left = Vec2.add(start_center, Vec2.scale(perpLeft(start_dir), half_width));
    const start_right = Vec2.sub(start_center, Vec2.scale(perpLeft(start_dir), half_width));
    const end_left = Vec2.add(end_center, Vec2.scale(perpLeft(end_dir), half_width));
    const end_right = Vec2.sub(end_center, Vec2.scale(perpLeft(end_dir), half_width));
    const left_start = left.curves.items[0].p0;
    const right_start = right.curves.items[0].p0;
    const right_end = right.curves.items[right.curves.items.len - 1].endPoint();

    try path.moveTo(start_right);
    switch (stroke.cap) {
        .round => try appendRoundCap(path, curves[0].p0, start_dir, half_width, true),
        .butt, .square => try appendLineIfNeeded(path, start_left),
    }
    try appendLineIfNeeded(path, left_start);
    try appendBoundaryCurves(path, &left, false);
    try appendLineIfNeeded(path, end_left);
    switch (stroke.cap) {
        .round => try appendRoundCap(path, curves[curves.len - 1].endPoint(), end_dir, half_width, false),
        .butt, .square => try appendLineIfNeeded(path, end_right),
    }
    try appendLineIfNeeded(path, right_end);
    try appendBoundaryCurves(path, &right, true);
    try appendLineIfNeeded(path, right_start);
    try path.close();
}

fn buildClosedStrokeContours(path: *Path, curves: []const CurveSegment, stroke: StrokeStyle) !void {
    if (curves.len == 0 or stroke.width <= 1e-4) return;

    var left = (try buildOffsetBoundary(path.allocator, curves, true, 1.0, stroke)) orelse return;
    defer left.deinit();
    var right = (try buildOffsetBoundary(path.allocator, curves, true, -1.0, stroke)) orelse return;
    defer right.deinit();

    try path.moveTo(left.curves.items[0].p0);
    try appendBoundaryCurves(path, &left, false);
    try path.close();

    try path.moveTo(right.curves.items[right.curves.items.len - 1].endPoint());
    try appendBoundaryCurves(path, &right, true);
    try path.close();
}

fn pointOnEllipse(center: Vec2, radii: Vec2, angle: f32) Vec2 {
    return center.add(.{
        .x = @cos(angle) * radii.x,
        .y = @sin(angle) * radii.y,
    });
}

fn buildCircularSectorPath(
    path: *Path,
    center: Vec2,
    outer_radius: f32,
    inner_radius: f32,
    start_angle: f32,
    end_angle: f32,
) !void {
    const outer_radii = Vec2.new(outer_radius, outer_radius);
    const outer_start = pointOnEllipse(center, outer_radii, start_angle);
    try path.moveTo(outer_start);
    try appendAdaptiveArcCurve(path, center, outer_radii, start_angle, end_angle, kPathArcSplitMaxDepth);
    if (inner_radius <= 1.0 / 65536.0) {
        try path.lineTo(center);
    } else {
        const inner_radii = Vec2.new(inner_radius, inner_radius);
        const inner_end = pointOnEllipse(center, inner_radii, end_angle);
        try path.lineTo(inner_end);
        try appendAdaptiveArcCurve(path, center, inner_radii, end_angle, start_angle, kPathArcSplitMaxDepth);
    }
    try path.close();
}

const kPaintInfoWidth: u32 = PATH_PAINT_INFO_WIDTH;
const kPaintTexelsPerRecord: u32 = PATH_PAINT_TEXELS_PER_RECORD;
const kPaintTagSolid: f32 = PATH_PAINT_TAG_SOLID;
const kPaintTagLinearGradient: f32 = PATH_PAINT_TAG_LINEAR_GRADIENT;
const kPaintTagRadialGradient: f32 = PATH_PAINT_TAG_RADIAL_GRADIENT;
const kPaintTagImage: f32 = PATH_PAINT_TAG_IMAGE;
const kPaintTagCompositeGroup: f32 = PATH_PAINT_TAG_COMPOSITE_GROUP;

const PathCompositeMode = enum(u8) {
    source_over = 0,
    fill_stroke_inside = 1,
};

fn pathPaintInfoWidth(texel_count: u32) u32 {
    return paint_records.infoWidth(texel_count);
}

fn pathLayerInfoTexelOffset(texel_width: u32, info_x: u16, info_y: u16) u32 {
    return @as(u32, info_y) * texel_width + @as(u32, info_x);
}

fn readPathLayerInfoTexel(data: []const f32, texel_width: u32, texel_offset: u32) [4]f32 {
    return paint_records.readTexel(data, texel_width, texel_offset);
}

fn writePathLayerInfoTexel(data: []f32, texel_width: u32, texel_offset: u32, value: [4]f32) void {
    paint_records.setTexel(data, texel_width, texel_offset, value);
}

fn paletteColor(index: usize) [4]f32 {
    const palette = [_][4]f32{
        .{ 0.27, 0.86, 0.98, 0.96 },
        .{ 0.98, 0.54, 0.29, 0.96 },
        .{ 0.58, 0.94, 0.43, 0.96 },
        .{ 0.95, 0.39, 0.77, 0.96 },
        .{ 0.99, 0.86, 0.28, 0.96 },
        .{ 0.56, 0.66, 0.98, 0.96 },
    };
    return palette[index % palette.len];
}

fn blendColor(a: [4]f32, b: [4]f32, t: f32) [4]f32 {
    return .{
        a[0] + (b[0] - a[0]) * t,
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
    };
}

fn debugPaintColor(view: PathPictureDebugView, role: PathPicture.LayerRole, shape_index: usize) [4]f32 {
    const base = paletteColor(shape_index);
    return switch (view) {
        .normal => .{ 0, 0, 0, 0 },
        .fill_mask => switch (role) {
            .fill => base,
            .stroke => .{ 0.0, 0.0, 0.0, 0.0 },
        },
        .stroke_mask => switch (role) {
            .fill => .{ 0.0, 0.0, 0.0, 0.0 },
            .stroke => base,
        },
        .layer_tint => switch (role) {
            .fill => blendColor(base, .{ 0.15, 0.90, 0.98, 0.96 }, 0.45),
            .stroke => blendColor(base, .{ 0.98, 0.24, 0.82, 0.96 }, 0.55),
        },
    };
}

pub const PathPicture = struct {
    allocator: std.mem.Allocator,
    atlas: Atlas,
    shapes: []Shape,
    layer_roles: []LayerRole,

    pub const LayerRole = enum(u8) {
        fill,
        stroke,
    };

    pub const Shape = struct {
        glyph_id: u16,
        bbox: BBox,
        page_index: u16,
        info_x: u16,
        info_y: u16,
        layer_count: u16 = 1,
        transform: Transform2D,
    };

    pub fn deinit(self: *PathPicture) void {
        self.atlas.deinit();
        self.allocator.free(self.shapes);
        self.allocator.free(self.layer_roles);
        self.* = undefined;
    }

    pub fn shapeCount(self: *const PathPicture) usize {
        return self.shapes.len;
    }

    pub fn uploadFootprint(self: *const PathPicture) ResourceFootprint {
        return curveAtlasFootprint(&self.atlas, .exact);
    }

    fn applyDebugViewInPlace(self: *PathPicture, view: PathPictureDebugView) void {
        if (view == .normal) return;
        const data = self.atlas.layer_info_data orelse return;
        const width = self.atlas.layer_info_width;

        for (self.shapes, 0..) |shape, shape_index| {
            const info_offset = pathLayerInfoTexelOffset(width, shape.info_x, shape.info_y);
            var header = readPathLayerInfoTexel(data, width, info_offset);
            var layer_count: usize = 1;
            var record_base = info_offset;

            if (@abs(header[3] - PATH_PAINT_TAG_COMPOSITE_GROUP) <= 0.001) {
                layer_count = @intCast(@as(i32, @intFromFloat(@round(header[0]))));
                header[1] = @floatFromInt(@intFromEnum(PathCompositeMode.source_over));
                writePathLayerInfoTexel(data, width, info_offset, header);
                record_base += 1;
            }

            for (0..layer_count) |layer_index| {
                const role_index = @as(usize, shape.glyph_id - 1) + layer_index;
                if (role_index >= self.layer_roles.len) break;
                const texel_offset = record_base + @as(u32, @intCast(layer_index)) * PATH_PAINT_TEXELS_PER_RECORD;
                var info = readPathLayerInfoTexel(data, width, texel_offset);
                info[3] = PATH_PAINT_TAG_SOLID;
                writePathLayerInfoTexel(data, width, texel_offset, info);
                writePathLayerInfoTexel(data, width, texel_offset + 2, debugPaintColor(view, self.layer_roles[role_index], shape_index));
            }
        }
    }

    pub fn withDebugView(
        self: *const PathPicture,
        allocator: std.mem.Allocator,
        view: PathPictureDebugView,
    ) !PathPicture {
        var glyph_map = std.AutoHashMap(u16, Atlas.GlyphInfo).init(allocator);
        errdefer glyph_map.deinit();
        var it = self.atlas.glyph_map.iterator();
        while (it.next()) |entry| try glyph_map.put(entry.key_ptr.*, entry.value_ptr.*);

        const pages = try allocator.alloc(*AtlasPage, self.atlas.pages.len);
        errdefer allocator.free(pages);
        for (self.atlas.pages, 0..) |page, i| pages[i] = page.retain();

        var atlas = try Atlas.initFromParts(allocator, null, pages, glyph_map);
        errdefer atlas.deinit();

        if (self.atlas.layer_info_data) |data| {
            atlas.layer_info_data = try allocator.dupe(f32, data);
            atlas.layer_info_width = self.atlas.layer_info_width;
            atlas.layer_info_height = self.atlas.layer_info_height;
        }
        if (self.atlas.paint_image_records) |records| {
            atlas.paint_image_records = try allocator.dupe(?Atlas.PaintImageRecord, records);
        }

        const shapes = try allocator.dupe(Shape, self.shapes);
        errdefer allocator.free(shapes);
        const layer_roles = try allocator.dupe(LayerRole, self.layer_roles);
        errdefer allocator.free(layer_roles);

        var result = PathPicture{
            .allocator = allocator,
            .atlas = atlas,
            .shapes = shapes,
            .layer_roles = layer_roles,
        };
        result.applyDebugViewInPlace(view);
        return result;
    }

    pub fn buildBoundsOverlay(
        self: *const PathPicture,
        allocator: std.mem.Allocator,
        options: PathPictureBoundsOverlayOptions,
    ) !PathPicture {
        if (self.shapes.len == 0) return error.EmptyPicture;

        var builder = PathPictureBuilder.init(allocator);
        defer builder.deinit();

        const cross_thickness = @max(options.stroke_width, 1.0);
        for (self.shapes) |shape| {
            const rect = Rect{
                .x = shape.bbox.min.x,
                .y = shape.bbox.min.y,
                .w = shape.bbox.max.x - shape.bbox.min.x,
                .h = shape.bbox.max.y - shape.bbox.min.y,
            };
            try builder.addStrokedRect(
                rect,
                .{ .paint = .{ .solid = options.stroke_color }, .width = options.stroke_width, .join = .miter },
                shape.transform,
            );
            if (options.origin_size > 1e-4 and options.origin_color[3] > 1e-4) {
                try builder.addFilledRect(.{
                    .x = -options.origin_size,
                    .y = -cross_thickness * 0.5,
                    .w = options.origin_size * 2.0,
                    .h = cross_thickness,
                }, .{ .paint = .{ .solid = options.origin_color } }, shape.transform);
                try builder.addFilledRect(.{
                    .x = -cross_thickness * 0.5,
                    .y = -options.origin_size,
                    .w = cross_thickness,
                    .h = options.origin_size * 2.0,
                }, .{ .paint = .{ .solid = options.origin_color } }, shape.transform);
            }
        }

        return builder.freeze(.{ .persistent_allocator = allocator, .scratch_allocator = allocator });
    }
};

pub const PathPictureBuilder = struct {
    allocator: std.mem.Allocator,
    paths: std.ArrayList(PathRecord) = .empty,

    pub const ShapeMark = struct {
        shape_count: usize = 0,
    };

    pub const FreezeOptions = struct {
        /// Owns the returned `PathPicture`'s arrays and atlas page data.
        persistent_allocator: std.mem.Allocator,
        /// Used only while compiling path geometry into texture data.
        scratch_allocator: std.mem.Allocator,
    };

    const PathLayerRecord = struct {
        curves: []CurveSegment,
        bbox: BBox,
        logical_curve_count: usize,
        paint: Paint,
        role: PathPicture.LayerRole,
    };

    const PathRecord = struct {
        bbox: BBox,
        transform: Transform2D,
        layer_count: u16,
        composite_mode: PathCompositeMode,
        layers: [2]PathLayerRecord,
    };

    pub fn init(allocator: std.mem.Allocator) PathPictureBuilder {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *PathPictureBuilder) void {
        for (self.paths.items) |path| {
            for (path.layers[0..path.layer_count]) |layer| self.allocator.free(layer.curves);
        }
        self.paths.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn shapeCount(self: *const PathPictureBuilder) usize {
        return self.paths.items.len;
    }

    pub fn mark(self: *const PathPictureBuilder) ShapeMark {
        return .{ .shape_count = self.shapeCount() };
    }

    pub fn rangeFrom(self: *const PathPictureBuilder, mark_value: ShapeMark) !Range {
        return self.rangeBetween(mark_value, self.mark());
    }

    pub fn rangeBetween(self: *const PathPictureBuilder, start: ShapeMark, end: ShapeMark) !Range {
        const total = self.shapeCount();
        if (start.shape_count > total or end.shape_count > total) return error.InvalidShapeMark;
        if (start.shape_count > end.shape_count) return error.InvalidShapeRange;
        return .{
            .start = start.shape_count,
            .count = end.shape_count - start.shape_count,
        };
    }

    fn addSingleRecord(
        self: *PathPictureBuilder,
        curves: []CurveSegment,
        bbox: BBox,
        logical_curve_count: usize,
        paint: Paint,
        role: PathPicture.LayerRole,
        transform: Transform2D,
    ) !void {
        try self.paths.append(self.allocator, .{
            .bbox = bbox,
            .transform = transform,
            .layer_count = 1,
            .composite_mode = .source_over,
            .layers = .{
                .{
                    .curves = curves,
                    .bbox = bbox,
                    .logical_curve_count = logical_curve_count,
                    .paint = paint,
                    .role = role,
                },
                undefined,
            },
        });
    }

    fn shouldTileRoundedRect(size: Vec2) bool {
        return @max(size.x, size.y) > kPathLargePrimitiveTileExtent;
    }

    fn addFilledRectTiles(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: FillStyle,
        transform: Transform2D,
    ) !void {
        const width = @max(rect.w, 0.0);
        const height = @max(rect.h, 0.0);
        if (width <= 1e-4 or height <= 1e-4) return;

        var y = rect.y;
        var remaining_h = height;
        while (remaining_h > 1e-4) {
            const tile_h = @min(remaining_h, kPathLargePrimitiveTileExtent);
            var x = rect.x;
            var remaining_w = width;
            while (remaining_w > 1e-4) {
                const tile_w = @min(remaining_w, kPathLargePrimitiveTileExtent);
                try self.addFilledRect(.{
                    .x = x,
                    .y = y,
                    .w = tile_w,
                    .h = tile_h,
                }, fill, transform);
                x += tile_w;
                remaining_w -= tile_w;
            }
            y += tile_h;
            remaining_h -= tile_h;
        }
    }

    fn addFilledCircularSector(
        self: *PathPictureBuilder,
        center: Vec2,
        outer_radius: f32,
        inner_radius: f32,
        start_angle: f32,
        end_angle: f32,
        fill: FillStyle,
        transform: Transform2D,
    ) !void {
        if (outer_radius <= 1e-4) return;
        var path = Path.init(self.allocator);
        defer path.deinit();
        try buildCircularSectorPath(&path, center, outer_radius, inner_radius, start_angle, end_angle);
        try self.addFilledPath(&path, fill, transform);
    }

    fn addSimpleFilledRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: FillStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.addRoundedRect(rect, corner_radius);
        try self.addPath(&path, fill, null, transform);
    }

    fn addLargeFilledRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: FillStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 1e-4 or size.y <= 1e-4) return;

        const max_radius = @min(size.x, size.y) * 0.5;
        const radius = std.math.clamp(corner_radius, 0.0, max_radius);
        if (radius <= 1.0 / 65536.0) return self.addFilledRect(rect, fill, transform);

        const inner_w = size.x - radius * 2.0;
        const inner_h = size.y - radius * 2.0;

        if (inner_w > 1e-4 and inner_h > 1e-4) {
            try self.addFilledRectTiles(.{
                .x = rect.x + radius,
                .y = rect.y + radius,
                .w = inner_w,
                .h = inner_h,
            }, fill, transform);
        }
        if (inner_w > 1e-4) {
            try self.addFilledRectTiles(.{
                .x = rect.x + radius,
                .y = rect.y,
                .w = inner_w,
                .h = radius,
            }, fill, transform);
            try self.addFilledRectTiles(.{
                .x = rect.x + radius,
                .y = rect.y + size.y - radius,
                .w = inner_w,
                .h = radius,
            }, fill, transform);
        }
        if (inner_h > 1e-4) {
            try self.addFilledRectTiles(.{
                .x = rect.x,
                .y = rect.y + radius,
                .w = radius,
                .h = inner_h,
            }, fill, transform);
            try self.addFilledRectTiles(.{
                .x = rect.x + size.x - radius,
                .y = rect.y + radius,
                .w = radius,
                .h = inner_h,
            }, fill, transform);
        }

        const centers = [4]struct { center: Vec2, start_angle: f32, end_angle: f32 }{
            .{ .center = .{ .x = rect.x + radius, .y = rect.y + radius }, .start_angle = std.math.pi, .end_angle = std.math.pi * 1.5 },
            .{ .center = .{ .x = rect.x + size.x - radius, .y = rect.y + radius }, .start_angle = std.math.pi * 1.5, .end_angle = std.math.pi * 2.0 },
            .{ .center = .{ .x = rect.x + size.x - radius, .y = rect.y + size.y - radius }, .start_angle = 0.0, .end_angle = std.math.pi * 0.5 },
            .{ .center = .{ .x = rect.x + radius, .y = rect.y + size.y - radius }, .start_angle = std.math.pi * 0.5, .end_angle = std.math.pi },
        };
        for (centers) |corner| {
            try self.addFilledCircularSector(
                corner.center,
                radius,
                0.0,
                corner.start_angle,
                corner.end_angle,
                fill,
                transform,
            );
        }
    }

    fn addLargeInsideStrokeRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: ?FillStyle,
        stroke: StrokeStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 1e-4 or size.y <= 1e-4) return;

        const max_radius = @min(size.x, size.y) * 0.5;
        const radius = std.math.clamp(corner_radius, 0.0, max_radius);
        const inset = std.math.clamp(stroke.width, 0.0, max_radius);
        if (radius <= 1.0 / 65536.0) {
            if (fill) |style| {
                const inner_w = @max(size.x - inset * 2.0, 0.0);
                const inner_h = @max(size.y - inset * 2.0, 0.0);
                if (inner_w > 1e-4 and inner_h > 1e-4) {
                    try self.addFilledRectTiles(.{
                        .x = rect.x + inset,
                        .y = rect.y + inset,
                        .w = inner_w,
                        .h = inner_h,
                    }, style, transform);
                }
            }
            const stroke_fill = fillStyleForStroke(stroke);
            if (inset > 1e-4) {
                try self.addFilledRectTiles(.{ .x = rect.x, .y = rect.y, .w = size.x, .h = inset }, stroke_fill, transform);
                try self.addFilledRectTiles(.{ .x = rect.x, .y = rect.y + size.y - inset, .w = size.x, .h = inset }, stroke_fill, transform);
                const middle_h = size.y - inset * 2.0;
                if (middle_h > 1e-4) {
                    try self.addFilledRectTiles(.{ .x = rect.x, .y = rect.y + inset, .w = inset, .h = middle_h }, stroke_fill, transform);
                    try self.addFilledRectTiles(.{ .x = rect.x + size.x - inset, .y = rect.y + inset, .w = inset, .h = middle_h }, stroke_fill, transform);
                }
            }
            return;
        }

        if (fill) |style| {
            const inner_rect = Rect{
                .x = rect.x + inset,
                .y = rect.y + inset,
                .w = size.x - inset * 2.0,
                .h = size.y - inset * 2.0,
            };
            if (inner_rect.w > 1e-4 and inner_rect.h > 1e-4) {
                const inner_radius = std.math.clamp(radius - inset, 0.0, @min(inner_rect.w, inner_rect.h) * 0.5);
                if (shouldTileRoundedRect(Vec2.new(inner_rect.w, inner_rect.h))) {
                    try self.addLargeFilledRoundedRect(inner_rect, style, inner_radius, transform);
                } else {
                    try self.addSimpleFilledRoundedRect(inner_rect, style, inner_radius, transform);
                }
            }
        }

        if (inset <= 1e-4) return;

        const stroke_fill = fillStyleForStroke(stroke);
        const straight_w = size.x - radius * 2.0;
        const straight_h = size.y - radius * 2.0;
        if (straight_w > 1e-4) {
            try self.addFilledRectTiles(.{
                .x = rect.x + radius,
                .y = rect.y,
                .w = straight_w,
                .h = inset,
            }, stroke_fill, transform);
            try self.addFilledRectTiles(.{
                .x = rect.x + radius,
                .y = rect.y + size.y - inset,
                .w = straight_w,
                .h = inset,
            }, stroke_fill, transform);
        }
        if (straight_h > 1e-4) {
            try self.addFilledRectTiles(.{
                .x = rect.x,
                .y = rect.y + radius,
                .w = inset,
                .h = straight_h,
            }, stroke_fill, transform);
            try self.addFilledRectTiles(.{
                .x = rect.x + size.x - inset,
                .y = rect.y + radius,
                .w = inset,
                .h = straight_h,
            }, stroke_fill, transform);
        }

        const inner_radius = @max(radius - inset, 0.0);
        const centers = [4]struct { center: Vec2, start_angle: f32, end_angle: f32 }{
            .{ .center = .{ .x = rect.x + radius, .y = rect.y + radius }, .start_angle = std.math.pi, .end_angle = std.math.pi * 1.5 },
            .{ .center = .{ .x = rect.x + size.x - radius, .y = rect.y + radius }, .start_angle = std.math.pi * 1.5, .end_angle = std.math.pi * 2.0 },
            .{ .center = .{ .x = rect.x + size.x - radius, .y = rect.y + size.y - radius }, .start_angle = 0.0, .end_angle = std.math.pi * 0.5 },
            .{ .center = .{ .x = rect.x + radius, .y = rect.y + size.y - radius }, .start_angle = std.math.pi * 0.5, .end_angle = std.math.pi },
        };
        for (centers) |corner| {
            try self.addFilledCircularSector(
                corner.center,
                radius,
                inner_radius,
                corner.start_angle,
                corner.end_angle,
                stroke_fill,
                transform,
            );
        }
    }

    fn addLargeCenterStrokeRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: ?FillStyle,
        stroke: StrokeStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
        if (size.x <= 1e-4 or size.y <= 1e-4) return;

        const max_radius = @min(size.x, size.y) * 0.5;
        const radius = std.math.clamp(corner_radius, 0.0, max_radius);
        const half_width = @max(stroke.width * 0.5, 0.0);

        if (fill) |style| {
            try self.addLargeFilledRoundedRect(rect, style, radius, transform);
        }

        if (stroke.width <= 1e-4) return;

        var stroke_only = stroke;
        stroke_only.placement = .inside;
        const expanded = Rect{
            .x = rect.x - half_width,
            .y = rect.y - half_width,
            .w = size.x + stroke.width,
            .h = size.y + stroke.width,
        };
        try self.addLargeInsideStrokeRoundedRect(
            expanded,
            null,
            stroke_only,
            radius + half_width,
            transform,
        );
    }

    fn addExplicitInsideStrokeRecord(
        self: *PathPictureBuilder,
        fill_path: *const Path,
        fill: ?FillStyle,
        stroke_path: *const Path,
        stroke_paint: Paint,
        transform: Transform2D,
    ) !void {
        const stroke_bbox = stroke_path.bounds() orelse return error.EmptyPath;
        const stroke_curves = try stroke_path.cloneFilledCurves(self.allocator);
        errdefer self.allocator.free(stroke_curves);
        const stroke_logical_curve_count = stroke_path.filledBandCurveCount();

        if (fill) |style| {
            const fill_bbox = fill_path.bounds() orelse return error.EmptyPath;
            const fill_curves = try fill_path.cloneFilledCurves(self.allocator);
            errdefer self.allocator.free(fill_curves);
            const fill_logical_curve_count = fill_path.filledBandCurveCount();
            try self.addCompositeRecord(
                fill_curves,
                fill_bbox,
                fill_logical_curve_count,
                style.paint,
                stroke_curves,
                stroke_bbox,
                stroke_logical_curve_count,
                stroke_paint,
                transform,
                .fill_stroke_inside,
            );
            return;
        }

        try self.addSingleRecord(stroke_curves, stroke_bbox, stroke_logical_curve_count, stroke_paint, .stroke, transform);
    }

    fn addCompositeRecord(
        self: *PathPictureBuilder,
        fill_curves: []CurveSegment,
        fill_bbox: BBox,
        fill_logical_curve_count: usize,
        fill_paint: Paint,
        stroke_curves: []CurveSegment,
        stroke_bbox: BBox,
        stroke_logical_curve_count: usize,
        stroke_paint: Paint,
        transform: Transform2D,
        composite_mode: PathCompositeMode,
    ) !void {
        try self.paths.append(self.allocator, .{
            .bbox = switch (composite_mode) {
                .source_over => fill_bbox.merge(stroke_bbox),
                .fill_stroke_inside => fill_bbox,
            },
            .transform = transform,
            .layer_count = 2,
            .composite_mode = composite_mode,
            .layers = .{
                .{
                    .curves = fill_curves,
                    .bbox = fill_bbox,
                    .logical_curve_count = fill_logical_curve_count,
                    .paint = fill_paint,
                    .role = .fill,
                },
                .{
                    .curves = stroke_curves,
                    .bbox = stroke_bbox,
                    .logical_curve_count = stroke_logical_curve_count,
                    .paint = stroke_paint,
                    .role = .stroke,
                },
            },
        });
    }

    pub fn addPath(
        self: *PathPictureBuilder,
        path: *const Path,
        fill: ?FillStyle,
        stroke: ?StrokeStyle,
        transform: Transform2D,
    ) !void {
        if (fill == null and stroke == null) return error.EmptyStyle;
        if (path.isEmpty()) return error.EmptyPath;

        if (fill) |style| {
            const bbox = path.bounds() orelse return error.EmptyPath;
            const curves = try path.cloneFilledCurves(self.allocator);
            errdefer self.allocator.free(curves);
            const logical_curve_count = path.filledBandCurveCount();
            if (stroke) |stroke_style| {
                var stroke_geom_style = stroke_style;
                if (stroke_style.placement == .inside) stroke_geom_style.width *= 2.0;
                if (try path.cloneStrokedCurves(self.allocator, stroke_geom_style)) |stroke_geom| {
                    errdefer self.allocator.free(stroke_geom.curves);
                    const composite_mode: PathCompositeMode = if (stroke_style.placement == .inside)
                        .fill_stroke_inside
                    else
                        .source_over;
                    try self.addCompositeRecord(
                        curves,
                        bbox,
                        logical_curve_count,
                        style.paint,
                        stroke_geom.curves,
                        stroke_geom.bbox,
                        stroke_geom.logical_curve_count,
                        stroke_style.paint,
                        transform,
                        composite_mode,
                    );
                    return;
                }
            }
            try self.addSingleRecord(curves, bbox, logical_curve_count, style.paint, .fill, transform);
        }
        if (stroke) |style| {
            var stroke_geom_style = style;
            if (style.placement == .inside) stroke_geom_style.width *= 2.0;
            if (try path.cloneStrokedCurves(self.allocator, stroke_geom_style)) |stroke_geom| {
                errdefer self.allocator.free(stroke_geom.curves);
                if (style.placement == .inside) {
                    const fill_bbox = path.bounds() orelse return error.EmptyPath;
                    const fill_curves = try path.cloneFilledCurves(self.allocator);
                    errdefer self.allocator.free(fill_curves);
                    try self.addCompositeRecord(
                        fill_curves,
                        fill_bbox,
                        path.filledBandCurveCount(),
                        .{ .solid = .{ 0, 0, 0, 0 } },
                        stroke_geom.curves,
                        stroke_geom.bbox,
                        stroke_geom.logical_curve_count,
                        style.paint,
                        transform,
                        .fill_stroke_inside,
                    );
                    return;
                }
                try self.addSingleRecord(
                    stroke_geom.curves,
                    stroke_geom.bbox,
                    stroke_geom.logical_curve_count,
                    style.paint,
                    .stroke,
                    transform,
                );
            }
        }
    }

    pub fn addFilledPath(
        self: *PathPictureBuilder,
        path: *const Path,
        fill: FillStyle,
        transform: Transform2D,
    ) !void {
        try self.addPath(path, fill, null, transform);
    }

    pub fn addStrokedPath(
        self: *PathPictureBuilder,
        path: *const Path,
        stroke: StrokeStyle,
        transform: Transform2D,
    ) !void {
        try self.addPath(path, null, stroke, transform);
    }

    pub fn addRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: ?FillStyle,
        stroke: ?StrokeStyle,
        transform: Transform2D,
    ) !void {
        if (stroke) |stroke_style| {
            const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
            const inset = std.math.clamp(stroke_style.width, 0.0, @min(size.x, size.y) * 0.5);
            if (stroke_style.placement == .inside and inset > 1e-4) {
                var fill_path = Path.init(self.allocator);
                defer fill_path.deinit();
                try fill_path.addRect(rect);

                var stroke_path = Path.init(self.allocator);
                defer stroke_path.deinit();
                try stroke_path.addRect(rect);
                if (size.x - inset * 2.0 > 1e-4 and size.y - inset * 2.0 > 1e-4) {
                    try stroke_path.addRectReversed(.{
                        .x = rect.x + inset,
                        .y = rect.y + inset,
                        .w = size.x - inset * 2.0,
                        .h = size.y - inset * 2.0,
                    });
                }
                return self.addExplicitInsideStrokeRecord(&fill_path, fill, &stroke_path, stroke_style.paint, transform);
            }
        }

        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.addRect(rect);
        try self.addPath(&path, fill, stroke, transform);
    }

    pub fn addRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: ?FillStyle,
        stroke: ?StrokeStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));

        if (stroke) |stroke_style| {
            const max_radius = @min(size.x, size.y) * 0.5;
            const radius = std.math.clamp(corner_radius, 0.0, max_radius);
            const inset = std.math.clamp(stroke_style.width, 0.0, max_radius);
            if (stroke_style.placement == .inside and inset > 1e-4) {
                var fill_path = Path.init(self.allocator);
                defer fill_path.deinit();
                try fill_path.addRoundedRect(rect, radius);

                var stroke_path = Path.init(self.allocator);
                defer stroke_path.deinit();
                try stroke_path.addRoundedRect(rect, radius);
                if (size.x - inset * 2.0 > 1e-4 and size.y - inset * 2.0 > 1e-4) {
                    const inner_rect = Rect{
                        .x = rect.x + inset,
                        .y = rect.y + inset,
                        .w = size.x - inset * 2.0,
                        .h = size.y - inset * 2.0,
                    };
                    const inner_radius = std.math.clamp(radius - inset, 0.0, @min(inner_rect.w, inner_rect.h) * 0.5);
                    try stroke_path.addRoundedRectReversed(inner_rect, inner_radius);
                }
                return self.addExplicitInsideStrokeRecord(&fill_path, fill, &stroke_path, stroke_style.paint, transform);
            }
        }

        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.addRoundedRect(rect, corner_radius);
        try self.addPath(&path, fill, stroke, transform);
    }

    pub fn addEllipse(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: ?FillStyle,
        stroke: ?StrokeStyle,
        transform: Transform2D,
    ) !void {
        if (stroke) |stroke_style| {
            const size = Vec2.new(@max(rect.w, 0.0), @max(rect.h, 0.0));
            const inset = std.math.clamp(stroke_style.width, 0.0, @min(size.x, size.y) * 0.5);
            if (stroke_style.placement == .inside and inset > 1e-4) {
                var fill_path = Path.init(self.allocator);
                defer fill_path.deinit();
                try fill_path.addEllipse(rect);

                var stroke_path = Path.init(self.allocator);
                defer stroke_path.deinit();
                try stroke_path.addEllipse(rect);
                if (size.x - inset * 2.0 > 1e-4 and size.y - inset * 2.0 > 1e-4) {
                    try stroke_path.addEllipseReversed(.{
                        .x = rect.x + inset,
                        .y = rect.y + inset,
                        .w = size.x - inset * 2.0,
                        .h = size.y - inset * 2.0,
                    });
                }
                return self.addExplicitInsideStrokeRecord(&fill_path, fill, &stroke_path, stroke_style.paint, transform);
            }
        }

        var path = Path.init(self.allocator);
        defer path.deinit();
        try path.addEllipse(rect);
        try self.addPath(&path, fill, stroke, transform);
    }

    pub fn addFilledRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: FillStyle,
        transform: Transform2D,
    ) !void {
        try self.addRect(rect, fill, null, transform);
    }

    pub fn addFilledRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: FillStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        try self.addRoundedRect(rect, fill, null, corner_radius, transform);
    }

    pub fn addFilledEllipse(
        self: *PathPictureBuilder,
        rect: Rect,
        fill: FillStyle,
        transform: Transform2D,
    ) !void {
        try self.addEllipse(rect, fill, null, transform);
    }

    pub fn addStrokedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        stroke: StrokeStyle,
        transform: Transform2D,
    ) !void {
        try self.addRect(rect, null, stroke, transform);
    }

    pub fn addStrokedRoundedRect(
        self: *PathPictureBuilder,
        rect: Rect,
        stroke: StrokeStyle,
        corner_radius: f32,
        transform: Transform2D,
    ) !void {
        try self.addRoundedRect(rect, null, stroke, corner_radius, transform);
    }

    pub fn addStrokedEllipse(
        self: *PathPictureBuilder,
        rect: Rect,
        stroke: StrokeStyle,
        transform: Transform2D,
    ) !void {
        try self.addEllipse(rect, null, stroke, transform);
    }

    pub fn freeze(self: *const PathPictureBuilder, options: FreezeOptions) !PathPicture {
        if (self.paths.items.len == 0) return error.EmptyPicture;
        const allocator = options.persistent_allocator;
        const scratch_allocator = options.scratch_allocator;

        var total_layer_count: usize = 0;
        var total_paint_texels: u32 = 0;
        for (self.paths.items) |path| {
            total_layer_count += path.layer_count;
            total_paint_texels += if (path.layer_count == 1)
                kPaintTexelsPerRecord
            else
                1 + @as(u32, path.layer_count) * kPaintTexelsPerRecord;
        }

        const glyph_curves = try scratch_allocator.alloc(curve_tex.GlyphCurves, total_layer_count);
        defer scratch_allocator.free(glyph_curves);
        const packed_curve_slices = try scratch_allocator.alloc([]CurveSegment, total_layer_count);
        defer scratch_allocator.free(packed_curve_slices);
        const prepared_curve_slices = try scratch_allocator.alloc([]CurveSegment, total_layer_count);
        defer scratch_allocator.free(prepared_curve_slices);
        var glyph_cursor: usize = 0;
        defer {
            for (packed_curve_slices[0..glyph_cursor], prepared_curve_slices[0..glyph_cursor]) |curves, prepared_curves| {
                scratch_allocator.free(curves);
                scratch_allocator.free(prepared_curves);
            }
        }
        for (self.paths.items) |path| {
            const origin = bboxCenter(path.bbox);
            for (path.layers[0..path.layer_count]) |layer| {
                const stored_curves = try scratch_allocator.dupe(CurveSegment, layer.curves);
                const prepared_curves = curve_tex.prepareGlyphCurvesForDirectEncoding(scratch_allocator, stored_curves, origin) catch |err| {
                    scratch_allocator.free(stored_curves);
                    return err;
                };
                packed_curve_slices[glyph_cursor] = stored_curves;
                prepared_curve_slices[glyph_cursor] = prepared_curves;
                glyph_curves[glyph_cursor] = .{
                    .curves = stored_curves,
                    .bbox = layer.bbox,
                    .origin = origin,
                    .logical_curve_count = layer.logical_curve_count,
                    .prefer_direct_encoding = true,
                    .prepared_curves = prepared_curves,
                };
                glyph_cursor += 1;
            }
        }

        var ct = try curve_tex.buildCurveTexture(allocator, scratch_allocator, glyph_curves);
        var ct_texture_owned = true;
        errdefer if (ct_texture_owned) ct.texture.deinit();
        defer scratch_allocator.free(ct.entries);

        var glyph_band_data: std.ArrayList(band_tex.GlyphBandData) = .empty;
        defer {
            for (glyph_band_data.items) |*bd| band_tex.freeGlyphBandData(scratch_allocator, bd);
            glyph_band_data.deinit(scratch_allocator);
        }
        for (glyph_curves, 0..) |gc, i| {
            var bd = try band_tex.buildGlyphBandDataForGlyph(scratch_allocator, gc, ct.entries[i]);
            try glyph_band_data.append(scratch_allocator, bd);
            _ = &bd;
        }

        var bt = try band_tex.buildBandTexture(allocator, scratch_allocator, glyph_band_data.items);
        var bt_texture_owned = true;
        errdefer if (bt_texture_owned) bt.texture.deinit();
        defer scratch_allocator.free(bt.entries);

        var glyph_map = std.AutoHashMap(u16, Atlas.GlyphInfo).init(allocator);
        errdefer glyph_map.deinit();

        const paint_width = pathPaintInfoWidth(total_paint_texels);
        const paint_height = @max(1, (total_paint_texels + paint_width - 1) / paint_width);
        const layer_info_data = try allocator.alloc(f32, paint_width * paint_height * 4);
        errdefer allocator.free(layer_info_data);
        @memset(layer_info_data, 0);

        const shapes = try allocator.alloc(PathPicture.Shape, self.paths.items.len);
        errdefer allocator.free(shapes);

        const layer_roles = try allocator.alloc(PathPicture.LayerRole, total_layer_count);
        errdefer allocator.free(layer_roles);

        const paint_image_records = try allocator.alloc(?Atlas.PaintImageRecord, total_layer_count);
        errdefer allocator.free(paint_image_records);
        @memset(paint_image_records, null);

        var has_image_paints = false;

        glyph_cursor = 0;
        var texel_cursor: u32 = 0;
        for (self.paths.items, 0..) |path, path_index| {
            const info_texel_offset = texel_cursor;
            if (path.layer_count > 1) {
                paint_records.setTexel(layer_info_data, paint_width, texel_cursor, .{
                    @floatFromInt(path.layer_count),
                    @floatFromInt(@intFromEnum(path.composite_mode)),
                    0,
                    kPaintTagCompositeGroup,
                });
                texel_cursor += 1;
            }

            var first_glyph_id: u16 = 0;
            const origin = bboxCenter(path.bbox);
            const delta = Vec2.new(-origin.x, -origin.y);
            for (path.layers[0..path.layer_count], 0..) |layer, layer_index| {
                const glyph_id: u16 = @intCast(glyph_cursor + 1);
                if (layer_index == 0) first_glyph_id = glyph_id;
                const local_bbox = translateBBox(layer.bbox, delta);
                const local_paint = translatePaint(layer.paint, delta);
                try glyph_map.put(glyph_id, .{
                    .bbox = local_bbox,
                    .advance_width = 0,
                    .band_entry = bt.entries[glyph_cursor],
                    .page_index = 0,
                });
                layer_roles[glyph_cursor] = layer.role;
                paint_records.write(layer_info_data, paint_width, texel_cursor, bt.entries[glyph_cursor], local_paint);
                switch (local_paint) {
                    .image => |image_paint| {
                        paint_image_records[glyph_cursor] = .{
                            .image = image_paint.image,
                            .texel_offset = texel_cursor,
                        };
                        has_image_paints = true;
                    },
                    else => {},
                }
                texel_cursor += kPaintTexelsPerRecord;
                glyph_cursor += 1;
            }

            shapes[path_index] = .{
                .glyph_id = first_glyph_id,
                .bbox = translateBBox(path.bbox, delta),
                .page_index = 0,
                .info_x = @intCast(info_texel_offset % paint_width),
                .info_y = @intCast(info_texel_offset / paint_width),
                .layer_count = path.layer_count,
                .transform = Transform2D.multiply(path.transform, Transform2D.translate(origin.x, origin.y)),
            };
        }

        const page = try AtlasPage.init(
            allocator,
            ct.texture.data,
            ct.texture.width,
            ct.texture.height,
            bt.texture.data,
            bt.texture.width,
            bt.texture.height,
        );
        ct_texture_owned = false;
        bt_texture_owned = false;
        errdefer page.release();

        const pages = try allocator.alloc(*AtlasPage, 1);
        errdefer allocator.free(pages);
        pages[0] = page;

        var atlas = try Atlas.initFromParts(allocator, null, pages, glyph_map);
        errdefer atlas.deinit();
        atlas.layer_info_data = layer_info_data;
        atlas.layer_info_width = paint_width;
        atlas.layer_info_height = paint_height;
        if (has_image_paints) {
            atlas.paint_image_records = paint_image_records;
        } else {
            allocator.free(paint_image_records);
        }

        return .{
            .allocator = allocator,
            .atlas = atlas,
            .shapes = shapes,
            .layer_roles = layer_roles,
        };
    }
};

pub const PathBatch = struct {
    buf: []u32,
    len: usize = 0,
    layer_window_base: ?u32 = null,

    pub fn init(buf: []u32) PathBatch {
        return .{ .buf = buf };
    }

    pub fn reset(self: *PathBatch) void {
        self.len = 0;
        self.layer_window_base = null;
    }

    pub fn shapeCount(self: *const PathBatch) usize {
        return self.len / PATH_WORDS_PER_SHAPE;
    }

    pub fn slice(self: *const PathBatch) []const u32 {
        return self.buf[0..self.len];
    }

    pub const AppendResult = struct {
        emitted: usize,
        next_shape: usize,
        completed: bool,
        layer_window_base: u32,
    };

    pub fn currentLayerWindowBase(self: *const PathBatch) u32 {
        return self.layer_window_base orelse 0;
    }

    fn localLayer(self: *PathBatch, atlas_layer: u32) !u8 {
        const base = textureLayerWindowBase(atlas_layer);
        if (self.layer_window_base) |expected| {
            if (base != expected) return error.TextureLayerWindowChanged;
        } else {
            self.layer_window_base = base;
        }
        return textureLayerLocal(atlas_layer);
    }

    /// Emit one slice of a `PathDraw` into this batch: the shapes from
    /// `[shape_start, draw.shapes.end)` under `draw.instances[override_index]`.
    /// Returns where to resume; the caller is responsible for advancing
    /// across overrides and re-opening batches when full or when the
    /// texture layer window changes.
    pub fn addDraw(
        self: *PathBatch,
        atlas_like: anytype,
        draw: PathDraw,
        override_index: usize,
        shape_start: usize,
    ) !AppendResult {
        const resolved_view = lowlevel_mod.coerceAtlasHandle(atlas_like);
        const view = &resolved_view;
        const range = draw.shapes.resolve(draw.picture.shapes.len);
        const start = @max(shape_start, range.start);
        if (start > range.end) return error.InvalidShapeRange;
        if (override_index >= draw.instances.len) return error.InvalidOverrideIndex;
        const override = draw.instances[override_index];
        var count: usize = 0;
        var idx = start;
        while (idx < range.end) : (idx += 1) {
            const shape = draw.picture.shapes[idx];
            const layer_base = view.glyphLayerWindowBase(shape.page_index);
            if (self.layer_window_base) |base| {
                if (base != layer_base) break;
            } else {
                self.layer_window_base = layer_base;
            }
            if (self.len + PATH_WORDS_PER_SHAPE > self.buf.len) return error.DrawListFull;
            const final_transform = Transform2D.multiply(override.transform, shape.transform);
            const info_loc = view.layerInfoLoc(shape.info_x, shape.info_y);
            const local_layer = try self.localLayer(view.glyphLayer(shape.page_index));
            if (!vertex_mod.generatePathRecordVerticesTransformedTinted(
                self.buf[self.len..],
                shape.bbox,
                info_loc.x,
                info_loc.y,
                shape.layer_count,
                .{ 1, 1, 1, 1 },
                override.tint,
                local_layer,
                final_transform,
            )) return error.InvalidTransform;
            self.len += PATH_WORDS_PER_SHAPE;
            count += 1;
        }
        return .{
            .emitted = count,
            .next_shape = idx,
            .completed = idx >= range.end,
            .layer_window_base = self.currentLayerWindowBase(),
        };
    }
};

test "vector path band count tracks source cubic commands" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();

    try path.moveTo(.{ .x = 0, .y = 0 });
    try path.cubicTo(.{ .x = 8, .y = 20 }, .{ .x = 16, .y = -20 }, .{ .x = 24, .y = 0 });
    try path.close();

    const filled = try path.cloneFilledCurves(std.testing.allocator);
    defer std.testing.allocator.free(filled);

    try std.testing.expect(filled.len > 2);
    try std.testing.expectEqual(@as(usize, 2), path.filledBandCurveCount());
}

test "path picture band heuristic uses source segment count for cubic fills" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();

    try path.moveTo(.{ .x = 0, .y = 0 });
    try path.cubicTo(.{ .x = 8, .y = 20 }, .{ .x = 16, .y = -20 }, .{ .x = 24, .y = 0 });
    try path.close();

    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addFilledPath(&path, .{ .paint = .{ .solid = .{ 0.8, 0.2, 0.1, 1.0 } } }, .identity);

    var picture = try builder.freeze(.{ .persistent_allocator = std.testing.allocator, .scratch_allocator = std.testing.allocator });
    defer picture.deinit();

    const info = picture.atlas.getGlyph(picture.shapes[0].glyph_id) orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(u16, 1), info.band_entry.h_band_count);
    try std.testing.expectEqual(@as(u16, 1), info.band_entry.v_band_count);
}

test "path picture layers use direct local curve encoding" {
    var body = Path.init(std.testing.allocator);
    defer body.deinit();
    try body.moveTo(.{ .x = 28.0, .y = 155.0 });
    try body.cubicTo(.{ .x = 62.0, .y = 132.0 }, .{ .x = 106.0, .y = 121.0 }, .{ .x = 142.0, .y = 127.0 });
    try body.cubicTo(.{ .x = 179.0, .y = 133.0 }, .{ .x = 210.0, .y = 151.0 }, .{ .x = 246.0, .y = 151.0 });
    try body.cubicTo(.{ .x = 288.0, .y = 151.0 }, .{ .x = 317.0, .y = 145.0 }, .{ .x = 332.0, .y = 131.0 });
    try body.cubicTo(.{ .x = 346.0, .y = 119.0 }, .{ .x = 345.0, .y = 104.0 }, .{ .x = 327.0, .y = 100.0 });
    try body.cubicTo(.{ .x = 307.0, .y = 96.0 }, .{ .x = 286.0, .y = 105.0 }, .{ .x = 278.0, .y = 119.0 });
    try body.cubicTo(.{ .x = 269.0, .y = 132.0 }, .{ .x = 252.0, .y = 136.0 }, .{ .x = 233.0, .y = 132.0 });
    try body.cubicTo(.{ .x = 210.0, .y = 126.0 }, .{ .x = 189.0, .y = 105.0 }, .{ .x = 166.0, .y = 92.0 });
    try body.cubicTo(.{ .x = 142.0, .y = 79.0 }, .{ .x = 106.0, .y = 84.0 }, .{ .x = 82.0, .y = 106.0 });
    try body.cubicTo(.{ .x = 58.0, .y = 127.0 }, .{ .x = 42.0, .y = 149.0 }, .{ .x = 28.0, .y = 155.0 });
    try body.close();

    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addPath(&body, .{ .paint = .{ .linear_gradient = .{
        .start = .{ .x = 48.0, .y = 102.0 },
        .end = .{ .x = 320.0, .y = 158.0 },
        .start_color = .{ 0.90, 0.87, 0.78, 0.98 },
        .end_color = .{ 0.58, 0.66, 0.57, 0.98 },
    } } }, .{
        .paint = .{ .solid = .{ 0.92, 0.92, 0.86, 0.42 } },
        .width = 2.0,
        .join = .round,
    }, .identity);

    var picture = try builder.freeze(.{ .persistent_allocator = std.testing.allocator, .scratch_allocator = std.testing.allocator });
    defer picture.deinit();

    const fill_info = picture.atlas.getGlyph(picture.shapes[0].glyph_id) orelse return error.TestExpectedEqual;
    const stroke_info = picture.atlas.getGlyph(picture.shapes[0].glyph_id + 1) orelse return error.TestExpectedEqual;
    try std.testing.expect(fill_info.band_entry.h_band_count > 0);
    try std.testing.expect(stroke_info.band_entry.h_band_count > 0);
    try std.testing.expectEqual(
        curve_tex.f32ToF16(curve_tex.DIRECT_ENCODING_KIND_BIAS),
        picture.atlas.page(0).curve_data[10],
    );
}

test "path picture freeze compiles atlas and transformed batch vertices" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();
    try path.moveTo(.{ .x = 0, .y = 0 });
    try path.lineTo(.{ .x = 16, .y = 0 });
    try path.lineTo(.{ .x = 8, .y = 12 });

    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addFilledPath(&path, .{ .paint = .{ .solid = .{ 0.8, 0.2, 0.1, 1.0 } } }, .{
        .xx = 1,
        .xy = 0,
        .tx = 20,
        .yx = 0,
        .yy = 1,
        .ty = 30,
    });

    var picture = try builder.freeze(.{ .persistent_allocator = std.testing.allocator, .scratch_allocator = std.testing.allocator });
    defer picture.deinit();
    try std.testing.expectEqual(@as(usize, 1), picture.shapeCount());
    try std.testing.expectEqual(@as(usize, 1), picture.atlas.pageCount());
    try std.testing.expectEqual(@as(u32, kPaintTexelsPerRecord), picture.atlas.layer_info_width);
    try std.testing.expectEqual(@as(u32, 1), picture.atlas.layer_info_height);
    try std.testing.expectEqual(@as(usize, kPaintTexelsPerRecord * 4), picture.atlas.layer_info_data.?.len);

    var vertex_buf: [PATH_WORDS_PER_SHAPE]u32 = undefined;
    var batch = PathBatch.init(&vertex_buf);
    const view = PreparedAtlasView{ .atlas = &picture.atlas };
    const result = try batch.addDraw(&view, .{ .picture = &picture }, 0, 0);
    try std.testing.expectEqual(@as(usize, 1), result.emitted);
    try std.testing.expect(result.completed);
    try std.testing.expectEqual(@as(usize, PATH_WORDS_PER_SHAPE), batch.slice().len);
    // Verify that the min corner world position equals the intended translation.
    const s = vertex_mod.decodeInstance(batch.slice());
    const world_x = s.xform[0] * s.rect[0] + s.xform[1] * s.rect[1] + s.origin[0];
    const world_y = s.xform[2] * s.rect[0] + s.xform[3] * s.rect[1] + s.origin[1];
    try std.testing.expectApproxEqAbs(@as(f32, 20), world_x, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 30), world_y, 0.5);
    const packed_gw = s.glyph[1];
    try std.testing.expectEqual(@as(u32, 0xFF), packed_gw >> 24);
    try std.testing.expectEqual(@as(u32, @intFromEnum(vertex_mod.SpecialGlyphKind.path)), (packed_gw >> 16) & 0xFF);
    try std.testing.expectApproxEqAbs(@as(f32, 0), s.band[3], 0.001);
}

test "resource upload footprints are allocation-free and policy-aware" {
    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addFilledRect(.{ .x = 0, .y = 0, .w = 10, .h = 8 }, .{ .paint = .{ .solid = .{ 1, 0, 0, 1 } } }, .identity);

    var picture = try builder.freeze(.{ .persistent_allocator = std.testing.allocator, .scratch_allocator = std.testing.allocator });
    defer picture.deinit();

    const picture_fp = picture.uploadFootprint();
    try std.testing.expectEqual(@as(usize, kPaintTexelsPerRecord * 4 * @sizeOf(f32)), picture_fp.layer_info_bytes_used);
    try std.testing.expectEqual(picture_fp.layer_info_bytes_used, picture_fp.layer_info_bytes_allocated);
    try std.testing.expect(picture_fp.curve_bytes_allocated >= picture_fp.curve_bytes_used);
    try std.testing.expect(picture_fp.band_bytes_allocated >= picture_fp.band_bytes_used);

    var pixels = [_]u8{ 255, 0, 0, 255 };
    var image = try Image.initSrgba8(std.testing.allocator, 1, 1, &pixels);
    defer image.deinit();
    const image_fp = image.uploadFootprint();
    try std.testing.expectEqual(@as(usize, 4), image_fp.image_bytes_used);
    try std.testing.expectEqual(@as(usize, 4), image_fp.image_bytes_allocated);

    var entries: [2]ResourceSet.Entry = undefined;
    var set = ResourceSet.init(&entries);
    try set.putPathPicture(.shape, &picture);
    try set.putImage(.image, &image);
    const set_fp = try set.estimateUploadFootprint();
    try std.testing.expectEqual(picture_fp.layer_info_bytes_used, set_fp.layer_info_bytes_used);
    try std.testing.expectEqual(@as(usize, 4), set_fp.image_bytes_used);
    try std.testing.expectEqual(@as(usize, 4), set_fp.image_bytes_allocated);

    var growable_entries: [1]ResourceSet.Entry = undefined;
    var growable_set = ResourceSet.init(&growable_entries);
    try growable_set.putPathPictureOptions(.shape, &picture, .{ .atlas_capacity = .growable });
    const growable_fp = try growable_set.estimateUploadFootprint();
    try std.testing.expect(growable_fp.curve_bytes_allocated > set_fp.curve_bytes_allocated);
}

test "path picture ranges emit selected shapes" {
    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    const first_mark = builder.mark();
    try builder.addFilledRect(.{ .x = 0, .y = 0, .w = 20, .h = 10 }, .{ .paint = .{ .solid = .{ 0.8, 0.2, 0.1, 1.0 } } }, .identity);
    const second_mark = builder.mark();
    try builder.addFilledRect(.{ .x = 40, .y = 0, .w = 20, .h = 10 }, .{ .paint = .{ .solid = .{ 0.1, 0.4, 0.8, 1.0 } } }, .identity);
    try std.testing.expectEqual(@as(usize, 2), builder.shapeCount());
    const first_range = try builder.rangeBetween(first_mark, second_mark);
    try std.testing.expectEqual(@as(usize, 0), first_range.start);
    try std.testing.expectEqual(@as(usize, 1), first_range.count);
    const second_range = try builder.rangeFrom(second_mark);
    try std.testing.expectEqual(@as(usize, 1), second_range.start);
    try std.testing.expectEqual(@as(usize, 1), second_range.count);
    const full_range = try builder.rangeFrom(first_mark);
    try std.testing.expectEqual(@as(usize, 0), full_range.start);
    try std.testing.expectEqual(@as(usize, 2), full_range.count);
    try std.testing.expectError(error.InvalidShapeMark, builder.rangeFrom(.{ .shape_count = 3 }));
    try std.testing.expectError(error.InvalidShapeRange, builder.rangeBetween(second_mark, first_mark));

    var picture = try builder.freeze(.{ .persistent_allocator = std.testing.allocator, .scratch_allocator = std.testing.allocator });
    defer picture.deinit();

    var vertex_buf: [PATH_WORDS_PER_SHAPE]u32 = undefined;
    var batch = PathBatch.init(&vertex_buf);
    const view = PreparedAtlasView{ .atlas = &picture.atlas };
    const result = try batch.addDraw(&view, .{
        .picture = &picture,
        .shapes = second_range,
    }, 0, 0);
    try std.testing.expectEqual(@as(usize, 1), result.emitted);
    try std.testing.expect(result.completed);
    try std.testing.expectEqual(@as(usize, PATH_WORDS_PER_SHAPE), batch.slice().len);

    var scene = Scene.init(std.testing.allocator);
    defer scene.deinit();
    try scene.addPath(.{ .picture = &picture, .shapes = second_range });
    const options = DrawOptions{ .mvp = Mat4.identity, .target = .{ .pixel_width = 100, .pixel_height = 100, .encoding = .srgb } };
    try std.testing.expectEqual(@as(usize, PATH_WORDS_PER_SHAPE), DrawList.estimate(&scene, options));
    try std.testing.expectEqual(@as(usize, 1), DrawList.estimateSegments(&scene, options));
}

test "path picture freeze separates persistent and scratch allocators" {
    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addFilledRect(.{ .x = 0, .y = 0, .w = 20, .h = 10 }, .{ .paint = .{ .solid = .{ 0.2, 0.6, 0.9, 1.0 } } }, .identity);

    var scratch_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    var picture = try builder.freeze(.{
        .persistent_allocator = std.testing.allocator,
        .scratch_allocator = scratch_arena.allocator(),
    });
    _ = scratch_arena.reset(.free_all);
    scratch_arena.deinit();
    defer picture.deinit();

    try std.testing.expectEqual(@as(usize, 1), picture.shapeCount());
    try std.testing.expect(picture.uploadFootprint().allocatedBytes() > 0);

    var vertex_buf: [PATH_WORDS_PER_SHAPE]u32 = undefined;
    var batch = PathBatch.init(&vertex_buf);
    const view = PreparedAtlasView{ .atlas = &picture.atlas };
    const result = try batch.addDraw(&view, .{ .picture = &picture }, 0, 0);
    try std.testing.expectEqual(@as(usize, 1), result.emitted);
    try std.testing.expect(result.completed);
}

test "path batch offsets layer info rows through atlas views" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();
    try path.addRect(.{ .x = 0, .y = 0, .w = 20, .h = 10 });

    var builder = PathPictureBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.addFilledPath(&path, .{ .paint = .{ .solid = .{ 0.4, 0.7, 0.9, 1.0 } } }, .identity);

    var picture = try builder.freeze(.{ .persistent_allocator = std.testing.allocator, .scratch_allocator = std.testing.allocator });
    defer picture.deinit();

    var vertex_buf: [PATH_WORDS_PER_SHAPE]u32 = undefined;
    var batch = PathBatch.init(&vertex_buf);
    const offset_view = PreparedAtlasView{
        .atlas = &picture.atlas,
        .layer_base = 3,
        .info_row_base = 17,
    };
    {
        const r = try batch.addDraw(&offset_view, .{ .picture = &picture }, 0, 0);
        try std.testing.expectEqual(@as(usize, 1), r.emitted);
    }
    const s = vertex_mod.decodeInstance(batch.slice());
    const packed_gz = s.glyph[0];
    try std.testing.expectEqual(@as(u32, picture.shapes[0].info_x), packed_gz & 0xFFFF);
    try std.testing.expectEqual(@as(u32, offset_view.info_row_base + picture.shapes[0].info_y), packed_gz >> 16);
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(try textureLayerLocal(offset_view.glyphLayer(0)))), s.band[3], 0.001);
}

test "square-capped stroked path extends beyond endpoints" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();
    try path.moveTo(.{ .x = 0, .y = 0 });
    try path.lineTo(.{ .x = 12, .y = 0 });

    const stroke_geom = (try path.cloneStrokedCurves(std.testing.allocator, .{
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
        .width = 6.0,
        .cap = .square,
        .join = .miter,
    })) orelse return error.TestExpectedEqual;
    defer std.testing.allocator.free(stroke_geom.curves);

    try std.testing.expectApproxEqAbs(@as(f32, -3.0), stroke_geom.bbox.min.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 15.0), stroke_geom.bbox.max.x, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, -3.0), stroke_geom.bbox.min.y, 0.05);
    try std.testing.expectApproxEqAbs(@as(f32, 3.0), stroke_geom.bbox.max.y, 0.05);
}

test "elliptical stroke outline stays curved without degenerate joins" {
    var path = Path.init(std.testing.allocator);
    defer path.deinit();
    try path.addEllipse(.{ .x = 0, .y = 0, .w = 100, .h = 60 });

    const stroke_geom = (try path.cloneStrokedCurves(std.testing.allocator, .{
        .paint = .{ .solid = .{ 1, 1, 1, 1 } },
        .width = 8.0,
        .join = .round,
    })) orelse return error.TestExpectedEqual;
    defer std.testing.allocator.free(stroke_geom.curves);

    var curved_count: usize = 0;
    for (stroke_geom.curves) |curve| {
        try std.testing.expect(Vec2.length(Vec2.sub(curve.endPoint(), curve.p0)) > 1e-4);
        const chord_mid = Vec2.lerp(curve.p0, curve.endPoint(), 0.5);
        const curve_mid = curve.evaluate(0.5);
        if (Vec2.length(Vec2.sub(curve_mid, chord_mid)) > 1e-3) curved_count += 1;
    }
    try std.testing.expect(curved_count >= 8);
}

test "quadratic stroked eye stalk contains its centerline midpoint" {
    const cases = [_]struct {
        start: Vec2,
        control: Vec2,
        end: Vec2,
    }{
        .{
            .start = .{ .x = 308.0, .y = 100.0 },
            .control = .{ .x = 316.0, .y = 76.0 },
            .end = .{ .x = 334.0, .y = 58.0 },
        },
        .{
            .start = .{ .x = 294.0, .y = 102.0 },
            .control = .{ .x = 298.0, .y = 80.0 },
            .end = .{ .x = 306.0, .y = 64.0 },
        },
    };

    for (cases) |case| {
        var path = Path.init(std.testing.allocator);
        defer path.deinit();
        try path.moveTo(case.start);
        try path.quadTo(case.control, case.end);

        const stroke_geom = (try path.cloneStrokedCurves(std.testing.allocator, .{
            .paint = .{ .solid = .{ 1, 1, 1, 1 } },
            .width = 4.0,
            .cap = .round,
            .join = .round,
        })) orelse return error.TestExpectedEqual;
        defer std.testing.allocator.free(stroke_geom.curves);

        const quads = try std.testing.allocator.alloc(bezier.QuadBezier, stroke_geom.curves.len);
        defer std.testing.allocator.free(quads);
        for (stroke_geom.curves, 0..) |curve, i| quads[i] = curve.asQuad();

        const midpoint = (bezier.QuadBezier{
            .p0 = case.start,
            .p1 = case.control,
            .p2 = case.end,
        }).evaluate(0.5);
        try std.testing.expect(roots.isInside(quads, midpoint));
    }
}
