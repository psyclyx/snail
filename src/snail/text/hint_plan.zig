const std = @import("std");

const hint_context = @import("hint_context.zig");
const range_mod = @import("../range.zig");
const shape_mod = @import("shape.zig");
const types_mod = @import("types.zig");
const vec = @import("../math/vec.zig");

const HintedGlyphValue = hint_context.HintedGlyphValue;
const Range = range_mod.Range;
const ShapedText = types_mod.ShapedText;
const TextAtlas = @import("atlas.zig").TextAtlas;
const TextPlacement = types_mod.TextPlacement;
const Transform2D = vec.Transform2D;
const Vec2 = vec.Vec2;

const glyphPlacementTransform = shape_mod.glyphPlacementTransform;
const shapedPenAt = shape_mod.shapedPenAt;

pub const HintedPlacement = struct {
    shaped_index: usize,
    face_index: u16,
    glyph_id: u16,
    transform: Transform2D,
};

pub const HintPlanStats = struct {
    glyph_count: usize = 0,
    advance: Vec2 = .zero,
};

pub const TextHintRunPlan = struct {
    allocator: std.mem.Allocator,
    placements: []HintedPlacement,
    hinted_glyphs: []?*const HintedGlyphValue,
    stats: HintPlanStats,

    pub fn deinit(self: *TextHintRunPlan) void {
        self.allocator.free(self.placements);
        self.allocator.free(self.hinted_glyphs);
        self.* = undefined;
    }
};

pub const PlanRunOptions = struct {
    atlas: *const TextAtlas,
    shaped: *const ShapedText,
    glyphs: Range = .{},
    placement: TextPlacement,
    /// One cached hinted glyph value per glyph in the resolved range.
    hinted_glyphs: []const ?*const HintedGlyphValue,
};

pub fn planRun(allocator: std.mem.Allocator, options: PlanRunOptions) !TextHintRunPlan {
    if (options.shaped.config != options.atlas.config) return error.WrongTextAtlasSnapshot;

    const range = options.glyphs.resolve(options.shaped.glyphs.len);
    const glyph_count = range.end - range.start;
    if (options.hinted_glyphs.len != glyph_count) return error.MissingHintedGlyph;

    const placements = try allocator.alloc(HintedPlacement, glyph_count);
    errdefer allocator.free(placements);

    const hinted_glyphs = try allocator.dupe(?*const HintedGlyphValue, options.hinted_glyphs);
    errdefer allocator.free(hinted_glyphs);

    var hinted_pen = Vec2.zero;
    for (placements, hinted_glyphs, 0..) |*out, hinted_glyph, local_index| {
        const hint = hinted_glyph orelse return error.MissingHintedGlyph;
        const shaped_index = range.start + local_index;
        const glyph = options.shaped.glyphs[shaped_index];
        const fc = &options.atlas.config.faces[glyph.face_index];
        const nominal_pen = shapedPenAt(options.shaped, shaped_index);
        const placement_delta = Vec2{
            .x = glyph.x_offset - nominal_pen.x,
            .y = glyph.y_offset - nominal_pen.y,
        };
        const x = options.placement.baseline.x + (hinted_pen.x + placement_delta.x) * options.placement.em;
        const y = options.placement.baseline.y + (hinted_pen.y + placement_delta.y) * options.placement.em;
        out.* = .{
            .shaped_index = shaped_index,
            .face_index = glyph.face_index,
            .glyph_id = glyph.glyph_id,
            .transform = glyphPlacementTransform(x, y, options.placement.em, fc.synthetic.skew_x),
        };
        hinted_pen = Vec2.add(hinted_pen, hint.advance);
    }

    return .{
        .allocator = allocator,
        .placements = placements,
        .hinted_glyphs = hinted_glyphs,
        .stats = .{
            .glyph_count = glyph_count,
            .advance = Vec2{
                .x = hinted_pen.x * options.placement.em,
                .y = hinted_pen.y * options.placement.em,
            },
        },
    };
}

test "hint run plan uses caller supplied advances" {
    const assets = @import("assets");
    const atlas_mod = @import("atlas.zig");

    var atlas = try atlas_mod.TextAtlas.init(std.testing.allocator, &.{
        .{ .data = assets.noto_sans_regular },
    });
    defer atlas.deinit();

    var shaped = try atlas.shapeText(std.testing.allocator, .{}, "AB");
    defer shaped.deinit();

    const values = [_]hint_context.HintedGlyphValue{
        .{
            .key = .{ .face_index = 0, .ppem_x_26_6 = 12 * 64, .ppem_y_26_6 = 12 * 64, .glyph_id = shaped.glyphs[0].glyph_id },
            .advance = .{ .x = 0.5, .y = 0 },
            .bbox = .{ .min = .zero, .max = .zero },
        },
        .{
            .key = .{ .face_index = 0, .ppem_x_26_6 = 12 * 64, .ppem_y_26_6 = 12 * 64, .glyph_id = shaped.glyphs[1].glyph_id },
            .advance = .{ .x = 0.25, .y = 0 },
            .bbox = .{ .min = .zero, .max = .zero },
        },
    };
    const hints = [_]?*const hint_context.HintedGlyphValue{
        &values[0],
        &values[1],
    };
    var plan = try planRun(std.testing.allocator, .{
        .atlas = &atlas,
        .shaped = &shaped,
        .placement = .{ .baseline = .{ .x = 10, .y = 20 }, .em = 12 },
        .hinted_glyphs = &hints,
    });
    defer plan.deinit();

    try std.testing.expectEqual(@as(usize, 2), plan.placements.len);
    try std.testing.expectApproxEqAbs(@as(f32, 9), plan.stats.advance.x, 1e-5);
    try std.testing.expect(plan.placements[1].transform.tx >= plan.placements[0].transform.tx + 5.9);
}
