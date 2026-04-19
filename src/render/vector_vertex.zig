const std = @import("std");

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

pub const FLOATS_PER_VERTEX = 18;
pub const VERTICES_PER_PRIMITIVE = 6;
pub const FLOATS_PER_PRIMITIVE = FLOATS_PER_VERTEX * VERTICES_PER_PRIMITIVE;

const unit_quad = [_][2]f32{
    .{ 0, 0 },
    .{ 1, 0 },
    .{ 1, 1 },
    .{ 0, 0 },
    .{ 1, 1 },
    .{ 0, 1 },
};

pub fn generatePrimitiveVertices(
    dst: []f32,
    kind: PrimitiveKind,
    rect: Rect,
    fill: [4]f32,
    border: [4]f32,
    border_width: f32,
    corner_radius: f32,
) void {
    std.debug.assert(dst.len >= FLOATS_PER_PRIMITIVE);

    const clamped_radius = @max(corner_radius, 0);
    const clamped_border = @max(border_width, 0);
    const kind_f: f32 = @floatFromInt(@intFromEnum(kind));

    for (unit_quad, 0..) |uv, i| {
        const base = i * FLOATS_PER_VERTEX;
        dst[base + 0] = uv[0];
        dst[base + 1] = uv[1];
        dst[base + 2] = rect.x;
        dst[base + 3] = rect.y;
        dst[base + 4] = rect.w;
        dst[base + 5] = rect.h;
        dst[base + 6] = fill[0];
        dst[base + 7] = fill[1];
        dst[base + 8] = fill[2];
        dst[base + 9] = fill[3];
        dst[base + 10] = border[0];
        dst[base + 11] = border[1];
        dst[base + 12] = border[2];
        dst[base + 13] = border[3];
        dst[base + 14] = kind_f;
        dst[base + 15] = clamped_radius;
        dst[base + 16] = clamped_border;
        dst[base + 17] = 0;
    }
}

pub fn generateRectVertices(
    dst: []f32,
    rect: Rect,
    fill: [4]f32,
    border: [4]f32,
    border_width: f32,
) void {
    generatePrimitiveVertices(dst, .rect, rect, fill, border, border_width, 0);
}

pub fn generateRoundedRectVertices(
    dst: []f32,
    rect: Rect,
    fill: [4]f32,
    border: [4]f32,
    border_width: f32,
    corner_radius: f32,
) void {
    generatePrimitiveVertices(dst, .rounded_rect, rect, fill, border, border_width, corner_radius);
}

pub fn generateEllipseVertices(
    dst: []f32,
    rect: Rect,
    fill: [4]f32,
    border: [4]f32,
    border_width: f32,
) void {
    generatePrimitiveVertices(dst, .ellipse, rect, fill, border, border_width, 0);
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

    try std.testing.expectApproxEqAbs(@as(f32, 12), buf[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24), buf[3], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 1), buf[14], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), buf[15], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), buf[16], 0.001);
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

    try std.testing.expectApproxEqAbs(@as(f32, 5), buf[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 7), buf[3], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2), buf[14], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 2), buf[16], 0.001);
}
