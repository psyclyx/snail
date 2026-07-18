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
};

fn averageScale(transform: Transform2D) f32 {
    const sx = @sqrt(transform.xx * transform.xx + transform.yx * transform.yx);
    const sy = @sqrt(transform.xy * transform.xy + transform.yy * transform.yy);
    return @max((sx + sy) * 0.5, 1.0 / 65536.0);
}

/// Re-express a paint so it can be sampled in a local coordinate space.
/// `local_to_paint` maps local sample points into the paint's authored space.
pub fn mapToLocal(paint: Paint, local_to_paint: Transform2D) ?Paint {
    return switch (paint) {
        .solid => paint,
        .linear_gradient => |gradient| blk: {
            const paint_to_local = local_to_paint.inverse() orelse return null;
            break :blk .{ .linear_gradient = .{
                .start = paint_to_local.applyPoint(gradient.start),
                .end = paint_to_local.applyPoint(gradient.end),
                .start_color = gradient.start_color,
                .end_color = gradient.end_color,
                .extend = gradient.extend,
            } };
        },
        .radial_gradient => |gradient| blk: {
            const paint_to_local = local_to_paint.inverse() orelse return null;
            break :blk .{ .radial_gradient = .{
                .center = paint_to_local.applyPoint(gradient.center),
                .radius = gradient.radius / averageScale(local_to_paint),
                .inner_color = gradient.inner_color,
                .outer_color = gradient.outer_color,
                .extend = gradient.extend,
            } };
        },
        .conic_gradient => |gradient| blk: {
            const paint_to_local = local_to_paint.inverse() orelse return null;
            // The sweep angle is measured in the local sample space, so shift
            // the start angle by the transform's rotation. Exact for
            // similarity transforms; non-uniform scale/shear distorts a conic
            // (angles aren't affine) — same approximation radial makes.
            const rotation = std.math.atan2(local_to_paint.yx, local_to_paint.xx);
            break :blk .{ .conic_gradient = .{
                .center = paint_to_local.applyPoint(gradient.center),
                .start_angle = gradient.start_angle - rotation,
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
}

pub const FillStyle = struct {
    paint: Paint,
    /// Winding rule for this fill. Property of the geometry author's
    /// intent (not the frame's rasterization), so it lives here instead
    /// of on per-frame raster state. Defaults to non-zero, the convention used
    /// by fonts and the majority of user-authored paths.
    fill_rule: FillRule = .non_zero,
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
};

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
    const mapped_ts = mapToLocal(paint, ts).?.conic_gradient;
    try std.testing.expectApproxEqAbs(@as(f32, 0), mapped_ts.start_angle, 1e-5);
    try std.testing.expectApproxEqAbs(@as(f32, -5), mapped_ts.center.x, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, -10), mapped_ts.center.y, 1e-4);

    // 90° rotation shifts the start angle by −π/2.
    const rot = Transform2D.rotate(std.math.pi / 2.0);
    const mapped_rot = mapToLocal(paint, rot).?.conic_gradient;
    try std.testing.expectApproxEqAbs(-std.math.pi / 2.0, mapped_rot.start_angle, 1e-4);
}
