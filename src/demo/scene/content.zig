//! Shared content builder for the screenshot demos.
//!
//! Each backend (`screenshot.zig` for CPU, `_gl`, `_gles30`, `_vulkan`)
//! used to inline ~300 lines of identical setup: shape text in six
//! scripts, extract curve data, lay out a card with a vector snail in
//! the corner, build the wordmark + tagline + multi-script sample row,
//! and assemble it into two atlases + two pictures (paths under text).
//!
//! `build()` produces those final four resources plus the `PagePool`
//! they share. The backend just spins up its own framebuffer / cache,
//! uploads the two atlases, and draws the two pictures.

const std = @import("std");
const snail = @import("snail");
const demo_support = @import("support");
const assets_data = @import("assets");
const banner_snail = @import("banner/snail.zig");

const Allocator = std.mem.Allocator;

pub const Content = struct {
    allocator: Allocator,
    pool: *snail.PagePool,
    paths_atlas: snail.Atlas,
    text_atlas: snail.Atlas,
    paths_picture: demo_support.Picture,
    text_picture: demo_support.Picture,

    pub fn deinit(self: *Content) void {
        self.text_picture.deinit();
        self.paths_picture.deinit();
        self.text_atlas.deinit();
        self.paths_atlas.deinit();
        self.pool.deinit();
    }
};

pub const TtHintOptions = struct {
    /// When non-null, the tagline + sample row are placed under hinted-glyph
    /// keys (`record_key.ttHintedGlyph(font_id, glyph_id, ppem_26_6)`) and the
    /// hinted curves are inserted into `text_atlas`. The TtHintVm must outlive
    /// `Content`.
    hinter: ?*snail.TtHintVm = null,
    /// TtHintVm face index (face_to_font_id slot) the TtHintVm was built for.
    /// Only one face is hinted; other glyphs in those runs fall back to
    /// unhinted entries.
    hint_face_index: u32 = 0,
    /// Pixel-per-em used by the hinter when running glyphs.
    hint_ppem_px: f32 = 13.0,
};

pub fn build(allocator: Allocator, width: u32, height: u32) !Content {
    return buildWithOptions(allocator, width, height, .{});
}

pub fn buildWithOptions(allocator: Allocator, width: u32, height: u32, tt_hint_opts: TtHintOptions) !Content {
    var font_regular = try snail.Font.init(assets_data.noto_sans_regular);
    var font_bold = try snail.Font.init(assets_data.noto_sans_bold);
    var font_arabic = try snail.Font.init(assets_data.noto_sans_arabic);
    var font_devanagari = try snail.Font.init(assets_data.noto_sans_devanagari);
    var font_thai = try snail.Font.init(assets_data.noto_sans_thai);
    var font_emoji = try snail.Font.init(assets_data.twemoji_mozilla);
    var fonts = [_]*snail.Font{ &font_regular, &font_bold, &font_arabic, &font_devanagari, &font_thai, &font_emoji };

    var faces = try snail.Faces.build(allocator, &.{
        .{ .font = &font_regular },
        .{ .font = &font_bold, .weight = .bold },
        .{ .font = &font_arabic, .fallback = true },
        .{ .font = &font_devanagari, .fallback = true },
        .{ .font = &font_thai, .fallback = true },
        .{ .font = &font_emoji, .fallback = true },
    });
    defer faces.deinit();

    const wordmark_text = "snail";
    const tagline_text = "GPU text and vector rendering";
    const sample_hello = "Hello";
    const sample_arabic = "\xd9\x85\xd8\xb1\xd8\xad\xd8\xa8\xd8\xa7"; // مرحبا
    const sample_devanagari = "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87"; // नमस्ते
    const sample_thai = "\xe0\xb8\xaa\xe0\xb8\xa7\xe0\xb8\xb1\xe0\xb8\xaa\xe0\xb8\x94\xe0\xb8\xb5"; // สวัสดี
    const sample_emoji = "\xe2\x9c\xa8\xf0\x9f\x8c\x8d"; // ✨🌍

    var shaped_wordmark = try snail.shape(allocator, &faces, wordmark_text, .{ .style = .{ .weight = .bold } });
    defer shaped_wordmark.deinit();
    var shaped_tagline = try snail.shape(allocator, &faces, tagline_text, .{});
    defer shaped_tagline.deinit();

    const sample_texts = [_][]const u8{ sample_hello, sample_arabic, sample_devanagari, sample_thai, sample_emoji };
    var shaped_samples: [sample_texts.len]snail.ShapedText = undefined;
    var shaped_count: usize = 0;
    defer for (shaped_samples[0..shaped_count]) |*s| s.deinit();
    for (sample_texts) |text| {
        shaped_samples[shaped_count] = try snail.shape(allocator, &faces, text, .{});
        shaped_count += 1;
    }
    var shaped_sep = try snail.shape(allocator, &faces, " \xc2\xb7 ", .{});
    defer shaped_sep.deinit();

    const pool = try snail.PagePool.init(allocator, .{
        .max_layers = 8,
        .curve_words_per_page = 1 << 17,
        .band_words_per_page = 1 << 14,
    });
    errdefer pool.deinit();

    var scratch_arena = std.heap.ArenaAllocator.init(allocator);
    defer scratch_arena.deinit();

    var owned_curves: std.ArrayList(snail.GlyphCurves) = .empty;
    defer {
        for (owned_curves.items) |*c| c.deinit();
        owned_curves.deinit(allocator);
    }
    var text_entries: std.ArrayList(snail.AtlasEntry) = .empty;
    defer text_entries.deinit(allocator);

    for (shaped_tagline.glyphs) |g| {
        const fid = g.font_id;
        const key = snail.record_key.unhintedGlyph(fid, g.glyph_id);
        if (containsKey(text_entries.items, key)) continue;
        const curves = try fonts[fid].extractCurves(allocator, scratch_arena.allocator(), g.glyph_id);
        _ = scratch_arena.reset(.retain_capacity);
        try owned_curves.append(allocator, curves);
        try text_entries.append(allocator, .{ .key = key, .curves = owned_curves.items[owned_curves.items.len - 1] });
    }
    const sample_runs = [_]*const snail.ShapedText{
        &shaped_samples[0], &shaped_samples[1], &shaped_samples[2],
        &shaped_samples[3], &shaped_samples[4], &shaped_sep,
    };
    for (sample_runs) |shaped_ptr| {
        for (shaped_ptr.glyphs) |g| {
            const fid = g.font_id;
            if (fid >= fonts.len) continue;
            try ensureGlyphOrColrLayers(allocator, &scratch_arena, fonts[fid], fid, g.glyph_id, &owned_curves, &text_entries);
        }
    }

    var path_curves_owned: std.ArrayList(snail.GlyphCurves) = .empty;
    defer {
        for (path_curves_owned.items) |*c| c.deinit();
        path_curves_owned.deinit(allocator);
    }
    var path_entries: std.ArrayList(snail.AtlasEntry) = .empty;
    defer path_entries.deinit(allocator);
    var path_shapes: std.ArrayList(snail.Shape) = .empty;
    defer path_shapes.deinit(allocator);
    var extra_layer_storage: std.ArrayList([]snail.AtlasLayer) = .empty;
    defer {
        for (extra_layer_storage.items) |s| allocator.free(s);
        extra_layer_storage.deinit(allocator);
    }
    var next_path_id: u32 = 0;

    const card_rect = snail.Rect{
        .x = 12,
        .y = 12,
        .w = @as(f32, @floatFromInt(width)) - 24,
        .h = @as(f32, @floatFromInt(height)) - 24,
    };

    // Card fill (white rounded rect), authored in a unit frame and placed
    // uniformly so its corners stay crisp at the card's large screen offset.
    const card_place = demo_support.placeRectUniform(card_rect);
    {
        var p = try demo_support.unitRoundedRectPathFor(allocator, card_rect, 12.0);
        defer p.deinit();
        var prepared = try p.prepare(allocator);
        defer prepared.deinit();
        try path_curves_owned.append(allocator, try prepared.fillCurves(allocator, allocator));
        const key = snail.record_key.RecordKey{ .namespace = snail.record_key.ns.path_fill, .a = next_path_id };
        next_path_id += 1;
        try path_entries.append(allocator, .{
            .key = key,
            .curves = path_curves_owned.items[path_curves_owned.items.len - 1],
            .paint = .{ .solid = .{ 1.0, 1.0, 1.0, 1.0 } },
        });
        try path_shapes.append(allocator, .{ .key = key, .local_transform = prepared.placedBy(card_place), .local_color = .{ 1, 1, 1, 1 } });
    }
    // Card stroke.
    {
        var p = try demo_support.unitRoundedRectPathFor(allocator, card_rect, 12.0);
        defer p.deinit();
        var prepared = try p.prepare(allocator);
        defer prepared.deinit();
        const stroke = snail.StrokeStyle{
            .paint = .{ .solid = .{ 0.78, 0.82, 0.88, 1.0 } },
            .width = demo_support.unitStrokeWidth(card_rect, 1.5),
        };
        try path_curves_owned.append(allocator, try prepared.strokeCurves(allocator, allocator, stroke));
        const key = snail.record_key.RecordKey{ .namespace = snail.record_key.ns.path_stroke, .a = next_path_id };
        next_path_id += 1;
        try path_entries.append(allocator, .{
            .key = key,
            .curves = path_curves_owned.items[path_curves_owned.items.len - 1],
            .paint = .{ .solid = .{ 0.78, 0.82, 0.88, 1.0 } },
        });
        try path_shapes.append(allocator, .{ .key = key, .local_transform = prepared.placedBy(card_place), .local_color = .{ 1, 1, 1, 1 } });
    }
    // Conic-gradient swatch (bottom-left) — exercises the conic paint through
    // the shared scene so the CPU/GL backend-compare covers it.
    {
        const rect = snail.Rect{ .x = 18, .y = @as(f32, @floatFromInt(height)) - 46, .w = 32, .h = 32 };
        var p = try demo_support.unitEllipsePath(allocator);
        defer p.deinit();
        var prepared = try p.prepare(allocator);
        defer prepared.deinit();
        try path_curves_owned.append(allocator, try prepared.fillCurves(allocator, allocator));
        const key = snail.record_key.RecordKey{ .namespace = snail.record_key.ns.path_fill, .a = next_path_id };
        next_path_id += 1;
        const paint = snail.Paint{ .conic_gradient = .{
            .center = .{ .x = 0.5, .y = 0.5 },
            .start_color = .{ 0.95, 0.75, 0.25, 1.0 },
            .end_color = .{ 0.30, 0.45, 0.85, 1.0 },
        } };
        try path_entries.append(allocator, .{
            .key = key,
            .curves = path_curves_owned.items[path_curves_owned.items.len - 1],
            .paint = prepared.paintForDesign(paint),
        });
        try path_shapes.append(allocator, .{ .key = key, .local_transform = prepared.placedBy(demo_support.placeRect(rect)), .local_color = .{ 1, 1, 1, 1 } });
    }
    // Vector snail.
    {
        const snail_stage = snail.Rect{
            .x = @as(f32, @floatFromInt(width)) - 154.0,
            .y = 12.0,
            .w = 140.0,
            .h = 122.0,
        };
        const snail_builder = banner_snail.Builder{
            .allocator = allocator,
            .scratch_arena = &scratch_arena,
            .owned_curves = &path_curves_owned,
            .entries = &path_entries,
            .shapes = &path_shapes,
            .extra_layer_storage = &extra_layer_storage,
            .next_id = &next_path_id,
        };
        try banner_snail.addVectorSnail(snail_builder, snail_stage);
    }

    // Text layout constants.
    const left_pad: f32 = 24;
    const wordmark_baseline: f32 = 76;
    const wordmark_em: f32 = 52;
    const tagline_baseline: f32 = wordmark_baseline + 22;
    const tagline_em: f32 = 13;
    const tagline_color = [4]f32{ 0.42, 0.46, 0.52, 1.0 };

    // Wordmark glyphs with per-glyph gradients.
    const wordmark_world_gradient = snail.LinearGradient{
        .start = .{ .x = left_pad, .y = wordmark_baseline - wordmark_em },
        .end = .{ .x = left_pad + 135, .y = wordmark_baseline },
        .start_color = .{ 0.08, 0.30, 0.72, 1.0 },
        .end_color = .{ 0.10, 0.10, 0.14, 1.0 },
    };
    for (shaped_wordmark.glyphs) |g| {
        const fid = g.font_id;
        if (fid >= fonts.len) continue;
        const pen_x = left_pad + wordmark_em * g.x_offset;
        const pen_y = wordmark_baseline + wordmark_em * g.y_offset;
        const transform = snail.Transform2D{
            .xx = wordmark_em,
            .xy = 0,
            .tx = pen_x,
            .yx = 0,
            .yy = -wordmark_em,
            .ty = pen_y,
        };
        const local_paint = snail.mapPaintToLocal(.{ .linear_gradient = wordmark_world_gradient }, transform) orelse continue;
        const curves = try fonts[fid].extractCurves(allocator, scratch_arena.allocator(), g.glyph_id);
        _ = scratch_arena.reset(.retain_capacity);
        try path_curves_owned.append(allocator, curves);
        const key = snail.record_key.RecordKey{ .namespace = snail.record_key.ns.path_fill, .a = next_path_id };
        next_path_id += 1;
        try path_entries.append(allocator, .{
            .key = key,
            .curves = path_curves_owned.items[path_curves_owned.items.len - 1],
            .paint = local_paint,
        });
        try path_shapes.append(allocator, .{
            .key = key,
            .local_transform = transform,
            .local_color = .{ 1, 1, 1, 1 },
        });
    }

    var paths_atlas = try snail.Atlas.from(allocator, pool, path_entries.items);
    errdefer paths_atlas.deinit();
    var paths_picture = try demo_support.Picture.from(allocator, path_shapes.items);
    errdefer paths_picture.deinit();

    // When hinting is requested, push hinted-glyph entries for the tagline
    // (Latin only) under `ttHintedGlyph` keys before sealing the atlas.
    const hinted_tagline_active = if (tt_hint_opts.hinter) |hinter_ptr| blk: {
        const ppem_26_6: u32 = @intFromFloat(@round(tt_hint_opts.hint_ppem_px * 64.0));
        const hint_ppem = snail.TtHintPpem.uniform(ppem_26_6);
        const hint_fid: u32 = tt_hint_opts.hint_face_index;
        // Run fpgm/prep once for this ppem, then hint each glyph off it.
        var prepared = hinter_ptr.prepare(hint_ppem) catch |err| switch (err) {
            error.NoHinting => break :blk false,
            else => return err,
        };
        defer prepared.deinit();
        for (shaped_tagline.glyphs) |g| {
            if (g.face_index != hint_fid) continue;
            const key = snail.record_key.ttHintedGlyph(hint_fid, g.glyph_id, ppem_26_6);
            if (containsKey(text_entries.items, key)) continue;
            const curves = hinter_ptr.hintGlyph(allocator, allocator, &prepared, g.glyph_id) catch |err| switch (err) {
                error.NoHinting, error.GlyphTopologyChanged => continue,
                else => return err,
            };
            try owned_curves.append(allocator, curves);
            try text_entries.append(allocator, .{ .key = key, .curves = owned_curves.items[owned_curves.items.len - 1] });
        }
        break :blk true;
    } else false;

    var text_atlas = try snail.Atlas.from(allocator, pool, text_entries.items);
    errdefer text_atlas.deinit();

    // Tagline + multi-script sample row.
    var tagline_pic = if (hinted_tagline_active)
        try demo_support.placeRun(allocator, &shaped_tagline, null, .{
            .baseline = .{ .x = left_pad, .y = tagline_baseline },
            .em = tt_hint_opts.hint_ppem_px,
            .color = tagline_color,
            .mode = .{ .tt_hint = .{ .ppem_26_6 = @intFromFloat(@round(tt_hint_opts.hint_ppem_px * 64.0)) } },
        })
    else
        try demo_support.placeRun(allocator, &shaped_tagline, &faces, .{
            .baseline = .{ .x = left_pad, .y = tagline_baseline },
            .em = tagline_em,
            .color = tagline_color,
        });
    defer tagline_pic.deinit();

    const sample_baseline: f32 = 196.0;
    const sample_em: f32 = 16.0;
    const sample_color = [4]f32{ 0.15, 0.18, 0.24, 1.0 };
    const sep_color = [4]f32{ 0.65, 0.70, 0.78, 1.0 };
    var sample_pics: std.ArrayList(demo_support.Picture) = .empty;
    defer {
        for (sample_pics.items) |*p| p.deinit();
        sample_pics.deinit(allocator);
    }

    var sx = left_pad;
    for (shaped_samples[0..shaped_count], 0..) |shaped, sample_idx| {
        if (sample_idx != 0) {
            try sample_pics.append(allocator, try demo_support.placeRun(allocator, &shaped_sep, &faces, .{
                .baseline = .{ .x = sx, .y = sample_baseline },
                .em = sample_em,
                .color = sep_color,
                .colr = true,
            }));
            sx += shaped_sep.advanceX() * sample_em;
        }
        try sample_pics.append(allocator, try demo_support.placeRun(allocator, &shaped, &faces, .{
            .baseline = .{ .x = sx, .y = sample_baseline },
            .em = sample_em,
            .color = sample_color,
            .colr = true,
        }));
        sx += shaped.advanceX() * sample_em;
    }

    var combine_inputs: std.ArrayList(*const demo_support.Picture) = .empty;
    defer combine_inputs.deinit(allocator);
    try combine_inputs.append(allocator, &tagline_pic);
    for (sample_pics.items) |*p| try combine_inputs.append(allocator, p);

    var text_picture = try demo_support.Picture.concat(allocator, combine_inputs.items);
    errdefer text_picture.deinit();

    return .{
        .allocator = allocator,
        .pool = pool,
        .paths_atlas = paths_atlas,
        .text_atlas = text_atlas,
        .paths_picture = paths_picture,
        .text_picture = text_picture,
    };
}

fn containsKey(entries: []const snail.AtlasEntry, key: snail.record_key.RecordKey) bool {
    for (entries) |e| if (e.key.eql(key)) return true;
    return false;
}

fn ensureGlyphOrColrLayers(
    allocator: Allocator,
    scratch_arena: *std.heap.ArenaAllocator,
    font: *snail.Font,
    fid: u32,
    glyph_id: u16,
    owned_curves: *std.ArrayList(snail.GlyphCurves),
    entries: *std.ArrayList(snail.AtlasEntry),
) !void {
    var iter = font.colrLayers(glyph_id);
    if (iter.count() > 0) {
        while (iter.next()) |layer| {
            const key = snail.record_key.unhintedGlyph(fid, layer.glyph_id);
            if (containsKey(entries.items, key)) continue;
            const curves = try font.extractCurves(allocator, scratch_arena.allocator(), layer.glyph_id);
            _ = scratch_arena.reset(.retain_capacity);
            try owned_curves.append(allocator, curves);
            try entries.append(allocator, .{ .key = key, .curves = owned_curves.items[owned_curves.items.len - 1] });
        }
        return;
    }
    const key = snail.record_key.unhintedGlyph(fid, glyph_id);
    if (containsKey(entries.items, key)) return;
    const curves = try font.extractCurves(allocator, scratch_arena.allocator(), glyph_id);
    _ = scratch_arena.reset(.retain_capacity);
    try owned_curves.append(allocator, curves);
    try entries.append(allocator, .{ .key = key, .curves = owned_curves.items[owned_curves.items.len - 1] });
}
