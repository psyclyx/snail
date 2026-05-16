const image_mod = @import("image.zig");
const vec = @import("math/vec.zig");

const Image = image_mod.Image;
const Transform2D = vec.Transform2D;
const Vec2 = vec.Vec2;

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

pub const ImagePaint = struct {
    image: *const Image,
    uv_transform: Transform2D = .identity,
    tint: [4]f32 = .{ 1, 1, 1, 1 },
    extend_x: Extend = .clamp,
    extend_y: Extend = .clamp,
    filter: ImageFilter = .linear,
};

pub const Paint = union(enum) {
    solid: [4]f32,
    linear_gradient: LinearGradient,
    radial_gradient: RadialGradient,
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
        .image => |image_paint| .{ .image = .{
            .image = image_paint.image,
            .uv_transform = Transform2D.multiply(image_paint.uv_transform, local_to_paint),
            .tint = image_paint.tint,
            .extend_x = image_paint.extend_x,
            .extend_y = image_paint.extend_y,
            .filter = image_paint.filter,
        } },
    };
}

pub const FillStyle = struct {
    paint: Paint,
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
