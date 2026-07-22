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
const Rect = @import("math.zig").Rect;

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
    if (!std.math.isFinite(logical_size) or logical_size <= 0.0 or pixel_size == 0) return 1.0;
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
    // f32 division can overflow even though snapping the original f32 value
    // is perfectly representable (large value, tiny step). Keep the quotient
    // and reconstruction wide, then decline an unrepresentable result.
    const scaled = @as(f64, value) / @as(f64, step);
    const snapped = switch (rule) {
        .floor => @floor(scaled),
        .nearest => @round(scaled),
        .ceil => @ceil(scaled),
    };
    const result = snapped * @as(f64, step);
    if (!std.math.isFinite(result) or @abs(result) > std.math.floatMax(f32)) return value;
    return @floatCast(result);
}

/// Delta added to `value` by `snapToStep(value, step, rule)`.
pub fn snapDeltaToStep(value: f32, step: f32, rule: Rule) f32 {
    if (!std.math.isFinite(value)) return 0;
    return snapToStep(value, step, rule) - value;
}

/// Snap `value` and clamp the result to at least `min_steps * step`.
/// Useful for stroke widths / row heights where shrinking past a minimum
/// reads as "disappear."
pub fn snapLengthToStep(value: f32, step: f32, rule: Rule, min_steps: f32) f32 {
    const snapped = snapToStep(value, step, rule);
    if (!std.math.isFinite(step) or step <= 0.0) return snapped;
    const valid_min_steps = if (std.math.isFinite(min_steps)) @max(min_steps, 0.0) else 0.0;
    const min_length = @as(f64, valid_min_steps) * @as(f64, step);
    if (!std.math.isFinite(min_length) or min_length > std.math.floatMax(f32)) return snapped;
    return @max(snapped, @as(f32, @floatCast(min_length)));
}

pub fn snapPointToStep(point: Vec2, step: Vec2, rule: Rule) Vec2 {
    return .{
        .x = snapToStep(point.x, step.x, rule),
        .y = snapToStep(point.y, step.y, rule),
    };
}

pub fn snapRectToStep(rect: Rect, step: Vec2, rule: Rule) Rect {
    if (!finite(.{ rect.x, rect.y, rect.w, rect.h, rect.x + rect.w, rect.y + rect.h })) return rect;
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
    if (!finite(.{ point.x, point.y })) return point;
    const inv = world_to_pixel.inverse() orelse return point;
    const screen = world_to_pixel.applyPoint(point);
    if (!finite(.{ screen.x, screen.y })) return point;
    const result = inv.applyPoint(.{ .x = screen.x, .y = @round(screen.y) });
    return if (finite(.{ result.x, result.y })) result else point;
}

/// Round `point` so that both its screen-space X and Y land on integer
/// pixels. Use this for icon glyph origins, axis-aligned strokes, and
/// 1px UI chrome that benefits from full pixel-grid alignment.
pub fn origin(point: Vec2, world_to_pixel: Transform2D) Vec2 {
    if (!finite(.{ point.x, point.y })) return point;
    const inv = world_to_pixel.inverse() orelse return point;
    const screen = world_to_pixel.applyPoint(point);
    if (!finite(.{ screen.x, screen.y })) return point;
    const result = inv.applyPoint(.{ .x = @round(screen.x), .y = @round(screen.y) });
    return if (finite(.{ result.x, result.y })) result else point;
}

/// Snap an axis-aligned rect (`min`, `max`) so its screen-space edges all
/// land on integer pixels. Useful for crisp 1px dividers and strokes.
/// Returns the rect's snapped corners in world coordinates.
pub fn gridRect(min: Vec2, max: Vec2, world_to_pixel: Transform2D) struct { min: Vec2, max: Vec2 } {
    if (!finite(.{ min.x, min.y, max.x, max.y })) return .{ .min = min, .max = max };
    const inv = world_to_pixel.inverse() orelse return .{ .min = min, .max = max };
    const min_screen = world_to_pixel.applyPoint(min);
    const max_screen = world_to_pixel.applyPoint(max);
    if (!finite(.{ min_screen.x, min_screen.y, max_screen.x, max_screen.y })) return .{ .min = min, .max = max };
    const result_min = inv.applyPoint(.{ .x = @round(min_screen.x), .y = @round(min_screen.y) });
    const result_max = inv.applyPoint(.{ .x = @round(max_screen.x), .y = @round(max_screen.y) });
    return if (finite(.{ result_min.x, result_min.y, result_max.x, result_max.y }))
        .{ .min = result_min, .max = result_max }
    else
        .{ .min = min, .max = max };
}

fn finite(values: anytype) bool {
    inline for (values) |value| if (!std.math.isFinite(value)) return false;
    return true;
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

test "snap helpers remain total for extreme and non-finite inputs" {
    try testing.expectEqual(@as(f32, 1), pixelStep(std.math.nan(f32), 100));
    try testing.expectEqual(std.math.floatMax(f32), snapToStep(std.math.floatMax(f32), std.math.floatTrueMin(f32), .nearest));
    try testing.expectEqual(@as(f32, 0), snapDeltaToStep(std.math.inf(f32), 1, .nearest));
    try testing.expectEqual(@as(f32, 4), snapLengthToStep(4, 1, .nearest, std.math.nan(f32)));

    const point = Vec2{ .x = std.math.floatMax(f32), .y = std.math.floatMax(f32) };
    const overflowing = Transform2D{ .xx = 2, .yy = 2 };
    try testing.expectEqual(point, origin(point, overflowing));
    try testing.expectEqual(point, baseline(point, overflowing));
}
