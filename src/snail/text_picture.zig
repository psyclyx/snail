//! Build a `Picture` from a `ShapedText` run.
//!
//! Bridges the existing shaping pipeline (`TextAtlas.shapeText`) to the new
//! `Picture` model: each shaped glyph becomes one `Shape` with a transform
//! placing it at its pen position in world coordinates.
//!
//! COLR / SVG / paint-bearing glyphs are out of scope here — those need
//! Picture-construction-layer expansion (Q5) and paint records, which land
//! in later phases. This function emits one `Shape` per shaped glyph with
//! an unhinted-glyph key; emoji glyphs from a color font will resolve to
//! their base outline if extracted, or fail at emit time if their key
//! isn't in the atlas.

const std = @import("std");

const math = @import("math/vec.zig");
const picture_mod = @import("picture.zig");
const shape_mod = @import("shape.zig");
const record_key_mod = @import("record_key.zig");
const types = @import("text/types.zig");
const font_mod = @import("font.zig");

pub const ShapedText = types.ShapedText;
pub const Picture = picture_mod.Picture;
pub const Shape = shape_mod.Shape;
pub const Vec2 = math.Vec2;
pub const Transform2D = math.Transform2D;
pub const Font = font_mod.Font;

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
    var shapes: std.ArrayList(Shape) = .empty;
    defer shapes.deinit(allocator);

    for (shaped.glyphs) |g| {
        const face_index_int: usize = @intCast(g.face_index);
        if (face_index_int >= options.face_to_font_id.len) return error.UnknownFaceIndex;
        const font_id = options.face_to_font_id[face_index_int];

        const pen_x = options.baseline.x + options.em * g.x_offset;
        const pen_y = options.baseline.y + options.em * g.y_offset;
        const transform: Transform2D = .{
            .xx = options.em,
            .xy = 0,
            .tx = pen_x,
            .yx = 0,
            .yy = -options.em,
            .ty = pen_y,
        };

        // COLR fanout. Each layer becomes its own Shape with the layer's
        // CPAL color (or `options.color` for the "foreground" sentinel
        // palette index 0xFFFF) and the same transform.
        var emitted = false;
        if (options.colr_fonts) |fonts| {
            if (face_index_int < fonts.len) {
                var iter = fonts[face_index_int].colrLayers(g.glyph_id);
                if (iter.count() > 0) {
                    while (iter.next()) |layer| {
                        const layer_color: [4]f32 = if (layer.color[0] < 0)
                            options.color
                        else
                            layer.color;
                        try shapes.append(allocator, .{
                            .key = record_key_mod.unhintedGlyph(font_id, layer.glyph_id),
                            .local_transform = transform,
                            .local_color = layer_color,
                        });
                    }
                    emitted = true;
                }
            }
        }
        if (!emitted) {
            try shapes.append(allocator, .{
                .key = record_key_mod.unhintedGlyph(font_id, g.glyph_id),
                .local_transform = transform,
                .local_color = options.color,
            });
        }
    }

    return Picture.from(allocator, shapes.items);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

test "shapedRunPicture builds one shape per shaped glyph" {
    const allocator = testing.allocator;
    const snail = @import("root.zig");
    const font_data = @import("assets").noto_sans_regular;

    var atlas = try snail.TextAtlas.init(allocator, &.{
        .{ .data = font_data },
    });
    defer atlas.deinit();
    if (try atlas.ensureText(.{}, "Hi")) |next| {
        atlas.deinit();
        atlas = next;
    }

    var shaped = try atlas.shapeText(allocator, .{}, "Hi");
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
        .config = undefined,
        .glyphs = fake_glyphs[0..],
    };
    try testing.expectError(error.UnknownFaceIndex, shapedRunPicture(allocator, &shaped, .{
        .baseline = .{ .x = 0, .y = 0 },
        .em = 16,
        .face_to_font_id = &.{0},
    }));
}
