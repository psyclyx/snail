//! Convert a shaped text run into renderer-ready `Shape` values.
//!
//! `placeRun` is allocation-free and works with caller-owned storage;
//! `placeRunAlloc` is the convenience allocator. Both handle all three hinting
//! paths (`HintMode`) with an explicit origin-snap policy (`RunSnap`),
//! plus optional COLR fanout.
//!
//! On snapping: the `.none` path leaves pens at natural sub-pixel positions,
//! so the resulting shapes stay content-only and cacheable. `.origins` / `.columns`
//! snap each glyph ORIGIN to an integer DEVICE pixel (via `world_to_pixel`),
//! which grid-fit hinting needs — that ties the shapes to a world transform,
//! which is fine: a hinted run is per-frame, not cacheable.

const std = @import("std");
const text = @import("../text.zig");
const faces_mod = @import("faces.zig");
const shape_mod = @import("../draw/shape.zig");
const math = @import("../math/vec.zig");
const record_key = @import("../atlas/record_key.zig");
const policy_mod = @import("../font/autohint/policy.zig");

pub const ShapedText = text.ShapedText;
pub const Shape = shape_mod.Shape;
pub const Vec2 = math.Vec2;
pub const Transform2D = math.Transform2D;
pub const Faces = faces_mod.Faces;

pub const PlaceRunError = error{
    /// A glyph references a `face_index` outside the `Faces` value.
    /// Only the COLR-fanout path can raise this — the non-COLR and
    /// hinted paths read `g.font_id` and never dereference `face_index`,
    /// so a forged index passes through them harmlessly.
    UnknownFaceIndex,
    /// COLR fanout refers to unhinted layer glyphs and cannot be combined
    /// with a hinted record namespace.
    InvalidColrMode,
    /// Device snapping requires an explicit world-to-pixel transform.
    MissingWorldToPixel,
    /// The supplied world-to-pixel transform cannot be inverted.
    InvalidWorldToPixel,
    /// Column snapping is defined only for an axis-aligned world-to-pixel
    /// transform. Use `.origins` for rotated or sheared text.
    UnsupportedColumnsTransform,
    /// Em size must be finite and strictly positive.
    InvalidEm,
    /// Baseline coordinates and all shaped glyph metrics must be finite.
    InvalidPlacement,
    /// Instance color components must be finite and straight alpha must be in
    /// `[0, 1]`. RGB remains unclamped so HDR values survive.
    InvalidColor,
    /// A TT ppem or autohint policy is invalid.
    InvalidHintMode,
    /// Column snapping requires one common horizontal advance.
    NonMonospaceColumns,
    /// Caller-provided shape storage was too small.
    BufferTooSmall,
    /// The expanded COLR shape count cannot be represented by `usize`.
    ShapeCountOverflow,
};

pub const PlaceRunAllocError = PlaceRunError || std.mem.Allocator.Error;

// ── Unified placement (placeRun) ───────────────────────────────────────────
//
// One call for all three hinting paths. `HintMode` folds the per-mode
// differences (local scale + record-key namespace) into data, and `RunSnap`
// selects device-pixel origin snapping.

/// Which glyph-record namespace + local scale a run places into. The three
/// hinting paths differ only in these two things plus how the atlas is
/// populated (the caller's job); placement hides both.
pub const HintMode = union(enum) {
    /// ppem-independent base curves. Scale = em. Supports COLR fanout.
    unhinted,
    /// Immutable autohint analysis with draw-time fitting policy. Analysis
    /// identity and scale are independent of policy and pixel size.
    autohint: policy_mod.AutohintPolicy,
    /// TT-hinted, per-ppem curves in pixel space, so scale = em/ppem_px.
    tt_hint: struct { ppem_26_6: u32 },

    /// Local-transform uniform scale for this mode at `em`.
    pub fn scale(self: HintMode, em: f32) f32 {
        return switch (self) {
            .unhinted, .autohint => em,
            .tt_hint => |t| blk: {
                const ppem_px = @as(f32, @floatFromInt(t.ppem_26_6)) / 64.0;
                break :blk em / ppem_px;
            },
        };
    }

    /// Atlas record key for `(font_id, glyph_id)` in this mode.
    pub fn key(self: HintMode, font_id: u32, glyph_id: u16) record_key.RecordKey {
        return switch (self) {
            .unhinted => record_key.unhintedGlyph(font_id, glyph_id),
            .autohint => record_key.autohintGlyph(font_id, glyph_id),
            .tt_hint => |m| record_key.ttHintedGlyph(font_id, glyph_id, m.ppem_26_6),
        };
    }
};

/// Per-glyph origin snapping. Grid-fit hinting (strong autohint x policies or
/// TT hinting) only pays off if each glyph origin lands on an integer DEVICE
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

/// Scene y-axis direction. Glyph geometry is stored y-up (font units);
/// placement orients it into the scene. `.down` (the default) suits
/// top-left-origin UI/framebuffer coordinates; `.up` suits hosts whose
/// world y grows upward. Coverage and winding are orientation-independent,
/// so both directions produce identical fills.
pub const YAxis = enum { down, up };

pub const RunPlacement = struct {
    /// Pen baseline in WORLD coordinates.
    baseline: Vec2,
    /// Em size in world units (the px font size).
    em: f32,
    color: [4]f32 = .{ 1, 1, 1, 1 },
    mode: HintMode = .unhinted,
    snap: RunSnap = .none,
    /// Which way scene y grows. Flips the sign of the glyph local
    /// transform's y column and of shaped vertical offsets.
    y_axis: YAxis = .down,
    /// world→DEVICE-pixel transform (`mvpToScenePixel(mvp, fb_w, fb_h)`
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
    scale: f32,
    base_dev: Vec2 = .{ .x = 0, .y = 0 },
    dev_adv: f32 = 0,
    /// +1 for `.down`, -1 for `.up`. Shaped `y_offset`/`y_advance` are
    /// stored in the y-down convention (`faces.zig` negates HarfBuzz's
    /// y-up values), so y-up placement flips them back.
    y_sign: f32 = 1,

    fn init(p: RunPlacement, shaped: *const ShapedText) PlaceRunError!Placer {
        try validatePlacement(shaped, p);
        const scale = p.mode.scale(p.em);
        if (!std.math.isFinite(scale)) return error.InvalidEm;
        var self = Placer{ .p = p, .scale = scale, .y_sign = if (p.y_axis == .down) 1 else -1 };
        if (p.snap != .none and p.world_to_pixel == null) return error.MissingWorldToPixel;
        if (p.snap != .none) self.inv = p.world_to_pixel.?.inverse() orelse return error.InvalidWorldToPixel;
        if (p.snap == .columns) {
            const w2p = p.world_to_pixel.?;
            if (w2p.xy != 0 or w2p.yx != 0) return error.UnsupportedColumnsTransform;
            const bdev = w2p.applyPoint(p.baseline);
            if (!finiteVec(bdev)) return error.InvalidPlacement;
            self.base_dev = .{ .x = @round(bdev.x), .y = @round(bdev.y) };
            // Device x-advance of one em-scaled unit advance. Axis alignment
            // was checked above, so `xx` is the complete x scale.
            const adv0 = if (shaped.glyphs.len > 0) shaped.glyphs[0].x_advance else 0;
            self.dev_adv = @round(w2p.xx * p.em * adv0);
            if (!std.math.isFinite(self.dev_adv)) return error.InvalidPlacement;
        }
        // Validate every derived origin before `placeRun` publishes its first
        // output shape, so an extreme later glyph cannot leave a partial run.
        for (shaped.glyphs, 0..) |glyph, i| _ = try self.originFor(glyph, i);
        return self;
    }

    fn originFor(self: *const Placer, g: anytype, i: usize) PlaceRunError!Vec2 {
        const natural = Vec2{
            .x = self.p.baseline.x + self.p.em * g.x_offset,
            .y = self.p.baseline.y + self.p.em * g.y_offset * self.y_sign,
        };
        const result = switch (self.p.snap) {
            .none => natural,
            .origins => blk: {
                if (!finiteVec(natural)) return error.InvalidPlacement;
                const device = self.p.world_to_pixel.?.applyPoint(natural);
                if (!finiteVec(device)) return error.InvalidPlacement;
                break :blk self.inv.applyPoint(.{ .x = @round(device.x), .y = @round(device.y) });
            },
            .columns => blk: {
                const device = Vec2{
                    .x = self.base_dev.x + @as(f32, @floatFromInt(i)) * self.dev_adv,
                    .y = self.base_dev.y,
                };
                if (!finiteVec(device)) return error.InvalidPlacement;
                break :blk self.inv.applyPoint(device);
            },
        };
        if (!finiteVec(result)) return error.InvalidPlacement;
        return result;
    }
};

fn finite(values: anytype) bool {
    inline for (values) |value| if (!std.math.isFinite(value)) return false;
    return true;
}

fn finiteVec(value: Vec2) bool {
    return finite(.{ value.x, value.y });
}

fn validColor(color: [4]f32) bool {
    return finite(color) and color[3] >= 0 and color[3] <= 1;
}

fn validatePlacement(shaped: *const ShapedText, p: RunPlacement) PlaceRunError!void {
    if (!std.math.isFinite(p.em) or p.em <= 0) return error.InvalidEm;
    if (!finite(.{ p.baseline.x, p.baseline.y })) return error.InvalidPlacement;
    if (!validColor(p.color)) return error.InvalidColor;
    switch (p.mode) {
        .unhinted => {},
        .autohint => |policy| policy.validate() catch return error.InvalidHintMode,
        .tt_hint => |tt| {
            if (tt.ppem_26_6 == 0 or tt.ppem_26_6 > text.TtHintPpem.max_26_6) return error.InvalidHintMode;
        },
    }
    if (p.snap != .none) {
        const w2p = p.world_to_pixel orelse return error.MissingWorldToPixel;
        _ = w2p.inverse() orelse return error.InvalidWorldToPixel;
        if (p.snap == .columns and (w2p.xy != 0 or w2p.yx != 0))
            return error.UnsupportedColumnsTransform;
    }

    const column_advance = if (shaped.glyphs.len == 0) @as(f32, 0) else shaped.glyphs[0].x_advance;
    for (shaped.glyphs) |glyph| {
        if (!finite(.{ glyph.x_offset, glyph.y_offset, glyph.x_advance, glyph.y_advance }))
            return error.InvalidPlacement;
        if (p.snap == .columns and
            (glyph.x_advance != column_advance or glyph.y_advance != 0))
        {
            return error.NonMonospaceColumns;
        }
    }
}

/// Number of shapes needed to place a run. Usually one per glyph; COLR glyphs
/// can fan out into several layer shapes.
pub fn placedRunShapeCount(
    shaped: *const ShapedText,
    faces: ?*const Faces,
    p: RunPlacement,
) PlaceRunError!usize {
    try validatePlacement(shaped, p);
    if (!p.colr) return shaped.glyphs.len;
    switch (p.mode) {
        .unhinted => {},
        else => return error.InvalidColrMode,
    }
    const fc = faces orelse return error.UnknownFaceIndex;
    var count: usize = 0;
    for (shaped.glyphs) |g| {
        const fi: usize = @intCast(g.face_index);
        if (fi >= fc.faceCount()) return error.UnknownFaceIndex;
        var layers = fc.fontForFace(g.face_index).?.colrLayers(g.glyph_id);
        const layer_count = layers.count();
        while (layers.next()) |layer| {
            // A negative red component is the COLR foreground marker; it is
            // replaced with the already-validated placement color.
            if (!(layer.color[0] < 0) and !validColor(layer.color)) return error.InvalidColor;
        }
        count = std.math.add(usize, count, if (layer_count > 0) layer_count else 1) catch
            return error.ShapeCountOverflow;
    }
    return count;
}

/// Write a shaped run into caller-owned storage and return the initialized
/// prefix. The caller is responsible for making the referenced records
/// resident in its atlas.
pub fn placeRun(
    out: []Shape,
    shaped: *const ShapedText,
    faces: ?*const Faces,
    p: RunPlacement,
) PlaceRunError![]Shape {
    const shape_count = try placedRunShapeCount(shaped, faces, p);
    if (out.len < shape_count) return error.BufferTooSmall;
    const placer = try Placer.init(p, shaped);

    // Fast path: one shape per glyph (all modes; COLR is the only fan-out).
    if (!p.colr) {
        for (shaped.glyphs, 0..) |g, i| {
            out[i] = placedShape(placer.originFor(g, i) catch unreachable, placer.scale, placer.y_sign, p.mode.key(g.font_id, g.glyph_id), p.color, p.mode);
        }
        return out[0..shape_count];
    }

    // COLR fanout — unhinted only. Every layer of a glyph shares that glyph's
    // (snapped) origin; each becomes a shape keyed by its layer glyph id.
    const fc = faces.?;
    var cursor: usize = 0;
    for (shaped.glyphs, 0..) |g, i| {
        const origin = placer.originFor(g, i) catch unreachable;
        var iter = fc.fontForFace(g.face_index).?.colrLayers(g.glyph_id);
        if (iter.count() > 0) {
            while (iter.next()) |layer| {
                const layer_color: [4]f32 = if (layer.color[0] < 0) p.color else layer.color;
                out[cursor] = placedShape(origin, placer.scale, placer.y_sign, record_key.unhintedGlyph(g.font_id, layer.glyph_id), layer_color, p.mode);
                cursor += 1;
            }
        } else {
            out[cursor] = placedShape(origin, placer.scale, placer.y_sign, record_key.unhintedGlyph(g.font_id, g.glyph_id), p.color, p.mode);
            cursor += 1;
        }
    }
    return out[0..cursor];
}

/// Allocate and place a shaped run. The returned slice belongs to `allocator`.
pub fn placeRunAlloc(
    allocator: std.mem.Allocator,
    shaped: *const ShapedText,
    faces: ?*const Faces,
    p: RunPlacement,
) PlaceRunAllocError![]Shape {
    const shape_count = try placedRunShapeCount(shaped, faces, p);
    const out = try allocator.alloc(Shape, shape_count);
    errdefer allocator.free(out);
    return placeRun(out, shaped, faces, p);
}

inline fn placedShape(origin: Vec2, scale: f32, y_sign: f32, key: record_key.RecordKey, color: [4]f32, mode: HintMode) Shape {
    const policy: ?policy_mod.AutohintPolicy = switch (mode) {
        .autohint => |p| p,
        else => null,
    };
    // Glyph curves are stored y-up (font units); `.yy = -scale` orients
    // them into a y-down scene, `+scale` into a y-up one.
    return .{
        .key = key,
        .autohint_policy = policy,
        .local_transform = .{ .xx = scale, .xy = 0, .tx = origin.x, .yx = 0, .yy = -y_sign * scale, .ty = origin.y },
        .local_color = color,
    };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;
const Font = @import("../font.zig").Font;

test "placeRun rejects unknown face_index on COLR fanout" {
    const allocator = testing.allocator;
    const font_data = @import("assets").noto_sans_regular;
    var font = try Font.init(font_data);
    var faces = try Faces.build(allocator, &.{.{ .font = &font, .font_id = 0 }});
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
        .font_id = 0,
    }};
    const shaped = ShapedText{
        .allocator = allocator,
        .glyphs = fake_glyphs[0..],
    };
    try testing.expectError(error.UnknownFaceIndex, placeRunAlloc(allocator, &shaped, &faces, .{
        .baseline = .{ .x = 0, .y = 0 },
        .em = 16,
        .colr = true,
    }));
}

test "autohint mode key is independent of policy" {
    const y_policy: policy_mod.AutohintPolicy = .{
        .y = .{ .@"align" = .blue_zones },
    };
    const xy_policy: policy_mod.AutohintPolicy = .{
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
    var faces = try Faces.build(allocator, &.{.{ .font = &font, .font_id = 0 }});
    defer faces.deinit();
    var shaped = try faces_mod.shape(allocator, &faces, "abc", .{});
    defer shaped.deinit();
    try testing.expect(shaped.glyphs.len == 3);

    // unhinted: em scale, unhinted namespace, natural (unsnapped) pen.
    {
        const shapes = try placeRunAlloc(allocator, &shaped, null, .{ .baseline = .{ .x = 5, .y = 30 }, .em = 16 });
        defer allocator.free(shapes);
        try testing.expect(shapes[0].key.namespace == record_key.ns.unhinted_glyph);
        try testing.expectEqual(@as(f32, 16), shapes[0].local_transform.xx);
        try testing.expectApproxEqAbs(@as(f32, 5), shapes[0].local_transform.tx, 1e-5);
    }

    // tt_hint: em/ppem_px scale, hinted namespace, columns = integer + uniform.
    {
        const ppem: u32 = 13 * 64; // ppem_px = 13, em = 16 -> scale = 16/13
        const shapes = try placeRunAlloc(allocator, &shaped, null, .{
            .baseline = .{ .x = 5, .y = 30 },
            .em = 16,
            .mode = .{ .tt_hint = .{ .ppem_26_6 = ppem } },
            .snap = .columns,
            .world_to_pixel = Transform2D{}, // identity: world == device
        });
        defer allocator.free(shapes);
        try testing.expect(shapes[0].key.namespace == record_key.ns.tt_hinted_glyph);
        try testing.expectApproxEqAbs(@as(f32, 16.0 / 13.0), shapes[0].local_transform.xx, 1e-4);
        const x0 = shapes[0].local_transform.tx;
        const x1 = shapes[1].local_transform.tx;
        const x2 = shapes[2].local_transform.tx;
        try testing.expectEqual(@round(x0), x0); // origins on the grid
        try testing.expectEqual(@round(x1 - x0), x1 - x0); // integer advance
        try testing.expectApproxEqAbs(x1 - x0, x2 - x1, 1e-4); // uniform columns
    }

    // autohint: em scale, policy-independent key, explicit draw-time policy.
    const policy: policy_mod.AutohintPolicy = .{
        .x = .{ .@"align" = .grid },
        .y = .{ .@"align" = .blue_zones },
    };
    {
        const shapes = try placeRunAlloc(allocator, &shaped, null, .{
            .baseline = .{ .x = 5, .y = 30 },
            .em = 16,
            .mode = .{ .autohint = policy },
        });
        defer allocator.free(shapes);
        try testing.expect(shapes[0].key.namespace == record_key.ns.autohint_glyph);
        try testing.expectEqual(@as(f32, 16), shapes[0].local_transform.xx);
        try testing.expectEqualDeep(policy, shapes[0].autohint_policy.?);
    }

    // origins: each pen lands on an integer device pixel.
    {
        const shapes = try placeRunAlloc(allocator, &shaped, null, .{
            .baseline = .{ .x = 5.4, .y = 30.6 },
            .em = 16,
            .mode = .{ .autohint = policy },
            .snap = .origins,
            .world_to_pixel = Transform2D{},
        });
        defer allocator.free(shapes);
        for (shapes) |s| try testing.expectEqual(@round(s.local_transform.tx), s.local_transform.tx);
    }
}

test "placeRun requires an explicit transform for snapping" {
    const shaped = ShapedText{ .allocator = testing.allocator, .glyphs = &.{} };
    try testing.expectError(error.MissingWorldToPixel, placeRun(&.{}, &shaped, null, .{
        .baseline = .{ .x = 0, .y = 0 },
        .em = 16,
        .snap = .origins,
    }));
}

test "placeRun validates numeric inputs, hint modes, and column transforms" {
    var glyphs = [_]ShapedText.Glyph{.{
        .face_index = 0,
        .glyph_id = 1,
        .x_offset = 0,
        .y_offset = 0,
        .x_advance = 0.5,
        .y_advance = 0,
        .source_start = 0,
        .source_end = 1,
        .font_id = 0,
    }};
    const shaped = ShapedText{ .allocator = testing.allocator, .glyphs = &glyphs };
    try testing.expectError(error.InvalidEm, placeRun(&.{}, &shaped, null, .{
        .baseline = .{ .x = 0, .y = 0 },
        .em = 0,
    }));
    try testing.expectError(error.InvalidColor, placeRun(&.{}, &shaped, null, .{
        .baseline = .{ .x = 0, .y = 0 },
        .em = 16,
        .color = .{ std.math.nan(f32), 1, 1, 1 },
    }));
    try testing.expectError(error.InvalidColor, placeRun(&.{}, &shaped, null, .{
        .baseline = .{ .x = 0, .y = 0 },
        .em = 16,
        .color = .{ -2, 4, 8, 1.01 },
    }));
    try testing.expectError(error.InvalidHintMode, placeRun(&.{}, &shaped, null, .{
        .baseline = .{ .x = 0, .y = 0 },
        .em = 16,
        .mode = .{ .tt_hint = .{ .ppem_26_6 = 0 } },
    }));
    try testing.expectError(error.UnsupportedColumnsTransform, placeRun(&.{}, &shaped, null, .{
        .baseline = .{ .x = 0, .y = 0 },
        .em = 16,
        .snap = .columns,
        .world_to_pixel = Transform2D.rotate(0.25),
    }));

    glyphs[0].x_advance = std.math.inf(f32);
    try testing.expectError(error.InvalidPlacement, placeRun(&.{}, &shaped, null, .{
        .baseline = .{ .x = 0, .y = 0 },
        .em = 16,
    }));
}

test "placeRun rejects derived overflow before touching output" {
    var glyphs = [_]ShapedText.Glyph{
        .{ .face_index = 0, .glyph_id = 1, .x_offset = 0, .y_offset = 0, .x_advance = 1, .y_advance = 0, .source_start = 0, .source_end = 1, .font_id = 0 },
        .{ .face_index = 0, .glyph_id = 2, .x_offset = std.math.floatMax(f32), .y_offset = 0, .x_advance = 1, .y_advance = 0, .source_start = 1, .source_end = 2, .font_id = 0 },
    };
    const shaped = ShapedText{ .allocator = testing.allocator, .glyphs = &glyphs };
    const sentinel = Shape{
        .key = record_key.unhintedGlyph(99, 99),
        .local_transform = .{ .tx = 1234, .ty = 5678 },
        .local_color = .{ 9, 8, 7, 1 },
    };
    var out = [_]Shape{ sentinel, sentinel };

    try testing.expectError(error.InvalidPlacement, placeRun(&out, &shaped, null, .{
        .baseline = .zero,
        .em = 2,
    }));
    try testing.expectEqualDeep(sentinel, out[0]);
    try testing.expectEqualDeep(sentinel, out[1]);

    glyphs[1].x_offset = 0;
    try testing.expectError(error.InvalidPlacement, placeRun(&out, &shaped, null, .{
        .baseline = .{ .x = std.math.floatMax(f32), .y = 0 },
        .em = 2,
        .snap = .origins,
        .world_to_pixel = .{ .xx = 2, .yy = 1 },
    }));
    try testing.expectEqualDeep(sentinel, out[0]);

    try testing.expectError(error.InvalidPlacement, placeRun(&out, &shaped, null, .{
        .baseline = .zero,
        .em = std.math.floatMax(f32),
        .snap = .columns,
        .world_to_pixel = .{ .xx = 2, .yy = 1 },
    }));
    try testing.expectEqualDeep(sentinel, out[0]);

    try testing.expectError(error.InvalidEm, placeRun(&out, &shaped, null, .{
        .baseline = .zero,
        .em = std.math.floatMax(f32),
        .mode = .{ .tt_hint = .{ .ppem_26_6 = 1 } },
    }));
    try testing.expectEqualDeep(sentinel, out[0]);
}

test "column snapping rejects proportional advances" {
    var glyphs = [_]ShapedText.Glyph{
        .{ .face_index = 0, .glyph_id = 1, .x_offset = 0, .y_offset = 0, .x_advance = 0.5, .y_advance = 0, .source_start = 0, .source_end = 1, .font_id = 0 },
        .{ .face_index = 0, .glyph_id = 2, .x_offset = 0.5, .y_offset = 0, .x_advance = 0.6, .y_advance = 0, .source_start = 1, .source_end = 2, .font_id = 0 },
    };
    const shaped = ShapedText{ .allocator = testing.allocator, .glyphs = &glyphs };
    try testing.expectError(error.NonMonospaceColumns, placeRun(&.{}, &shaped, null, .{
        .baseline = .{ .x = 0, .y = 0 },
        .em = 16,
        .snap = .columns,
        .world_to_pixel = .identity,
    }));
}

test "y-up placement mirrors y-down about the baseline" {
    const allocator = testing.allocator;
    var fake_glyphs = [_]ShapedText.Glyph{.{
        .face_index = 0,
        .glyph_id = 7,
        .x_offset = 0.25,
        .y_offset = -0.5, // "raised" in the stored y-down convention
        .x_advance = 0.6,
        .y_advance = 0,
        .source_start = 0,
        .source_end = 1,
        .font_id = 0,
    }};
    const shaped = ShapedText{ .allocator = allocator, .glyphs = fake_glyphs[0..] };

    const down = try placeRunAlloc(allocator, &shaped, null, .{
        .baseline = .{ .x = 10, .y = 100 },
        .em = 16,
    });
    defer allocator.free(down);
    const up = try placeRunAlloc(allocator, &shaped, null, .{
        .baseline = .{ .x = 10, .y = 100 },
        .em = 16,
        .y_axis = .up,
    });
    defer allocator.free(up);

    // x is unaffected; the y column and vertical offset flip sign.
    try testing.expectEqual(down[0].local_transform.xx, up[0].local_transform.xx);
    try testing.expectEqual(down[0].local_transform.tx, up[0].local_transform.tx);
    try testing.expectEqual(@as(f32, -16), down[0].local_transform.yy);
    try testing.expectEqual(@as(f32, 16), up[0].local_transform.yy);
    // Stored y_offset -0.5 raises the glyph: scene y shrinks when y is
    // down, grows when y is up — mirrored about the baseline.
    try testing.expectApproxEqAbs(@as(f32, 100 - 8), down[0].local_transform.ty, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 100 + 8), up[0].local_transform.ty, 1e-5);
}
