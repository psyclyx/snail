const std = @import("std");
const snail = @import("../../../core.zig");

const Vec2 = snail.Vec2;
const Transform2D = snail.Transform2D;
const SubpixelOrder = snail.SubpixelOrder;

pub fn inverseTransform(transform: Transform2D) ?Transform2D {
    const det = transform.xx * transform.yy - transform.xy * transform.yx;
    if (@abs(det) < 1.0 / 65536.0) return null;
    const inv_det = 1.0 / det;
    return .{
        .xx = transform.yy * inv_det,
        .xy = -transform.xy * inv_det,
        .tx = (transform.xy * transform.ty - transform.yy * transform.tx) * inv_det,
        .yx = -transform.yx * inv_det,
        .yy = transform.xx * inv_det,
        .ty = (transform.yx * transform.tx - transform.xx * transform.ty) * inv_det,
    };
}

pub const ScreenBounds = struct {
    min: Vec2,
    max: Vec2,
};

pub fn transformedGlyphBounds(bbox: snail.BBox, transform: Transform2D) ScreenBounds {
    const corners = [_]Vec2{
        transform.applyPoint(bbox.min),
        transform.applyPoint(.{ .x = bbox.max.x, .y = bbox.min.y }),
        transform.applyPoint(bbox.max),
        transform.applyPoint(.{ .x = bbox.min.x, .y = bbox.max.y }),
    };

    var min = corners[0];
    var max = corners[0];
    for (corners[1..]) |corner| {
        min.x = @min(min.x, corner.x);
        min.y = @min(min.y, corner.y);
        max.x = @max(max.x, corner.x);
        max.y = @max(max.y, corner.y);
    }
    return .{ .min = min, .max = max };
}

pub fn subpixelSupportExtra(order: SubpixelOrder) Vec2 {
    const extra = 2.0 / 3.0;
    return switch (order) {
        .rgb, .bgr => .{ .x = extra, .y = 0.0 },
        .vrgb, .vbgr => .{ .x = 0.0, .y = extra },
        .none => .{ .x = 0.0, .y = 0.0 },
    };
}

pub fn expandBoundsForSubpixel(bounds: *ScreenBounds, order: SubpixelOrder, allow_subpixel: bool) void {
    if (!allow_subpixel) return;
    const extra = subpixelSupportExtra(order);
    bounds.min.x -= extra.x;
    bounds.min.y -= extra.y;
    bounds.max.x += extra.x;
    bounds.max.y += extra.y;
}

pub fn expandBoundsForCoverageSupport(bounds: *ScreenBounds, order: SubpixelOrder, allow_subpixel: bool) void {
    // floor(min) / ceil(max) already includes pixel centers up to the
    // half-pixel analytic coverage fringe. Only LCD sampling needs more span.
    expandBoundsForSubpixel(bounds, order, allow_subpixel);
}

pub fn glyphEdgePixelsPerPixel(inverse: Transform2D) Vec2 {
    return .{
        .x = @max(@sqrt(inverse.xx * inverse.xx + inverse.xy * inverse.xy), 1.0 / 65536.0),
        .y = @max(@sqrt(inverse.yx * inverse.yx + inverse.yy * inverse.yy), 1.0 / 65536.0),
    };
}

test "CPU grayscale footprint matches shader derivative length" {
    const inv = Transform2D{
        .xx = 0.5,
        .xy = 0.5,
        .yx = -0.25,
        .yy = 0.25,
    };
    const epp = glyphEdgePixelsPerPixel(inv);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f32, 0.5)), epp.x, 0.0001);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f32, 0.125)), epp.y, 0.0001);
}

pub inline fn advanceLocalPixel(col: *u32, local: *Vec2, sample_dx: Vec2) void {
    col.* += 1;
    local.x += sample_dx.x;
    local.y += sample_dx.y;
}

test "cpu subpixel bounds expand only along physical subpixel axis" {
    var rgb_bounds = ScreenBounds{
        .min = Vec2.new(10.0, 20.0),
        .max = Vec2.new(30.0, 40.0),
    };
    expandBoundsForSubpixel(&rgb_bounds, .rgb, true);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0 - 2.0 / 3.0), rgb_bounds.min.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0 + 2.0 / 3.0), rgb_bounds.max.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), rgb_bounds.min.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 40.0), rgb_bounds.max.y, 0.0001);

    var vertical_bounds = ScreenBounds{
        .min = Vec2.new(10.0, 20.0),
        .max = Vec2.new(30.0, 40.0),
    };
    expandBoundsForSubpixel(&vertical_bounds, .vrgb, true);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), vertical_bounds.min.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 30.0), vertical_bounds.max.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0 - 2.0 / 3.0), vertical_bounds.min.y, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 40.0 + 2.0 / 3.0), vertical_bounds.max.y, 0.0001);
}
