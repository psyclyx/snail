const std = @import("std");

const build_options = @import("build_options");
const config_mod = @import("config.zig");
const types_mod = @import("types.zig");
const vec = @import("../math/vec.zig");
const view_mod = @import("view.zig");

const Allocator = std.mem.Allocator;
const FaceConfig = config_mod.FaceConfig;
const FaceIndex = config_mod.FaceIndex;
const FaceView = view_mod.FaceView;
const MissingGlyphReplacement = config_mod.MissingGlyphReplacement;
const ShapedText = types_mod.ShapedText;
const Transform2D = vec.Transform2D;
const Vec2 = vec.Vec2;

pub fn isIdentityTransform(transform: Transform2D) bool {
    return transform.xx == 1 and transform.xy == 0 and transform.tx == 0 and transform.yx == 0 and transform.yy == 1 and transform.ty == 0;
}

pub fn glyphPlacementTransform(x: f32, y: f32, font_size: f32, skew_x: f32) Transform2D {
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

const FallbackGlyphRun = struct {
    gids: []u16,
    src_starts: []u32,
    src_ends: []u32,
    glyph_count: usize,

    fn deinit(self: *FallbackGlyphRun, allocator: Allocator) void {
        allocator.free(self.gids);
        allocator.free(self.src_starts);
        allocator.free(self.src_ends);
        self.* = undefined;
    }
};

fn emptyShapeRun() ShapeRunResult {
    return .{ .glyphs = &.{}, .advance_x = 0, .advance_y = 0 };
}

fn shapeRunWithHarfbuzz(
    allocator: Allocator,
    fc: *const FaceConfig,
    face_index: FaceIndex,
    text: []const u8,
    source_base: u32,
    inv_upem: f32,
    missing_replacement: ?u16,
) !?ShapeRunResult {
    if (comptime build_options.enable_harfbuzz) {
        if (fc.hb_shaper) |hbs| {
            const shaped = hbs.shapeText(text);
            if (shaped.count == 0 or shaped.infos == null or shaped.positions == null)
                return emptyShapeRun();

            const out = try allocator.alloc(ShapedText.Glyph, shaped.count);
            errdefer allocator.free(out);

            var cursor_x: f32 = 0;
            var cursor_y: f32 = 0;
            for (0..shaped.count) |i| {
                const info = shaped.infos[i];
                const pos = shaped.positions[i];
                const cluster = @min(@as(u32, @intCast(info.cluster)), @as(u32, @intCast(text.len)));
                const raw_gid: u16 = @intCast(info.codepoint);
                const glyph_id = replacementGlyphId(raw_gid, missing_replacement);
                const advance_x = harfbuzzAdvanceX(fc, raw_gid, glyph_id, pos.x_advance);
                out[i] = .{
                    .face_index = face_index,
                    .glyph_id = glyph_id,
                    .x_offset = (cursor_x + @as(f32, @floatFromInt(pos.x_offset))) * inv_upem,
                    .y_offset = -(cursor_y + @as(f32, @floatFromInt(pos.y_offset))) * inv_upem,
                    .x_advance = advance_x * inv_upem,
                    .y_advance = -@as(f32, @floatFromInt(pos.y_advance)) * inv_upem,
                    .source_start = source_base + cluster,
                    .source_end = source_base + @as(u32, @intCast(text.len)),
                };
                cursor_x += advance_x;
                cursor_y += @as(f32, @floatFromInt(pos.y_advance));
            }

            return .{
                .glyphs = out,
                .advance_x = cursor_x * inv_upem,
                .advance_y = -cursor_y * inv_upem,
            };
        }
    }
    return null;
}

fn replacementForFace(replacement: ?MissingGlyphReplacement, face_index: FaceIndex) ?u16 {
    const value = replacement orelse return null;
    if (value.face_index != face_index) return null;
    return value.glyph_id;
}

fn replacementGlyphId(glyph_id: u16, missing_replacement: ?u16) u16 {
    if (glyph_id != 0) return glyph_id;
    return missing_replacement orelse 0;
}

fn harfbuzzAdvanceX(fc: *const FaceConfig, raw_gid: u16, glyph_id: u16, shaped_advance: i32) f32 {
    if (raw_gid != 0 or glyph_id == 0) return @floatFromInt(shaped_advance);
    return @floatFromInt(fc.font.advanceWidth(glyph_id) catch 500);
}

fn countUtf8Codepoints(text: []const u8) usize {
    var cp_count: usize = 0;
    const utf8_view = std.unicode.Utf8View.initUnchecked(text);
    var it = utf8_view.iterator();
    while (it.nextCodepoint()) |_| cp_count += 1;
    return cp_count;
}

fn buildFallbackGlyphRun(allocator: Allocator, fc: *const FaceConfig, text: []const u8, source_base: u32, cp_count: usize) !FallbackGlyphRun {
    const gids = try allocator.alloc(u16, cp_count);
    errdefer allocator.free(gids);
    const src_starts = try allocator.alloc(u32, cp_count);
    errdefer allocator.free(src_starts);
    const src_ends = try allocator.alloc(u32, cp_count);
    errdefer allocator.free(src_ends);

    var glyph_count: usize = 0;
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

    return .{
        .gids = gids,
        .src_starts = src_starts,
        .src_ends = src_ends,
        .glyph_count = glyph_count,
    };
}

fn applyFallbackLigatures(fc: *const FaceConfig, run: *FallbackGlyphRun) void {
    if (fc.shaper) |shaper| {
        run.glyph_count = shaper.applyLigaturesTracked(
            run.gids[0..run.glyph_count],
            run.src_starts[0..run.glyph_count],
            run.src_ends[0..run.glyph_count],
        ) catch run.glyph_count;
    }
}

fn fallbackKerning(fc: *const FaceConfig, prev_gid: u16, gid: u16) i16 {
    if (prev_gid == 0) return 0;
    var kern: i16 = 0;
    if (fc.shaper) |shaper| kern = shaper.getKernAdjustment(prev_gid, gid) catch 0;
    if (kern == 0) kern = fc.font.getKerning(prev_gid, gid) catch 0;
    return kern;
}

fn shapeFallbackGlyphs(
    allocator: Allocator,
    fc: *const FaceConfig,
    face_index: FaceIndex,
    run: FallbackGlyphRun,
    inv_upem: f32,
    missing_replacement: ?u16,
) !ShapeRunResult {
    const out = try allocator.alloc(ShapedText.Glyph, run.glyph_count);
    errdefer allocator.free(out);

    var cursor_x: f32 = 0;
    var prev_gid: u16 = 0;
    for (run.gids[0..run.glyph_count], 0..) |gid, i| {
        if (gid == 0) {
            const glyph_id = missing_replacement orelse 0;
            const advance = fallbackAdvance(fc, glyph_id, inv_upem);
            out[i] = .{
                .face_index = face_index,
                .glyph_id = glyph_id,
                .x_offset = cursor_x,
                .y_offset = 0,
                .x_advance = advance,
                .y_advance = 0,
                .source_start = run.src_starts[i],
                .source_end = run.src_ends[i],
            };
            cursor_x += advance;
            prev_gid = 0;
            continue;
        }

        cursor_x += @as(f32, @floatFromInt(fallbackKerning(fc, prev_gid, gid))) * inv_upem;

        const advance = @as(f32, @floatFromInt(fc.font.advanceWidth(gid) catch 500)) * inv_upem;
        out[i] = .{
            .face_index = face_index,
            .glyph_id = gid,
            .x_offset = cursor_x,
            .y_offset = 0,
            .x_advance = advance,
            .y_advance = 0,
            .source_start = run.src_starts[i],
            .source_end = run.src_ends[i],
        };
        cursor_x += advance;
        prev_gid = gid;
    }

    return .{ .glyphs = out, .advance_x = cursor_x, .advance_y = 0 };
}

fn fallbackAdvance(fc: *const FaceConfig, glyph_id: u16, inv_upem: f32) f32 {
    if (glyph_id == 0) return 500.0 * inv_upem;
    return @as(f32, @floatFromInt(fc.font.advanceWidth(glyph_id) catch 500)) * inv_upem;
}

fn shapeRunWithFallback(
    allocator: Allocator,
    fc: *const FaceConfig,
    face_index: FaceIndex,
    text: []const u8,
    source_base: u32,
    inv_upem: f32,
    missing_replacement: ?u16,
) !ShapeRunResult {
    const cp_count = countUtf8Codepoints(text);
    if (cp_count == 0) return emptyShapeRun();

    var run = try buildFallbackGlyphRun(allocator, fc, text, source_base, cp_count);
    defer run.deinit(allocator);
    applyFallbackLigatures(fc, &run);
    return shapeFallbackGlyphs(allocator, fc, face_index, run, inv_upem, missing_replacement);
}

pub fn shapeRunForFace(
    allocator: Allocator,
    fc: *const FaceConfig,
    face_index: FaceIndex,
    text: []const u8,
    source_base: u32,
    replacement: ?MissingGlyphReplacement,
) !ShapeRunResult {
    if (text.len == 0) return emptyShapeRun();
    const inv_upem = 1.0 / @as(f32, @floatFromInt(fc.font.units_per_em));
    const missing_replacement = replacementForFace(replacement, face_index);
    if (try shapeRunWithHarfbuzz(allocator, fc, face_index, text, source_base, inv_upem, missing_replacement)) |result| return result;
    return shapeRunWithFallback(allocator, fc, face_index, text, source_base, inv_upem, missing_replacement);
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

pub fn shapedPenAt(shaped: *const ShapedText, glyph_index: usize) Vec2 {
    var pen = Vec2.zero;
    for (shaped.glyphs[0..@min(glyph_index, shaped.glyphs.len)]) |glyph| {
        pen.x += glyph.x_advance;
        pen.y += glyph.y_advance;
    }
    return pen;
}

pub fn scaleAdvance(advance: Vec2, em: f32) Vec2 {
    return .{ .x = advance.x * em, .y = advance.y * em };
}
