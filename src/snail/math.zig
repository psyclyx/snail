const bezier = @import("math/bezier.zig");
const vec = @import("math/vec.zig");
const std = @import("std");

pub const Mat4 = vec.Mat4;
pub const Vec2 = vec.Vec2;
pub const BBox = bezier.BBox;
pub const Transform2D = vec.Transform2D;

pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

/// Project the z = 0 plane of `mvp` to viewport pixel coordinates with a
/// TOP-LEFT origin (the `1 - ndc.y` flip below). This is the framebuffer
/// texel convention, not a scene-axis choice — the scene's y direction
/// comes from the caller's projection matrix (see `RunPlacement.y_axis`).
/// A host addressing its framebuffer bottom-up should flip the returned
/// transform's y row itself.
/// Returns `null` for perspective or degenerate projections.
pub fn mvpToScenePixel(mvp: Mat4, viewport_w: f32, viewport_h: f32) ?Transform2D {
    const m = mvp.data;
    if (!std.math.isFinite(viewport_w) or
        !std.math.isFinite(viewport_h) or
        viewport_w <= 0 or viewport_h <= 0)
    {
        return null;
    }
    for (m) |value| {
        if (!std.math.isFinite(value)) return null;
    }
    const o_clip = [3]f32{ m[12], m[13], m[15] };
    const x_clip = [3]f32{ m[0] + m[12], m[1] + m[13], m[3] + m[15] };
    const y_clip = [3]f32{ m[4] + m[12], m[5] + m[13], m[7] + m[15] };

    // Any x/y-dependent clip W is perspective on the z=0 plane. Do not
    // silently approximate a weak perspective transform as affine.
    if (m[3] != 0 or m[7] != 0 or o_clip[2] == 0) return null;

    const inv_w = 1.0 / o_clip[2];
    const half_w = viewport_w * 0.5;
    const half_h = viewport_h * 0.5;
    const o_x = (o_clip[0] * inv_w + 1.0) * half_w;
    const o_y = (1.0 - o_clip[1] * inv_w) * half_h;
    const x_x = (x_clip[0] * inv_w + 1.0) * half_w;
    const x_y = (1.0 - x_clip[1] * inv_w) * half_h;
    const y_x = (y_clip[0] * inv_w + 1.0) * half_w;
    const y_y = (1.0 - y_clip[1] * inv_w) * half_h;

    const result = Transform2D{
        .xx = x_x - o_x,
        .yx = x_y - o_y,
        .xy = y_x - o_x,
        .yy = y_y - o_y,
        .tx = o_x,
        .ty = o_y,
    };
    // This also rejects arithmetic overflow and singular scene projections.
    return if (result.inverse() != null) result else null;
}

test "mvpToScenePixel composes affine transforms" {
    const projection = Mat4.ortho(0, 100, 50, 0, -1, 1);
    const scene = Mat4.multiply(Mat4.translate(10, -5, 0), Mat4.scaleUniform(0.5));
    const t = mvpToScenePixel(Mat4.multiply(projection, scene), 200, 100) orelse return error.TestExpectedTransform;
    const origin = t.applyPoint(.{ .x = 0, .y = 0 });
    try std.testing.expectApproxEqAbs(@as(f32, 20), origin.x, 1e-4);
    try std.testing.expectApproxEqAbs(@as(f32, -10), origin.y, 1e-4);
}

test "mvpToScenePixel rejects perspective" {
    const persp = Mat4.perspective(std.math.pi * 0.5, 1.0, 0.1, 100);
    try std.testing.expectEqual(@as(?Transform2D, null), mvpToScenePixel(persp, 100, 100));

    var weak = Mat4.identity;
    weak.data[3] = 1.0e-7;
    try std.testing.expectEqual(@as(?Transform2D, null), mvpToScenePixel(weak, 100, 100));
}

test "mvpToScenePixel rejects invalid matrices and viewports" {
    try std.testing.expectEqual(@as(?Transform2D, null), mvpToScenePixel(.identity, 0, 100));
    try std.testing.expectEqual(@as(?Transform2D, null), mvpToScenePixel(.identity, -1, 100));
    try std.testing.expectEqual(@as(?Transform2D, null), mvpToScenePixel(.identity, std.math.nan(f32), 100));

    var invalid = Mat4.identity;
    invalid.data[0] = std.math.inf(f32);
    try std.testing.expectEqual(@as(?Transform2D, null), mvpToScenePixel(invalid, 100, 100));

    var singular = Mat4.identity;
    singular.data[0] = 0;
    try std.testing.expectEqual(@as(?Transform2D, null), mvpToScenePixel(singular, 100, 100));
}
