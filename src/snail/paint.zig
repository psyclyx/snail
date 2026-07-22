//! Paint payloads for fills and strokes. All `[4]f32` colors are LINEAR
//! light with straight alpha (see `color.zig`); gradient endpoints
//! interpolate in linear light.

const std = @import("std");
const image_mod = @import("image.zig");
const vec = @import("math/vec.zig");

const Image = image_mod.Image;
const Transform2D = vec.Transform2D;
const Vec2 = vec.Vec2;

pub const FillRule = enum(c_int) {
    non_zero = 0,
    even_odd = 1,
};

pub const Extend = enum(u8) {
    clamp = 0,
    repeat = 1,
    reflect = 2,
};

pub const ImageFilter = enum(u8) {
    linear = 0,
    nearest = 1,
};

pub const LinearGradient = struct {
    start: Vec2,
    end: Vec2,
    start_color: [4]f32,
    end_color: [4]f32,
    extend: Extend = .clamp,
};

pub const RadialGradient = struct {
    center: Vec2,
    radius: f32,
    inner_color: [4]f32,
    outer_color: [4]f32,
    extend: Extend = .clamp,
};

/// A sweep of two colors around `center`, from `start_color` at
/// `start_angle` (radians, +x axis = 0) sweeping counter-clockwise back to
/// `start_color` — `end_color` sits opposite. This is the one gradient the
/// image escape hatch can't serve (an affine UV can't produce `atan2`), and
/// it stays resolution-independent under zoom, so it earns a native slot.
pub const ConicGradient = struct {
    center: Vec2,
    start_angle: f32 = 0,
    start_color: [4]f32,
    end_color: [4]f32,
    /// Defaults to `.repeat` — the natural full sweep (start→end→seam).
    /// `.reflect` gives a seamless mirror (start→end→start, no hard line).
    extend: Extend = .repeat,
};

pub const ImagePaint = struct {
    image: *const Image,
    uv_transform: Transform2D = .identity,
    extend_x: Extend = .clamp,
    extend_y: Extend = .clamp,
    filter: ImageFilter = .linear,
};

pub const Paint = union(enum) {
    solid: [4]f32,
    linear_gradient: LinearGradient,
    radial_gradient: RadialGradient,
    conic_gradient: ConicGradient,
    image: ImagePaint,

    /// Validate every scalar consumed by paint serialization and sampling.
    /// RGB channels may be outside `[0, 1]` (paint records support HDR and
    /// wide-gamut values), while straight alpha must remain in `[0, 1]`.
    pub fn validate(self: Paint) PaintValidationError!void {
        switch (self) {
            .solid => |color| try validateColor(color),
            .linear_gradient => |gradient| {
                try validatePoint(gradient.start);
                try validatePoint(gradient.end);
                try validateColor(gradient.start_color);
                try validateColor(gradient.end_color);
            },
            .radial_gradient => |gradient| {
                try validatePoint(gradient.center);
                if (!std.math.isFinite(gradient.radius) or gradient.radius <= 0) return error.InvalidPaint;
                try validateColor(gradient.inner_color);
                try validateColor(gradient.outer_color);
            },
            .conic_gradient => |gradient| {
                try validatePoint(gradient.center);
                if (!std.math.isFinite(gradient.start_angle)) return error.InvalidPaint;
                try validateColor(gradient.start_color);
                try validateColor(gradient.end_color);
            },
            .image => |image_paint| {
                try validateTransform(image_paint.uv_transform);
                image_paint.image.validate() catch return error.InvalidPaint;
            },
        }
    }
};

pub const PaintValidationError = error{InvalidPaint};
pub const PaintMapError = PaintValidationError || error{
    InvalidTransform,
    UnsupportedTransform,
};

fn validatePoint(point: Vec2) PaintValidationError!void {
    if (!std.math.isFinite(point.x) or !std.math.isFinite(point.y)) return error.InvalidPaint;
}

fn validateColor(color: [4]f32) PaintValidationError!void {
    for (color) |component| {
        if (!std.math.isFinite(component)) return error.InvalidPaint;
    }
    if (color[3] < 0 or color[3] > 1) return error.InvalidPaint;
}

fn validateTransform(transform: Transform2D) PaintValidationError!void {
    const values = [_]f32{ transform.xx, transform.xy, transform.tx, transform.yx, transform.yy, transform.ty };
    for (values) |value| {
        if (!std.math.isFinite(value)) return error.InvalidPaint;
    }
}

const Similarity = struct {
    scale: f32,
    rotation: f32,
    orientation_preserving: bool,
};

/// Return the scale, first-axis angle, and orientation of a similarity.
/// Native radial and conic records cannot represent ellipses, shear, or an
/// orientation-reversing conic sweep, so those transforms are rejected instead
/// of being approximated.
fn similarity(transform: Transform2D) ?Similarity {
    // Match Transform2D.inverse's wide intermediates: f32 squares can
    // overflow/underflow even when the transform and its inverse are both
    // representable.
    const xx: f64 = transform.xx;
    const xy: f64 = transform.xy;
    const yx: f64 = transform.yx;
    const yy: f64 = transform.yy;
    const x_len_sq = xx * xx + yx * yx;
    const y_len_sq = xy * xy + yy * yy;
    const dot = xx * xy + yx * yy;
    const determinant = xx * yy - xy * yx;
    const norm = @max(x_len_sq, y_len_sq);
    if (!std.math.isFinite(norm) or !std.math.isFinite(dot) or
        !std.math.isFinite(determinant) or norm == 0 or determinant == 0) return null;
    const tolerance = norm * (32.0 * @as(f64, std.math.floatEps(f32)));
    if (@abs(x_len_sq - y_len_sq) > tolerance or @abs(dot) > tolerance) return null;
    const scale = @sqrt((x_len_sq + y_len_sq) * 0.5);
    if (!std.math.isFinite(scale) or scale <= 0 or scale > std.math.floatMax(f32)) return null;
    return .{
        .scale = @floatCast(scale),
        .rotation = @floatCast(std.math.atan2(yx, xx)),
        .orientation_preserving = determinant > 0,
    };
}

/// Re-express a paint so it can be sampled in a local coordinate space.
/// `local_to_paint` maps local sample points into the paint's authored space.
/// Radial paints require a similarity; conic paints additionally require it
/// to preserve orientation. Transforms which would turn a circle into an
/// ellipse or reverse a conic sweep return `UnsupportedTransform` rather than
/// silently changing the paint.
pub fn mapToLocal(paint: Paint, local_to_paint: Transform2D) PaintMapError!Paint {
    try paint.validate();
    const mapped: Paint = switch (paint) {
        .solid => paint,
        .linear_gradient => |gradient| blk: {
            const paint_to_local = local_to_paint.inverse() orelse return error.InvalidTransform;
            break :blk .{ .linear_gradient = .{
                .start = paint_to_local.applyPoint(gradient.start),
                .end = paint_to_local.applyPoint(gradient.end),
                .start_color = gradient.start_color,
                .end_color = gradient.end_color,
                .extend = gradient.extend,
            } };
        },
        .radial_gradient => |gradient| blk: {
            const paint_to_local = local_to_paint.inverse() orelse return error.InvalidTransform;
            const sim = similarity(local_to_paint) orelse return error.UnsupportedTransform;
            break :blk .{ .radial_gradient = .{
                .center = paint_to_local.applyPoint(gradient.center),
                .radius = gradient.radius / sim.scale,
                .inner_color = gradient.inner_color,
                .outer_color = gradient.outer_color,
                .extend = gradient.extend,
            } };
        },
        .conic_gradient => |gradient| blk: {
            const paint_to_local = local_to_paint.inverse() orelse return error.InvalidTransform;
            const sim = similarity(local_to_paint) orelse return error.UnsupportedTransform;
            if (!sim.orientation_preserving) return error.UnsupportedTransform;
            break :blk .{ .conic_gradient = .{
                .center = paint_to_local.applyPoint(gradient.center),
                .start_angle = gradient.start_angle - sim.rotation,
                .start_color = gradient.start_color,
                .end_color = gradient.end_color,
                .extend = gradient.extend,
            } };
        },
        .image => |image_paint| .{ .image = .{
            .image = image_paint.image,
            .uv_transform = Transform2D.multiply(image_paint.uv_transform, local_to_paint),
            .extend_x = image_paint.extend_x,
            .extend_y = image_paint.extend_y,
            .filter = image_paint.filter,
        } },
    };
    mapped.validate() catch return error.InvalidTransform;
    return mapped;
}

pub const FillStyle = struct {
    paint: Paint,
    /// Winding rule for this fill. Property of the geometry author's
    /// intent (not the frame's rasterization), so it lives here instead
    /// of on per-frame raster state. Defaults to non-zero, the convention used
    /// by fonts and the majority of user-authored paths.
    fill_rule: FillRule = .non_zero,

    pub fn validate(self: FillStyle) PaintValidationError!void {
        try self.paint.validate();
    }
};

pub const StrokeCap = enum {
    butt,
    square,
    round,
};

pub const StrokeJoin = enum {
    miter,
    bevel,
    round,
};

pub const StrokePlacement = enum {
    center,
    inside,
};

pub const StrokeStyle = struct {
    paint: Paint,
    width: f32,
    cap: StrokeCap = .butt,
    join: StrokeJoin = .miter,
    miter_limit: f32 = 4.0,
    placement: StrokePlacement = .center,

    pub fn validate(self: StrokeStyle) StrokeValidationError!void {
        try self.paint.validate();
        if (!std.math.isFinite(self.width) or self.width < 0 or
            !std.math.isFinite(self.miter_limit) or self.miter_limit < 1) return error.InvalidStroke;
    }
};

pub const StrokeValidationError = PaintValidationError || error{InvalidStroke};

/// How the layers of a multi-layer path atlas entry combine. This is a
/// closed set, not a general blend-mode selector: the single-pass renderer
/// evaluates all layers in one fragment, so Porter-Duff-style destination
/// blend modes (multiply/screen/…) are deliberately out of scope — they
/// would require a separate pass. `.source_over` stacks the layers back to
/// front. `.fill_stroke_inside` is the *only* realization of an inside
/// stroke: it clips a center-stroke layer's coverage to the fill interior
/// at render time (there is no inside-offset stroke geometry path).
pub const CompositeMode = enum {
    source_over,
    fill_stroke_inside,
};

test "mapToLocal shifts a conic start angle by the transform rotation" {
    const paint = Paint{ .conic_gradient = .{
        .center = .{ .x = 0, .y = 0 },
        .start_angle = 0,
        .start_color = .{ 0, 0, 0, 1 },
        .end_color = .{ 1, 1, 1, 1 },
    } };

    // Translate + scale: angle unchanged; center maps by the inverse.
    const ts = Transform2D{ .xx = 2, .yy = 2, .tx = 10, .ty = 20 };
    const mapped_ts = (try mapToLocal(paint, ts)).conic_gradient;
    try std.testing.expectApproxEqAbs(@as(f32, 0), mapped_ts.start_angle, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, -5), mapped_ts.center.x, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, -10), mapped_ts.center.y, 1e-4);

    // 90° rotation shifts the start angle by −π/2.
    const rot = Transform2D.rotate(std.math.pi / 2.0);
    const mapped_rot = (try mapToLocal(paint, rot)).conic_gradient;
    try std.testing.expectApproxEqAbs(-std.math.pi / 2.0, mapped_rot.start_angle, 1e-4);
}

test "Paint validation rejects non-finite and invalid-domain payloads" {
    try std.testing.expectError(error.InvalidPaint, (Paint{ .solid = .{ 0, 0, std.math.nan(f32), 1 } }).validate());
    try std.testing.expectError(error.InvalidPaint, (Paint{ .solid = .{ 2, -1, 0, 1.01 } }).validate());
    try std.testing.expectError(error.InvalidPaint, (Paint{ .radial_gradient = .{
        .center = .zero,
        .radius = 0,
        .inner_color = .{ 0, 0, 0, 1 },
        .outer_color = .{ 1, 1, 1, 1 },
    } }).validate());
    try (Paint{ .solid = .{ 4, -1, 0.5, 1 } }).validate();
}

test "radial and conic mapping reject transforms they cannot represent" {
    const radial = Paint{ .radial_gradient = .{
        .center = .zero,
        .radius = 1,
        .inner_color = .{ 0, 0, 0, 1 },
        .outer_color = .{ 1, 1, 1, 1 },
    } };
    try std.testing.expectError(error.UnsupportedTransform, mapToLocal(radial, Transform2D.scale(2, 1)));
    try std.testing.expectError(error.UnsupportedTransform, mapToLocal(radial, .{ .xx = 1, .xy = 0.25, .yy = 1 }));

    const conic = Paint{ .conic_gradient = .{
        .center = .zero,
        .start_color = .{ 0, 0, 0, 1 },
        .end_color = .{ 1, 1, 1, 1 },
    } };
    const reflected_radial = (try mapToLocal(radial, Transform2D.scale(-2, 2))).radial_gradient;
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), reflected_radial.radius, 1e-6);
    const tiny_radial = (try mapToLocal(radial, Transform2D.scale(1e-20, 1e-20))).radial_gradient;
    try std.testing.expectApproxEqRel(@as(f32, 1e20), tiny_radial.radius, 1e-6);
    const huge_radial = (try mapToLocal(radial, Transform2D.scale(1e20, 1e20))).radial_gradient;
    try std.testing.expectApproxEqRel(@as(f32, 1e-20), huge_radial.radius, 1e-6);
    try std.testing.expectError(error.UnsupportedTransform, mapToLocal(conic, Transform2D.scale(-1, 1)));
}

test "StrokeStyle validates width, miter, and paint" {
    const valid = StrokeStyle{ .paint = .{ .solid = .{ 1, 1, 1, 1 } }, .width = 2 };
    try valid.validate();
    var invalid = valid;
    invalid.width = std.math.nan(f32);
    try std.testing.expectError(error.InvalidStroke, invalid.validate());
    invalid = valid;
    invalid.miter_limit = 0.5;
    try std.testing.expectError(error.InvalidStroke, invalid.validate());
}
