//! Build a `Picture` from a `snail.shape()` run.
//!
//! `placeRun` is the unified entry point: one call for all three hinting
//! paths (`HintMode`) with an explicit origin-snap policy (`RunSnap`),
//! plus optional COLR fanout.
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

pub const ShapedRunError = error{
    /// A glyph references a `face_index` outside the `Faces` value.
    /// Only the COLR-fanout path can raise this — the non-COLR and
    /// hinted paths read `g.font_id` and never dereference `face_index`,
    /// so a forged index passes through them harmlessly.
    UnknownFaceIndex,
} || std.mem.Allocator.Error;

// ── Unified placement (placeRun) ───────────────────────────────────────────
//
// One call for all three hinting paths. `HintMode` folds the per-mode
// differences (local scale + record-key namespace) into data, and `RunSnap`
// selects device-pixel origin snapping.

/// Which glyph-record namespace + local scale a run places into. The three
/// hinting paths differ only in these two things plus how the atlas is
/// populated (the caller's / facade's job); placement hides both.
pub const HintMode = union(enum) {
    /// ppem-independent base curves. Scale = em. Supports COLR fanout.
    unhinted,
    /// Immutable autohint analysis with draw-time fitting policy. Analysis
    /// identity and scale are independent of policy and pixel size.
    autohint: snail.autohint.AutohintPolicy,
    /// TrueType baked per-ppem curves in pixel space, so scale = em/ppem_px.
    truetype: struct { ppem_26_6: u32 },

    /// Local-transform uniform scale for this mode at `em`.
    pub fn scale(self: HintMode, em: f32) f32 {
        return switch (self) {
            .unhinted, .autohint => em,
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
            .autohint => snail.recordKey.autohintGlyph(font_id, glyph_id),
            .truetype => |m| snail.recordKey.hintedGlyph(font_id, glyph_id, m.ppem_26_6),
        };
    }
};

/// Per-glyph origin snapping. Grid-fit hinting (strong autohint x policies or
/// TrueType) only pays off if each glyph origin lands on an integer DEVICE
/// pixel; a fractional pen smears the stems for glyphs after the first.
/// Strong x policies therefore normally pair with `.origins` or `.columns`;
/// the policy and snapping choice remain explicit and independent.
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
/// otherwise. The caller is responsible for having made the referenced glyph
/// records resident in the atlas.
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
            buf[i] = placedShape(placer.originFor(g, i), scale, p.mode.key(g.font_id, g.glyph_id), p.color, p.mode);
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
                try shapes.append(allocator, placedShape(origin, scale, snail.recordKey.unhintedGlyph(g.font_id, layer.glyph_id), layer_color, p.mode));
            }
        } else {
            try shapes.append(allocator, placedShape(origin, scale, snail.recordKey.unhintedGlyph(g.font_id, g.glyph_id), p.color, p.mode));
        }
    }
    return Picture.from(allocator, shapes.items);
}

inline fn placedShape(origin: Vec2, scale: f32, key: snail.RecordKey, color: [4]f32, mode: HintMode) Shape {
    const policy: ?snail.autohint.AutohintPolicy = switch (mode) {
        .autohint => |p| p,
        else => null,
    };
    return .{
        .key = key,
        .autohint_policy = policy,
        .local_transform = .{ .xx = scale, .xy = 0, .tx = origin.x, .yx = 0, .yy = -scale, .ty = origin.y },
        .local_color = color,
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;
const Font = snail.Font;

test "placeRun rejects unknown face_index on COLR fanout" {
    const allocator = testing.allocator;
    const font_data = @import("assets").noto_sans_regular;
    var font = try Font.init(font_data);
    var faces = try Faces.build(allocator, &.{.{ .font = &font }});
    defer faces.deinit();

    // COLR is the only path that dereferences face_index; the
    // non-COLR fast path and hinted modes read only `font_id` +
    // `glyph_id` and let forged indices pass through.
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
    try testing.expectError(error.UnknownFaceIndex, placeRun(allocator, &shaped, &faces, .{
        .baseline = .{ .x = 0, .y = 0 },
        .em = 16,
        .colr = true,
    }));
}

test "autohint mode key is independent of policy" {
    const y_policy: snail.autohint.AutohintPolicy = .{
        .y = .{ .@"align" = .blue_zones },
    };
    const xy_policy: snail.autohint.AutohintPolicy = .{
        .x = .{ .@"align" = .grid },
        .y = .{ .@"align" = .blue_zones },
    };
    const a: HintMode = .{ .autohint = y_policy };
    const b: HintMode = .{ .autohint = xy_policy };
    try testing.expect(a.key(2, 44).eql(b.key(2, 44)));
    try testing.expectEqual(@as(f32, 16), a.scale(16));
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

    // autohint: em scale, policy-independent key, explicit draw-time policy.
    const policy: snail.autohint.AutohintPolicy = .{
        .x = .{ .@"align" = .grid },
        .y = .{ .@"align" = .blue_zones },
    };
    {
        var pic = try placeRun(allocator, &shaped, null, .{
            .baseline = .{ .x = 5, .y = 30 },
            .em = 16,
            .mode = .{ .autohint = policy },
        });
        defer pic.deinit();
        try testing.expect(pic.shapes[0].key.namespace == snail.ns.autohint_glyph);
        try testing.expectEqual(@as(f32, 16), pic.shapes[0].local_transform.xx);
        try testing.expectEqualDeep(policy, pic.shapes[0].autohint_policy.?);
    }

    // origins: each pen lands on an integer device pixel.
    {
        var pic = try placeRun(allocator, &shaped, null, .{
            .baseline = .{ .x = 5.4, .y = 30.6 },
            .em = 16,
            .mode = .{ .autohint = policy },
            .snap = .origins,
            .world_to_pixel = Transform2D{},
        });
        defer pic.deinit();
        for (pic.shapes) |s| try testing.expectEqual(@round(s.local_transform.tx), s.local_transform.tx);
    }
}
