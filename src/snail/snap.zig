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
const Rect = @import("target.zig").Rect;

/// Rounding rule for scalar pixel-grid snaps. Used by `snapToStep`.
pub const Rule = enum {
    floor,
    nearest,
    ceil,
};

/// Logical-units per pixel along one axis: `logical_size / pixel_size`.
/// Returns 1.0 if either input is zero, so callers can plumb this
/// through degenerate frames without branching.
pub fn pixelStep(logical_size: f32, pixel_size: u32) f32 {
    if (logical_size <= 0.0 or pixel_size == 0) return 1.0;
    return logical_size / @as(f32, @floatFromInt(pixel_size));
}

/// Per-axis `pixelStep` over a 2-vector of logical/pixel dims.
pub fn pixelSteps(logical_size: [2]f32, pixel_size: [2]u32) Vec2 {
    return .{
        .x = pixelStep(logical_size[0], pixel_size[0]),
        .y = pixelStep(logical_size[1], pixel_size[1]),
    };
}

/// Snap `value` to the nearest multiple of `step` under `rule`. NaN /
/// infinite / non-positive `step` round-trips `value` unchanged.
pub fn snapToStep(value: f32, step: f32, rule: Rule) f32 {
    if (!std.math.isFinite(value) or !std.math.isFinite(step) or step <= 0.0) return value;
    const scaled = value / step;
    const snapped = switch (rule) {
        .floor => @floor(scaled),
        .nearest => @round(scaled),
        .ceil => @ceil(scaled),
    };
    return snapped * step;
}

/// Delta added to `value` by `snapToStep(value, step, rule)`.
pub fn snapDeltaToStep(value: f32, step: f32, rule: Rule) f32 {
    return snapToStep(value, step, rule) - value;
}

/// Snap `value` and clamp the result to at least `min_steps * step`.
/// Useful for stroke widths / row heights where shrinking past a minimum
/// reads as "disappear."
pub fn snapLengthToStep(value: f32, step: f32, rule: Rule, min_steps: f32) f32 {
    const snapped = snapToStep(value, step, rule);
    if (!std.math.isFinite(step) or step <= 0.0) return snapped;
    return @max(snapped, @max(min_steps, 0.0) * step);
}

pub fn snapPointToStep(point: Vec2, step: Vec2, rule: Rule) Vec2 {
    return .{
        .x = snapToStep(point.x, step.x, rule),
        .y = snapToStep(point.y, step.y, rule),
    };
}

pub fn snapRectToStep(rect: Rect, step: Vec2, rule: Rule) Rect {
    const min = snapPointToStep(.{ .x = rect.x, .y = rect.y }, step, rule);
    const max = snapPointToStep(.{ .x = rect.x + rect.w, .y = rect.y + rect.h }, step, rule);
    return .{
        .x = min.x,
        .y = min.y,
        .w = @max(max.x - min.x, 0.0),
        .h = @max(max.y - min.y, 0.0),
    };
}

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
