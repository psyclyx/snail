//! Author path shapes the way glyphs are authored: geometry lives in a
//! **unit design frame** (`[0,1]²`, near the origin), and every placement —
//! position, size, rotation — is carried in the per-instance
//! `local_transform`. Nothing about a shape's on-screen location is ever
//! baked into the f16 curve texture.
//!
//! This is the direct analog of the unhinted-glyph contract
//! (`text_picture.zig` + `ttf.zig`'s `1/units_per_em` normalization): a
//! glyph outline is stored in a unit em and positioned by `xx = em` plus a
//! pen translate. Here a unit circle / unit rounded-rect is stored once and
//! positioned by `placeRect`.
//!
//! Why it matters: f16 precision is *relative* to coordinate magnitude, so a
//! shape whose control points sit at screen coordinates (hundreds to
//! thousands) and draws near 1:1 loses ~0.25–2px at the corners. Authored in
//! `[0,1]²` and scaled up by the transform, the same shape keeps sub-0.05px
//! error at any size or position — see the precision regression test below.
//!
//! Reuse falls out for free: identical unit geometry keyed the same collapses
//! to one atlas record (the atlas dedups on `RecordKey`), so the same shape
//! at any size/position is one record, N instances — exactly like a glyph.

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

/// Decode the f16 control points of the first packed segment. Direct
/// encoding lays segment 0 out as (p0.x, p0.y, p1.x, p1.y, p2.x, p2.y,
/// p3.x, p3.y) in the first eight u16s.
fn decodeFirstSegment(cb: []const u16) [8]f32 {
    var out: [8]f32 = undefined;
    for (0..8) |i| out[i] = @floatCast(@as(f16, @bitCast(cb[i])));
    return out;
}

fn maxQuantError(authored: []const snail.Vec2, decoded: [8]f32) f32 {
    // authored packs as x0,y0,x1,y1,... aligned with the decoded layout.
    var m: f32 = 0;
    for (authored, 0..) |a, i| {
        m = @max(m, @abs(a.x - decoded[2 * i]));
        m = @max(m, @abs(a.y - decoded[2 * i + 1]));
    }
    return m;
}

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

    var ca = try a.toCurves(testing.allocator, testing.allocator);
    defer ca.deinit();
    var cb = try b.toCurves(testing.allocator, testing.allocator);
    defer cb.deinit();

    try testing.expectEqualSlices(u16, ca.curve_bytes, cb.curve_bytes);
    try testing.expectEqualSlices(u16, ca.band_bytes, cb.band_bytes);
}

test "unit authoring keeps f16 precision that screen authoring loses" {
    // Same ellipse, far from the origin at 1:1 — the wobble's worst case.
    const target = Rect{ .x = 5000, .y = 5000, .w = 100, .h = 100 };

    // Screen authoring: geometry baked at world coordinates, drawn 1:1.
    var screen = Path.init(testing.allocator);
    defer screen.deinit();
    try screen.addEllipse(target);
    const screen_authored = try screen.cloneFilledCurves(testing.allocator);
    defer testing.allocator.free(screen_authored);
    var screen_curves = try screen.toCurves(testing.allocator, testing.allocator);
    defer screen_curves.deinit();
    const screen_err = maxQuantError(
        &.{ screen_authored[0].p0, screen_authored[0].p1, screen_authored[0].p2, screen_authored[0].p3 },
        decodeFirstSegment(screen_curves.curve_bytes),
    );

    // Unit authoring: geometry in [0,1]², placed by transform. Error is
    // measured in unit space then scaled by the placement (×100) to compare
    // like-for-like on screen.
    var unit = try unitEllipsePath(testing.allocator);
    defer unit.deinit();
    const unit_authored = try unit.cloneFilledCurves(testing.allocator);
    defer testing.allocator.free(unit_authored);
    var unit_curves = try unit.toCurves(testing.allocator, testing.allocator);
    defer unit_curves.deinit();
    const unit_err_local = maxQuantError(
        &.{ unit_authored[0].p0, unit_authored[0].p1, unit_authored[0].p2, unit_authored[0].p3 },
        decodeFirstSegment(unit_curves.curve_bytes),
    );
    const unit_err_screen = unit_err_local * target.w;

    // The unit path stays well under a pixel; screen authoring is an order
    // of magnitude worse at this offset.
    try testing.expect(unit_err_screen < 0.05);
    try testing.expect(screen_err > 1.0);
    try testing.expect(screen_err > unit_err_screen * 10.0);
}
