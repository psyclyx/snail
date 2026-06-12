//! Build a `Picture` from a `snail.shape()` run.
//!
//! Each shaped glyph becomes one `Shape` with a transform placing it at
//! its pen position in world coordinates. COLR base glyphs expand into N
//! shapes when COLR is enabled; non-COLR glyphs fall back to the run color.
//! Hinted variants use `hintedShapedRunPicture`.
//!
//! Pixel-grid snapping is the caller's responsibility — call
//! `snail.snap.baseline(world_baseline, world_to_pixel)` to get a snapped
//! baseline and pass *that* to these builders. The library does not bake
//! a "I'm a hinted run, snap me" mode into the Picture, because snapping
//! at draw time would tie Picture to a particular world transform; pure
//! caller-side snapping keeps the Picture content-only and cacheable.

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
    // alloc+memcpy.
    if (!options.colr) {
        const buf = try allocator.alloc(Shape, shaped.glyphs.len);
        errdefer allocator.free(buf);
        for (shaped.glyphs, 0..) |g, i| {
            const fi: usize = @intCast(g.face_index);
            if (fi >= faces.faceCount()) return error.UnknownFaceIndex;
            buf[i] = makeShape(g, options, g.font_id, g.glyph_id, options.color);
        }
        return Picture.fromOwnedSlice(allocator, buf);
    }

    // COLR-capable slow path: shape count varies per glyph. Pre-size to
    // glyph count and let it grow when a glyph fans out.
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
    faces: *const Faces,
    options: HintedShapedRunOptions,
) ShapedRunError!Picture {
    // Hinted text never fans out — one shape per glyph. Allocate the
    // final buffer directly at the right size, same pattern as the
    // non-COLR `shapedRunPicture` fast path.
    const ppem_26_6 = options.ppem_26_6;
    const ppem_px = @as(f32, @floatFromInt(ppem_26_6)) / 64.0;
    const scale: f32 = if (ppem_px > 0.0) options.em / ppem_px else 1.0;

    const buf = try allocator.alloc(Shape, shaped.glyphs.len);
    errdefer allocator.free(buf);

    for (shaped.glyphs, 0..) |g, i| {
        const fi: usize = @intCast(g.face_index);
        if (fi >= faces.faceCount()) return error.UnknownFaceIndex;
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
    var pic = try hintedShapedRunPicture(allocator, &shaped, &faces, .{
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
    var pic = try hintedShapedRunPicture(allocator, &shaped, &faces, .{
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

test "shapedRunPicture rejects unknown face_index" {
    const allocator = testing.allocator;
    const font_data = @import("assets").noto_sans_regular;
    var font = try Font.init(font_data);
    var faces = try Faces.build(allocator, &.{.{ .font = &font }});
    defer faces.deinit();

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
    }));
}
