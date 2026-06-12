//! Pixel-grid snap helpers.
//!
//! Pure functions on `Transform2D`s. Callers compute the desired snap at
//! draw-list build time using the same world→pixel transform the renderer
//! will see (typically `snail.mvpToScenePixel(drawState.mvp, ...)`).
//!
//! Decoupled from Picture/Shape so any caller — Picture-based, custom
//! scene-graph, or direct-emit — can pixel-align text baselines, icon
//! origins, or stroke-rect edges without the library taking an opinion on
//! how the scene is organized.
//!
//! Each helper applies its snap in *screen* pixel space (round through
//! `world_to_pixel`) and returns a value back in world coordinates. The
//! input world_to_pixel is the same transform the renderer derives via
//! `mvpToScenePixel`; degenerate transforms (zero determinant) round-trip
//! the input unchanged.

const std = @import("std");
const math = @import("math/vec.zig");

const Transform2D = math.Transform2D;
const Vec2 = math.Vec2;

/// Round `point` so that its screen-space Y lands on an integer pixel,
/// preserving the screen-space X. Use this for shaped-text run baselines
/// where you want hinted vertical alignment but smooth horizontal kerning.
pub fn baseline(point: Vec2, world_to_pixel: Transform2D) Vec2 {
    const inv = world_to_pixel.inverse() orelse return point;
    const screen = world_to_pixel.applyPoint(point);
    return inv.applyPoint(.{ .x = screen.x, .y = @round(screen.y) });
}

/// Round `point` so that both its screen-space X and Y land on integer
/// pixels. Use this for icon glyph origins, axis-aligned strokes, and
/// 1px UI chrome that benefits from full pixel-grid alignment.
pub fn origin(point: Vec2, world_to_pixel: Transform2D) Vec2 {
    const inv = world_to_pixel.inverse() orelse return point;
    const screen = world_to_pixel.applyPoint(point);
    return inv.applyPoint(.{ .x = @round(screen.x), .y = @round(screen.y) });
}

/// Snap an axis-aligned rect (`min`, `max`) so its screen-space edges all
/// land on integer pixels. Useful for crisp 1px dividers and strokes.
/// Returns the rect's snapped corners in world coordinates.
pub fn gridRect(min: Vec2, max: Vec2, world_to_pixel: Transform2D) struct { min: Vec2, max: Vec2 } {
    const inv = world_to_pixel.inverse() orelse return .{ .min = min, .max = max };
    const min_screen = world_to_pixel.applyPoint(min);
    const max_screen = world_to_pixel.applyPoint(max);
    return .{
        .min = inv.applyPoint(.{ .x = @round(min_screen.x), .y = @round(min_screen.y) }),
        .max = inv.applyPoint(.{ .x = @round(max_screen.x), .y = @round(max_screen.y) }),
    };
}

const testing = std.testing;

test "baseline rounds y, preserves x" {
    // 0.5× scale, fractional translate: world (10, 20) → screen (5.3, 10.7) → snap (5.3, 11)
    // → back to world (9.4 + something, …). Just verify x is preserved screen-side.
    const w2p = Transform2D{ .xx = 0.5, .yy = 0.5, .tx = 0.3, .ty = 0.7 };
    const snapped = baseline(.{ .x = 10, .y = 20 }, w2p);
    const screen = w2p.applyPoint(snapped);
    try testing.expectApproxEqAbs(@as(f32, 5.3), screen.x, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 11.0), screen.y, 1e-4);
}

test "origin rounds both axes" {
    const w2p = Transform2D{ .xx = 1.0, .yy = 1.0, .tx = 0.3, .ty = 0.7 };
    const snapped = origin(.{ .x = 10.4, .y = 20.6 }, w2p);
    const screen = w2p.applyPoint(snapped);
    try testing.expectApproxEqAbs(@as(f32, 11.0), screen.x, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 21.0), screen.y, 1e-4);
}

test "degenerate transform passes input through" {
    const zero = Transform2D{ .xx = 0, .yy = 0 };
    const p = Vec2{ .x = 1.25, .y = 2.5 };
    try testing.expectEqual(p, baseline(p, zero));
    try testing.expectEqual(p, origin(p, zero));
}

test "gridRect snaps both corners" {
    const w2p = Transform2D{ .xx = 1.0, .yy = 1.0, .tx = 0.3, .ty = 0.7 };
    const r = gridRect(.{ .x = 0.4, .y = 0.4 }, .{ .x = 10.4, .y = 10.4 }, w2p);
    const min_s = w2p.applyPoint(r.min);
    const max_s = w2p.applyPoint(r.max);
    try testing.expectApproxEqAbs(@as(f32, 1.0), min_s.x, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 1.0), min_s.y, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 11.0), max_s.x, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 11.0), max_s.y, 1e-4);
}
