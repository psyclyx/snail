//! Reusable primitive-path conveniences for the demos.
//!
//! `Path.prepare` already normalizes arbitrary source coordinates into the
//! renderer's precision-safe `[-1,1]` design space. These unit builders are
//! therefore only scene-authoring and record-reuse conveniences; callers do
//! not need them for numerical correctness.

const std = @import("std");
const snail = @import("snail");

const Allocator = std.mem.Allocator;
const Path = snail.Path;
const Rect = snail.Rect;
const Transform2D = snail.Transform2D;

/// Transform mapping the unit design frame `[0,1]²` onto a world-space
/// rectangle. Compose it with a scene/world transform to place a
/// unit-authored shape. A non-square `rect` scales the unit circle into an
/// ellipse (fills are exact; strokes shear, so keep square rects for
/// uniform stroke width — the glyph-uniform-scale rule).
pub fn placeRect(rect: Rect) Transform2D {
    return .{ .xx = rect.w, .yy = rect.h, .tx = rect.x, .ty = rect.y };
}

/// Uniform placement: scales both axes by `rect.w` and translates to
/// `rect.{x,y}`. Unlike `placeRect` (independent per-axis scale), this keeps
/// circular corners circular, so it is the right choice for rounded rects or
/// any shape with a corner radius on a non-square rect. Pair it with a unit
/// path authored at the rect's aspect (see `unitRoundedRectPathFor`).
pub fn placeRectUniform(rect: Rect) Transform2D {
    return .{ .xx = rect.w, .yy = rect.w, .tx = rect.x, .ty = rect.y };
}

/// A unit circle inscribed in `[0,1]²`. Every ellipse in a scene can reuse
/// this single record, placed with a different `placeRect`.
pub fn unitEllipsePath(allocator: Allocator) !Path {
    var p = Path.init(allocator);
    errdefer p.deinit();
    try p.addEllipse(.{ .x = 0, .y = 0, .w = 1, .h = 1 });
    return p;
}

/// A unit square filling `[0,1]²`.
pub fn unitRectPath(allocator: Allocator) !Path {
    var p = Path.init(allocator);
    errdefer p.deinit();
    try p.addRect(.{ .x = 0, .y = 0, .w = 1, .h = 1 });
    return p;
}

/// A unit rounded square in `[0,1]²` with corner radius `r_rel` expressed as
/// a fraction of the frame (so `0.1` ⇒ 10% corners). The radius scales with
/// the shape, mirroring how glyph stems scale with the em.
pub fn unitRoundedRectPath(allocator: Allocator, r_rel: f32) !Path {
    var p = Path.init(allocator);
    errdefer p.deinit();
    try p.addRoundedRect(.{ .x = 0, .y = 0, .w = 1, .h = 1 }, r_rel);
    return p;
}

/// A rounded rect authored at `rect`'s aspect ratio: width 1, height
/// `rect.h/rect.w`, corner radius `radius/rect.w` — so under uniform
/// placement (`placeRectUniform(rect)`) it fills `rect` with circular
/// corners. Use for non-square rounded rects (cards, panels) where
/// `unitRoundedRectPath` + `placeRect` would shear the corners.
pub fn unitRoundedRectPathFor(allocator: Allocator, rect: Rect, radius: f32) !Path {
    const w = if (rect.w != 0) rect.w else 1;
    var p = Path.init(allocator);
    errdefer p.deinit();
    try p.addRoundedRect(.{ .x = 0, .y = 0, .w = 1, .h = rect.h / w }, radius / w);
    return p;
}

/// Rescale an absolute (screen-space) stroke width into the unit frame used
/// by `placeRectUniform(rect)`.
pub fn unitStrokeWidth(rect: Rect, width: f32) f32 {
    return if (rect.w != 0) width / rect.w else width;
}

// ── tests ────────────────────────────────────────────────────────────────

const testing = std.testing;

test "placeRect maps the unit frame onto a world rectangle" {
    const t = placeRect(.{ .x = 600, .y = 400, .w = 100, .h = 50 });
    const p = t.applyPoint(.{ .x = 1, .y = 1 });
    try testing.expectApproxEqAbs(@as(f32, 700), p.x, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 450), p.y, 1e-4);
    const o = t.applyPoint(.{ .x = 0, .y = 0 });
    try testing.expectApproxEqAbs(@as(f32, 600), o.x, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 400), o.y, 1e-4);
}

test "placeRectUniform keeps a non-square rounded rect's corners circular" {
    // A 200×100 card: authored at aspect (height 0.5) and placed uniformly,
    // the unit corner radius maps to the same world radius on both axes.
    const rect = Rect{ .x = 900, .y = 300, .w = 200, .h = 100 };
    var p = try unitRoundedRectPathFor(testing.allocator, rect, 20);
    defer p.deinit();
    const bb = p.bounds().?;
    try testing.expectApproxEqAbs(@as(f32, 1.0), bb.max.x, 1e-4); // unit width
    try testing.expectApproxEqAbs(@as(f32, 0.5), bb.max.y, 1e-4); // aspect height

    const t = placeRectUniform(rect);
    const corner = t.applyPoint(.{ .x = 1, .y = 0.5 });
    try testing.expectApproxEqAbs(@as(f32, 1100), corner.x, 1e-3); // 900 + 200
    try testing.expectApproxEqAbs(@as(f32, 400), corner.y, 1e-3); //  300 + 100
    // Uniform scale ⇒ world corner radius equal on both axes (20/200 × 200).
    try testing.expectApproxEqAbs(@as(f32, 20), t.xx * (20.0 / rect.w), 1e-3);
    try testing.expectApproxEqAbs(@as(f32, 20), t.yy * (20.0 / rect.w), 1e-3);
}

test "unit shapes are authored inside the unit frame" {
    var p = try unitRoundedRectPath(testing.allocator, 0.1);
    defer p.deinit();
    const bb = p.bounds().?;
    try testing.expect(bb.min.x >= -1e-6 and bb.min.y >= -1e-6);
    try testing.expect(bb.max.x <= 1.0 + 1e-6 and bb.max.y <= 1.0 + 1e-6);
}

test "parametric unit builders are byte-deterministic (dedup precondition)" {
    var a = try unitRoundedRectPath(testing.allocator, 0.2);
    defer a.deinit();
    var b = try unitRoundedRectPath(testing.allocator, 0.2);
    defer b.deinit();

    var prepared_a = try a.prepare(testing.allocator);
    defer prepared_a.deinit();
    var prepared_b = try b.prepare(testing.allocator);
    defer prepared_b.deinit();
    var ca = try prepared_a.fillCurves(testing.allocator, testing.allocator);
    defer ca.deinit();
    var cb = try prepared_b.fillCurves(testing.allocator, testing.allocator);
    defer cb.deinit();

    try testing.expectEqualSlices(u16, ca.curve_bytes, cb.curve_bytes);
    try testing.expectEqualSlices(u16, ca.band_bytes, cb.band_bytes);
}
