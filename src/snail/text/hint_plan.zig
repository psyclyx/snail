const std = @import("std");

const range_mod = @import("../range.zig");
const shape_mod = @import("shape.zig");
const text_hint = @import("../render/format/text_hint.zig");
const types_mod = @import("types.zig");
const vec = @import("../math/vec.zig");

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
    upload_count: usize = 0,
    upload_bytes: usize = 0,
    advance: Vec2 = .zero,
};

pub const TextHintRunPlan = struct {
    allocator: std.mem.Allocator,
    placements: []HintedPlacement,
    uploads: []text_hint.UploadOp,
    stats: HintPlanStats,

    pub fn deinit(self: *TextHintRunPlan) void {
        self.allocator.free(self.placements);
        self.allocator.free(self.uploads);
        self.* = undefined;
    }
};

pub const PlanRunOptions = struct {
    atlas: *const TextAtlas,
    shaped: *const ShapedText,
    glyphs: Range = .{},
    placement: TextPlacement,
    /// One hinted advance per glyph in the resolved range, in em units.
    hinted_advances: []const Vec2,
    uploads: []const text_hint.UploadOp = &.{},
};

pub fn planRun(allocator: std.mem.Allocator, options: PlanRunOptions) !TextHintRunPlan {
    if (options.shaped.config != options.atlas.config) return error.WrongTextAtlasSnapshot;

    const range = options.glyphs.resolve(options.shaped.glyphs.len);
    const glyph_count = range.end - range.start;
    if (options.hinted_advances.len != glyph_count) return error.MissingHintedAdvance;

    const placements = try allocator.alloc(HintedPlacement, glyph_count);
    errdefer allocator.free(placements);

    var hinted_pen = Vec2.zero;
    for (placements, 0..) |*out, local_index| {
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
        hinted_pen = Vec2.add(hinted_pen, options.hinted_advances[local_index]);
    }

    const uploads = try allocator.dupe(text_hint.UploadOp, options.uploads);
    errdefer allocator.free(uploads);

    return .{
        .allocator = allocator,
        .placements = placements,
        .uploads = uploads,
        .stats = .{
            .glyph_count = glyph_count,
            .upload_count = uploads.len,
            .upload_bytes = text_hint.totalUploadBytes(uploads),
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

    const advances = [_]Vec2{
        .{ .x = 0.5, .y = 0 },
        .{ .x = 0.25, .y = 0 },
    };
    var plan = try planRun(std.testing.allocator, .{
        .atlas = &atlas,
        .shaped = &shaped,
        .placement = .{ .baseline = .{ .x = 10, .y = 20 }, .em = 12 },
        .hinted_advances = &advances,
        .uploads = &.{.{ .curve_deltas = .{ .byte_len = 128 } }},
    });
    defer plan.deinit();

    try std.testing.expectEqual(@as(usize, 2), plan.placements.len);
    try std.testing.expectEqual(@as(usize, 128), plan.stats.upload_bytes);
    try std.testing.expectApproxEqAbs(@as(f32, 9), plan.stats.advance.x, 1e-5);
    try std.testing.expect(plan.placements[1].transform.tx >= plan.placements[0].transform.tx + 5.9);
}
