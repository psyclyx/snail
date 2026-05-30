//! Minimal screenshot demo that goes through the new snail API end-to-end:
//! shaped text (`shapedRunPicture`) + paint records + path primitives via
//! direct `pathToCurves` / `strokeToCurves` composition + CPU draw.
//!
//! Not a replacement for the legacy `screenshot.zig` demo yet: the COLR /
//! SVG emoji and multi-script fallback are dropped, and the vector-snail
//! `addVectorSnail` content is reduced to a placeholder shell ellipse.
//! Output goes to `zig-out/demo-screenshot-new.tga`.

const std = @import("std");
const snail = @import("snail");
const screenshot = @import("support").screenshot;
const assets_data = @import("assets");
const banner_snail_new = @import("banner_snail_new.zig");

const W: u32 = 400;
const H: u32 = 240;
const STRIDE: u32 = W * 4;
const OUT_PATH = "zig-out/demo-screenshot-new.tga";

pub fn main() !void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    const pixels = try allocator.alloc(u8, H * STRIDE);
    defer allocator.free(pixels);
    const bg = [4]u8{ 245, 246, 249, 255 };
    var i: usize = 0;
    while (i + 3 < pixels.len) : (i += 4) {
        pixels[i + 0] = bg[0];
        pixels[i + 1] = bg[1];
        pixels[i + 2] = bg[2];
        pixels[i + 3] = bg[3];
    }

    // -- Shape text via the existing TextAtlas (no new-API shaping yet).
    var text_atlas = try snail.TextAtlas.init(allocator, &.{
        .{ .data = assets_data.noto_sans_regular },
        .{ .data = assets_data.noto_sans_bold, .weight = .bold },
        .{ .data = assets_data.noto_sans_arabic, .fallback = true },
        .{ .data = assets_data.noto_sans_devanagari, .fallback = true },
        .{ .data = assets_data.noto_sans_thai, .fallback = true },
        .{ .data = assets_data.twemoji_mozilla, .fallback = true },
    });
    defer text_atlas.deinit();

    const wordmark_text = "snail";
    const tagline_text = "GPU text and vector rendering";
    const sample_hello = "Hello";
    const sample_arabic = "\xd9\x85\xd8\xb1\xd8\xad\xd8\xa8\xd8\xa7"; // مرحبا
    const sample_devanagari = "\xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87"; // नमस्ते
    const sample_thai = "\xe0\xb8\xaa\xe0\xb8\xa7\xe0\xb8\xb1\xe0\xb8\xaa\xe0\xb8\x94\xe0\xb8\xb5"; // สวัสดี
    const sample_emoji = "\xe2\x9c\xa8\xf0\x9f\x8c\x8d"; // ✨🌍

    inline for (.{
        .{ .weight = .bold, .text = wordmark_text },
        .{ .weight = .regular, .text = tagline_text },
        .{ .weight = .regular, .text = sample_hello },
        .{ .weight = .regular, .text = sample_arabic },
        .{ .weight = .regular, .text = sample_devanagari },
        .{ .weight = .regular, .text = sample_thai },
        .{ .weight = .regular, .text = sample_emoji },
        .{ .weight = .regular, .text = " \xc2\xb7 " }, // separator
    }) |entry| {
        const style: snail.FontStyle = .{ .weight = entry.weight };
        if (try text_atlas.ensureText(style, entry.text)) |next| {
            text_atlas.deinit();
            text_atlas = next;
        }
    }

    var shaped_wordmark = try text_atlas.shapeText(allocator, .{ .weight = .bold }, wordmark_text);
    defer shaped_wordmark.deinit();
    var shaped_tagline = try text_atlas.shapeText(allocator, .{}, tagline_text);
    defer shaped_tagline.deinit();

    // Shape each multi-script sample.
    const sample_texts = [_][]const u8{ sample_hello, sample_arabic, sample_devanagari, sample_thai, sample_emoji };
    var shaped_samples: [sample_texts.len]snail.ShapedText = undefined;
    var shaped_count: usize = 0;
    defer for (shaped_samples[0..shaped_count]) |*s| s.deinit();
    for (sample_texts) |text| {
        shaped_samples[shaped_count] = try text_atlas.shapeText(allocator, .{}, text);
        shaped_count += 1;
    }
    var shaped_sep = try text_atlas.shapeText(allocator, .{}, " \xc2\xb7 ");
    defer shaped_sep.deinit();

    var pool = try snail.PagePool.init(allocator, .{
        .max_layers = 8,
        .curve_words_per_page = 1 << 17,
        .band_words_per_page = 1 << 14,
    });
    defer pool.deinit();

    var font_regular = try snail.Font.init(assets_data.noto_sans_regular);
    defer font_regular.deinit();
    var font_bold = try snail.Font.init(assets_data.noto_sans_bold);
    defer font_bold.deinit();
    var font_arabic = try snail.Font.init(assets_data.noto_sans_arabic);
    defer font_arabic.deinit();
    var font_devanagari = try snail.Font.init(assets_data.noto_sans_devanagari);
    defer font_devanagari.deinit();
    var font_thai = try snail.Font.init(assets_data.noto_sans_thai);
    defer font_thai.deinit();
    var font_emoji = try snail.Font.init(assets_data.twemoji_mozilla);
    defer font_emoji.deinit();
    var fonts = [_]*snail.Font{ &font_regular, &font_bold, &font_arabic, &font_devanagari, &font_thai, &font_emoji };
    const face_to_font_id = [_]u32{ 0, 1, 2, 3, 4, 5 };
    const colr_fonts = [_]*const snail.Font{ &font_regular, &font_bold, &font_arabic, &font_devanagari, &font_thai, &font_emoji };

    var glyph_cache = snail.font.GlyphCache.init(allocator);
    defer glyph_cache.deinit();

    var owned_curves: std.ArrayList(snail.GlyphCurves) = .empty;
    defer {
        for (owned_curves.items) |*c| c.deinit();
        owned_curves.deinit(allocator);
    }
    var text_entries: std.ArrayList(snail.AtlasEntry) = .empty;
    defer text_entries.deinit(allocator);

    for (shaped_tagline.glyphs) |g| {
        const fid: u32 = g.face_index;
        const key = snail.recordKey.unhintedGlyph(fid, g.glyph_id);
        if (containsKey(text_entries.items, key)) continue;
        const curves = try fonts[fid].extractCurves(allocator, &glyph_cache, g.glyph_id);
        try owned_curves.append(allocator, curves);
        try text_entries.append(allocator, .{ .key = key, .curves = owned_curves.items[owned_curves.items.len - 1] });
    }
    // Multi-script sample + separator glyphs. COLR base glyphs (Twemoji)
    // expand: extract one entry per layer glyph, not the base.
    const sample_runs = [_]*const snail.ShapedText{
        &shaped_samples[0], &shaped_samples[1], &shaped_samples[2],
        &shaped_samples[3], &shaped_samples[4], &shaped_sep,
    };
    for (sample_runs) |shaped_ptr| {
        for (shaped_ptr.glyphs) |g| {
            const fid: u32 = g.face_index;
            if (fid >= fonts.len) continue;
            try ensureGlyphOrColrLayers(
                allocator,
                &glyph_cache,
                fonts[fid],
                fid,
                g.glyph_id,
                &owned_curves,
                &text_entries,
            );
        }
    }

    // -- Path content: build geometry directly with the Path API, convert
    // via `pathToCurves` / `strokeToCurves`, and assemble Atlas entries
    // and Shapes inline. No helper builder layer.
    var path_curves_owned: std.ArrayList(snail.GlyphCurves) = .empty;
    defer {
        for (path_curves_owned.items) |*c| c.deinit();
        path_curves_owned.deinit(allocator);
    }
    var path_entries: std.ArrayList(snail.AtlasEntry) = .empty;
    defer path_entries.deinit(allocator);
    var path_shapes: std.ArrayList(snail.Shape) = .empty;
    defer path_shapes.deinit(allocator);
    var next_path_id: u32 = 0;

    const card_rect = snail.Rect{
        .x = 12,
        .y = 12,
        .w = @as(f32, @floatFromInt(W)) - 24,
        .h = @as(f32, @floatFromInt(H)) - 24,
    };

    // Card fill (white rounded rect).
    {
        var p = snail.paths.Path.init(allocator);
        defer p.deinit();
        try p.addRoundedRect(card_rect, 12.0);
        try path_curves_owned.append(allocator, try snail.paths.pathToCurves(allocator, &p));
        const key = snail.RecordKey{ .namespace = snail.ns.path_fill, .a = next_path_id };
        next_path_id += 1;
        try path_entries.append(allocator, .{
            .key = key,
            .curves = path_curves_owned.items[path_curves_owned.items.len - 1],
            .paint = .{ .solid = .{ 1.0, 1.0, 1.0, 1.0 } },
        });
        try path_shapes.append(allocator, .{ .key = key, .local_transform = .identity, .local_color = .{ 1, 1, 1, 1 } });
    }
    // Card stroke (light gray border).
    {
        var p = snail.paths.Path.init(allocator);
        defer p.deinit();
        try p.addRoundedRect(card_rect, 12.0);
        try path_curves_owned.append(allocator, try snail.paths.strokeToCurves(allocator, &p, .{
            .paint = .{ .solid = .{ 0.78, 0.82, 0.88, 1.0 } },
            .width = 1.5,
        }));
        const key = snail.RecordKey{ .namespace = snail.ns.path_stroke, .a = next_path_id };
        next_path_id += 1;
        try path_entries.append(allocator, .{
            .key = key,
            .curves = path_curves_owned.items[path_curves_owned.items.len - 1],
            .paint = .{ .solid = .{ 0.78, 0.82, 0.88, 1.0 } },
        });
        try path_shapes.append(allocator, .{ .key = key, .local_transform = .identity, .local_color = .{ 1, 1, 1, 1 } });
    }
    // Full vector snail in the top-right corner (mirrors legacy demo).
    {
        const snail_stage = snail.Rect{
            .x = @as(f32, @floatFromInt(W)) - 154.0,
            .y = 12.0,
            .w = 140.0,
            .h = 122.0,
        };
        const snail_builder = banner_snail_new.Builder{
            .allocator = allocator,
            .owned_curves = &path_curves_owned,
            .entries = &path_entries,
            .shapes = &path_shapes,
            .next_id = &next_path_id,
        };
        try banner_snail_new.addVectorSnail(snail_builder, snail_stage);
    }

    // -- Text layout constants (used by wordmark prepass and shaped runs).
    const left_pad: f32 = 24;
    const wordmark_baseline: f32 = 76;
    const wordmark_em: f32 = 52;
    const tagline_baseline: f32 = wordmark_baseline + 22;
    const tagline_em: f32 = 13;
    const tagline_color = [4]f32{ 0.42, 0.46, 0.52, 1.0 };

    // Wordmark glyphs need per-instance paints so the linear gradient
    // spans the entire word in world coordinates (not per glyph). Build
    // them as path_fill entries with mapToLocal'd gradients per glyph,
    // appended to path_entries / path_shapes so they share the same
    // paint-record format the path renderer already handles.
    const wordmark_world_gradient = snail.LinearGradient{
        .start = .{ .x = left_pad, .y = wordmark_baseline - wordmark_em },
        .end = .{ .x = left_pad + 135, .y = wordmark_baseline },
        .start_color = .{ 0.08, 0.30, 0.72, 1.0 },
        .end_color = .{ 0.10, 0.10, 0.14, 1.0 },
    };
    for (shaped_wordmark.glyphs) |g| {
        const fid: u32 = g.face_index;
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
        const curves = try fonts[fid].extractCurves(allocator, &glyph_cache, g.glyph_id);
        try path_curves_owned.append(allocator, curves);
        const key = snail.RecordKey{ .namespace = snail.ns.path_fill, .a = next_path_id };
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
    defer paths_atlas.deinit();
    var paths_picture = try snail.Picture.from(allocator, path_shapes.items);
    defer paths_picture.deinit();

    var text_atlas_new = try snail.Atlas.from(allocator, pool, text_entries.items);
    defer text_atlas_new.deinit();

    // One cache serves both atlases through the same pool; bindings
    // disambiguate via their `generation` slot.
    var cache = try snail.CpuPreparedPages.init(allocator, pool);
    defer cache.deinit();
    const paths_binding = try cache.upload(&paths_atlas);
    const text_binding = try cache.upload(&text_atlas_new);

    var tagline_pic = try snail.shapedRunPicture(allocator, &shaped_tagline, .{
        .baseline = .{ .x = left_pad, .y = tagline_baseline },
        .em = tagline_em,
        .color = tagline_color,
        .face_to_font_id = &face_to_font_id,
    });
    defer tagline_pic.deinit();

    // Multi-script sample row. Lay each sample left-to-right with a
    // middle-dot separator between them, accumulating x_advance to advance
    // the pen.
    const sample_baseline: f32 = 196.0;
    const sample_em: f32 = 16.0;
    const sample_color = [4]f32{ 0.15, 0.18, 0.24, 1.0 };
    const sep_color = [4]f32{ 0.65, 0.70, 0.78, 1.0 };
    var sample_pics: std.ArrayList(snail.Picture) = .empty;
    defer {
        for (sample_pics.items) |*p| p.deinit();
        sample_pics.deinit(allocator);
    }

    var sx = left_pad;
    for (shaped_samples[0..shaped_count], 0..) |shaped, sample_idx| {
        if (sample_idx != 0) {
            try sample_pics.append(allocator, try snail.shapedRunPicture(allocator, &shaped_sep, .{
                .baseline = .{ .x = sx, .y = sample_baseline },
                .em = sample_em,
                .color = sep_color,
                .face_to_font_id = &face_to_font_id,
                .colr_fonts = &colr_fonts,
            }));
            sx += shaped_sep.advanceX() * sample_em;
        }
        try sample_pics.append(allocator, try snail.shapedRunPicture(allocator, &shaped, .{
            .baseline = .{ .x = sx, .y = sample_baseline },
            .em = sample_em,
            .color = sample_color,
            .face_to_font_id = &face_to_font_id,
            .colr_fonts = &colr_fonts,
        }));
        sx += shaped.advanceX() * sample_em;
    }

    var combine_inputs: std.ArrayList(*const snail.Picture) = .empty;
    defer combine_inputs.deinit(allocator);
    try combine_inputs.append(allocator, &tagline_pic);
    for (sample_pics.items) |*p| try combine_inputs.append(allocator, p);

    var text_pic = try snail.Picture.concat(allocator, combine_inputs.items);
    defer text_pic.deinit();

    // -- Emit + draw. Paths first (under), then text (over).
    const words = try allocator.alloc(u32, snail.emit.wordBudget(&paths_picture, 0) + snail.emit.wordBudget(&text_pic, 0));
    defer allocator.free(words);
    const segs = try allocator.alloc(snail.DrawSegment, 4);
    defer allocator.free(segs);

    var wlen: usize = 0;
    var slen: usize = 0;
    _ = try snail.emit.emit(words, segs, &wlen, &slen, paths_binding, &paths_atlas, &paths_picture, .identity, .{ 1, 1, 1, 1 });
    _ = try snail.emit.emit(words, segs, &wlen, &slen, text_binding, &text_atlas_new, &text_pic, .identity, .{ 1, 1, 1, 1 });

    var renderer = snail.CpuRenderer.init(pixels.ptr, W, H, STRIDE);
    const wf: f32 = @floatFromInt(W);
    const hf: f32 = @floatFromInt(H);
    const state = snail.DrawState{
        .surface = .{ .pixel_width = wf, .pixel_height = hf, .encoding = .srgb },
        .raster = .{ .subpixel_order = .none, .coverage_transfer = .{ .exponent = 1.0 } },
        .mvp = snail.Mat4.ortho(0, wf, hf, 0, -1, 1),
    };
    try snail.drawCpu(&renderer, state, .{ .words = words[0..wlen], .segments = segs[0..slen] }, &.{&cache});

    // CPU buffer is top-down; writeTga assumes GL-style bottom-up.
    flipRowsInPlace(pixels);

    _ = std.c.mkdir("zig-out", 0o755);
    try screenshot.writeTga(OUT_PATH, pixels, W, H);
    std.debug.print("wrote {s}\n", .{OUT_PATH});
}

fn flipRowsInPlace(pixels: []u8) void {
    var tmp: [W * 4]u8 = undefined;
    var y: usize = 0;
    while (y < H / 2) : (y += 1) {
        const top = y * W * 4;
        const bottom = (@as(usize, H) - 1 - y) * W * 4;
        @memcpy(&tmp, pixels[top..][0 .. W * 4]);
        @memcpy(pixels[top..][0 .. W * 4], pixels[bottom..][0 .. W * 4]);
        @memcpy(pixels[bottom..][0 .. W * 4], &tmp);
    }
}

fn containsKey(entries: []const snail.AtlasEntry, key: snail.RecordKey) bool {
    for (entries) |e| if (e.key.eql(key)) return true;
    return false;
}

fn ensureGlyphOrColrLayers(
    allocator: std.mem.Allocator,
    cache: *snail.font.GlyphCache,
    font: *snail.Font,
    fid: u32,
    glyph_id: u16,
    owned_curves: *std.ArrayList(snail.GlyphCurves),
    entries: *std.ArrayList(snail.AtlasEntry),
) !void {
    var iter = font.colrLayers(glyph_id);
    if (iter.count() > 0) {
        while (iter.next()) |layer| {
            const key = snail.recordKey.unhintedGlyph(fid, layer.glyph_id);
            if (containsKey(entries.items, key)) continue;
            const curves = try font.extractCurves(allocator, cache, layer.glyph_id);
            try owned_curves.append(allocator, curves);
            try entries.append(allocator, .{ .key = key, .curves = owned_curves.items[owned_curves.items.len - 1] });
        }
        return;
    }
    const key = snail.recordKey.unhintedGlyph(fid, glyph_id);
    if (containsKey(entries.items, key)) return;
    const curves = try font.extractCurves(allocator, cache, glyph_id);
    try owned_curves.append(allocator, curves);
    try entries.append(allocator, .{ .key = key, .curves = owned_curves.items[owned_curves.items.len - 1] });
}
