const std = @import("std");

const snail = @import("../root.zig");
const build_options = @import("build_options");
const config_mod = @import("config.zig");
const types_mod = @import("types.zig");
const view_mod = @import("view.zig");

const Allocator = std.mem.Allocator;
const FaceConfig = config_mod.FaceConfig;
const FaceIndex = config_mod.FaceIndex;
const FaceView = view_mod.FaceView;
const ShapedText = types_mod.ShapedText;

pub fn isIdentityTransform(transform: snail.Transform2D) bool {
    return transform.xx == 1 and transform.xy == 0 and transform.tx == 0 and transform.yx == 0 and transform.yy == 1 and transform.ty == 0;
}

pub fn glyphPlacementTransform(x: f32, y: f32, font_size: f32, skew_x: f32) snail.Transform2D {
    return .{
        .xx = font_size,
        .xy = skew_x * font_size,
        .tx = x,
        .yx = 0,
        .yy = -font_size,
        .ty = y,
    };
}

pub const ShapeRunResult = struct {
    glyphs: []ShapedText.Glyph,
    advance_x: f32,
    advance_y: f32,
};

pub fn shapeRunForFace(
    allocator: Allocator,
    fc: *const FaceConfig,
    face_index: FaceIndex,
    text: []const u8,
    source_base: u32,
) !ShapeRunResult {
    if (text.len == 0) return .{ .glyphs = &.{}, .advance_x = 0, .advance_y = 0 };
    const inv_upem = 1.0 / @as(f32, @floatFromInt(fc.font.units_per_em));

    if (comptime build_options.enable_harfbuzz) {
        if (fc.hb_shaper) |hbs| {
            const shaped = hbs.shapeText(text);
            if (shaped.count == 0 or shaped.infos == null or shaped.positions == null)
                return .{ .glyphs = &.{}, .advance_x = 0, .advance_y = 0 };

            const out = try allocator.alloc(ShapedText.Glyph, shaped.count);
            errdefer allocator.free(out);

            var cursor_x: f32 = 0;
            var cursor_y: f32 = 0;
            for (0..shaped.count) |i| {
                const info = shaped.infos[i];
                const pos = shaped.positions[i];
                const cluster = @min(@as(u32, @intCast(info.cluster)), @as(u32, @intCast(text.len)));
                out[i] = .{
                    .face_index = face_index,
                    .glyph_id = @intCast(info.codepoint),
                    .x_offset = (cursor_x + @as(f32, @floatFromInt(pos.x_offset))) * inv_upem,
                    .y_offset = -(cursor_y + @as(f32, @floatFromInt(pos.y_offset))) * inv_upem,
                    .x_advance = @as(f32, @floatFromInt(pos.x_advance)) * inv_upem,
                    .y_advance = -@as(f32, @floatFromInt(pos.y_advance)) * inv_upem,
                    .source_start = source_base + cluster,
                    .source_end = source_base + @as(u32, @intCast(text.len)),
                };
                cursor_x += @as(f32, @floatFromInt(pos.x_advance));
                cursor_y += @as(f32, @floatFromInt(pos.y_advance));
            }

            return .{
                .glyphs = out,
                .advance_x = cursor_x * inv_upem,
                .advance_y = -cursor_y * inv_upem,
            };
        }
    }

    var cp_count: usize = 0;
    {
        const utf8_view = std.unicode.Utf8View.initUnchecked(text);
        var it = utf8_view.iterator();
        while (it.nextCodepoint()) |_| cp_count += 1;
    }
    if (cp_count == 0) return .{ .glyphs = &.{}, .advance_x = 0, .advance_y = 0 };

    const gids = try allocator.alloc(u16, cp_count);
    defer allocator.free(gids);
    const src_starts = try allocator.alloc(u32, cp_count);
    defer allocator.free(src_starts);
    const src_ends = try allocator.alloc(u32, cp_count);
    defer allocator.free(src_ends);

    var glyph_count: usize = 0;
    {
        const utf8_view = std.unicode.Utf8View.initUnchecked(text);
        var it = utf8_view.iterator();
        while (it.nextCodepointSlice()) |cp_slice| {
            const byte_pos = @intFromPtr(cp_slice.ptr) - @intFromPtr(text.ptr);
            const cp = std.unicode.utf8Decode(cp_slice) catch 0;
            gids[glyph_count] = fc.font.glyphIndex(@intCast(cp)) catch 0;
            src_starts[glyph_count] = source_base + @as(u32, @intCast(byte_pos));
            src_ends[glyph_count] = source_base + @as(u32, @intCast(byte_pos + cp_slice.len));
            glyph_count += 1;
        }
    }

    if (fc.shaper) |shaper| {
        glyph_count = shaper.applyLigaturesTracked(
            gids[0..glyph_count],
            src_starts[0..glyph_count],
            src_ends[0..glyph_count],
        ) catch glyph_count;
    }

    const out = try allocator.alloc(ShapedText.Glyph, glyph_count);
    errdefer allocator.free(out);

    var cursor_x: f32 = 0;
    var prev_gid: u16 = 0;
    for (gids[0..glyph_count], 0..) |gid, i| {
        if (gid == 0) {
            const advance = 500.0 * inv_upem;
            out[i] = .{
                .face_index = face_index,
                .glyph_id = 0,
                .x_offset = cursor_x,
                .y_offset = 0,
                .x_advance = advance,
                .y_advance = 0,
                .source_start = src_starts[i],
                .source_end = src_ends[i],
            };
            cursor_x += advance;
            prev_gid = 0;
            continue;
        }

        if (prev_gid != 0) {
            var kern: i16 = 0;
            if (fc.shaper) |shaper| kern = shaper.getKernAdjustment(prev_gid, gid) catch 0;
            if (kern == 0) kern = fc.font.getKerning(prev_gid, gid) catch 0;
            cursor_x += @as(f32, @floatFromInt(kern)) * inv_upem;
        }

        const advance = @as(f32, @floatFromInt(fc.font.advanceWidth(gid) catch 500)) * inv_upem;
        out[i] = .{
            .face_index = face_index,
            .glyph_id = gid,
            .x_offset = cursor_x,
            .y_offset = 0,
            .x_advance = advance,
            .y_advance = 0,
            .source_start = src_starts[i],
            .source_end = src_ends[i],
        };
        cursor_x += advance;
        prev_gid = gid;
    }

    return .{ .glyphs = out, .advance_x = cursor_x, .advance_y = 0 };
}

pub fn shapedGlyphAvailable(face_view: *const FaceView, glyph_id: u16) bool {
    if (glyph_id == 0) return true;
    if (face_view.getGlyph(glyph_id) != null) return true;
    if (face_view.getColrBase(glyph_id) != null) return true;
    var layers = face_view.colrLayers(glyph_id);
    if (layers.count() == 0) return false;
    var has_renderable_layer = false;
    while (layers.next()) |layer| {
        const info = face_view.getGlyph(layer.glyph_id) orelse return false;
        if (info.band_entry.h_band_count == 0 or info.band_entry.v_band_count == 0) return false;
        has_renderable_layer = true;
    }
    return has_renderable_layer;
}

pub fn glyphInstanceBudget(face_view: *const FaceView, glyph_id: u16) usize {
    if (glyph_id == 0) return 0;
    if (face_view.getColrBase(glyph_id) != null) return 1;

    var layer_it = face_view.colrLayers(glyph_id);
    const layer_count = layer_it.count();
    if (layer_count > 0) return layer_count;

    // Match `glyph_emit.hasRenderableBands`: a present-but-empty glyph
    // (e.g. space with `h_band_count == 0`) emits no instances, so it must
    // not contribute to the budget — otherwise PreparedScene over-allocates.
    const info = face_view.getGlyph(glyph_id) orelse return 0;
    if (info.band_entry.h_band_count == 0 or info.band_entry.v_band_count == 0) return 0;
    return 1;
}

pub fn shapedPenAt(shaped: *const ShapedText, glyph_index: usize) snail.Vec2 {
    var pen = snail.Vec2.zero;
    for (shaped.glyphs[0..@min(glyph_index, shaped.glyphs.len)]) |glyph| {
        pen.x += glyph.x_advance;
        pen.y += glyph.y_advance;
    }
    return pen;
}

pub fn shapedAdvanceForRange(shaped: *const ShapedText, range: snail.Range.Resolved) snail.Vec2 {
    var advance = snail.Vec2.zero;
    for (shaped.glyphs[range.start..range.end]) |glyph| {
        advance.x += glyph.x_advance;
        advance.y += glyph.y_advance;
    }
    return advance;
}

pub fn scaleAdvance(advance: snail.Vec2, em: f32) snail.Vec2 {
    return .{ .x = advance.x * em, .y = advance.y * em };
}
