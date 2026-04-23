const std = @import("std");
const Transform2D = @import("../math/vec.zig").Transform2D;
const Vec2 = @import("../math/vec.zig").Vec2;

/// Per-vertex sprite data: 3 vec4s = 12 floats per vertex.
pub const FLOATS_PER_VERTEX: usize = 12;
pub const VERTICES_PER_SPRITE: usize = 4;
pub const FLOATS_PER_SPRITE: usize = FLOATS_PER_VERTEX * VERTICES_PER_SPRITE;

pub fn generateSpriteVertices(
    dst: []f32,
    image_view: anytype,
    size: Vec2,
    tint: [4]f32,
    uv_rect: anytype,
    filter: anytype,
    anchor: anytype,
    transform: Transform2D,
) void {
    std.debug.assert(dst.len >= FLOATS_PER_SPRITE);

    const min_x = -anchor.x * size.x;
    const min_y = -anchor.y * size.y;
    const max_x = min_x + size.x;
    const max_y = min_y + size.y;

    const uv0_x = uv_rect.u0 * image_view.uv_scale.x;
    const uv0_y = uv_rect.v0 * image_view.uv_scale.y;
    const uv1_x = uv_rect.u1 * image_view.uv_scale.x;
    const uv1_y = uv_rect.v1 * image_view.uv_scale.y;
    const layer_f: f32 = @floatFromInt(image_view.layer);
    const filter_f: f32 = @floatFromInt(@intFromEnum(filter));

    const corners = [4]struct {
        local: Vec2,
        uv: Vec2,
    }{
        .{ .local = .{ .x = min_x, .y = min_y }, .uv = .{ .x = uv0_x, .y = uv0_y } },
        .{ .local = .{ .x = max_x, .y = min_y }, .uv = .{ .x = uv1_x, .y = uv0_y } },
        .{ .local = .{ .x = max_x, .y = max_y }, .uv = .{ .x = uv1_x, .y = uv1_y } },
        .{ .local = .{ .x = min_x, .y = max_y }, .uv = .{ .x = uv0_x, .y = uv1_y } },
    };

    inline for (corners, 0..) |corner, i| {
        const world = transform.applyPoint(corner.local);
        const base = i * FLOATS_PER_VERTEX;
        dst[base + 0] = world.x;
        dst[base + 1] = world.y;
        dst[base + 2] = corner.uv.x;
        dst[base + 3] = corner.uv.y;
        dst[base + 4] = tint[0];
        dst[base + 5] = tint[1];
        dst[base + 6] = tint[2];
        dst[base + 7] = tint[3];
        dst[base + 8] = layer_f;
        dst[base + 9] = filter_f;
        dst[base + 10] = 0;
        dst[base + 11] = 0;
    }
}

test "sprite vertex packing applies anchor and uv scale" {
    const ImageFilter = enum(u8) { linear = 0, nearest = 1 };
    var buf: [FLOATS_PER_SPRITE]f32 = undefined;
    generateSpriteVertices(
        &buf,
        .{
            .layer = 3,
            .uv_scale = .{ .x = 0.5, .y = 0.25 },
        },
        .{ .x = 20, .y = 10 },
        .{ 1, 0.5, 0.25, 1 },
        .{ .u0 = 0.25, .v0 = 0.5, .u1 = 0.75, .v1 = 1.0 },
        ImageFilter.nearest,
        .{ .x = 0.0, .y = 0.0 },
        .{ .tx = 4, .ty = 6 },
    );

    try std.testing.expectApproxEqAbs(@as(f32, 4), buf[0], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 6), buf[1], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.125), buf[2], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.125), buf[3], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 24), buf[12], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 3), buf[8], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(@intFromEnum(ImageFilter.nearest))), buf[9], 0.001);
}
