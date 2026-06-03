//! Build a `Picture` from a `Shaper.shape` run.
//!
//! Each shaped glyph becomes one `Shape` with a transform placing it at
//! its pen position in world coordinates. COLR base glyphs expand into N
//! shapes when `colr_fonts` is supplied; non-COLR glyphs fall back to the
//! run color. Hinted variants use `hintedShapedRunPicture`.

const std = @import("std");

const math = @import("../math/vec.zig");
const picture_mod = @import("../picture.zig");
const shape_mod = @import("shape.zig");
const record_key_mod = @import("../atlas/record_key.zig");
const text_mod = @import("../text.zig");
const font_mod = @import("../font.zig");
const hinter_mod = @import("../font/hinter.zig");

pub const ShapedText = text_mod.ShapedText;
pub const Picture = picture_mod.Picture;
pub const Shape = shape_mod.Shape;
pub const Vec2 = math.Vec2;
pub const Transform2D = math.Transform2D;
pub const Font = font_mod.Font;
pub const Hinter = hinter_mod.Hinter;
pub const HintPpem = hinter_mod.HintPpem;

pub const ShapedRunOptions = struct {
    /// Pen baseline in world coordinates.
    baseline: Vec2,
    /// Em size in world units (i.e. the px font size).
    em: f32,
    /// Color applied uniformly to every glyph in the run.
    color: [4]f32 = .{ 1, 1, 1, 1 },
    /// Maps `ShapedText.Glyph.face_index` to the `font_id` used in
    /// `RecordKey`s. Caller provides this so the atlas knows which font
    /// each key belongs to. Length must cover every face_index in the run.
    face_to_font_id: []const u32,
    /// Optional fonts array for COLR fanout. When provided, COLR base
    /// glyphs expand into N shapes (one per layer) with the CPAL palette
    /// color on each. Indexed by `face_index`. Glyphs whose face has no
    /// matching font, or that aren't COLR base glyphs, render as a single
    /// shape with `options.color` (the default outline path).
    colr_fonts: ?[]const *const Font = null,
};

pub const ShapedRunError = error{
    /// A glyph references a `face_index` outside `face_to_font_id`.
    UnknownFaceIndex,
} || std.mem.Allocator.Error;

/// Build a Picture by placing each shaped glyph at its pen position.
/// COLR base glyphs expand into N shapes when `options.colr_fonts` is set.
pub fn shapedRunPicture(
    allocator: std.mem.Allocator,
    shaped: *const ShapedText,
    options: ShapedRunOptions,
) ShapedRunError!Picture {
    // Fast path: when no COLR expansion is possible, every glyph becomes
    // exactly one shape. Allocate the final buffer directly at the right
    // size and hand it off to Picture — no ArrayList growth, no Picture.from
    // alloc+memcpy.
    if (options.colr_fonts == null) {
        const buf = try allocator.alloc(Shape, shaped.glyphs.len);
        errdefer allocator.free(buf);
        for (shaped.glyphs, 0..) |g, i| {
            const face_index_int: usize = @intCast(g.face_index);
            if (face_index_int >= options.face_to_font_id.len) return error.UnknownFaceIndex;
            buf[i] = makeShape(g, options, options.face_to_font_id[face_index_int], g.glyph_id, options.color);
        }
        return Picture.fromOwnedSlice(allocator, buf);
    }

    // COLR-capable slow path: shape count varies per glyph. Pre-size the
    // ArrayList to at least `shaped.glyphs.len` to skip the early growth
    // reallocs; let it grow if any glyph fans out.
    var shapes: std.ArrayList(Shape) = .empty;
    defer shapes.deinit(allocator);
    try shapes.ensureTotalCapacity(allocator, shaped.glyphs.len);

    for (shaped.glyphs) |g| {
        const face_index_int: usize = @intCast(g.face_index);
        if (face_index_int >= options.face_to_font_id.len) return error.UnknownFaceIndex;
        const font_id = options.face_to_font_id[face_index_int];

        // COLR fanout. Each layer becomes its own Shape keyed by the
        // *layer* glyph id (not `g.glyph_id`) with the layer's CPAL
        // color, or `options.color` for the foreground sentinel palette
        // index 0xFFFF.
        var emitted = false;
        const fonts = options.colr_fonts.?;
        if (face_index_int < fonts.len) {
            var iter = fonts[face_index_int].colrLayers(g.glyph_id);
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
        .key = record_key_mod.unhintedGlyph(font_id, glyph_id),
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
    /// Pen baseline in world coordinates (pixel-space).
    baseline: Vec2,
    /// Em size in pixels. Used to scale the shaper's em-relative glyph
    /// offsets into pixel-space pen positions.
    em: f32,
    /// 26.6 fixed-point ppem the glyphs were hinted at — the same value
    /// passed to the `Hinter` and used to key atlas entries under
    /// `recordKey.hintedGlyph(font_id, glyph_id, ppem_26_6)`. Callers must
    /// pass exactly the ppem they hinted at, *not* `em * 64`: under zoom
    /// the two differ because hinting scales by zoom, but per-glyph layout
    /// still uses the unscaled em.
    ppem_26_6: u32,
    color: [4]f32 = .{ 1, 1, 1, 1 },
    /// Maps `ShapedText.Glyph.face_index` to the `font_id` used in
    /// `RecordKey`s.
    face_to_font_id: []const u32,
};

/// Build a Picture for hinted text. Caller is responsible for having
/// already inserted hinted curves into the atlas under
/// `recordKey.hintedGlyph(font_id, glyph_id, ppem_26_6)` keys.
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
        const face_index_int: usize = @intCast(g.face_index);
        if (face_index_int >= options.face_to_font_id.len) return error.UnknownFaceIndex;
        const font_id = options.face_to_font_id[face_index_int];
        const pen_x = options.baseline.x + options.em * g.x_offset;
        const pen_y = options.baseline.y + options.em * g.y_offset;
        buf[i] = .{
            .key = record_key_mod.hintedGlyph(font_id, g.glyph_id, ppem_26_6),
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

test "shapedRunPicture builds one shape per shaped glyph" {
    const allocator = testing.allocator;
    const snail = @import("../root.zig");
    const font_data = @import("assets").noto_sans_regular;

    var shaper = try snail.Shaper.init(allocator, &.{.{ .data = font_data }});
    defer shaper.deinit();

    var shaped = try shaper.shape(allocator, .{}, "Hi");
    defer shaped.deinit();
    try testing.expect(shaped.glyphs.len == 2);

    var pic = try shapedRunPicture(allocator, &shaped, .{
        .baseline = .{ .x = 10, .y = 40 },
        .em = 24,
        .color = .{ 1, 1, 1, 1 },
        .face_to_font_id = &.{0},
    });
    defer pic.deinit();

    try testing.expectEqual(@as(usize, 2), pic.shapes.len);
    // First glyph at x_offset=0 should land at the baseline x.
    try testing.expectApproxEqAbs(@as(f32, 10), pic.shapes[0].local_transform.tx, 1e-5);
    try testing.expectEqual(@as(f32, 24), pic.shapes[0].local_transform.xx);
    try testing.expectEqual(@as(f32, -24), pic.shapes[0].local_transform.yy);
    try testing.expect(pic.shapes[0].key.namespace == record_key_mod.ns.unhinted_glyph);
}

test "hintedShapedRunPicture builds shapes for hinted glyph keys" {
    const allocator = testing.allocator;
    const snail = @import("../root.zig");
    const font_data = @import("assets").noto_sans_regular;

    var shaper = try snail.Shaper.init(allocator, &.{.{ .data = font_data }});
    defer shaper.deinit();
    var shaped = try shaper.shape(allocator, .{}, "Hi");
    defer shaped.deinit();
    try testing.expect(shaped.glyphs.len == 2);

    const expected_ppem: u32 = @intFromFloat(@round(14.0 * 64.0));
    var pic = try hintedShapedRunPicture(allocator, &shaped, .{
        .baseline = .{ .x = 5, .y = 32 },
        .em = 14,
        .ppem_26_6 = expected_ppem,
        .color = .{ 1, 1, 1, 1 },
        .face_to_font_id = &.{0},
    });
    defer pic.deinit();

    try testing.expectEqual(@as(usize, 2), pic.shapes.len);
    try testing.expectEqual(record_key_mod.ns.hinted_glyph, pic.shapes[0].key.namespace);
    try testing.expectEqual(expected_ppem, pic.shapes[0].key.c);
    try testing.expectApproxEqAbs(@as(f32, 1), pic.shapes[0].local_transform.xx, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, -1), pic.shapes[0].local_transform.yy, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 5), pic.shapes[0].local_transform.tx, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 32), pic.shapes[0].local_transform.ty, 1e-5);
}

test "hinted curves render through new API CPU draw" {
    const build_options = @import("build_options");
    if (!build_options.enable_cpu) return error.SkipZigTest;
    const allocator = testing.allocator;
    const snail = @import("../root.zig");
    const font_data = @import("assets").noto_sans_regular;

    var font = try Font.init(font_data);
    var hinter = Hinter.init(allocator, &font) catch return error.SkipZigTest;
    defer hinter.deinit();

    const ppem_26_6: u32 = @intFromFloat(@round(16.0 * 64.0));
    const ppem = HintPpem.uniform(ppem_26_6);
    const gid = try font.glyphIndex('A');

    var hinted = hinter.hint(allocator, allocator, gid, ppem) catch return error.SkipZigTest;
    defer hinted.deinit();
    if (hinted.isEmpty()) return error.SkipZigTest;

    var pool = try snail.PagePool.init(allocator, .{
        .max_layers = 2,
        .curve_words_per_page = 1 << 16,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    const key = record_key_mod.hintedGlyph(0, gid, ppem_26_6);
    var atlas = try snail.Atlas.from(allocator, pool, &.{.{ .key = key, .curves = hinted }});
    defer atlas.deinit();

    var cache = try snail.CpuBackendCache.init(allocator, pool, .{ .max_bindings = 1, .layer_info_height = 8, .max_images = 0 });
    defer cache.deinit();
    var bindings: [1]snail.Binding = undefined;
    try cache.upload(allocator, &.{&atlas}, &bindings);
    const binding = bindings[0];

    const W: u32 = 32;
    const H: u32 = 32;
    const STRIDE: u32 = W * 4;
    const px = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(px);
    @memset(px, 0);

    // Translate-only transform: hinted curves are already in pixel space.
    const shape = @import("shape.zig").Shape{
        .key = key,
        .local_transform = .{ .xx = 1, .yy = -1, .tx = 6, .ty = 24 },
        .local_color = .{ 1, 1, 1, 1 },
    };
    var picture = try Picture.from(allocator, &.{shape});
    defer picture.deinit();

    const emit_mod = @import("emit.zig");
    const draw_records_mod = @import("draw_records.zig");
    const words = try allocator.alloc(u32, emit_mod.wordBudget(&picture, 0));
    defer allocator.free(words);
    var segs: [2]draw_records_mod.DrawSegment = undefined;
    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try emit_mod.emit(words, segs[0..], &wlen, &slen, binding, &atlas, &picture, .identity, .{ 1, 1, 1, 1 });

    var renderer = snail.CpuRenderer.init(px.ptr, W, H, STRIDE);
    const wf: f32 = @floatFromInt(W);
    const hf: f32 = @floatFromInt(H);
    const state = snail.DrawState{
        .surface = .{ .pixel_width = wf, .pixel_height = hf, .encoding = .srgb },
        .raster = .{ .subpixel_order = .none, .coverage_transfer = .{ .exponent = 1.0 } },
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
    };
    try snail.drawCpu(&renderer, state, .{ .words = words[0..wlen], .segments = segs[0..slen] }, &.{&cache});

    var any_drawn = false;
    for (px) |b| if (b != 0) {
        any_drawn = true;
        break;
    };
    try testing.expect(any_drawn);
}

test "shapedRunPicture rejects unknown face_index" {
    const allocator = testing.allocator;
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
    try testing.expectError(error.UnknownFaceIndex, shapedRunPicture(allocator, &shaped, .{
        .baseline = .{ .x = 0, .y = 0 },
        .em = 16,
        .face_to_font_id = &.{0},
    }));
}
