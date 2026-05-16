const std = @import("std");
const snail = @import("../../../root.zig");

const Vec2 = snail.Vec2;
const Transform2D = snail.Transform2D;
const SubpixelOrder = snail.SubpixelOrder;

pub fn sceneToPixelFromMvp(mvp: snail.Mat4, vw: f32, vh: f32) Transform2D {
    const m = mvp.data;

    // Apply mvp to (0, 0, 0, 1), (1, 0, 0, 1), (0, 1, 0, 1) — origin and
    // basis vectors of the glyph-local z = 0 plane.
    const o_clip = [3]f32{ m[12], m[13], m[15] };
    const x_clip = [3]f32{ m[0] + m[12], m[1] + m[13], m[3] + m[15] };
    const y_clip = [3]f32{ m[4] + m[12], m[5] + m[13], m[7] + m[15] };

    // Affine projection of the plane requires constant w across reference
    // points. A perspective MVP would violate this; the CPU rasterizer
    // doesn't yet do per-pixel `1/w`, so refuse rather than produce output
    // that disagrees with the GPU backends.
    const eps_w: f32 = 1e-4;
    if (@abs(o_clip[2] - x_clip[2]) > eps_w or @abs(o_clip[2] - y_clip[2]) > eps_w) {
        std.debug.panic(
            "CpuRenderer: MVP projects the z = 0 plane non-affinely (perspective). w(o)={d}, w(x)={d}, w(y)={d}",
            .{ o_clip[2], x_clip[2], y_clip[2] },
        );
    }
    if (@abs(o_clip[2]) < 1e-6) {
        std.debug.panic("CpuRenderer: degenerate MVP — w == 0", .{});
    }

    const inv_w = 1.0 / o_clip[2];
    const half_w = vw * 0.5;
    const half_h = vh * 0.5;

    // ndc = clip / w, then viewport remap (snail uses y-down screen space, so
    // ndc_y is flipped).
    const o_x = (o_clip[0] * inv_w + 1.0) * half_w;
    const o_y = (1.0 - o_clip[1] * inv_w) * half_h;
    const x_x = (x_clip[0] * inv_w + 1.0) * half_w;
    const x_y = (1.0 - x_clip[1] * inv_w) * half_h;
    const y_x = (y_clip[0] * inv_w + 1.0) * half_w;
    const y_y = (1.0 - y_clip[1] * inv_w) * half_h;

    return .{
        .xx = x_x - o_x,
        .yx = x_y - o_y,
        .xy = y_x - o_x,
        .yy = y_y - o_y,
        .tx = o_x,
        .ty = o_y,
    };
}

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
