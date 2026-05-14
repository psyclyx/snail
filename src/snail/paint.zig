const snail = @import("root.zig");

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
    start: snail.Vec2,
    end: snail.Vec2,
    start_color: [4]f32,
    end_color: [4]f32,
    extend: Extend = .clamp,
};

pub const RadialGradient = struct {
    center: snail.Vec2,
    radius: f32,
    inner_color: [4]f32,
    outer_color: [4]f32,
    extend: Extend = .clamp,
};

pub const ImagePaint = struct {
    image: *const snail.Image,
    uv_transform: snail.Transform2D = .identity,
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
