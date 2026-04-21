const std = @import("std");
const Transform2D = @import("../math/vec.zig").Transform2D;

pub const Rect = struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

pub const PrimitiveKind = enum(u32) {
    rect = 0,
    rounded_rect = 1,
    ellipse = 2,
};

/// Packed instance record consumed by the vector pipelines.
/// One primitive = one record; the GPU expands it into a quad internally.
pub const FLOATS_PER_VERTEX = 24;
pub const VERTICES_PER_PRIMITIVE = 1;
pub const FLOATS_PER_PRIMITIVE = 24;

fn writePrimitiveVertices(
    dst: []f32,
    kind: PrimitiveKind,
    rect: Rect,
    fill: [4]f32,
    border: [4]f32,
    border_width: f32,
    corner_radius: f32,
    transform: Transform2D,
) void {
    std.debug.assert(dst.len >= FLOATS_PER_PRIMITIVE);

    const clamped_radius = @max(corner_radius, 0);
    const clamped_border = @max(border_width, 0);
    const kind_f: f32 = @floatFromInt(@intFromEnum(kind));
    const expand: f32 = 1.0;
    dst[0] = rect.x;
    dst[1] = rect.y;
    dst[2] = rect.w;
    dst[3] = rect.h;
    dst[4] = fill[0];
    dst[5] = fill[1];
    dst[6] = fill[2];
    dst[7] = fill[3];
    dst[8] = border[0];
    dst[9] = border[1];
    dst[10] = border[2];
    dst[11] = border[3];
    dst[12] = kind_f;
    dst[13] = clamped_radius;
    dst[14] = clamped_border;
    dst[15] = expand;
    dst[16] = transform.xx;
    dst[17] = transform.xy;
    dst[18] = transform.tx;
    dst[19] = 0;
    dst[20] = transform.yx;
    dst[21] = transform.yy;
    dst[22] = transform.ty;
    dst[23] = 0;
}

pub fn generateRectVertices(
    dst: []f32,
    rect: Rect,
    fill: [4]f32,
    border: [4]f32,
    border_width: f32,
) void {
    writePrimitiveVertices(dst, .rect, rect, fill, border, border_width, 0, .identity);
}

pub fn generateRectVerticesTransformed(
    dst: []f32,
    rect: Rect,
    fill: [4]f32,
    border: [4]f32,
    border_width: f32,
    transform: Transform2D,
) void {
    writePrimitiveVertices(dst, .rect, rect, fill, border, border_width, 0, transform);
}

pub fn generateRoundedRectVertices(
    dst: []f32,
    rect: Rect,
    fill: [4]f32,
    border: [4]f32,
    border_width: f32,
    corner_radius: f32,
) void {
    writePrimitiveVertices(dst, .rounded_rect, rect, fill, border, border_width, corner_radius, .identity);
}

pub fn generateRoundedRectVerticesTransformed(
    dst: []f32,
    rect: Rect,
    fill: [4]f32,
    border: [4]f32,
    border_width: f32,
    corner_radius: f32,
    transform: Transform2D,
) void {
    writePrimitiveVertices(dst, .rounded_rect, rect, fill, border, border_width, corner_radius, transform);
}

pub fn generateEllipseVertices(
    dst: []f32,
    rect: Rect,
    fill: [4]f32,
    border: [4]f32,
    border_width: f32,
) void {
    writePrimitiveVertices(dst, .ellipse, rect, fill, border, border_width, 0, .identity);
}

pub fn generateEllipseVerticesTransformed(
    dst: []f32,
    rect: Rect,
    fill: [4]f32,
    border: [4]f32,
    border_width: f32,
    transform: Transform2D,
) void {
    writePrimitiveVertices(dst, .ellipse, rect, fill, border, border_width, 0, transform);
}

test "rounded rect vertex packing clamps negative params" {
    var buf: [FLOATS_PER_PRIMITIVE]f32 = undefined;
    generateRoundedRectVertices(
        &buf,
        .{ .x = 12, .y = 24, .w = 48, .h = 32 },
        .{ 1, 0.5, 0.25, 1 },
        .{ 0, 0, 0, 1 },
        -3,
        -8,
    );

    try std.testing.expectApproxEqAbs(@as(f32, 12), buf[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24), buf[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), buf[12], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), buf[13], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), buf[14], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), buf[15], 0.001);
}

test "ellipse vertex packing stores primitive kind" {
    var buf: [FLOATS_PER_PRIMITIVE]f32 = undefined;
    generateEllipseVertices(
        &buf,
        .{ .x = 5, .y = 7, .w = 20, .h = 14 },
        .{ 0.2, 0.4, 0.6, 1 },
        .{ 1, 1, 1, 1 },
        2,
    );

    try std.testing.expectApproxEqAbs(@as(f32, 5), buf[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 7), buf[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2), buf[12], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2), buf[14], 0.001);
}

test "transformed primitive stores affine rows" {
    var buf: [FLOATS_PER_PRIMITIVE]f32 = undefined;
    generateRectVerticesTransformed(
        &buf,
        .{ .x = 1, .y = 2, .w = 3, .h = 4 },
        .{ 1, 1, 1, 1 },
        .{ 0, 0, 0, 0 },
        0,
        .{ .xx = 2, .xy = 3, .tx = 4, .yx = 5, .yy = 6, .ty = 7 },
    );

    try std.testing.expectApproxEqAbs(@as(f32, 2), buf[16], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 3), buf[17], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 4), buf[18], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 5), buf[20], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 6), buf[21], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 7), buf[22], 0.001);
}
