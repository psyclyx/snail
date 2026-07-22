//! Screen-space geometry helpers for the software rasterizer.

const std = @import("std");
const snail = @import("snail");
const render_state = @import("render-state");

const Vec2 = snail.Vec2;
const Transform2D = snail.Transform2D;
const SubpixelOrder = render_state.SubpixelOrder;

pub fn inverseTransform(transform: Transform2D) ?Transform2D {
    // Keep raster acceptance identical to the public transform contract.
    // Transform2D.inverse uses f64 intermediates, so small/large invertible
    // f32 transforms are not misclassified by determinant under/overflow.
    return transform.inverse();
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
    // Match GLSL fwidth: a pixel's square support maps to the L1 norm of each
    // inverse-transform row. A Euclidean row length underfilters rotated and
    // perspective-projected edges by as much as sqrt(2).
    return .{
        .x = @max(@abs(inverse.xx) + @abs(inverse.xy), 1.0 / 65536.0),
        .y = @max(@abs(inverse.yx) + @abs(inverse.yy), 1.0 / 65536.0),
    };
}

test "CPU grayscale footprint matches shader fwidth" {
    const inv = Transform2D{
        .xx = 0.5,
        .xy = 0.5,
        .yx = -0.25,
        .yy = 0.25,
    };
    const epp = glyphEdgePixelsPerPixel(inv);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), epp.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.5), epp.y, 0.0001);
}

test "CPU inverse accepts representable determinant underflow" {
    const tiny = Transform2D{ .xx = 1.0e-20, .yy = 1.0e-20 };
    const inverse = inverseTransform(tiny) orelse return error.TestExpectedInverse;
    try std.testing.expectApproxEqRel(@as(f32, 1.0e20), inverse.xx, 1e-6);
    try std.testing.expectApproxEqRel(@as(f32, 1.0e20), inverse.yy, 1e-6);
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
