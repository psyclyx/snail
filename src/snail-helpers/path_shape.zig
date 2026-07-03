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
//! `PathShapeCache` memoizes the packed `GlyphCurves` per identity so the
//! expensive pack runs once.

const std = @import("std");
const snail = @import("snail");

const Allocator = std.mem.Allocator;
const Path = snail.Path;
const Rect = snail.Rect;
const Transform2D = snail.Transform2D;
const StrokeStyle = snail.StrokeStyle;
const GlyphCurves = snail.GlyphCurves;

/// Transform mapping the unit design frame `[0,1]²` onto a world-space
/// rectangle. Compose it with a scene/world transform to place a
/// unit-authored shape. A non-square `rect` scales the unit circle into an
/// ellipse (fills are exact; strokes shear, so keep square rects for
/// uniform stroke width — the glyph-uniform-scale rule).
pub fn placeRect(rect: Rect) Transform2D {
    return .{ .xx = rect.w, .yy = rect.h, .tx = rect.x, .ty = rect.y };
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

/// Stable identities for the parametric unit shapes, so identical shapes
/// dedup without hashing geometry. Caller-authored arbitrary paths pick
/// their own ids in the `custom` range.
pub const key = struct {
    pub const ellipse: u64 = 0x0001_0000_0000_0000;
    pub const rect: u64 = 0x0002_0000_0000_0000;
    /// Rounded rect keyed by quantized relative radius (12.12-ish fixed
    /// point), so equal radii share a record and differ otherwise.
    pub fn roundedRect(r_rel: f32) u64 {
        const q: u64 = @intFromFloat(@round(std.math.clamp(r_rel, 0, 0.5) * 65536.0));
        return 0x0003_0000_0000_0000 | q;
    }
    /// Namespace for caller-authored arbitrary unit paths. `id` is the
    /// caller's stable per-shape identity (reused ⇒ shared record).
    pub fn custom(id: u32) u64 {
        return 0x0004_0000_0000_0000 | @as(u64, id);
    }
};

/// Memoizes packed unit-frame `GlyphCurves` by shape identity, mirroring
/// `UnhintedGlyphCache`. The first `getOrInsert*` for an identity packs the
/// curves; later calls return the same pointer. The cache owns the curves.
pub const PathShapeCache = struct {
    allocator: Allocator,
    curves: std.AutoHashMapUnmanaged(u64, GlyphCurves) = .{},

    pub fn init(allocator: Allocator) PathShapeCache {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *PathShapeCache) void {
        var it = self.curves.valueIterator();
        while (it.next()) |c| c.deinit();
        self.curves.deinit(self.allocator);
        self.* = undefined;
    }

    /// Packed fill curves for a unit-authored `path`, packing on first use.
    /// `unit_path` MUST be authored in the unit frame; `identity` MUST be
    /// stable and unique per distinct unit geometry.
    pub fn getOrInsertFill(
        self: *PathShapeCache,
        scratch: Allocator,
        identity: u64,
        unit_path: *const Path,
    ) !*const GlyphCurves {
        const gop = try self.curves.getOrPut(self.allocator, identity);
        if (!gop.found_existing) {
            errdefer _ = self.curves.remove(identity);
            gop.value_ptr.* = try unit_path.toCurves(self.allocator, scratch);
        }
        return gop.value_ptr;
    }

    /// Packed stroke curves for a unit-authored `path`. `stroke.width` is in
    /// unit-frame units and scales with placement.
    pub fn getOrInsertStroke(
        self: *PathShapeCache,
        scratch: Allocator,
        identity: u64,
        unit_path: *const Path,
        stroke: StrokeStyle,
    ) !*const GlyphCurves {
        const gop = try self.curves.getOrPut(self.allocator, identity);
        if (!gop.found_existing) {
            errdefer _ = self.curves.remove(identity);
            gop.value_ptr.* = try unit_path.strokeToCurves(self.allocator, scratch, stroke);
        }
        return gop.value_ptr;
    }

    pub fn count(self: *const PathShapeCache) u32 {
        return self.curves.count();
    }

    pub fn clear(self: *PathShapeCache) void {
        var it = self.curves.valueIterator();
        while (it.next()) |c| c.deinit();
        self.curves.clearRetainingCapacity();
    }
};

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

test "PathShapeCache memoizes by identity" {
    var cache = PathShapeCache.init(testing.allocator);
    defer cache.deinit();

    var p = try unitEllipsePath(testing.allocator);
    defer p.deinit();

    const first = try cache.getOrInsertFill(testing.allocator, key.ellipse, &p);
    const second = try cache.getOrInsertFill(testing.allocator, key.ellipse, &p);
    try testing.expectEqual(first, second);
    try testing.expectEqual(@as(u32, 1), cache.count());

    var rr = try unitRoundedRectPath(testing.allocator, 0.1);
    defer rr.deinit();
    _ = try cache.getOrInsertFill(testing.allocator, key.roundedRect(0.1), &rr);
    try testing.expectEqual(@as(u32, 2), cache.count());
}

test "distinct rounded-rect radii get distinct identities" {
    try testing.expect(key.roundedRect(0.1) != key.roundedRect(0.2));
    try testing.expect(key.roundedRect(0.1) == key.roundedRect(0.1));
    try testing.expect(key.ellipse != key.rect);
}
