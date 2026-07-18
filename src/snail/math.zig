const bezier = @import("math/bezier.zig");
const vec = @import("math/vec.zig");

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

/// Project the z = 0 plane of `mvp` to y-down viewport pixel coordinates.
/// Returns `null` for perspective or degenerate projections.
pub fn mvpToScenePixel(mvp: Mat4, viewport_w: f32, viewport_h: f32) ?Transform2D {
    const m = mvp.data;
    const o_clip = [3]f32{ m[12], m[13], m[15] };
    const x_clip = [3]f32{ m[0] + m[12], m[1] + m[13], m[3] + m[15] };
    const y_clip = [3]f32{ m[4] + m[12], m[5] + m[13], m[7] + m[15] };

    const eps_w: f32 = 1e-4;
    if (@abs(o_clip[2] - x_clip[2]) > eps_w or @abs(o_clip[2] - y_clip[2]) > eps_w) return null;
    if (@abs(o_clip[2]) < 1e-6) return null;

    const inv_w = 1.0 / o_clip[2];
    const half_w = viewport_w * 0.5;
    const half_h = viewport_h * 0.5;
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

const std = @import("std");

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
}
