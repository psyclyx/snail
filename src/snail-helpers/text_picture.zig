//! Build a `Picture` from a `snail.shape()` run.
//!
//! `placeRun` is the unified entry point: one call for all three hinting
//! paths (`HintMode`) with an explicit origin-snap policy (`RunSnap`). The
//! older `shapedRunPicture` (+ COLR fanout) and `hintedShapedRunPicture`
//! remain as narrower builders.
//!
//! On snapping: the `.none` path leaves pens at natural sub-pixel positions,
//! so the Picture stays content-only and cacheable. `.origins` / `.columns`
//! snap each glyph ORIGIN to an integer DEVICE pixel (via `world_to_pixel`),
//! which grid-fit hinting needs — that ties the Picture to a world transform,
//! which is fine: a hinted run is per-frame, not cacheable.

const std = @import("std");
const snail = @import("snail");

pub const Picture = @import("picture.zig").Picture;
pub const computeBBox = @import("picture.zig").computeBBox;

pub const ShapedText = snail.ShapedText;
pub const Shape = snail.Shape;
pub const Vec2 = snail.Vec2;
pub const Transform2D = snail.Transform2D;
pub const Faces = snail.Faces;

pub const ShapedRunOptions = struct {
    /// Pen baseline in world coordinates. Apply `snail.snap.baseline` here
    /// before calling if you want hinted-text pixel alignment.
    baseline: Vec2,
    /// Em size in world units (i.e. the px font size).
    em: f32,
    /// Color applied uniformly to every glyph in the run.
    color: [4]f32 = .{ 1, 1, 1, 1 },
    /// When `true`, COLR base glyphs expand into N shapes (one per
    /// layer) using the CPAL palette color on each. The fonts come from
    /// `faces` automatically. When `false`, the run renders one shape
    /// per glyph with `options.color`.
    colr: bool = false,
};

pub const ShapedRunError = error{
    /// A glyph references a `face_index` outside the `Faces` value.
    /// Only the COLR-fanout path can raise this — the non-COLR and
    /// hinted paths read `g.font_id` and never dereference `face_index`,
    /// so a forged index passes through them harmlessly.
    UnknownFaceIndex,
} || std.mem.Allocator.Error;

/// Build a Picture by placing each shaped glyph at its pen position.
/// Font ids come from `g.font_id` (populated by `shape()`); COLR fanout
/// (when `options.colr`) walks the layer table on the face's font, so
/// `faces` is consulted only on that path.
pub fn shapedRunPicture(
    allocator: std.mem.Allocator,
    shaped: *const ShapedText,
    faces: *const Faces,
    options: ShapedRunOptions,
) ShapedRunError!Picture {
    // Fast path: no COLR expansion. Every glyph becomes exactly one
    // shape. Allocate the final buffer directly at the right size and
    // hand it off to Picture — no ArrayList growth, no Picture.from
    // alloc+memcpy. `face_index` is not read here; only `font_id`
    // (already resolved by `shape()`) and `glyph_id` matter.
    if (!options.colr) {
        const buf = try allocator.alloc(Shape, shaped.glyphs.len);
        errdefer allocator.free(buf);
        for (shaped.glyphs, 0..) |g, i| {
            buf[i] = makeShape(g, options, g.font_id, g.glyph_id, options.color);
        }
        return Picture.fromOwnedSlice(allocator, buf);
    }

    // COLR-capable slow path: shape count varies per glyph. Pre-size to
    // glyph count and let it grow when a glyph fans out. `face_index`
    // is dereferenced here to find the COLR layer table, so an
    // out-of-range value is caught explicitly.
    var shapes: std.ArrayList(Shape) = .empty;
    defer shapes.deinit(allocator);
    try shapes.ensureTotalCapacity(allocator, shaped.glyphs.len);

    for (shaped.glyphs) |g| {
        const fi: usize = @intCast(g.face_index);
        if (fi >= faces.faceCount()) return error.UnknownFaceIndex;
        const font_id = g.font_id;

        // COLR fanout. Each layer becomes its own Shape keyed by the
        // *layer* glyph id (not `g.glyph_id`) with the layer's CPAL
        // color, or `options.color` for the foreground sentinel palette
        // index 0xFFFF.
        var emitted = false;
        var iter = faces.face(g.face_index).font.colrLayers(g.glyph_id);
        if (iter.count() > 0) {
            while (iter.next()) |layer| {
                const layer_color: [4]f32 = if (layer.color[0] < 0)
                    options.color
                else
                    layer.color;
                try shapes.append(allocator, makeShape(g, options, font_id, layer.glyph_id, layer_color));
            }
            emitted = true;
        }
        if (!emitted) {
            try shapes.append(allocator, makeShape(g, options, font_id, g.glyph_id, options.color));
        }
    }

    return Picture.from(allocator, shapes.items);
}

inline fn makeShape(g: anytype, options: ShapedRunOptions, font_id: u32, glyph_id: u16, color: [4]f32) Shape {
    const pen_x = options.baseline.x + options.em * g.x_offset;
    const pen_y = options.baseline.y + options.em * g.y_offset;
    return .{
        .key = snail.recordKey.unhintedGlyph(font_id, glyph_id),
        .local_transform = .{
            .xx = options.em,
            .xy = 0,
            .tx = pen_x,
            .yx = 0,
            .yy = -options.em,
            .ty = pen_y,
        },
        .local_color = color,
    };
}

pub const HintedShapedRunOptions = struct {
    /// Pen baseline in world coordinates. Apply `snail.snap.baseline` here
    /// before calling for crisp hinted alignment under projection — per-glyph
    /// offsets ride through untouched so kerning survives.
    baseline: Vec2,
    /// Em size in world units. Used to scale the shaper's em-relative
    /// glyph offsets into world-space pen positions.
    em: f32,
    /// 26.6 fixed-point ppem the glyphs were hinted at — the same value
    /// passed to the `HintVm` and used to key atlas entries under
    /// `recordKey.hintedGlyph(font_id, glyph_id, ppem_26_6)`. Callers must
    /// pass exactly the ppem they hinted at, *not* `em * 64`: under zoom
    /// the two differ because hinting scales by zoom, but per-glyph layout
    /// still uses the unscaled em.
    ppem_26_6: u32,
    color: [4]f32 = .{ 1, 1, 1, 1 },
};

/// Build a Picture for hinted text. Caller is responsible for having
/// already inserted hinted curves into the atlas under
/// `recordKey.hintedGlyph(font_id, glyph_id, ppem_26_6)` keys, and for
/// applying `snail.snap.baseline` to `options.baseline` if pixel-grid
/// alignment is desired.
///
/// Hinted curves live in pixel-space at the hint-time ppem (= `ppem_26_6
/// / 64`), which may differ from `em` when the world transform applies
/// a non-identity scale (e.g. interactive zoom). The per-glyph transform
/// scales by `em / ppem_px` so the glyph occupies `em` scene units along
/// each axis regardless of the hint-time ppem; the subsequent MVP zoom
/// brings it to its intended screen size with pixel-grid alignment baked
/// in by the hinter.
pub fn hintedShapedRunPicture(
    allocator: std.mem.Allocator,
    shaped: *const ShapedText,
    options: HintedShapedRunOptions,
) std.mem.Allocator.Error!Picture {
    // Hinted text never fans out — one shape per glyph. Allocate the
    // final buffer directly at the right size, same pattern as the
    // non-COLR `shapedRunPicture` fast path. No `Faces` is needed:
    // hinted runs key off `(g.font_id, g.glyph_id, ppem)` and never
    // dereference `face_index`.
    const ppem_26_6 = options.ppem_26_6;
    const ppem_px = @as(f32, @floatFromInt(ppem_26_6)) / 64.0;
    const scale: f32 = if (ppem_px > 0.0) options.em / ppem_px else 1.0;

    const buf = try allocator.alloc(Shape, shaped.glyphs.len);
    errdefer allocator.free(buf);

    for (shaped.glyphs, 0..) |g, i| {
        const font_id = g.font_id;
        const pen_x = options.baseline.x + options.em * g.x_offset;
        const pen_y = options.baseline.y + options.em * g.y_offset;
        buf[i] = .{
            .key = snail.recordKey.hintedGlyph(font_id, g.glyph_id, ppem_26_6),
            .local_transform = .{
                .xx = scale,
                .xy = 0,
                .tx = pen_x,
                .yx = 0,
                .yy = -scale,
                .ty = pen_y,
            },
            .local_color = options.color,
        };
    }

    return Picture.fromOwnedSlice(allocator, buf);
}

// ── Unified placement (placeRun) ───────────────────────────────────────────
//
// One call for all three hinting paths. `HintMode` folds the per-mode
// differences (local scale + record-key namespace) into data, and `RunSnap`
// selects device-pixel origin snapping. Supersedes `shapedRunPicture` /
// `hintedShapedRunPicture`, which stay as thin back-compat wrappers.

/// Which glyph-record namespace + local scale a run places into. The three
/// hinting paths differ only in these two things plus how the atlas is
/// populated (the caller's / facade's job); placement hides both.
pub const HintMode = union(enum) {
    /// ppem-independent base curves. Scale = em. Supports COLR fanout.
    unhinted,
    /// auto_light resolution-independent warp: shared base curves + a per-ppem
    /// knot record. Samples the em-space base, so scale = em.
    auto_light: struct { ppem_26_6: u32 },
    /// TrueType baked per-ppem curves in pixel space, so scale = em/ppem_px.
    truetype: struct { ppem_26_6: u32 },

    /// Local-transform uniform scale for this mode at `em`.
    pub fn scale(self: HintMode, em: f32) f32 {
        return switch (self) {
            .unhinted, .auto_light => em,
            .truetype => |t| blk: {
                const ppem_px = @as(f32, @floatFromInt(t.ppem_26_6)) / 64.0;
                break :blk if (ppem_px > 0.0) em / ppem_px else em;
            },
        };
    }

    /// Atlas record key for `(font_id, glyph_id)` in this mode.
    pub fn key(self: HintMode, font_id: u32, glyph_id: u16) snail.RecordKey {
        return switch (self) {
            .unhinted => snail.recordKey.unhintedGlyph(font_id, glyph_id),
            .auto_light => |m| snail.recordKey.autohintGlyph(font_id, glyph_id, m.ppem_26_6),
            .truetype => |m| snail.recordKey.hintedGlyph(font_id, glyph_id, m.ppem_26_6),
        };
    }
};

/// Per-glyph origin snapping. Grid-fit hinting (auto_light x-warp, TrueType)
/// only pays off if each glyph origin lands on an integer DEVICE pixel; a
/// fractional pen smears the stems for glyphs after the first.
pub const RunSnap = enum {
    /// No snapping — the cacheable path for unhinted content placed at any
    /// sub-pixel position. `world_to_pixel` is not consulted.
    none,
    /// Proportional hinted text: snap each glyph ORIGIN to a whole device
    /// pixel. Rounds the POSITION (baseline + em*offset), not the advance, so
    /// rounding error never accumulates and HarfBuzz kerning survives.
    origins,
    /// Monospace: one integer device-pixel column advance from the first
    /// glyph — exact terminal columns. Caller ASSERTS the run is monospace.
    columns,
};

pub const RunPlacement = struct {
    /// Pen baseline in WORLD coordinates.
    baseline: Vec2,
    /// Em size in world units (the px font size).
    em: f32,
    color: [4]f32 = .{ 1, 1, 1, 1 },
    mode: HintMode = .unhinted,
    snap: RunSnap = .none,
    /// world→DEVICE-pixel transform (`snail.mvpToScenePixel(mvp, fb_w, fb_h)`
    /// — the FRAMEBUFFER size, so snapping is HiDPI-correct). Required when
    /// `snap != .none`; ignored otherwise.
    world_to_pixel: ?Transform2D = null,
    /// COLR fanout (one shape per layer). Only valid with `mode == .unhinted`.
    colr: bool = false,
};

/// Precomputed per-run placement state; `originFor` maps a glyph to its
/// world-space origin under the chosen snap policy.
const Placer = struct {
    p: RunPlacement,
    inv: Transform2D = .{},
    base_dev: Vec2 = .{ .x = 0, .y = 0 },
    dev_adv: f32 = 0,

    fn init(p: RunPlacement, shaped: *const ShapedText) Placer {
        var self = Placer{ .p = p };
        if (p.snap == .columns) {
            const w2p = p.world_to_pixel orelse Transform2D{};
            self.inv = w2p.inverse() orelse Transform2D{};
            const bdev = w2p.applyPoint(p.baseline);
            self.base_dev = .{ .x = @round(bdev.x), .y = @round(bdev.y) };
            // Device x-advance of one em-scaled unit advance. Assumes an
            // axis-aligned world→device transform (hinted text isn't rotated);
            // `xx` is the x-scale.
            const adv0 = if (shaped.glyphs.len > 0) shaped.glyphs[0].x_advance else 0;
            self.dev_adv = @round(w2p.xx * p.em * adv0);
        }
        return self;
    }

    fn originFor(self: *const Placer, g: anytype, i: usize) Vec2 {
        return switch (self.p.snap) {
            .none => .{
                .x = self.p.baseline.x + self.p.em * g.x_offset,
                .y = self.p.baseline.y + self.p.em * g.y_offset,
            },
            .origins => snail.snap.origin(.{
                .x = self.p.baseline.x + self.p.em * g.x_offset,
                .y = self.p.baseline.y + self.p.em * g.y_offset,
            }, self.p.world_to_pixel orelse Transform2D{}),
            .columns => self.inv.applyPoint(.{
                .x = self.base_dev.x + @as(f32, @floatFromInt(i)) * self.dev_adv,
                .y = self.base_dev.y,
            }),
        };
    }
};

/// Build a `Picture` for a shaped run in any hinting mode with any origin-snap
/// policy. `faces` is needed only for COLR fanout (`p.colr`); pass `null`
/// otherwise. The caller (or the `TextAtlas` facade) is responsible for having
/// made the referenced glyph records resident in the atlas.
pub fn placeRun(
    allocator: std.mem.Allocator,
    shaped: *const ShapedText,
    faces: ?*const Faces,
    p: RunPlacement,
) ShapedRunError!Picture {
    const scale = p.mode.scale(p.em);
    const placer = Placer.init(p, shaped);

    // Fast path: one shape per glyph (all modes; COLR is the only fan-out).
    if (!p.colr) {
        const buf = try allocator.alloc(Shape, shaped.glyphs.len);
        errdefer allocator.free(buf);
        for (shaped.glyphs, 0..) |g, i| {
            buf[i] = placedShape(placer.originFor(g, i), scale, p.mode.key(g.font_id, g.glyph_id), p.color);
        }
        return Picture.fromOwnedSlice(allocator, buf);
    }

    // COLR fanout — unhinted only. Every layer of a glyph shares that glyph's
    // (snapped) origin; each becomes a shape keyed by its layer glyph id.
    const fc = faces orelse return error.UnknownFaceIndex;
    var shapes: std.ArrayList(Shape) = .empty;
    defer shapes.deinit(allocator);
    try shapes.ensureTotalCapacity(allocator, shaped.glyphs.len);
    for (shaped.glyphs, 0..) |g, i| {
        const fi: usize = @intCast(g.face_index);
        if (fi >= fc.faceCount()) return error.UnknownFaceIndex;
        const origin = placer.originFor(g, i);
        var iter = fc.face(g.face_index).font.colrLayers(g.glyph_id);
        if (iter.count() > 0) {
            while (iter.next()) |layer| {
                const layer_color: [4]f32 = if (layer.color[0] < 0) p.color else layer.color;
                try shapes.append(allocator, placedShape(origin, scale, snail.recordKey.unhintedGlyph(g.font_id, layer.glyph_id), layer_color));
            }
        } else {
            try shapes.append(allocator, placedShape(origin, scale, snail.recordKey.unhintedGlyph(g.font_id, g.glyph_id), p.color));
        }
    }
    return Picture.from(allocator, shapes.items);
}

inline fn placedShape(origin: Vec2, scale: f32, key: snail.RecordKey, color: [4]f32) Shape {
    return .{
        .key = key,
        .local_transform = .{ .xx = scale, .xy = 0, .tx = origin.x, .yx = 0, .yy = -scale, .ty = origin.y },
        .local_color = color,
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;
const Font = snail.Font;
const HintVm = snail.HintVm;
const HintPpem = snail.HintPpem;

test "shapedRunPicture builds one shape per shaped glyph" {
    const allocator = testing.allocator;
    const font_data = @import("assets").noto_sans_regular;

    var font = try Font.init(font_data);
    var faces = try Faces.build(allocator, &.{.{ .font = &font }});
    defer faces.deinit();

    var shaped = try snail.shape(allocator, &faces, "Hi", .{});
    defer shaped.deinit();
    try testing.expect(shaped.glyphs.len == 2);

    var pic = try shapedRunPicture(allocator, &shaped, &faces, .{
        .baseline = .{ .x = 10, .y = 40 },
        .em = 24,
        .color = .{ 1, 1, 1, 1 },
    });
    defer pic.deinit();

    try testing.expectEqual(@as(usize, 2), pic.shapes.len);
    // First glyph at x_offset=0 should land at the baseline x.
    try testing.expectApproxEqAbs(@as(f32, 10), pic.shapes[0].local_transform.tx, 1e-5);
    try testing.expectEqual(@as(f32, 24), pic.shapes[0].local_transform.xx);
    try testing.expectEqual(@as(f32, -24), pic.shapes[0].local_transform.yy);
    try testing.expect(pic.shapes[0].key.namespace == snail.ns.unhinted_glyph);
}

test "hintedShapedRunPicture builds shapes for hinted glyph keys" {
    const allocator = testing.allocator;
    const font_data = @import("assets").noto_sans_regular;

    var font = try Font.init(font_data);
    var faces = try Faces.build(allocator, &.{.{ .font = &font }});
    defer faces.deinit();

    var shaped = try snail.shape(allocator, &faces, "Hi", .{});
    defer shaped.deinit();
    try testing.expect(shaped.glyphs.len == 2);

    const expected_ppem: u32 = @intFromFloat(@round(14.0 * 64.0));
    var pic = try hintedShapedRunPicture(allocator, &shaped, .{
        .baseline = .{ .x = 5, .y = 32 },
        .em = 14,
        .ppem_26_6 = expected_ppem,
        .color = .{ 1, 1, 1, 1 },
    });
    defer pic.deinit();

    try testing.expectEqual(@as(usize, 2), pic.shapes.len);
    try testing.expectEqual(snail.ns.hinted_glyph, pic.shapes[0].key.namespace);
    try testing.expectEqual(expected_ppem, pic.shapes[0].key.c);
    try testing.expectApproxEqAbs(@as(f32, 1), pic.shapes[0].local_transform.xx, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, -1), pic.shapes[0].local_transform.yy, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 5), pic.shapes[0].local_transform.tx, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 32), pic.shapes[0].local_transform.ty, 1e-5);
}

test "caller-snapped baseline propagates through hintedShapedRunPicture" {
    const allocator = testing.allocator;
    const font_data = @import("assets").noto_sans_regular;

    var font = try Font.init(font_data);
    var faces = try Faces.build(allocator, &.{.{ .font = &font }});
    defer faces.deinit();

    var shaped = try snail.shape(allocator, &faces, "AV", .{});
    defer shaped.deinit();
    try testing.expect(shaped.glyphs.len == 2);

    // World→pixel: 0.5× scale with a fractional translation so a baseline
    // world position of (10.0, 20.0) maps to screen (5.3, 10.7) — round
    // to (5.3, 11), inverse back to a snapped world baseline of (10.0, 20.6).
    // (snap.baseline keeps x, rounds y in screen space.)
    const w2p = Transform2D{ .xx = 0.5, .yy = 0.5, .tx = 0.3, .ty = 0.7 };
    const snapped = snail.snap.baseline(.{ .x = 10, .y = 20 }, w2p);

    const ppem: u32 = @intFromFloat(@round(14.0 * 64.0));
    var pic = try hintedShapedRunPicture(allocator, &shaped, .{
        .baseline = snapped,
        .em = 14,
        .ppem_26_6 = ppem,
    });
    defer pic.deinit();

    // First glyph's pen lands on the snapped baseline.
    try testing.expectApproxEqAbs(snapped.x, pic.shapes[0].local_transform.tx, 1e-4);
    try testing.expectApproxEqAbs(snapped.y, pic.shapes[0].local_transform.ty, 1e-4);

    // Second glyph's pen = snapped_baseline + em * x_offset. The
    // em * x_offset delta must equal the unsnapped delta from baseline
    // (i.e. snapping the baseline does not perturb intra-run advances).
    const delta_x = pic.shapes[1].local_transform.tx - pic.shapes[0].local_transform.tx;
    const expected_delta = 14.0 * shaped.glyphs[1].x_offset;
    try testing.expectApproxEqAbs(expected_delta, delta_x, 1e-4);
}

test "shapedRunPicture rejects unknown face_index on COLR fanout" {
    const allocator = testing.allocator;
    const font_data = @import("assets").noto_sans_regular;
    var font = try Font.init(font_data);
    var faces = try Faces.build(allocator, &.{.{ .font = &font }});
    defer faces.deinit();

    // COLR is the only path that dereferences face_index; the
    // non-COLR fast path and `hintedShapedRunPicture` read only
    // `font_id` + `glyph_id` and let forged indices pass through.
    var fake_glyphs = [_]ShapedText.Glyph{.{
        .face_index = 5,
        .glyph_id = 0,
        .x_offset = 0,
        .y_offset = 0,
        .x_advance = 0,
        .y_advance = 0,
        .source_start = 0,
        .source_end = 0,
    }};
    const shaped = ShapedText{
        .allocator = allocator,
        .glyphs = fake_glyphs[0..],
    };
    try testing.expectError(error.UnknownFaceIndex, shapedRunPicture(allocator, &shaped, &faces, .{
        .baseline = .{ .x = 0, .y = 0 },
        .em = 16,
        .colr = true,
    }));
}

test "placeRun: mode picks scale+key, columns snaps to integer device pens" {
    const allocator = testing.allocator;
    var font = try Font.init(@import("assets").dejavu_sans_mono);
    var faces = try Faces.build(allocator, &.{.{ .font = &font }});
    defer faces.deinit();
    var shaped = try snail.shape(allocator, &faces, "abc", .{});
    defer shaped.deinit();
    try testing.expect(shaped.glyphs.len == 3);

    // unhinted: em scale, unhinted namespace, natural (unsnapped) pen.
    {
        var pic = try placeRun(allocator, &shaped, null, .{ .baseline = .{ .x = 5, .y = 30 }, .em = 16 });
        defer pic.deinit();
        try testing.expect(pic.shapes[0].key.namespace == snail.ns.unhinted_glyph);
        try testing.expectEqual(@as(f32, 16), pic.shapes[0].local_transform.xx);
        try testing.expectApproxEqAbs(@as(f32, 5), pic.shapes[0].local_transform.tx, 1e-5);
    }

    // truetype: em/ppem_px scale, hinted namespace, columns = integer + uniform.
    {
        const ppem: u32 = 13 * 64; // ppem_px = 13, em = 16 -> scale = 16/13
        var pic = try placeRun(allocator, &shaped, null, .{
            .baseline = .{ .x = 5, .y = 30 },
            .em = 16,
            .mode = .{ .truetype = .{ .ppem_26_6 = ppem } },
            .snap = .columns,
            .world_to_pixel = Transform2D{}, // identity: world == device
        });
        defer pic.deinit();
        try testing.expect(pic.shapes[0].key.namespace == snail.ns.hinted_glyph);
        try testing.expectApproxEqAbs(@as(f32, 16.0 / 13.0), pic.shapes[0].local_transform.xx, 1e-4);
        const x0 = pic.shapes[0].local_transform.tx;
        const x1 = pic.shapes[1].local_transform.tx;
        const x2 = pic.shapes[2].local_transform.tx;
        try testing.expectEqual(@round(x0), x0); // origins on the grid
        try testing.expectEqual(@round(x1 - x0), x1 - x0); // integer advance
        try testing.expectApproxEqAbs(x1 - x0, x2 - x1, 1e-4); // uniform columns
    }

    // auto_light: em scale, autohint namespace.
    {
        var pic = try placeRun(allocator, &shaped, null, .{
            .baseline = .{ .x = 5, .y = 30 },
            .em = 16,
            .mode = .{ .auto_light = .{ .ppem_26_6 = 13 * 64 } },
        });
        defer pic.deinit();
        try testing.expect(pic.shapes[0].key.namespace == snail.ns.autohint_glyph);
        try testing.expectEqual(@as(f32, 16), pic.shapes[0].local_transform.xx);
    }

    // origins: each pen lands on an integer device pixel.
    {
        var pic = try placeRun(allocator, &shaped, null, .{
            .baseline = .{ .x = 5.4, .y = 30.6 },
            .em = 16,
            .mode = .{ .auto_light = .{ .ppem_26_6 = 13 * 64 } },
            .snap = .origins,
            .world_to_pixel = Transform2D{},
        });
        defer pic.deinit();
        for (pic.shapes) |s| try testing.expectEqual(@round(s.local_transform.tx), s.local_transform.tx);
    }
}
