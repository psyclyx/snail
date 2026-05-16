const std = @import("std");
const snail = @import("../../../../root.zig");
const color = @import("../color.zig");

const SubpixelOrder = snail.SubpixelOrder;
const Vec2 = snail.Vec2;
const clamp01 = color.clamp01;

pub const SubpixelCoverage = struct {
    rgb: [3]f32,
    alpha: f32,
};

fn edgePixelsToPixelsPerEm(edge_pixels: Vec2) Vec2 {
    return .{
        .x = 1.0 / @max(edge_pixels.x, 1.0 / 65536.0),
        .y = 1.0 / @max(edge_pixels.y, 1.0 / 65536.0),
    };
}

fn subpixelCoveragePixelsPerEm(sample_dx: Vec2, sample_dy: Vec2, subpixel_order: SubpixelOrder) Vec2 {
    const dx = Vec2.new(@abs(sample_dx.x), @abs(sample_dx.y));
    const dy = Vec2.new(@abs(sample_dy.x), @abs(sample_dy.y));
    const edge_pixels = switch (subpixel_order) {
        .rgb, .bgr => Vec2.new(dx.x * (1.0 / 3.0) + dy.x, dx.y * (1.0 / 3.0) + dy.y),
        .vrgb, .vbgr => Vec2.new(dx.x + dy.x * (1.0 / 3.0), dx.y + dy.y * (1.0 / 3.0)),
        .none => Vec2.new(dx.x + dy.x, dx.y + dy.y),
    };
    return edgePixelsToPixelsPerEm(edge_pixels);
}

pub const SubpixelCoveragePlan = struct {
    order: SubpixelOrder,
    ppe: Vec2,
    step: Vec2,
    reverse_order: bool,

    pub fn init(sample_dx: Vec2, sample_dy: Vec2, order: SubpixelOrder) SubpixelCoveragePlan {
        return .{
            .order = order,
            .ppe = subpixelCoveragePixelsPerEm(sample_dx, sample_dy, order),
            .step = Vec2.scale(switch (order) {
                .rgb, .bgr => sample_dx,
                .vrgb, .vbgr => sample_dy,
                .none => Vec2.zero,
            }, 1.0 / 3.0),
            .reverse_order = order == .bgr or order == .vbgr,
        };
    }
};

pub fn filterCoverage(s_m3: f32, s_m2: f32, s_m1: f32, s_0: f32, s_p1: f32, s_p2: f32, s_p3: f32, reverse_order: bool) SubpixelCoverage {
    const w0 = 8.0 / 256.0;
    const w1 = 77.0 / 256.0;
    const w2 = 86.0 / 256.0;
    const left = w0 * s_m3 + w1 * s_m2 + w2 * s_m1 + w1 * s_0 + w0 * s_p1;
    const center = w0 * s_m2 + w1 * s_m1 + w2 * s_0 + w1 * s_p1 + w0 * s_p2;
    const right = w0 * s_m1 + w1 * s_0 + w2 * s_p1 + w1 * s_p2 + w0 * s_p3;
    const rgb = if (reverse_order)
        [3]f32{ clamp01(right), clamp01(center), clamp01(left) }
    else
        [3]f32{ clamp01(left), clamp01(center), clamp01(right) };
    return .{
        .rgb = rgb,
        .alpha = clamp01((rgb[0] + rgb[1] + rgb[2]) * (1.0 / 3.0)),
    };
}

pub fn premultiplySubpixelCoverage(color_value: [4]f32, cov: [3]f32, alpha_cov: f32) [4]f32 {
    return .{
        color_value[0] * color_value[3] * cov[0],
        color_value[1] * color_value[3] * cov[1],
        color_value[2] * color_value[3] * cov[2],
        color_value[3] * alpha_cov,
    };
}

pub fn subpixelBlendCoverage(color_value: [4]f32, cov: [3]f32) [3]f32 {
    return .{
        color_value[3] * cov[0],
        color_value[3] * cov[1],
        color_value[3] * cov[2],
    };
}

pub fn compositeSubpixelOver(src: [4]f32, src_blend: [3]f32, dst_color: *[4]f32, dst_blend: *[3]f32) void {
    dst_color.* = .{
        src[0] + dst_color.*[0] * (1.0 - src_blend[0]),
        src[1] + dst_color.*[1] * (1.0 - src_blend[1]),
        src[2] + dst_color.*[2] * (1.0 - src_blend[2]),
        src[3] + dst_color.*[3] * (1.0 - src[3]),
    };
    dst_blend.* = .{
        src_blend[0] + dst_blend.*[0] * (1.0 - src_blend[0]),
        src_blend[1] + dst_blend.*[1] * (1.0 - src_blend[1]),
        src_blend[2] + dst_blend.*[2] * (1.0 - src_blend[2]),
    };
}

test "subpixel coverage narrows the analytic footprint on the subpixel axis" {
    const sample_dx = Vec2.new(1.0 / 20.0, 0.0);
    const sample_dy = Vec2.new(0.0, 1.0 / 24.0);

    const rgb = subpixelCoveragePixelsPerEm(sample_dx, sample_dy, .rgb);
    try std.testing.expectApproxEqAbs(@as(f32, 60.0), rgb.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), rgb.y, 0.0001);

    const bgr = subpixelCoveragePixelsPerEm(sample_dx, sample_dy, .bgr);
    try std.testing.expectApproxEqAbs(@as(f32, 60.0), bgr.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), bgr.y, 0.0001);

    const vrgb = subpixelCoveragePixelsPerEm(sample_dx, sample_dy, .vrgb);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), vrgb.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 72.0), vrgb.y, 0.0001);

    const none = subpixelCoveragePixelsPerEm(sample_dx, sample_dy, .none);
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), none.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), none.y, 0.0001);
}

test "subpixel coverage footprint is screen-space under shear" {
    const sample_dx = Vec2.new(1.0 / 20.0, 0.0);
    const sample_dy = Vec2.new(0.01, 1.0 / 24.0);

    const rgb = subpixelCoveragePixelsPerEm(sample_dx, sample_dy, .rgb);
    try std.testing.expectApproxEqAbs(@as(f32, 37.5), rgb.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), rgb.y, 0.0001);

    const vrgb = subpixelCoveragePixelsPerEm(sample_dx, sample_dy, .vrgb);
    try std.testing.expectApproxEqAbs(@as(f32, 18.75), vrgb.x, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 72.0), vrgb.y, 0.0001);
}
